# Simulators

Xcode 27 removed the Simulator app. Booted devices live in Device Hub. Do not launch or script `Simulator.app`.

## Which device

- **Logic, build, and test runs:** any available iPhone simulator. Prefer one that is already booted so nothing waits on a boot. Find one with `xcrun simctl list devices available`.
- **Layout or visual changes:** check more than one size. At minimum the smallest and largest available iPhones, plus an iPad when the change touches an adaptive or split layout. Say which devices you checked.
- **A device the user names:** use that one.
- If more than one simulator is booted, pass the UDID to `xcrun simctl`. `booted` is ambiguous.

## Driving the simulator

- Prefer Claude Code's own simulator tools: the iOS Simulator pane in Claude Code Desktop, or computer use from the CLI.
- The Desktop pane does not yet work with Xcode 27. When it cannot attach a device, drive the simulator through MobAI `execute_dsl` (tap, swipe, type, scroll) instead. Do not use `cliclick` or Quartz mouse events.
- Capture with `xcrun simctl io <udid> screenshot`, or the pane's capture button.

When running `xcodebuild` or other long simulator jobs, follow [`.claude/rules/shell-progress.md`](.claude/rules/shell-progress.md): `tee` the log; do not pipe into `tail -N` without `-f`.
