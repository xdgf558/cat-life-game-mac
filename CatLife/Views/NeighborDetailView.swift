import SwiftUI
import CatGameCore

@MainActor
struct NeighborDetailView: View {
    @Bindable var store: GameStore
    let neighborID: String
    var showsExchangeEntry = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var dialogueKey: String?
    @State private var isWorking = false
    @State private var failed = false
    @State private var choosingGift = false
    @State private var showsMarket = false
    @State private var rewardsExpanded = false
    @State private var isVisible = false
    @State private var pendingGift: (id: String, receipt: NeighborActionReceipt)?
    @State private var stageReceipt: NeighborActionReceipt?
    @State private var gain: Int?
    @State private var gainFloated = false
    @State private var gainTask: Task<Void, Never>?
    @State private var resultPresentationID = UUID()

    private var neighbor: NeighborDefinition? { CommunityCatalog.neighbor(id: neighborID) }
    private var relationship: NeighborRelationship {
        store.snapshot?.community.relationship(for: neighborID) ?? NeighborRelationship()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let neighbor {
                        profile(neighbor)
                        friendship(neighbor)
                        if showsExchangeEntry {
                            Button {
                                store.playNavigationSound()
                                showsMarket = true
                            } label: {
                                Label(GameStrings.text("market.neighborEntry"), systemImage: "arrow.left.arrow.right")
                                    .font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(SoftButtonStyle()).disabled(isWorking || store.isBusy)
                            .accessibilityIdentifier("neighborExchangeButton")
                        }
                    } else { Text(GameStrings.text("community.neighborMissing")) }
                }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize).background(RoomTheme.cream)
            .accessibilityIdentifier("neighborDetail_\(neighborID)")
            .onChange(of: resultPresentationID) { _, _ in
                guard stageReceipt == nil else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("neighborResult", anchor: .top)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            CommunityHeader(title: GameStrings.format("community.neighborHome", GameStrings.text(neighbor?.nameKey ?? "community.title")),
                            backTitle: showsExchangeEntry ? "community.title" : "market.shortTitle",
                            gold: store.snapshot?.player.gold ?? 0,
                            symbol: "house.fill", backID: "neighborBackButton") { dismiss() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if neighbor != nil { actions } }
        .accessibilityHidden(stageReceipt != nil)
        .overlay {
            if let stageReceipt, let neighbor {
                CommunityStageSuccessView(neighbor: neighbor, receipt: stageReceipt) { self.stageReceipt = nil }
            }
        }
        .sheet(isPresented: $choosingGift, onDismiss: {
            finishGiftPresentation()
        }) {
            CommunityGiftView(store: store, neighborID: neighborID, onGift: { giftID, receipt in
                guard canPresent(receipt) else { return false }
                pendingGift = (giftID, receipt)
                return true
            }, onClose: { choosingGift = false })
            .safeAreaInset(edge: .top, spacing: 0) { if store.hasSaveFailure { SaveStatusBanner(store: store) } }
            .saveRecoveryAlert(store: store)
            .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .onChange(of: choosingGift) { _, presented in store.isPresentingCommunityGift = presented }
        .navigationDestination(isPresented: $showsMarket) {
            ExchangeMarketView(store: store, initialNeighborID: neighborID,
                               onClose: { showsMarket = false })
        }
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            store.isPresentingCommunityGift = false
            finishGiftPresentation()
            stageReceipt = nil
            gainTask?.cancel()
        }
        .onChange(of: store.saveSceneGeneration) { _, _ in
            pendingGift = nil; stageReceipt = nil; dialogueKey = nil; gain = nil
            gainTask?.cancel()
        }
    }

    private func profile(_ neighbor: NeighborDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { CommunityPortrait(neighbor: neighbor, size: 96); biography(neighbor) }
            } else {
                HStack(alignment: .center, spacing: 14) { CommunityPortrait(neighbor: neighbor, size: 96); biography(neighbor) }
            }
            Label(dialogueKey.map { GameStrings.text($0) } ?? CompanionshipPresentation.neighborDialogue(for: store.cat)
                  ?? GameStrings.text("community.dialogueHint"), systemImage: "text.bubble.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(dialogueKey == nil ? RoomTheme.secondary : RoomTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white, lineWidth: 2))
                .overlay(alignment: .topLeading) {
                    Image(systemName: "triangle.fill").font(.system(size: 17)).foregroundStyle(RoomTheme.paper)
                        .offset(x: 28, y: -12).accessibilityHidden(true)
                }
                .id(dialogueKey).transition(.opacity.combined(with: .scale(scale: 0.97)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: dialogueKey)
                .accessibilityIdentifier("neighborDialogue")
                .id("neighborResult")
            VStack(alignment: .leading, spacing: 6) {
                Label(GameStrings.text(neighbor.homeKey), systemImage: "house.fill")
                Label(GameStrings.text(neighbor.catsKey), systemImage: "pawprint.fill")
            }.font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [CommunityPalette.background(neighbor), RoomTheme.paper],
                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 3))
    }

    private func biography(_ neighbor: NeighborDefinition) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(GameStrings.text(neighbor.nameKey)).font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
            CommunityStagePill(neighbor: neighbor, stage: relationship.stage)
            Text(GameStrings.text(neighbor.descriptionKey)).font(.subheadline.weight(.bold))
                .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func friendship(_ neighbor: NeighborDefinition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Label(GameStrings.text("community.friendshipTitle"), systemImage: "heart.fill")
                    .font(.headline.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                Spacer(minLength: 8)
                Text("\(relationship.friendship) / 100").font(.subheadline.weight(.heavy)).monospacedDigit()
                    .accessibilityLabel(GameStrings.format("community.friendshipValue", relationship.friendship))
                    .accessibilityIdentifier("neighborFriendshipValue").accessibilityValue("\(relationship.friendship)")
            }
            .overlay(alignment: .topTrailing) {
                if let gain {
                    Label(GameStrings.format("community.ordinaryGain", gain), systemImage: "heart.fill")
                        .font(.caption.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6).background(RoomTheme.friendship, in: Capsule())
                        .offset(y: reduceMotion ? -28 : gainFloated ? -42 : -20)
                        .opacity(reduceMotion ? 1 : gainFloated ? 0 : 1).allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            CommunityFriendshipTrack(friendship: relationship.friendship)
            if let next = relationship.nextStage {
                Text(GameStrings.format("community.nextStage", GameStrings.text(next.nameKey), next.minimumPoints - relationship.friendship))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            } else {
                Text(GameStrings.text("community.closestStage")).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
            }
            Divider().overlay(RoomTheme.track)
            VStack(alignment: .leading, spacing: 8) {
                Text(GameStrings.text("community.favoriteGifts")).font(.subheadline.weight(.heavy))
                ForEach(neighbor.favoriteGiftIDs.compactMap(CommunityCatalog.gift)) { gift in
                    HStack(spacing: 6) { CommunityGiftIcon(gift: gift, size: 24); Text(GameStrings.text(gift.nameKey)) }
                        .font(.caption.weight(.heavy)).foregroundStyle(CommunityPalette.giftTint(gift))
                }
                Text(GameStrings.format("community.giftPreferenceShort", CommunityCatalog.favoriteGiftFriendship,
                                        CommunityCatalog.ordinaryGiftFriendship))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            DisclosureGroup(isExpanded: $rewardsExpanded) {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(CommunityCatalog.stages.filter { $0.level > 1 }) { stage in rewardRow(stage) }
                    Text(GameStrings.text("community.stageRewardHint")).font(.caption2).foregroundStyle(RoomTheme.secondary)
                }.padding(.top, 12)
            } label: {
                Label(GameStrings.text("community.stageRewards") + " · "
                      + GameStrings.format("community.rewardsCount", relationship.rewardedStageLevels.count,
                                           CommunityCatalog.stages.filter { $0.level > 1 }.count), systemImage: "gift.fill")
                    .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("neighborRewardsDisclosure")
        }.fixedSize(horizontal: false, vertical: true).padding(16).gameCard(cornerRadius: 28)
    }

    private func rewardRow(_ stage: FriendshipStage) -> some View {
        let earned = relationship.rewardedStageLevels.contains(stage.level)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(GameStrings.format("community.rewardStage", GameStrings.text(stage.nameKey), stage.minimumPoints))
                Spacer(minLength: 3)
                Image(systemName: earned ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(earned ? RoomTheme.mint : RoomTheme.secondary)
            }.font(.caption.weight(.heavy))
            CommunityRewardChips(gold: stage.goldReward, food: stage.foodReward,
                                 litter: stage.litterReward, toys: stage.toyUsesReward)
            if earned { Text(GameStrings.text("community.rewardReceived")).font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.darkMint) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(earned ? RoomTheme.paleMint.opacity(0.4) : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if failed {
                Text(GameStrings.text(store.hasSaveFailure ? "save.writeTitle" : "community.actionFailed"))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep).accessibilityIdentifier("neighborActionFailure")
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { visitButton; giftButton }
            } else { HStack(alignment: .top, spacing: 12) { visitButton; giftButton } }
        }
        .padding(16).frame(maxWidth: .infinity).background(RoomTheme.cream)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain).accessibilityIdentifier("neighborActionBar")
    }

    @ViewBuilder private var visitButton: some View {
        if relationship.visitedToday {
            Button(action: visit) { visitLabel }.buttonStyle(SoftButtonStyle())
                .disabled(isWorking || store.isBusy).accessibilityIdentifier("neighborVisitButton")
        } else {
            Button(action: visit) { visitLabel }.buttonStyle(MintButtonStyle())
                .disabled(isWorking || store.isBusy).accessibilityIdentifier("neighborVisitButton")
        }
    }
    private var visitLabel: some View {
        VStack(spacing: 4) {
            Label(GameStrings.text(relationship.visitedToday ? "community.chatAction" : "community.visitAction"),
                  systemImage: relationship.visitedToday ? "bubble.left.fill" : "hand.wave.fill").font(.subheadline.weight(.heavy))
            Text(relationship.visitedToday ? GameStrings.text("community.visitAlreadyEarnedShort")
                 : relationship.friendship == 100 ? GameStrings.text("community.closestShort")
                 : GameStrings.format("community.visitGainShort", min(CommunityCatalog.visitFriendship, 100 - relationship.friendship)))
                .font(.caption2.weight(.bold))
        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44)
    }
    @ViewBuilder private var giftButton: some View {
        if relationship.remainingGiftsToday > 0 {
            Button { store.playNavigationSound(); choosingGift = true } label: { giftLabel }
                .buttonStyle(FriendshipButtonStyle()).disabled(isWorking || store.isBusy).accessibilityIdentifier("neighborGiftButton")
        } else {
            Button { store.showCommunityGiftLimit() } label: { giftLabel }
                .buttonStyle(SoftButtonStyle()).disabled(isWorking || store.isBusy).accessibilityIdentifier("neighborGiftButton")
        }
    }
    private var giftLabel: some View {
        VStack(spacing: 4) {
            Label(GameStrings.text(relationship.remainingGiftsToday > 0 ? "community.sendGift" : "community.giftedToday"),
                  systemImage: "gift.fill").font(.subheadline.weight(.heavy))
            Text(relationship.remainingGiftsToday == 0 ? GameStrings.text("community.giftTomorrow")
                 : relationship.friendship == 100 ? GameStrings.text("community.closestShort")
                 : GameStrings.format("community.giftDailyShort", relationship.giftsGivenToday,
                                      CommunityCatalog.dailyGiftLimit, CommunityCatalog.favoriteGiftFriendship))
                .font(.caption2.weight(.bold))
                .accessibilityIdentifier("neighborDailyGiftStatus")
        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44)
    }

    private func visit() {
        guard !isWorking, !store.isBusy, let neighbor else { return }
        isWorking = true; failed = false
        Task {
            defer { isWorking = false }
            let receipt = await store.visitNeighborWithReceipt(id: neighborID, presentResult: { receipt in
                guard canPresent(receipt) else { return false }
                dialogueKey = neighbor.dialogueKey(friendship: relationship.friendship)
                showGain(receipt.friendshipGained)
                if receipt.stageReached != nil { stageReceipt = receipt }
                resultPresentationID = UUID()
                return true
            })
            if receipt == nil { failed = true }
        }
    }

    private func canPresent(_ receipt: NeighborActionReceipt) -> Bool {
        isVisible && scenePhase == .active && (store.isShowingNeighbors || store.isShowingMarket) && store.activeSheet == .town
            && receipt.saveSceneGeneration == store.saveSceneGeneration
    }

    private func finishGiftPresentation() {
        guard let gift = pendingGift else { return }
        pendingGift = nil
        guard canPresent(gift.receipt) else {
            store.showNeighborActionResult(gift.receipt)
            return
        }
        dialogueKey = neighbor?.giftDialogueKey(giftID: gift.id)
        failed = false
        showGain(gift.receipt.friendshipGained)
        if gift.receipt.stageReached != nil { stageReceipt = gift.receipt }
        resultPresentationID = UUID()
    }

    private func showGain(_ amount: Int) {
        guard amount > 0 else { return }
        gainTask?.cancel(); gain = amount; gainFloated = false
        gainTask = Task { @MainActor in
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 1.4)) { gainFloated = true }
            }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            gain = nil
        }
    }
}
