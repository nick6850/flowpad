import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var accessibilityGranted = AccessibilityPermission.isGranted

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Only the essentials for reliable gesture recognition.")
                        .foregroundStyle(.secondary)
                }

                settingsStack
            }
            .padding(24)
        }
        .onAppear(perform: refreshAccessibilityPermission)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityPermission()
        }
    }

    private var settingsStack: some View {
        VStack(spacing: 16) {
            SurfaceCard {
                SettingsSection(title: "General", symbol: "switch.2") {
                    settingToggle("Enable gestures", value: Binding(
                        get: { model.settings.gesturesEnabled },
                        set: { value in model.updateSettings { $0.gesturesEnabled = value } }
                    ))
                    Divider()
                    settingToggle("Launch at login", value: Binding(
                        get: { model.settings.launchAtLogin },
                        set: { value in model.updateSettings { $0.launchAtLogin = value } }
                    ))
                    Divider()
                    settingToggle("Show in menu bar", value: Binding(
                        get: { model.settings.showMenuBarIcon },
                        set: { value in model.updateSettings { $0.showMenuBarIcon = value } }
                    ))
                }
            }

            SurfaceCard {
                SettingsSection(title: "Recognition", symbol: "scope") {
                    sensitivityControl("Touch precision", value: Binding(
                        get: { model.settings.touchPrecision },
                        set: { value in model.updateSettings { $0.touchPrecision = value } }
                    ))
                    Divider()
                    sensitivityControl("Swipe sensitivity", value: Binding(
                        get: { model.settings.swipeSensitivity },
                        set: { value in model.updateSettings { $0.swipeSensitivity = value } }
                    ))
                }
            }

            SurfaceCard {
                SettingsSection(title: "Permissions", symbol: "checkmark.shield") {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(accessibilityGranted ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility — \(accessibilityGranted ? "Granted" : "Required")")
                                .fontWeight(.medium)
                            Text("Needed only to send keyboard shortcuts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Open System Settings") {
                        AccessibilityPermission.openSystemSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func settingToggle(_ title: String, value: Binding<Bool>) -> some View {
        Toggle(title, isOn: value)
            .toggleStyle(.switch)
    }

    private func sensitivityControl(_ title: String, value: Binding<Sensitivity>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.medium))
            Picker(title, selection: value) {
                ForEach(Sensitivity.allCases) { sensitivity in
                    Text(sensitivity.rawValue).tag(sensitivity)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private func refreshAccessibilityPermission() {
        accessibilityGranted = AccessibilityPermission.isGranted
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
