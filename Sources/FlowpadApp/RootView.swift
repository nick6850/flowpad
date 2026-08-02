import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.55)

            Group {
                switch model.selectedSection {
                case .trackpad:
                    TrackpadView()
                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.black.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .preferredColorScheme(.dark)
        .alert("Flowpad", isPresented: Binding(
            get: { model.notice != nil },
            set: { if !$0 { model.notice = nil } }
        )) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "circle.grid.2x2.fill")
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                Text("Flowpad")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }

            Picker("Section", selection: $model.selectedSection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.rawValue, systemImage: section == .trackpad ? "rectangle.and.hand.point.up.left" : "slider.horizontal.3")
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 250)

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(model.engineAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(model.engineStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help(model.engineStatus)
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }
}

struct SurfaceCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}
