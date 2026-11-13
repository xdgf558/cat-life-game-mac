import SwiftUI

@MainActor
struct OnboardingGuideView: View {
    @Bindable var store: GameStore
    let onExplore: (GameOnboardingStep) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool
    private var locked: Bool { store.isBusy || store.saveTransferInProgress }

    var body: some View {
        if let step = store.onboarding.step {
            VStack(spacing: 12) {
                header(step)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("onboardingHeader")
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if store.hasSaveFailure { SaveStatusBanner(store: store) }
                            HStack(spacing: 12) {
                                GameIcon(asset: artwork(step), symbol: "sparkles", size: 42, tint: RoomTheme.gold)
                                    .padding(8).background(RoomTheme.track, in: RoundedRectangle(cornerRadius: 18))
                                Text(GameStrings.text("onboarding.\(step.rawValue).title"))
                                    .font(.title3.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                                    .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                                    .accessibilityIdentifier("onboardingTitle")
                            }.id("onboardingPageTop")
                            ForEach(1...3, id: \.self) { number in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: tipSymbol(step, number: number))
                                        .font(.system(size: 14, weight: .bold)).foregroundStyle(RoomTheme.gold)
                                        .frame(width: 26, height: 26)
                                        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 9))
                                        .accessibilityHidden(true)
                                    Text(GameStrings.text("onboarding.\(step.rawValue).tip\(number)"))
                                        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Button { onExplore(step) } label: {
                                Label(GameStrings.text("onboarding.\(step.rawValue).explore"), systemImage: "arrow.up.right.square")
                                    .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 10).padding(.vertical, 4)
                                    .contentShape(RoundedRectangle(cornerRadius: 18))
                            }
                            .buttonStyle(.plain).foregroundStyle(RoomTheme.gold).disabled(locked)
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(RoomTheme.gold,
                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                            .accessibilityIdentifier("onboardingExploreButton")
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            Text(GameStrings.text("onboarding.combinedHint"))
                                .font(.caption).foregroundStyle(RoomTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.horizontal, 4).padding(.vertical, 4)
                    }
                    .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("onboardingGuide")
                    .onChange(of: step) { _, _ in
                        proxy.scrollTo("onboardingPageTop", anchor: .top)
                        headingFocused = true
                    }
                }
                HStack(spacing: 10) {
                    Button { store.playNavigationSound(); store.onboarding.previous() } label: {
                        Text(GameStrings.text("onboarding.previous")).font(.subheadline.weight(.heavy))
                            .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(SoftButtonStyle()).disabled(locked || store.onboarding.stepIndex == 0)
                    .opacity(store.onboarding.stepIndex == 0 ? 0.45 : 1)
                    .accessibilityIdentifier("onboardingPreviousButton")
                    Button { store.playNavigationSound(); store.onboarding.next() } label: {
                        Text(GameStrings.text(step == .town ? "onboarding.complete" : "onboarding.next"))
                            .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(MintButtonStyle()).disabled(locked)
                    .accessibilityIdentifier("onboardingNextButton")
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("onboardingFooter")
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .padding(16).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
            .environment(\.locale, Locale(identifier: store.language.rawValue))
            .accessibilityElement(children: .contain).accessibilityIdentifier("onboardingCard")
            .onAppear { headingFocused = true }
            .transaction { if reduceMotion { $0.animation = nil } }
        }
    }

    private func header(_ step: GameOnboardingStep) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                Text(GameStrings.format("onboarding.progress", store.onboarding.stepIndex + 1,
                                        GameOnboardingStep.allCases.count))
                    .font(.caption.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboardingStep").accessibilityValue(step.rawValue)
                HStack(spacing: 4) {
                    ForEach(GameOnboardingStep.allCases.indices, id: \.self) { index in
                        Capsule().fill(index == store.onboarding.stepIndex ? RoomTheme.mint : RoomTheme.wood)
                            .frame(width: index == store.onboarding.stepIndex ? 18 : 7, height: 7)
                    }
                }.accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Button { store.playNavigationSound(); store.onboarding.isPresented = false } label: {
                Text(GameStrings.text("onboarding.skip")).font(.caption.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 12).frame(minHeight: 44)
                    .background(RoomTheme.track, in: Capsule()).contentShape(Capsule())
            }
            .buttonStyle(.plain).foregroundStyle(RoomTheme.secondary).disabled(locked)
            .accessibilityIdentifier("onboardingSkipButton")
        }
    }

    private func artwork(_ step: GameOnboardingStep) -> String {
        switch step {
        case .care: "cat-avatar"
        case .work: "job-flyer-cartoon"
        case .supplies: "icon-shop"
        case .tasks: "town-board-cartoon"
        case .town: "town-street-cartoon"
        }
    }

    private func tipSymbol(_ step: GameOnboardingStep, number: Int) -> String {
        let symbols: [String] = switch step {
        case .care: ["pawprint.fill", "basket.fill", "person.crop.circle"]
        case .work: ["briefcase.fill", "clock.fill", "bolt.fill"]
        case .supplies: ["storefront.fill", "backpack.fill", "sofa.fill"]
        case .tasks: ["checklist", "gift.fill", "sun.max.fill"]
        case .town: ["cat.fill", "cross.case.fill", "heart.fill"]
        }
        return symbols[number - 1]
    }
}

@MainActor
struct GuideResumeBar: View {
    @Bindable var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false

    var body: some View {
        if store.onboarding.isActive {
            Button { store.playNavigationSound(); store.onboarding.show() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "safari.fill").accessibilityHidden(true)
                    Text(GameStrings.format("onboarding.resume", store.onboarding.stepIndex + 1,
                                            GameOnboardingStep.allCases.count))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
                .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.darkMint)
                .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 44)
                .background(RoomTheme.paleMint, in: Capsule())
                .overlay(Capsule().strokeBorder(RoomTheme.mint.opacity(0.45), lineWidth: 2))
                .shadow(color: RoomTheme.mint.opacity(reduceMotion ? 0 : (glowing ? 0.35 : 0.1)), radius: glowing ? 7 : 2)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(store.isBusy || store.saveTransferInProgress)
            .accessibilityLabel(GameStrings.format("onboarding.resumeAccessibility", store.onboarding.stepIndex + 1,
                                                  GameOnboardingStep.allCases.count))
            .accessibilityIdentifier("onboardingResumeButton")
            .task(id: reduceMotion) {
                glowing = false
                if !reduceMotion { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { glowing = true } }
            }
        }
    }
}
