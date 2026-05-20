import Foundation
import Darwin

extension Notification.Name {
    static let serversDidChange = Notification.Name("serversDidChange")
}

struct SystemProcess: Identifiable {
    let id: UUID
    let pid: Int32
    let name: String
    let serverType: ServerType
    let folderPath: String
    let port: Int
}

struct ServerError: Identifiable {
    let id: UUID
    let serverID: UUID
    let message: String
}

class ServerManager: ObservableObject {
    @Published var servers: [Server] = []
    @Published var systemProcesses: [SystemProcess] = []
    @Published var lastError: ServerError?
    private var processes: [UUID: Process] = [:]
    private var healthTimer: Timer?

    private let savedServersKey = "savedServers"
    
    init() {
        loadServers()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pollRunningServers()
        }
    }
    
    private func notifyServersChanged() {
        NotificationCenter.default.post(name: .serversDidChange, object: nil)
    }

    private func setError(serverID: UUID, message: String) {
        let err = ServerError(id: UUID(), serverID: serverID, message: message)
        if Thread.isMainThread {
            lastError = err
        } else {
            DispatchQueue.main.async { self.lastError = err }
        }
    }

    private func clearError(serverID: UUID) {
        if lastError?.serverID == serverID {
            lastError = nil
        }
    }

    func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: savedServersKey),
              let saved = try? JSONDecoder().decode([Server].self, from: data) else {
            return
        }
        
        servers = saved.map { server in
            var mutableServer = server
            if server.isRunning, let pid = server.pid {
                let result = kill(pid, 0)
                if result != 0 {
                    mutableServer.isRunning = false
                    mutableServer.pid = nil
                }
            }
            return mutableServer
        }
        
        saveServers()
    }
    
    func addServer(name: String, serverType: ServerType, folderPath: String, port: Int) -> Server {
        let server = Server(
            id: UUID(),
            name: name.isEmpty ? "Сервер" : name,
            serverType: serverType,
            folderPath: folderPath,
            port: port,
            isRunning: false,
            pid: nil
        )
        servers.append(server)
        saveServers()
        return server
    }
    
    func updateServer(id: UUID, name: String, serverType: ServerType, folderPath: String, port: Int) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].name = name
        servers[index].serverType = serverType
        servers[index].folderPath = folderPath
        servers[index].port = port
        saveServers()
    }

    func moveServers(fromOffsets source: IndexSet, toOffset destination: Int) {
        servers.move(fromOffsets: source, toOffset: destination)
        saveServers()
    }
    
    private func saveServers() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: savedServersKey)
        }
        notifyServersChanged()
    }
    
    func isPortAvailable(port: Int) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_PASSIVE
        
        var result: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        
        guard getaddrinfo(nil, portStr, &hints, &result) == 0, let res = result else {
            return true
        }
        
        let socket = Darwin.socket(res.pointee.ai_family, res.pointee.ai_socktype, res.pointee.ai_protocol)
        if socket == -1 {
            freeaddrinfo(result)
            return true
        }
        
        let bindResult = bind(socket, res.pointee.ai_addr, res.pointee.ai_addrlen)
        freeaddrinfo(result)
        close(socket)
        
        return bindResult == 0
    }
    
    func startServer(id: UUID) -> String? {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            setError(serverID: id, message: "Сервер не найден")
            return "Сервер не найден"
        }

        let server = servers[index]

        guard isPortAvailable(port: server.port) else {
            let msg = "Порт \(server.port) уже занят"
            setError(serverID: id, message: msg)
            return msg
        }

        guard FileManager.default.fileExists(atPath: server.folderPath) else {
            let msg = "Папка не существует"
            setError(serverID: id, message: msg)
            return msg
        }

        let task = Process()

        switch server.serverType {
        case .php:
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/php")
            task.arguments = ["-S", "localhost:\(server.port)", "-t", server.folderPath]
        case .python:
            task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            task.arguments = ["-m", "http.server", String(server.port), "--directory", server.folderPath]
        }

        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        task.terminationHandler = { [weak self] proc in
            let endedPid = proc.processIdentifier
            DispatchQueue.main.async {
                guard let self = self,
                      let idx = self.servers.firstIndex(where: { $0.id == id }) else { return }
                if self.servers[idx].pid == endedPid {
                    self.servers[idx].isRunning = false
                    self.servers[idx].pid = nil
                    self.processes[id] = nil
                    self.saveServers()
                }
            }
        }

        do {
            try task.run()
        } catch {
            let msg = "Не удалось запустить сервер: \(error.localizedDescription)"
            setError(serverID: id, message: msg)
            return msg
        }

        servers[index].isRunning = true
        servers[index].pid = task.processIdentifier
        processes[id] = task
        clearError(serverID: id)
        saveServers()

        return nil
    }

    func stopServer(id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        if let pid = servers[index].pid {
            kill(pid, SIGTERM)
        }
        servers[index].isRunning = false
        servers[index].pid = nil
        processes[id] = nil
        saveServers()
    }
    func stopAllServers() {
        for server in servers {
            if let pid = server.pid {
                kill(pid, SIGTERM)
            }
        }
        for i in servers.indices {
            servers[i].isRunning = false
            servers[i].pid = nil
        }
        processes.removeAll()
        saveServers()
    }

    func deleteServer(id: UUID) {
        if let index = servers.firstIndex(where: { $0.id == id }),
           servers[index].isRunning, let pid = servers[index].pid {
            kill(pid, SIGTERM)
        }
        processes[id] = nil
        servers.removeAll { $0.id == id }
        if lastError?.serverID == id { lastError = nil }
        saveServers()
    }

    func restartServer(id: UUID) {
        guard let server = servers.first(where: { $0.id == id }) else {
            setError(serverID: id, message: "Сервер не найден")
            return
        }
        let port = server.port

        if server.isRunning {
            stopServer(id: id)
        }

        let deadline = Date().addingTimeInterval(2.0)

        func attempt() {
            if isPortAvailable(port: port) {
                _ = startServer(id: id)
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { attempt() }
            } else {
                setError(serverID: id, message: "Порт \(port) не освободился, перезапуск отменён")
            }
        }

        attempt()
    }

    func checkServerHealth(id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }),
              let pid = servers[index].pid else { return }
        if kill(pid, 0) != 0 {
            DispatchQueue.main.async {
                guard let idx = self.servers.firstIndex(where: { $0.id == id }) else { return }
                self.servers[idx].isRunning = false
                self.servers[idx].pid = nil
                self.processes[id] = nil
                self.saveServers()
            }
        }
    }
    
    private func pollRunningServers() {
        var deadIDs: [UUID] = []
        for server in servers where server.isRunning {
            if let pid = server.pid, kill(pid, 0) != 0 {
                deadIDs.append(server.id)
            }
        }
        guard !deadIDs.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var changed = false
            for id in deadIDs {
                guard let i = self.servers.firstIndex(where: { $0.id == id }) else { continue }
                self.servers[i].isRunning = false
                self.servers[i].pid = nil
                self.processes[id] = nil
                changed = true
            }
            if changed { self.saveServers() }
        }
    }

    func scanSystemProcesses() {
        var processes: [SystemProcess] = []
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-iTCP", "-sTCP:LISTEN", "-nP"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return }
            
            let lines = output.components(separatedBy: "\n")
            
            for line in lines {
                let components = line.split{ $0 == " " || $0 == "\t" }.map(String.init)
                guard components.count >= 9 else { continue }
                
                let command = components[0]
                let pidStr = components[1]
                guard let pid = Int32(pidStr) else { continue }
                
                var serverType: ServerType?
                var folderPath = ""
                
                if command == "php" {
                    serverType = .php
                    folderPath = extractFolderFromPhpArgs(pid: pid)
                } else if command == "Python" || command == "python3" {
                    serverType = .python
                    folderPath = extractFolderFromPythonArgs(pid: pid)
                }
                
                guard let type = serverType else { continue }
                
                let portStr = components[8]
                    .replacingOccurrences(of: "*:", with: "")
                    .replacingOccurrences(of: "[::1]:", with: "")
                    .replacingOccurrences(of: "127.0.0.1:", with: "")
                    .components(separatedBy: "(").first ?? ""
                guard let port = Int(portStr.trimmingCharacters(in: .whitespaces)) else { continue }
                
                processes.append(SystemProcess(
                    id: UUID(),
                    pid: pid,
                    name: type == .php ? "PHP Server" : "Python Server",
                    serverType: type,
                    folderPath: folderPath,
                    port: port
                ))
            }
        } catch {
            return
        }
        
        DispatchQueue.main.async {
            self.systemProcesses = processes
        }
    }
    
    private func extractFolderFromPhpArgs(pid: Int32) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(pid), "-o", "command="]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return "" }
            
            if let tRange = output.range(of: "-t ") {
                let afterT = String(output[tRange.upperBound...])
                if let nextFlag = afterT.range(of: " -") {
                    return String(afterT[..<nextFlag.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                return afterT.trimmingCharacters(in: .whitespaces)
            }
        } catch {}
        return ""
    }
    
    private func extractFolderFromPythonArgs(pid: Int32) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", String(pid), "-o", "command="]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return "" }
            
            if let dirRange = output.range(of: "--directory ") {
                let afterDir = String(output[dirRange.upperBound...])
                if let nextFlag = afterDir.range(of: " -") {
                    return String(afterDir[..<nextFlag.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                return afterDir.trimmingCharacters(in: .whitespaces)
            }
        } catch {}
        return ""
    }
    
    func killSystemProcess(pid: Int32) -> Bool {
        let result = kill(pid, SIGTERM)
        if result == 0 {
            DispatchQueue.main.async {
                self.systemProcesses.removeAll { $0.pid == pid }
            }
        }
        return result == 0
    }
}
