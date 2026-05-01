# ParamClaudeBar — Product Spec

A native macOS menu bar app for monitoring Claude AI usage. Personal tool for Param Sharma, forked from [Blimp-Labs/claude-usage-bar](https://github.com/Blimp-Labs/claude-usage-bar) (BSD-2 license) and rebuilt for higher polish, better UX, and a foundation suitable for future feature growth.

This document is the source of truth. If something is unclear, default to **what a polished native macOS menu bar app would do**.

---

## 1. Goal

Build a Mac-native menu bar app that's noticeably better than `claude-usage-bar` and `Usage4Claude` in visual polish, information density, and at-a-glance usefulness. Single user, single machine (16" MacBook Pro M5 Pro, macOS 14+).

This is **Tier 1 — polish and UX**. No SQLite backfill, no heatmaps, no Apple Watch, no per-conversation attribution. Those are explicitly out of scope and may be added later.

---

## 2. Non-goals

- Cross-platform (Windows/Linux). Mac only.
- App Store distribution. Personal use only, ad-hoc signed.
- Multiple Claude accounts. Single account.
- Public open-source release. Private repo under `param123`.
- Paid Apple Developer cert. Ad-hoc only — first launch requires right-click → Open.
- Claude Code/CLI usage attribution. Just consumer subscription quotas (5h, 7d, Extra, 7d Opus, 7d Sonnet).

---

## 3. Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI + AppKit hybrid (SwiftUI for views, AppKit `NSStatusItem` for menu bar)
- **Charts:** Swift Charts (built-in, macOS 14+)
- **Persistence:** JSON files in `~/Library/Application Support/ParamClaudeBar/`
- **Auto-updates:** Sparkle 2.x via Swift Package Manager
- **Build system:** Swift Package Manager + Makefile (inherited from upstream)
- **Min OS:** macOS 14 (Sonoma)
- **Distribution:** Ad-hoc signed `.app` bundle, distributed via private GitHub Releases

---

## 4. Renaming work (Phase 0 — do this first, in one commit)

The fork keeps the upstream's name and bundle structure. All of it gets renamed before any feature work begins.

| Item | From | To |
| --- | --- | --- |
| Repo | `claude-usage-bar` | `ParamClaudeBar` (done on GitHub before clone) |
| Swift package name | `ClaudeUsageBar` | `ParamClaudeBar` |
| Source folder | `Sources/ClaudeUsageBar/` | `Sources/ParamClaudeBar/` |
| Main app file | `ClaudeUsageBarApp.swift` | `ParamClaudeBarApp.swift` |
| Bundle ID | upstream value | `com.paramsharma.paramclaudebar` |
| App display name | `ClaudeUsageBar` | `ParamClaudeBar` |
| Binary | `ClaudeUsageBar.app` | `ParamClaudeBar.app` |
| Data dir | `~/.config/claude-usage-bar/` | `~/Library/Application Support/ParamClaudeBar/` |
| Token file | `~/.config/claude-usage-bar/token` | `~/Library/Application Support/ParamClaudeBar/token` |
| History file | `~/.config/claude-usage-bar/history.json` | `~/Library/Application Support/ParamClaudeBar/history.json` |
| Makefile targets | reference old name | reference new name |
| README | upstream README | new ParamClaudeBar README (see §16) |

Update all references in: `Package.swift`, `Makefile`, all `.swift` files, `Resources/`, `.github/workflows/`, `scripts/`.

Commit message: `Rename to ParamClaudeBar`

---

## 5. Architecture

```
Sources/ParamClaudeBar/
├── ParamClaudeBarApp.swift          # App entry, menu bar setup
├── UsageService.swift               # OAuth, polling, API calls (kept)
├── UsageModel.swift                 # API response types (kept)
├── UsageHistoryModel.swift          # History data types (kept, extended)
├── UsageHistoryService.swift        # Persistence (kept, path updated)
├── UsageChartView.swift             # Chart (rewritten)
├── PopoverView.swift                # Popover UI (rewritten)
├── MenuBarIconRenderer.swift        # Icon drawing (rewritten — dual ring)
├── SettingsView.swift               # NEW — settings window
├── SettingsStore.swift              # NEW — UserDefaults wrapper
├── BurnRateCalculator.swift         # NEW — projection logic
├── NotificationManager.swift        # NEW — UNUserNotificationCenter wrapper
├── Theme.swift                      # NEW — colour tokens, system-adaptive
└── UpdaterController.swift          # NEW — Sparkle integration
```

---

## 6. Data layer

### 6.1 Polling

- Default interval: **60 seconds** (kept from upstream)
- Configurable: 30s / 60s / 2min / 5min
- Pause polling on system sleep, resume on wake (`NSWorkspace.willSleepNotification` / `didWakeNotification`)
- Manual refresh via popover ⌘R and right-click menu "Refresh now"

### 6.2 Storage

All in `~/Library/Application Support/ParamClaudeBar/`:

| File | Mode | Purpose |
| --- | --- | --- |
| `token` | 0600 | OAuth access token |
| `history.json` | 0644 | Usage history, 30-day retention |
| `settings.json` | 0644 | App preferences (mirrored from UserDefaults) |

Migration on first launch: if `~/.config/claude-usage-bar/` exists, copy contents to new location and leave the old dir alone (don't delete — Param can clean up manually).

### 6.3 History

Kept from upstream — append-only, in-memory buffer flushed every 5 minutes and on quit. 30-day retention. No schema change.

---

## 7. Menu bar widget

### 7.1 Display modes

User-selectable in Settings → Appearance:

1. **Icon only** — just the dual-ring icon
2. **Icon + percentage** — icon plus higher of (5h%, 7d%) as text. **Default.**
3. **Percentage only** — just the number

### 7.2 Icon design

Dual concentric rings, 22×22pt, rendered programmatically:

- **Outer ring (7-day):** thicker stroke, ~3px
- **Inner ring (5-hour):** thinner stroke, ~2px, inset by 4px
- **Background:** transparent
- **Empty state:** rings drawn at 10% opacity in current text colour
- **Filled state:** stroke proceeds clockwise from 12 o'clock, length = percentage
- 2× rendering for Retina, `NSImage.isTemplate = false`

### 7.3 Colour logic

| Range | 5h ring | 7d ring |
| --- | --- | --- |
| 0–60% | `systemGreen` | `systemBlue` |
| 60–85% | `systemOrange` | `systemPurple` |
| 85–100% | `systemRed` | `systemPink` |

Thresholds match notification triggers and are configurable (Settings → Notifications).

### 7.4 Burn-rate hint (optional, off by default)

Setting: "Show burn-rate hint in menu bar."

When on and burn rate suggests 5h limit will be hit before reset, append small text after the percentage: `→2h12m`. Off by default.

---

## 8. Popover

Width: 380pt. Height: dynamic, ~520pt with chart visible.

### 8.1 Header

- App name "ParamClaudeBar" small, top-left, secondary text
- Last-updated timestamp top-right ("Updated 12s ago"), live
- Refresh button (⌘R), top-right

### 8.2 Usage section

For each active limit type (5h, 7d, plus Extra/Opus/Sonnet if present):

- Limit name (e.g. "5-hour window") — body text
- Percentage as large numeral — title2, semibold
- Progress bar — full-width, 8pt tall, rounded, colour matches §7.3
- Reset time as **wall-clock** — "Resets at 22:50" (24-hour, UK locale)
- Sub-line: relative time as secondary — "in 2h 48m"

### 8.3 Insights row

Three cards horizontal, 12pt spacing:

| Card | Content | Example |
| --- | --- | --- |
| Burn rate | % consumed per hour, current 5h window | "12.4% / hr" |
| Projection | Hit time at current burn rate, or "On track" | "5h limit at 21:30" |
| Pace | Sparkline of last 60 minutes | (rendered) |

If burn rate ≤ 0 → show "Idle" or "Recovering."

### 8.4 Chart

- Time range buttons: `1h` `6h` `1d` `7d` `30d` — default `1d`
- Two lines: 5h (filled accent, semi-transparent area), 7d (line only, secondary)
- Smooth `.catmullRom` interpolation
- Subtle dashed gridlines, horizontal only at 25/50/75/100%
- Y-axis: 0–100%
- X-axis: HH:mm for 1h/6h/1d, dd MMM for 7d/30d
- Hover tooltip: timestamp + 5h% + 7d%
- Empty state: "Collecting usage history… check back in a few minutes"

### 8.5 Footer

- Left: Settings (⌘,)
- Centre: Sign-in status (green dot = authed)
- Right: Quit (⌘Q)

### 8.6 Visual treatment

- Background: `.regularMaterial` (vibrancy)
- Padding: 16pt outer, 20pt section spacing
- Animations: 0.2s easeInOut on data changes; `.contentTransition(.numericText())` for numbers
- Typography: SF Pro system default

---

## 9. Settings window

Standalone window, tabbed, ~520×400pt, not resizable.

### 9.1 General

- ☐ Launch at login (`SMAppService.mainApp.register()`)
- Refresh interval — segmented: 30s / 1min / 2min / 5min (default 1min)
- ☐ Show burn-rate hint in menu bar (default off)
- Menu bar display — segmented: Icon / Icon + % / % only (default Icon + %)

### 9.2 Appearance

- Theme — segmented: System / Light / Dark (default System)
- ☐ Use monochrome icon (default off)

### 9.3 Notifications

- ☐ Warning notification (default on) — slider 50–95%, default 75%
- ☐ Critical notification (default on) — slider 75–99%, default 90%
- ☐ Burn-rate alert (default on) — fires once per active window when projected to hit 5h limit within 30 minutes
- ☐ Reset notification (default off)
- "Test notification" button

### 9.4 Account

- Signed-in state with green dot
- "Sign out" button — clears token, returns to onboarding
- Last successful poll timestamp
- Polling status indicator

### 9.5 About

- App icon, name, version (from `Bundle.main`)
- "Check for updates" button (Sparkle)
- Link to private GitHub repo
- Credits: "Forked from Blimp-Labs/claude-usage-bar (BSD-2-Clause)"

---

## 10. Notifications

`UNUserNotificationCenter`. Permission requested in onboarding.

### 10.1 Triggers

| Trigger | Title | Body | Frequency |
| --- | --- | --- | --- |
| Warning | "Approaching limit" | "5-hour usage at 75%. Resets at 22:50." | Once per crossing per window |
| Critical | "Limit nearly reached" | "5-hour usage at 90%. Resets at 22:50." | Once per crossing per window |
| Burn-rate | "Limit imminent" | "At current pace you'll hit the 5-hour limit in ~22 minutes." | Once per active window |
| Reset | "Quota reset" | "Your 5-hour window has reset." | On reset detection |

### 10.2 Debouncing

State stored in `settings.json` under `notificationState`. Reset all `lastX5h` flags when 5h window resets (detected via reset time changing to a later value).

```json
{
  "lastWarning5h": "2026-05-01T17:30:00Z",
  "lastCritical5h": null,
  "lastBurnRate5h": null,
  "lastReset5h": "2026-05-01T17:00:00Z"
}
```

---

## 11. Burn-rate calculation

Pure function in `BurnRateCalculator.swift`:

```
Input: history points within current 5h (or 7d) window
Output: { burnRatePerHour: Double, projectedHitTime: Date? }
```

1. Take last 30 minutes of history (or all if fewer points).
2. Linear regression on (time, percentage). Slope → % per hour.
3. If slope ≤ 0 → projection = nil ("Idle" or "Recovering").
4. Else: `timeToHit = (100 - currentPercent) / slope`; `projectedHitTime = now + timeToHit`.
5. If `projectedHitTime > resetTime` → projection = nil ("On track").
6. Else → projection = `projectedHitTime`.

---

## 12. Sparkle auto-updates

### 12.1 Setup

- Add Sparkle 2.x via SPM
- Generate EdDSA keypair with Sparkle's `generate_keys` tool; private key stays on Param's MacBook, public key embedded in `Info.plist` as `SUPublicEDKey`
- `SUFeedURL` → committed `appcast.xml` in repo

For v1: ship `appcast.xml` inside the repo; generate manually after each release using `scripts/release.sh`. If private repo causes Sparkle auth issues, fall back to a public Gist hosting just the appcast (binaries stay on private releases).

### 12.2 Update flow

- Launch check after 60s delay
- Periodic check every 24h
- "Check for updates" in About tab triggers manual check
- Sparkle handles download + verify + install

### 12.3 Release script

`scripts/release.sh`:

1. Bump version in `Info.plist`
2. `make zip` to produce `ParamClaudeBar.zip`
3. Sign zip with `sign_update` (Sparkle tool) using EdDSA key → emit signature
4. Generate appcast entry: version, date, signature, URL
5. Append to `appcast.xml`
6. Commit, tag, push
7. Print instructions to manually upload zip to GitHub release

---

## 13. Onboarding (first launch)

Single-window flow, ~520×400pt:

1. **Welcome** — "ParamClaudeBar" + tagline. Continue.
2. **Sign in** — "Sign in with Claude" button. OAuth flow (kept from upstream). Paste-back UI.
3. **Notifications** — system permission prompt. Allow / Skip.
4. **Done** — "You're all set." Closes onboarding, popover opens.

Stored flag: `hasCompletedOnboarding` in `settings.json`.

---

## 14. Right-click menu

Native `NSMenu`:

- Refresh now (⌘R)
- ──
- Open ParamClaudeBar (⌘O)
- Settings… (⌘,)
- ──
- Check for updates…
- ──
- Quit ParamClaudeBar (⌘Q)

---

## 15. Build & distribution

### 15.1 Local build

```bash
make app            # builds .app bundle to .build/release/
make install        # copies to /Applications
make zip            # produces ParamClaudeBar.zip
```

### 15.2 Code signing

Ad-hoc only:

```bash
codesign --force --deep --sign - .build/release/ParamClaudeBar.app
```

(Already in upstream's Makefile — verify after rename.)

### 15.3 First-launch behaviour

User must right-click → Open the first time after each install/update. Document in README.

### 15.4 Launch at login

`SMAppService.mainApp` (macOS 13+). Toggle in Settings → General.

---

## 16. README

Replace upstream's README. Cover:

- Title + one-line description
- Screenshot placeholder
- Features (Tier 1 only, honest)
- Install: download from Releases → drag to /Applications → right-click → Open
- Sign-in flow
- Settings overview
- Data storage paths
- Build from source (Xcode 15+, Swift 5.9+, macOS 14+)
- Credits: "Forked from [Blimp-Labs/claude-usage-bar](https://github.com/Blimp-Labs/claude-usage-bar) under BSD-2-Clause."
- License: BSD-2-Clause (inherited)

Keep `LICENSE` from upstream — BSD-2 requires retention.

---

## 17. Acceptance criteria (Tier 1 done when…)

- [ ] All renaming complete; no `ClaudeUsageBar` or `claude-usage-bar` strings remain except legitimate upstream credit references.
- [ ] App builds cleanly with `make app`. Zero Swift compiler warnings.
- [ ] App launches, signs in, polls successfully, displays usage.
- [ ] Menu bar icon updates within 60s of usage change.
- [ ] All three menu bar display modes work and persist across relaunches.
- [ ] Popover opens on click, closes on outside click. Vibrancy renders.
- [ ] Chart shows data, all 5 time ranges work, hover tooltip works.
- [ ] Burn-rate calculation produces sensible numbers under manual history injection.
- [ ] All settings persist across relaunches.
- [ ] Notifications fire at correct thresholds. Debouncing prevents spam.
- [ ] Right-click menu works, all items functional.
- [ ] ⌘R, ⌘,, ⌘Q, ⌘O shortcuts work.
- [ ] Launch at login works.
- [ ] Sparkle reaches the appcast and reports version status correctly.
- [ ] Light + dark mode both polished. No contrast failures.
- [ ] Quitting during a poll doesn't crash.
- [ ] Sleep/wake cycle resumes polling correctly.

---

## 18. Out of scope (explicit)

NOT in Tier 1:

- Multi-account
- SQLite migration
- Heatmap calendar
- Per-conversation cost attribution
- Apple Watch / iOS app
- Webhooks / Discord / Slack
- Email digests
- Floating HUD overlay
- Browser extension
- Public release / open-sourcing
- Localisation (English only — but UK English)
- Keyboard shortcut customisation
- Custom icons / icon picker

---

## 19. Build order

Each phase = focused commit.

1. **Phase 0 — Rename** (everything in §4). App still builds and runs identically after.
2. **Phase 1 — Storage migration** to `~/Library/Application Support/ParamClaudeBar/`.
3. **Phase 2 — Theme + colour tokens** in `Theme.swift`. Refactor existing views to use it. No visual change yet.
4. **Phase 3 — Menu bar icon redesign** (dual concentric rings).
5. **Phase 4 — Settings infrastructure** (`SettingsStore.swift`, `SettingsView.swift` skeleton, all tabs). Wire up display modes.
6. **Phase 5 — Popover redesign** per §8.
7. **Phase 6 — Chart redesign** per §8.4.
8. **Phase 7 — Burn-rate calc** + insights row.
9. **Phase 8 — Notifications** + debouncing.
10. **Phase 9 — Onboarding flow.**
11. **Phase 10 — Sparkle integration.**
12. **Phase 11 — Polish pass** (animations, light/dark testing, edge cases, README).
13. **Phase 12 — Release v1.0.0.**

---

## 20. Working notes for Claude Code

- Param wants production-quality first-attempt outputs. Avoid placeholder patterns — write the real thing.
- Don't rewrite files larger than ~150 lines in one go. Work section by section, offer diffs.
- Before any non-trivial change, read the existing file and confirm understanding.
- If a section of this spec is genuinely ambiguous or contradicts itself, ask Param a single clarifying question rather than guessing.
- All UI text in **British English** (colour, customise, behaviour, organisation).
- 24-hour clock in any time displays.
- Upstream code is fine — keep what works, replace only what this spec changes.
- Param is on a Max plan with Claude — token usage during Claude Code work isn't a constraint, but quality is. Don't chunk tasks artificially.
