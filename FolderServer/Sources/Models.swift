import Foundation

enum ServerType: String, Codable, CaseIterable {
    case php = "PHP"
    case python = "Python (статик)"
}

struct Server: Identifiable, Codable {
    let id: UUID
    var name: String
    var serverType: ServerType
    var folderPath: String
    var port: Int
    var isRunning: Bool
    var pid: Int32?
}