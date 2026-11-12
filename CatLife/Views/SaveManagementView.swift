import SwiftUI
import CatGameCore

@MainActor
struct SaveManagementView: View {
    @Bindable var store: GameStore
    var recoveryOnly = false
    var onRecovered: (() -> Void)?
    var onWorkingChange: ((Bool) -> Void)?
    var onReturnHome: (() -> Void)?
    var onRetryLoad: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var isRestoring = false
    @State private var isImportingFile = false
    @State private var isExportingFile = false
    @State private var presentedExportDocument: SaveArchiveDocument?
    @State private var presentedExportFilename = ""
    @State private var presentedExportCompletion: ((Result<URL, Error>?) -> Void)?
    @State private var exportDocument: SaveArchiveDocument?
    @State private var exportFilename = ""
    @State private var exportURL: URL?
    @State private var exportDate: Date?
    @State private var exportSize: Int?
    @State private var recovery: NativeSaveArchive?
    @State private var recoveryUnavailable = true
    @State private var preview: ImportPreview?
    @State private var acknowledged = false
    @State private var isShowingModal = false
    @State private var chooseAfterDismiss = false
    @State private var retryReadAfterDismiss = false
    @State private var issue: SaveTransferError?
    @State private var retryExport = false
    @State private var didRestore = false
    @State private var statusKey: String?

    private struct ImportPreview {
        let archive: NativeSaveArchive
        let filename: String
        let byteCount: Int?
        let isRecovery: Bool
    }

    private var busy: Bool { isWorking || store.saveTransferInProgress || store.isBusy }

    var body: some View {
        VStack(spacing: 0) {
            if !recoveryOnly {
                heading.padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.cream)
            }
            pageContent
        }
        .background(RoomTheme.cream.ignoresSafeArea())
        .task { if !recoveryOnly { await refreshRecovery() } }
        .overlay { if isWorking && !isShowingModal { SaveTransferWorkingView(recoveryOnly: recoveryOnly, restoring: isRestoring) } }
        .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): readImport(url)
            case .failure(let error): retryExport = false; report(error)
            }
        }
        .fileExporter(isPresented: $isExportingFile, document: presentedExportDocument,
                      contentType: .json, defaultFilename: presentedExportFilename) { result in
            if let presentedExportCompletion { presentedExportCompletion(result); return }
            switch result {
            case .success: setStatus("saveTransfer.exported")
            case .failure(let error):
                if (error as? CocoaError)?.code == .userCancelled { setStatus("saveTransfer.unchanged") }
                else { retryExport = true; report(SaveTransferError.writeFailed) }
            }
        }
        .onChange(of: isImportingFile) { _, presented in
            if !presented && !isWorking && statusKey == nil { setStatus("saveTransfer.unchanged") }
        }
        .onChange(of: isExportingFile) { _, presented in
            if !presented {
                if let presentedExportCompletion { presentedExportCompletion(nil) }
                else if statusKey == nil { setStatus("saveTransfer.unchanged") }
            }
        }
        .sheet(isPresented: $isShowingModal, onDismiss: modalDismissed) {
            modal
                .fontDesign(.rounded).foregroundStyle(RoomTheme.ink)
                .environment(\.locale, Locale(identifier: store.language.rawValue))
                .interactiveDismissDisabled(isWorking)
                .presentationDragIndicator(isWorking ? .hidden : .visible)
                .presentationDetents([.large])
        }
    }

    private var pageContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if recoveryOnly { heading }
                if !recoveryOnly, let snapshot = store.snapshot {
                    currentProgress(snapshot)
                    Text(GameStrings.text("saveTransfer.backupTitle")).font(.headline.weight(.heavy))
                    exportCard
                }
                importCard
                if !recoveryOnly {
                    recoveryCard
                    PreservedNewerSavesView(store: store, busy: busy, onWorkingChange: setWorking,
                                           presentExport: presentPreservedExport)
                }
                if let statusKey {
                    Label(GameStrings.text(statusKey), systemImage: "checkmark.shield.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("saveTransferStatus")
                }
                Text(GameStrings.text(recoveryOnly ? "saveTransfer.failureScope" : "saveTransfer.scope")
                     + " " + GameStrings.text("saveTransfer.sizeLimit"))
                    .font(.caption).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RoomTheme.cream.ignoresSafeArea())
        .accessibilityIdentifier("saveManagementScroll")
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recoveryOnly {
                GamePageHeading(title: GameStrings.text("saveTransfer.failureEntry"), symbol: "externaldrive.fill",
                                tint: RoomTheme.mint, background: RoomTheme.paleMint)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { backButton; titlePlaque.fixedSize(horizontal: true, vertical: false) }
                    VStack(alignment: .leading, spacing: 12) { backButton; titlePlaque }
                }
            }
            Text(GameStrings.text("saveTransfer.subtitle")).font(.subheadline.weight(.bold))
                .foregroundStyle(RoomTheme.secondary)
        }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Label(GameStrings.text("settings.title"), systemImage: "chevron.left")
                .font(.subheadline.weight(.heavy))
        }
        .buttonStyle(SoftButtonStyle()).fixedSize(horizontal: true, vertical: false)
        .disabled(busy).accessibilityIdentifier("settingsBackButton")
    }

    private var titlePlaque: some View {
        Label(GameStrings.text("saveTransfer.title"), systemImage: "externaldrive")
            .font(.title3.weight(.heavy)).padding(.horizontal, 16).padding(.vertical, 13)
            .background(RoomTheme.wood, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(RoomTheme.secondary.opacity(0.4), lineWidth: 3))
            .shadow(color: RoomTheme.wood, radius: 0, y: 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.text("saveTransfer.title"))
            .accessibilityIdentifier("saveManagementTitle")
    }

    private func currentProgress(_ snapshot: GameSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image("app-icon-preview").resizable().scaledToFit().frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white, lineWidth: 2))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(GameStrings.text("saveTransfer.current")).font(.caption.weight(.bold))
                        .foregroundStyle(RoomTheme.secondary)
                    Text(SaveTransferPresentation.player(snapshot) + " · " + store.homeDisplayName)
                        .font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                }
            }
            SaveTransferStats(snapshot: snapshot)
            VStack(alignment: .leading, spacing: 5) {
                Label(store.hasSaveFailure ? GameStrings.text("save.writeTitle")
                      : (store.isBusy ? GameStrings.text("common.saving")
                         : GameStrings.format("saveTransfer.savedAt", dateText(snapshot.meta.lastSyncAt))),
                      systemImage: store.hasSaveFailure ? "exclamationmark.circle.fill" : "circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(store.hasSaveFailure ? RoomTheme.coral : RoomTheme.darkMint)
                Text(GameStrings.text("saveTransfer.autosaveContinues")).font(.caption2)
                    .foregroundStyle(RoomTheme.secondary)
            }
        }
        .padding(16).gameCard(cornerRadius: 28).accessibilityIdentifier("saveCurrentSummary")
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeading("saveTransfer.prepareExport", subtitle: "saveTransfer.backupHint", symbol: "shippingbox", tint: RoomTheme.darkMint)
            if exportDocument != nil, let exportDate {
                SaveTransferPostcard(filename: exportFilename + ".json", byteCount: exportSize,
                    subtitle: GameStrings.format("saveTransfer.preparedAt", dateText(exportDate)), prepared: true)
                    .accessibilityIdentifier("saveExportPrepared")
                if store.hasSaveFailure {
                    Text(GameStrings.text("saveTransfer.exportMemoryHint"))
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                        .accessibilityIdentifier("saveExportMemoryHint")
                }
                if exportURL == nil {
                    Text(GameStrings.text("saveTransfer.shareUnavailable"))
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { exportButtons(exportURL) }
                    VStack(spacing: 10) { exportButtons(exportURL) }
                }
            } else {
                Button { prepareExport() } label: {
                    Label(GameStrings.text("saveTransfer.prepareExport"), systemImage: "shippingbox")
                        .font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle()).disabled(busy).accessibilityIdentifier("saveExportButton")
            }
        }
        .padding(16).gameCard(cornerRadius: 28)
    }

    @ViewBuilder private func exportButtons(_ url: URL?) -> some View {
        Button {
            statusKey = nil
            presentedExportDocument = exportDocument
            presentedExportFilename = exportFilename
            presentedExportCompletion = nil
            isExportingFile = true
        } label: {
            Label(GameStrings.text("saveTransfer.saveToFiles"), systemImage: "folder.fill")
                .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
        }
        .buttonStyle(MintButtonStyle()).disabled(busy).accessibilityIdentifier("saveExportFilesButton")
        if let url {
            ShareLink(item: url) {
                Label(GameStrings.text("saveTransfer.share"), systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(SaveTransferOutlineButtonStyle()).disabled(busy).accessibilityIdentifier("saveExportShareButton")
        }
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if recoveryOnly {
                Text(GameStrings.text(store.needsNewerVersion ? "saveTransfer.failureNewerIntro" : "saveTransfer.failureIntro"))
                    .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                if store.needsNewerVersion { SaveTransferUpdateButton() }
            } else {
                cardHeading("saveTransfer.restoreTitle", subtitle: "saveTransfer.importShortHint",
                            symbol: "square.and.arrow.down", tint: RoomTheme.gold)
            }
            Button { retryExport = false; statusKey = nil; isImportingFile = true } label: {
                Label(GameStrings.text("saveTransfer.chooseFile"), systemImage: "doc.badge.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SaveTransferOutlineButtonStyle(tint: RoomTheme.gold, fill: RoomTheme.rewardPaper))
            .disabled(busy).accessibilityIdentifier("saveImportButton")
        }
        .padding(16).gameCard(cornerRadius: 28)
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GameStrings.text("saveTransfer.recoveryTitle")).font(.headline.weight(.heavy))
                .accessibilityIdentifier("saveRecoveryCard")
            Text(GameStrings.text("saveTransfer.singleRecoveryHint"))
                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            VStack(alignment: .leading, spacing: 12) {
                if let recovery {
                    HStack(spacing: 10) {
                        GameIconTile(symbol: "clock.arrow.circlepath", tint: RoomTheme.lilac,
                                     background: RoomTheme.lilac.opacity(0.12), size: 44)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(SaveTransferPresentation.summary(recovery.snapshot)).font(.subheadline.weight(.heavy))
                            Text(dateText(recovery.snapshot.meta.lastSyncAt)).font(.caption.weight(.bold))
                                .foregroundStyle(RoomTheme.secondary)
                        }
                    }
                    Button { previewRecovery() } label: { Text(GameStrings.text("saveTransfer.previewRecovery")) }
                        .buttonStyle(SaveTransferOutlineButtonStyle(tint: RoomTheme.lilac))
                        .disabled(busy).accessibilityIdentifier("saveRecoveryButton")
                } else {
                    Text(GameStrings.text(recoveryUnavailable ? "saveTransfer.unknownRecovery" : "saveTransfer.noRecovery"))
                        .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(
                recovery == nil ? RoomTheme.rewardBorder : RoomTheme.lilac.opacity(0.35),
                style: StrokeStyle(lineWidth: 2, dash: recovery == nil ? [6, 4] : [])))
        }
    }

    private func cardHeading(_ title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GameIconTile(symbol: symbol, tint: tint, background: tint.opacity(0.15), size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(GameStrings.text(title)).font(.headline.weight(.heavy))
                Text(GameStrings.text(subtitle)).font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var modal: some View {
        if isRestoring {
            SaveTransferWorkingView(recoveryOnly: recoveryOnly).background(RoomTheme.cream.ignoresSafeArea())
        } else if let issue {
            SaveTransferErrorView(reason: issue, recoveryOnly: recoveryOnly, retryExport: retryExport,
                chooseAgain: {
                    if issue == .currentSaveReadable { retryReadAfterDismiss = true }
                    else { chooseAfterDismiss = true }
                    isShowingModal = false
                },
                close: { cancelPreview() })
        } else if didRestore, let snapshot = store.snapshot {
            SaveTransferSuccessView(snapshot: snapshot, recovery: recovery, recoveryUnavailable: recoveryUnavailable,
                home: { isShowingModal = false; onReturnHome?() },
                stay: { isShowingModal = false })
        } else if let preview {
            confirmation(preview)
        }
    }

    private func confirmation(_ candidate: ImportPreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(GameStrings.text(candidate.isRecovery ? "saveTransfer.recoveryPreviewTitle" : "saveTransfer.filePreview"))
                        .font(.title2.weight(.heavy))
                    Spacer(minLength: 4)
                    Button { cancelPreview() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).frame(width: 44, height: 44)
                            .background(RoomTheme.chipBg, in: Circle())
                    }
                    .buttonStyle(.plain).disabled(busy).accessibilityLabel(GameStrings.text("common.close"))
                    .accessibilityIdentifier("savePreviewCloseButton")
                }
                if recoveryOnly && store.needsNewerVersion {
                    SaveTransferNotice(text: GameStrings.text("saveTransfer.failureNewerIntro"), symbol: "arrow.up.circle.fill", tint: RoomTheme.gold)
                }
                SaveTransferPostcard(filename: candidate.filename, byteCount: candidate.byteCount,
                    subtitle: recoveryOnly ? GameStrings.format("saveTransfer.previewIdentity", SaveTransferPresentation.player(candidate.archive.snapshot), dateText(candidate.archive.exportedAt)) : nil,
                    snapshot: recoveryOnly ? candidate.archive.snapshot : nil, isRecovery: candidate.isRecovery)
                if !recoveryOnly, let current = store.snapshot {
                    SaveTransferComparisonView(current: current, incoming: candidate.archive.snapshot,
                                               isRecovery: candidate.isRecovery, language: store.language)
                    if SaveTransferComparison.isEarlier(current: current, incoming: candidate.archive.snapshot) {
                        SaveTransferNotice(text: GameStrings.text("saveTransfer.earlierBackup"), symbol: "clock.arrow.circlepath", tint: RoomTheme.gold)
                            .accessibilityIdentifier("saveEarlierBackupNotice")
                    } else {
                        Text(GameStrings.text("saveTransfer.importHint")).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    }
                    SaveTransferNotice(text: GameStrings.text("saveTransfer.replaceWarning"), symbol: "exclamationmark.circle.fill", tint: RoomTheme.coral)
                }
                if recoveryOnly {
                    SaveTransferNotice(text: GameStrings.text("saveTransfer.failurePreservePromise"), symbol: "checkmark.shield.fill")
                        .accessibilityIdentifier("saveFailureRawPreservationNotice")
                    Text(GameStrings.text("saveTransfer.failureEvidenceHint")).font(.caption.weight(.bold))
                        .foregroundStyle(RoomTheme.secondary)
                } else {
                    recoveryPromise(candidate)
                }
                Button { acknowledged.toggle() } label: {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                            .font(.title2).foregroundStyle(acknowledged ? RoomTheme.mint : RoomTheme.secondary)
                        Text(GameStrings.text("saveTransfer.acknowledge")).font(.subheadline.weight(.bold))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(busy).accessibilityValue(acknowledged ? "1" : "0")
                .accessibilityAddTraits(acknowledged ? [.isSelected] : [])
                .accessibilityIdentifier("saveImportAcknowledgement")
                if recoveryOnly && store.needsNewerVersion { SaveTransferUpdateButton() }
                if recoveryOnly && store.needsNewerVersion {
                    confirmButton(candidate).buttonStyle(SaveTransferOutlineButtonStyle())
                } else { confirmButton(candidate).buttonStyle(MintButtonStyle()) }
                Button { cancelPreview() } label: {
                    Text(GameStrings.text(recoveryOnly ? "common.cancel" : "saveTransfer.cancelKeepProgress"))
                        .font(.subheadline.weight(.heavy))
                }
                .buttonStyle(SoftButtonStyle()).disabled(busy).accessibilityIdentifier("saveCancelImportButton")
            }
            .padding(16).padding(.top, 10).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(RoomTheme.cream.ignoresSafeArea()).accessibilityIdentifier("saveImportPreview")
    }

    private func confirmButton(_ candidate: ImportPreview) -> some View {
        Button { confirm(candidate) } label: {
            Text(GameStrings.text(recoveryOnly ? "saveTransfer.failureConfirm"
                                  : (candidate.isRecovery ? "saveTransfer.confirmRecovery" : "saveTransfer.confirmImport")))
                .font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
        }
        .disabled(!acknowledged || busy).accessibilityIdentifier("saveConfirmImportButton")
    }

    private func recoveryPromise(_ candidate: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(GameStrings.text("saveTransfer.recoveryPromise"), systemImage: "checkmark.shield.fill")
                .accessibilityIdentifier("saveRecoveryPromise")
            if candidate.isRecovery {
                Text(GameStrings.text("saveTransfer.recoverySwapHint"))
            }
            if let recovery {
                Text(GameStrings.text("saveTransfer.replaceRecovery")).accessibilityIdentifier("saveRecoveryReplacementWarning")
                Text(SaveTransferPresentation.summary(recovery.snapshot)).accessibilityIdentifier("saveExistingRecoverySummary")
                Text(dateText(recovery.snapshot.meta.lastSyncAt)).font(.caption.weight(.bold))
                    .accessibilityIdentifier("saveExistingRecoveryTime")
            } else if recoveryUnavailable {
                Text(GameStrings.text("saveTransfer.unknownRecovery")).accessibilityIdentifier("saveRecoveryReplacementWarning")
            }
        }
        .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.lilac)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.lilac.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(RoomTheme.lilac.opacity(0.28), lineWidth: 2))
    }

    private func prepareExport() {
        guard !busy else { return }
        retryExport = true
        setWorking(true); statusKey = nil
        Task {
            defer { setWorking(false) }
            do {
                let data = try await store.exportSaveArchive()
                let prepared = try await Task.detached {
                    let exportedAt = try NativeSaveTransfer.decode(data).exportedAt
                    let filename = SaveArchiveFiles.backupFilename(exportedAt: exportedAt)
                    // FileExporter can write the in-memory document to another provider
                    // even when local storage cannot create a ShareLink attachment.
                    return (try? SaveArchiveFiles.prepareShareFile(data, filename: filename), exportedAt, filename)
                }.value
                exportDocument = SaveArchiveDocument(data: data)
                exportURL = prepared.0; exportDate = prepared.1; exportSize = data.count
                exportFilename = prepared.2
            } catch { report(error) }
        }
    }

    private func presentPreservedExport(_ document: SaveArchiveDocument, filename: String,
                                       completion: @escaping (Result<URL, Error>?) -> Void) {
        presentedExportDocument = document
        presentedExportFilename = filename
        presentedExportCompletion = completion
        isExportingFile = true
    }

    private func readImport(_ url: URL) {
        retryExport = false
        setWorking(true); statusKey = nil
        Task {
            defer { setWorking(false) }
            do {
                let selection = try await Task.detached { try SaveArchiveFiles.readSelection(url) }.value
                if !recoveryOnly { await refreshRecovery() }
                showPreview(ImportPreview(archive: selection.archive, filename: selection.filename,
                                          byteCount: selection.byteCount, isRecovery: false))
            } catch { report(error) }
        }
    }

    private func previewRecovery() {
        guard !busy else { return }
        retryExport = false
        setWorking(true); statusKey = nil
        Task {
            defer { setWorking(false) }
            await refreshRecovery()
            if let recovery {
                showPreview(ImportPreview(archive: recovery, filename: GameStrings.text("saveTransfer.recoveryTitle"), byteCount: nil, isRecovery: true))
            } else if recoveryUnavailable { report(SaveTransferError.readFailed) }
        }
    }

    private func showPreview(_ candidate: ImportPreview) {
        do { try NativeSaveTransfer.validateImportTime(candidate.archive) }
        catch { report(error); return }
        preview = candidate; acknowledged = false; issue = nil; didRestore = false; retryExport = false
        isShowingModal = true
    }

    private func confirm(_ candidate: ImportPreview) {
        guard acknowledged, !busy else { return }
        setWorking(true); isRestoring = true; statusKey = nil
        Task {
            defer { setWorking(false); isRestoring = false }
            do {
                if recoveryOnly { try await store.restoreSaveArchiveAfterLoadFailure(candidate.archive) }
                else { try await store.importSaveArchive(candidate.archive, isRecovery: candidate.isRecovery) }
                exportDocument = nil; exportURL = nil; exportDate = nil; exportSize = nil
                acknowledged = false
                if recoveryOnly {
                    didRestore = true
                    setStatus("saveTransfer.failureRestored")
                    isShowingModal = false
                    setWorking(false); isRestoring = false
                    onRecovered?()
                } else {
                    await refreshRecovery()
                    setStatus(candidate.isRecovery ? "saveTransfer.restored" : "saveTransfer.imported")
                    didRestore = true
                }
            } catch {
                if !recoveryOnly { await refreshRecovery() }
                acknowledged = false
                report(error)
            }
        }
    }

    private func refreshRecovery() async {
        recoveryUnavailable = true; recovery = nil
        do { recovery = try await store.importRecoveryPreview(); recoveryUnavailable = false }
        catch { /* A recovery-point read failure must not misreport an already committed import. */ }
    }

    private func cancelPreview() {
        guard !isWorking else { return }
        setStatus(issue == .writeFailed ? "saveTransfer.originalPreserved" : "saveTransfer.unchanged")
        isShowingModal = false
    }

    private func modalDismissed() {
        if !didRestore && preview != nil && statusKey == nil { setStatus("saveTransfer.unchanged") }
        preview = nil; issue = nil; acknowledged = false; didRestore = false
        if retryReadAfterDismiss {
            retryReadAfterDismiss = false
            onRetryLoad?()
        } else if chooseAfterDismiss {
            chooseAfterDismiss = false; statusKey = nil
            if retryExport { prepareExport() } else { isImportingFile = true }
        }
    }

    private func setWorking(_ value: Bool) { isWorking = value; onWorkingChange?(value) }

    private func dateText(_ date: Date) -> String { SaveTransferPresentation.date(date, language: store.language) }
    private func setStatus(_ key: String) { statusKey = key }

    private func report(_ error: Error) {
        if (error as? CocoaError)?.code == .userCancelled { setStatus("saveTransfer.unchanged"); return }
        issue = SaveTransferError.reason(for: error)
        didRestore = false; isShowingModal = true
    }
}
