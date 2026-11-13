import SwiftUI
import CatGameCore

@MainActor
enum TownEventAccessibility {
    static func value(_ text: String, diagnostic: String) -> String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return diagnostic }
        #endif
        return text
    }
}

@MainActor
enum TownEventPresentation {
    static func title(_ receipt: TownEventReceipt) -> String {
        GameStrings.text(TownEventCatalog.event(id: receipt.eventID)?.titleKey ?? "townEvents.letter.archivedTitle")
    }

    static func sender(_ neighborID: String) -> String {
        CommunityCatalog.neighbor(id: neighborID).map { GameStrings.text($0.nameKey) }
            ?? GameStrings.text("townEvents.letter.fromTown")
    }

    static func sender(_ receipt: TownEventReceipt) -> String {
        receipt.responseKey == "townEvents.letter.archived" ? GameStrings.text("townEvents.letter.fromTown") : sender(receipt.neighborID)
    }

    static func choice(_ receipt: TownEventReceipt) -> String? {
        TownEventCatalog.event(id: receipt.eventID)?.choices.first { $0.id == receipt.choiceID }
            .map { GameStrings.text($0.titleKey) }
    }

    static func available(_ choice: TownEventChoice, in snapshot: GameSnapshot) -> String {
        if choice.staminaCost > 0 { return GameStrings.format("townEvents.haveStamina", snapshot.player.stamina) }
        let count = choice.supplyCost.map { snapshot.inventory.count($0) }
            ?? choice.giftID.map { snapshot.inventory.giftCount($0) } ?? 0
        return GameStrings.format("townEvents.haveStock", count)
    }

    static func failure(_ choice: TownEventChoice, day: String, in snapshot: GameSnapshot) -> ActionFailure? {
        TownEventCatalog.eligibility(eventID: choice.eventID, choiceID: choice.id, dayKey: day, in: snapshot)
    }

    static func costs(_ choice: TownEventChoice) -> [String] {
        var lines: [String] = []
        if choice.staminaCost > 0 { lines.append(GameStrings.format("townEvents.staminaCost", choice.staminaCost)) }
        if let supply = choice.supplyCost, choice.supplyCount > 0 {
            lines.append(GameStrings.format("townEvents.supplyCost",
                GameStrings.text(SupplyCatalog.definition(for: supply).nameKey), choice.supplyCount))
        }
        if let id = choice.giftID, let gift = CommunityCatalog.gift(id: id) {
            lines.append(GameStrings.format("townEvents.giftCost", GameStrings.text(gift.nameKey), 1))
        }
        return lines
    }

    static func rewards(_ value: TownEventRewards) -> String {
        var parts: [String] = []
        if value.gold > 0 { parts.append(GameStrings.format("townEvents.reward.gold", value.gold)) }
        for (key, count) in [("food", value.food), ("litter", value.litter), ("toys", value.toys),
                             ("premiumFood", value.premiumFood), ("premiumLitter", value.premiumLitter)] where count > 0 {
            parts.append(GameStrings.format("townEvents.reward.\(key)", count))
        }
        return parts.joined(separator: " · ")
    }
}

struct TownBoardBackground: View {
    var body: some View {
        RoomTheme.cork.overlay {
            Canvas { context, size in
                for y in stride(from: 0.0, to: size.height, by: 14) {
                    for x in stride(from: 0.0, to: size.width, by: 14) {
                        context.fill(Path(ellipseIn: CGRect(x: x + 6, y: y + 5, width: 2.5, height: 2.5)),
                                     with: .color(RoomTheme.ink.opacity(0.15)))
                        context.fill(Path(ellipseIn: CGRect(x: x + 11, y: y + 11, width: 2, height: 2)),
                                     with: .color(.white.opacity(0.25)))
                    }
                }
            }.accessibilityHidden(true)
        }.ignoresSafeArea()
    }
}

struct TownBoardHeader: View {
    let stamina: Int
    var backID = "townBoardBackButton"
    var backTitle = "tab.town"
    let back: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) { HStack { backButton; Spacer(); energy }; plaque }
            } else {
                HStack(spacing: 10) { backButton; plaque; Spacer(minLength: 0); energy }
            }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
    private var backButton: some View {
        Button(action: back) {
            Label(GameStrings.text(backTitle), systemImage: "chevron.left")
                .font(.caption.weight(.heavy)).padding(.horizontal, 12).frame(minHeight: 44).gameCard(cornerRadius: 24)
        }.buttonStyle(.plain).accessibilityIdentifier(backID)
    }
    private var plaque: some View {
        Label {
            Text(GameStrings.text("townEvents.title")).fixedSize(horizontal: false, vertical: true)
        } icon: { Image(systemName: "pin.fill").foregroundStyle(RoomTheme.friendship) }
            .font(.headline.weight(.heavy)).padding(.horizontal, 12).padding(.vertical, 13)
            .background {
                RoundedRectangle(cornerRadius: 17).fill(RoomTheme.wood.gradient)
                    .shadow(color: TownPalette.woodEdge, radius: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(TownPalette.woodEdge, lineWidth: 2.5))
            }.accessibilityAddTraits(.isHeader)
    }
    private var energy: some View {
        Label("\(stamina)", systemImage: "bolt.fill").font(.subheadline.weight(.heavy)).monospacedDigit()
            .foregroundStyle(RoomTheme.darkMint).padding(.horizontal, 12).frame(minHeight: 38).gameCard(cornerRadius: 24)
            .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text("resource.stamina"))
            .accessibilityValue("\(stamina)").accessibilityIdentifier("townBoardStamina")
    }
}

struct TownLetterLines: View {
    var body: some View {
        Canvas { context, size in
            for y in stride(from: 28.0, to: size.height, by: 30) {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(RoomTheme.wood.opacity(0.5)), lineWidth: 1)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct TownEventInvitation: View {
    let event: TownEventDefinition
    let date: Date
    var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var stamped = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if let neighbor = CommunityCatalog.neighbor(id: event.neighborID) { CommunityPortrait(neighbor: neighbor, size: 52) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(GameStrings.format("townEvents.letterFrom", TownEventPresentation.sender(event.neighborID)))
                        .font(.caption.weight(.heavy)).foregroundStyle(senderTint)
                    Text(GameStrings.text(event.titleKey)).font(.system(.title3, design: .rounded, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("townEventTitle")
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(date, format: .dateTime.month().day()).font(.caption2.weight(.heavy))
                        .multilineTextAlignment(.center).frame(width: 53, height: 53)
                        .overlay(Circle().strokeBorder(TownPalette.woodEdge, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        .rotationEffect(.degrees(10)).foregroundStyle(RoomTheme.secondary)
                }
            }
            Text(GameStrings.text(event.bodyKey)).font(.subheadline.weight(.semibold)).lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 4).background(TownLetterLines())
            if completed {
                Label(GameStrings.text("townEvents.participated"), systemImage: "checkmark.seal.fill")
                    .font(.headline.weight(.heavy)).foregroundStyle(RoomTheme.darkMint)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(RoomTheme.mint, lineWidth: 2))
                    .rotationEffect(.degrees(reduceMotion ? 0 : -6))
                    .scaleEffect(stamped || reduceMotion ? 1 : 1.3).opacity(stamped || reduceMotion ? 1 : 0)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16).background {
            UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 5)
                .fill(RoomTheme.letterPaper).shadow(color: RoomTheme.ink.opacity(0.15), radius: 0, y: 5)
        }
        .overlay(alignment: .top) {
            Circle().fill(RoomTheme.friendship.gradient).frame(width: 20, height: 20)
                .shadow(color: RoomTheme.ink.opacity(0.25), radius: 2, y: 3).offset(y: -10).accessibilityHidden(true)
        }
        .rotationEffect(.degrees(dynamicTypeSize.isAccessibilitySize || reduceMotion ? 0 : -1))
        .onChange(of: completed, initial: true) { _, value in
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { stamped = value }
        }
    }
    private var senderTint: Color {
        CommunityCatalog.neighbor(id: event.neighborID).map(CommunityPalette.tint) ?? RoomTheme.secondary
    }
}

struct TownEventRewardsView: View {
    let receipt: TownEventReceipt
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var supplies: [(kind: SupplyKind, count: Int)] {
        [(.food, receipt.rewards.food), (.litter, receipt.rewards.litter), (.toy, receipt.rewards.toys),
         (.premiumFood, receipt.rewards.premiumFood), (.premiumLitter, receipt.rewards.premiumLitter)]
            .filter { $0.count > 0 }
    }
    private var hasItems: Bool { receipt.rewards.gold > 0 || !supplies.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(GameStrings.text("townEvents.received"), systemImage: "gift.fill")
                .font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.darkMint)
            if receipt.friendshipGained > 0 {
                Label(GameStrings.format("townEvents.friendshipGain", receipt.friendshipGained), systemImage: "heart.fill")
                    .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.friendshipDeep)
            }
            if receipt.stageAfter > receipt.stageBefore,
               let stage = CommunityCatalog.stages.first(where: { $0.level == receipt.stageAfter }) {
                Text(GameStrings.format("townEvents.stageReached", GameStrings.text(stage.nameKey)))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.friendshipDeep)
            }
            if hasItems {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                         count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                          alignment: .leading, spacing: 8) {
                    if receipt.rewards.gold > 0 {
                        reward(GameStrings.text("resource.gold"), amount: receipt.rewards.gold,
                               asset: "", symbol: "dollarsign.circle.fill", tint: RoomTheme.gold)
                    }
                    ForEach(Array(supplies.enumerated()), id: \.offset) { _, row in
                        let supply = SupplyCatalog.definition(for: row.kind)
                        reward(GameStrings.text(supply.nameKey), amount: row.count,
                               asset: supply.assetName, symbol: supply.symbol, tint: RoomTheme.darkMint)
                    }
                }
            } else {
                Text(GameStrings.text("townEvents.noReward")).font(.caption.weight(.semibold))
                    .foregroundStyle(RoomTheme.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RoomTheme.rewardBorder, lineWidth: 2))
        .accessibilityElement(children: .contain).accessibilityIdentifier("townEventActualRewards")
    }

    private func reward(_ name: String, amount: Int, asset: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            GameIcon(asset: asset, symbol: symbol, size: 27, tint: tint)
            Text("\(name) +\(amount)").font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TownEventLetterView: View {
    let receipt: TownEventReceipt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                if let neighbor = CommunityCatalog.neighbor(id: receipt.neighborID) {
                    CommunityPortrait(neighbor: neighbor, size: 58)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(GameStrings.text("townEvents.resultTitle")).font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.secondary)
                    Text(GameStrings.format("townEvents.letterFrom", TownEventPresentation.sender(receipt)))
                        .font(.title3.weight(.heavy))
                    Text(receipt.completedAt, format: .dateTime.year().month().day())
                        .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "pawprint.fill").font(.title2).foregroundStyle(RoomTheme.friendship)
                    .frame(width: 44, height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(RoomTheme.friendship, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    .rotationEffect(.degrees(8)).accessibilityHidden(true)
            }
            Text(TownEventPresentation.choice(receipt).map {
                GameStrings.format("townEvents.letterChoice", TownEventPresentation.title(receipt), $0)
            } ?? TownEventPresentation.title(receipt)).font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.coralDeep)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 18) {
                Text(GameStrings.text(receipt.responseKey)).font(.body.weight(.semibold)).lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(GameStrings.format("townEvents.signature", TownEventPresentation.sender(receipt)))
                    .font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.coralDeep).frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(.vertical, 8).background(TownLetterLines())
            TownEventRewardsView(receipt: receipt)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(RoomTheme.letterPaper)
                .shadow(color: RoomTheme.wood.opacity(0.25), radius: 0, y: 5)
        }
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white, lineWidth: 3))
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { appeared = true } }
        .accessibilityElement(children: .contain).accessibilityIdentifier("townEventLetter")
        .accessibilityValue(TownEventAccessibility.value(TownEventPresentation.title(receipt), diagnostic: receipt.eventID))
    }
}

@MainActor
struct TownEventLetterSheet: View {
    let receipt: TownEventReceipt
    var opensEnvelope = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var opened = false

    var body: some View {
        Group {
            if opensEnvelope && !opened && !reduceMotion {
                TownEventSavingView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView { TownEventLetterView(receipt: receipt).padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity) }
                    .scrollBounceBehavior(.basedOnSize)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        Button { dismiss() } label: {
                            Text(GameStrings.text("townEvents.backToBoard")).font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
                        }.buttonStyle(MintButtonStyle())
                            .padding(16).background(RoomTheme.letterPaper).accessibilityIdentifier("townEventBackButton")
                    }
            }
        }
        .presentationBackground(RoomTheme.letterPaper).presentationDragIndicator(.visible)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(600), .large])
        .interactiveDismissDisabled(opensEnvelope && !opened && !reduceMotion)
        .task {
            guard opensEnvelope && !reduceMotion else { opened = true; return }
            do { try await Task.sleep(for: .milliseconds(850)) } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { opened = true }
        }
    }
}

struct TownEventSavingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: opened ? "envelope.open.fill" : "envelope.fill")
                .font(.system(size: 72, weight: .medium)).foregroundStyle(RoomTheme.friendship)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace.offUp))
                .scaleEffect(reduceMotion || opened ? 1 : 0.8).accessibilityHidden(true)
            Text(GameStrings.text("townEvents.working")).font(.headline.weight(.heavy))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ProgressView().tint(RoomTheme.darkMint)
        }.padding(28).gameCard(cornerRadius: 28).padding(24)
            .accessibilityElement(children: .combine).accessibilityIdentifier("townEventSaving")
            .onAppear { withAnimation(reduceMotion ? nil : .spring(duration: 0.6)) { opened = true } }
    }
}
