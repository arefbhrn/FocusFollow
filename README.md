# FocusFollow

A macOS menu bar app that moves keyboard focus to the screen, window, or pane you're facing, using your Mac's camera and on-device head-pose detection.

Camera frames stay in memory on your Mac. Nothing is recorded or sent.

> Status: early development. See [ROADMAP.md](ROADMAP.md).

## Requirements

- macOS 14 Sonoma or later
- A Mac with a built-in or external camera
- Xcode 16 or later to build

## Build and run

1. Open `FocusFollow.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, pick your own team (a free Personal Team works).
3. Run (⌘R). FocusFollow appears in the menu bar — there's no Dock icon.

Or from the command line:

```bash
xcodebuild -project FocusFollow.xcodeproj -scheme FocusFollow -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/FocusFollow.app
```

## Permissions

FocusFollow needs:

- **Camera** — to detect head pose.
- **Accessibility** — to focus windows and move the pointer.

If a permission stops working after rebuilding, reset it and grant it again:

```bash
tccutil reset Accessibility com.arefbhrn.focusfollow
tccutil reset Camera com.arefbhrn.focusfollow
```
