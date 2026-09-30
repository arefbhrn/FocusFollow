# FocusFollow

A macOS menu bar app that moves keyboard focus to the screen you're facing, using your Mac's camera and on-device head-pose detection. Turn your head to another display and start typing — no click needed.

Camera frames stay in memory on your Mac. Nothing is recorded or sent anywhere.

## Features (v1)

- **Screen focus:** detects which display you're facing and focuses the last window you used there.
- **Calibration:** look at each display for about 20 seconds. Calibration is saved per display arrangement, and FocusFollow asks you to recalibrate when you plug in or remove a monitor.
- **Stays out of the way:** ignores quick glances, holds while you type or use the mouse, ignores looking away from every screen, and stops on sleep, lock and screen saver.
- **Menu bar control:** pause and resume from the menu or with **⌃⌥⌘F**; the icon shows the current state.
- **Settings:** glance delay, pause after typing, pause after mouse use, head-turn tolerance, cursor-follows-focus, camera choice, open at login.
- **Single instance:** launching it again just brings the running copy forward.

Not in v1: focusing windows on the same screen and split panes. See [ROADMAP.md](ROADMAP.md).

## Requirements

- macOS 14 Sonoma or later
- A Mac with a built-in or external camera
- Xcode 16 or later to build from source

## Install

Download the DMG from the latest GitHub release, open it and drag `FocusFollow.app` onto Applications. The app is not notarized, so macOS blocks it the first time: open it once, then go to **System Settings → Privacy & Security** and choose **Open Anyway**.

Release builds are for Apple silicon. On an Intel Mac, build from source.

## Build from source

1. Open `FocusFollow.xcodeproj` in Xcode.
2. In **Signing & Capabilities**, pick your own team (a free Personal Team works).
3. Run (⌘R). FocusFollow appears in the menu bar — there's no Dock icon.

Or from the command line:

```bash
xcodebuild -project FocusFollow.xcodeproj -scheme FocusFollow -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/FocusFollow.app
```

Only one copy can run at a time, so quit a running copy before starting a new build.

To make the release DMG (needs `brew install create-dmg`):

```bash
scripts/make-dmg.sh   # writes dist/FocusFollow-<version>-arm64.dmg and prints its SHA-256
```

The app icon is drawn by `scripts/make-icon.swift`; rerun it to regenerate the PNGs in the asset catalog.

## First run

1. Allow **Camera** access when asked.
2. In the menu, choose **Grant Accessibility Access…** and turn FocusFollow on in System Settings. It needs this to focus windows and move the pointer.
3. Choose **Calibrate…** and look at each highlighted screen, keeping your head natural and still.
4. Use **Show Debug Window** to see the camera, your head pose and which screen FocusFollow thinks you're facing.

## Permissions

- **Camera** — head-pose detection.
- **Accessibility** — focusing windows, moving the pointer, and noticing keyboard and mouse activity so it doesn't switch while you're working. Only timestamps are kept, never what you type.

If a permission stops working after rebuilding, reset it and grant it again:

```bash
tccutil reset Accessibility com.arefbhrn.focusfollow
tccutil reset Camera com.arefbhrn.focusfollow
```

## Known limits

- It uses head direction, not eye tracking, so it tells displays apart but not windows on the same screen.
- Accuracy depends on camera position, lighting and posture. Recalibrate if you move your setup.
- Minimized, hidden and other-Space windows are never focused.
