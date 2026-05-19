import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var serverManager: ServerManager
    
    @State private var serverName: String = ""
    @State private var folderPath: String = ""
    @State private var port: String = "8080"
    @State private var serverType: ServerType = .php
    @State private var showFolderPicker: Bool = false
    @State private var showSystemProcesses: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            formSection
            Divider()
            serversListSection
        }
        .frame(width: 520, height: 450)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var formSection: some View {
        HStack(spacing: 8) {
            TextField("Название", text: $serverName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
            
            Button(action: { showFolderPicker = true }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.bordered)
            
            Picker("", selection: $serverType) {
                ForEach(ServerType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 90)
            
            TextField("Port", text: $port)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
            
            Button(action: addServer) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(folderPath.isEmpty || port.isEmpty)
            
            Spacer()
            
            Button(action: { showSystemProcesses = true; serverManager.scanSystemProcesses() }) {
                Image(systemName: "list.bullet")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.top, 15)
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(folderPath: $folderPath)
        }
        .sheet(isPresented: $showSystemProcesses) {
            SystemProcessesView(serverManager: serverManager)
        }
    }
    
    private var serversListSection: some View {
        VStack(spacing: 0) {
            if serverManager.servers.isEmpty {
                Spacer()
                Text("Нет серверов")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(serverManager.servers) { server in
                        CompactServerRow(
                            server: server,
                            onStart: { _ = serverManager.startServer(id: server.id) },
                            onStop: { serverManager.stopServer(id: server.id) },
                            onDelete: { deleteServer(id: server.id) }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func addServer() {
        guard let portNum = Int(port), portNum >= 1024, portNum <= 65535 else { return }
        let name = serverName.isEmpty ? "Сервер" : serverName
        _ = serverManager.addServer(name: name, serverType: serverType, folderPath: folderPath, port: portNum)
        serverName = ""
        folderPath = ""
        port = "8080"
    }
    
    private func deleteServer(id: UUID) {
        serverManager.servers.removeAll { $0.id == id }
    }
}

struct CompactServerRow: View {
    let server: Server
    let onStart: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(.subheadline)
                Text(server.folderPath)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Text(server.serverType.rawValue)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(3)
            
            Text(":\(server.port)")
                .font(.caption)
                .foregroundColor(.blue)
            
            Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: server.folderPath)) }) {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            if server.isRunning {
                Button(action: { NSWorkspace.shared.open(URL(string: "http://localhost:\(server.port)")!) }) {
                    Image(systemName: "safari")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            } else {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.vertical, 4)
    }
}

struct FolderPickerView: View {
    @Binding var folderPath: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("Выберите папку")
                .font(.headline)
                .padding()
            
            HStack {
                TextField("Путь к папке", text: $folderPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                
                Button("Обзор...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        folderPath = url.path
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            
            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Выбрать") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folderPath.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 150)
    }
}

struct SystemProcessesView: View {
    @ObservedObject var serverManager: ServerManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Серверы в системе")
                    .font(.headline)
                Spacer()
                Button(action: { serverManager.scanSystemProcesses() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            
            Divider()
            
            if serverManager.systemProcesses.isEmpty {
                VStack {
                    Spacer()
                    Text("Нет запущенных")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(serverManager.systemProcesses) { process in
                    SystemProcessRowView(
                        process: process,
                        onKill: {
                            _ = serverManager.killSystemProcess(pid: process.pid)
                        }
                    )
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                Button("Закрыть") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 350)
    }
}

struct SystemProcessRowView: View {
    let process: SystemProcess
    let onKill: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(process.name)
                        .font(.subheadline)
                    Text(":\(process.port)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                if !process.folderPath.isEmpty {
                    Text(process.folderPath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            if !process.folderPath.isEmpty {
                Button(action: { NSWorkspace.shared.open(URL(fileURLWithPath: process.folderPath)) }) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Button(action: { NSWorkspace.shared.open(URL(string: "http://localhost:\(process.port)")!) }) {
                Image(systemName: "safari")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button(action: onKill) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
        }
        .padding(.vertical, 2)
    }
}