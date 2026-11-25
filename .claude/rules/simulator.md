# Simulators

Xcode 27 removed the Simulator app. Booted devices live in Device Hub. Do not launch or script `Simulator.app`.

## Which device

- **Logic, build, and test runs:** your checkout's own iPhone, `UDID=$(python3 scripts/worktree-simulator.py)` (add `--boot` to boot it). It is named `SilverScreen <worktree>` and created on first use; other sessions' worktrees have their own, so never install onto, erase, or shut down a simulator that is not yours. The stop hook uses the same one.
- **Layout or visual changes:** check more than one size. At minimum the smallest and largest available iPhones, plus an iPad when the change touches an adaptive or split layout. Say which devices you checked. A booted device you did not boot may be another session's: prefer shutdown ones for the extra sizes, and shut down what you booted when done. `python3 scripts/worktree-simulator.py --duo` gives your checkout's own iPhone Duo.
- **A device the user names:** use that one.
- If more than one simulator is booted, pass the UDID to `xcrun simctl`. `booted` is ambiguous.

## Driving the simulator

- Prefer Claude Code's own simulator tools: the iOS Simulator pane in Claude Code Desktop, or computer use from the CLI.
- The Desktop pane does not yet work with Xcode 27. When it cannot attach a device, drive the simulator through MobAI `execute_dsl` (tap, swipe, type, scroll) instead. Do not use `cliclick` or Quartz mouse events.
- Capture with `xcrun simctl io <udid> screenshot`, or the pane's capture button.

When running `xcodebuild` or other long simulator jobs, follow [`.claude/rules/shell-progress.md`](.claude/rules/shell-progress.md): `tee` the log; do not pipe into `tail -N` without `-f`.
