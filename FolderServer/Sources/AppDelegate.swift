import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
        window.isReleasedWhenClosed = false
        window.delegate = self
        NSApp.setActivationPolicy(.accessory)
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
        popover.contentSize = NSSize(width: 320, height: 120)
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
            },
            onQuit: { [weak self] in
                self?.quitApp()
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
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { [weak self] in
                guard let window = self?.popover.contentViewController?.view.window else { return }
                window.makeKey()
                window.makeFirstResponder(nil)
            }
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
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
