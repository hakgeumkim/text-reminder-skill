---
name: text-reminder
description: Build and install a small macOS menu bar app that shows one text message over the full screen at a fixed interval. Use it for a personal motto, a quote, or a habit you want to keep in mind. The user cannot close the message for 3 seconds. After that, any key or click closes it. Use when the user asks for a full-screen text reminder, a quote reminder, or a motto pop-up on a Mac.
---

# Text Reminder

This skill builds a native macOS app from source on the user's Mac. Because the user's Mac compiles the app, Gatekeeper does not show an "unidentified developer" warning. No Apple Developer account is necessary.

## What the app does

- The app runs in the menu bar. It has no Dock icon.
- At each interval, the app shows the text on all screens with a dark background.
- For the first 3 seconds, the app blocks all input and shows a countdown. It also blocks Cmd+Tab.
- After 3 seconds, any key or mouse click closes the message.
- The next interval starts when the user closes the message. The interval is not a fixed clock schedule.
- When the Mac wakes from sleep, the interval starts again. The app does not show reminders that the Mac missed during sleep.
- Defaults: the text "Do what you can, not what you want." and an interval of 60 minutes.

Menu bar items: Show Now, Settings…, Pause/Resume, Launch at Login, Quit. To use another language, change the labels in `main.swift`.

## Files

| File | Purpose |
|---|---|
| `main.swift` | The full app (AppKit, one file) |
| `Info.plist` | Bundle settings. `LSUIElement` hides the Dock icon. |
| `build.sh` | Compiles the app, installs it to `~/Applications/TextReminder.app`, and starts it |

## Procedure

1. Make sure that the Mac runs macOS 13 or later.
2. Run `xcode-select -p`. If the command fails, tell the user to run `xcode-select --install`. Wait until the installation completes. Do not install the full Xcode app. It is not necessary.
3. Copy this skill folder to a location that the user selects, for example `~/TextReminder`. Do not build from inside the skills directory.
4. If the user wants a different default text, interval, or lock time, edit `main.swift` before the build (see Customization).
5. Run `./build.sh` in that folder.
6. Run `pgrep -lx TextReminder` to make sure that the app runs.
7. Tell the user to click the menu bar icon and select Show Now to see the message. Do not show the overlay yourself without the user's approval, because it blocks the screen for 3 seconds.

To rebuild after a change, run `./build.sh` again. The script stops the running app before it installs the new one.

## Customization

All values are in `main.swift`.

| Change | Location |
|---|---|
| Default text and interval | `defaults.register(defaults: [...])` near the top |
| Lock time (seconds) | `let lockSeconds = 3` |
| Font size | `label.font = .systemFont(ofSize: max(36, screen.frame.width / 22), ...)` |
| Background color and opacity | `window.backgroundColor = NSColor.black.withAlphaComponent(0.93)` |
| Menu bar icon | `NSImage(systemSymbolName: "text.bubble", ...)` |

The user can also change the text and the interval in the Settings window without a rebuild. The app keeps these values in `UserDefaults` with the domain `com.hakgeumkim.TextReminder`.

## Uninstall

1. If Launch at Login is on, select it in the menu bar menu to turn it off.
2. Select Quit in the menu bar menu.
3. Delete `~/Applications/TextReminder.app`.
4. Run `defaults delete com.hakgeumkim.TextReminder` to delete the saved settings.

## Known limits

- The app shows only one text. It does not rotate through several texts.
- Force Quit (Cmd+Option+Esc) still works during the lock. This is intentional, so the user can always recover the Mac.
