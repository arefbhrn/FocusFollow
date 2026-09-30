# FocusFollow Roadmap

FocusFollow is a macOS menu bar app that watches your head pose through the camera and moves keyboard focus to the screen, window, or pane you're facing — so you can start typing without clicking first.

Everything runs on-device. Camera frames stay in memory and are never recorded or sent anywhere.

## Goals

- Mac only (macOS 14 Sonoma or later, Apple silicon and Intel).
- Personal / open-source project. Signed with a free Personal Team; no notarization, no App Store.
- Pure Apple frameworks, no third-party dependencies unless clearly worth it.

## Tech stack

| Area | Choice |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI (`MenuBarExtra`, settings, calibration) + AppKit where needed |
| Camera | AVFoundation (`AVCaptureSession`, 720p, ≤15 fps) |
| Head pose | Vision (`VNDetectFaceRectanglesRequest` rev. 3 → yaw / pitch / roll) |
| Math | simd / Accelerate (smoothing, calibration fit) |
| Windows | CoreGraphics `CGWindowListCopyWindowInfo`, `CGWarpMouseCursorPosition` |
| Focus | Accessibility API (`AXUIElement`), `NSRunningApplication.activate` |
| Input activity | `NSEvent` global monitors |
| Global hotkey | Carbon `RegisterEventHotKey` |
| System events | `NSWorkspace` notifications (sleep, lock, screen changes) |
| State | Observation (`@Observable`) |
| Persistence | UserDefaults + Codable JSON |
| Launch at login | ServiceManagement `SMAppService` |
| Logging | OSLog |

Build settings: `LSUIElement = YES` (no Dock icon), `NSCameraUsageDescription`, App Sandbox **off** (Accessibility control needs it).

---

## Phase 0 — Project setup

- [x] Git repo + GitHub remote
- [x] Roadmap
- [x] Xcode project (macOS App, SwiftUI), bundle ID `com.arefbhrn.focusfollow`
- [x] Signing with Personal Team (stable identity so permissions survive rebuilds)
- [x] Info.plist: `LSUIElement`, `NSCameraUsageDescription`
- [x] Entitlements: sandbox off, camera
- [x] README with build instructions

## Phase 1 — Camera + head pose (prototype)

- [x] Menu bar app shell with `MenuBarExtra`
- [x] Camera selection (built-in / external)
- [x] Capture pipeline at 720p, ≤15 fps, frames kept in memory only
- [x] Vision face detection (rev. 3) → yaw / pitch / roll per frame
- [x] Smoothing (EMA, later maybe Kalman)
- [x] Debug window: live camera preview + pose readout
- [x] Permission flow: Camera prompt, clear message if denied

## Phase 2 — Multi-screen focus (MVP)

- [x] Read display layout from `NSScreen`
- [x] Calibration flow: look at each screen ~20 s, store pose samples per screen
- [x] Classifier: current pose → nearest screen, or "away" when outside all regions
- [x] Dwell delay (default 300 ms) to ignore quick glances
- [x] Track last focused window per screen
- [x] Switch: focus that window via Accessibility + warp cursor to that screen
- [x] Accessibility permission flow (check `AXIsProcessTrusted`, deep link to Settings)
- [x] Save calibration per display arrangement

## Phase 3 — Don't get in the way

- [x] Pause after typing (default 3 s since last keystroke)
- [x] Pause after mouse / trackpad activity (default 1.5 s)
- [x] Ignore "away" poses (phone, ceiling, desk)
- [x] Pause on sleep, screen lock, screensaver
- [x] Global pause / resume hotkey (default ⌃⌥⌘F, configurable later; ⇧⌘G collides with "Go to Folder" / "Find Previous")
- [ ] Menu bar icon reflects state (active / paused / no face / no permission)
- [x] Re-detect display changes (plug / unplug monitor) and prompt recalibration

## Phase 4 — Settings

- [ ] Dwell delay, typing pause, mouse pause sliders
- [ ] Head-turn sensitivity
- [ ] Toggle: move cursor with focus
- [ ] Camera picker
- [ ] Launch at login (`SMAppService`)
- [ ] Recalibrate button + per-screen calibration status

## Phase 5 — Same-screen window focus

- [ ] Map pose to position within a screen (needs finer calibration: corners / grid)
- [ ] Pick window under the estimated gaze point from `CGWindowList`
- [ ] Treat browsers / document windows as whole units (no focus stealing inside)
- [ ] Hysteresis so focus doesn't flicker on window borders

## Phase 6 — Split-pane focus

- [ ] Pane detection via AX tree for supported apps
- [ ] Terminals: iTerm2, Terminal, Ghostty, Warp, kitty
- [ ] Editors: VS Code, Zed, Xcode, JetBrains IDEs
- [ ] Per-app adapters (AX actions, AppleScript, or keyboard shortcuts as fallback)
- [ ] Separate pane-focus delay setting

## Phase 7 — Accuracy + learning

- [ ] Learn from clicks: each click on a screen/window is a labelled pose sample
- [ ] Online recalibration with sample decay
- [ ] Distance compensation using face size
- [ ] Detect drift and suggest recalibration
- [ ] Optional: small Core ML model if nearest-match isn't accurate enough

## Phase 8 — Polish + sharing

- [ ] App icon + menu bar glyph
- [ ] Onboarding (permissions → calibration → done)
- [ ] CPU / battery tuning (lower fps when idle, stop camera when paused)
- [ ] Release build zipped on GitHub Releases (unsigned; "Open Anyway" instructions)
- [ ] Optional: Sparkle auto-updates

---

## Out of scope (for now)

- Linux and Windows (possible later with a Rust core + per-OS backends; Wayland is the hard part)
- Eye tracking (head pose only)
- Paid distribution, App Store, notarization
