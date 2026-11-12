import SwiftUI
import CatGameCore

@MainActor
struct CatAdoptionConfirmationView: View {
    @Bindable var store: GameStore
    let offer: CatAdoptionOffer
    let isSaving: Bool
    let failed: Bool
    let confirm: () -> Void
    let cancel: () -> Void
    @AccessibilityFocusState private var focused: Bool
    private var balance: Int { store.snapshot?.player.gold ?? 0 }
    private var canAdopt: Bool {
        store.snapshot.map { CatAdoptionView.conditionsMet(offer, in: $0) == 3 && !$0.cats.contains { $0.id == offer.id } } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 17) {
                    CatCollectionPortrait(appearance: offer.appearance, size: 96)
                    Text(GameStrings.format("cat.adoptionConfirmTitle", GameStrings.catAdoptionName(offer)))
                        .font(.system(size: 23, weight: .heavy)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focused).accessibilityIdentifier("catAdoptionConfirmationTitle")
                    Text(GameStrings.format("cat.adoptionConfirmBody", offer.price))
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        metric("cat.adoptionSpend", value: "−\(offer.price)", background: RoomTheme.gold.opacity(0.22))
                        metric("cat.adoptionConfirmBalance", value: "\(max(0, balance - offer.price))", background: RoomTheme.chipBg)
                    }
                    if failed {
                        Text(GameStrings.text("cat.adoptionFailed")).font(.footnote.weight(.semibold))
                            .foregroundStyle(RoomTheme.coralDeep).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("catAdoptionConfirmationHint").accessibilityValue("failed")
                    }
                    SaveStatusBanner(store: store)
                }
                .padding(20).padding(.top, 15).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("catAdoptionConfirmation").accessibilityValue(Text(verbatim: "\(offer.id):\(balance):\(offer.price)"))
            VStack(spacing: 10) {
                Button(action: confirm) {
                    HStack(spacing: 8) {
                        if isSaving { ProgressView().tint(.white) }
                        Text(GameStrings.text(isSaving ? "common.saving" : "cat.adoptionConfirm"))
                    }.font(.system(size: 18, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle()).disabled(isSaving || store.isBusy || !canAdopt)
                .accessibilityIdentifier("catAdoptionConfirmButton")
                Button(action: cancel) {
                    Text(GameStrings.text("cat.adoptionThinkAgain")).font(.system(size: 16, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(SoftButtonStyle()).disabled(isSaving).accessibilityIdentifier("catAdoptionCancelButton")
                Text(GameStrings.text("cat.adoptionSavePromise")).font(.system(size: 11, weight: .bold))
                    .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(RoomTheme.paper).fontDesign(.rounded).foregroundStyle(RoomTheme.ink)
        .accessibilityElement(children: .contain)
        .onAppear { focused = true }
    }
    private func metric(_ title: String, value: String, background: Color) -> some View {
        VStack(spacing: 5) {
            Text(GameStrings.text(title)).font(.system(size: 12, weight: .heavy))
            Text(verbatim: value).font(.system(size: 24, weight: .heavy)).monospacedDigit()
        }.padding(13).frame(maxWidth: .infinity).background(background, in: RoundedRectangle(cornerRadius: 20))
    }
}

@MainActor
struct CatAdoptionSuccessView: View {
    let cat: CatState
    let offer: CatAdoptionOffer
    let snapshot: GameSnapshot
    let isSaving: Bool
    let isBusy: Bool
    let selectionFailed: Bool
    let back: () -> Void
    let bringHome: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @AccessibilityFocusState private var focused: Bool
    private var appearances: Set<CatAppearance> { Set(snapshot.cats.map(\.appearance)) }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                Image("adoption-success-rays").resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped().accessibilityHidden(true)
            }
            VStack(spacing: 0) {
                CatCollectionHeader(title: "cat.adoptionNewFriend", backTitle: "catDirectory.collectionShort",
                                    gold: snapshot.player.gold, disabled: isSaving,
                                    backID: "catAdoptionBackButton", back: back)
                ScrollView {
                    VStack(spacing: 20) {
                        CatCollectionPortrait(appearance: cat.appearance, size: 160)
                            .scaleEffect(appeared || reduceMotion ? 1 : 0.85)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "heart.fill").font(.system(size: 26)).foregroundStyle(RoomTheme.coral)
                                    .offset(x: 8, y: 3).accessibilityHidden(true)
                            }
                            .overlay(alignment: .bottomLeading) {
                                Image(systemName: "sparkles").font(.system(size: 27)).foregroundStyle(RoomTheme.gold)
                                    .offset(x: -7, y: 1).accessibilityHidden(true)
                            }
                        Text(GameStrings.format("cat.adoptionSuccessTitle", GameStrings.catName(cat)))
                            .font(.system(size: 27, weight: .heavy)).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader).accessibilityFocused($focused)
                            .accessibilityIdentifier("catAdoptionSuccess").accessibilityValue(cat.id)
                        VStack(spacing: 12) {
                            ViewThatFits(in: .horizontal) {
                                HStack { Text(GameStrings.text("town.title")); Spacer(minLength: 8); progressText }
                                VStack(spacing: 5) { Text(GameStrings.text("town.title")); progressText }
                            }.font(.system(size: 14, weight: .heavy))
                            CatCollectionSegments(appearances: appearances)
                            HStack(spacing: 8) {
                                Label("−\(offer.price)", systemImage: "dollarsign.circle.fill")
                                    .font(.system(size: 16, weight: .heavy)).padding(13)
                                    .background(RoomTheme.gold.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
                                Label(GameStrings.text("cat.adoptionIndependent"), systemImage: "heart.text.clipboard.fill")
                                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                                    .fixedSize(horizontal: false, vertical: true).padding(13).frame(maxWidth: .infinity)
                                    .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 18))
                            }
                        }.padding(16).gameCard(cornerRadius: 26)
                    }
                    .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 20)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }.scrollBounceBehavior(.basedOnSize)
                VStack(spacing: 11) {
                    if selectionFailed {
                        Text(GameStrings.text("cat.companionFailed")).font(.footnote.weight(.semibold))
                            .foregroundStyle(RoomTheme.coralDeep).multilineTextAlignment(.center)
                            .accessibilityIdentifier("catAdoptionBringHomeHint").accessibilityValue("failed")
                    }
                    Button(action: bringHome) {
                        Label(isSaving ? GameStrings.text("common.saving") : GameStrings.format("cat.adoptionBringHome", GameStrings.catName(cat)),
                              systemImage: "house.fill").font(.system(size: 17, weight: .heavy)).frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).disabled(isSaving || isBusy).accessibilityIdentifier("catAdoptionBringHomeButton")
                    Button(action: back) {
                        Text(GameStrings.text("cat.adoptionLater")).font(.system(size: 16, weight: .heavy)).frame(maxWidth: .infinity)
                    }.buttonStyle(SoftButtonStyle()).disabled(isSaving).accessibilityIdentifier("catAdoptionLaterButton")
                }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }
        // Keep the success marker on its title instead of letting a container
        // identifier propagate into the independently accessible footer buttons.
        .accessibilityElement(children: .contain)
        .onAppear {
            focused = true
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.18)) { appeared = true }
        }
    }
    private var progressText: some View {
        Text(appearances.count == CatAppearance.allCases.count
             ? GameStrings.format("catDirectory.breedsComplete", appearances.count, CatAppearance.allCases.count)
             : "\(appearances.count) / \(CatAppearance.allCases.count)")
            .foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("catAdoptionSuccessProgress")
            .accessibilityValue("\(appearances.count)/\(CatAppearance.allCases.count)")
    }
}
