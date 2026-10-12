#!/bin/zsh
# Build TextReminder.app into ~/Applications and start it.
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/TextReminder.app"
pkill -x TextReminder || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/TextReminder"
cp Info.plist "$APP/Contents/"
codesign --force -s - "$APP"
open "$APP"
