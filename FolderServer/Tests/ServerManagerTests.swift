import XCTest
@testable import ServerList

final class ServerManagerTests: XCTestCase {
    private let savedServersKey = "savedServers"
    private var previousSavedServers: Data?

    override func setUp() {
        super.setUp()
        previousSavedServers = UserDefaults.standard.data(forKey: savedServersKey)
        UserDefaults.standard.removeObject(forKey: savedServersKey)
    }

    override func tearDown() {
        if let previousSavedServers {
            UserDefaults.standard.set(previousSavedServers, forKey: savedServersKey)
        } else {
            UserDefaults.standard.removeObject(forKey: savedServersKey)
        }
        super.tearDown()
    }

    func testMoveServersReordersAndPersistsListOrder() throws {
        let manager = ServerManager()
        let first = makeServer(name: "first", port: 8001)
        let second = makeServer(name: "second", port: 8002)
        let third = makeServer(name: "third", port: 8003)
        manager.servers = [first, second, third]

        manager.moveServers(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        XCTAssertEqual(manager.servers.map(\.id), [second.id, third.id, first.id])

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: savedServersKey))
        let persisted = try JSONDecoder().decode([Server].self, from: data)
        XCTAssertEqual(persisted.map(\.id), [second.id, third.id, first.id])
    }

    private func makeServer(name: String, port: Int) -> Server {
        Server(
            id: UUID(),
            name: name,
            serverType: .php,
            folderPath: "/tmp",
            port: port,
            isRunning: false,
            pid: nil
        )
    }
}
