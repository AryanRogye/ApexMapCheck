import SwiftUI

struct ContentView: View {
    @StateObject private var model = RotationViewModel()
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            AppBackground()

            if model.hasAPIKey {
                rotationContent
            } else {
                APIKeySetupView { key in
                    await model.saveAPIKey(key)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                currentKey: model.usesBundledAPIKey ? "" : model.apiKey,
                usesBundledKey: model.usesBundledAPIKey,
                onSave: { key in await model.saveAPIKey(key) },
                onRemove: { model.removeAPIKey() }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await model.loadIfNeeded()
        }
    }

    private var rotationContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                header

                if model.isLoading && model.rotations.isEmpty {
                    LoadingView()
                } else if model.rotations.isEmpty, let message = model.errorMessage {
                    RotationFailureView(
                        message: message,
                        actionURL: model.errorActionURL,
                        prepareForAction: model.prepareForAccountVerification
                    ) {
                        Task { await model.refresh() }
                    }
                } else if model.rotations.isEmpty {
                    EmptyRotationView {
                        Task { await model.refresh() }
                    }
                } else {
                    if let message = model.errorMessage {
                        ErrorBanner(message: message) {
                            Task { await model.refresh() }
                        }
                    }

                    ForEach(model.rotations) { rotation in
                        RotationCard(rotation: rotation)
                    }

                    statusFooter
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .refreshable {
            await model.refresh()
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("APEX")
                    .font(.caption.weight(.black))
                    .tracking(2.6)
                    .foregroundStyle(Color.apexRed)

                Text("Map Rotation")
                    .font(.largeTitle.weight(.black))
                    .tracking(-1.1)
                    .foregroundStyle(.white)
            }

            Spacer()

            if model.isLoading {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Refreshing rotations")
            }

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("API settings")
        }
        .padding(.top, 18)
    }

    private var statusFooter: some View {
        VStack(spacing: 10) {
            if let date = model.lastUpdated {
                Text("Updated \(date, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.56))
            }

            Link(destination: URL(string: "https://apexlegendsstatus.com")!) {
                HStack(spacing: 5) {
                    Text("Data provided by Apex Legends Status")
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
            }
            .accessibilityHint("Opens the data provider website")
        }
        .padding(.top, 6)
    }
}

private struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.039, blue: 0.05)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.apexRed.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 430
            )
            .ignoresSafeArea()
        }
    }
}

private struct RotationCard: View {
    let rotation: GameModeRotation

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            mapArtwork

            LinearGradient(
                colors: [.clear, .black.opacity(0.22), .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(rotation.displayName.uppercased(), systemImage: rotation.symbolName)
                        .font(.caption.weight(.black))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.88))

                    Spacer()

                    Text("LIVE")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.apexRed, in: Capsule())
                }

                Spacer(minLength: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(rotation.current.map)
                        .font(.system(.title, design: .rounded, weight: .black))
                        .tracking(-0.7)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(rotation.current.countdown(at: context.date))
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                            .contentTransition(.numericText())
                            .accessibilityLabel("\(rotation.current.accessibleTimeRemaining(at: context.date)) remaining")
                    }
                }

                if let next = rotation.next {
                    Divider()
                        .overlay(.white.opacity(0.18))

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            nextLabel
                            nextMap(next)
                            Spacer()
                            duration(next)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            nextLabel
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                nextMap(next)
                                Spacer()
                                duration(next)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minHeight: 286)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
    }

    private var nextLabel: some View {
        Text("NEXT")
            .font(.caption2.weight(.black))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.5))
    }

    private func nextMap(_ window: MapWindow) -> some View {
        Text(window.map)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white.opacity(0.86))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func duration(_ window: MapWindow) -> some View {
        Text(window.durationLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.58))
            .fixedSize()
    }

    @ViewBuilder
    private var mapArtwork: some View {
        if let assetURL = rotation.current.assetURL {
            AsyncImage(url: assetURL, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    MapFallback(mapName: rotation.current.map)
                }
            }
        } else {
            MapFallback(mapName: rotation.current.map)
        }
    }
}

private struct MapFallback: View {
    let mapName: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 112, weight: .black))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: 82, y: -38)
        }
    }

    private var palette: [Color] {
        let seed = mapName.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let choices: [[Color]] = [
            [Color(red: 0.33, green: 0.10, blue: 0.10), Color(red: 0.06, green: 0.06, blue: 0.08)],
            [Color(red: 0.08, green: 0.25, blue: 0.28), Color(red: 0.04, green: 0.06, blue: 0.09)],
            [Color(red: 0.28, green: 0.18, blue: 0.08), Color(red: 0.06, green: 0.05, blue: 0.07)]
        ]
        return choices[seed % choices.count]
    }
}

private struct APIKeySetupView: View {
    @State private var key = ""
    @State private var isSaving = false
    @FocusState private var keyFocused: Bool

    let onSave: (String) async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 64)

                Image(systemName: "map.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.apexRed, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Color.apexRed.opacity(0.35), radius: 24, y: 12)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Know the map\nbefore you queue.")
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .tracking(-1.2)
                        .foregroundStyle(.white)

                    Text("See the live pubs and ranked rotations, the next map, and exactly when each switch happens.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("APEX LEGENDS STATUS API KEY")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.52))

                    SecureField("Paste your API key", text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($keyFocused)
                        .padding(16)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        isSaving = true
                        Task {
                            await onSave(key.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSaving = false
                        }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Check rotations")
                                    .fontWeight(.bold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.apexRed)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                    Link("Get a free API key ↗", destination: URL(string: "https://apexlegendsapi.com/#my-api-access")!)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Text("Your key is stored securely in this device’s Keychain.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.44))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key: String
    @State private var isSaving = false

    let usesBundledKey: Bool
    let onSave: (String) async -> Void
    let onRemove: () -> Void

    init(
        currentKey: String,
        usesBundledKey: Bool,
        onSave: @escaping (String) async -> Void,
        onRemove: @escaping () -> Void
    ) {
        _key = State(initialValue: currentKey)
        self.usesBundledKey = usesBundledKey
        self.onSave = onSave
        self.onRemove = onRemove
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("API access") {
                    if usesBundledKey {
                        Label("Included in this build", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Text("This build is configured for you and your friends. The key is not stored in the public Git repository.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        SecureField("API key", text: $key)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Link("Manage API access", destination: URL(string: "https://apexlegendsapi.com/#my-api-access")!)
                }

                if !usesBundledKey {
                    Section {
                        Button("Save and refresh") {
                            isSaving = true
                            Task {
                                await onSave(key.trimmingCharacters(in: .whitespacesAndNewlines))
                                isSaving = false
                                dismiss()
                            }
                        }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                        Button("Remove API key", role: .destructive) {
                            onRemove()
                            dismiss()
                        }
                    }
                }

                Section {
                    Link("Data provided by Apex Legends Status", destination: URL(string: "https://apexlegendsstatus.com")!)
                } footer: {
                    Text("This app is not affiliated with EA or Respawn Entertainment.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Retry", action: retry)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Finding the live maps…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

private struct RotationFailureView: View {
    @Environment(\.openURL) private var openURL

    let message: String
    let actionURL: URL?
    let prepareForAction: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: actionURL == nil ? "exclamationmark.triangle.fill" : "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(actionURL == nil ? Color.yellow : Color.apexRed)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(actionURL == nil ? "Couldn’t load rotations" : "Verify API account")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: 320)
            }

            if let actionURL {
                Button("Verify API account") {
                    prepareForAction()
                    openURL(actionURL)
                }
                    .buttonStyle(.borderedProminent)
                    .tint(.apexRed)
            }

            Button("Try again", action: retry)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(.horizontal, 24)
    }
}

private struct EmptyRotationView: View {
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No rotations found", systemImage: "map")
        } description: {
            Text("The service returned no active map rotations.")
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.apexRed)
        }
        .frame(minHeight: 360)
    }
}

extension Color {
    static let apexRed = Color(red: 0.84, green: 0.12, blue: 0.13)
}

#Preview("Rotations") {
    ContentView()
}
