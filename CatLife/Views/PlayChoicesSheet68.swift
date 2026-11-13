import SwiftUI
import CatGameCore

enum PlayChoice68: Equatable { case quick, together }

@MainActor
struct PlayChoicesSheet68: View {
    let store: GameStore
    let onChoose: (PlayChoice68) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var tutorialAvailable: Bool { PlayDesign68Presentation.tutorialAvailable(in: store.snapshot) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    if let cat = store.cat {
                        GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 52)
                            .padding(6).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(GameStrings.text("catHabits.choosePlay")).font(.title3.weight(.heavy))
                            .accessibilityAddTraits(.isHeader)
                        Text(GameStrings.format("play68.inventory", store.snapshot?.inventory.toys ?? 0))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                }
                if tutorialAvailable {
                    Label(GameStrings.text("catHabits.intro"), systemImage: "sparkles")
                        .font(.footnote.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(RoomTheme.rewardBorder, lineWidth: 2))
                        .accessibilityIdentifier("playChoiceFirstFree")
                }
                choice(.quick)
                choice(.together)
            }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(RoomTheme.cream.ignoresSafeArea()).foregroundStyle(RoomTheme.ink).fontDesign(.rounded)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .accessibilityIdentifier("playChoicesSheet68")
    }

    @ViewBuilder private func choice(_ choice: PlayChoice68) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            let together = choice == .together
            let title = GameStrings.text(together ? "catHabits.playTogether" : "catHabits.quickPlay")
            let description = GameStrings.text(together ? "play68.togetherBody" : "play68.quickBody")
            let badge = together ? GameStrings.text(tutorialAvailable ? "play68.freeBadge" : "play68.learnBadge") : ""
            let duration = together ? GameStrings.format("play68.duration", Int(CatHabitCatalog.playDuration)) : GameStrings.text("play68.instant")
            let cost = GameStrings.text(together ? (tutorialAvailable ? "catHabits.freeHint" : "catHabits.costHint") : "play68.oneToy")
            VStack(alignment: .leading, spacing: 12) {
                if together {
                    Text(badge).font(.caption.weight(.heavy)).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoomTheme.friendship, in: Capsule()).frame(maxWidth: .infinity, alignment: .trailing)
                        .accessibilityHidden(true)
                }
                accessibleChoiceHeading(choice, title: title,
                    spokenTitle: together ? title + ", " + badge : title,
                    hint: [description, duration, cost, together ? GameStrings.text("play68.clueTag") : ""].joined(separator: " "))
                Text(description).font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) { tags(together: together) }
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityHidden(true)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(together ? RoomTheme.friendship : .white, lineWidth: 3))
        } else {
            regularChoice(choice)
        }
    }

    private func accessibleChoiceHeading(_ choice: PlayChoice68, title: String, spokenTitle: String, hint: String) -> some View {
        let together = choice == .together
        let tint: Color = together ? RoomTheme.friendshipDeep : RoomTheme.gold
        return Button { onChoose(choice) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: together ? "leaf.fill" : "bolt.fill")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 38, height: 44).accessibilityHidden(true)
                Text(title).font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                    .frame(width: 16, height: 44).accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(store.isBusy)
        .accessibilityIdentifier(together ? "playTogetherChoice" : "quickPlayChoice")
        .accessibilityLabel(spokenTitle).accessibilityHint(hint)
    }

    private func regularChoice(_ choice: PlayChoice68) -> some View {
        let together = choice == .together
        let tint = together ? RoomTheme.friendshipDeep : RoomTheme.gold
        return Button { onChoose(choice) } label: {
            VStack(alignment: .leading, spacing: 10) {
                if together {
                    Text(GameStrings.text(tutorialAvailable ? "play68.freeBadge" : "play68.learnBadge"))
                        .font(.caption.weight(.heavy)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoomTheme.friendship, in: Capsule()).frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: together ? "leaf.fill" : "bolt.fill")
                        .font(.system(size: 28, weight: .bold)).foregroundStyle(tint)
                        .frame(width: 52, height: 60)
                        .background(together ? RoomTheme.friendshipPaper : RoomTheme.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(GameStrings.text(together ? "catHabits.playTogether" : "catHabits.quickPlay"))
                            .font(.headline.weight(.heavy))
                        Text(GameStrings.text(together ? "play68.togetherBody" : "play68.quickBody"))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).accessibilityHidden(true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { tags(together: together) }
                    VStack(alignment: .leading, spacing: 6) { tags(together: together) }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(together ? RoomTheme.friendship : .white, lineWidth: 3))
                .contentShape(RoundedRectangle(cornerRadius: 25))
        }.buttonStyle(.plain).disabled(store.isBusy)
            .accessibilityIdentifier(together ? "playTogetherChoice" : "quickPlayChoice")
    }

    @ViewBuilder private func tags(together: Bool) -> some View {
        tag(together ? GameStrings.format("play68.duration", Int(CatHabitCatalog.playDuration))
            : GameStrings.text("play68.instant"), color: RoomTheme.secondary)
        tag(GameStrings.text(together && tutorialAvailable ? "play68.freeTag" : "play68.oneToy"),
            color: together && tutorialAvailable ? RoomTheme.darkMint : RoomTheme.gold)
        if together { tag(GameStrings.text("play68.clueTag"), color: RoomTheme.friendshipDeep) }
    }
    private func tag(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.09), in: Capsule())
    }
}
