import SwiftUI
import CatGameCore

@MainActor
struct TownNoticeBoardView: View {
    @Bindable var store: GameStore
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section: Section = .today
    @State private var page = 0
    @State private var claiming = false
    @State private var letter: TownEventReceipt?
    private enum Section: String, CaseIterable, Identifiable {
        case today, letters, memento
        var id: String { rawValue }
        var symbol: String { switch self { case .today: "sun.max.fill"; case .letters: "envelope.fill"; case .memento: "photo.artframe" } }
    }
    private var letters: [TownEventReceipt] { Array((store.snapshot?.community.events.letters ?? []).reversed()) }
    private var pageSize: Int { dynamicTypeSize.isAccessibilitySize ? 2 : 4 }
    private var pageCount: Int { max(1, (letters.count + pageSize - 1) / pageSize) }

    var body: some View {
        VStack(spacing: 0) {
            TownBoardHeader(stamina: store.snapshot?.player.stamina ?? 0, back: onClose)
            tabs.padding(.horizontal, 16).padding(.bottom, 12)
            if section == .today {
                today
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Color.clear.frame(height: 1).id("boardTop")
                            if section == .letters { letterList } else { mementos }
                        }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
                    }.scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("townBoardScroll")
                        .onChange(of: section) { _, _ in proxy.scrollTo("boardTop", anchor: .top) }
                        .onChange(of: page) { _, _ in proxy.scrollTo("boardTop", anchor: .top) }
                }
            }
        }
        .background(TownBoardBackground()).toolbar(.hidden, for: .navigationBar)
        .id(store.saveSceneGeneration).fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .sheet(item: $letter) { TownEventLetterSheet(receipt: $0) }
        .onChange(of: dynamicTypeSize) { _, _ in page = min(page, pageCount - 1) }
        .onChange(of: letters.count) { _, _ in page = min(page, pageCount - 1) }
    }

    private var tabs: some View {
        HStack(spacing: 3) {
            ForEach(Section.allCases) { item in
                Button { store.playNavigationSound(); section = item } label: {
                    Label(GameStrings.text("townEvents.\(item.rawValue)"), systemImage: item.symbol)
                        .font(.caption.weight(.heavy)).labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 3)
                        .foregroundStyle(section == item ? RoomTheme.darkMint : RoomTheme.ink)
                        .background(section == item ? RoomTheme.paper : .clear, in: Capsule())
                        .overlay(alignment: .topTrailing) {
                            if item == .today, store.snapshot?.community.events.todayReceipt == nil {
                                Circle().fill(RoomTheme.friendship).frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(.white, lineWidth: 2)).padding(4).accessibilityHidden(true)
                            }
                        }.contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("townBoardTab_\(item.rawValue)")
                    .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }.padding(4).background(RoomTheme.letterPaper.opacity(0.6), in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var today: some View {
        Group {
            if let snapshot = store.snapshot, let day = snapshot.community.events.dayKey,
               let eventID = snapshot.community.events.eventID {
                TownEventDetailView(store: store, eventID: eventID, dayKey: day, showMemento: { section = .memento })
                    .id("\(eventID)-\(day)")
            } else {
                ContentUnavailableView(GameStrings.text("townEvents.empty"), systemImage: "sun.horizon.fill")
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("townEventToday")
        .accessibilityValue(TownEventAccessibility.value(
            GameStrings.text(store.snapshot?.community.events.todayReceipt == nil ? "townEvents.available" : "townEvents.completed"),
            diagnostic: "\(store.snapshot?.community.events.eventID ?? "")|\(store.snapshot?.community.events.dayKey ?? "")|\(store.snapshot?.community.events.totalCompleted ?? 0)"))
    }

    private var letterList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(GameStrings.text("townEvents.lettersHint")).font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if letters.isEmpty { ContentUnavailableView(GameStrings.text("townEvents.noLetters"), systemImage: "envelope.open") }
            else {
                ForEach(Array(letters.dropFirst(page * pageSize).prefix(pageSize).enumerated()), id: \.element.id) { index, receipt in
                    letterCard(receipt).rotationEffect(.degrees(reduceMotion || dynamicTypeSize.isAccessibilitySize ? 0 : index.isMultiple(of: 2) ? -0.6 : 0.6))
                }
                HStack(spacing: 8) {
                    Button { page -= 1 } label: {
                        Label(GameStrings.text("townEvents.previous"), systemImage: "chevron.left").frame(minHeight: 44)
                    }.disabled(page == 0).opacity(page == 0 ? 0.4 : 1).accessibilityIdentifier("townLettersPrevious")
                    Spacer(minLength: 0)
                    Text(GameStrings.format("townEvents.page", page + 1, pageCount)).monospacedDigit()
                        .accessibilityIdentifier("townLettersPage").accessibilityValue("\(page + 1)/\(pageCount)")
                    Spacer(minLength: 0)
                    Button { page += 1 } label: {
                        Label(GameStrings.text("townEvents.next"), systemImage: "chevron.right").frame(minHeight: 44)
                    }.disabled(page + 1 >= pageCount).opacity(page + 1 >= pageCount ? 0.4 : 1).accessibilityIdentifier("townLettersNext")
                }.font(.caption.weight(.heavy)).buttonStyle(.plain).foregroundStyle(RoomTheme.ink)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("townEventLetters")
    }

    private func letterCard(_ receipt: TownEventReceipt) -> some View {
        let tint = CommunityCatalog.neighbor(id: receipt.neighborID).map(CommunityPalette.tint) ?? RoomTheme.secondary
        return Button { letter = receipt } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "envelope.fill").font(.system(size: 28)).foregroundStyle(tint)
                    .frame(width: 48, height: 56).background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(TownEventPresentation.title(receipt)).font(.subheadline.weight(.heavy))
                    Text(GameStrings.text(receipt.responseKey)).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(RoomTheme.secondary)
                    Text(TownEventPresentation.sender(receipt) + " · " + CatGrowthPresentation.date(receipt.completedAt))
                        .font(.caption2.weight(.heavy)).foregroundStyle(tint)
                    if let choice = TownEventPresentation.choice(receipt) {
                        Text(choice).font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    }
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption.weight(.heavy)).padding(.top, 20)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 22)
        }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityIdentifier("townLetter_\(receipt.id)")
    }

    @ViewBuilder private var mementos: some View {
        if let snapshot = store.snapshot {
            ForEach(TownEventCatalog.milestones) { milestone in
                let count = min(snapshot.community.events.totalCompleted, milestone.target)
                let claimed = snapshot.community.events.claimedMilestoneIDs.contains(milestone.id)
                let failure = TownEventCatalog.milestoneEligibility(id: milestone.id, in: snapshot)
                VStack(spacing: 16) {
                    Image(FurnitureArtwork68.assetName(for: .init(id: "souvenir", kind: milestone.furnitureKind))).resizable().scaledToFit().frame(height: 170)
                        .saturation(count >= milestone.target ? 1 : 0).opacity(count >= milestone.target ? 1 : 0.4)
                        .frame(maxWidth: .infinity).overlay {
                            if count < milestone.target { Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(RoomTheme.secondary) }
                        }.accessibilityHidden(true)
                    Text(GameStrings.text(milestone.titleKey)).font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
                    Text(GameStrings.text(milestone.bodyKey)).font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                              count: dynamicTypeSize.isAccessibilitySize ? 4 : milestone.target), spacing: 10) {
                        ForEach(0..<milestone.target, id: \.self) { index in
                            Image(systemName: "pawprint.fill").font(.system(size: 16, weight: .bold))
                                .foregroundStyle(index < count ? RoomTheme.friendship : RoomTheme.wood)
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .background(index < count ? RoomTheme.friendshipPaper : .clear, in: Circle())
                                .overlay(Circle().strokeBorder(index < count ? RoomTheme.friendship : RoomTheme.wood,
                                    style: StrokeStyle(lineWidth: 2, dash: index < count ? [] : [4, 3])))
                        }
                    }.accessibilityHidden(true)
                    Text(GameStrings.format("townEvents.progress", count, milestone.target))
                        .font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                    if claimed {
                        Button { arrange(milestone.itemID) } label: {
                            Label(GameStrings.text("townEvents.arrangeMemento"), systemImage: "checkmark.seal.fill")
                                .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                        }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy || claiming)
                            .accessibilityIdentifier("townEventArrangeMemento")
                    } else {
                        Button { claim(milestone.id) } label: {
                            Label(count < milestone.target ? GameStrings.format("townEvents.remaining", milestone.target - count)
                                  : GameStrings.text(claiming ? "townEvents.working" : "townEvents.claim"),
                                  systemImage: count < milestone.target ? "lock.fill" : "gift.fill")
                                .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                        }.buttonStyle(FriendshipButtonStyle()).disabled(claiming || store.isBusy || failure != nil)
                            .accessibilityIdentifier("townEventClaim_\(milestone.id)")
                        if count >= milestone.target, let failure {
                            Text(GameActionNotice.message(for: ActionOutcome(failure: failure), snapshot: snapshot))
                                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(18).frame(maxWidth: .infinity).background(RoomTheme.letterPaper, in: RoundedRectangle(cornerRadius: 28))
                    .accessibilityElement(children: .contain).accessibilityIdentifier("townEventMilestone_\(milestone.id)")
                    .accessibilityValue(TownEventAccessibility.value(claimed ? GameStrings.text("townEvents.claimed")
                        : GameStrings.format("townEvents.progress", count, milestone.target),
                        diagnostic: claimed ? "claimed" : failure == nil ? "ready" : "locked"))
            }
        }
    }
    private func claim(_ id: String) {
        guard !claiming, !store.isBusy else { return }
        claiming = true
        Task { _ = await store.claimTownMilestone(milestoneID: id); claiming = false }
    }
    private func arrange(_ id: String) {
        guard !store.isBusy else { return }
        Task {
            if store.furnitureFloor(for: id) != nil || store.availableFurnitureFloor != nil {
                _ = await store.arrangeInventoryFurniture(id: id)
            } else {
                store.activeSheet = nil; store.beginDecorating(); store.showNotice(store.furnitureCapacityNotice)
            }
            store.isFurnitureTrayExpanded = true
        }
    }
}
