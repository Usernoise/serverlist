import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var serverManager: ServerManager!
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var eventMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        serverManager = ServerManager()
        
        setupStatusBar()
        setupPopover()
        
        let contentView = ContentView(serverManager: serverManager)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 450),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "ServerList"
        window.contentView = NSHostingView(rootView: contentView)
        window.minSize = NSSize(width: 520, height: 450)
        window.maxSize = NSSize(width: 520, height: 450)
        window.makeKeyAndOrderFront(nil)
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "ServerList")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover)
            button.target = self
        }
    }
    
    func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.animates = false
        
        let popoverContent = StatusBarPopoverView(
            serverManager: serverManager,
            onClose: { [weak self] in
                self?.closePopover()
            },
            onOpenApp: { [weak self] in
                self?.openApp()
                self?.closePopover()
            }
        )
        popover.contentViewController = NSHostingController(rootView: popoverContent)
    }
    
    @objc func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }
    
    func showPopover() {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            setupEventMonitor()
        }
    }
    
    func closePopover() {
        popover.performClose(nil)
        removeEventMonitor()
    }
    
    func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover.isShown == true {
                self?.closePopover()
            }
        }
    }
    
    func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    @objc func openApp() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() {
        serverManager.stopAllServers()
        NSApp.terminate(nil)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        removeEventMonitor()
        serverManager.stopAllServers()
    }
}