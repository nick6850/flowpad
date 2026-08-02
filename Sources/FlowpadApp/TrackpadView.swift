import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TrackpadView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var editorGesture: GestureDefinition?

    private var filteredBindings: [GestureBinding] {
        guard !searchText.isEmpty else { return model.bindings }
        return model.bindings.filter { binding in
            guard let definition = GestureCatalog.byID[binding.gestureID] else { return false }
            return definition.searchableText.localizedCaseInsensitiveContains(searchText)
                || binding.action.kindTitle.localizedCaseInsensitiveContains(searchText)
                || binding.action.detailTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trackpad gestures")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Assign a shortcut or application to any supported gesture.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let gestureID = model.lastDetectedGesture,
                   let definition = GestureCatalog.byID[gestureID] {
                    Label("Last: \(definition.title)", systemImage: "waveform.path")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.10)))
                        .help("Most recently recognized gesture")
                }
                Toggle("Enabled", isOn: Binding(
                    get: { model.settings.gesturesEnabled },
                    set: { value in model.updateSettings { $0.gesturesEnabled = value } }
                ))
                .toggleStyle(.switch)
            }

            HStack(spacing: 10) {
                TextField("Search bindings", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    editorGesture = GestureCatalog.all.first
                } label: {
                    Label("Add gesture", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }

            if filteredBindings.isEmpty {
                emptyState
            } else {
                bindingList
            }
        }
        .padding(24)
        .sheet(item: $editorGesture) { gesture in
            GestureEditorSheet(initialGesture: gesture)
                .environmentObject(model)
        }
    }

    private var emptyState: some View {
        SurfaceCard {
            VStack(spacing: 13) {
                Image(systemName: "rectangle.and.hand.point.up.left")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .cyan], startPoint: .top, endPoint: .bottom)
                    )
                Text(searchText.isEmpty ? "No gestures configured" : "No matching bindings")
                    .font(.title3.weight(.semibold))
                Text(searchText.isEmpty
                     ? "Choose from all 61 supported trackpad gestures."
                     : "Try another search term.")
                    .foregroundStyle(.secondary)
                if searchText.isEmpty {
                    Button("Add your first gesture") { editorGesture = GestureCatalog.all.first }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 80)
        }
    }

    private var bindingList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(GestureCategory.allCases) { category in
                    let items = filteredBindings.filter { GestureCatalog.byID[$0.gestureID]?.category == category }
                    if !items.isEmpty {
                        GestureBindingGroup(category: category, bindings: items) { definition in
                            editorGesture = definition
                        }
                    }
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 2)
        }
    }
}

private struct GestureBindingGroup: View {
    @EnvironmentObject private var model: AppModel
    let category: GestureCategory
    let bindings: [GestureBinding]
    let onEdit: (GestureDefinition) -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(category.rawValue)
                        .font(.headline)
                    Text("\(bindings.count)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(nsColor: category.color).opacity(0.22)))
                    Spacer()
                }

                ForEach(bindings) { binding in
                    if let definition = GestureCatalog.byID[binding.gestureID] {
                        GestureBindingRow(binding: binding, definition: definition) {
                            onEdit(definition)
                        }
                        if binding.id != bindings.last?.id { Divider().opacity(0.5) }
                    }
                }
            }
        }
    }
}

private struct GestureBindingRow: View {
    @EnvironmentObject private var model: AppModel
    let binding: GestureBinding
    let definition: GestureDefinition
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { binding.enabled },
                set: { model.setBindingEnabled(binding.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: definition.category.color).opacity(0.16))
                Image(systemName: definition.symbol)
                    .foregroundStyle(Color(nsColor: definition.category.color))
            }
            .frame(width: 34, height: 34)

            Text(definition.title)
                .lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(binding.action.kindTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(binding.action.detailTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, 12)
            .frame(width: 170, height: 46, alignment: .trailing)
            .background(Capsule().fill(Color.white.opacity(0.055)))

            Menu {
                Button("Edit", action: onEdit)
                Divider()
                Button("Remove", role: .destructive) { model.removeBinding(binding.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
        }
    }
}

struct GestureEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: GestureCategory
    @State private var selectedGesture: GestureDefinition
    @State private var actionKind: ActionKind = .keyboardShortcut
    @State private var shortcut = KeyboardShortcut(
        keyCode: 49,
        modifiers: CGEventFlags.maskAlternate.rawValue,
        displayText: "⌥ Space"
    )
    @State private var application: ApplicationTarget?
    @State private var folder: FolderTarget?

    enum ActionKind: String, CaseIterable, Identifiable {
        case nothing = "Nothing"
        case keyboardShortcut = "Keyboard Shortcut"
        case launchApplication = "Launch Application"
        case openFolder = "Open Folder"
        case playPause = "Play/Pause"
        case switchApplication = "Switch Application"
        case missionControl = "Mission Control"
        case screenCapture = "Screen Capture"
        case launchpad = "Launchpad"
        var id: String { rawValue }

        var systemAction: SystemAction? {
            switch self {
            case .playPause: .playPause
            case .switchApplication: .switchApplication
            case .missionControl: .missionControl
            case .screenCapture: .screenCapture
            case .launchpad: .launchpad
            case .nothing, .keyboardShortcut, .launchApplication, .openFolder: nil
            }
        }
    }

    init(initialGesture: GestureDefinition) {
        _selectedGesture = State(initialValue: initialGesture)
        _selectedCategory = State(initialValue: initialGesture.category)
    }

    private var availableGestures: [GestureDefinition] {
        GestureCatalog.definitions(in: selectedCategory).filter {
            searchText.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var canSave: Bool {
        switch actionKind {
        case .nothing, .keyboardShortcut, .playPause, .switchApplication, .missionControl, .screenCapture, .launchpad:
            true
        case .launchApplication:
            application != nil
        case .openFolder:
            folder != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.binding(for: selectedGesture.id) == nil ? "Add gesture" : "Edit gesture")
                        .font(.title2.weight(.semibold))
                    Text("Choose a gesture, then assign one action.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(!canSave)
            }
            .padding(22)

            Divider()

            HStack(spacing: 0) {
                gestureLibrary
                    .frame(minWidth: 410)
                Divider()
                actionEditor
                    .frame(width: 310)
            }
        }
        .frame(width: 780, height: 610)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadExistingBinding)
    }

    private var gestureLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search gesture library", text: $searchText)
                .textFieldStyle(.roundedBorder)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3),
                spacing: 7
            ) {
                ForEach(GestureCategory.allCases) { category in
                    Button {
                        selectedCategory = category
                        if let first = GestureCatalog.definitions(in: category).first { selectedGesture = first }
                    } label: {
                        Text(category.rawValue)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(
                                Capsule().fill(selectedCategory == category
                                    ? Color(nsColor: category.color).opacity(0.28)
                                    : Color.white.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(availableGestures) { gesture in
                        Button {
                            selectedGesture = gesture
                            loadExistingBinding()
                        } label: {
                            HStack(spacing: 11) {
                                Image(systemName: gesture.symbol)
                                    .foregroundStyle(Color(nsColor: gesture.category.color))
                                    .frame(width: 28)
                                Text(gesture.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if model.binding(for: gesture.id) != nil {
                                    Text("Configured")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if selectedGesture.id == gesture.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.purple)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedGesture.id == gesture.id
                                          ? Color.purple.opacity(0.14)
                                          : Color.white.opacity(0.035))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
    }

    private var actionEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Assign action")
                .font(.headline)
            Text(selectedGesture.title)
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Action", selection: $actionKind) {
                ForEach(ActionKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            .pickerStyle(.radioGroup)

            Divider()

            switch actionKind {
            case .nothing:
                Label("Remove this gesture action", systemImage: "trash")
                    .font(.headline)
                Text("Saving will remove the configured action for this gesture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .keyboardShortcut:
                Text("Click the field, then press the shortcut.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ShortcutRecorder(shortcut: $shortcut)
                    .frame(height: 44)
            case .launchApplication:
                if let application {
                    HStack(spacing: 10) {
                        if let icon = NSWorkspace.shared.icon(forFile: application.path) as NSImage? {
                            Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                        }
                        VStack(alignment: .leading) {
                            Text(application.displayName).fontWeight(.medium)
                            Text(application.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No application selected")
                        .foregroundStyle(.secondary)
                }
                Button("Choose Application…", action: chooseApplication)
            case .openFolder:
                if let folder {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.displayName).fontWeight(.medium)
                            Text(folder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    Text("No folder selected")
                        .foregroundStyle(.secondary)
                }
                Button("Choose Folder…", action: chooseFolder)
            case .playPause, .switchApplication, .missionControl, .screenCapture, .launchpad:
                if let action = actionKind.systemAction {
                    Label(action.title, systemImage: action.symbol)
                        .font(.headline)
                    Text(systemActionDescription(action))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private func loadExistingBinding() {
        guard let binding = model.binding(for: selectedGesture.id) else { return }
        switch binding.action {
        case let .keyboardShortcut(value):
            actionKind = .keyboardShortcut
            shortcut = value
        case let .launchApplication(value):
            actionKind = .launchApplication
            application = value
        case let .openFolder(value):
            actionKind = .openFolder
            folder = value
        case let .systemAction(value):
            actionKind = switch value {
            case .playPause: .playPause
            case .switchApplication: .switchApplication
            case .missionControl: .missionControl
            case .screenCapture: .screenCapture
            case .launchpad: .launchpad
            }
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier
        else { return }
        application = ApplicationTarget(
            bundleIdentifier: bundleIdentifier,
            displayName: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
            path: url.path
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = FolderTarget(
            displayName: FileManager.default.displayName(atPath: url.path),
            path: url.path
        )
    }

    private func systemActionDescription(_ action: SystemAction) -> String {
        switch action {
        case .playPause:
            "Controls the active media player with the native media key."
        case .switchApplication:
            "Opens the native app switcher. Repeat the gesture to move through apps."
        case .missionControl:
            "Shows all open windows and Spaces using Mission Control."
        case .screenCapture:
            "Opens the macOS Screenshot controls."
        case .launchpad:
            "Shows Apps on macOS 26 or Launchpad on earlier macOS versions."
        }
    }

    private func save() {
        if actionKind == .nothing {
            if let binding = model.binding(for: selectedGesture.id) {
                model.removeBinding(binding.id)
            }
            dismiss()
            return
        }

        let action: BindingAction
        switch actionKind {
        case .nothing:
            return
        case .keyboardShortcut:
            action = .keyboardShortcut(shortcut)
        case .launchApplication:
            guard let application else { return }
            action = .launchApplication(application)
        case .openFolder:
            guard let folder else { return }
            action = .openFolder(folder)
        case .playPause, .switchApplication, .missionControl, .screenCapture, .launchpad:
            guard let systemAction = actionKind.systemAction else { return }
            action = .systemAction(systemAction)
        }
        model.setBinding(gestureID: selectedGesture.id, action: action)
        dismiss()
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let control = ShortcutRecorderControl()
        control.onChange = { shortcut = $0 }
        control.shortcut = shortcut
        return control
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.shortcut = shortcut
    }

    static func dismantleNSView(_ nsView: ShortcutRecorderControl, coordinator: ()) {
        nsView.stopRecording()
    }
}

private final class ShortcutRecorderControl: NSView {
    var shortcut: KeyboardShortcut = .init(keyCode: 49, modifiers: 0, displayText: "Space") {
        didSet { needsDisplay = true }
    }
    var onChange: ((KeyboardShortcut) -> Void)?
    private var recording = false
    private var liveDisplayText: String?
    private var eventInterceptor: ShortcutEventInterceptor?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        beginRecording()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording, eventInterceptor == nil else { return }
        captureFallback(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, eventInterceptor == nil else {
            return super.performKeyEquivalent(with: event)
        }
        captureFallback(event)
        return true
    }

    func stopRecording() {
        eventInterceptor?.stop()
        eventInterceptor = nil
        recording = false
        needsDisplay = true
    }

    private func beginRecording() {
        stopRecording()
        recording = true
        liveDisplayText = nil
        needsDisplay = true

        let interceptor = ShortcutEventInterceptor { [weak self] update in
            DispatchQueue.main.async { self?.apply(update) }
        }
        if interceptor.start() {
            eventInterceptor = interceptor
        }
    }

    private func apply(_ update: ShortcutCaptureUpdate) {
        guard recording else { return }
        switch update {
        case .none:
            break
        case let .preview(text):
            liveDisplayText = text.isEmpty ? nil : text
            needsDisplay = true
        case let .capture(value):
            shortcut = value
            liveDisplayText = value.displayText
            onChange?(value)
        case .cancel:
            break
        case .finish:
            stopRecording()
            if window?.firstResponder === self {
                window?.makeFirstResponder(nil)
            }
        }
    }

    private func captureFallback(_ event: NSEvent) {
        if event.keyCode == 53 {
            stopRecording()
            window?.makeFirstResponder(nil)
            return
        }
        let display = Self.displayText(for: event)
        let flags = Self.cgFlags(for: event.modifierFlags)
        shortcut = KeyboardShortcut(keyCode: event.keyCode, modifiers: flags.rawValue, displayText: display)
        onChange?(shortcut)
        stopRecording()
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        (recording ? NSColor.systemPurple.withAlphaComponent(0.28) : NSColor.white.withAlphaComponent(0.06)).setFill()
        path.fill()
        (recording ? NSColor.systemPurple : NSColor.white.withAlphaComponent(0.14)).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = recording ? (liveDisplayText ?? "Press shortcut…") : shortcut.displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }

    private static func displayText(for event: NSEvent) -> String {
        ShortcutText.display(keyCode: event.keyCode, flags: cgFlags(for: event.modifierFlags))
    }

    private static func cgFlags(for flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }
}

enum ShortcutCaptureUpdate: Equatable {
    case none
    case preview(String)
    case capture(KeyboardShortcut)
    case cancel
    case finish
}

struct ShortcutCaptureState {
    private(set) var capturedKey = false
    private var pressedKeys: Set<CGKeyCode> = []

    mutating func handle(
        type: CGEventType,
        keyCode: CGKeyCode,
        flags: CGEventFlags
    ) -> ShortcutCaptureUpdate {
        let modifiers = Self.recordableFlags(flags)

        switch type {
        case .keyDown:
            pressedKeys.insert(keyCode)
            guard !capturedKey else { return .none }
            capturedKey = true
            if keyCode == 53 { return .cancel }
            return .capture(KeyboardShortcut(
                keyCode: keyCode,
                modifiers: modifiers.rawValue,
                displayText: ShortcutText.display(keyCode: keyCode, flags: modifiers)
            ))

        case .keyUp:
            pressedKeys.remove(keyCode)
            return shouldFinish(modifiers: modifiers) ? .finish : .none

        case .flagsChanged:
            if shouldFinish(modifiers: modifiers) { return .finish }
            if !capturedKey { return .preview(ShortcutText.displayModifiers(modifiers)) }
            return .none

        default:
            return .none
        }
    }

    static func recordableFlags(_ flags: CGEventFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.maskControl) { result.insert(.maskControl) }
        if flags.contains(.maskAlternate) { result.insert(.maskAlternate) }
        if flags.contains(.maskShift) { result.insert(.maskShift) }
        if flags.contains(.maskCommand) { result.insert(.maskCommand) }
        if flags.contains(.maskSecondaryFn) { result.insert(.maskSecondaryFn) }
        return result
    }

    private func shouldFinish(modifiers: CGEventFlags) -> Bool {
        capturedKey && pressedKeys.isEmpty && modifiers.isEmpty
    }
}

private final class ShortcutEventInterceptor: @unchecked Sendable {
    private let onUpdate: @Sendable (ShortcutCaptureUpdate) -> Void
    private let lock = NSLock()
    private var state = ShortcutCaptureState()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onUpdate: @escaping @Sendable (ShortcutCaptureUpdate) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() -> Bool {
        let keyDownMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        let keyUpMask = CGEventMask(1) << CGEventType.keyUp.rawValue
        let flagsChangedMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        // kCGEventSystemDefined is raw event type 14; CoreGraphics does not
        // expose a Swift enum case for it.
        let systemDefinedMask = CGEventMask(1) << 14
        let mask = keyDownMask | keyUpMask | flagsChangedMask | systemDefinedMask
        guard let tap = CGEvent.tapCreate(
            // HID-level capture sees physical keyboards and virtual keyboards
            // created by device software such as Logi Options+.
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let interceptor = Unmanaged<ShortcutEventInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = interceptor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        interceptor.lock.lock()
        let update = interceptor.state.handle(type: type, keyCode: keyCode, flags: event.flags)
        interceptor.lock.unlock()
        if update != .none { interceptor.onUpdate(update) }

        // A nil event stops it before Dock, Mission Control, menus, or the
        // foreground application can act on the shortcut being recorded.
        return nil
    }

    deinit {
        stop()
    }
}
