import EVEStaticData
import SwiftUI

public struct SDEUpdateView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var showSettings = false
    @State private var manifestURLString = ""

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    closeView()
                }

            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("SDE Update Details")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.eveText)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSettings.toggle()
                        }
                    } label: {
                        Image(systemName: showSettings ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(showSettings ? Color.eveAmber : Color.eveText.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)

                // Optional Manifest URL Configuration (Collapsible Settings)
                if showSettings {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("MANIFEST URL")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.eveText.opacity(0.5))

                            Spacer()

                            Button("Reset Default") {
                                env.sdeUpdates.resetToDefaultManifestURL()
                                manifestURLString = env.sdeUpdates.manifestURLString
                                Task { await env.sdeUpdates.checkForUpdates() }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.eveCyan)
                        }

                        HStack(spacing: 8) {
                            TextField("https://example.com/manifest.json", text: $manifestURLString)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(10)
                                .foregroundStyle(Color.eveText)
                                .background(Color.black.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button("Check") {
                                env.sdeUpdates.manifestURLString = manifestURLString
                                Task { await env.sdeUpdates.checkForUpdates() }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.eveAmber)
                            .foregroundStyle(Color.eveBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
                    .background(Color.eveBackground.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // SDE Data Package Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("SDE Data Package")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.eveText.opacity(0.85))

                    VStack(spacing: 10) {
                        versionRow(
                            label: "Current Version",
                            value: currentBuildVersion,
                            isHighlight: true
                        )
                        Divider().background(Color.white.opacity(0.08))
                        versionRow(
                            label: "Latest Version",
                            value: latestBuildVersion,
                            isHighlight: false
                        )
                    }
                    .padding(14)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Icon / Schema Package Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Icon & Schema Package")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.eveText.opacity(0.85))

                    VStack(spacing: 10) {
                        versionRow(
                            label: "Current Version",
                            value: currentIconVersion,
                            isHighlight: true
                        )
                        Divider().background(Color.white.opacity(0.08))
                        versionRow(
                            label: "Latest Version",
                            value: latestIconVersion,
                            isHighlight: false
                        )
                    }
                    .padding(14)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // What's New (named diff against the installed database)
                if let changelog = env.sdeUpdates.remoteChangelog, !changelog.isEmpty {
                    whatsNewCard(changelog)
                }

                // Status message & progress
                if statusMessage != nil || isDownloading {
                    VStack(spacing: 6) {
                        if isDownloading {
                            ProgressView()
                                .tint(Color.eveCyan)
                                .scaleEffect(0.9)
                        }
                        if let statusMessage {
                            Text(statusMessage)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(statusColor)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // Action Buttons (Update & Dismiss)
                VStack(spacing: 10) {
                    Button {
                        Task {
                            if env.sdeUpdates.remoteManifest == nil {
                                await env.sdeUpdates.checkForUpdates()
                            }
                            if env.sdeUpdates.isUpdateAvailable || env.sdeUpdates.remoteManifest != nil {
                                if await env.sdeUpdates.installUpdate() {
                                    await env.reloadRepository()
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if isBusy {
                                ProgressView()
                                    .tint(.white)
                                    .padding(.trailing, 6)
                            }
                            Text(updateButtonTitle)
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(updateButtonBackground)
                        .foregroundStyle(Color.white)
                        .clipShape(Capsule())
                    }
                    .disabled(isBusy || isUpToDate)

                    Button {
                        closeView()
                    } label: {
                        Text("Dismiss")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.12))
                            .foregroundStyle(Color.eveText.opacity(0.9))
                            .clipShape(Capsule())
                    }
                }
                .padding(.top, 6)
            }
            .padding(24)
            .background(
                ZStack {
                    Color.eveCard
                    Color.black.opacity(0.4)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 24)
            .frame(maxWidth: 440)
        }
        .task {
            env.sdeUpdates.refreshLocalMetadata()
            manifestURLString = env.sdeUpdates.manifestURLString
            if env.sdeUpdates.remoteManifest == nil {
                await env.sdeUpdates.checkForUpdates()
            }
        }
    }

    private func closeView() {
        env.showSDEUpdateSheet = false
        dismiss()
    }

    // MARK: - Helper Views & Computed Properties

    private func whatsNewCard(_ changelog: SDEChangelog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's New")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.eveText.opacity(0.85))

            VStack(alignment: .leading, spacing: 8) {
                changelogRow(label: "NEW", items: changelog.types.added, count: changelog.types.addedCount, color: .eveGreen)
                changelogRow(label: "CHANGED", items: changelog.types.changed, count: changelog.types.changedCount, color: .eveCyan)
                changelogRow(label: "REMOVED", items: changelog.types.removed, count: changelog.types.removedCount, color: Color.eveText.opacity(0.5))

                let structuralChanges = changelog.categoriesChanged + changelog.groupsChanged
                    + changelog.dogmaAttributesChanged + changelog.dogmaEffectsChanged
                if structuralChanges > 0 {
                    Text("+ \(structuralChanges) internal attribute/category updates")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.eveText.opacity(0.4))
                }
            }
        }
        .padding(14)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func changelogRow(label: String, items: [String], count: Int, color: Color) -> some View {
        if count > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(label) (\(count))")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text(itemsPreview(items, totalCount: count))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.eveText.opacity(0.8))
                    .lineLimit(3)
            }
        }
    }

    private func itemsPreview(_ items: [String], totalCount: Int) -> String {
        let shown = items.prefix(6)
        var text = shown.joined(separator: ", ")
        if totalCount > shown.count {
            text += " and \(totalCount - shown.count) more"
        }
        return text
    }

    private func versionRow(label: String, value: String, isHighlight: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.eveText.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(isHighlight ? Color(hue: 0.08, saturation: 0.85, brightness: 0.95) : Color.eveText)
        }
    }

    private var currentBuildVersion: String {
        env.sdeUpdates.localMetadata?.build ?? "3503375"
    }

    private var latestBuildVersion: String {
        env.sdeUpdates.remoteManifest?.build ?? (env.sdeUpdates.phase == .checking ? "Checking..." : currentBuildVersion)
    }

    private var currentIconVersion: String {
        if let schema = env.sdeUpdates.localMetadata?.schemaVersion {
            return "v\(schema)"
        }
        return "v1"
    }

    private var latestIconVersion: String {
        if let iconVer = env.sdeUpdates.remoteManifest?.iconVersion {
            return iconVer
        }
        if let schema = env.sdeUpdates.remoteManifest?.schemaVersion {
            return "v\(schema)"
        }
        return env.sdeUpdates.phase == .checking ? "Checking..." : currentIconVersion
    }

    private var isBusy: Bool {
        switch env.sdeUpdates.phase {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    private var isDownloading: Bool {
        if case .downloading = env.sdeUpdates.phase { return true }
        return false
    }

    private var isUpToDate: Bool {
        env.sdeUpdates.phase == .upToDate
    }

    private var updateButtonTitle: String {
        switch env.sdeUpdates.phase {
        case .idle:
            return "Check for Updates"
        case .checking:
            return "Checking..."
        case .upToDate:
            return "Up to Date"
        case .updateAvailable:
            return "Update"
        case .downloading:
            return "Downloading..."
        case .installing:
            return "Installing..."
        case .installed:
            return "Installed"
        case .failed:
            return "Retry Update"
        }
    }

    private var updateButtonBackground: Color {
        if isBusy || isUpToDate {
            return Color.blue.opacity(0.35)
        }
        return Color(red: 0.0, green: 0.48, blue: 1.0) // Vibrantly matched Tritanium blue button
    }

    private var statusMessage: String? {
        switch env.sdeUpdates.phase {
        case .failed(let msg):
            return msg
        case .installed:
            return "Database successfully updated."
        case .upToDate:
            return "Your SDE database is up to date."
        case .downloading:
            return "Downloading SDE package..."
        case .installing:
            return "Installing database package..."
        default:
            return nil
        }
    }

    private var statusColor: Color {
        if case .failed = env.sdeUpdates.phase {
            return .red
        }
        if case .installed = env.sdeUpdates.phase {
            return .eveGreen
        }
        return .eveCyan
    }
}
