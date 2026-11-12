import SwiftUI
import CatGameCore

@MainActor
struct AdoptionAvailableBanner: View {
    @Bindable var store: GameStore
    let offer: CatAdoptionOffer

    var body: some View {
        HStack(spacing: 8) {
            GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: offer.appearance),
                     symbol: "cat.fill", size: 36, tint: RoomTheme.mint)
            Text(GameStrings.format("cat.adoptionUnlocked", GameStrings.catAdoptionName(offer)))
                .font(.system(size: 13, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(GameStrings.text("cat.adoptionSeeOffer")) {
                store.adoptionReminders.dismiss(offer.id)
                store.openCatCollection(filter: .unowned, adoptionID: offer.id)
            }
            .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            .frame(minHeight: 44).disabled(store.isBusy)
            .accessibilityIdentifier("adoptionReminderOpen")
            Button { store.adoptionReminders.dismiss(offer.id) } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel(GameStrings.text("common.close"))
            .accessibilityIdentifier("adoptionReminderDismiss")
        }
        .padding(.leading, 12).padding(.trailing, 4).gameCard(cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("adoptionAvailableNotice").accessibilityValue(offer.id)
        .task(id: offer.id) {
            store.adoptionReminders.markPresented(offer.id)
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            store.adoptionReminders.dismiss(offer.id)
        }
    }
}
