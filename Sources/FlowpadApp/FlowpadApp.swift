import AppKit
import SwiftUI

@main
struct FlowpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Flowpad") {
            RootView()
                .environmentObject(model)
                .background(WindowAccessor())
                .frame(minWidth: 760, idealWidth: 920, minHeight: 560, idealHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.selectedSection = .settings
                    AppDelegate.openMainWindow()
                }
                .keyboardShortcut(",")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static weak var current: AppDelegate?
    private var statusItem: NSStatusItem?
    private var observer: NSObjectProtocol?
    private var fallbackWindow: NSWindow?

    override init() {
        super.init()
        Self.current = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            do {
                try SelfTest.run()
                print("Flowpad self-test passed")
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                fputs("Flowpad self-test failed: \(error)\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }
        }

        if CommandLine.arguments.contains("--import-multitouch") {
            do {
                let result = try AppModel.shared.importMultitouchBindings()
                print(result.summary)
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                fputs("Multitouch import failed: \(error.localizedDescription)\n", stderr)
                Darwin.exit(EXIT_FAILURE)
            }
        }

        NSApp.setActivationPolicy(.regular)
        AppModel.shared.start()
        updateStatusItem()
        DispatchQueue.main.async {
            Self.openMainWindow()
        }
        observer = NotificationCenter.default.addObserver(
            forName: .flowpadMenuBarVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.openMainWindow()
        return true
    }

    static func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "FlowpadMainWindow" })
            ?? NSApp.windows.first(where: { $0.title == "Flowpad" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            current?.createFallbackWindow()
        }
    }

    private func createFallbackWindow() {
        if let fallbackWindow {
            fallbackWindow.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = RootView().environmentObject(AppModel.shared)
        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: controller)
        window.identifier = NSUserInterfaceItemIdentifier("FlowpadMainWindow")
        window.title = "Flowpad"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 920, height: 680))
        window.minSize = NSSize(width: 760, height: 560)
        window.center()
        window.delegate = RetainedWindowDelegate.shared
        fallbackWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func updateStatusItem() {
        if AppModel.shared.settings.showMenuBarIcon {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "circle.grid.2x2.fill", accessibilityDescription: "Flowpad")
                let menu = NSMenu()
                let open = NSMenuItem(title: "Open Flowpad", action: #selector(openFlowpad), keyEquivalent: "")
                open.target = self
                menu.addItem(open)
                let enabled = NSMenuItem(title: "Enable Gestures", action: #selector(toggleGestures), keyEquivalent: "")
                enabled.target = self
                enabled.state = AppModel.shared.settings.gesturesEnabled ? .on : .off
                menu.addItem(enabled)
                menu.addItem(.separator())
                let quit = NSMenuItem(title: "Quit Flowpad", action: #selector(quitFlowpad), keyEquivalent: "q")
                quit.target = self
                menu.addItem(quit)
                item.menu = menu
                statusItem = item
            }
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @objc private func openFlowpad() {
        Self.openMainWindow()
    }

    @objc private func toggleGestures(_ sender: NSMenuItem) {
        AppModel.shared.updateSettings { $0.gesturesEnabled.toggle() }
        sender.state = AppModel.shared.settings.gesturesEnabled ? .on : .off
    }

    @objc private func quitFlowpad() {
        NSApp.terminate(nil)
    }
}

@MainActor
private final class RetainedWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = RetainedWindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier("FlowpadMainWindow")
        window.title = "Flowpad"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = RetainedWindowDelegate.shared
        window.center()
    }
}
