import Foundation

/// A snapshot of the most recently active Claude Code session, derived from the
/// newest `*.jsonl` transcript under `~/.claude/projects`.
struct ClaudeCodeSession: Equatable {
    let modelDisplayName: String
    let contextTokens: Int
    let contextWindow: Int
    let lastActivity: Date

    /// 0–1 fraction of the context window currently in use.
    var contextFraction: Double {
        guard contextWindow > 0 else { return 0 }
        return min(1, Double(contextTokens) / Double(contextWindow))
    }

    var contextPercent: Int { Int((contextFraction * 100).rounded()) }

    /// e.g. "Opus 4.8 (1M context)".
    var modelLabel: String {
        let window = contextWindow >= 1_000_000
            ? "1M"
            : "\(contextWindow / 1000)K"
        return "\(modelDisplayName) (\(window) context)"
    }

    /// Seconds since the transcript was last written.
    func idleSeconds(now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(lastActivity)
    }

    /// True when the session hasn't been written to recently, so its context
    /// reading is stale rather than live.
    func isIdle(now: Date = Date(), threshold: TimeInterval = 300) -> Bool {
        idleSeconds(now: now) >= threshold
    }
}

/// Watches the Claude Code transcript directory and publishes a snapshot of the
/// currently active session (model + context-window utilisation).
///
/// There is no structured context-window field in the transcripts, so the
/// window is inferred: any session whose effective context has ever exceeded
/// the 200K tier must be running on the 1M-context model. This is correct once
/// a 1M session passes 200K (which happens quickly); a brand-new 1M session
/// below 200K is briefly reported against the 200K window.
@MainActor
final class ClaudeCodeSessionMonitor: ObservableObject {
    @Published private(set) var session: ClaudeCodeSession?

    private let projectsDir: URL
    private let tailBytes: Int
    private var timer: Timer?

    init(
        projectsDir: URL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        tailBytes: Int = 512 * 1024
    ) {
        self.projectsDir = projectsDir
        self.tailBytes = tailBytes
    }

    /// Recompute the snapshot off the main actor, then publish the result.
    func refresh() {
        let dir = projectsDir
        let tail = tailBytes
        Task.detached(priority: .utility) {
            let snapshot = ClaudeCodeSessionMonitor.computeSnapshot(projectsDir: dir, tailBytes: tail)
            await MainActor.run { [weak self] in
                self?.session = snapshot
            }
        }
    }

    /// Refresh now and keep refreshing on an interval so the menu-bar reading
    /// stays current even while the popover is closed. Reading only the last
    /// 512 KB of one file makes this cheap.
    func startBackgroundRefresh(interval: TimeInterval = 30) {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    // MARK: - Pure(ish) computation

    nonisolated static func computeSnapshot(
        projectsDir: URL,
        tailBytes: Int,
        defaults: UserDefaults = .standard
    ) -> ClaudeCodeSession? {
        guard let url = newestTranscript(in: projectsDir) else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        let lines = readTail(url, maxBytes: tailBytes)
        guard let parsed = parseLatestAssistant(lines: lines) else { return nil }

        // Infer the window from the *high-water mark* of this session, not the
        // current fill, so a session that once crossed 200K stays on the 1M
        // window even after a /compact drops it back down.
        let sessionId = url.deletingPathExtension().lastPathComponent
        let peak = persistedPeakTokens(sessionId: sessionId, current: parsed.tokens, defaults: defaults)
        let window = inferContextWindow(effectiveTokens: peak)
        return ClaudeCodeSession(
            modelDisplayName: friendlyModelName(parsed.model),
            contextTokens: parsed.tokens,
            contextWindow: window,
            lastActivity: modified
        )
    }

    /// Track and return the highest effective-token count ever seen for a
    /// session id, persisted across launches.
    nonisolated static func persistedPeakTokens(
        sessionId: String,
        current: Int,
        defaults: UserDefaults
    ) -> Int {
        let key = "ccSessionPeak.\(sessionId)"
        let stored = defaults.integer(forKey: key)
        let peak = max(stored, current)
        if peak != stored { defaults.set(peak, forKey: key) }
        return peak
    }

    /// Newest `*.jsonl` by modification date across every project directory.
    nonisolated static func newestTranscript(in projectsDir: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (URL, Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let date = values?.contentModificationDate else { continue }
            if newest == nil || date > newest!.1 {
                newest = (url, date)
            }
        }
        return newest?.0
    }

    /// Read only the last `maxBytes` of a file and return its complete lines.
    /// The first (possibly partial) line is dropped so we never parse a
    /// half-record straddling the read boundary.
    nonisolated static func readTail(_ url: URL, maxBytes: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        let trimmedHead = start > 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        if trimmedHead, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// Scan from the end for the last `assistant` record carrying usage and
    /// return its model id plus the effective context-token count.
    nonisolated static func parseLatestAssistant(lines: [String]) -> (model: String, tokens: Int)? {
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let model = message["model"] as? String,
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            let input = usage["input_tokens"] as? Int ?? 0
            let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            return (model, input + cacheCreate + cacheRead)
        }
        return nil
    }

    /// Standard tier that contains the given effective-token count.
    nonisolated static func inferContextWindow(effectiveTokens: Int) -> Int {
        effectiveTokens > 200_000 ? 1_000_000 : 200_000
    }

    /// Map a raw model id (e.g. "claude-opus-4-8[1m]") to a friendly name
    /// ("Opus 4.8"). Falls back to a title-cased best effort.
    nonisolated static func friendlyModelName(_ id: String) -> String {
        var base = id
        if let bracket = base.firstIndex(of: "[") {
            base = String(base[..<bracket])
        }
        base = base.replacingOccurrences(
            of: #"-\d{6,}$"#,
            with: "",
            options: .regularExpression
        )

        let known: [String: String] = [
            "claude-opus-4-8": "Opus 4.8",
            "claude-opus-4-7": "Opus 4.7",
            "claude-opus-4-6": "Opus 4.6",
            "claude-sonnet-5": "Sonnet 5",
            "claude-haiku-4-5": "Haiku 4.5",
            "claude-fable-5": "Fable 5"
        ]
        if let name = known[base] { return name }

        // Generic: "claude-opus-4-8" -> "Opus 4.8"
        let stripped = base.hasPrefix("claude-") ? String(base.dropFirst(7)) : base
        let parts = stripped.split(separator: "-")
        guard let family = parts.first else { return id }
        let version = parts.dropFirst().joined(separator: ".")
        let familyName = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? familyName : "\(familyName) \(version)"
    }
}
