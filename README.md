# FocusFollow

A macOS menu bar app that moves keyboard focus to the screen you're facing, using your Mac's camera and on-device head-pose detection. Turn your head to another display and start typing — no click needed.

Camera frames stay in memory on your Mac. Nothing is recorded or sent anywhere.

## Features

- **Screen focus:** detects which display you're facing and focuses the last window you used there.
- **Calibration:** look at each display for about 20 seconds. Calibration is saved per display arrangement, and FocusFollow asks you to recalibrate when you plug in or remove a monitor.
- **Stays out of the way:** ignores quick glances, holds while you type or use the mouse, ignores looking away from every screen, and stops on sleep, lock and screen saver.
- **Menu bar popover:** see at a glance what FocusFollow is doing, whether the camera, Accessibility and calibration are fine (with a fix button when not), and pause or resume with the button or **⌃⌥⌘F**.
- **Settings:** tabs for General, Switching, Windows and Displays: glance delay, pause after typing and mouse use, head-turn tolerance, cursor-follows-focus, camera, open at login.
- **Window focus (experimental, off by default):** after a gaze grid calibration (25 dots per screen), looking at a window on the screen you're already on focuses it. The grid fit ignores bad dots, each dot is shown on a quality map, and screens where the estimate is too coarse are skipped. It relies on head direction, so it works best with large windows that don't overlap.
- **Diagnostics:** a window that shows the camera, head direction, what FocusFollow thinks you're looking at, and the gaze map.
- **Single instance:** launching it again just brings the running copy forward.

Not built yet: focusing split panes inside terminals and editors. See [ROADMAP.md](ROADMAP.md).

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

To see the windows without running the camera (Debug builds only), launch with `-snapshotDir /some/folder`: it writes light and dark PNGs of each window and quits.

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
