#if os(macOS)
import SwiftUI

/// Real desktop regions the first-run tour spotlights. Views tag themselves with `macTourAnchor`.
enum MacTourTarget: Hashable {
    case careCard, tasks, navWork, navShop, navTown
    /// The visible frame of the home page's scrolling right panel, used to clip panel targets.
    case homePanel

    var isInHomePanel: Bool { self == .careCard || self == .tasks }
}

struct MacTourAnchorKey: PreferenceKey {
    static let defaultValue: [MacTourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [MacTourTarget: Anchor<CGRect>], nextValue: () -> [MacTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func macTourAnchor(_ target: MacTourTarget?) -> some View {
        anchorPreference(key: MacTourAnchorKey.self, value: .bounds) { anchor in
            target.map { [$0: anchor] } ?? [:]
        }
    }
}

extension GameOnboardingStep {
    /// Each shared tour step points at the desktop control that owns it.
    var macTarget: MacTourTarget {
        switch self {
        case .care: .careCard
        case .work: .navWork
        case .supplies: .navShop
        case .tasks: .tasks
        case .town: .navTown
        }
    }
    var macSymbol: String {
        switch self {
        case .care: "pawprint.fill"
        case .work: "briefcase.fill"
        case .supplies: "storefront.fill"
        case .tasks: "checklist"
        case .town: "map.fill"
        }
    }
}

/// Spotlight tour over the home layout: dims the window, outlines one real control and explains it.
/// It only navigates; feeding, buying and claiming still happen through the normal pages.
@MainActor
struct MacOnboardingTour: View {
    @Bindable var store: GameStore
    let anchors: [MacTourTarget: Anchor<CGRect>]
    let preferences: MacPreferences
    let onExplore: (GameOnboardingStep) -> Void
    @Environment(\.gameReduceMotionOverride) private var reduceMotion
    @State private var pulse = false
    @AccessibilityFocusState private var titleFocused: Bool
    private let cardWidth: CGFloat = 380
    private var locked: Bool { store.isBusy || store.saveTransferInProgress }

    var body: some View {
        GeometryReader { proxy in
            if let step = store.onboarding.step {
                let target = spotlight(step.macTarget, in: proxy)
                ZStack(alignment: .topLeading) {
                    scrim(size: proxy.size, hole: target)
                    if let target {
                        RoundedRectangle(cornerRadius: 22).stroke(RoomTheme.mint, lineWidth: 3)
                            .shadow(color: RoomTheme.mint.opacity(pulse ? 0.8 : 0.3), radius: pulse ? 14 : 6)
                            .frame(width: target.width, height: target.height)
                            .position(x: target.midX, y: target.midY)
                            .allowsHitTesting(false)
                    }
                    card(step).frame(width: cardWidth)
                        .position(cardCenter(target: target, size: proxy.size))
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("macOnboardingTour")
        .onAppear { titleFocused = true }
        .onChange(of: store.onboarding.step) { _, _ in titleFocused = true }
        .task(id: reduceMotion) {
            pulse = false
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    /// Only the part of a target that is actually on screen is outlined. Panel targets are clipped
    /// to the scrolling panel's visible frame (the home page scrolls them into view first).
    private func spotlight(_ target: MacTourTarget, in proxy: GeometryProxy) -> CGRect? {
        guard var rect = anchors[target].map({ proxy[$0] }) else { return nil }
        if target.isInHomePanel, let panel = anchors[.homePanel].map({ proxy[$0] }) {
            rect = rect.intersection(panel)
            guard !rect.isNull, rect.height >= 24 else { return nil }
        }
        return rect.insetBy(dx: -8, dy: -8)
    }

    private func scrim(size: CGSize, hole: CGRect?) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 22, height: 22)) }
        }
        .fill(Color(red: 0.16, green: 0.11, blue: 0.07).opacity(0.5), style: FillStyle(eoFill: true))
        .contentShape(Rectangle()) // Clicks on the dimmed window never reach the game underneath.
        .onTapGesture {}
        .accessibilityHidden(true)
    }

    /// Beside the highlighted control, on whichever side has room; centred when nothing is found.
    private func cardCenter(target: CGRect?, size: CGSize) -> CGPoint {
        let estimatedHeight: CGFloat = 330, margin: CGFloat = 24
        guard let target else { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let x = target.midX < size.width / 2
            ? target.maxX + margin + cardWidth / 2
            : target.minX - margin - cardWidth / 2
        let y = min(max(target.midY, estimatedHeight / 2 + margin), size.height - estimatedHeight / 2 - margin)
        return CGPoint(x: min(max(x, cardWidth / 2 + margin), size.width - cardWidth / 2 - margin), y: y)
    }

    private func card(_ step: GameOnboardingStep) -> some View {
        let index = store.onboarding.stepIndex, count = GameOnboardingStep.allCases.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(GameStrings.format("onboarding.progress", index + 1, count))
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { dot in
                        Capsule().fill(dot == index ? RoomTheme.mint : RoomTheme.track)
                            .frame(width: dot == index ? 16 : 6, height: 6)
                    }
                }.accessibilityHidden(true)
                Spacer(minLength: 6)
                Button { store.playNavigationSound(); store.onboarding.isPresented = false } label: {
                    HStack(spacing: 5) { Text(GameStrings.text("onboarding.skip")); MacKeyCap(value: "Esc") }
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                }.buttonStyle(.plain).keyboardShortcut(.cancelAction).disabled(locked)
                    .accessibilityIdentifier("macTourSkip")
            }
            HStack(spacing: 12) {
                Image(systemName: step.macSymbol).font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(RoomTheme.mint, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityHidden(true)
                Text(GameStrings.text("mac.tour.\(step.rawValue).title"))
                    .font(.system(size: 20, weight: .heavy, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($titleFocused)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(1...3, id: \.self) { number in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle().fill(RoomTheme.gold).frame(width: 6, height: 6).offset(y: -2).accessibilityHidden(true)
                        Text(tip(step, number)).font(.system(size: 13.5, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button { onExplore(step) } label: {
                Label(GameStrings.text("mac.tour.\(step.rawValue).explore"), systemImage: "arrow.up.right")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            }.buttonStyle(.plain).disabled(locked).accessibilityIdentifier("macTourExplore")
            HStack(spacing: 10) {
                Button { store.playNavigationSound(); store.onboarding.previous() } label: {
                    HStack(spacing: 6) { MacKeyCap(value: "←"); Text(GameStrings.text("onboarding.previous")) }
                        .frame(maxWidth: .infinity)
                }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(locked || index == 0).opacity(index == 0 ? 0.45 : 1)
                    .accessibilityIdentifier("macTourPrevious")
                Button { store.playNavigationSound(); store.onboarding.next() } label: {
                    HStack(spacing: 6) {
                        Text(GameStrings.text(step == .town ? "onboarding.complete" : "onboarding.next"))
                        MacKeyCap(value: step == .town ? "↩" : "→")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).keyboardShortcut(step == .town ? .defaultAction : KeyboardShortcut(.rightArrow, modifiers: []))
                    .disabled(locked).accessibilityIdentifier("macTourNext")
            }
            Text(GameStrings.text("mac.tour.footer")).font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: 3))
        .compositingGroup().shadow(color: .black.opacity(0.22), radius: 22, y: 10)
        .foregroundStyle(RoomTheme.ink)
        .accessibilityElement(children: .contain).accessibilityIdentifier("macTourCard")
    }

    /// Tips name the player's own shortcuts, so a rebound key never contradicts the card.
    private func tip(_ step: GameOnboardingStep, _ number: Int) -> String {
        let key = "mac.tour.\(step.rawValue).tip\(number)"
        switch (step, number) {
        case (.care, 2):
            return GameStrings.format(key, preferences.binding(for: .feed).label,
                                      preferences.binding(for: .clean).label, preferences.binding(for: .play).label)
        case (.care, 3):
            return GameStrings.format(key, preferences.binding(for: .viewLeft).label, preferences.binding(for: .viewRight).label)
        case (.work, 1): return GameStrings.format(key, preferences.binding(for: .work).label)
        case (.supplies, 1): return GameStrings.format(key, preferences.binding(for: .shop).label)
        case (.supplies, 2): return GameStrings.format(key, preferences.binding(for: .decorate).label)
        case (.town, 1): return GameStrings.format(key, preferences.binding(for: .town).label)
        default: return GameStrings.text(key)
        }
    }
}

/// Small pill in the top bar that brings a paused tour back.
@MainActor
struct MacTourResumePill: View {
    @Bindable var store: GameStore
    let resume: () -> Void
    var body: some View {
        if store.onboarding.isActive, !store.onboarding.isPresented {
            Button(action: resume) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text(GameStrings.format("onboarding.resume", store.onboarding.stepIndex + 1, GameOnboardingStep.allCases.count))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
                }
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoomTheme.paleMint, in: Capsule())
                .overlay(Capsule().strokeBorder(RoomTheme.mint.opacity(0.5), lineWidth: 1.5))
            }
            .buttonStyle(.plain).disabled(store.isBusy || store.saveTransferInProgress)
            .accessibilityLabel(GameStrings.format("onboarding.resumeAccessibility", store.onboarding.stepIndex + 1,
                                                  GameOnboardingStep.allCases.count))
            .accessibilityIdentifier("macTourResume")
        }
    }
}
#endif
