import SwiftUI

/// Recovery stays reachable after dismissing the alert or leaving a subpage.
struct SaveStatusBanner: View {
    @Bindable var store: GameStore

    var body: some View {
        if store.hasSaveFailure {
            VStack(alignment: .leading, spacing: 8) {
                Label(GameStrings.text("save.writeTitle"), systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                Text(GameStrings.text(store.saveRetryIsSlow ? "save.recoverySlow" : "save.recoveryPending"))
                    .font(.footnote).fixedSize(horizontal: false, vertical: true)
                Button { store.retrySaving() } label: {
                    Text(GameStrings.text(store.isBusy ? "common.saving" : "save.retry"))
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(SoftButtonStyle()).disabled(store.isBusy)
                .accessibilityIdentifier("saveStatusRetryButton")
            }
            .padding(12).foregroundStyle(RoomTheme.ink)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(RoomTheme.gold.opacity(0.6)))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("saveStatusBanner")
        }
    }
}

extension View {
    func saveRecoveryAlert(store: GameStore, isActive: Bool = true) -> some View {
        modifier(SaveRecoveryAlert(store: store, isActive: isActive))
    }
}

private struct SaveRecoveryAlert: ViewModifier {
    @Bindable var store: GameStore
    let isActive: Bool

    func body(content: Content) -> some View {
        content.alert(GameStrings.text("save.writeTitle"), isPresented: Binding(
            get: { isActive && store.showSaveError },
            set: { if isActive { store.showSaveError = $0 } }
        )) {
            Button(GameStrings.text("save.retry")) { store.retrySaving() }
            Button(GameStrings.text("common.done"), role: .cancel) { }
        } message: {
            Text(GameStrings.text("save.writeBody"))
        }
    }
}
