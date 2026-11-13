import SwiftUI
import CatGameCore

@MainActor
struct CatAdoptionView: View {
    @Bindable var store: GameStore
    let catID: String
    @Binding var isSaving: Bool
    let back: () -> Void
    let directory: () -> Void
    let go: (HomeSheet) -> Void
    let home: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirming = false
    @State private var confirmationDetent: PresentationDetent = .height(480)
    @State private var failed = false
    @State private var adoptedHere = false
    @State private var selectionFailed = false
    @State private var floating = false
    @State private var isVisible = false
    private var offer: CatAdoptionOffer? { CatCatalog.adoptionOffer(catID: catID) }
    private var cat: CatState? { store.snapshot?.cats.first { $0.id == catID } }

    static func conditionsMet(_ offer: CatAdoptionOffer, in snapshot: GameSnapshot) -> Int {
        [snapshot.player.level >= offer.requiredPlayerLevel, snapshot.home.roomLevel >= offer.requiredRoomLevel,
         snapshot.player.gold >= offer.price].filter { $0 }.count
    }

    var body: some View {
        Group {
            if let offer, let snapshot = store.snapshot {
                if adoptedHere, let cat {
                    CatAdoptionSuccessView(cat: cat, offer: offer, snapshot: snapshot, isSaving: isSaving, isBusy: store.isBusy,
                                           selectionFailed: selectionFailed, back: directory,
                                           bringHome: bringHome)
                } else {
                    VStack(spacing: 0) {
                        CatCollectionHeader(title: "cat.adoptionTitle", backTitle: "catDirectory.collectionShort",
                                            gold: snapshot.player.gold, disabled: isSaving,
                                            backID: "catAdoptionBackButton", back: back)
                        ScrollView {
                            VStack(spacing: 14) {
                                stage(offer, snapshot: snapshot)
                                requirements(offer, snapshot: snapshot)
                                Label(GameStrings.text(failed ? "cat.adoptionFailed" : "cat.adoptionHint"), systemImage: "info.circle.fill")
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(failed ? RoomTheme.coralDeep : RoomTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoomTheme.chipBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
                                    .accessibilityIdentifier("catAdoptionHint").accessibilityValue(failed ? "failed" : "ready")
                            }
                            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
                            .frame(maxWidth: 560).frame(maxWidth: .infinity)
                        }.accessibilityIdentifier("catAdoptionScroll")
                        footer(offer, snapshot: snapshot)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Text(GameStrings.text("cat.adoptionMissing"))
                    Button(GameStrings.text("common.back"), action: back).buttonStyle(SoftButtonStyle())
                }.padding(24)
            }
        }
        .background(RoomTheme.cream)
        .sheet(isPresented: $confirming, onDismiss: { store.isPresentingAdoptionConfirmation = false }) {
            if let offer {
                CatAdoptionConfirmationView(store: store, offer: offer, isSaving: isSaving, failed: failed,
                                            confirm: adopt, cancel: { confirming = false })
                    .saveRecoveryAlert(store: store)
                    .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(480), .large],
                                         selection: $confirmationDetent)
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(30).presentationBackground(RoomTheme.paper)
                    .interactiveDismissDisabled(isSaving)
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .onChange(of: dynamicTypeSize) { _, size in
            if size.isAccessibilitySize { confirmationDetent = .large }
        }
        .task(id: reduceMotion) {
            floating = false
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { floating = true }
        }
    }

    private func stage(_ offer: CatAdoptionOffer, snapshot: GameSnapshot) -> some View {
        let badge = CatCollectionBadge.adoption(appearance: offer.appearance, isOwned: cat != nil,
                                                 isAvailable: Self.conditionsMet(offer, in: snapshot) == 3)
        return VStack(spacing: 13) {
            CatCollectionPortrait(appearance: offer.appearance, size: 128)
                .offset(y: !reduceMotion && floating ? -3 : 0).padding(.top, 4)
            HStack(spacing: 8) {
                Text(GameStrings.catAdoptionName(offer)).font(.system(size: 26, weight: .heavy))
                    .accessibilityIdentifier("catAdoptionName")
                CatCollectionCoatPill(appearance: offer.appearance)
            }.fixedSize(horizontal: false, vertical: true)
            Text(GameStrings.catDescription(offer.appearance)).font(.system(size: 13, weight: .bold))
                .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20).frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(RadialGradient(colors: [RoomTheme.paper, CatCollectionPalette.background(offer.appearance)],
                                     center: .center, startRadius: 10, endRadius: 230))
                .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 3))
        .overlay(alignment: .topLeading) {
            if let badge {
                Text(GameStrings.text(badge.textKey)).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5).background(badge.tint, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 2)).padding(15)
                    .accessibilityIdentifier("catAdoptionBadge")
            }
        }
    }

    private func requirements(_ offer: CatAdoptionOffer, snapshot: GameSnapshot) -> some View {
        let met = Self.conditionsMet(offer, in: snapshot)
        return VStack(spacing: 13) {
            HStack(spacing: 8) {
                Text(GameStrings.text("cat.adoptionRequirements")).font(.system(size: 16, weight: .heavy))
                Spacer(minLength: 0)
                Text(met == 3 ? GameStrings.text("cat.adoptionAllMet") : GameStrings.format("cat.adoptionConditionsMet", met, 3))
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(met == 3 ? RoomTheme.darkMint : RoomTheme.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(met == 3 ? RoomTheme.paleMint : RoomTheme.chipBg, in: Capsule())
                    .accessibilityIdentifier("catAdoptionConditionsMet").accessibilityValue("\(met)/3")
            }
            requirement("cat.adoptionWorkLevelTitle", symbol: "briefcase.fill", have: snapshot.player.level,
                        need: offer.requiredPlayerLevel, action: "cat.adoptionGoWork", destination: .work,
                        identifier: "catAdoptionPlayerRequirement")
            requirement("cat.adoptionRoomLevelTitle", symbol: "house.fill", have: snapshot.home.roomLevel,
                        need: offer.requiredRoomLevel, action: "cat.adoptionGoUpgrade", destination: .upgrade,
                        identifier: "catAdoptionRoomRequirement")
            requirement("cat.adoptionFeeTitle", symbol: "dollarsign.circle.fill", have: snapshot.player.gold,
                        need: offer.price, action: "cat.adoptionGoEarn", destination: .work,
                        identifier: "catAdoptionGoldRequirement")
        }.padding(16).gameCard(cornerRadius: 26)
    }

    private func requirement(_ title: String, symbol: String, have: Int, need: Int, action: String,
                             destination: HomeSheet, identifier: String) -> some View {
        let met = have >= need
        return HStack(spacing: 9) {
            GameIconTile(symbol: symbol, tint: symbol == "house.fill" ? RoomTheme.secondary : RoomTheme.gold,
                         background: symbol == "house.fill" ? RoomTheme.track : RoomTheme.gold.opacity(0.20), size: 38)
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(GameStrings.text(title)).font(.system(size: 12, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text("\(have) / \(need)").font(.system(size: 12, weight: .heavy)).monospacedDigit().fixedSize()
                        .foregroundStyle(met ? RoomTheme.darkMint : RoomTheme.secondary)
                }
                ProgressView(value: Double(min(have, need)), total: Double(max(1, need)))
                    .tint(met ? RoomTheme.mint : RoomTheme.gold).scaleEffect(x: 1, y: 2).frame(height: 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: GameStrings.text(title) + " · \(have) / \(need)"))
            .accessibilityValue(GameStrings.text(met ? "cat.requirementMet" : "cat.requirementUnmet"))
            .accessibilityIdentifier(identifier)
            if met {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 23)).foregroundStyle(RoomTheme.mint).accessibilityHidden(true)
            } else {
                Button { go(destination) } label: {
                    Text(GameStrings.text(action)).font(.system(size: 11, weight: .heavy)).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 78, minHeight: 44)
                        .padding(.horizontal, 7).foregroundStyle(RoomTheme.darkMint)
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CatCollectionPalette.readyBorder, lineWidth: 2))
                }.buttonStyle(.plain).disabled(isSaving || store.isBusy).accessibilityIdentifier(identifier + "Action")
            }
        }
    }

    private func footer(_ offer: CatAdoptionOffer, snapshot: GameSnapshot) -> some View {
        let met = Self.conditionsMet(offer, in: snapshot)
        let action = snapshot.player.level < offer.requiredPlayerLevel ? "cat.adoptionGoWork"
            : snapshot.home.roomLevel < offer.requiredRoomLevel ? "cat.adoptionGoUpgrade" : "cat.adoptionGoEarn"
        return VStack(spacing: 10) {
            if met == 3 {
                HStack {
                    Text(GameStrings.format("cat.adoptionBalance", snapshot.player.gold))
                        .accessibilityIdentifier("catAdoptionGold").accessibilityValue("\(snapshot.player.gold)")
                    Spacer(minLength: 6)
                    Text(GameStrings.format("cat.adoptionAfterBalance", snapshot.player.gold - offer.price))
                }
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                Button {
                    failed = false
                    confirmationDetent = dynamicTypeSize.isAccessibilitySize ? .large : .height(480)
                    store.isPresentingAdoptionConfirmation = true
                    confirming = true
                } label: {
                    HStack(spacing: 9) {
                        Label(GameStrings.text(cat == nil ? "cat.adoptionAction" : "cat.adoptionOwned"), systemImage: "heart.fill")
                        Label("\(offer.price)", systemImage: "dollarsign.circle.fill")
                            .font(.system(size: 14, weight: .heavy)).padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.white.opacity(0.2), in: Capsule())
                    }.font(.system(size: 18, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle()).disabled(isSaving || store.isBusy || cat != nil)
                .accessibilityIdentifier("catAdoptionButton")
            } else {
                Text(GameStrings.format("cat.adoptionRemainingConditions", 3 - met, GameStrings.catAdoptionName(offer)))
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button { go(action == "cat.adoptionGoUpgrade" ? .upgrade : .work) } label: {
                    Label(GameStrings.text(action), systemImage: action == "cat.adoptionGoUpgrade" ? "house.fill" : "briefcase.fill")
                        .font(.system(size: 17, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(TaskGoldButtonStyle()).disabled(isSaving || store.isBusy)
                    .accessibilityIdentifier("catAdoptionRequirementAction")
            }
        }
        .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(RoomTheme.cream, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
    }

    private func adopt() {
        guard !isSaving, !store.isBusy, cat == nil else { return }
        isSaving = true
        failed = false
        Task { @MainActor in
            let succeeded = await store.adoptCat(catID: catID, playsSound: false, showsSuccessNotice: false)
            failed = !succeeded
            isSaving = false
            guard succeeded else { return }
            confirming = false
            adoptedHere = true
            if isVisible { store.playFeedback(.claim); store.playFeedback(.catCoax) }
        }
    }
    private func bringHome() {
        guard !isSaving, !store.isBusy else { return }
        isSaving = true
        selectionFailed = false
        Task { @MainActor in
            let saved = await store.selectCompanion(catID: catID)
            isSaving = false
            selectionFailed = !saved
            if saved, isVisible { home() }
        }
    }
}
