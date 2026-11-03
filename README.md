# text-reminder-skill

![The Settings window, then the full-screen message with a countdown](demo.gif)

An agent skill that builds a small macOS menu bar app. The app shows one text over the full screen at a fixed interval. Use it to keep a motto or a quote in mind during the day.

- The message covers all screens. Input is blocked for 3 seconds.
- After 3 seconds, any key or click closes the message.
- The next interval starts when you close the message.
- Optional **Active Hours** restrict automatic reminders to one daily time range, including overnight ranges. Times always follow your Mac's timezone; there is no separate timezone setting.
- One compact menu row shows the next reminder time, for example `18:30` or `Tomorrow 09:00`. Hover over the row or menu bar icon for the full date, seconds, and scheduling state.

## Active Hours

Open **Settings…**, enable **Active Hours**, and choose a start and end time. It is off by default, so existing reminders and intervals keep working unchanged.

- The start is included and the end is excluded. Equal start/end times are rejected; disable Active Hours for all-day reminders.
- At the start of active hours, the app waits one full reminder interval. Launching, resuming, dismissing a message, or waking during active hours also starts a new interval. Missed reminders are never replayed.
- If the next reminder cannot fit before the end, the menu shows the next eligible date/time, possibly tomorrow. The active range must fit the interval plus the 3-second input lock.
- At the end, an automatic message already on screen closes and releases input. Automatic reminders with less than 3 seconds remaining are skipped.
- **Show Now** remains an explicit preview at any time, including while paused. Its preview is not closed by the active-hours boundary. Manual Pause is never cleared by a new active window; as before, relaunching the app clears Pause.
- Clock or timezone changes recalculate the schedule using the Mac's settings. A nonexistent DST boundary advances to the next valid time; a repeated boundary uses its first occurrence.

The agent compiles the app on your Mac with `swiftc` from the Xcode Command Line Tools. You do not need Xcode, an Apple Developer account, or a downloaded binary.

## Install the skill

Claude Code:

```bash
git clone https://github.com/hakgeumkim/text-reminder-skill ~/.claude/skills/text-reminder
```

Codex and other agents that read `~/.agents/skills`:

```bash
git clone https://github.com/hakgeumkim/text-reminder-skill ~/.agents/skills/text-reminder
```

Then ask your agent: "Make me a full-screen text reminder that shows my motto every hour."

## Build without an agent

```bash
./build.sh
```

The script installs the app to `~/Applications/TextReminder.app` and starts it. See [SKILL.md](SKILL.md) for customization and uninstall steps.

## Scheduling checks

Run `./tests/test.sh` to check daytime and overnight ranges, boundaries, and daylight-saving transitions without launching the app or changing preferences.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)

## License

MIT
