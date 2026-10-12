# text-reminder-skill

![The Settings window, then the full-screen message with a countdown](demo.gif)

An agent skill that builds a small macOS menu bar app. The app shows one text over the full screen at a fixed interval. Use it to keep a motto or a quote in mind during the day.

- The message covers all screens. Input is blocked for 3 seconds.
- After 3 seconds, any key or click closes the message.
- The next interval starts when you close the message.

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

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)

## License

MIT
