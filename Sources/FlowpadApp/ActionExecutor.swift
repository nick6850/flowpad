import AppKit
import ApplicationServices
import Darwin
import Foundation

struct KeyboardEventStep: Equatable {
    let keyCode: CGKeyCode
    let keyDown: Bool
    let flags: CGEventFlags
}

enum AppSwitcherDirection: Equatable {
    case next
    case previous
}

final class ActionExecutor: @unchecked Sendable {
    // Keep Command held long enough for another trackpad gesture to advance
    // the native switcher. Every repeated Switch Application action refreshes
    // this deadline; letting it expire accepts the highlighted application.
    static let appSwitcherReleaseDelay: TimeInterval = 1.0

    private let keyboardQueue = DispatchQueue(
        label: "app.flowpad.keyboard-output",
        qos: .userInteractive
    )
    private var appSwitcherCommandHeld = false
    private var appSwitcherGeneration: UInt = 0

    func execute(_ action: BindingAction) {
        switch action {
        case let .keyboardShortcut(shortcut):
            execute(shortcut)
        case let .launchApplication(target):
            performWorkspaceAction { [weak self] in self?.launch(target) }
        case let .openFolder(target):
            performWorkspaceAction { [weak self] in self?.openFolder(target) }
        case let .systemAction(action):
            execute(action)
        }
    }

    private func execute(_ shortcut: KeyboardShortcut) {
        guard AXIsProcessTrusted() else { return }
        keyboardQueue.async {
            guard let source = self.makeEventSource() else { return }
            self.releaseAppSwitcherIfNeeded(using: source)

            for step in Self.eventPlan(for: shortcut) {
                self.post(
                    keyCode: step.keyCode,
                    keyDown: step.keyDown,
                    flags: step.flags,
                    source: source
                )

                // Electron/Chromium observes the real modifier transition
                // sequence. Keep the key down for one short frame so its menu
                // accelerator and renderer both see the chord reliably.
                usleep(step.keyCode == shortcut.keyCode && step.keyDown ? 16_000 : 1_500)
            }
        }
    }

    func stop() {
        keyboardQueue.sync {
            guard let source = makeEventSource() else { return }
            releaseAppSwitcherIfNeeded(using: source)
        }
    }

    /// While the native switcher is visible, horizontal swipes are navigation
    /// controls rather than their normally configured Flowpad actions.
    func advanceAppSwitcherIfActive(for pattern: GesturePattern) -> Bool {
        guard let direction = Self.appSwitcherDirection(for: pattern) else { return false }
        return advanceAppSwitcherIfActive(direction)
    }

    func advanceAppSwitcherIfActive(_ direction: AppSwitcherDirection) -> Bool {
        return keyboardQueue.sync {
            guard appSwitcherCommandHeld,
                  let source = makeEventSource()
            else { return false }
            postAppSwitcherStep(direction, using: source)
            scheduleAppSwitcherRelease()
            return true
        }
    }

    var isAppSwitcherActive: Bool {
        keyboardQueue.sync { appSwitcherCommandHeld }
    }

    static func appSwitcherDirection(for pattern: GesturePattern) -> AppSwitcherDirection? {
        guard case let .multiSwipe(count, direction) = pattern, count >= 2 else { return nil }
        switch direction {
        case .right: return .next
        case .left: return .previous
        case .up, .down: return nil
        }
    }

    private func execute(_ action: SystemAction) {
        switch action {
        case .playPause:
            keyboardQueue.async {
                if let source = self.makeEventSource() {
                    self.releaseAppSwitcherIfNeeded(using: source)
                }
                self.postMediaKey(keyType: 16)
            }
        case .switchApplication:
            guard AXIsProcessTrusted() else { return }
            executeAppSwitcher()
        case .missionControl:
            performWorkspaceAction { [weak self] in
                self?.launchSystemApplication(
                    bundleIdentifier: "com.apple.exposelauncher",
                    fallbackPath: "/System/Applications/Mission Control.app"
                )
            }
        case .screenCapture:
            performWorkspaceAction { [weak self] in
                self?.launchSystemApplication(
                    bundleIdentifier: "com.apple.screenshot.launcher",
                    fallbackPath: "/System/Applications/Utilities/Screenshot.app"
                )
            }
        case .launchpad:
            // Fn-Shift-A opens Apps on macOS 26+ and Launchpad on earlier
            // supported releases. Apple documents the same semantic shortcut
            // for both versions.
            execute(KeyboardShortcut(
                keyCode: 0,
                modifiers: (CGEventFlags.maskSecondaryFn.rawValue | CGEventFlags.maskShift.rawValue),
                displayText: "fn ⇧ A"
            ))
        }
    }

    private func executeAppSwitcher() {
        keyboardQueue.async {
            guard let source = self.makeEventSource() else { return }

            if !self.appSwitcherCommandHeld {
                self.postModifier(keyCode: 55, flags: .maskCommand, source: source)
                self.appSwitcherCommandHeld = true
                usleep(1_500)
            }

            self.postAppSwitcherStep(.next, using: source)
            self.scheduleAppSwitcherRelease()
        }
    }

    private func postAppSwitcherStep(_ direction: AppSwitcherDirection, using source: CGEventSource) {
        switch direction {
        case .next:
            post(keyCode: 48, keyDown: true, flags: .maskCommand, source: source)
            usleep(16_000)
            post(keyCode: 48, keyDown: false, flags: .maskCommand, source: source)
        case .previous:
            let flags: CGEventFlags = [.maskCommand, .maskShift]
            postModifier(keyCode: 56, flags: flags, source: source)
            usleep(1_500)
            post(keyCode: 48, keyDown: true, flags: flags, source: source)
            usleep(16_000)
            post(keyCode: 48, keyDown: false, flags: flags, source: source)
            postModifier(keyCode: 56, flags: .maskCommand, source: source)
        }
    }

    private func scheduleAppSwitcherRelease() {
        appSwitcherGeneration &+= 1
        let generation = appSwitcherGeneration
        keyboardQueue.asyncAfter(deadline: .now() + Self.appSwitcherReleaseDelay) {
            guard generation == self.appSwitcherGeneration,
                  let releaseSource = self.makeEventSource()
            else { return }
            self.releaseAppSwitcherIfNeeded(using: releaseSource)
        }
    }

    private func performWorkspaceAction(_ action: @escaping @Sendable () -> Void) {
        keyboardQueue.async { [weak self] in
            guard let self else { return }
            if let source = self.makeEventSource() {
                self.releaseAppSwitcherIfNeeded(using: source)
            }
            DispatchQueue.main.async(execute: action)
        }
    }

    private func releaseAppSwitcherIfNeeded(using source: CGEventSource) {
        guard appSwitcherCommandHeld else { return }
        appSwitcherGeneration &+= 1
        postModifier(keyCode: 55, flags: [], source: source)
        appSwitcherCommandHeld = false
    }

    private func makeEventSource() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }
        source.localEventsSuppressionInterval = 0
        return source
    }

    private func post(
        keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags,
        source: CGEventSource
    ) {
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: keyDown
        ) else { return }
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        event.post(tap: .cghidEventTap)
    }

    /// Modifier transitions must be flagsChanged events. Posting them as
    /// ordinary keyDown/keyUp events is enough for many apps, but Dock's native
    /// app switcher does not keep Command latched and closes immediately.
    private func postModifier(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        source: CGEventSource
    ) {
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: !flags.isEmpty
        ) else { return }
        event.type = .flagsChanged
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func postMediaKey(keyType: Int) {
        for isDown in [true, false] {
            let keyState = isDown ? 0xA00 : 0xB00
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (keyType << 16) | keyState,
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
            if isDown { usleep(16_000) }
        }
    }

    static func eventPlan(for shortcut: KeyboardShortcut) -> [KeyboardEventStep] {
        let requestedFlags = shortcut.eventFlags
        let modifiers: [(flag: CGEventFlags, keyCode: CGKeyCode)] = [
            (.maskControl, 59),
            (.maskAlternate, 58),
            (.maskShift, 56),
            (.maskCommand, 55),
            (.maskSecondaryFn, 63)
        ].filter { requestedFlags.contains($0.flag) }

        var plan: [KeyboardEventStep] = []
        var activeFlags: CGEventFlags = []
        for modifier in modifiers {
            activeFlags.insert(modifier.flag)
            plan.append(KeyboardEventStep(
                keyCode: modifier.keyCode,
                keyDown: true,
                flags: activeFlags
            ))
        }

        plan.append(KeyboardEventStep(
            keyCode: shortcut.keyCode,
            keyDown: true,
            flags: requestedFlags
        ))
        plan.append(KeyboardEventStep(
            keyCode: shortcut.keyCode,
            keyDown: false,
            flags: requestedFlags
        ))

        for modifier in modifiers.reversed() {
            activeFlags.remove(modifier.flag)
            plan.append(KeyboardEventStep(
                keyCode: modifier.keyCode,
                keyDown: false,
                flags: activeFlags
            ))
        }
        return plan
    }

    private func launch(_ target: ApplicationTarget) {
        let workspace = NSWorkspace.shared
        let url: URL?
        if FileManager.default.fileExists(atPath: target.path) {
            url = URL(fileURLWithPath: target.path)
        } else {
            url = workspace.urlForApplication(withBundleIdentifier: target.bundleIdentifier)
        }
        guard let url else { return }
        workspace.openApplication(at: url, configuration: .init())
    }

    private func openFolder(_ target: FolderTarget) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: target.path, isDirectory: true))
    }

    private func launchSystemApplication(bundleIdentifier: String, fallbackPath: String) {
        let workspace = NSWorkspace.shared
        let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
            ?? URL(fileURLWithPath: fallbackPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        workspace.openApplication(at: url, configuration: .init())
    }
}

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
