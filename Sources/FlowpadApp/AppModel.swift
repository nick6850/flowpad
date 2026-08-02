import Combine
import Foundation
import ServiceManagement

enum AppSection: String, CaseIterable, Identifiable {
    case trackpad = "Trackpad"
    case settings = "Settings"

    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var selectedSection: AppSection = .trackpad
    @Published private(set) var bindings: [GestureBinding]
    @Published private(set) var settings: AppSettings
    @Published private(set) var engineAvailable = false
    @Published private(set) var engineStatus = "Starting gesture engine…"
    @Published private(set) var lastDetectedGesture: GestureID?
    @Published var notice: String?

    let store: ConfigurationStore
    let executor = ActionExecutor()
    lazy var gestureEngine = GestureEngine(model: self)

    private init(store: ConfigurationStore = ConfigurationStore()) {
        self.store = store
        let result = store.load()
        bindings = result.bindings
        settings = result.settings
        notice = result.message
    }

    func start() {
        gestureEngine.start()
        applyLaunchAtLogin(settings.launchAtLogin)
    }

    func stop() {
        gestureEngine.stop()
    }

    func binding(for gestureID: GestureID) -> GestureBinding? {
        bindings.first { $0.gestureID == gestureID }
    }

    func setBinding(gestureID: GestureID, action: BindingAction) {
        if let index = bindings.firstIndex(where: { $0.gestureID == gestureID }) {
            bindings[index].action = action
            bindings[index].enabled = true
        } else {
            bindings.append(GestureBinding(gestureID: gestureID, action: action))
        }
        bindings.sort { lhs, rhs in
            let left = GestureCatalog.all.firstIndex { $0.id == lhs.gestureID } ?? .max
            let right = GestureCatalog.all.firstIndex { $0.id == rhs.gestureID } ?? .max
            return left < right
        }
        persist()
    }

    func setBindingEnabled(_ id: UUID, enabled: Bool) {
        guard let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        bindings[index].enabled = enabled
        persist()
    }

    func removeBinding(_ id: UUID) {
        bindings.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    func importMultitouchBindings() throws -> MultitouchImportResult {
        let result = try MultitouchImporter.load()
        for imported in result.bindings {
            if let index = bindings.firstIndex(where: { $0.gestureID == imported.gestureID }) {
                bindings[index] = imported
            } else {
                bindings.append(imported)
            }
        }
        bindings.sort { lhs, rhs in
            let left = GestureCatalog.all.firstIndex { $0.id == lhs.gestureID } ?? .max
            let right = GestureCatalog.all.firstIndex { $0.id == rhs.gestureID } ?? .max
            return left < right
        }
        persist()
        notice = result.summary
        return result
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        let previous = settings
        mutate(&settings)
        gestureEngine.update(settings: settings)
        persist()

        if previous.launchAtLogin != settings.launchAtLogin {
            applyLaunchAtLogin(settings.launchAtLogin)
        }
        if previous.showMenuBarIcon != settings.showMenuBarIcon {
            NotificationCenter.default.post(name: .flowpadMenuBarVisibilityChanged, object: nil)
        }
    }

    func handleRecognized(_ gestureID: GestureID) {
        lastDetectedGesture = gestureID
        guard settings.gesturesEnabled,
              let binding = bindings.first(where: { $0.gestureID == gestureID && $0.enabled })
        else { return }
        executor.execute(binding.action)
    }

    func updateEngineStatus(available: Bool, message: String) {
        engineAvailable = available
        engineStatus = message
    }

    private func persist() {
        do {
            try store.save(bindings: bindings, settings: settings)
        } catch {
            notice = "Could not save settings: \(error.localizedDescription)"
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            notice = "Launch at login could not be changed: \(error.localizedDescription)"
        }
    }
}

extension Notification.Name {
    static let flowpadMenuBarVisibilityChanged = Notification.Name("FlowpadMenuBarVisibilityChanged")
}
