import AppKit
import ApplicationServices
import Darwin
import Foundation

struct KeyboardEventStep: Equatable {
    let keyCode: CGKeyCode
    let keyDown: Bool
    let flags: CGEventFlags
}

final class ActionExecutor: @unchecked Sendable {
    private let keyboardQueue = DispatchQueue(
        label: "app.flowpad.keyboard-output",
        qos: .userInteractive
    )

    func execute(_ action: BindingAction) {
        switch action {
        case let .keyboardShortcut(shortcut):
            execute(shortcut)
        case let .launchApplication(target):
            launch(target)
        }
    }

    private func execute(_ shortcut: KeyboardShortcut) {
        guard AXIsProcessTrusted() else { return }
        keyboardQueue.async {
            guard let source = CGEventSource(stateID: .hidSystemState) else { return }
            source.localEventsSuppressionInterval = 0

            for step in Self.eventPlan(for: shortcut) {
                guard let event = CGEvent(
                    keyboardEventSource: source,
                    virtualKey: step.keyCode,
                    keyDown: step.keyDown
                ) else { continue }
                event.flags = step.flags
                event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                event.post(tap: .cghidEventTap)

                // Electron/Chromium observes the real modifier transition
                // sequence. Keep the key down for one short frame so its menu
                // accelerator and renderer both see the chord reliably.
                usleep(step.keyCode == shortcut.keyCode && step.keyDown ? 16_000 : 1_500)
            }
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
}

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
