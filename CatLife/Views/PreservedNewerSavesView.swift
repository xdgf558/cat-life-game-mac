import SwiftUI
import CatGameCore

/// These originals are independent of both the current save and the single import recovery point.
@MainActor
struct PreservedNewerSavesView: View {
    @Bindable var store: GameStore
    let busy: Bool
    let onWorkingChange: (Bool) -> Void
    let presentExport: (SaveArchiveDocument, String, @escaping (Result<URL, Error>?) -> Void) -> Void
    @State private var originals: [PreservedNewerSave] = []
    @State private var listFailed = false
    @State private var isLoading = false
    @State private var statusKey: String?
    @State private var exportFailed = false

    var body: some View {
        VStack(spacing: 0) {
            if listFailed || !originals.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Label(GameStrings.text("saveTransfer.preservedTitle"), systemImage: "externaldrive.fill")
                        .font(.headline.weight(.heavy))
                        .accessibilityIdentifier("savePreservedTitle")
                    Text(GameStrings.text("saveTransfer.preservedHint"))
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if listFailed {
                        Text(GameStrings.text("saveTransfer.preservedListFailed"))
                            .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.coral)
                            .accessibilityIdentifier("savePreservedListError")
                        Button { Task { await refresh() } } label: {
                            Label(GameStrings.text("common.retry"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SoftButtonStyle()).disabled(busy || isLoading)
                        .accessibilityIdentifier("savePreservedRetryButton")
                    }
                    ForEach(originals, id: \.id) { original in entry(original) }
                    if let statusKey {
                        Text(GameStrings.text(statusKey))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(exportFailed ? RoomTheme.coral : RoomTheme.darkMint)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("savePreservedExportStatus")
                    }
                }
                .padding(16).gameCard(cornerRadius: 28)
            }
        }
        .task { await refresh() }
    }

    private func entry(_ original: PreservedNewerSave) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameStrings.format("saveTransfer.preservedSchema", original.schemaVersion))
                .font(.subheadline.weight(.heavy))
            Text(GameStrings.format("saveTransfer.preservedAt",
                                    SaveTransferPresentation.date(original.savedAt, language: store.language)))
                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            Text(ByteCountFormatter.string(fromByteCount: Int64(original.byteCount), countStyle: .file))
                .font(.caption).foregroundStyle(RoomTheme.secondary)
            Button { export(original) } label: {
                Label(GameStrings.text("saveTransfer.exportPreserved"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SaveTransferOutlineButtonStyle())
            .disabled(busy || isLoading)
            .accessibilityIdentifier("savePreservedExportButton_\(original.id)")
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.paleMint.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
    }

    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            originals = try await store.preservedNewerSaves()
            listFailed = false
        } catch { listFailed = true }
    }

    private func export(_ original: PreservedNewerSave) {
        guard !busy, !isLoading else { return }
        onWorkingChange(true)
        statusKey = nil; exportFailed = false
        Task {
            do {
                let data = try await store.exportPreservedNewerSave(id: original.id)
                let date = DateFormatter()
                date.locale = Locale(identifier: "en_US_POSIX")
                date.dateFormat = "yyyyMMdd-HHmmss"
                let suffix = URL(fileURLWithPath: original.id).deletingPathExtension().lastPathComponent.suffix(8)
                let filename = "CatLife-Preserved-v\(original.schemaVersion)-\(date.string(from: original.savedAt))-\(suffix)"
                onWorkingChange(false)
                presentExport(SaveArchiveDocument(data: data), filename, completeExport)
            } catch {
                onWorkingChange(false)
                exportFailed = true; statusKey = "saveTransfer.preservedExportFailed"
            }
        }
    }

    private func completeExport(_ result: Result<URL, Error>?) {
        // Dismissal may precede the actual completion callback; do not replace its result.
        guard let result else {
            if statusKey == nil { statusKey = "saveTransfer.unchanged" }
            return
        }
        switch result {
        case .success:
            exportFailed = false; statusKey = "saveTransfer.exported"
        case .failure(let error):
            exportFailed = (error as? CocoaError)?.code != .userCancelled
            statusKey = exportFailed ? "saveTransfer.preservedExportFailed" : "saveTransfer.unchanged"
        }
    }
}
