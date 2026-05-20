import AppKit
import XCTest
@testable import ServerList

final class AppDelegateTests: XCTestCase {
    @MainActor
    func testMainWindowIsNotReleasedWhenClosed() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        let window = try XCTUnwrap(delegate.window)
        XCTAssertFalse(window.isReleasedWhenClosed)
    }
}
