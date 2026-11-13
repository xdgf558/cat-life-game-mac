import SwiftUI
import CatGameCore

/// The board owns navigation; a choice is only committed by the fixed confirmation button.
@MainActor
struct TownEventDetailView: View {
    @Bindable var store: GameStore
    let eventID: String
    let dayKey: String
    let showMemento: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedChoiceID: String?
    @State private var isVisible = false
    @State private var isWorking = false
    @State private var failed = false
    @State private var letter: TownEventReceipt?
    @State private var opensEnvelope = false
    private var event: TownEventDefinition? { TownEventCatalog.event(id: eventID) }
    private var receipt: TownEventReceipt? { store.snapshot?.community.events.todayReceipt }
    private var selectedChoice: TownEventChoice? { event?.choices.first { $0.id == selectedChoiceID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let event, let snapshot = store.snapshot {
                    TownEventInvitation(event: event, date: snapshot.meta.lastSyncAt, completed: receipt != nil)
                    if let receipt {
                        Button { opensEnvelope = false; letter = receipt } label: {
                            completedRow("townEvents.letterKept", detail: GameStrings.text("townEvents.reread"), symbol: "envelope.fill")
                        }.buttonStyle(.plain).accessibilityIdentifier("townEventTodayLetter")
                        Button(action: showMemento) {
                            completedRow("townEvents.memento", detail: GameStrings.format("townEvents.progress",
                                min(snapshot.community.events.totalCompleted, TownEventCatalog.milestones[0].target),
                                TownEventCatalog.milestones[0].target), symbol: "photo.artframe")
                        }.buttonStyle(.plain).accessibilityIdentifier("townEventMementoProgress")
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) { choiceHeading }.fixedSize()
                            VStack(alignment: .leading, spacing: 5) { choiceHeading }
                        }.fixedSize(horizontal: false, vertical: true)
                        if failed {
                            Label(GameStrings.text("townEvents.saveFailed"), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("townEventSaveFailed")
                        }
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 14) { ForEach(event.choices) { choiceCard($0, snapshot: snapshot) } }
                        } else {
                            HStack(alignment: .top, spacing: 12) { ForEach(event.choices) { choiceCard($0, snapshot: snapshot) } }
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(GameStrings.text("townEvents.refreshHint")).font(.caption.weight(.semibold))
                        .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                } else { ContentUnavailableView(GameStrings.text("townEvents.empty"), systemImage: "envelope") }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("townEventDetail")
        .safeAreaInset(edge: .bottom, spacing: 0) { if receipt == nil { confirmationBar } }
        .overlay {
            if isWorking {
                ZStack { RoomTheme.ink.opacity(0.3).ignoresSafeArea(); TownEventSavingView() }
                    .accessibilityAddTraits(.isModal)
            }
        }
        .sheet(item: $letter) { TownEventLetterSheet(receipt: $0, opensEnvelope: opensEnvelope) }
        .onAppear { isVisible = true }.onDisappear { isVisible = false }
        .onChange(of: store.saveSceneGeneration) { _, _ in selectedChoiceID = nil; letter = nil; failed = false }
        .onChange(of: store.snapshot) { _, snapshot in
            if let choice = selectedChoice, let snapshot,
               TownEventPresentation.failure(choice, day: dayKey, in: snapshot) != nil { selectedChoiceID = nil }
        }
    }

    @ViewBuilder private var choiceHeading: some View {
        Text(GameStrings.text("townEvents.chooseWay")).font(.headline.weight(.heavy))
        Text(GameStrings.text("townEvents.choiceHint")).font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
    }

    private func choiceCard(_ choice: TownEventChoice, snapshot: GameSnapshot) -> some View {
        let failure = TownEventPresentation.failure(choice, day: dayKey, in: snapshot)
        let selected = selectedChoiceID == choice.id && failure == nil
        let gain = min(choice.friendshipReward, max(0, 100 - snapshot.community.relationship(for: event?.neighborID ?? "").friendship))
        return Button {
            if let failure {
                store.playFeedback(.softError)
                store.showNotice(GameActionNotice.message(for: ActionOutcome(failure: failure), snapshot: snapshot))
            } else { selectedChoiceID = choice.id; store.playNavigationSound() }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                GameIconTile(symbol: choice.staminaCost > 0 ? "hand.thumbsup.fill" : "shippingbox.fill",
                             tint: choice.staminaCost > 0 ? RoomTheme.darkMint : RoomTheme.gold,
                             background: choice.staminaCost > 0 ? RoomTheme.paleMint : RoomTheme.gold.opacity(0.2), size: 42)
                Text(GameStrings.text(choice.staminaCost > 0 ? "townEvents.helpType" : "townEvents.supplyType"))
                    .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.secondary)
                Text(GameStrings.text(choice.titleKey)).font(.subheadline.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 38, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(GameStrings.text("townEvents.cost")).font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) { choiceCost(choice, snapshot: snapshot) }.fixedSize()
                        VStack(alignment: .leading, spacing: 4) { choiceCost(choice, snapshot: snapshot) }
                    }
                }.foregroundStyle(failure == nil ? RoomTheme.ink : RoomTheme.coralDeep)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 13))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) { choiceRewards(choice, gain: gain) }.fixedSize()
                    VStack(alignment: .leading, spacing: 6) { choiceRewards(choice, gain: gain) }
                }.font(.caption2.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                if let failure {
                    Text(GameActionNotice.message(for: ActionOutcome(failure: failure), snapshot: snapshot))
                        .font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.coralDeep).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12).padding(.top, 6).frame(maxWidth: .infinity, minHeight: 220,
                maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .topLeading)
            .gameCard(cornerRadius: 25)
            .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(selected ? RoomTheme.mint : .clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(RoomTheme.mint, RoomTheme.paper)
                        .font(.title3).padding(9).accessibilityHidden(true)
                } else if choice.friendshipReward == event?.choices.map(\.friendshipReward).max(), choice.staminaCost == 0 {
                    Text(GameStrings.text("townEvents.moreFriendship")).font(.caption2.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(RoomTheme.friendship, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 2)).offset(y: -8).padding(.trailing, 9)
                }
            }.opacity(failure == nil ? 1 : 0.6).contentShape(RoundedRectangle(cornerRadius: 25))
        }
        .buttonStyle(.plain).disabled(isWorking || store.isBusy)
        .accessibilityElement(children: .combine).accessibilityIdentifier("townEventChoice_\(choice.id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(failure == nil ? GameStrings.text(selected ? "townEvents.selected" : "townEvents.notSelected")
                            : GameStrings.text("townEvents.choiceUnavailable"))
    }

    @ViewBuilder private func choiceCost(_ choice: TownEventChoice, snapshot: GameSnapshot) -> some View {
        Text(TownEventPresentation.costs(choice).joined(separator: " · ")).font(.caption.weight(.heavy))
        Text(TownEventPresentation.available(choice, in: snapshot)).font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
    }

    @ViewBuilder private func choiceRewards(_ choice: TownEventChoice, gain: Int) -> some View {
        Label(gain > 0 ? GameStrings.format("townEvents.friendshipGain", gain) : GameStrings.text("community.closestShort"), systemImage: "heart.fill")
            .foregroundStyle(RoomTheme.friendshipDeep).padding(6).background(RoomTheme.friendshipPaper, in: Capsule())
        Text(TownEventPresentation.rewards(choice.rewards)).foregroundStyle(RoomTheme.ink)
            .padding(6).background(RoomTheme.gold.opacity(0.2), in: Capsule())
    }

    private var confirmationBar: some View {
        Button { participate() } label: {
            Label(selectedChoice.map { GameStrings.format("townEvents.confirmChoice", GameStrings.text($0.titleKey)) }
                  ?? GameStrings.text("townEvents.selectFirst"), systemImage: "paperplane.fill")
                .font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
        }
        .buttonStyle(MintButtonStyle())
        .disabled(isWorking || store.isBusy || selectedChoice == nil || store.snapshot == nil)
        .padding(16).background(RoomTheme.cream).accessibilityIdentifier("townEventConfirmButton")
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func completedRow(_ key: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(RoomTheme.darkMint)
            VStack(alignment: .leading, spacing: 5) {
                Text(GameStrings.text(key)).font(.subheadline.weight(.heavy))
                Text(detail).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption.weight(.heavy))
        }.padding(16).frame(maxWidth: .infinity, minHeight: 72).gameCard(cornerRadius: 22)
    }

    private func participate() {
        guard !isWorking, !store.isBusy, let choice = selectedChoice, let snapshot = store.snapshot else { return }
        if let failure = TownEventPresentation.failure(choice, day: dayKey, in: snapshot) {
            store.showNotice(GameActionNotice.message(for: ActionOutcome(failure: failure), snapshot: snapshot)); selectedChoiceID = nil
            return
        }
        isWorking = true; failed = false
        let generation = store.saveSceneGeneration
        Task {
            let saved = await store.resolveTownEvent(eventID: eventID, choiceID: choice.id, dayKey: dayKey) { receipt in
                guard isVisible, scenePhase == .active, store.activeSheet == .town, store.isShowingTownBoard,
                      store.saveSceneGeneration == generation, receipt.eventID == eventID, receipt.dayKey == dayKey else { return false }
                opensEnvelope = true; letter = receipt
                return true
            }
            isWorking = false
            if saved == nil, store.saveSceneGeneration == generation { failed = store.hasSaveFailure }
        }
    }
}
