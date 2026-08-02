import AppKit
import Foundation

enum GestureCategory: String, Codable, CaseIterable, Identifiable {
    case oneFinger = "One Finger"
    case twoFinger = "Two Finger"
    case threeFinger = "Three Finger"
    case fourFinger = "Four Finger"
    case fiveFinger = "Five Finger"
    case forceTouch = "Force Touch"

    var id: String { rawValue }

    var color: NSColor {
        switch self {
        case .oneFinger: .systemPurple
        case .twoFinger: .systemIndigo
        case .threeFinger: .systemBlue
        case .fourFinger: .systemTeal
        case .fiveFinger: .systemGreen
        case .forceTouch: .systemOrange
        }
    }
}

enum GestureDirection: String, Codable {
    case up, down, left, right
}

enum GestureSide: String, Codable {
    case left, right
}

enum GestureCorner: String, Codable {
    case topLeft, topRight, bottomLeft, bottomRight
}

enum RelativeTapPosition: String, Codable {
    case left, center, right
}

enum GesturePattern: Hashable, Codable {
    case cornerTap(GestureCorner)
    case cornerClick(GestureCorner)
    case edgeSwipeLeft
    case restOneTap(side: GestureSide, near: Bool)
    case restOneSwipe(side: GestureSide, direction: GestureDirection)
    case multiClick(count: Int)
    case multiTap(count: Int)
    case restTwoTap(RelativeTapPosition)
    case restOneTwoSwipe(side: GestureSide, direction: GestureDirection)
    case multiSwipe(count: Int, direction: GestureDirection)
    case collapseToOne(count: Int, direction: GestureDirection?)
    case restThreeTap(GestureSide)
    case forceTouch(count: Int, corner: GestureCorner?)
}

enum GestureID: String, Codable, CaseIterable, Identifiable {
    case oneTopLeftTap, oneTopRightTap, oneBottomLeftTap, oneBottomRightTap
    case oneTopLeftClick, oneTopRightClick, oneBottomLeftClick, oneBottomRightClick
    case twoLeftEdgeSwipe
    case onePlusLeft, onePlusRight, onePlusLeftNear, onePlusRightNear
    case onePlusSwipeDownLeft, onePlusSwipeUpLeft, onePlusSwipeDownRight, onePlusSwipeUpRight
    case threeClick, threeTap, twoPlusCenter, twoPlusLeft, twoPlusRight
    case onePlusTwoSwipeDownLeft, onePlusTwoSwipeUpLeft, onePlusTwoSwipeDownRight, onePlusTwoSwipeUpRight
    case threeSwipeUp, threeSwipeDown, threeSwipeLeft, threeSwipeRight
    case threeToOne, threeToOneUp, threeToOneDown, threeToOneLeft, threeToOneRight
    case fourClick, fourTap, threePlusLeft, threePlusRight
    case fourSwipeUp, fourSwipeDown, fourSwipeLeft, fourSwipeRight
    case fourToOne, fourToOneUp, fourToOneDown, fourToOneLeft, fourToOneRight
    case fiveClick, fiveToOne, fiveToOneUp, fiveToOneDown, fiveToOneLeft, fiveToOneRight
    case oneTopLeftForce, oneTopRightForce, oneBottomLeftForce, oneBottomRightForce
    case oneForce, threeForce, fourForce

    var id: String { rawValue }
}

struct GestureDefinition: Identifiable, Hashable {
    let id: GestureID
    let title: String
    let category: GestureCategory
    let pattern: GesturePattern
    let symbol: String

    var searchableText: String {
        "\(title) \(category.rawValue) \(id.rawValue)"
    }
}

struct KeyboardShortcut: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64
    var displayText: String

    var eventFlags: CGEventFlags { CGEventFlags(rawValue: modifiers) }
}

struct ApplicationTarget: Codable, Hashable {
    var bundleIdentifier: String
    var displayName: String
    var path: String
}

enum BindingAction: Codable, Hashable {
    case keyboardShortcut(KeyboardShortcut)
    case launchApplication(ApplicationTarget)

    var kindTitle: String {
        switch self {
        case .keyboardShortcut: "Keyboard Shortcut"
        case .launchApplication: "Launch Application"
        }
    }

    var detailTitle: String {
        switch self {
        case let .keyboardShortcut(shortcut): shortcut.displayText
        case let .launchApplication(application): application.displayName
        }
    }
}

struct GestureBinding: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var gestureID: GestureID
    var action: BindingAction
    var enabled: Bool = true
}

enum Sensitivity: String, Codable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    var swipeThreshold: Double {
        switch self {
        case .low: 0.11
        case .medium: 0.07
        case .high: 0.045
        }
    }

    var stillnessThreshold: Double {
        switch self {
        case .low: 0.025
        case .medium: 0.035
        case .high: 0.05
        }
    }
}

struct AppSettings: Codable, Equatable {
    var gesturesEnabled = true
    var launchAtLogin = false
    var showMenuBarIcon = true
    var touchPrecision: Sensitivity = .medium
    var swipeSensitivity: Sensitivity = .medium
}

struct PersistedConfiguration: Codable {
    var schemaVersion: Int
    var bindings: [FailableDecodable<GestureBinding>]
    var settings: AppSettings
}

struct FailableDecodable<Value: Codable>: Codable {
    let value: Value?

    init(_ value: Value?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        guard let value else {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
            return
        }
        try value.encode(to: encoder)
    }
}
