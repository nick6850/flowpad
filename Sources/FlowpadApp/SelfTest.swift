import Foundation
import CoreGraphics

enum SelfTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): message
        }
    }
}

enum SelfTest {
    static func run() throws {
        try require(GestureCatalog.all.count == 61, "catalog must contain 61 gestures")
        try require(Set(GestureCatalog.all.map(\.id)).count == 61, "gesture IDs must be unique")
        try require(Set(GestureCatalog.all.map(\.pattern)).count == 61, "gesture patterns must be unique")

        let expectedCounts: [GestureCategory: Int] = [
            .oneFinger: 8,
            .twoFinger: 9,
            .threeFinger: 18,
            .fourFinger: 13,
            .fiveFinger: 6,
            .forceTouch: 7
        ]
        for (category, expectedCount) in expectedCounts {
            try require(
                GestureCatalog.definitions(in: category).count == expectedCount,
                "unexpected count for \(category.rawValue)"
            )
        }

        try testConfigurationRoundTrip()
        try testLegacySystemActionMigration()
        try testMalformedBindingIsolation()
        try testKeyboardEventPlan()
        try testShortcutCapture()
        try testContinuousAppSwitcherNavigation()
        try testGestureEmissionGate()
        try testRecognizerFamilies()
        try testEveryCatalogGesture()
    }

    private static func testConfigurationRoundTrip() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowpadSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = ConfigurationStore(baseDirectory: temporaryDirectory)
        let shortcut = KeyboardShortcut(
            keyCode: 49,
            modifiers: CGEventFlags.maskAlternate.rawValue,
            displayText: "⌥ Space"
        )
        let binding = GestureBinding(gestureID: .threeSwipeUp, action: .keyboardShortcut(shortcut))
        let folderBinding = GestureBinding(
            gestureID: .threeSwipeDown,
            action: .openFolder(FolderTarget(displayName: "Downloads", path: "/tmp/Downloads"))
        )
        let systemBinding = GestureBinding(
            gestureID: .fourSwipeLeft,
            action: .systemAction(.missionControl)
        )
        var settings = AppSettings()
        settings.swipeSensitivity = .high

        let expectedBindings = [binding, folderBinding, systemBinding]
        try store.save(bindings: expectedBindings, settings: settings)
        let loaded = store.load()
        try require(loaded.bindings == expectedBindings, "configuration binding round-trip failed")
        try require(loaded.settings == settings, "configuration settings round-trip failed")
        try require(loaded.discardedBindings == 0, "healthy binding was discarded")
    }

    private static func testLegacySystemActionMigration() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowpadSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = ConfigurationStore(baseDirectory: temporaryDirectory)
        let legacyBinding = GestureBinding(
            gestureID: .threeSwipeRight,
            action: .keyboardShortcut(KeyboardShortcut(
                keyCode: 48,
                modifiers: CGEventFlags.maskCommand.rawValue,
                displayText: "⌘ Tab"
            ))
        )
        try store.save(bindings: [legacyBinding], settings: .init())

        let loaded = store.load()
        try require(
            loaded.bindings.first?.action == .systemAction(.switchApplication),
            "saved Command-Tab did not migrate to the semantic app switcher"
        )
    }

    private static func testMalformedBindingIsolation() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowpadSelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let store = ConfigurationStore(baseDirectory: temporaryDirectory)
        let shortcut = KeyboardShortcut(keyCode: 11, modifiers: 0, displayText: "B")
        let first = GestureBinding(gestureID: .threeSwipeLeft, action: .keyboardShortcut(shortcut))
        let second = GestureBinding(gestureID: .threeSwipeRight, action: .keyboardShortcut(shortcut))
        try store.save(bindings: [first, second], settings: .init())

        var source = try String(contentsOf: store.configurationURL, encoding: .utf8)
        source = source.replacingOccurrences(of: GestureID.threeSwipeRight.rawValue, with: "invalidGesture")
        try source.write(to: store.configurationURL, atomically: true, encoding: .utf8)

        let loaded = store.load()
        try require(loaded.bindings.count == 1, "malformed binding was not isolated")
        try require(loaded.bindings.first?.gestureID == .threeSwipeLeft, "healthy binding was lost")
        try require(loaded.discardedBindings == 1, "discarded binding count is wrong")
    }

    private static func testKeyboardEventPlan() throws {
        let commandB = KeyboardShortcut(
            keyCode: 11,
            modifiers: CGEventFlags.maskCommand.rawValue,
            displayText: "⌘ B"
        )
        let commandPlan = ActionExecutor.eventPlan(for: commandB)
        try require(commandPlan == [
            KeyboardEventStep(keyCode: 55, keyDown: true, flags: .maskCommand),
            KeyboardEventStep(keyCode: 11, keyDown: true, flags: .maskCommand),
            KeyboardEventStep(keyCode: 11, keyDown: false, flags: .maskCommand),
            KeyboardEventStep(keyCode: 55, keyDown: false, flags: [])
        ], "Command shortcut must include explicit modifier transitions")

        let optionCommandI = KeyboardShortcut(
            keyCode: 34,
            modifiers: (CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue),
            displayText: "⌥ ⌘ I"
        )
        let combinedPlan = ActionExecutor.eventPlan(for: optionCommandI)
        try require(combinedPlan.map(\.keyCode) == [58, 55, 34, 34, 55, 58], "modifier ordering is unstable")
        try require(combinedPlan.last?.flags.isEmpty == true, "modifier release leaked flags")

        let commandTab = KeyboardShortcut(
            keyCode: 48,
            modifiers: CGEventFlags.maskCommand.rawValue,
            displayText: "⌘ Tab"
        )
        try require(
            SystemAction.inferred(from: commandTab) == .switchApplication,
            "legacy Command-Tab did not migrate to Switch Application"
        )
        try require(
            ActionExecutor.appSwitcherReleaseDelay == 1.0,
            "app switcher release delay changed unexpectedly"
        )
        try require(
            ActionExecutor.appSwitcherDirection(for: .multiSwipe(count: 2, direction: .right)) == .next,
            "two-finger right swipe cannot advance the active app switcher"
        )
        try require(
            ActionExecutor.appSwitcherDirection(for: .multiSwipe(count: 4, direction: .left)) == .previous,
            "four-finger left swipe cannot reverse the active app switcher"
        )
        try require(
            ActionExecutor.appSwitcherDirection(for: .multiSwipe(count: 3, direction: .up)) == nil,
            "vertical swipe was incorrectly consumed by the app switcher"
        )
        try require(SystemAction.inferred(from: commandB) == nil, "ordinary Command shortcut migrated")

        let commandBacktick = KeyboardShortcut(
            keyCode: 50,
            modifiers: CGEventFlags.maskCommand.rawValue,
            displayText: "⌘ `"
        )
        try require(
            SystemAction.inferred(from: commandBacktick) == nil,
            "Command-backtick was incorrectly migrated to Switch Application"
        )
    }

    private static func testShortcutCapture() throws {
        try require(
            ShortcutText.displayModifiers([.maskAlternate, .maskCommand]) == "⌥ ⌘",
            "live modifier preview is unstable"
        )
        var commandTab = ShortcutCaptureState()
        try require(
            commandTab.handle(type: .flagsChanged, keyCode: 55, flags: .maskCommand) == .preview("⌘"),
            "modifier press was not shown in the live preview"
        )
        try require(
            commandTab.handle(type: .keyDown, keyCode: 48, flags: .maskCommand) == .capture(
                KeyboardShortcut(
                    keyCode: 48,
                    modifiers: CGEventFlags.maskCommand.rawValue,
                    displayText: "⌘ Tab"
                )
            ),
            "Command-Tab was not captured"
        )
        try require(
            commandTab.handle(type: .keyUp, keyCode: 48, flags: .maskCommand) == .none,
            "recorder stopped before Command was released"
        )
        try require(
            commandTab.handle(type: .flagsChanged, keyCode: 55, flags: []) == .finish,
            "recorder did not stop after all keys were released"
        )

        var commandBacktick = ShortcutCaptureState()
        _ = commandBacktick.handle(type: .flagsChanged, keyCode: 55, flags: .maskCommand)
        try require(
            commandBacktick.handle(type: .keyDown, keyCode: 50, flags: .maskCommand) == .capture(
                KeyboardShortcut(
                    keyCode: 50,
                    modifiers: CGEventFlags.maskCommand.rawValue,
                    displayText: "⌘ `"
                )
            ),
            "Command-backtick was not captured"
        )
        try require(
            commandBacktick.handle(type: .keyUp, keyCode: 50, flags: .maskCommand) == .none,
            "Command-backtick stopped before Command was released"
        )
        try require(
            commandBacktick.handle(type: .flagsChanged, keyCode: 55, flags: []) == .finish,
            "Command-backtick did not release the recorder"
        )

        var escape = ShortcutCaptureState()
        try require(
            escape.handle(type: .keyDown, keyCode: 53, flags: []) == .cancel,
            "Escape must cancel shortcut recording"
        )
        try require(
            escape.handle(type: .keyUp, keyCode: 53, flags: []) == .finish,
            "Escape cancellation did not release the recorder"
        )
    }

    private static func testGestureEmissionGate() throws {
        var gate = GestureEmissionGate()
        let restTap = GesturePattern.restTwoTap(.right)
        try require(gate.shouldEmit(restTap, at: 10), "first gesture was incorrectly blocked")
        try require(!gate.shouldEmit(restTap, at: 10.12), "120 ms duplicate was not blocked")
        try require(!gate.shouldEmit(restTap, at: 10.50), "same physical gesture escaped cooldown")
        try require(gate.shouldEmit(restTap, at: 10.65), "next deliberate gesture stayed blocked")

        try require(
            gate.shouldEmit(.multiSwipe(count: 3, direction: .left), at: 10.20),
            "one gesture incorrectly blocked a different pattern"
        )
    }

    private static func testContinuousAppSwitcherNavigation() throws {
        var stepper = ContinuousSwipeStepper(stepDistance: 0.05)
        try require(stepper.update(x: 0.30) == 0, "app switcher scrubber lacks an anchor")
        try require(stepper.update(x: 0.34) == 0, "app switcher scrubber advanced too early")
        try require(stepper.update(x: 0.41) == 2, "continuous right swipe did not cross two icons")
        try require(stepper.update(x: 0.34) == -1, "continuous reversal did not move left")
        try require(stepper.update(x: 0.19) == -3, "long continuous swipe did not traverse multiple icons")
    }

    private static func testRecognizerFamilies() throws {
        let cornerTap = GestureEngine.classifyForTesting(frames: [
            frame(0, [contact(1, 0.05, 0.95)]),
            frame(0.12, [contact(1, 0.052, 0.949)])
        ])
        try require(cornerTap == .cornerTap(.topLeft), "corner tap recognition failed")

        let twoSwipe = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [contact(1, 0.30, 0.45), contact(2, 0.55, 0.45)]),
            frame(0.03, [contact(1, 0.30, 0.45), contact(2, 0.55, 0.45)]),
            frame(0.07, [contact(1, 0.35, 0.45), contact(2, 0.60, 0.45)]),
            frame(0.10, [contact(1, 0.41, 0.45), contact(2, 0.66, 0.45)])
        ])
        try require(
            twoSwipe == .multiSwipe(count: 2, direction: .right),
            "two-finger app-switcher navigation swipe recognition failed"
        )

        let threeSwipe = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [contact(1, 0.30, 0.25)]),
            frame(0.02, [contact(1, 0.30, 0.25), contact(2, 0.50, 0.25)]),
            frame(0.04, [contact(1, 0.30, 0.25), contact(2, 0.50, 0.25), contact(3, 0.70, 0.25)]),
            frame(0.07, [contact(1, 0.30, 0.25), contact(2, 0.50, 0.25), contact(3, 0.70, 0.25)]),
            frame(0.10, [contact(1, 0.30, 0.28), contact(2, 0.50, 0.28), contact(3, 0.70, 0.28)]),
            frame(0.13, [contact(1, 0.30, 0.34), contact(2, 0.50, 0.34), contact(3, 0.70, 0.34)])
        ])
        try require(threeSwipe == .multiSwipe(count: 3, direction: .up), "three-finger swipe recognition failed")

        let fourSwipe = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [
                contact(1, 0.25, 0.70), contact(2, 0.42, 0.70),
                contact(3, 0.59, 0.70), contact(4, 0.76, 0.70)
            ]),
            frame(0.03, [
                contact(1, 0.25, 0.70), contact(2, 0.42, 0.70),
                contact(3, 0.59, 0.70), contact(4, 0.76, 0.70)
            ]),
            frame(0.06, [
                contact(1, 0.25, 0.66), contact(2, 0.42, 0.66),
                contact(3, 0.59, 0.66), contact(4, 0.76, 0.66)
            ]),
            frame(0.09, [
                contact(1, 0.25, 0.61), contact(2, 0.42, 0.61),
                contact(3, 0.59, 0.61), contact(4, 0.76, 0.61)
            ])
        ])
        try require(fourSwipe == .multiSwipe(count: 4, direction: .down), "four-finger live swipe recognition failed")

        let restOneTap = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [contact(1, 0.4, 0.5)]),
            frame(0.1, [contact(1, 0.4, 0.5), contact(2, 0.72, 0.5)]),
            frame(0.17, [contact(1, 0.4, 0.5), contact(2, 0.721, 0.5)]),
            frame(0.20, [contact(1, 0.4, 0.5)])
        ])
        try require(restOneTap == .restOneTap(side: .right, near: false), "rest-one tap recognition failed")

        let restTwoTap = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [contact(1, 0.35, 0.5), contact(2, 0.50, 0.5)]),
            frame(0.08, [contact(1, 0.35, 0.5), contact(2, 0.50, 0.5)]),
            frame(0.14, [contact(1, 0.35, 0.5), contact(2, 0.50, 0.5), contact(3, 0.76, 0.5)]),
            frame(0.20, [contact(1, 0.35, 0.5), contact(2, 0.50, 0.5), contact(3, 0.761, 0.5)]),
            frame(0.23, [contact(1, 0.35, 0.5), contact(2, 0.50, 0.5)])
        ])
        try require(restTwoTap == .restTwoTap(.right), "rest-two tap recognition failed")

        let restThreeTap = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [contact(1, 0.34, 0.5), contact(2, 0.46, 0.5), contact(3, 0.58, 0.5)]),
            frame(0.10, [contact(1, 0.34, 0.5), contact(2, 0.46, 0.5), contact(3, 0.58, 0.5)]),
            frame(0.18, [
                contact(1, 0.34, 0.5), contact(2, 0.46, 0.5),
                contact(3, 0.58, 0.5), contact(4, 0.82, 0.5)
            ]),
            frame(0.24, [
                contact(1, 0.34, 0.5), contact(2, 0.46, 0.5),
                contact(3, 0.58, 0.5), contact(4, 0.821, 0.5)
            ]),
            frame(0.27, [contact(1, 0.34, 0.5), contact(2, 0.46, 0.5), contact(3, 0.58, 0.5)])
        ])
        try require(restThreeTap == .restThreeTap(.right), "rest-three tap recognition failed")

        let restOneSwipe = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [contact(1, 0.42, 0.5)]),
            frame(0.10, [contact(1, 0.42, 0.5), contact(2, 0.72, 0.52)]),
            frame(0.13, [contact(1, 0.42, 0.5), contact(2, 0.72, 0.49)]),
            frame(0.16, [contact(1, 0.42, 0.5), contact(2, 0.72, 0.43)])
        ])
        try require(
            restOneSwipe == .restOneSwipe(side: .right, direction: .down),
            "rest-one swipe recognition failed"
        )

        // A finger landing early must not turn a normal coherent three-finger
        // swipe into a compound gesture when that finger moves with the others.
        let staggeredThreeSwipe = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [contact(1, 0.30, 0.3)]),
            frame(0.09, [contact(1, 0.30, 0.3), contact(2, 0.50, 0.3), contact(3, 0.70, 0.3)]),
            frame(0.12, [contact(1, 0.33, 0.3), contact(2, 0.53, 0.3), contact(3, 0.73, 0.3)]),
            frame(0.16, [contact(1, 0.39, 0.3), contact(2, 0.59, 0.3), contact(3, 0.79, 0.3)])
        ])
        try require(
            staggeredThreeSwipe == .multiSwipe(count: 3, direction: .right),
            "staggered three-finger swipe was misclassified"
        )

        let unevenLiftTap = GestureEngine.classifyForTesting(frames: [
            frame(0, [contact(1, 0.3, 0.4), contact(2, 0.5, 0.4), contact(3, 0.7, 0.4)]),
            frame(0.1, [contact(1, 0.3, 0.4), contact(2, 0.5, 0.4), contact(3, 0.7, 0.4)]),
            frame(0.13, [contact(1, 0.3, 0.4)])
        ])
        try require(unevenLiftTap == .multiTap(count: 3), "uneven finger lift broke multi-tap")

        let accidentalOneFrameCollapse = GestureEngine.classifyForTesting(frames: [
            frame(0, [contact(1, 0.3, 0.4), contact(2, 0.5, 0.4), contact(3, 0.7, 0.4)]),
            frame(0.06, [contact(1, 0.3, 0.4), contact(2, 0.5, 0.4), contact(3, 0.7, 0.4)]),
            frame(0.09, [contact(1, 0.3, 0.4)])
        ])
        try require(
            accidentalOneFrameCollapse != .collapseToOne(count: 3, direction: nil),
            "one-frame lift transition was mistaken for collapse"
        )

        let incoherentMovement = GestureEngine.classifyLiveForTesting(frames: [
            frame(0, [contact(1, 0.3, 0.4), contact(2, 0.5, 0.4), contact(3, 0.7, 0.4)]),
            frame(0.03, [contact(1, 0.3, 0.4), contact(2, 0.5, 0.4), contact(3, 0.7, 0.4)]),
            frame(0.08, [contact(1, 0.58, 0.4), contact(2, 0.5, 0.4), contact(3, 0.7, 0.4)])
        ])
        try require(incoherentMovement == nil, "one moving finger triggered a multi-finger swipe")

        let collapse = GestureEngine.classifyForTesting(frames: [
            frame(0, [contact(1, 0.4, 0.3), contact(2, 0.5, 0.3), contact(3, 0.6, 0.3), contact(4, 0.7, 0.3)]),
            frame(0.1, [contact(1, 0.4, 0.3), contact(2, 0.5, 0.3), contact(3, 0.6, 0.3), contact(4, 0.7, 0.3)]),
            frame(0.2, [contact(1, 0.4, 0.4)]),
            frame(0.27, [contact(1, 0.4, 0.49)]),
            frame(0.34, [contact(1, 0.4, 0.66)])
        ])
        try require(collapse == .collapseToOne(count: 4, direction: .up), "collapse-to-one recognition failed")

        let force = GestureEngine.classifyForTesting(
            frames: [frame(0, [contact(1, 0.94, 0.06)])],
            forceTouch: true
        )
        try require(force == .forceTouch(count: 1, corner: .bottomRight), "force touch recognition failed")
    }

    private static func testEveryCatalogGesture() throws {
        for definition in GestureCatalog.all {
            let recognized = recognizeFixture(for: definition.pattern)
            try require(
                recognized == definition.pattern,
                "fixture for \(definition.id.rawValue) produced \(String(describing: recognized))"
            )
        }
    }

    private static func recognizeFixture(for pattern: GesturePattern) -> GesturePattern? {
        switch pattern {
        case let .cornerTap(corner):
            let position = cornerPosition(corner)
            return GestureEngine.classifyForTesting(frames: [
                frame(0, [contact(1, position.x, position.y)]),
                frame(0.12, [contact(1, position.x + 0.001, position.y)])
            ])

        case let .cornerClick(corner):
            let position = cornerPosition(corner)
            return GestureEngine.classifyForTesting(
                frames: [frame(0, [contact(1, position.x, position.y)])],
                physicalClick: true
            )

        case .edgeSwipeLeft:
            let start = [contact(1, 0.03, 0.45), contact(2, 0.08, 0.58)]
            return GestureEngine.classifyLiveForTesting(frames: [
                frame(0, start),
                frame(0.03, shifted(start, dx: 0.025, dy: 0)),
                frame(0.07, shifted(start, dx: 0.09, dy: 0))
            ])

        case let .restOneTap(side, near):
            let base = contact(1, 0.50, 0.50)
            let distance = near ? 0.14 : 0.34
            let x = side == .left ? 0.50 - distance : 0.50 + distance
            let added = contact(2, x, 0.50)
            return GestureEngine.classifyLiveForTesting(frames: [
                frame(0, [base]),
                frame(0.10, [base, added]),
                frame(0.17, [base, contact(2, x + 0.001, 0.50)]),
                frame(0.20, [base])
            ])

        case let .restOneSwipe(side, direction):
            let base = contact(1, 0.50, 0.50)
            let x = side == .left ? 0.20 : 0.80
            let dy = direction == .up ? 0.09 : -0.09
            return GestureEngine.classifyLiveForTesting(frames: [
                frame(0, [base]),
                frame(0.10, [base, contact(2, x, 0.50)]),
                frame(0.13, [base, contact(2, x, 0.50 + dy * 0.35)]),
                frame(0.17, [base, contact(2, x, 0.50 + dy)])
            ])

        case let .multiClick(count):
            return GestureEngine.classifyForTesting(
                frames: [frame(0, evenlySpacedContacts(count: count))],
                physicalClick: true
            )

        case let .multiTap(count):
            let touches = evenlySpacedContacts(count: count)
            return GestureEngine.classifyForTesting(frames: [
                frame(0, touches),
                frame(0.13, shifted(touches, dx: 0.001, dy: 0))
            ])

        case let .restTwoTap(position):
            let base = [contact(1, 0.42, 0.50), contact(2, 0.58, 0.50)]
            let x: Double = switch position {
            case .left: 0.20
            case .center: 0.50
            case .right: 0.80
            }
            return GestureEngine.classifyLiveForTesting(frames: [
                frame(0, base),
                frame(0.10, base),
                frame(0.18, base + [contact(3, x, 0.50)]),
                frame(0.25, base + [contact(3, x + 0.001, 0.50)]),
                frame(0.28, base)
            ])

        case let .restOneTwoSwipe(side, direction):
            let base = contact(1, 0.50, 0.50)
            let xs = side == .left ? [0.18, 0.32] : [0.68, 0.82]
            let dy = direction == .up ? 0.09 : -0.09
            return GestureEngine.classifyLiveForTesting(frames: [
                frame(0, [base]),
                frame(0.10, [base, contact(2, xs[0], 0.50), contact(3, xs[1], 0.50)]),
                frame(0.13, [
                    base,
                    contact(2, xs[0], 0.50 + dy * 0.35),
                    contact(3, xs[1], 0.50 + dy * 0.35)
                ]),
                frame(0.17, [
                    base,
                    contact(2, xs[0], 0.50 + dy),
                    contact(3, xs[1], 0.50 + dy)
                ])
            ])

        case let .multiSwipe(count, direction):
            let start = evenlySpacedContacts(count: count)
            let delta = directionDelta(direction, amount: 0.09)
            return GestureEngine.classifyLiveForTesting(frames: [
                frame(0, start),
                frame(0.03, shifted(start, dx: delta.x * 0.3, dy: delta.y * 0.3)),
                frame(0.07, shifted(start, dx: delta.x, dy: delta.y))
            ])

        case let .collapseToOne(count, direction):
            let initial = evenlySpacedContacts(count: count)
            let delta = direction.map { directionDelta($0, amount: 0.14) } ?? (x: 0.0, y: 0.0)
            return GestureEngine.classifyForTesting(frames: [
                frame(0, initial),
                frame(0.08, initial),
                frame(0.18, [contact(1, 0.50, 0.50)]),
                frame(0.25, [contact(1, 0.50 + delta.x * 0.4, 0.50 + delta.y * 0.4)]),
                frame(0.32, [contact(1, 0.50 + delta.x, 0.50 + delta.y)])
            ])

        case let .restThreeTap(side):
            let base = [
                contact(1, 0.36, 0.50), contact(2, 0.50, 0.50), contact(3, 0.64, 0.50)
            ]
            let x = side == .left ? 0.16 : 0.84
            return GestureEngine.classifyLiveForTesting(frames: [
                frame(0, base),
                frame(0.10, base),
                frame(0.18, base + [contact(4, x, 0.50)]),
                frame(0.24, base + [contact(4, x + 0.001, 0.50)]),
                frame(0.27, base)
            ])

        case let .forceTouch(count, corner):
            let touches: [TouchContact]
            if let corner {
                let position = cornerPosition(corner)
                touches = [contact(1, position.x, position.y)]
            } else {
                touches = evenlySpacedContacts(count: count)
            }
            return GestureEngine.classifyForTesting(
                frames: [frame(0, touches)],
                forceTouch: true
            )
        }
    }

    private static func evenlySpacedContacts(count: Int) -> [TouchContact] {
        (0..<count).map { index in
            let x = 0.24 + Double(index) * (0.52 / Double(max(1, count - 1)))
            return contact(index + 1, x, 0.50)
        }
    }

    private static func shifted(_ contacts: [TouchContact], dx: Double, dy: Double) -> [TouchContact] {
        contacts.map { contact($0.identifier, $0.x + dx, $0.y + dy) }
    }

    private static func directionDelta(
        _ direction: GestureDirection,
        amount: Double
    ) -> (x: Double, y: Double) {
        switch direction {
        case .up: (0, amount)
        case .down: (0, -amount)
        case .left: (-amount, 0)
        case .right: (amount, 0)
        }
    }

    private static func cornerPosition(_ corner: GestureCorner) -> (x: Double, y: Double) {
        switch corner {
        case .topLeft: (0.06, 0.94)
        case .topRight: (0.94, 0.94)
        case .bottomLeft: (0.06, 0.06)
        case .bottomRight: (0.94, 0.06)
        }
    }

    private static func contact(_ id: Int, _ x: Double, _ y: Double) -> TouchContact {
        TouchContact(identifier: id, x: x, y: y, size: 1, density: 1)
    }

    private static func frame(_ timestamp: TimeInterval, _ contacts: [TouchContact]) -> TouchFrame {
        TouchFrame(timestamp: timestamp, contacts: contacts)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelfTestError.failed(message) }
    }
}
