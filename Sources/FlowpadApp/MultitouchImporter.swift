import AppKit
import Foundation

struct MultitouchImportResult {
    var bindings: [GestureBinding]
    var skipped: Int

    var summary: String {
        "Imported \(bindings.count) gesture(s) from Multitouch"
            + (skipped > 0 ? "; skipped \(skipped) unsupported record(s)." : ".")
    }
}

@MainActor
enum MultitouchImporter {
    private static let domain = "com.brassmonkery.Multitouch" as CFString

    static var isAvailable: Bool {
        CFPreferencesCopyAppValue("gesturesV2" as CFString, domain) != nil
    }

    static func load() throws -> MultitouchImportResult {
        guard let gestureJSON = CFPreferencesCopyAppValue("gesturesV2" as CFString, domain) as? String,
              let gestureData = gestureJSON.data(using: .utf8),
              let records = try JSONSerialization.jsonObject(with: gestureData) as? [[String: Any]]
        else {
            throw SelfTestError.failed("No readable Multitouch gesture configuration was found.")
        }

        let applicationMap: [String: String]
        if let appJSON = CFPreferencesCopyAppValue("executableStrings" as CFString, domain) as? String,
           let data = appJSON.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            applicationMap = decoded
        } else {
            applicationMap = [:]
        }

        var bindings: [GestureBinding] = []
        var skipped = 0

        for record in records {
            guard let gesture = record["gid"] as? [String: Any],
                  let oldGestureID = gesture["gesture"] as? String,
                  let gestureID = mappedGestureID(oldGestureID),
                  let receiver = record["r"] as? [String: Any],
                  let action = action(from: receiver, applicationMap: applicationMap)
            else {
                skipped += 1
                continue
            }
            bindings.append(GestureBinding(gestureID: gestureID, action: action))
        }

        return MultitouchImportResult(bindings: bindings, skipped: skipped)
    }

    private static func mappedGestureID(_ oldID: String) -> GestureID? {
        if let direct = GestureID(rawValue: oldID) { return direct }
        let aliases: [String: GestureID] = [
            "oneTopLeft": .oneTopLeftTap,
            "oneTopRight": .oneTopRightTap,
            "oneBottomLeftTap": .oneBottomLeftTap,
            "oneBottomRightTap": .oneBottomRightTap,
            "oneTopLeftClick": .oneTopLeftClick,
            "oneTopRightClick": .oneTopRightClick,
            "oneBottomLeftClick": .oneBottomLeftClick,
            "oneBottomRightClick": .oneBottomRightClick,
            "twoLeftEdgeSwipe": .twoLeftEdgeSwipe
        ]
        return aliases[oldID]
    }

    private static func action(
        from receiver: [String: Any],
        applicationMap: [String: String]
    ) -> BindingAction? {
        guard let type = (receiver["type"] as? NSNumber)?.intValue else { return nil }
        switch type {
        case 1:
            guard let keyCode = (receiver["keyCode"] as? NSNumber)?.intValue,
                  let modifierFlags = (receiver["modifierFlags"] as? NSNumber)?.uint64Value
            else { return nil }
            let flags = cgFlags(fromLegacyModifiers: modifierFlags)
            let shortcut = KeyboardShortcut(
                keyCode: UInt16(keyCode),
                modifiers: flags.rawValue,
                displayText: ShortcutText.display(keyCode: UInt16(keyCode), flags: flags)
            )
            return .keyboardShortcut(shortcut)

        case 2:
            guard (receiver["action"] as? NSNumber)?.intValue == 226 else { return nil }
            let flags = CGEventFlags.maskCommand
            return .keyboardShortcut(
                KeyboardShortcut(
                    keyCode: 49,
                    modifiers: flags.rawValue,
                    displayText: ShortcutText.display(keyCode: 49, flags: flags)
                )
            )

        case 16:
            guard let referenceID = receiver["id"] as? String,
                  let bundleIdentifier = applicationMap[referenceID],
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            else { return nil }
            let name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return .launchApplication(
                ApplicationTarget(bundleIdentifier: bundleIdentifier, displayName: name, path: url.path)
            )

        default:
            return nil
        }
    }

    private static func cgFlags(fromLegacyModifiers rawValue: UInt64) -> CGEventFlags {
        let legacy = NSEvent.ModifierFlags(rawValue: UInt(rawValue))
        var flags: CGEventFlags = []
        if legacy.contains(NSEvent.ModifierFlags.control) { flags.insert(.maskControl) }
        if legacy.contains(NSEvent.ModifierFlags.option) { flags.insert(.maskAlternate) }
        if legacy.contains(NSEvent.ModifierFlags.shift) { flags.insert(.maskShift) }
        if legacy.contains(NSEvent.ModifierFlags.command) { flags.insert(.maskCommand) }
        if legacy.contains(NSEvent.ModifierFlags.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }
}

enum ShortcutText {
    static func display(keyCode: UInt16, flags: CGEventFlags) -> String {
        var pieces: [String] = []
        if flags.contains(.maskControl) { pieces.append("⌃") }
        if flags.contains(.maskAlternate) { pieces.append("⌥") }
        if flags.contains(.maskShift) { pieces.append("⇧") }
        if flags.contains(.maskCommand) { pieces.append("⌘") }
        if flags.contains(.maskSecondaryFn) { pieces.append("fn") }
        pieces.append(keyName(keyCode))
        return pieces.joined(separator: " ")
    }

    private static func keyName(_ keyCode: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Delete", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }
}
