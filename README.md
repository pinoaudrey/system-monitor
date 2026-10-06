# System Monitor

Menu bar system monitor for macOS. Shows live CPU and memory in the menu bar
(`38% 21.4G`), with a dropdown panel listing the top processes by CPU or
memory, each with a kill button. The menu bar icon switches to a flame when
CPU exceeds 80% or memory is above 90% of physical RAM.

Native SwiftUI (`MenuBarExtra`), zero dependencies, unsandboxed (required to
read and signal other processes).

## Build and run

```bash
./make-app.sh
open "build/System Monitor.app"
```

To install permanently: `cp -R "build/System Monitor.app" /Applications/` and enable
"Launch at login" in the dropdown. For other Macs, build there or copy the
.app (ad-hoc signed, so Gatekeeper may need right-click > Open on first
launch).

Until 2026-10-06 the app had the name SysHUD and the bundle id
`com.audreypino.syshud`. The Swift targets and the executable keep the old name.
A login item keeps the name from its first registration, so the rename needed a
new bundle id. To move the old preferences, run this once:
`defaults export com.audreypino.syshud - | defaults import com.audreypino.system-monitor -`.

## Headless check

```bash
swift run SysHUD --sample
```

Prints one system sample and the top 12 processes by CPU, no UI.

## Tests

```bash
swift test
```

## How it reads stats

- System CPU: `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas between 2s samples.
- System memory: `host_statistics64(HOST_VM_INFO64)`, used = app memory
  (internal minus purgeable) + wired + compressed, matching Activity Monitor.
- Per process: `proc_pid_rusage` for CPU time (mach time, converted via
  timebase) and `ri_phys_footprint` for memory, the same number Activity
  Monitor's Memory column shows. CPU% is per single core, so multi-threaded
  processes can exceed 100%.

## Crowded menu bars

macOS hides status items that don't fit right of the notch, truncating at the
first item that doesn't fit (everything queued behind it hides too, even if
narrower). Two mitigations here:

- "Compact label" in the dropdown switches the item to CPU-only (~40pt vs
  ~75pt), persisted in UserDefaults.
- The item's slot can be pinned by writing the app's own preferred-position
  default before launch, e.g.
  `defaults write com.audreypino.system-monitor "NSStatusItem Preferred Position Item-0" -float 560`.
  Cmd-dragging the item overwrites this, which is the normal way to reorder.

## Killing processes

The ✕ button sends SIGTERM (graceful quit). Option-click sends SIGKILL. Only
processes owned by your user can be signalled; others are dimmed. `kernel_task`
and other kernel-owned pids don't appear since `proc_pid_rusage` denies them.
