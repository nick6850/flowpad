import Darwin
import Foundation

struct TouchContact: Sendable, Equatable {
    let identifier: Int
    let x: Double
    let y: Double
    let size: Double
    let density: Double
}

struct TouchFrame: Sendable {
    let timestamp: TimeInterval
    let contacts: [TouchContact]
}

private struct MTPoint {
    var x: Float
    var y: Float
}

private struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

private struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var unknown1: Int32
    var unknown2: Int32
    var normalized: MTVector
    var size: Float
    var unknown3: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var millimeters: MTVector
    var unknown4: Int32
    var unknown5: Int32
    var density: Float
}

private typealias MTContactCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

private typealias MTDeviceCreateDefaultFunction = @convention(c) () -> UnsafeMutableRawPointer?
private typealias MTRegisterCallbackFunction = @convention(c) (UnsafeMutableRawPointer?, MTContactCallback) -> Void
private typealias MTUnregisterCallbackFunction = @convention(c) (UnsafeMutableRawPointer?, MTContactCallback) -> Void
private typealias MTDeviceStartFunction = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
private typealias MTDeviceStopFunction = @convention(c) (UnsafeMutableRawPointer?) -> Void

final class MultitouchBridge: @unchecked Sendable {
    enum BridgeError: LocalizedError {
        case frameworkUnavailable
        case symbolMissing(String)
        case deviceUnavailable

        var errorDescription: String? {
            switch self {
            case .frameworkUnavailable:
                "The macOS MultitouchSupport framework is unavailable."
            case let .symbolMissing(symbol):
                "The MultitouchSupport symbol \(symbol) is unavailable."
            case .deviceUnavailable:
                "No built-in trackpad was detected."
            }
        }
    }

    var onFrame: (@Sendable (TouchFrame) -> Void)?

    private var library: UnsafeMutableRawPointer?
    private var device: UnsafeMutableRawPointer?
    private var registerCallback: MTRegisterCallbackFunction?
    private var unregisterCallback: MTUnregisterCallbackFunction?
    private var startDevice: MTDeviceStartFunction?
    private var stopDevice: MTDeviceStopFunction?
    private var isRunning = false

    private static let callback: MTContactCallback = { _, fingerBytes, count, timestamp, _ in
        guard let fingerBytes, count >= 0 else { return 0 }
        let fingers = fingerBytes.bindMemory(to: MTFinger.self, capacity: Int(count))
        var contacts: [TouchContact] = []
        contacts.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let finger = fingers[index]
            // MultitouchSupport keeps reporting a path while it is lifting,
            // lingering and leaving the sensor (states 5...7). Treating those
            // paths as live fingers makes the count oscillate at gesture end.
            guard finger.state == 3 || finger.state == 4 else { continue }
            contacts.append(
                TouchContact(
                    identifier: Int(finger.identifier),
                    x: Double(finger.normalized.position.x),
                    y: Double(finger.normalized.position.y),
                    size: Double(finger.size),
                    density: Double(finger.density)
                )
            )
        }
        MultitouchCallbackRouter.shared.deliver(TouchFrame(timestamp: timestamp, contacts: contacts))
        return 0
    }

    func start() throws {
        guard !isRunning else { return }
        let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let library = dlopen(frameworkPath, RTLD_NOW | RTLD_LOCAL) else {
            throw BridgeError.frameworkUnavailable
        }
        self.library = library

        let create: MTDeviceCreateDefaultFunction = try load("MTDeviceCreateDefault", from: library)
        let register: MTRegisterCallbackFunction = try load("MTRegisterContactFrameCallback", from: library)
        let unregister: MTUnregisterCallbackFunction = try load("MTUnregisterContactFrameCallback", from: library)
        let start: MTDeviceStartFunction = try load("MTDeviceStart", from: library)
        let stop: MTDeviceStopFunction = try load("MTDeviceStop", from: library)

        guard let device = create() else { throw BridgeError.deviceUnavailable }
        self.device = device
        registerCallback = register
        unregisterCallback = unregister
        startDevice = start
        stopDevice = stop

        MultitouchCallbackRouter.shared.bridge = self
        register(device, Self.callback)
        start(device, 0)
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        if let device {
            stopDevice?(device)
            unregisterCallback?(device, Self.callback)
        }
        if MultitouchCallbackRouter.shared.bridge === self {
            MultitouchCallbackRouter.shared.bridge = nil
        }
        device = nil
        isRunning = false
        if let library {
            dlclose(library)
            self.library = nil
        }
    }

    deinit {
        stop()
    }

    fileprivate func deliver(_ frame: TouchFrame) {
        onFrame?(frame)
    }

    private func load<T>(_ name: String, from library: UnsafeMutableRawPointer) throws -> T {
        guard let symbol = dlsym(library, name) else { throw BridgeError.symbolMissing(name) }
        return unsafeBitCast(symbol, to: T.self)
    }
}

private final class MultitouchCallbackRouter: @unchecked Sendable {
    static let shared = MultitouchCallbackRouter()
    weak var bridge: MultitouchBridge?

    func deliver(_ frame: TouchFrame) {
        bridge?.deliver(frame)
    }
}
