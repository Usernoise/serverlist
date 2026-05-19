import SwiftUI

struct StatusBarPopoverView: View {
    @ObservedObject var serverManager: ServerManager
    let onClose: () -> Void
    let onOpenApp: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            serversList
            Divider()
            actionButtons
        }
        .frame(width: 320, height: 400)
    }
    
    private var serversList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if serverManager.servers.isEmpty {
                    VStack {
                        Spacer()
                        Text("Нет серверов")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ForEach(serverManager.servers) { server in
                        ServerPopoverRow(
                            server: server,
                            onToggle: {
                                if server.isRunning {
                                    self.serverManager.stopServer(id: server.id)
                                } else {
                                    if self.serverManager.startServer(id: server.id) == nil {
                                        NSWorkspace.shared.open(URL(string: "http://localhost:\(server.port)")!)
                                    }
                                }
                            },
                            onRestart: {
                                self.serverManager.stopServer(id: server.id)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    _ = self.serverManager.startServer(id: server.id)
                                }
                            },
                            onOpenBrowser: {
                                NSWorkspace.shared.open(URL(string: "http://localhost:\(server.port)")!)
                            },
                            onOpenFolder: {
                                NSWorkspace.shared.open(URL(fileURLWithPath: server.folderPath))
                            },
                            onDelete: {
                                self.serverManager.servers.removeAll { $0.id == server.id }
                            }
                        )
                        Divider()
                    }
                }
            }
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 0) {
            Button(action: onOpenApp) {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12))
                    Text("Открыть")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            Divider()
            
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                    Text("Закрыть")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ServerPopoverRow: View {
    let server: Server
    let onToggle: () -> Void
    let onRestart: () -> Void
    let onOpenBrowser: () -> Void
    let onOpenFolder: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(server.name)
                .font(.system(size: 13))
                .lineLimit(1)
            
            Spacer()
            
            HStack(spacing: 6) {
                if server.isRunning {
                    Button(action: onOpenBrowser) {
                        Image(systemName: "safari")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Открыть в браузере")
                    
                    Button(action: onRestart) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Перезапустить")
                }
                
                Button(action: onToggle) {
                    Image(systemName: server.isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(server.isRunning ? .red : .green)
                }
                .buttonStyle(.plain)
                .help(server.isRunning ? "Остановить" : "Запустить")
                
                Button(action: onOpenFolder) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Открыть папку")
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Удалить")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
}