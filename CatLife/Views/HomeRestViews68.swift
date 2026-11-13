import SwiftUI
import CatGameCore

/// Display-only scene facts; no timing or recovery is committed from this value.
struct HomeRestScene68: Equatable {
    var phase = "layout-planning"
    var reasonKey: String? = "home68.rest.preparing"
    var requestFrame: CGRect?
    var cornerFrame: CGRect?
    var cornerAnchor: CGPoint?
    var canStart: Bool { reasonKey == nil }
}

/// A player's chosen guide and newly saved memories take precedence over an automatic invitation.
enum HomePromptPriority68 {
    static func showsAutomaticIntro(eligible: Bool, hasPinnedMemory: Bool, hasPendingMemory: Bool) -> Bool {
        eligible && !hasPinnedMemory && !hasPendingMemory
    }
}

enum HomeRestLayout68 {
    static func top(in bounds: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: bounds.minY, width: max(0, bounds.width),
               height: min(max(0, height), max(0, bounds.height)))
    }

    static func bottom(in bounds: CGRect, height: CGFloat) -> CGRect {
        let height = min(max(0, height), max(0, bounds.height))
        return CGRect(x: bounds.minX, y: bounds.maxY - height, width: max(0, bounds.width), height: height)
    }

    /// Keep at least 45% of the stage available for waking the cat and camera gestures.
    static func status(in bounds: CGRect, height: CGFloat) -> CGRect {
        bottom(in: bounds, height: min(max(0, height), max(0, bounds.height) * 0.55))
    }

    static func statusNeedsScrolling(in bounds: CGRect, height: CGFloat) -> Bool {
        height > max(0, bounds.height) * 0.55
    }

    static func request(near furniture: CGRect?, in bounds: CGRect, height: CGFloat) -> CGRect {
        HabitRoomPromptLayout.frame(above: furniture ?? bounds, within: bounds, height: height)
    }
}

struct HomeRestClock68: Equatable {
    let remaining: Int
    let progress: Double

    init(rest: CatRest, at date: Date) {
        let duration = rest.endsAt.timeIntervalSince(rest.startedAt)
        guard duration.isFinite, duration > 0, date.timeIntervalSince1970.isFinite else {
            remaining = 0; progress = 1; return
        }
        remaining = Int(ceil(min(duration, max(0, rest.endsAt.timeIntervalSince(date)))))
        progress = min(1, max(0, date.timeIntervalSince(rest.startedAt) / duration))
    }
}

@MainActor
struct HomeRestRequest68: View {
    let cat: CatState
    let furniture: FurnitureItem
    let reasonKey: String?
    let confirm: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                GameIcon(asset: FurnitureArtwork68.assetName(for: furniture), symbol: "bed.double.fill", size: 40)
                    .background(RoomTheme.lilac.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameStrings.furnitureName(furniture)).font(.subheadline.weight(.heavy))
                    Text(GameStrings.format("home68.rest.energy", cat.energy)).font(.caption.weight(.semibold))
                        .foregroundStyle(RoomTheme.secondary)
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(RoomTheme.secondary)
                    .accessibilityLabel(GameStrings.text("common.close"))
                    .accessibilityIdentifier("homeRestAskClose")
            }
            if let reasonKey {
                Text(GameStrings.text(reasonKey)).font(.caption).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeRestAskReason")
            }
            Button(action: confirm) {
                Text(GameStrings.format("home68.rest.start", GameStrings.catName(cat)))
                    .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(MintButtonStyle()).disabled(reasonKey != nil)
                .accessibilityIdentifier("homeRestAskConfirm")
        }
        .padding(12).gameCard(cornerRadius: 22).accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeRestAsk")
    }
}

@MainActor
struct HomeRestStatus68: View {
    let store: GameStore
    let cat: CatState
    let furniture: FurnitureItem
    let rest: CatRest

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let clock = HomeRestClock68(rest: rest, at: max(context.date, store.now))
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        title.frame(maxWidth: .infinity, alignment: .leading)
                        remaining(clock)
                    }
                    VStack(alignment: .leading, spacing: 5) { title; remaining(clock) }
                }
                ProgressView(value: clock.progress).tint(RoomTheme.lilac)
                    .accessibilityLabel(GameStrings.text("home68.rest.progress"))
                    .accessibilityValue(GameStrings.format("home68.rest.remaining", clock.remaining / 60, clock.remaining % 60))
                if rest.observation != nil, !store.habitStudyMode,
                   let preference = CatHabitCatalog.definition(for: cat.id)?.rest,
                   let kind = CatRestPreference(kind: furniture.kind) {
                    Text(GameStrings.text("catHabits.restHint.\(kind.rawValue).\(kind == preference ? "match" : "compare")"))
                        .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(GameStrings.text(rest.observation == nil ? "home68.rest.automatic" : "home68.rest.observation"))
                    .font(.caption2.weight(.medium)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(12).gameCard(cornerRadius: 22)
                .accessibilityElement(children: .contain).accessibilityIdentifier("homeRestStatus")
        }
    }

    private var title: some View {
        Label(GameStrings.format("home68.rest.title", GameStrings.catName(cat), GameStrings.furnitureName(furniture)),
              systemImage: "moon.stars.fill")
            .font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.lilac)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func remaining(_ clock: HomeRestClock68) -> some View {
        Text(GameStrings.format("home68.rest.remaining", clock.remaining / 60, clock.remaining % 60))
            .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(RoomTheme.secondary)
            .fixedSize().accessibilityIdentifier("homeRestRemaining")
    }
}

@MainActor
struct HomeCornerMarker68: View {
    let name: String
    let furniture: CGRect
    let anchor: CGPoint
    let available: CGRect
    let reducedMotion: Bool
    @State private var flagHeight: CGFloat = 44

    var body: some View {
        ZStack {
            Ellipse().stroke(RoomTheme.friendship, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: max(24, furniture.width * 1.05), height: max(10, furniture.width * 0.26))
                .position(anchor)
            Group {
                if reducedMotion { flag }
                else {
                    flag.phaseAnimator([false, true]) { content, raised in
                        content.rotationEffect(.degrees(raised ? 1.3 : -1.3), anchor: .bottomLeading)
                    } animation: { _ in .easeInOut(duration: 2.8) }
                }
            }.frame(width: min(190, available.width))
            .background { GeometryReader { geometry in
                Color.clear.onAppear { flagHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in flagHeight = height }
            } }
            .position(x: min(available.maxX - min(190, available.width) / 2,
                             max(available.minX + min(190, available.width) / 2, furniture.midX)),
                      y: min(available.maxY - min(flagHeight, available.height) / 2,
                             max(available.minY + min(flagHeight, available.height) / 2, furniture.minY - 14)))
        }.allowsHitTesting(false).accessibilityHidden(true).accessibilityIdentifier("homeCornerMarker")
    }

    private var flag: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(GameStrings.format("home68.corner.title", name), systemImage: "heart.fill")
                .font(.caption2.weight(.heavy)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 7).padding(.vertical, 4)
                .background(RoomTheme.friendship, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white, lineWidth: 2))
            RoundedRectangle(cornerRadius: 1).fill(RoomTheme.wood).frame(width: 2, height: 12).padding(.leading, 10)
        }
    }
}

@MainActor
struct HomeRestSleep68: View {
    let reducedMotion: Bool
    private var letters: some View { Text("z ᶻ").font(.system(size: 21, weight: .heavy)).foregroundStyle(RoomTheme.lilac) }
    var body: some View {
        if reducedMotion { letters }
        else {
            letters.phaseAnimator([false, true]) { content, raised in
                content.offset(y: raised ? -3 : 0).opacity(raised ? 0.75 : 1)
            } animation: { _ in .easeInOut(duration: 1.8) }
        }
    }
}

@MainActor
struct HomeRestIntroduction68: View {
    let style: CatBehaviorStyle
    let reducedMotion: Bool

    var body: some View {
        Group {
            if reducedMotion { bubble }
            else {
                bubble.phaseAnimator([false, true]) { content, raised in
                    content.offset(y: raised ? -1.5 : 0)
                } animation: { _ in .easeInOut(duration: 1) }
            }
        }.transition(reducedMotion ? .identity : .opacity)
    }

    private var bubble: some View {
        Text(GameStrings.text("home68.introduction.\(style.rawValue)"))
            .font(.caption.weight(.bold)).foregroundStyle(Color(red: 61 / 255, green: 127 / 255, blue: 168 / 255))
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(red: 216 / 255, green: 232 / 255, blue: 242 / 255), lineWidth: 2))
            .allowsHitTesting(false).accessibilityIdentifier("homeRestIntroduction")
            .accessibilityAddTraits(.updatesFrequently)
    }
}
