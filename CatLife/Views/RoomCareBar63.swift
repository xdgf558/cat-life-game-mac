import SwiftUI

@MainActor
struct RoomCareBar63: View {
    let store: GameStore
    let presentation: CatNeedPresentation
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var reducedMotion = false
    private var reduceMotion: Bool { systemReduceMotion || reducedMotion }

    private var need: CatNeed? { CatNeed.current(in: store) }
    private var foodUsesPremium: Bool { CatNeed.food.premiumChoice(in: store) }
    private var cleanUsesPremium: Bool { CatNeed.clean.premiumChoice(in: store) }

    var body: some View {
        HStack(spacing: 8) {
            careButton(.food, key: "care.feed", count: foodUsesPremium
                ? (store.snapshot?.inventory.premiumFood ?? 0) : store.totalFood,
                premium: foodUsesPremium, stockID: "foodCount") { store.feed() }
            careButton(.clean, key: "care.clean", count: cleanUsesPremium
                ? (store.snapshot?.inventory.premiumLitter ?? 0) : (store.snapshot?.inventory.litter ?? 0),
                premium: cleanUsesPremium, stockID: cleanUsesPremium ? "litterPremiumCount" : "litterCount") { store.clean() }
            careButton(.play, key: "care.play", count: store.snapshot?.inventory.toys ?? 0,
                premium: false, stockID: "toyCount") { store.presentPlayChoices() }
        }
        .opacity(store.cat?.activeRest == nil ? 1 : 0.5)
        .disabled(store.isBusy || store.isDecorating || store.cat == nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeCareBar63")
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { presentation.careActionsFrame = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in presentation.careActionsFrame = frame }
            }.allowsHitTesting(false)
        }
        .onDisappear { presentation.careActionsFrame = nil }
        .onboardingTarget(.care)
    }

    private func careButton(_ action: CatNeed, key: String, count: Int, premium: Bool,
                            stockID: String, perform: @escaping () -> Void) -> some View {
        let highlighted = need?.careButtonID == action.careButtonID
        return Button(action: perform) {
            VStack(spacing: 3) {
                GameIcon(asset: action.assetName, symbol: action.symbol, size: 28,
                         tint: highlighted ? RoomTheme.friendshipDeep : RoomTheme.ink)
                    .frame(width: 28, height: 28).accessibilityHidden(true)
                Text(GameStrings.text(key)).font(.system(size: 13, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(highlighted ? RoomTheme.friendshipDeep : RoomTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 22).fill(highlighted ? RoomTheme.friendshipPaper : RoomTheme.paper)
                    .shadow(color: highlighted ? RoomTheme.friendshipDeep.opacity(0.25) : RoomTheme.ink.opacity(0.1), radius: 0, y: 3)
            }
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(highlighted ? RoomTheme.friendship : .white, lineWidth: 2))
            .opacity(count == 0 ? 0.58 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(action.careButtonID ?? "")
        .accessibilityLabel(GameStrings.text(key))
        .accessibilityHint(action.careHintKey(in: store).map { GameStrings.text($0) } ?? "")
        .background {
            if highlighted && !reduceMotion {
                RoundedRectangle(cornerRadius: 22).stroke(RoomTheme.friendship.opacity(0.55), lineWidth: 2)
                    .phaseAnimator([false, true]) { content, expanded in
                        content.opacity(expanded ? 0.1 : 0.65)
                    } animation: { _ in .easeInOut(duration: 0.8) }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            stock(count: count, premium: premium, action: action, identifier: stockID)
                .padding(.top, 10).padding(.trailing, 6)
        }
        .overlay(alignment: .top) {
            if highlighted, let cat = store.cat {
                Text(GameStrings.format("home63.needFor", GameStrings.catName(cat)))
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoomTheme.friendship, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                    .padding(.horizontal, 5).offset(y: -7)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("roomCareNeedBadge")
            }
        }
    }

    private func stock(count: Int, premium: Bool, action: CatNeed, identifier: String) -> some View {
        HStack(spacing: 2) {
            if premium { Image(systemName: "sparkle").accessibilityHidden(true) }
            Text("×\(count)")
        }
        .font(.system(size: 10, weight: .heavy)).foregroundStyle(premium ? PremiumSupplyStyle.effectText : RoomTheme.secondary)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(premium ? PremiumSupplyStyle.paper : RoomTheme.wood.opacity(0.2), in: Capsule())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(premium
            ? (action == .food ? "supply.premiumFood.name" : "supply.premiumLitter.name")
            : (action == .food ? "accessibility.food" : action == .clean ? "supply.litter.name" : "supply.toy.name")))
        .accessibilityValue("\(count)")
        .accessibilityIdentifier(identifier)
    }
}
