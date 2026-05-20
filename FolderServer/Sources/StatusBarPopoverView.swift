import SwiftUI
import AppKit

struct StatusBarPopoverView: View {
    @ObservedObject var serverManager: ServerManager
    let onClose: () -> Void
    let onOpenApp: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            serversList
            Divider()
            footer
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var header: some View {
        HStack {
            Text("ServerList")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var serversList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if serverManager.servers.isEmpty {
                    VStack(spacing: 6) {
                        Text("Нет серверов")
                            .foregroundColor(.secondary)
                        Text("Откройте окно, чтобы добавить сервер")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    ForEach(serverManager.servers) { server in
                        ServerPopoverRow(
                            server: server,
                            errorMessage: serverManager.lastError?.serverID == server.id
                                ? serverManager.lastError?.message
                                : nil,
                            onToggle: {
                                if server.isRunning {
                                    serverManager.stopServer(id: server.id)
                                } else {
                                    _ = serverManager.startServer(id: server.id)
                                }
                            },
                            onRestart: {
                                serverManager.restartServer(id: server.id)
                            },
                            onOpenBrowser: {
                                if let url = URL(string: "http://localhost:\(server.port)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Button(action: onOpenApp) {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 12))
                    Text("Открыть приложение")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .focusable(false)

            Divider()

            Button(action: onQuit) {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("Выход")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ServerPopoverRow: View {
    let server: Server
    let errorMessage: String?
    let onToggle: () -> Void
    let onRestart: () -> Void
    let onOpenBrowser: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle()
                    .fill(server.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                Text(server.name)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Text(":" + String(server.port))
                    .font(.system(size: 12))
                    .foregroundColor(.blue)

                Spacer()

                HStack(spacing: 10) {
                    if server.isRunning {
                        Button(action: onRestart) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Перезапустить")

                        Button(action: onOpenBrowser) {
                            Image(systemName: "safari")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Открыть в браузере")
                    }

                    Button(action: onToggle) {
                        Image(systemName: server.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(server.isRunning ? .red : .green)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(server.isRunning ? "Остановить" : "Запустить")
                }
            }

            if let errorMessage = errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 28)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
