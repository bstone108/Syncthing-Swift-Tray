import SwiftUI

struct PopoverContentView: View {
    @ObservedObject var appModel: AppModel
    @ObservedObject var attentionLogStore: AttentionLogStore

    private let panelBackground = Color(nsColor: NSColor(calibratedWhite: 0.1, alpha: 0.94))
    private let panelBorder = Color.white.opacity(0.08)
    private let cardBackground = Color.white.opacity(0.06)

    private let controlColumns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity)),
        GridItem(.flexible(minimum: 0, maximum: .infinity)),
        GridItem(.flexible(minimum: 0, maximum: .infinity))
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(panelBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(panelBorder, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appModel.statusSnapshot.summaryText)
                        .font(.headline)

                    Text("Runtime \(appModel.currentRuntimeVersion) • minimum \(appModel.minimumRuntimeVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(appModel.guiURLText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let updateBannerMessage = appModel.updateBannerMessage {
                    Text(updateBannerMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Text("Controls")
                    .font(.subheadline.weight(.semibold))

                LazyVGrid(columns: controlColumns, spacing: 8) {
                    Button("Start") { appModel.requestStart() }
                    Button("Stop") { appModel.requestStop() }
                    Button("Restart") { appModel.requestRestart() }
                    Button("Web GUI") { appModel.requestOpenGUI() }
                    Button("Repair") { appModel.requestRepairRuntime() }
                    Button("Quit") { appModel.requestQuit() }
                }
                .buttonStyle(.bordered)

                HStack(spacing: 8) {
                    Text("Actions:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Start, Stop, Restart, Web GUI, Repair, Quit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Launch at login", isOn: Binding(
                        get: { appModel.preferences.launchAtLoginEnabled },
                        set: { appModel.setLaunchAtLoginEnabled($0) }
                    ))

                    Toggle("Start Syncthing automatically", isOn: Binding(
                        get: { appModel.preferences.startSyncthingAutomatically },
                        set: { appModel.setStartSyncthingAutomatically($0) }
                    ))

                    Toggle("Auto-check runtime updates", isOn: Binding(
                        get: { appModel.preferences.autoCheckUpdates },
                        set: { appModel.setAutoCheckUpdates($0) }
                    ))
                }
                .toggleStyle(.switch)

                Divider()

                Text("Attention Log")
                    .font(.subheadline.weight(.semibold))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if attentionLogStore.entries.isEmpty {
                            Text("No important log messages yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(attentionLogStore.entries) { entry in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("[\(entry.level.rawValue.uppercased())] \(entry.source.rawValue.capitalized)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(color(for: entry.level))
                                    Text(entry.message)
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                    Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .padding(8)
        .frame(width: 390, height: 470)
        .preferredColorScheme(.dark)
    }

    private func color(for level: AttentionLogLevel) -> Color {
        switch level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
