import AppKit
import Foundation

private struct Point: Sendable, Equatable {
    var x: Double
    var y: Double

    static func -(lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func +(lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func /(lhs: Point, rhs: Double) -> Point {
        Point(x: lhs.x / rhs, y: lhs.y / rhs)
    }

    var magnitude: Double { hypot(x, y) }
}

private struct SessionFrame: Sendable {
    let timestamp: TimeInterval
    let contacts: [Int: TouchContact]
}

private struct GestureSession: Sendable {
    var frames: [SessionFrame] = []
    var physicalClick = false
    var forceTouch = false
    var consumed = false
    var appSwitcherStepper = ContinuousSwipeStepper()

    var maxTouches: Int { frames.map(\.contacts.count).max() ?? 0 }
    var startTime: TimeInterval { frames.first?.timestamp ?? 0 }
    var endTime: TimeInterval { frames.last?.timestamp ?? startTime }
}

struct ContinuousSwipeStepper: Sendable {
    static let defaultStepDistance = 0.055

    private var anchorX: Double?
    private let stepDistance: Double

    init(stepDistance: Double = Self.defaultStepDistance) {
        self.stepDistance = stepDistance
    }

    mutating func update(x: Double) -> Int {
        guard let anchorX else {
            self.anchorX = x
            return 0
        }
        let steps = Int((x - anchorX) / stepDistance)
        guard steps != 0 else { return 0 }
        self.anchorX = anchorX + Double(steps) * stepDistance
        return steps
    }
}

struct GestureEmissionGate {
    static let defaultCooldown: TimeInterval = 0.65

    private var lastEmissionByPattern: [GesturePattern: TimeInterval] = [:]
    private let cooldown: TimeInterval

    init(cooldown: TimeInterval = Self.defaultCooldown) {
        self.cooldown = cooldown
    }

    mutating func shouldEmit(_ pattern: GesturePattern, at timestamp: TimeInterval) -> Bool {
        if let previous = lastEmissionByPattern[pattern], timestamp - previous < cooldown {
            return false
        }
        lastEmissionByPattern[pattern] = timestamp
        return true
    }
}

final class GestureEngine: @unchecked Sendable {
    private weak var model: AppModel?
    private let executor: ActionExecutor?
    private let bridge = MultitouchBridge()
    private let queue = DispatchQueue(label: "app.flowpad.gesture-engine", qos: .userInteractive)
    private var session: GestureSession?
    private var settings = AppSettings()
    private var clickMonitor: Any?
    private var pressureMonitor: Any?
    private var silenceGeneration = 0
    private var emissionGate = GestureEmissionGate()

    @MainActor
    init(model: AppModel) {
        self.model = model
        executor = model.executor
        settings = model.settings
    }

    private init(testingSettings: AppSettings) {
        executor = nil
        settings = testingSettings
    }

    static func classifyForTesting(
        frames: [TouchFrame],
        physicalClick: Bool = false,
        forceTouch: Bool = false,
        settings: AppSettings = .init()
    ) -> GesturePattern? {
        let engine = GestureEngine(testingSettings: settings)
        let session = GestureSession(
            frames: frames.map { frame in
                SessionFrame(timestamp: frame.timestamp, contacts: engine.contactMap(frame.contacts))
            },
            physicalClick: physicalClick,
            forceTouch: forceTouch
        )
        return engine.classifyCompleted(session)
    }

    /// Returns the first pattern that would be emitted while the supplied frames arrive.
    /// This exercises the low-latency path used by the live engine.
    static func classifyLiveForTesting(
        frames: [TouchFrame],
        settings: AppSettings = .init()
    ) -> GesturePattern? {
        let engine = GestureEngine(testingSettings: settings)
        var session = GestureSession()
        var previousCount = 0
        for frame in frames {
            let contacts = engine.contactMap(frame.contacts)
            guard !contacts.isEmpty else { continue }
            session.frames.append(SessionFrame(timestamp: frame.timestamp, contacts: contacts))
            if let pattern = engine.classifyLive(session, previousCount: previousCount, currentCount: contacts.count) {
                return pattern
            }
            previousCount = contacts.count
        }
        return nil
    }

    @MainActor
    func start() {
        update(settings: model?.settings ?? .init())
        bridge.onFrame = { [weak self] frame in
            guard let engine = self else { return }
            engine.queue.async { engine.ingest(frame) }
        }

        do {
            try bridge.start()
            installEventMonitors()
            model?.updateEngineStatus(available: true, message: "Trackpad connected")
        } catch {
            model?.updateEngineStatus(available: false, message: error.localizedDescription)
        }
    }

    @MainActor
    func stop() {
        bridge.stop()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let pressureMonitor { NSEvent.removeMonitor(pressureMonitor) }
        clickMonitor = nil
        pressureMonitor = nil
    }

    @MainActor
    func update(settings: AppSettings) {
        queue.async { [weak self] in self?.settings = settings }
    }

    private func installEventMonitors() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let engine = self else { return }
            engine.queue.async {
                engine.session?.physicalClick = true
                engine.recognizeImmediateFlagIfPossible()
            }
        }
        pressureMonitor = NSEvent.addGlobalMonitorForEvents(matching: .pressure) { [weak self] event in
            guard event.stage >= 2 || event.pressure >= 0.75 else { return }
            guard let engine = self else { return }
            engine.queue.async {
                engine.session?.forceTouch = true
                engine.recognizeImmediateFlagIfPossible()
            }
        }
    }

    private func ingest(_ frame: TouchFrame) {
        let contacts = contactMap(frame.contacts)
        if contacts.isEmpty {
            guard session != nil else { return }
            silenceGeneration += 1
            let generation = silenceGeneration
            // MultitouchSupport briefly reports lifting/lingering paths. A tiny
            // grace period prevents a one-frame dropout from splitting a gesture,
            // while taps still complete in perceptually instant time.
            queue.asyncAfter(deadline: .now() + 0.035) { [weak self] in
                self?.finishAfterSilence(generation)
            }
            return
        }

        silenceGeneration += 1
        if session == nil { session = GestureSession() }
        let previousCount = session?.frames.last?.contacts.count ?? 0
        session?.frames.append(SessionFrame(timestamp: frame.timestamp, contacts: contacts))

        // The native app switcher behaves like a scrubber: while Command is
        // held, one continuous horizontal movement can cross many icons. This
        // path intentionally bypasses normal gesture bindings until the
        // switcher accepts its selection.
        if handleContinuousAppSwitcherNavigation(contacts) { return }

        // Keep a long resting finger cheap without losing the recent motion that
        // compound gestures need.
        if session?.frames.count ?? 0 > 1_800 {
            session?.frames.removeFirst(600)
        }

        guard let current = session, !current.consumed,
              let pattern = classifyLive(current, previousCount: previousCount, currentCount: contacts.count)
        else { return }
        emit(pattern)
        session?.consumed = true
    }

    private func handleContinuousAppSwitcherNavigation(_ contacts: [Int: TouchContact]) -> Bool {
        guard let executor, executor.isAppSwitcherActive else { return false }
        session?.consumed = true
        guard (2...5).contains(contacts.count),
              let x = centroid(SessionFrame(timestamp: 0, contacts: contacts))?.x
        else { return true }

        let steps = session?.appSwitcherStepper.update(x: x) ?? 0
        guard steps != 0 else { return true }
        let direction: AppSwitcherDirection = steps > 0 ? .next : .previous
        for _ in 0..<abs(steps) {
            guard executor.advanceAppSwitcherIfActive(direction) else { break }
        }
        return true
    }

    private func finishAfterSilence(_ generation: Int) {
        guard generation == silenceGeneration, let completed = session else { return }
        session = nil
        guard !completed.consumed, let pattern = classifyCompleted(completed) else { return }
        emit(pattern)
    }

    private func recognizeImmediateFlagIfPossible() {
        guard let current = session, !current.consumed,
              let pattern = classifyClickOrForce(current)
        else { return }
        emit(pattern)
        session?.consumed = true
    }

    private func emit(_ pattern: GesturePattern) {
        guard settings.gesturesEnabled else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard emissionGate.shouldEmit(pattern, at: now) else { return }
        Task { @MainActor [weak model] in
            model?.handleRecognized(pattern)
        }
    }

    private func classifyLive(
        _ session: GestureSession,
        previousCount: Int,
        currentCount: Int
    ) -> GesturePattern? {
        if let flagged = classifyClickOrForce(session) { return flagged }

        // A compound tap finishes when only the tapping finger(s) lift; the
        // resting fingers intentionally remain down.
        if currentCount < previousCount {
            if session.maxTouches == 2, currentCount == 1,
               let tap = classifyTwoFingerCompound(session, requireTapCompletion: true, allowSwipe: false) {
                return tap
            }
            if session.maxTouches == 3, currentCount == 2,
               let tap = classifyThreeFingerCompound(session, requireTapCompletion: true, allowSwipe: false) {
                return tap
            }
            if session.maxTouches == 4, currentCount == 3,
               let tap = classifyFourFingerCompound(session, requireTapCompletion: true) {
                return tap
            }
        }

        // Compound swipes fire as soon as the moving fingers cross the threshold.
        if session.maxTouches == 2,
           let compound = classifyTwoFingerCompound(session, requireTapCompletion: false, allowSwipe: true),
           isSwipePattern(compound) {
            return compound
        }
        if session.maxTouches == 3,
           let compound = classifyThreeFingerCompound(session, requireTapCompletion: false, allowSwipe: true),
           isSwipePattern(compound) {
            return compound
        }

        if currentCount == 2,
           let start = contiguousFrames(session, count: 2).first.flatMap(centroid),
           start.x < 0.10,
           let direction = coherentSwipeDirection(session, count: 2), direction == .right {
            return .edgeSwipeLeft
        }

        if (2...5).contains(currentCount),
           let direction = coherentSwipeDirection(session, count: currentCount) {
            return .multiSwipe(count: currentCount, direction: direction)
        }

        // Collapse gestures require a deliberate, stable one-finger phase. This
        // prevents normal asynchronous finger lifting from stealing every swipe.
        if currentCount == 1, let collapse = classifyCollapse(session) { return collapse }
        return nil
    }

    private func classifyCompleted(_ session: GestureSession) -> GesturePattern? {
        let count = session.maxTouches
        guard count > 0 else { return nil }

        if let flagged = classifyClickOrForce(session, preferMaximumCount: true) { return flagged }
        if count == 2, let compound = classifyTwoFingerCompound(session, requireTapCompletion: false, allowSwipe: true) {
            return compound
        }
        if count == 3, let compound = classifyThreeFingerCompound(session, requireTapCompletion: false, allowSwipe: true) {
            return compound
        }
        if count == 4, let compound = classifyFourFingerCompound(session, requireTapCompletion: false) {
            return compound
        }

        if count == 2,
           let start = longestContiguousFrames(session, count: 2).first.flatMap(centroid),
           start.x < 0.10,
           coherentSwipeDirection(session, count: 2, useLongestRun: true) == .right {
            return .edgeSwipeLeft
        }
        if (2...5).contains(count),
           let direction = coherentSwipeDirection(session, count: count, useLongestRun: true) {
            return .multiSwipe(count: count, direction: direction)
        }
        if let collapse = classifyCollapse(session) { return collapse }

        let run = longestContiguousFrames(session, count: count)
        guard let first = run.first, let last = run.last else { return nil }
        let duration = last.timestamp - first.timestamp
        let displacement = (centroid(last) ?? Point(x: 0, y: 0)) - (centroid(first) ?? Point(x: 0, y: 0))
        if duration <= 0.42, displacement.magnitude <= tapStillnessThreshold {
            if count == 1, let corner = corner(for: centroid(first)) { return .cornerTap(corner) }
            if [3, 4].contains(count), run.count >= 2 { return .multiTap(count: count) }
        }
        return nil
    }

    private func classifyClickOrForce(
        _ session: GestureSession,
        preferMaximumCount: Bool = false
    ) -> GesturePattern? {
        let count = preferMaximumCount
            ? session.maxTouches
            : (session.frames.last?.contacts.count ?? session.maxTouches)
        guard count > 0 else { return nil }
        if session.forceTouch {
            if count == 1, let corner = corner(for: session.frames.last.flatMap(centroid)) {
                return .forceTouch(count: 1, corner: corner)
            }
            if [1, 3, 4].contains(count) { return .forceTouch(count: count, corner: nil) }
        }
        if session.physicalClick {
            if count == 1, let corner = corner(for: session.frames.last.flatMap(centroid)) {
                return .cornerClick(corner)
            }
            if [3, 4, 5].contains(count) { return .multiClick(count: count) }
        }
        return nil
    }

    private func classifyTwoFingerCompound(
        _ session: GestureSession,
        requireTapCompletion: Bool,
        allowSwipe: Bool
    ) -> GesturePattern? {
        let appearances = contactAppearances(session).sorted { $0.value < $1.value }
        guard appearances.count == 2 else { return nil }
        let base = appearances[0]
        let added = appearances[1]
        guard added.value - base.value >= 0.075,
              let baseAtAdd = point(base.key, near: added.value, session),
              let addedStart = firstPoint(added.key, session),
              let addedEnd = lastPoint(added.key, session),
              baseMovement([base.key], since: added.value, session) <= restDriftThreshold
        else { return nil }

        let side: GestureSide = addedStart.x < baseAtAdd.x ? .left : .right
        let delta = addedEnd - addedStart
        if allowSwipe,
           abs(delta.y) >= swipeTriggerThreshold * 0.82,
           abs(delta.y) > abs(delta.x) * 1.12 {
            return .restOneSwipe(side: side, direction: delta.y > 0 ? .up : .down)
        }

        let currentIDs = session.frames.last?.contacts.keys ?? Dictionary<Int, TouchContact>().keys
        if requireTapCompletion, currentIDs.contains(added.key) { return nil }
        let lifetime = contactLifetime(added.key, session)
        guard lifetime <= 0.38, delta.magnitude <= tapStillnessThreshold else { return nil }
        let near = abs(addedStart.x - baseAtAdd.x) < 0.18
        return .restOneTap(side: side, near: near)
    }

    private func classifyThreeFingerCompound(
        _ session: GestureSession,
        requireTapCompletion: Bool,
        allowSwipe: Bool
    ) -> GesturePattern? {
        let appearances = contactAppearances(session).sorted { $0.value < $1.value }
        guard appearances.count == 3 else { return nil }
        let first = appearances[0]
        let second = appearances[1]
        let third = appearances[2]

        // One resting finger followed by a near-simultaneous two-finger swipe.
        if second.value - first.value >= 0.075,
           abs(third.value - second.value) <= 0.065 {
            let addedIDs = [second.key, third.key]
            let addedTime = min(second.value, third.value)
            if baseMovement([first.key], since: addedTime, session) <= restDriftThreshold,
               let baseAtAdd = point(first.key, near: addedTime, session),
               let addedStart = averagePoint(addedIDs, first: true, session),
               let addedEnd = averagePoint(addedIDs, first: false, session) {
                let side: GestureSide = addedStart.x < baseAtAdd.x ? .left : .right
                let delta = addedEnd - addedStart
                if allowSwipe,
                   abs(delta.y) >= swipeTriggerThreshold * 0.82,
                   abs(delta.y) > abs(delta.x) * 1.12,
                   coherentVerticalMovement(addedIDs, directionUp: delta.y > 0, session: session) {
                    return .restOneTwoSwipe(side: side, direction: delta.y > 0 ? .up : .down)
                }
            }
        }

        // Two resting fingers followed by one short tap.
        let baseIDs = [first.key, second.key]
        let baseReadyTime = max(first.value, second.value)
        guard third.value - baseReadyTime >= 0.075,
              baseMovement(baseIDs, since: third.value, session) <= restDriftThreshold,
              let thirdStart = firstPoint(third.key, session),
              let thirdEnd = lastPoint(third.key, session),
              let baseAtTap = averagePoint(baseIDs, near: third.value, session)
        else { return nil }

        let currentIDs = session.frames.last?.contacts.keys ?? Dictionary<Int, TouchContact>().keys
        if requireTapCompletion, currentIDs.contains(third.key) { return nil }
        guard contactLifetime(third.key, session) <= 0.38,
              (thirdEnd - thirdStart).magnitude <= tapStillnessThreshold
        else { return nil }

        let dx = thirdStart.x - baseAtTap.x
        let position: RelativeTapPosition = abs(dx) < 0.12 ? .center : (dx < 0 ? .left : .right)
        return .restTwoTap(position)
    }

    private func classifyFourFingerCompound(
        _ session: GestureSession,
        requireTapCompletion: Bool
    ) -> GesturePattern? {
        let appearances = contactAppearances(session).sorted { $0.value < $1.value }
        guard appearances.count == 4 else { return nil }
        let base = Array(appearances.prefix(3))
        let added = appearances[3]
        let baseReadyTime = base.map(\.value).max() ?? added.value
        let baseIDs = base.map(\.key)
        guard added.value - baseReadyTime >= 0.075,
              baseMovement(baseIDs, since: added.value, session) <= restDriftThreshold,
              let addedStart = firstPoint(added.key, session),
              let addedEnd = lastPoint(added.key, session),
              let baseAtTap = averagePoint(baseIDs, near: added.value, session)
        else { return nil }

        let currentIDs = session.frames.last?.contacts.keys ?? Dictionary<Int, TouchContact>().keys
        if requireTapCompletion, currentIDs.contains(added.key) { return nil }
        guard contactLifetime(added.key, session) <= 0.38,
              (addedEnd - addedStart).magnitude <= tapStillnessThreshold
        else { return nil }
        return .restThreeTap(addedStart.x < baseAtTap.x ? .left : .right)
    }

    private func classifyCollapse(_ session: GestureSession) -> GesturePattern? {
        let maxCount = session.maxTouches
        guard [3, 4, 5].contains(maxCount) else { return nil }
        let frames = session.frames
        guard let lastMaxIndex = frames.lastIndex(where: { $0.contacts.count == maxCount }),
              lastMaxIndex + 1 < frames.count,
              let oneStartIndex = frames[(lastMaxIndex + 1)...].firstIndex(where: { $0.contacts.count == 1 })
        else { return nil }

        let oneFrames = Array(frames[oneStartIndex...].prefix { $0.contacts.count == 1 })
        guard oneFrames.count >= 3,
              let first = oneFrames.first,
              let last = oneFrames.last,
              last.timestamp - first.timestamp >= 0.10,
              let survivorID = first.contacts.keys.first,
              oneFrames.allSatisfy({ $0.contacts[survivorID] != nil }),
              let start = first.contacts[survivorID].map(point),
              let end = last.contacts[survivorID].map(point)
        else { return nil }

        let delta = end - start
        let direction = delta.magnitude >= swipeTriggerThreshold * 0.78
            ? dominantDirection(delta, dominance: 1.08)
            : nil
        return .collapseToOne(count: maxCount, direction: direction)
    }

    private func coherentSwipeDirection(
        _ session: GestureSession,
        count: Int,
        useLongestRun: Bool = false
    ) -> GestureDirection? {
        let run = useLongestRun
            ? longestContiguousFrames(session, count: count)
            : contiguousFrames(session, count: count)
        guard run.count >= 3, let first = run.first, let last = run.last,
              last.timestamp - first.timestamp >= 0.018 else { return nil }
        let ids = Set(first.contacts.keys).intersection(last.contacts.keys)
        guard ids.count == count else { return nil }
        let deltas = ids.compactMap { id -> Point? in
            guard let start = first.contacts[id], let end = last.contacts[id] else { return nil }
            return point(end) - point(start)
        }
        return coherentDirection(deltas, threshold: swipeTriggerThreshold)
    }

    private func coherentDirection(_ deltas: [Point], threshold: Double) -> GestureDirection? {
        guard !deltas.isEmpty else { return nil }
        let average = deltas.reduce(Point(x: 0, y: 0), +) / Double(deltas.count)
        guard let direction = dominantDirection(average, dominance: 1.12) else { return nil }
        let projections = deltas.map { projection($0, direction) }
        let orthogonal = deltas.map { abs(orthogonalProjection($0, direction)) }
        let coherentCount = projections.filter { $0 >= threshold * 0.32 }.count
        let requiredCount = max(2, deltas.count - 1)
        guard projection(average, direction) >= threshold,
              coherentCount >= requiredCount,
              projections.allSatisfy({ $0 > -threshold * 0.12 }),
              (orthogonal.reduce(0, +) / Double(orthogonal.count)) < projection(average, direction) * 0.9
        else { return nil }
        return direction
    }

    private func coherentVerticalMovement(
        _ ids: [Int],
        directionUp: Bool,
        session: GestureSession
    ) -> Bool {
        let deltas = ids.compactMap { id -> Point? in
            guard let start = firstPoint(id, session), let end = lastPoint(id, session) else { return nil }
            return end - start
        }
        guard deltas.count == ids.count else { return false }
        let minimum = swipeTriggerThreshold * 0.28
        return deltas.allSatisfy { directionUp ? $0.y >= minimum : -$0.y >= minimum }
    }

    private var swipeTriggerThreshold: Double {
        settings.swipeSensitivity.swipeThreshold
    }

    private var tapStillnessThreshold: Double {
        settings.touchPrecision.stillnessThreshold
    }

    private var restDriftThreshold: Double {
        min(0.045, tapStillnessThreshold * 1.15)
    }

    private func isSwipePattern(_ pattern: GesturePattern) -> Bool {
        switch pattern {
        case .restOneSwipe, .restOneTwoSwipe, .multiSwipe, .edgeSwipeLeft:
            true
        default:
            false
        }
    }

    private func contactMap(_ contacts: [TouchContact]) -> [Int: TouchContact] {
        var result: [Int: TouchContact] = [:]
        for contact in contacts { result[contact.identifier] = contact }
        return result
    }

    private func contactAppearances(_ session: GestureSession) -> [Int: TimeInterval] {
        var result: [Int: TimeInterval] = [:]
        for frame in session.frames {
            for id in frame.contacts.keys where result[id] == nil { result[id] = frame.timestamp }
        }
        return result
    }

    private func contactLifetime(_ id: Int, _ session: GestureSession) -> TimeInterval {
        let timestamps = session.frames.compactMap { $0.contacts[id] == nil ? nil : $0.timestamp }
        guard let first = timestamps.first, let last = timestamps.last else { return .infinity }
        return last - first
    }

    private func firstPoint(_ id: Int, _ session: GestureSession) -> Point? {
        for frame in session.frames {
            if let contact = frame.contacts[id] { return point(contact) }
        }
        return nil
    }

    private func lastPoint(_ id: Int, _ session: GestureSession) -> Point? {
        for frame in session.frames.reversed() {
            if let contact = frame.contacts[id] { return point(contact) }
        }
        return nil
    }

    private func point(_ id: Int, near timestamp: TimeInterval, _ session: GestureSession) -> Point? {
        session.frames
            .filter { $0.contacts[id] != nil }
            .min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) })?
            .contacts[id]
            .map(point)
    }

    private func averagePoint(_ ids: [Int], first: Bool, _ session: GestureSession) -> Point? {
        let points = ids.compactMap { first ? firstPoint($0, session) : lastPoint($0, session) }
        return average(points)
    }

    private func averagePoint(_ ids: [Int], near timestamp: TimeInterval, _ session: GestureSession) -> Point? {
        average(ids.compactMap { point($0, near: timestamp, session) })
    }

    private func average(_ points: [Point]) -> Point? {
        guard !points.isEmpty else { return nil }
        return points.reduce(Point(x: 0, y: 0), +) / Double(points.count)
    }

    private func baseMovement(_ ids: [Int], since timestamp: TimeInterval, _ session: GestureSession) -> Double {
        ids.compactMap { id -> Double? in
            let points = session.frames
                .filter { $0.timestamp >= timestamp }
                .compactMap { $0.contacts[id].map(point) }
            guard let first = points.first, let last = points.last else { return nil }
            return (last - first).magnitude
        }.max() ?? .infinity
    }

    private func contiguousFrames(_ session: GestureSession, count: Int) -> [SessionFrame] {
        Array(session.frames.reversed().prefix { $0.contacts.count == count }.reversed())
    }

    private func longestContiguousFrames(_ session: GestureSession, count: Int) -> [SessionFrame] {
        var longest: [SessionFrame] = []
        var current: [SessionFrame] = []
        for frame in session.frames {
            if frame.contacts.count == count {
                current.append(frame)
                if current.count > longest.count { longest = current }
            } else {
                current.removeAll(keepingCapacity: true)
            }
        }
        return longest
    }

    private func centroid(_ frame: SessionFrame) -> Point? {
        average(frame.contacts.values.map(point))
    }

    private func point(_ contact: TouchContact) -> Point {
        Point(x: contact.x, y: contact.y)
    }

    private func dominantDirection(_ delta: Point, dominance: Double = 1) -> GestureDirection? {
        guard delta.magnitude > 0 else { return nil }
        if abs(delta.x) >= abs(delta.y) * dominance { return delta.x > 0 ? .right : .left }
        if abs(delta.y) >= abs(delta.x) * dominance { return delta.y > 0 ? .up : .down }
        return nil
    }

    private func projection(_ delta: Point, _ direction: GestureDirection) -> Double {
        switch direction {
        case .up: delta.y
        case .down: -delta.y
        case .left: -delta.x
        case .right: delta.x
        }
    }

    private func orthogonalProjection(_ delta: Point, _ direction: GestureDirection) -> Double {
        switch direction {
        case .up, .down: delta.x
        case .left, .right: delta.y
        }
    }

    private func corner(for point: Point?) -> GestureCorner? {
        guard let point else { return nil }
        let margin = 0.24
        if point.x <= margin, point.y >= 1 - margin { return .topLeft }
        if point.x >= 1 - margin, point.y >= 1 - margin { return .topRight }
        if point.x <= margin, point.y <= margin { return .bottomLeft }
        if point.x >= 1 - margin, point.y <= margin { return .bottomRight }
        return nil
    }
}
