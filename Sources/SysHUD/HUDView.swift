import SwiftUI
import SysHUDCore

struct HUDView: View {
    @ObservedObject var monitor: Monitor
    @State private var expanded: Set<Int32> = []

    private static let expandedMemberCap = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            meter(
                label: "CPU",
                fraction: monitor.system.cpuPercent / 100,
                detail: String(format: "%.0f%%", monitor.system.cpuPercent),
                critical: monitor.system.cpuPercent > 80
            )
            meter(
                label: "MEM",
                fraction: monitor.memoryFraction,
                detail: "\(ByteFormat.short(monitor.system.usedMemory)) / \(ByteFormat.short(monitor.system.totalMemory))",
                critical: monitor.memoryFraction > 0.9
            )

            Divider()

            Picker("Sort", selection: $monitor.sortByMemory) {
                Text("By CPU").tag(false)
                Text("By Memory").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 5) {
                ForEach(monitor.displayGroups) { group in
                    if group.isSolo {
                        soloRow(group.members[0])
                    } else {
                        groupRow(group)
                        if expanded.contains(group.id) {
                            memberRows(group)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Toggle("Compact label", isOn: $monitor.compactLabel)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Quit System Monitor") { NSApplication.shared.terminate(nil) }
                    .font(.caption)
            }
            Text("✕ quits the process (SIGTERM), ⌥-click force kills (SIGKILL)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 360)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { monitor.launchAtLogin },
            set: { monitor.setLaunchAtLogin($0) }
        )
    }

    private func meter(label: String, fraction: Double, detail: String, critical: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .frame(width: 34, alignment: .leading)
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(critical ? .red : .accentColor)
            Text(detail)
                .font(.caption.monospacedDigit())
                .frame(width: 100, alignment: .trailing)
        }
    }

    private func soloRow(_ process: ProcessSample) -> some View {
        HStack(spacing: 8) {
            chevron(expandedState: nil)
            Text(process.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: String(process.pid))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            metrics(cpuPercent: process.cpuPercent, memoryBytes: process.memoryBytes)
            killButton(
                pid: process.pid,
                name: process.name,
                enabled: process.ownedByMe,
                disabledHelp: "Owned by another user"
            )
        }
    }

    private func groupRow(_ group: AppGroup) -> some View {
        HStack(spacing: 8) {
            // A Button, not onTapGesture: the MenuBarExtra panel drops tap
            // gestures on plain views while buttons receive clicks normally.
            Button {
                if expanded.contains(group.id) {
                    expanded.remove(group.id)
                } else {
                    expanded.insert(group.id)
                }
            } label: {
                HStack(spacing: 8) {
                    chevron(expandedState: expanded.contains(group.id))
                    Text(group.name)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("×\(group.members.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded.contains(group.id) ? "Hide processes" : "Show processes")
            Spacer(minLength: 4)
            metrics(cpuPercent: group.cpuPercent, memoryBytes: group.memoryBytes)
            killButton(
                pid: group.responsiblePid,
                name: group.name,
                enabled: group.ownedByMe,
                disabledHelp: "The responsible process is not killable from here"
            )
        }
    }

    @ViewBuilder
    private func memberRows(_ group: AppGroup) -> some View {
        ForEach(group.members.prefix(Self.expandedMemberCap)) { member in
            HStack(spacing: 8) {
                Text(member.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: String(member.pid))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                Text(String(format: "%.1f%%", member.cpuPercent))
                    .font(.caption.monospacedDigit())
                    .frame(width: 56, alignment: .trailing)
                Text(ByteFormat.short(member.memoryBytes))
                    .font(.caption.monospacedDigit())
                    .frame(width: 52, alignment: .trailing)
                killButton(
                    pid: member.pid,
                    name: member.name,
                    enabled: member.ownedByMe,
                    disabledHelp: "Owned by another user"
                )
            }
            .padding(.leading, 18)
        }
        if group.members.count > Self.expandedMemberCap {
            Text("and \(group.members.count - Self.expandedMemberCap) more")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)
        }
    }

    /// Nil renders an invisible chevron so solo rows align with group rows.
    private func chevron(expandedState: Bool?) -> some View {
        Image(systemName: expandedState == true ? "chevron.down" : "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(width: 10)
            .opacity(expandedState == nil ? 0 : 1)
    }

    private func metrics(cpuPercent: Double, memoryBytes: UInt64) -> some View {
        HStack(spacing: 8) {
            Text(String(format: "%.1f%%", cpuPercent))
                .font(.callout.monospacedDigit())
                .frame(width: 56, alignment: .trailing)
            Text(ByteFormat.short(memoryBytes))
                .font(.callout.monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func killButton(pid: Int32, name: String, enabled: Bool, disabledHelp: String) -> some View {
        Button {
            monitor.terminate(pid: pid)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .opacity(enabled ? 1 : 0.25)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? "Quit \(name) (⌥-click to force kill)" : disabledHelp)
    }
}
