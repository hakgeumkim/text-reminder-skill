#!/bin/zsh
set -eu
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/.build/module-cache"
TEST_DIR="$(mktemp -d "$ROOT_DIR/.build/test.XXXXXX")"
swiftc -module-cache-path "$ROOT_DIR/.build/module-cache" \
  "$ROOT_DIR/ReminderSchedule.swift" "$ROOT_DIR/tests/ScheduleTests.swift" \
  -o "$TEST_DIR/ScheduleTests"
"$TEST_DIR/ScheduleTests"
