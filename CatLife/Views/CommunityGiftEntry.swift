import SwiftUI
import CatGameCore

struct CommunityGiftEntry: View {
    @Bindable var store: GameStore
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var count: Int {
        CommunityCatalog.gifts.reduce(0) { $0 + (store.snapshot?.inventory.giftCount($1.id) ?? 0) }
    }

    var body: some View {
        Button(action: open) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { giftIcon; Spacer(); chevron }
                        giftLabel.frame(maxWidth: .infinity, alignment: .leading)
                        giftStock
                    }
                } else {
                    HStack(spacing: 10) {
                        giftIcon
                        giftLabel
                        Spacer(minLength: 0)
                        giftStock
                        chevron
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RoomTheme.wood, lineWidth: 2))
        }
        .buttonStyle(.plain).disabled(store.isBusy).foregroundStyle(RoomTheme.ink)
        .accessibilityIdentifier("communityGiftEntry")
    }

    private var giftIcon: some View {
        Image(systemName: "gift.fill").font(.title2).foregroundStyle(RoomTheme.gold)
            .frame(width: 40, height: 40).background(RoomTheme.gold.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.heavy)).accessibilityHidden(true)
    }

    private var giftLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GameStrings.text("community.giftEntry")).font(.subheadline.weight(.heavy))
            Text(GameStrings.format("community.giftEntryCount", count))
                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var giftStock: some View {
        HStack(spacing: 3) {
            ForEach(CommunityCatalog.gifts) { gift in
                CommunityGiftIcon(gift: gift, size: 24)
                    .opacity((store.snapshot?.inventory.giftCount(gift.id) ?? 0) > 0 ? 1 : 0.4)
            }
        }.accessibilityHidden(true)
    }
}
