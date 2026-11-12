import SwiftUI
import CatGameCore

@MainActor
enum CompanionshipPresentation {
    static let pinnableMemories: [CatMemoryKind] = [.favoritePlay, .littleCorner, .settledAfterMove]

    static func guideKey(for memory: CatMemoryKind) -> String {
        "habit67.guide.\(memory.rawValue)"
    }

    static func memoryBody(for memory: CatMemoryKind, cat: CatState) -> String {
        if memory == .settledAfterMove, let style = CatHabitCatalog.definition(for: cat.id)?.style {
            return GameStrings.text("catMemories.settledAfterMove.body.\(style.rawValue)")
        }
        return GameStrings.text(memory.bodyKey)
    }

    static func guidance(for memory: CatMemoryKind, cat: CatState) -> String {
        if memory == .favoritePlay, cat.habits.playConfirmed,
           let preference = CatHabitCatalog.definition(for: cat.id)?.play {
            return GameStrings.format("habit67.guide.favoritePlay.known",
                                      GameStrings.text("catHabits.playConfirmed.\(preference.rawValue)"))
        }
        return GameStrings.text("habit67.guide.\(memory.rawValue).body")
    }

    static func shopGoal(for product: ShopListing, cat: CatState?) -> String? {
        guard let cat else { return nil }
        if product.kind == .furniture, let offer = ShopCatalog.furnitureOffer(id: product.id),
           CatRestPreference(kind: offer.kind) != nil {
            if cat.habits.memories.contains(where: { $0.kind == .settledAfterMove }) {
                return GameStrings.text("habit67.memoryRecorded")
            }
            return GameStrings.format("habit67.shop.restGoal", GameStrings.catName(cat))
        }
        if product.kind == .supply(.toy) {
            return GameStrings.format("habit67.shop.playGoal", GameStrings.catName(cat))
        }
        return nil
    }

    static func neighborDialogue(for cat: CatState?) -> String? {
        guard let cat, let definition = CatHabitCatalog.definition(for: cat.id) else { return nil }
        let name = GameStrings.catName(cat)
        let rest = GameStrings.text("catHabits.restConfirmed.\(definition.rest.rawValue)")
        let play = GameStrings.text("catHabits.playConfirmed.\(definition.play.rawValue)")
        switch (cat.habits.restConfirmed, cat.habits.playConfirmed) {
        case (true, true): return GameStrings.format("habit67.neighbor.both", name, rest, play)
        case (true, false): return GameStrings.format("habit67.neighbor.rest", name, rest)
        case (false, true): return GameStrings.format("habit67.neighbor.play", name, play)
        case (false, false): return GameStrings.format("habit67.neighbor.learning", name)
        }
    }
}

@MainActor
struct PinnedHabitPrompt: View {
    let store: GameStore
    let cat: CatState
    let memory: CatMemoryKind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var collapsed: Bool { cat.habits.pinnedHintCollapsed }
    private var completed: Bool { cat.habits.memories.contains { $0.kind == memory } }
    private var symbol: String {
        switch memory {
        case .favoritePlay: "sparkles"
        case .littleCorner: "flag.fill"
        default: "arrow.up.left.and.arrow.down.right"
        }
    }
    private var tone: Color { memory == .settledAfterMove ? Color(red: 61/255, green: 127/255, blue: 168/255) : RoomTheme.friendshipDeep }
    private var tint: Color { memory == .settledAfterMove ? Color(red: 216/255, green: 232/255, blue: 242/255) : RoomTheme.friendshipPaper }

    var body: some View {
        VStack(alignment: .leading, spacing: collapsed ? 0 : 10) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 8) {
                    Text(GameStrings.text(CompanionshipPresentation.guideKey(for: memory)))
                        .font(collapsed ? .caption.weight(.heavy) : .subheadline.weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("habitPinnedHintTitle")
                    Button {
                        Task { _ = await store.setPinnedHabitHintCollapsed(catID: cat.id, collapsed: !collapsed) }
                    } label: {
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.ink)
                            .frame(width: 44, height: 44).background(RoomTheme.chipBg.opacity(0.5), in: Circle())
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(store.isBusy)
                    .accessibilityLabel(GameStrings.format(collapsed ? "habit67.expandGuide" : "habit67.collapseGuide",
                        GameStrings.text(CompanionshipPresentation.guideKey(for: memory))))
                    .accessibilityIdentifier("habitPinnedHintToggle")
                }
            } else {
                Button {
                    Task { _ = await store.setPinnedHabitHintCollapsed(catID: cat.id, collapsed: !collapsed) }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: symbol).font(.system(size: collapsed ? 13 : 18, weight: .bold))
                            .foregroundStyle(tone).frame(width: collapsed ? 24 : 34, height: collapsed ? 24 : 34)
                            .background(tint, in: RoundedRectangle(cornerRadius: 11)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            if !collapsed {
                                Label(GameStrings.format("design68.pin.forCat", GameStrings.catName(cat)), systemImage: "pin.fill")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                            }
                            HStack(spacing: 4) {
                                Text(GameStrings.text(CompanionshipPresentation.guideKey(for: memory)))
                                    .font(collapsed ? .caption.weight(.heavy) : .subheadline.weight(.heavy))
                                if collapsed && completed { Image(systemName: "checkmark.circle.fill").foregroundStyle(RoomTheme.darkMint) }
                            }.fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: collapsed ? "chevron.down" : "chevron.up").font(.system(size: 12, weight: .heavy))
                            .frame(width: 32, height: 32).background(RoomTheme.chipBg.opacity(0.5), in: Circle())
                    }.foregroundStyle(RoomTheme.ink).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(store.isBusy)
                .accessibilityLabel(GameStrings.format(collapsed ? "habit67.expandGuide" : "habit67.collapseGuide",
                    GameStrings.text(CompanionshipPresentation.guideKey(for: memory))))
                .accessibilityIdentifier("habitPinnedHintToggle")
            }
            if !collapsed {
                if dynamicTypeSize.isAccessibilitySize {
                    Label(GameStrings.format("design68.pin.forCat", GameStrings.catName(cat)), systemImage: "pin.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(CompanionshipPresentation.guidance(for: memory, cat: cat))
                    .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if completed {
                    Label(GameStrings.text("habit67.memoryRecorded"), systemImage: "checkmark.circle.fill")
                        .font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                        .padding(7).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.paleMint.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { actions; Spacer(minLength: 0); footer }
                    VStack(alignment: .leading, spacing: 3) { HStack(spacing: 16) { actions }; footer }
                }
            }
        }.padding(.horizontal, collapsed ? 10 : 12).padding(.vertical, collapsed ? 2 : 10)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: collapsed ? 22 : 20))
            .overlay(RoundedRectangle(cornerRadius: collapsed ? 22 : 20)
                .strokeBorder(completed ? RoomTheme.mint : .white, lineWidth: completed ? 1.5 : 2))
            .accessibilityElement(children: .contain).accessibilityIdentifier("habitPinnedPrompt")
            .accessibilityValue(TownEventAccessibility.value(GameStrings.catName(cat),
                diagnostic: "\(memory.rawValue)|\(collapsed ? "collapsed" : "expanded")"))

    }
    @ViewBuilder private var actions: some View {
        Button(GameStrings.text("habit67.changeGuide")) { store.habitGuideCatID = cat.id }
            .font(.caption.weight(.bold)).buttonStyle(.plain).frame(minHeight: 44)
            .foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("homeHabitChangeGuide")
        Button(GameStrings.text("habit67.unpin")) { Task { _ = await store.pinHabitMemory(catID: cat.id, memory: nil) } }
            .font(.caption.weight(.bold)).buttonStyle(.plain).frame(minHeight: 44)
            .foregroundStyle(RoomTheme.secondary).accessibilityIdentifier("homeHabitUnpin")
    }
    private var footer: some View {
        Text(GameStrings.text("design68.pin.noDeadline")).font(.caption2.weight(.medium))
            .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
