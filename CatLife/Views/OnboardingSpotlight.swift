import SwiftUI

struct OnboardingTargetKey: PreferenceKey {
    static let defaultValue: [GameOnboardingStep: Anchor<CGRect>] = [:]
    static func reduce(value: inout [GameOnboardingStep: Anchor<CGRect>],
                       nextValue: () -> [GameOnboardingStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func onboardingTarget(_ step: GameOnboardingStep) -> some View {
        anchorPreference(key: OnboardingTargetKey.self, value: .bounds) { [step: $0] }
    }
}

enum OnboardingSpotlightLayout {
    static func card(in size: CGSize, target: CGRect?, gap: CGFloat = 44) -> CGRect {
        let margin: CGFloat = 14
        let width = max(0, min(560, size.width - margin * 2))
        guard let target else {
            let height = min(540, max(0, size.height - margin * 2))
            return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        }
        let above = max(0, target.minY - gap - margin)
        let below = max(0, size.height - target.maxY - gap - margin)
        let useAbove = above >= below
        let height = min(540, useAbove ? above : below)
        let y = useAbove ? max(margin, target.minY - gap - height) : target.maxY + gap
        return CGRect(x: (size.width - width) / 2, y: y, width: width, height: height)
    }
}

@MainActor
struct OnboardingSpotlight: View {
    @Bindable var store: GameStore
    let target: CGRect?
    let size: CGSize
    let onExplore: (GameOnboardingStep) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        let frame = target?.insetBy(dx: -5, dy: -5)
            .intersection(CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2))
        let card = OnboardingSpotlightLayout.card(in: size, target: frame, gap: store.onboarding.step == .care ? 14 : 44)
        ZStack(alignment: .topLeading) {
            SpotlightScrim(hole: frame)
                .fill(Color(red: 43 / 255, green: 28 / 255, blue: 18 / 255).opacity(0.55), style: FillStyle(eoFill: true))
                .contentShape(Rectangle()).onTapGesture {}.accessibilityHidden(true)
            if let frame, let step = store.onboarding.step {
                // Handle the hole here: passing touches through could spend food or start work.
                Button { onExplore(step) } label: {
                    RoundedRectangle(cornerRadius: 22).stroke(.white, lineWidth: 3)
                        .frame(width: frame.width, height: frame.height)
                        .contentShape(RoundedRectangle(cornerRadius: 22))
                }
                    .buttonStyle(.plain).position(x: frame.midX, y: frame.midY)
                    .disabled(store.isBusy || store.saveTransferInProgress)
                    .accessibilityLabel(GameStrings.text("onboarding.\(step.rawValue).explore"))
                    .accessibilityIdentifier("onboardingSpotlight")
                RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(pulsing ? 0 : 0.55), lineWidth: 2)
                    .frame(width: frame.width + (pulsing ? 10 : 0), height: frame.height + (pulsing ? 10 : 0))
                    .position(x: frame.midX, y: frame.midY).opacity(reduceMotion ? 0 : 1)
                    .accessibilityHidden(true).allowsHitTesting(false)
                Image(systemName: store.onboarding.step == .care ? "arrow.right" : (frame.midY > size.height / 2 ? "arrow.down" : "arrow.up"))
                    .font(.system(size: 25, weight: .black)).foregroundStyle(RoomTheme.wood)
                    .position(x: store.onboarding.step == .care ? max(18, frame.minX - 25) : frame.midX,
                              y: store.onboarding.step == .care ? frame.midY : (frame.midY > size.height / 2 ? frame.minY - 25 : frame.maxY + 25))
                    .accessibilityHidden(true).allowsHitTesting(false)
            }
            OnboardingGuideView(store: store, onExplore: onExplore)
                .frame(width: card.width, height: card.height).position(x: card.midX, y: card.midY)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .saveRecoveryAlert(store: store)
        .task(id: reduceMotion) {
            pulsing = false
            if !reduceMotion { withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulsing = true } }
        }
    }
}

private struct SpotlightScrim: Shape {
    let hole: CGRect?
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: -200, dy: -200))
        if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 22, height: 22)) }
        return path
    }
}
