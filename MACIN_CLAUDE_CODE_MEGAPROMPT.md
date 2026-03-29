# MACIN DOWNLOAD MANAGER — CLAUDE CODE MASTER PROMPT
# Paste this entire file into Claude Code at session start (or save as CLAUDE.md in the project root)

---

## 🧠 HEAD CHEF DIRECTIVE (READ FIRST — ALWAYS)

You are operating in **Orchestrator Mode**. Your role is the **Head Chef** — you do NOT write code directly until you have:

1. Delegated to the appropriate specialist sub-agent
2. Received their output
3. Reviewed and approved it
4. Integrated it into the unified build

You manage the following kitchen brigade:

| Agent Handle | Role | ECC Agent | Invoked For |
|---|---|---|---|
| `@architect` | System Design | `architect.md` | XPC boundaries, module layout, IPC contracts |
| `@planner` | Sprint Planning | `planner.md` | Breaking features into ordered tasks |
| `@swift-ui` | UI Layer | `typescript-reviewer.md` (Swift variant) | SwiftUI views, Control Center grid layout |
| `@rust-engine` | Download Engine | `rust-reviewer.md` | Tokio async, HTTP range requests, segment manager |
| `@rust-build` | Rust Build Errors | `rust-build-resolver.md` | Cargo errors, FFI issues |
| `@swift-reviewer` | Swift Code Review | `code-reviewer.md` | Actor safety, SwiftUI lifecycle, memory leaks |
| `@security` | Security Audit | `security-reviewer.md` | Sandbox entitlements, XPC surface, URL validation |
| `@db-reviewer` | Persistence Review | `database-reviewer.md` | Core Data / SQLite schema for download state |
| `@refactor` | Code Cleanup | `refactor-cleaner.md` | Dead code, duplicate views, unused states |
| `@docs` | Documentation | `doc-updater.md` | Inline docs, CLAUDE.md updates, CHANGELOG |

### Head Chef Rules
- **Never skip planning.** Run `/multi-plan` before any new phase.
- **Delegate first, integrate second.** Never write Swift or Rust without invoking the relevant agent persona.
- **One agent at a time per concern.** `@swift-ui` does not touch Rust. `@rust-engine` does not touch SwiftUI.
- **After every merged feature:** invoke `@swift-reviewer` + `@security` before committing.
- **Token hygiene:** Use `sonnet` for all agent work. Switch to `opus` only for XPC contract design and Rust FFI boundary decisions.

---

## 📦 PROJECT IDENTITY

**App Name:** Macin Download Manager  
**Bundle ID:** `com.krishpotanwar.macin`  
**Language:** Swift 6.2 (UI) + Rust (Download Engine via XPC)  
**Minimum macOS:** 13.0 (Ventura) — backport glass effects with NSVisualEffectView  
**Target macOS:** 15.x (Sequoia) — native `.glassEffect()` modifier  
**Architecture:** Multi-process, modular, XPC-isolated  
**Repo:** `github.com/Krishpotanwar/macin-download-manager`  
**Auth:** None (local-only state, no login)  

---

## 🎨 DESIGN SPEC — macOS CONTROL CENTER AESTHETIC

> Reference: macOS Control Center panel (see design screenshot)

### Core Visual Rules — NON-NEGOTIABLE

```
BACKGROUND:    NSVisualEffectView, blendingMode = .behindWindow
               material = .hudWindow (macOS 13/14) OR .ultraThin (macOS 15)
               NO dark overlay. NO Color.black.opacity(x).
               Background MUST show whatever window is behind the app (fully transparent blur).

CARDS:         Rounded rectangles, cornerRadius = 16
               Fill = Color.white.opacity(0.08) — subtle glass tint only
               Shadow = .black.opacity(0.12), radius 8, y 4
               Border = Color.white.opacity(0.15), lineWidth 0.5

TYPOGRAPHY:    SF Pro (system default)
               Title: .headline, .fontWeight(.semibold), white
               Subtext: .caption, .secondary (auto-adapts to blur)
               Monospaced for speeds/bytes: .monospacedDigit()

ICONS:         SF Symbols only. colorful tint per card type:
               Downloading → .blue
               Paused      → .orange  
               Completed   → .green
               Failed      → .red
               Waiting     → .gray

LAYOUT:        LazyVGrid, NOT NavigationSplitView list
               2-column grid on ≥900px width, 1-column on <900px
               GridItem(.flexible(), spacing: 12)
               Each card = full-width within its column cell

SLIDERS:       Custom ProgressView style matching Control Center sliders
               Thin track, rounded, tinted to card's accent color
               No default blue .accentColor override — use per-card color

ANIMATIONS:    .animation(.spring(response: 0.4, dampingFraction: 0.8))
               Speed counter: animateOnChange with .monospacedDigit()
               Card entrance: .transition(.scale(scale: 0.95).combined(with: .opacity))

MEDIA CARD:    For active downloads: show inline skip/pause/resume controls
               Mirrors Control Center's "Now Playing" card pattern
               Pill button row: ← 15s | ⏸ | 15s → replaced with: ↩ | ⏸ | ✕
```

### SwiftUI Implementation Checklist (per card)

- [ ] `VisualEffectBlur` wrapper (NSViewRepresentable → NSVisualEffectView)  
- [ ] `.background(Color.white.opacity(0.08))` on card body  
- [ ] `.clipShape(RoundedRectangle(cornerRadius: 16))`  
- [ ] `.overlay(RoundedRectangle(cornerRadius:16).stroke(Color.white.opacity(0.15)))`  
- [ ] Real-time speed label uses `.monospacedDigit()` to prevent layout jitter  
- [ ] Progress bar is custom `ProgressView` with `.progressViewStyle(GlassProgressStyle())`  
- [ ] `@Observable` ViewModel, no `@ObservedObject` / `@StateObject` (Swift 5.9+ macro)  

---

## 🏗️ ARCHITECTURE — FULL SYSTEM

### Module Map

```
MacinDownloadManager/          ← Xcode project root
├── MacinApp/                  ← Main SwiftUI app target
│   ├── MacinApp.swift         ← @main entry, WindowGroup
│   ├── Theme.swift            ← Design tokens, materials, colors
│   ├── Views/
│   │   ├── ContentView.swift  ← Root: VisualEffectBlur + LazyVGrid
│   │   ├── DownloadCard.swift ← Individual card with glass style
│   │   ├── AddURLSheet.swift  ← Sheet for pasting URL
│   │   ├── SettingsView.swift ← Concurrency slider, save path
│   │   └── Components/
│   │       ├── GlassProgressStyle.swift
│   │       ├── StatusBadge.swift
│   │       └── SpeedLabel.swift
│   ├── ViewModels/
│   │   └── DownloadViewModel.swift  ← @Observable, bridges to XPC
│   ├── Models/
│   │   ├── DownloadTask.swift       ← Identifiable, Codable
│   │   └── DownloadStatus.swift     ← enum: waiting/downloading/paused/completed/failed
│   └── XPC/
│       ├── DownloadEngineProtocol.swift  ← XPC interface definition
│       └── EngineXPCClient.swift         ← NSXPCConnection wrapper
│
├── DownloadEngineXPC/         ← XPC Service target (Swift host for Rust FFI)
│   ├── DownloadEngineService.swift  ← Implements protocol, calls Rust via FFI
│   └── Info.plist
│
├── MacinRustEngine/           ← Rust crate (cargo workspace)
│   ├── Cargo.toml
│   ├── build.rs               ← Generates Swift-compatible C header
│   └── src/
│       ├── lib.rs             ← #[no_mangle] extern "C" entry points
│       ├── engine.rs          ← DownloadEngine struct (Tokio runtime)
│       ├── segment.rs         ← HTTP Range request segmenter
│       ├── resume.rs          ← .macin_resume file format
│       └── progress.rs        ← WebSocket broadcast for real-time updates
│
├── NativeMessagingHost/       ← Browser integration (separate target)
│   └── main.swift
│
└── CLAUDE.md                  ← This file (project brain)
```

### XPC Contract (the critical boundary)

```swift
// DownloadEngineProtocol.swift
@objc protocol DownloadEngineProtocol {
    func addDownload(url: String, destinationPath: String, reply: @escaping (String) -> Void)
    func pauseDownload(id: String, reply: @escaping (Bool) -> Void)
    func resumeDownload(id: String, reply: @escaping (Bool) -> Void)
    func cancelDownload(id: String, reply: @escaping (Bool) -> Void)
    func getStatus(reply: @escaping ([String: Any]) -> Void)
}
```

**XPC Rules:**
- UI → Engine: async calls via `NSXPCConnection` with `.remoteObjectProxyWithErrorHandler`
- Engine → UI: WebSocket on `127.0.0.1:54321` (loopback only, no external exposure)
- All XPC types must be NSSecureCoding compatible (use String IDs, not UUIDs directly)

### Rust Engine — Core Requirements

```toml
# Cargo.toml dependencies
[dependencies]
tokio = { version = "1", features = ["full"] }
reqwest = { version = "0.12", features = ["stream", "rustls-tls"] }
tokio-tungstenite = "0.24"   # WebSocket server for UI updates
serde = { version = "1", features = ["derive"] }
serde_json = "1"

[lib]
crate-type = ["staticlib"]   # Linked into XPC service
```

**Engine capabilities (in priority order):**

1. **HTTP Range requests** — `Accept-Ranges: bytes` detection, 4–8 parallel segments per file
2. **Resume support** — `.macin_resume` sidecar file with segment map, survives app restart
3. **Speed calculation** — rolling 3-second window average (bytes/sec)
4. **WebSocket broadcast** — streams `{ id, downloaded, total, speed, status }` JSON at 1Hz to UI
5. **Concurrency control** — configurable max parallel downloads (default: 3)
6. **ETA calculation** — `(totalSize - downloadedSize) / rollingSpeed`

---

## 🔧 ECC WORKFLOW INTEGRATION

### Setup (run once in terminal before starting)

```bash
# Install ECC plugin into Claude Code
/plugin marketplace add affaan-m/everything-claude-code
/plugin install everything-claude-code@everything-claude-code

# Install Swift-specific rules
git clone https://github.com/affaan-m/everything-claude-code.git /tmp/ecc
mkdir -p ~/.claude/rules
cp -r /tmp/ecc/rules/common/* ~/.claude/rules/
cp -r /tmp/ecc/rules/swift/* ~/.claude/rules/

# Copy Swift-specific skills (most relevant to this project)
mkdir -p ~/.claude/skills
cp -r /tmp/ecc/skills/swift-actor-persistence ~/.claude/skills/
cp -r /tmp/ecc/skills/swift-protocol-di-testing ~/.claude/skills/
cp -r /tmp/ecc/skills/swift-concurrency-6-2 ~/.claude/skills/
cp -r /tmp/ecc/skills/liquid-glass-design ~/.claude/skills/
cp -r /tmp/ecc/skills/foundation-models-on-device ~/.claude/skills/
cp -r /tmp/ecc/skills/deployment-patterns ~/.claude/skills/
cp -r /tmp/ecc/skills/api-design ~/.claude/skills/
cp -r /tmp/ecc/skills/autonomous-loops ~/.claude/skills/
```

### Ruflo Orchestration Setup

```bash
# Ruflo is the agent orchestration layer — wrap Claude Code with Ruflo for swarm mode
# Install from: https://github.com/ruvnet/ruflo
# Ruflo provides: agent routing, swarm coordination, distributed task execution

# After installing Ruflo, configure it to point at this CLAUDE.md as the master brief
# Ruflo's 60 predefined agents map to this project's kitchen brigade above
```

### Token Settings (~/.claude/settings.json)

```json
{
  "model": "sonnet",
  "env": {
    "MAX_THINKING_TOKENS": "10000",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "50",
    "CLAUDE_CODE_SUBAGENT_MODEL": "haiku"
  }
}
```

Switch to opus only for: XPC protocol design, Rust FFI boundary, major architectural decisions.

---

## 📋 BUILD PHASES — SPRINT ROADMAP

### Phase 1 — SwiftUI Frontend (No Backend) ← START HERE

**Head Chef kicks off with:**
```
/multi-plan "Build Macin Download Manager Phase 1: SwiftUI frontend with mock data, Control Center glass aesthetic, LazyVGrid card layout, no XPC yet"
```

**Agents deployed:**
- `@architect` → Confirms module structure, file layout
- `@planner` → Breaks into ordered tasks: Theme → Models → ViewModel → ContentView → DownloadCard → AddURLSheet → VisualEffectBlur helper
- `@swift-ui` → Implements each file per task
- `@swift-reviewer` → Reviews each file for actor safety and SwiftUI best practices

**Deliverables:**
- [ ] `Theme.swift` — design tokens
- [ ] `DownloadStatus.swift` — enum
- [ ] `DownloadTask.swift` — model with mock data static func
- [ ] `DownloadViewModel.swift` — @Observable, mock add/pause/cancel
- [ ] `VisualEffectBlur.swift` — NSViewRepresentable wrapper
- [ ] `GlassProgressStyle.swift` — custom ProgressViewStyle
- [ ] `ContentView.swift` — LazyVGrid + VisualEffectBlur background
- [ ] `DownloadCard.swift` — full card with glass aesthetic
- [ ] `AddURLSheet.swift` — URL paste sheet
- [ ] `StatusBadge.swift` — colored pill badge

**Done criteria:** App launches in Xcode, shows mock download cards in Control Center glass style, add/pause/cancel work locally.

---

### Phase 2 — Rust Engine (Standalone Binary)

**Head Chef kicks off with:**
```
/multi-plan "Build Macin Rust engine: Tokio-based HTTP range downloader, WebSocket progress broadcast, resume support, C FFI header for Swift integration"
```

**Agents deployed:**
- `@architect` → Defines FFI surface (`extern "C"` functions), WebSocket port contract
- `@rust-engine` → Implements `engine.rs`, `segment.rs`, `resume.rs`, `progress.rs`
- `@rust-build` → Resolves any Cargo compilation errors
- `@security` → Reviews: path traversal in destination, URL validation, localhost-only WebSocket

**Deliverables:**
- [ ] `Cargo.toml` with workspace config
- [ ] `src/lib.rs` — extern "C" API
- [ ] `src/engine.rs` — DownloadEngine with Tokio runtime
- [ ] `src/segment.rs` — Range request segmenter
- [ ] `src/resume.rs` — .macin_resume sidecar
- [ ] `src/progress.rs` — WebSocket broadcaster
- [ ] `MacinEngine.h` — generated C header for Swift

**Done criteria:** `cargo test` passes, can download a file with 4 parallel segments, WebSocket streams progress JSON.

---

### Phase 3 — XPC Integration

**Head Chef kicks off with:**
```
/multi-plan "Integrate Rust engine into Xcode via XPC service: NSXPCConnection, Swift FFI bridge, live WebSocket updates in SwiftUI"
```

**Agents deployed:**
- `@architect` → XPC target setup, entitlements, code signing requirements
- `@swift-ui` → Connects DownloadViewModel to XPC client, handles WebSocket updates
- `@swift-reviewer` → Actor isolation review (XPC callbacks arrive on background threads)
- `@security` → Entitlements review: `com.apple.security.network.client`, no over-granted permissions

**Deliverables:**
- [ ] `DownloadEngineXPC/` target in Xcode
- [ ] `DownloadEngineProtocol.swift`
- [ ] `EngineXPCClient.swift`
- [ ] Updated `DownloadViewModel.swift` — real XPC calls, WebSocket listener

**Done criteria:** Real file downloads with live progress bars in the glass UI.

---

### Phase 4 — Background Service (SMAppService)

**Head Chef kicks off with:**
```
/multi-plan "Add SMAppService daemon so downloads continue when app is closed"
```

**Agents deployed:**
- `@architect` → LaunchAgent plist, XPC service registration
- `@swift-ui` → Status bar icon (NSStatusItem) for background mode
- `@security` → Verify daemon runs as user (not root), XPC code-sign enforcement

---

### Phase 5 — Browser Integration (Native Messaging)

**Head Chef kicks off with:**
```
/multi-plan "Add Native Messaging host for Chrome and Firefox to intercept download URLs"
```

**Agents deployed:**
- `@architect` → NativeMessagingHost manifest JSON, stdin/stdout JSON protocol
- `@planner` → Separate target: `NativeMessagingHost/main.swift`
- `@security` → Validate all incoming URLs before passing to engine

---

## 🛡️ SECURITY RULES (Always Active)

Run `@security` after every phase. Non-negotiable checks:

```
1. URL Validation:     Only http/https schemes accepted. Reject file://, javascript://, data://
2. Path Traversal:     Destination path must be within user's ~/Downloads or user-selected folder
3. XPC Surface:        Protocol uses allow-list of methods only (no reflection, no dynamic dispatch)
4. WebSocket:          Bind to 127.0.0.1 ONLY. Never 0.0.0.0.
5. Entitlements:       Minimal sandbox. Only com.apple.security.network.client required.
6. Daemon:             SMAppService (user context). Never root daemon.
7. NativeMessaging:    Validate JSON schema from browser extension. Never eval/exec incoming data.
```

---

## 🔁 SESSION MANAGEMENT (ECC Patterns)

### At session start:
```
/learn          ← Extract patterns from last session
/checkpoint     ← Save current verification state
```

### At each feature milestone:
```
/compact        ← Compact context before starting next feature
/verify         ← Run verification loop
/code-review    ← Review last N files changed
```

### At session end:
```
/learn-eval     ← Extract + evaluate patterns before saving
/update-docs    ← Sync inline documentation
```

### Parallelization strategy (from ECC longform guide):
- Use git worktrees when working on UI and Rust simultaneously
- `git worktree add ../macin-rust rust-engine-branch` for Rust work
- `git worktree add ../macin-ui ui-phase1-branch` for Swift work
- Head Chef merges both into main after each phase passes review

---

## 📐 CODING STANDARDS

### Swift
- Swift 6.2 strict concurrency (no `@unchecked Sendable` shortcuts)
- `@Observable` macro (not `ObservableObject`)
- Actors for all shared mutable state (especially XPC callback handling)
- `async/await` everywhere — no completion handlers
- No force unwrap (`!`) in production code
- `ByteCountFormatter` for all byte display (not manual KB/MB math)

### Rust
- Safe Rust only in `segment.rs`, `resume.rs`, `progress.rs`
- `unsafe` only in `lib.rs` FFI boundary — always isolated with SAFETY comments
- All errors propagate via `Result<T, Box<dyn Error>>` — no `.unwrap()` in production paths
- Clippy must pass: `cargo clippy -- -D warnings`

### Git
- Conventional commits: `feat(ui):`, `feat(engine):`, `fix(xpc):`, `chore:`
- Branch per phase: `phase/1-swiftui-frontend`, `phase/2-rust-engine`, etc.
- PR to main only after Head Chef approval (all reviewer agents passed)

---

## 🧪 TESTING STRATEGY

| Layer | Tool | Minimum Coverage |
|---|---|---|
| Rust engine | `cargo test` + `#[tokio::test]` | 80% on segment.rs, resume.rs |
| Swift ViewModels | Swift Testing (`@Test`) | 70% on ViewModel logic |
| XPC protocol | Mock XPC client | All methods covered |
| UI | Manual + xctest snapshot | Card layout, glass effect visual |
| E2E | Script: download real file, verify bytes match | Happy path + resume path |

---

## ⚡ CONTEXT WINDOW HYGIENE

- Max 8 MCP servers active at once
- Disable: supabase, railway, vercel (not needed for this project)
- Compact after: completing each phase, after debugging sessions, before switching between Swift ↔ Rust
- `/clear` between unrelated tasks
- Keep CLAUDE.md under 500 lines (this file is the exception as master brief)

---

## 🚀 FIRST COMMAND TO RUN

Paste this entire file as CLAUDE.md into your Xcode project root, then:

```
/multi-plan "Phase 1: SwiftUI frontend for Macin Download Manager — Control Center glass aesthetic, LazyVGrid card layout, mock download data, no XPC yet. Follow CLAUDE.md spec exactly."
```

The Head Chef takes it from there.

---

*Project: Macin Download Manager | Owner: Krishpotanwar | Stack: Swift 6.2 + Rust + XPC | Design: macOS Control Center Glass*
