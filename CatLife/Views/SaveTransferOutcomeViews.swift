import SwiftUI
import CatGameCore

struct SaveTransferSuccessView: View {
    let snapshot: GameSnapshot
    let recovery: NativeSaveArchive?
    var recoveryUnavailable = false
    let home: () -> Void
    let stay: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                successCard
                    .padding(24)
                    .frame(maxWidth: 480)
                    .gameCard(cornerRadius: 32)
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(RoomTheme.cream.ignoresSafeArea()).accessibilityIdentifier("saveImportSuccess")
    }

    private var successCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark")
                .font(.system(size: 44, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                .frame(width: 104, height: 104).background(RoomTheme.paleMint, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 5)).padding(10)
                .background(RoomTheme.paleMint.opacity(0.4), in: Circle())
                .accessibilityHidden(true)
            Text(GameStrings.text("saveTransfer.successTitle"))
                .font(.title.weight(.heavy)).multilineTextAlignment(.center)
            Text(GameStrings.text(recoveryUnavailable ? "saveTransfer.successRecoveryUnknown"
                                  : (recovery == nil ? "saveTransfer.successNoRecovery" : "saveTransfer.successHint")))
                .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { summaries }
                VStack(spacing: 10) { summaries }
            }
            Button(action: home) {
                Label(GameStrings.text("saveTransfer.returnHome"), systemImage: "house.fill")
                    .font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(MintButtonStyle()).accessibilityIdentifier("saveReturnHomeButton")
            Button(action: stay) {
                Text(GameStrings.text("saveTransfer.stayManagement")).font(.subheadline.weight(.heavy))
            }
            .buttonStyle(SoftButtonStyle()).accessibilityIdentifier("saveStayManagementButton")
        }
    }

    @ViewBuilder private var summaries: some View {
        result(title: "saveTransfer.compare.current", snapshot: snapshot, tint: RoomTheme.darkMint)
        if let recovery {
            result(title: "saveTransfer.compare.recovery", snapshot: recovery.snapshot, tint: RoomTheme.lilac)
        }
    }

    private func result(title: String, snapshot: GameSnapshot, tint: Color) -> some View {
        VStack(spacing: 6) {
            Text(GameStrings.text(title)).font(.caption.weight(.heavy))
            Text(SaveTransferPresentation.summary(snapshot)).font(.subheadline.weight(.heavy))
        }
        .foregroundStyle(tint).padding(14).frame(maxWidth: .infinity)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SaveTransferErrorView: View {
    let reason: SaveTransferError
    var recoveryOnly = false
    var retryExport = false
    let chooseAgain: () -> Void
    let close: () -> Void

    private var titleKey: String {
        switch reason {
        case .busy: "saveTransfer.busy"
        case .invalidFile: "saveTransfer.error.invalidTitle"
        case .fileTooLarge: "saveTransfer.error.sizeTitle"
        case .unsupportedVersion: "saveTransfer.error.versionTitle"
        case .readFailed: "saveTransfer.error.readTitle"
        case .writeFailed: "saveTransfer.error.writeTitle"
        case .currentSaveReadable: "saveTransfer.error.readableTitle"
        case .futureProgress: "saveTransfer.error.futureTitle"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: reason == .writeFailed ? "externaldrive.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40, weight: .bold)).foregroundStyle(RoomTheme.coral)
                    .frame(width: 104, height: 104)
                    .background(RoomTheme.paleCoral.opacity(0.5), in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 4)).accessibilityHidden(true)
                Text(GameStrings.text(titleKey)).font(.title2.weight(.heavy)).multilineTextAlignment(.center)
                    .accessibilityIdentifier("saveImportErrorTitle")
                Text(GameStrings.text(reason == .writeFailed && recoveryOnly
                                      ? "saveTransfer.failureWriteFailed" : SaveTransferError.messageKey(for: reason)))
                    .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center).accessibilityIdentifier("saveImportError")
                Label(GameStrings.text(reason == .writeFailed ? "saveTransfer.originalPreserved" : "saveTransfer.unchanged"),
                      systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                    .padding(.horizontal, 16).padding(.vertical, 10).background(RoomTheme.paleMint, in: Capsule())
                    .accessibilityIdentifier("saveImportErrorSafety")
                if reason == .unsupportedVersion { SaveTransferUpdateButton() }
                Button(action: chooseAgain) {
                    Text(GameStrings.text(reason == .currentSaveReadable ? "saveTransfer.retryRead"
                                          : (retryExport ? "saveTransfer.retryExport" : "saveTransfer.chooseAgain")))
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle())
                .accessibilityIdentifier(reason == .currentSaveReadable ? "saveErrorRetryReadButton" : "saveErrorChooseAgainButton")
                Button(action: close) { Text(GameStrings.text("common.close")).font(.subheadline.weight(.heavy)) }
                    .buttonStyle(SoftButtonStyle()).accessibilityIdentifier("saveErrorCloseButton")
            }
            .padding(24).padding(.top, 30).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
        .background(RoomTheme.cream.ignoresSafeArea())
    }
}
