import SwiftUI
import Observation

/// Presentation priorities only; care effects and spending still belong to Core.
enum CatNeed: Equatable {
    case food, buyFood, clean, play, hospital

    static func current(satiety: Int, cleanliness: Int, mood: Int, hasFood: Bool, isIll: Bool = false) -> CatNeed? {
        if isIll { return .hospital }
        if satiety < 50 { return hasFood ? .food : .buyFood }
        if cleanliness < 40 { return .clean }
        if mood < 45 { return .play }
        return nil
    }

    @MainActor static func current(in store: GameStore) -> CatNeed? {
        guard let cat = store.cat else { return nil }
        return current(satiety: cat.satiety, cleanliness: cat.cleanliness, mood: cat.mood,
                       hasFood: store.hasFood, isIll: cat.healthState?.illness != nil)
    }

    var titleKey: String {
        switch self {
        case .food: "catNeed.food"
        case .buyFood: "catNeed.buyFood"
        case .clean: "catNeed.clean"
        case .play: "catNeed.play"
        case .hospital: "hospital.healthAlert"
        }
    }
    var shortTitleKey: String {
        switch self {
        case .food, .buyFood: "home63.need.food"
        case .clean: "home63.need.clean"
        case .play: "home63.need.play"
        case .hospital: "home63.need.hospital"
        }
    }
    var careButtonID: String? {
        switch self {
        case .food, .buyFood: "feedButton"
        case .clean: "cleanButton"
        case .play: "playButton"
        case .hospital: nil
        }
    }
    var assetName: String {
        switch self {
        case .food, .buyFood: "bowl-full"
        case .clean: "icon-clean"
        case .play: "icon-play"
        case .hospital: "town-hospital-cartoon"
        }
    }
    var symbol: String {
        switch self {
        case .food: "takeoutbag.and.cup.and.straw.fill"
        case .buyFood: "basket.fill"
        case .clean: "sparkles"
        case .play: "party.popper.fill"
        case .hospital: "cross.case.fill"
        }
    }
    @MainActor func premiumChoice(in store: GameStore) -> Bool {
        if self == .food {
            return (store.snapshot?.inventory.food ?? 0) < store.foodRequired
                && (store.snapshot?.inventory.premiumFood ?? 0) >= store.foodRequired
        }
        return self == .clean && (store.snapshot?.inventory.litter ?? 0) == 0
            && (store.snapshot?.inventory.premiumLitter ?? 0) > 0
    }
    @MainActor func careHintKey(in store: GameStore) -> String? {
        switch self {
        case .food, .buyFood:
            if !store.hasFood { return "care.shopFood" }
        case .clean:
            if (store.snapshot?.inventory.litter ?? 0) == 0 && (store.snapshot?.inventory.premiumLitter ?? 0) == 0 {
                return "care.shopLitter"
            }
        case .play: return "catHabits.choosePlay"
        case .hospital: return nil
        }
        return premiumChoice(in: store) ? actionTitleKey(in: store) : nil
    }
    @MainActor func actionTitleKey(in store: GameStore) -> String {
        guard premiumChoice(in: store) else { return titleKey }
        if self == .food {
            return (store.snapshot?.inventory.food ?? 0) == 0 ? "supply.home.foodChoice" : "supply.home.foodShort"
        }
        return "supply.home.litterChoice"
    }
}

/// SpriteKit samples at most 10 times per second and ignores sub-point idle motion.
struct CatNeedAnchorSampler {
    private var sampledAt = -Double.infinity
    private(set) var point: CGPoint?

    mutating func sample(_ proposed: CGPoint?, at time: TimeInterval) -> Bool {
        guard time < sampledAt || time - sampledAt >= 0.1 else { return false }
        sampledAt = time
        if let point, let proposed {
            guard hypot(point.x - proposed.x, point.y - proposed.y) > 1 else { return false }
        } else if point == nil, proposed == nil { return false }
        point = proposed
        return true
    }
}

enum CatNeedBubbleLayout {
    static func position(above anchor: CGPoint, in size: CGSize,
                         bubbleSize: CGSize = CGSize(width: 190, height: 44), avoiding obstacle: CGRect = .zero,
                         bottomInset: CGFloat = 76) -> CGPoint {
        let usableHeight = max(0, size.height - max(0, bottomInset))
        let minimumX = min(bubbleSize.width / 2 + 8, max(0, size.width / 2))
        let minimumY = min(bubbleSize.height / 2 + 8, usableHeight / 2)
        let maximumY = max(minimumY, usableHeight - bubbleSize.height / 2 - 8)
        func clamped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: min(max(minimumX, size.width - minimumX), max(minimumX, point.x)),
                    y: min(maximumY, max(minimumY, point.y)))
        }
        let preferred = clamped(CGPoint(x: anchor.x, y: anchor.y - bubbleSize.height / 2 - 6))
        guard !obstacle.isEmpty else { return preferred }
        let blocked = obstacle.insetBy(dx: -8, dy: -8)
        func isClear(_ center: CGPoint) -> Bool {
            !CGRect(x: center.x - bubbleSize.width / 2, y: center.y - bubbleSize.height / 2,
                    width: bubbleSize.width, height: bubbleSize.height).intersects(blocked)
        }
        guard !isClear(preferred) else { return preferred }
        let candidates = [
            CGPoint(x: blocked.minX - bubbleSize.width / 2 - 1, y: preferred.y),
            CGPoint(x: blocked.maxX + bubbleSize.width / 2 + 1, y: preferred.y),
            CGPoint(x: preferred.x, y: blocked.minY - bubbleSize.height / 2 - 1),
            CGPoint(x: preferred.x, y: blocked.maxY + bubbleSize.height / 2 + 1)
        ].map(clamped)
        return candidates.first(where: isClear) ?? preferred
    }
}

/// Keeping the observed anchor in this leaf isolates motion from the room/HUD view tree.
@MainActor @Observable
final class CatNeedPresentation {
    var stageFrame: CGRect?
    var headerFrame: CGRect?
    var careActionsFrame: CGRect?
    var isInspectingResident = false
    var anchor: CGPoint?
    var localCatFrame: CGRect?
    var canvasOrigin = CGPoint.zero
    var catFrame: CGRect? { localCatFrame?.offsetBy(dx: canvasOrigin.x, dy: canvasOrigin.y) }
}

@MainActor
struct CatNeedBubble: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var reducedMotion = false
    private var reduceMotion: Bool { systemReduceMotion || reducedMotion }
    @State private var bubbleSize = CGSize(width: 174, height: 54)
    let store: GameStore
    let presentation: CatNeedPresentation
    let canvasSize: CGSize
    let isActive: Bool
    let canAct: () -> Bool
    var avoidingFrame: CGRect = .zero
    var bottomInset: CGFloat = 76

    var body: some View {
        if isActive, !store.isBusy, !store.isDecorating, !presentation.isInspectingResident,
           let anchor = presentation.anchor, let cat = store.cat {
            let need = CatNeed.current(in: store)
            let name = GameStrings.catName(cat)
            let center = CatNeedBubbleLayout.position(above: anchor, in: canvasSize,
                bubbleSize: bubbleSize, avoiding: avoidingFrame, bottomInset: bottomInset)
            if need != nil && !reduceMotion {
                marker(need: need, name: name, anchor: anchor, center: center)
                    .phaseAnimator([false, true]) { content, raised in
                        content.offset(y: raised ? -2 : 0)
                    } animation: { _ in .easeInOut(duration: 1.1) }
            } else {
                marker(need: need, name: name, anchor: anchor, center: center)
            }
        }
    }

    private func marker(need: CatNeed?, name: String, anchor: CGPoint, center: CGPoint) -> some View {
        Group {
            if let need {
                needButton(need, name: name, tail: (anchor.x - center.x) / max(1, bubbleSize.width) + 0.5)
            } else {
                Text(verbatim: "♥ " + name).font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(RoomTheme.darkMint).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoomTheme.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(RoomTheme.mint, lineWidth: 1.5))
                    .accessibilityIdentifier("catCompanionName")
                    .allowsHitTesting(false)
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { bubbleSize = geometry.size }
                    .onChange(of: geometry.size) { _, size in bubbleSize = size }
            }.allowsHitTesting(false)
        }
        .position(center)
    }

    private func needButton(_ need: CatNeed, name: String, tail: CGFloat) -> some View {
        Button {
            guard !store.isBusy, !store.isDecorating, need == .hospital || canAct() else { return }
            switch need {
            case .food, .buyFood: store.feed()
            case .clean: store.clean()
            case .play: store.presentPlayChoices()
            case .hospital: store.openHospital(catID: store.cat?.id)
            }
        } label: {
            HStack(spacing: 8) {
                GameIcon(asset: need.assetName, symbol: need.symbol, size: 26, tint: RoomTheme.friendship)
                    .frame(width: 26, height: 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "♥ " + name).font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(RoomTheme.darkMint)
                    Text(GameStrings.text(need.shortTitleKey)).font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(RoomTheme.friendshipDeep)
                }.lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10).padding(.vertical, 7).padding(.bottom, 8)
            .frame(minHeight: 44)
            .background(CatNeedBubbleShape(tail: tail).fill(RoomTheme.paper))
            .overlay(CatNeedBubbleShape(tail: tail).stroke(RoomTheme.friendship, lineWidth: 2))
            .shadow(color: RoomTheme.ink.opacity(0.14), radius: 5, y: 3)
            .contentShape(CatNeedBubbleShape(tail: tail))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("catNeedBubble")
        .accessibilityLabel(GameStrings.text(need.actionTitleKey(in: store)))
        .accessibilityValue(Text(verbatim: name))
    }
}

private struct CatNeedBubbleShape: Shape {
    var tail: CGFloat
    func path(in rect: CGRect) -> Path {
        let bottom = max(0, rect.height - 8)
        let radius = min(16, bottom / 2)
        let tip = min(rect.width - radius - 8, max(radius + 8, rect.width * tail))
        return Path { p in
            p.move(to: CGPoint(x: radius, y: 0))
            p.addLine(to: CGPoint(x: rect.width - radius, y: 0))
            p.addQuadCurve(to: CGPoint(x: rect.width, y: radius), control: CGPoint(x: rect.width, y: 0))
            p.addLine(to: CGPoint(x: rect.width, y: bottom - radius))
            p.addQuadCurve(to: CGPoint(x: rect.width - radius, y: bottom), control: CGPoint(x: rect.width, y: bottom))
            p.addLine(to: CGPoint(x: tip + 8, y: bottom))
            p.addLine(to: CGPoint(x: tip, y: rect.height))
            p.addLine(to: CGPoint(x: tip - 8, y: bottom))
            p.addLine(to: CGPoint(x: radius, y: bottom))
            p.addQuadCurve(to: CGPoint(x: 0, y: bottom - radius), control: CGPoint(x: 0, y: bottom))
            p.addLine(to: CGPoint(x: 0, y: radius))
            p.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
            p.closeSubpath()
        }
    }
}
