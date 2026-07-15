import XCTest
@testable import ParamClaudeBar

final class ClaudeCodeSessionMonitorTests: XCTestCase {
    func testParseLatestAssistantSumsEffectiveTokens() {
        let line = """
        {"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"input_tokens":2,"cache_creation_input_tokens":1757,"cache_read_input_tokens":602521,"output_tokens":290}}}
        """
        let result = ClaudeCodeSessionMonitor.parseLatestAssistant(lines: [line])
        XCTAssertEqual(result?.model, "claude-opus-4-8")
        XCTAssertEqual(result?.tokens, 2 + 1757 + 602521)
    }

    func testParseSkipsNonAssistantAndPicksMostRecent() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":10,"cache_read_input_tokens":90}}}"#,
            #"{"type":"mode","mode":"normal"}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-4-8","usage":{"input_tokens":5,"cache_read_input_tokens":50000}}}"#
        ]
        let result = ClaudeCodeSessionMonitor.parseLatestAssistant(lines: lines)
        XCTAssertEqual(result?.model, "claude-opus-4-8")
        XCTAssertEqual(result?.tokens, 50005)
    }

    func testParseReturnsNilWhenNoAssistantUsage() {
        let lines = [
            #"{"type":"user","message":{"role":"user"}}"#,
            #"{"type":"assistant","message":{"model":"claude-opus-4-8"}}"#
        ]
        XCTAssertNil(ClaudeCodeSessionMonitor.parseLatestAssistant(lines: lines))
    }

    func testInferContextWindow() {
        XCTAssertEqual(ClaudeCodeSessionMonitor.inferContextWindow(effectiveTokens: 34_000), 200_000)
        XCTAssertEqual(ClaudeCodeSessionMonitor.inferContextWindow(effectiveTokens: 200_000), 200_000)
        XCTAssertEqual(ClaudeCodeSessionMonitor.inferContextWindow(effectiveTokens: 200_001), 1_000_000)
        XCTAssertEqual(ClaudeCodeSessionMonitor.inferContextWindow(effectiveTokens: 604_280), 1_000_000)
    }

    func testFriendlyModelName() {
        XCTAssertEqual(ClaudeCodeSessionMonitor.friendlyModelName("claude-opus-4-8"), "Opus 4.8")
        XCTAssertEqual(ClaudeCodeSessionMonitor.friendlyModelName("claude-opus-4-8[1m]"), "Opus 4.8")
        XCTAssertEqual(ClaudeCodeSessionMonitor.friendlyModelName("claude-sonnet-5"), "Sonnet 5")
        XCTAssertEqual(ClaudeCodeSessionMonitor.friendlyModelName("claude-fable-5"), "Fable 5")
        XCTAssertEqual(ClaudeCodeSessionMonitor.friendlyModelName("claude-haiku-4-5-20251001"), "Haiku 4.5")
    }

    func testSessionLabelAndPercent() {
        let session = ClaudeCodeSession(
            modelDisplayName: "Opus 4.8",
            contextTokens: 170_000,
            contextWindow: 1_000_000,
            lastActivity: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(session.modelLabel, "Opus 4.8 (1M context)")
        XCTAssertEqual(session.contextPercent, 17)

        let small = ClaudeCodeSession(
            modelDisplayName: "Sonnet 5",
            contextTokens: 100_000,
            contextWindow: 200_000,
            lastActivity: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(small.modelLabel, "Sonnet 5 (200K context)")
        XCTAssertEqual(small.contextPercent, 50)
    }

    func testReadTailDropsPartialFirstLine() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")

        let full = "AAAA\nBBBB\nCCCC\n"
        try full.data(using: .utf8)!.write(to: file)

        // maxBytes smaller than the file forces a mid-line start; the partial
        // leading fragment must be dropped.
        let lines = ClaudeCodeSessionMonitor.readTail(file, maxBytes: 7)
        XCTAssertFalse(lines.contains("AAAA"))
        XCTAssertEqual(lines.last, "CCCC")
    }
}
