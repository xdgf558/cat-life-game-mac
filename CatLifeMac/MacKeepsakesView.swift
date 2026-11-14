#if os(macOS)
import SwiftUI
import CatGameCore

/// 纪念册 (2.0), the Cats page's second tab: keepsakes by spot, garden decor and what the placed
/// decor is doing for the home right now (K1 / K2 / K4). Duplicates are compared here too (K3).
@MainActor
struct MacKeepsakesView: View {
    let store: GameStore
    /// Enter arrange mode with this furniture item selected.
    let arrange: (String) -> Void
    var openGarden: () -> Void = {}

    private enum Section: String, CaseIterable { case keepsakes, decor, bonus }
    @State private var section: Section = .keepsakes
    @State private var selectedKeepsake: String?
    @State private var selectedDecor: String?
    @State private var comparing: String?
    @State private var saving = false

    private var outing: OutingState { store.snapshot?.outing ?? OutingState() }
    private var hasShelf: Bool { store.snapshot?.inventory.furniture.contains { $0.id == OutingCatalog.shelfItemID } ?? false }

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 14) {
                categories.frame(width: 210)
                Group {
                    switch section {
                    case .keepsakes: keepsakeGrid
                    case .decor: decorGrid
                    case .bonus: bonusPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if section != .bonus { detail.frame(width: 300) }
            }
            if let comparing, outing.decor[comparing]?.pendingDuplicate != nil {
                MacModalScrim { MacDecorCompareCard(store: store, decorID: comparing, onLater: { self.comparing = nil }) }
            }
        }
        .font(.system(size: 13.5, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .accessibilityElement(children: .contain).accessibilityIdentifier("macKeepsakesPage")
        .onAppear {
            selectedKeepsake = selectedKeepsake ?? OutingCatalog.keepsakes.first { outing.keepsakes[$0.id] != nil }?.id
            selectedDecor = selectedDecor ?? OutingCatalog.decor.first { outing.decor[$0.id] != nil }?.id
            // A duplicate brought home waits for its compare the first time the album opens.
            if outing.trip == nil { comparing = outing.pendingDuplicates.first }
        }
        .onChange(of: store.saveSceneGeneration) { _, _ in comparing = nil; selectedKeepsake = nil; selectedDecor = nil }
    }

    // MARK: Categories

    private var categories: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameStrings.text("outing.album.title")).font(.system(size: 17, weight: .heavy))
            category(.keepsakes, symbol: "book.closed.fill",
                     count: GameStrings.format("outing.album.count", outing.foundKeepsakeCount, OutingCatalog.keepsakes.count))
            category(.decor, symbol: "sofa.fill",
                     count: GameStrings.format("outing.album.count", OutingCatalog.decor.filter { outing.decor[$0.id] != nil }.count,
                                               OutingCatalog.decor.count))
            category(.bonus, symbol: "sparkles",
                     count: GameStrings.format("outing.album.count", store.snapshot.map { OutingBonuses.active(in: $0).count } ?? 0,
                                               OutingCatalog.maximumActiveDecor))
            Spacer(minLength: 0)
            if !outing.pendingDuplicates.isEmpty, outing.trip == nil {
                Button { comparing = outing.pendingDuplicates.first } label: {
                    Label(GameStrings.format("outing.compare.pending", outing.pendingDuplicates.count), systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.paleCoral.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityIdentifier("albumComparePending")
            }
            Button(action: openGarden) {
                Label(GameStrings.text("outing.album.toGarden"), systemImage: "camera.macro")
                    .font(.system(size: 12.5, weight: .heavy)).frame(maxWidth: .infinity)
            }.buttonStyle(SoftButtonStyle())
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .macContentCard69(padding: 12)
    }

    private func category(_ value: Section, symbol: String, count: String) -> some View {
        Button { section = value } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 20)
                Text(GameStrings.text("outing.album.\(value.rawValue)")).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(count).font(.system(size: 11, weight: .heavy)).monospacedDigit().opacity(0.8)
            }
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(section == value ? .white : RoomTheme.ink)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(section == value ? RoomTheme.mint : RoomTheme.cream.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityAddTraits(section == value ? .isSelected : [])
        .accessibilityIdentifier("albumSection_\(value.rawValue)")
    }

    // MARK: Keepsakes (K1)

    private var keepsakeGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(OutingSpot.allCases) { spot in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(GameStrings.text(spot.titleKey), systemImage: MacGardenScene.symbol(spot))
                            .font(.system(size: 13.5, weight: .heavy)).foregroundStyle(MacGardenScene.tint(spot))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                            ForEach(OutingCatalog.keepsakes(at: spot)) { item in keepsakeSlot(item) }
                        }
                    }
                }
                if hasShelf {
                    Text(GameStrings.format("outing.shelf.count", outing.shelfCount, OutingCatalog.shelfSlots))
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                } else {
                    Text(GameStrings.format("outing.shelf.locked", OutingCatalog.keepsakeShelfThreshold))
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                }
            }.padding(2)
        }
        .scrollIndicators(.never)
        .macContentCard69(padding: 14)
    }

    private func keepsakeSlot(_ item: OutingKeepsakeDefinition) -> some View {
        let record = outing.keepsakes[item.id]
        let selected = selectedKeepsake == item.id
        return Button { selectedKeepsake = item.id } label: {
            VStack(spacing: 5) {
                if record != nil {
                    GameIcon(asset: "keepsake-\(item.id)", symbol: item.symbol, size: 40, tint: RoomTheme.friendshipDeep)
                        .frame(height: 48)
                    Text(GameStrings.text(item.nameKey)).font(.system(size: 11.5, weight: .heavy)).lineLimit(2)
                        .multilineTextAlignment(.center).minimumScaleFactor(0.8)
                } else {
                    Text("?").font(.system(size: 24, weight: .heavy)).foregroundStyle(RoomTheme.secondary.opacity(0.6)).frame(height: 48)
                    Text(GameStrings.text("outing.album.unfound")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                }
            }
            .padding(8).frame(maxWidth: .infinity, minHeight: 96)
            .background(record == nil ? Color.clear : (selected ? RoomTheme.friendshipPaper : RoomTheme.cream.opacity(0.7)),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? RoomTheme.friendship : RoomTheme.track,
                                                                    style: StrokeStyle(lineWidth: 2, dash: record == nil ? [5, 4] : [])))
            .overlay(alignment: .topTrailing) {
                if record?.onShelf == true {
                    Image(systemName: "square.stack.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(4).background(RoomTheme.friendship, in: Circle()).padding(5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain).disabled(record == nil)
        .accessibilityLabel(record == nil ? GameStrings.text("outing.album.unfound") : GameStrings.text(item.nameKey))
        .accessibilityIdentifier("albumKeepsake_\(item.id)")
    }

    // MARK: Decor (K2)

    private var decorGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                ForEach(OutingCatalog.decor) { item in decorCard(item) }
            }.padding(2)
        }
        .scrollIndicators(.never)
        .macContentCard69(padding: 14)
    }

    private func decorState(_ item: OutingDecorDefinition) -> String {
        guard outing.decor[item.id] != nil else { return GameStrings.text("outing.album.unfound") }
        let placed = store.snapshot?.home.furniture.contains { $0.itemID == item.itemID } ?? false
        guard placed else { return GameStrings.text("outing.decor.inBag") }
        let active = store.snapshot.map { OutingBonuses.active(in: $0).contains { $0.decorID == item.id } } ?? false
        return GameStrings.text(active ? "outing.decor.active" : "outing.decor.inactive")
    }

    private func decorCard(_ item: OutingDecorDefinition) -> some View {
        let record = outing.decor[item.id]
        let selected = selectedDecor == item.id
        return Button { selectedDecor = item.id } label: {
            VStack(spacing: 6) {
                ZStack {
                    if let roll = record?.kept {
                        Circle().fill(MacOutingText.qualityTint(roll.quality).opacity(0.18)).frame(width: 70, height: 70)
                    }
                    if record != nil {
                        GameIcon(asset: FurnitureCatalog.metadata(for: item.kind).assetName, symbol: item.symbol, size: 48,
                                 tint: record.map { MacOutingText.qualityTint($0.kept.quality) } ?? RoomTheme.secondary)
                    } else {
                        Text("?").font(.system(size: 26, weight: .heavy)).foregroundStyle(RoomTheme.secondary.opacity(0.6))
                    }
                }.frame(height: 72)
                Text(record == nil ? GameStrings.text("outing.album.unfound") : GameStrings.text(item.nameKey))
                    .font(.system(size: 12.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                if let roll = record?.kept {
                    Text(GameStrings.text(roll.quality.titleKey) + " · " + MacOutingText.attribute(roll))
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(MacOutingText.qualityTint(roll.quality))
                        .lineLimit(1).minimumScaleFactor(0.75)
                } else {
                    Text(GameStrings.format("outing.decor.where", GameStrings.text(item.spot.titleKey)))
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                }
                Text(decorState(item)).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
            }
            .padding(10).frame(maxWidth: .infinity)
            .background(selected ? RoomTheme.paleMint : RoomTheme.cream.opacity(record == nil ? 0.25 : 0.7), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? RoomTheme.mint : RoomTheme.track,
                                                                    style: StrokeStyle(lineWidth: 2, dash: record == nil ? [5, 4] : [])))
            .overlay(alignment: .topTrailing) {
                if record?.pendingDuplicate != nil {
                    Text(GameStrings.text("outing.decor.newCopy")).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3).background(RoomTheme.coral, in: Capsule()).padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("albumDecor_\(item.id)")
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if section == .keepsakes {
                if let id = selectedKeepsake, let item = OutingCatalog.keepsake(id: id), let record = outing.keepsakes[id] {
                    keepsakeDetail(item, record)
                } else { emptyDetail("outing.album.pickKeepsake") }
            } else if let id = selectedDecor, let item = OutingCatalog.decor(id: id) {
                decorDetail(item, outing.decor[id])
            } else { emptyDetail("outing.album.pickDecor") }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .macContentCard69(padding: 14)
    }

    private func emptyDetail(_ key: String) -> some View {
        Text(GameStrings.text(key)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            .frame(maxWidth: .infinity, alignment: .center).padding(.top, 40)
    }

    private func catName(_ id: String) -> String {
        store.snapshot?.cats.first { $0.id == id }.map(GameStrings.catName) ?? GameStrings.text("outing.album.someCat")
    }

    private func keepsakeDetail(_ item: OutingKeepsakeDefinition, _ record: OutingKeepsakeRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                GameIcon(asset: "keepsake-\(item.id)", symbol: item.symbol, size: 72, tint: RoomTheme.friendshipDeep)
                    .frame(width: 96, height: 96).background(RoomTheme.friendshipPaper, in: Circle())
                Spacer()
            }
            Text(GameStrings.text(item.nameKey)).font(.system(size: 18, weight: .heavy))
            Text(GameStrings.text(item.storyKey)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(GameStrings.text("outing.album.thatDay")).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            Text(GameStrings.format("outing.album.foundBy", record.foundAt.formatted(date: .abbreviated, time: .omitted),
                                    catName(record.catID), GameStrings.text(item.spot.titleKey)))
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            Text(GameStrings.format(record.storyKey, catName(record.catID))).font(.system(size: 12.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Toggle(isOn: Binding(get: { record.onShelf }, set: { value in
                guard !saving else { return }
                saving = true
                Task { _ = await store.setKeepsakeOnShelf(keepsakeID: item.id, onShelf: value); saving = false }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameStrings.text("outing.shelf.toggle")).font(.system(size: 13, weight: .heavy))
                    Text(hasShelf ? GameStrings.format("outing.shelf.count", outing.shelfCount, OutingCatalog.shelfSlots)
                         : GameStrings.format("outing.shelf.locked", OutingCatalog.keepsakeShelfThreshold))
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                }
            }
            .toggleStyle(.switch).tint(RoomTheme.friendship)
            .disabled(saving || !hasShelf || (!record.onShelf && outing.shelfCount >= OutingCatalog.shelfSlots))
            .accessibilityIdentifier("albumShelfToggle")
        }
    }

    private func decorDetail(_ item: OutingDecorDefinition, _ record: OutingDecorRecord?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let record {
                let loot = OutingLoot(id: item.id, kind: .decor, itemID: item.id, roll: record.kept, gold: 0, duplicate: false)
                MacOutingLootDetail(loot: loot, catName: catName(record.kept.catID), reactionKey: nil, outing: nil)
                    .frame(maxWidth: .infinity)
                Text(GameStrings.format("outing.album.foundBy", record.kept.foundAt.formatted(date: .abbreviated, time: .omitted),
                                        catName(record.kept.catID), GameStrings.text(item.spot.titleKey)))
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                Text(GameStrings.text(item.placement == .wall ? "outing.decor.wall" : "outing.decor.floor"))
                    .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                Text(decorState(item)).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                Spacer(minLength: 0)
                if record.pendingDuplicate != nil {
                    Button { comparing = item.id } label: {
                        Text(GameStrings.text("outing.compare.open")).font(.system(size: 13, weight: .heavy)).frame(maxWidth: .infinity)
                    }.buttonStyle(SoftButtonStyle()).disabled(outing.trip != nil)
                }
                Button { arrange(item.itemID) } label: {
                    Text(GameStrings.text("outing.decor.arrange")).font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("albumArrange")
            } else {
                Text("?").font(.system(size: 40, weight: .heavy)).foregroundStyle(RoomTheme.secondary.opacity(0.5)).frame(maxWidth: .infinity)
                Text(GameStrings.format("outing.decor.where", GameStrings.text(item.spot.titleKey)))
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            }
        }
    }

    // MARK: Home bonus (K4)

    private var bonusPage: some View {
        let active = store.snapshot.map(OutingBonuses.active(in:)) ?? []
        let inactive = store.snapshot.map(OutingBonuses.inactivePlaced(in:)) ?? []
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(GameStrings.text("outing.bonus.title")).font(.system(size: 16, weight: .heavy))
                Text(GameStrings.text("outing.bonus.subtitle")).font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(0..<OutingCatalog.maximumActiveDecor, id: \.self) { index in
                    if active.indices.contains(index), let item = OutingCatalog.decor(id: active[index].decorID) {
                        HStack(spacing: 10) {
                            GameIcon(asset: FurnitureCatalog.metadata(for: item.kind).assetName, symbol: item.symbol, size: 32,
                                     tint: MacOutingText.qualityTint(active[index].quality))
                                .frame(width: 44, height: 44).background(MacOutingText.qualityTint(active[index].quality).opacity(0.15), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(GameStrings.text(item.nameKey)).font(.system(size: 13.5, weight: .heavy))
                                Text(GameStrings.format("outing.attribute.\(active[index].attribute.rawValue).value", active[index].value))
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                            }
                            Spacer(minLength: 0)
                            Text(GameStrings.text(active[index].quality.titleKey)).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3).background(MacOutingText.qualityTint(active[index].quality), in: Capsule())
                        }
                        .padding(10).background(RoomTheme.cream.opacity(0.75), in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text(GameStrings.text("outing.bonus.emptySlot")).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(RoomTheme.track, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    }
                }
                if !inactive.isEmpty {
                    Text(GameStrings.format("outing.bonus.inactive", inactive.compactMap(OutingCatalog.decor(id:)).map { GameStrings.text($0.nameKey) }.joined(separator: "、")))
                        .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { arrange(active.first.flatMap { OutingCatalog.decor(id: $0.decorID)?.itemID } ?? "") } label: {
                    Text(GameStrings.text("outing.decor.arrange")).font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("bonusArrange")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .macContentCard69(padding: 14)
            VStack(alignment: .leading, spacing: 10) {
                Text(GameStrings.text("outing.bonus.totals")).font(.system(size: 14, weight: .heavy))
                ForEach(OutingDecorAttribute.allCases, id: \.self) { attribute in
                    let value = active.first { $0.attribute == attribute }?.value ?? 0
                    HStack {
                        Text(GameStrings.text(attribute.titleKey)).font(.system(size: 12.5, weight: .bold))
                        Spacer(minLength: 4)
                        Text(value > 0 ? GameStrings.format("outing.attribute.\(attribute.rawValue).value", value) : "—")
                            .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(value > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
                    }
                }
                Divider()
                Text(GameStrings.text("outing.bonus.rules")).font(.system(size: 13, weight: .heavy))
                ForEach(["outing.bonus.rule.placed", "outing.bonus.rule.best", "outing.bonus.rule.open", "outing.bonus.rule.away"], id: \.self) { rule in
                    Label {
                        Text(rule == "outing.bonus.rule.best" ? GameStrings.format(rule, OutingCatalog.maximumActiveDecor) : GameStrings.text(rule))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: { Image(systemName: "sparkle").foregroundStyle(RoomTheme.mint) }
                        .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                }
            }
            .frame(width: 300).frame(maxHeight: .infinity, alignment: .top)
            .macContentCard69(padding: 14)
        }
    }
}

/// K3: one copy per decor. Keep the old one or take the new one; the other becomes gold and the
/// piece stays where it is in the room.
@MainActor
struct MacDecorCompareCard: View {
    let store: GameStore
    let decorID: String
    var onLater: () -> Void
    @State private var saving = false

    var body: some View {
        let item = OutingCatalog.decor(id: decorID)
        let record = store.snapshot?.outing.decor[decorID]
        return VStack(alignment: .leading, spacing: 14) {
            Text(GameStrings.format("outing.compare.title", item.map { GameStrings.text($0.nameKey) } ?? "")).font(.system(size: 18, weight: .heavy))
            Text(GameStrings.format("outing.compare.body", OutingCatalog.duplicateDecorGold)).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            if let item, let record, let pending = record.pendingDuplicate {
                HStack(alignment: .top, spacing: 12) {
                    side("outing.compare.old", item: item, roll: record.kept, keepNew: false)
                    side("outing.compare.new", item: item, roll: pending, keepNew: true)
                }
            }
            Button(action: onLater) {
                Text(GameStrings.text("outing.compare.later")).font(.system(size: 12.5, weight: .heavy)).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).foregroundStyle(RoomTheme.secondary).disabled(saving)
        }
        .padding(20).frame(width: 560)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: 3))
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal).accessibilityIdentifier("outingCompare")
    }

    private func side(_ titleKey: String, item: OutingDecorDefinition, roll: OutingDecorRoll, keepNew: Bool) -> some View {
        VStack(spacing: 8) {
            Text(GameStrings.text(titleKey)).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
            MacOutingLootDetail(loot: OutingLoot(id: titleKey, kind: .decor, itemID: item.id, roll: roll, gold: 0, duplicate: false),
                                catName: "", reactionKey: nil, outing: nil)
            Text(roll.foundAt.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            Button {
                guard !saving else { return }
                saving = true
                Task { _ = await store.resolveDecorDuplicate(decorID: decorID, keepNew: keepNew); saving = false }
            } label: {
                Text(GameStrings.text(keepNew ? "outing.compare.takeNew" : "outing.compare.keepOld")).font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(MintButtonStyle()).disabled(saving)
            .accessibilityIdentifier(keepNew ? "outingCompareTakeNew" : "outingCompareKeepOld")
        }
        .padding(12).frame(maxWidth: .infinity)
        .background(RoomTheme.cream.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
    }
}
#endif
