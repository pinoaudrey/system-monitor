# System Monitor handoff (formerly SysHUD)

2026-08-06: v1 shipped, pushed to pinoaudrey/syshud (root commit 32bbac9).
2026-08-16: the syshud-v2 run closed every v1 verification gap and built
auto-compact (PR #1). Full evidence: `~/agent-projects/syshud-v2/`.
2026-08-18: branch `perf-and-app-grouping`. Cut SysHUD's own CPU cost
(probe gating, uid cache, publish-on-change) and grouped the panel by
responsible app. The probe now judges visibility on the item's own screen.
2026-10-06: renamed to System Monitor. The repo is now
pinoaudrey/system-monitor, at `~/Documents/Projects/system-monitor`. The app is
`/Applications/System Monitor.app` with the bundle id
`com.audreypino.system-monitor`. The preferences moved to the new id. The old
login item is off. The Swift targets and the executable keep the name SysHUD.

## State

Verified end to end on the MacBook Air (macOS 26, Swift 6.3), with
evidence in the project state dir:

- Menu bar item shows live "CPU% MEM" every 2s.
- Dropdown panel: rows grouped by responsible app (summed CPU/memory,
  member count, click to disclose members), CPU/Memory sort toggle,
  compact-label toggle, Quit.
- Kill button: on a group row it targets the responsible app, on a
  member row that one process. Plain click sends SIGTERM (proven via a
  trap log), option-click sends SIGKILL (proven via untrappable death).
- Launch-at-login toggle: both directions, from the installed bundle.
- `swift run SysHUD --sample` prints real headless output.
- Auto-compact on overflow: built, live-verified, merged (PR #1, merge
  commit f2966ff).

## Machine state right now

- Installed to `/Applications/System Monitor.app`, running from there.
- Launch at login: ON. The BTM record is keyed by bundle id and self-heals
  its URL to the running bundle's path.
- `compactLabel = 0`; auto-compact handles overflow.
- A position default is written on this Mac:
  `NSStatusItem Preferred Position Item-0` (currently 447; a Cmd-drag
  overwrites it). Without it, new status items queue leftmost and get
  overflow-hidden.
- The Mac now runs three displays (built-in Air, a 4K left of it at
  negative x, a QHD right of it at x >= ~1470). The built-in bar is full:
  a 226pt calendar item plus the system items consume its ~617pt of
  usable status width, so SysHUD is overflow-hidden there even compact,
  while both external bars show it. Auto-compact cannot help when there
  is no room at any width; only item eviction (Cmd-drag order, or
  slimming the wide neighbors) can. AppKit parks SysHUD's own
  NSStatusBarWindow on a screen where the item is visible, and the probe
  judges visibility on that screen.

## Architecture

SwiftPM, two targets plus tests. Core is UI-free and unit-tested.

- `Sources/SysHUDCore/Sampler.swift`: all Darwin API access. Host CPU via
  `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas; memory via
  `host_statistics64(HOST_VM_INFO64)` (internal - purgeable + wired +
  compressed, matches Activity Monitor); per-process via `proc_pid_rusage`
  (`ri_user_time`/`ri_system_time` are mach time units, converted through
  `mach_timebase_info`; `ri_phys_footprint` matches Activity Monitor's
  Memory column). Stateful deltas: first sample() reports 0% CPU.
  Name, uid, and responsible pid live in a per-pid identity cache and are
  looked up once per pid. The responsible pid comes from the private
  `responsibility_get_pid_responsible_for_pid` SPI (via `@_silgen_name`);
  the caveat comment sits on the declaration.
- `Sources/SysHUDCore/AppGrouping.swift`: pure roll-up of processes under
  their responsible app (summed CPU/memory, leader naming), tested.
- `Sources/SysHUDCore/ProbeGate.swift`: pure rate limiter for the
  visibility probe (width change, retry, or 60s recheck), tested.
- `Sources/SysHUDCore/{CPUMath,ByteFormat,Models}.swift`: pure logic, tested.
- `Sources/SysHUD/Entry.swift`: @main enum dispatches `--sample` CLI vs app.
- `Sources/SysHUD/Monitor.swift`: view model, 2s timer, sampling on a serial
  queue, kill action (SIGTERM, option-click SIGKILL). Per-tick data stays
  unpublished while the panel is closed; the label renders through a
  separate LabelModel that updates only when the title or heat changes,
  so an idle tick costs no SwiftUI layout.
- `Sources/SysHUD/HUDView.swift`: dropdown panel, grouped rows with
  disclosure.
- `make-app.sh`: release build, .app bundle, ad-hoc codesign.

## Verify gate

`swift test` (48 tests), `swift run SysHUD --sample`, `./make-app.sh` and a
visual check of the menu bar. No lint config in this repo.

## Gotchas learned building this (do not relearn)

- A SwiftUI `Label` inside `MenuBarExtra` renders icon-only, silently
  dropping the text. Use an explicit `Image` + `Text` pair or plain `Text`.
- macOS hides status items right of the notch by truncating at the first
  item that doesn't fit; everything queued behind it hides too, even if
  narrower. Queue position beats item width. Newest-launched apps queue
  leftmost (worst position).
- On macOS 26, third-party status items render as Control-Center-owned
  windows (layer 25, `kCGWindowName` = owning bundle id). CGWindowList is
  the way to inspect visibility (`onscreen` flag) without accessibility
  permission. `isVisible` on NSStatusItem lies (reports true when
  overflow-hidden).
- Refinement of the above, critical for any visibility probe: the
  bundle-named layer-25 window is a PROXY that reads onscreen=false at X=0
  even when the item is visible. Judge visibility from the paired
  anonymous `Item-0` window (adjacent window id, matching width); click at
  its coordinates. Its width tracks the live label.
- Label width bands (do not read a width change as a state change): plain
  compact 44-49pt, hot compact ("🔥96%") 66-68pt, hot compact 3-digit
  74pt, plain full 75pt, hot full ~95pt. Hot compact overlaps plain full,
  so width alone cannot tell compact from full; capture the window image
  to check content.
- CGWindowList emits single-sample absurd-X glitches (e.g. -2091), always
  bracketed by normal reads. Ignore singletons.
- The panel's Quit button and checkbox AX titles are `missing value`;
  automation targets by index + AX position, not title.
- Stale `.build` after a repo move: ModuleCache pcms pin the old absolute
  path and `make-app.sh` fails with "precompiled file ... was compiled
  with module cache path". Fix: `rm -rf .build`.
- `sfltool dumpbtm` hangs indefinitely as non-root on this machine
  (TCC-protected BTM store). Use the unified log for
  `backgroundtaskmanagementd` instead, via absolute path `/usr/bin/log`
  (a zsh function named `log` shadows it). The daemon logs identifier,
  URL, and disposition per register/unregister event.
- Notch boundary on this 1470pt Air measured at x≈855, so usable status
  width is ~617pt.
- Multi-display: CGWindowList carries one Control-Center copy of each
  status item per display, and each bar hides items independently. A copy
  onscreen on one bar says nothing about another. Judge visibility per
  screen; CG global x aligns with AppKit screen-frame x (only y flips).
- `NSApp.windows`' NSStatusBarWindow sits on one screen
  (`window.screen`), and macOS picks one where the item is visible when
  it can. Do not assume it sits on the built-in display.
- Asserting live system counters in one short window is flaky (kernel tick
  lag under load). The sampler test burns CPU and retries up to 5 times.
- Executable targets aren't cleanly testable; that's why the core is a
  library target.
- SwiftUI `onAppear`/`onDisappear` on MenuBarExtra window content do not
  re-fire per open. Detect the panel by its window: class
  `MenuBarExtraWindow<AnyView>` in `NSApp.windows`; its `isVisible` is
  honest (unlike NSStatusBarWindow's).
- The MenuBarExtra panel drops `onTapGesture` on plain views; use a
  `Button`. The panel also exposes NO accessibility tree (0 AX windows)
  on macOS 26. `AXPress` on the menu bar item opens it, but a panel
  opened that way is not key, and synthetic clicks then reach only
  AppKit-backed controls (the sort Picker), not SwiftUI buttons or
  toggles. Real mouse clicks through the normal open path work.

## Next steps (none blocking)

1. Other Macs: clone, `./make-app.sh` (ad-hoc signed, right-click Open on
   first launch). Decide whether a small brew tap is worth it.
2. Possible follow-ups: a color-based hot indicator (fixes the hot-emoji
   overflow limitation above), per-core breakdown, network/disk meters.
