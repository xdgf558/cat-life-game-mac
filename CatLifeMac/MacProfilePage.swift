#if os(macOS)
import SwiftUI
import CatGameCore

/// Exits from the profile page into the rest of the game.
struct MacProfileExits {
    var work: () -> Void = {}
    var bag: () -> Void = {}
    var shopEquipment: () -> Void = {}
    var saves: () -> Void = {}
}

/// "My Profile" on the desktop: character on the left, what you wear in the middle, your numbers on the right.
/// Data and rules are unchanged (Core); only the layout and flow are desktop-specific.
@MainActor
struct MacProfilePage: View {
    let store: GameStore
    var exits = MacProfileExits()
    /// True while a nested state is open, so the root can send Esc here instead of to the title.
    @Binding var isNested: Bool

    private enum Mode: Equatable { case overview, wardrobe(EquipmentSlot), sources }
    @State private var mode: Mode = .overview
    @State private var picked: String?
    @State private var renaming = false
    @State private var nameDraft = ""
    @State private var nameError: String?
    @State private var showsAvatars = false
    /// A rename save is in flight: the editor is frozen so nothing typed meanwhile is thrown away.
    @State private var savingName = false
    /// Bumped each time the editor opens, so a late save only closes the edit that started it.
    @State private var renameSession = 0
    @AccessibilityFocusState private var avatarSheetFocused: Bool
    @State private var avatarPick: String?
    @FocusState private var nameFocused: Bool
    @FocusState private var pageFocused: Bool

    private var player: PlayerState? { store.snapshot?.player }
    private var profile: PlayerProfile { player?.profile ?? PlayerProfile() }
    private var avatar: PlayerAvatar? { profile.avatarID.flatMap(PlayerCatalog.avatar(id:)) }
    private var bonuses: EquipmentBonuses { PlayerCatalog.bonuses(for: profile) }
    private let slots = EquipmentSlot.allCases

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width < 1240 ? 360.0 : 420.0
            let right = geometry.size.width < 1240 ? 320.0 : 364.0
            HStack(alignment: .top, spacing: 16) {
                character.frame(width: side)
                middle.frame(maxWidth: .infinity)
                rightColumn.frame(width: right)
            }
            // The avatar picker is modal: the columns behind it can't be clicked or reached by VoiceOver.
            .disabled(showsAvatars).accessibilityHidden(showsAvatars)
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .overlay { if showsAvatars { avatarSheet } }
        .focusable().focusEffectDisabled().focused($pageFocused)
        .onKeyPress(phases: .down) { key in handleKey(key) }
        .onAppear { pageFocused = true; syncNested() }
        .onChange(of: mode) { _, _ in syncNested() }
        .onChange(of: renaming) { _, _ in syncNested() }
        .onChange(of: showsAvatars) { _, _ in syncNested(); if !showsAvatars { pageFocused = true } }
        .onReceive(NotificationCenter.default.publisher(for: .macProfileEscape)) { _ in back() }
        .onDisappear { isNested = false }
        .accessibilityElement(children: .contain).accessibilityIdentifier("macProfilePage")
    }

    private func syncNested() { isNested = mode != .overview || renaming || showsAvatars }

    // MARK: Left · character

    private var character: some View {
        VStack(alignment: .leading, spacing: 12) {
            if renaming { nameEditor } else { nameRow }
            levelRow
            stage
            meter("player.stamina", symbol: "bolt.fill", value: player?.stamina ?? 0, tint: RoomTheme.mint)
            meter("player.mood", symbol: "face.smiling.fill", value: player?.mood ?? 0, tint: RoomTheme.friendship)
        }.macContentCard69(padding: 20).frame(maxHeight: .infinity)
    }

    private var nameRow: some View {
        HStack(spacing: 10) {
            Text(verbatim: store.playerDisplayName).font(.system(size: 30, weight: .black, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6).accessibilityIdentifier("profilePlayerName")
            Button(action: startRename) {
                Image(systemName: "pencil").font(.system(size: 14, weight: .heavy)).frame(width: 34, height: 34)
                    .background(RoomTheme.track.opacity(0.7), in: Circle())
            }.buttonStyle(.plain).help(GameStrings.text("playerName.edit"))
                .accessibilityLabel(GameStrings.text("playerName.edit")).accessibilityIdentifier("profileRenameButton")
            Spacer(minLength: 6)
            Label(GameStrings.text(statusKey), systemImage: statusSymbol)
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(ExchangePalette.goldInk)
                .padding(.horizontal, 10).padding(.vertical, 5).background(RoomTheme.gold.opacity(0.14), in: Capsule())
                .lineLimit(1).accessibilityIdentifier("profileStatus")
        }
    }

    private var nameEditor: some View {
        let count = nameDraft.count, limit = PlayerNameRules.maximumLength
        let invalid = nameError != nil || count > limit
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack {
                    TextField(GameStrings.text("playerName.placeholder"), text: $nameDraft)
                        .textFieldStyle(.plain).font(.system(size: 22, weight: .heavy, design: .rounded))
                        .focused($nameFocused).onSubmit(saveName).disabled(savingName).accessibilityIdentifier("profileNameField")
                    Text(GameStrings.format("playerName.count", count, limit)).font(.caption.weight(.bold))
                        .foregroundStyle(invalid ? RoomTheme.coralDeep : RoomTheme.secondary).monospacedDigit()
                }.padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(invalid ? RoomTheme.coral : RoomTheme.mint, lineWidth: 2.5))
                Button(action: saveName) {
                    HStack(spacing: 4) { Text(GameStrings.text("mac.profile.save")); Image(systemName: "return") }
                }.buttonStyle(MintButtonStyle()).fixedSize().disabled(store.isBusy || savingName)
                Button(GameStrings.text("mac.profile.cancel")) { renaming = false }.buttonStyle(SoftButtonStyle()).fixedSize()
                    .disabled(savingName)
            }
            Text(nameError ?? GameStrings.format("mac.profile.nameHint", limit)).font(.caption.weight(.bold))
                .foregroundStyle(nameError == nil ? RoomTheme.secondary : RoomTheme.coralDeep)
        }
    }

    private var levelRow: some View {
        let level = player?.level ?? 1, exp = player?.exp ?? 0
        let need = max(1, WorkCatalog.requiredExperience(forLevel: level))
        return HStack(spacing: 10) {
            Text("Lv\(level)").font(.system(size: 13, weight: .black)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4).background(RoomTheme.gold, in: Capsule())
            MacCapsuleProgress(value: Double(exp), total: Double(need), tint: RoomTheme.mint)
            Text(GameStrings.format("mac.profile.exp", exp, need)).font(.system(size: 12.5, weight: .heavy))
                .foregroundStyle(RoomTheme.secondary).monospacedDigit().fixedSize()
        }.accessibilityElement(children: .combine).accessibilityIdentifier("profileLevelSummary")
    }

    private var stage: some View {
        ZStack {
            RadialGradient(colors: [RoomTheme.paper, RoomTheme.cream, RoomTheme.wood.opacity(0.35)],
                           center: .center, startRadius: 20, endRadius: 360)
            Ellipse().fill(RoomTheme.ink.opacity(0.09)).frame(width: 200, height: 26)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 26)
            if let avatar {
                Image(avatar.assetName).resizable().scaledToFit().padding(.top, 44).padding(.bottom, 20)
                    .accessibilityLabel(GameStrings.text(avatar.nameKey))
            } else {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 72, weight: .light))
                    .foregroundStyle(RoomTheme.darkMint.opacity(0.7))
            }
        }
        .overlay(alignment: .topLeading) {
            Label(avatar.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("player.avatar.unselected"), systemImage: "person.fill")
                .font(.system(size: 12, weight: .heavy)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoomTheme.paper.opacity(0.95), in: Capsule()).padding(12)
                .accessibilityIdentifier("profileAvatarName")
        }
        .overlay(alignment: .topTrailing) {
            Button(action: openAvatars) {
                Label(GameStrings.text("mac.profile.changeLook"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12.5, weight: .heavy)).padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoomTheme.paper, in: Capsule())
            }.buttonStyle(.plain).padding(10).accessibilityIdentifier("profileChooseAvatar")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func meter(_ key: String, symbol: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 18)
            Text(GameStrings.text(key)).font(.system(size: 13, weight: .heavy)).frame(width: 44, alignment: .leading)
            MacCapsuleProgress(value: Double(value), tint: tint)
            (Text("\(value)").font(.system(size: 14, weight: .heavy)) + Text(" / 100").font(.system(size: 11, weight: .bold)).foregroundColor(RoomTheme.secondary))
                .monospacedDigit().fixedSize()
        }.accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text(key)).accessibilityValue("\(value)")
    }

    // MARK: Middle · what you wear

    @ViewBuilder private var middle: some View {
        if case .wardrobe(let slot) = mode { wardrobe(slot) } else { outfit }
    }

    private var outfit: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(GameStrings.text("mac.profile.wearing"), systemImage: "tshirt.fill").font(.system(size: 17, weight: .heavy))
                Spacer()
                Text(GameStrings.format("mac.profile.wornCount", profile.equipped.count, slots.count))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            ForEach(slots, id: \.self) { slot in slotRow(slot) }
            Spacer(minLength: 0)
            bonusCard
        }.macContentCard69(padding: 20).frame(maxHeight: .infinity)
    }

    private func slotRow(_ slot: EquipmentSlot) -> some View {
        let item = profile.equipped[slot].flatMap(PlayerCatalog.item(id:))
        return Button { openWardrobe(slot) } label: {
            HStack(spacing: 14) {
                Group {
                    if let item {
                        GameIcon(asset: item.displayAssetName, symbol: Self.symbol(slot), size: 50, tint: RoomTheme.darkMint)
                            .frame(width: 62, height: 62).background(RoomTheme.paleMint.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        Image(systemName: Self.symbol(slot)).font(.system(size: 22)).foregroundStyle(RoomTheme.secondary.opacity(0.6))
                            .frame(width: 62, height: 62)
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(GameStrings.text("gear.slot.\(slot.rawValue)")).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    Text(item.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("mac.profile.notWearing"))
                        .font(.system(size: 16, weight: .black)).lineLimit(1)
                    if let item { bonusPill(item.bonuses) }
                }
                Spacer(minLength: 6)
                Text(GameStrings.text(item == nil ? "mac.profile.pickOne" : "mac.profile.change") + " ›")
                    .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(RoomTheme.track, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(MacProfileRowStyle()).accessibilityIdentifier("profileSlot_\(slot.rawValue)")
            .accessibilityLabel(GameStrings.text("gear.slot.\(slot.rawValue)"))
            .accessibilityValue(item.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
    }

    private func bonusPill(_ value: EquipmentBonuses) -> some View {
        Text(Self.bonusText(value) ?? GameStrings.text("mac.profile.noBonus"))
            .font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            .padding(.horizontal, 9).padding(.vertical, 3).background(RoomTheme.paleMint, in: Capsule())
    }

    private var bonusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(GameStrings.text("mac.profile.bonusTitle"), systemImage: "sparkles").font(.system(size: 14, weight: .heavy))
                Spacer()
                Button { mode = mode == .sources ? .overview : .sources } label: {
                    Text(GameStrings.text("mac.profile.sources") + " ›").font(.system(size: 12.5, weight: .heavy))
                }.buttonStyle(.plain).accessibilityIdentifier("profileBonusSources")
            }.foregroundStyle(RoomTheme.darkMint)
            HStack(spacing: 10) {
                ForEach(Self.stats, id: \.key) { stat in
                    VStack(spacing: 4) {
                        Image(systemName: stat.symbol).foregroundStyle(RoomTheme.darkMint)
                        Text(stat.value(bonuses) > 0 ? "−\(stat.value(bonuses))%" : "—").font(.system(size: 22, weight: .black)).monospacedDigit()
                        Text(GameStrings.text(stat.key)).font(.caption.weight(.heavy))
                        Text(sourceNames(stat)).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
                    }.padding(.vertical, 10).frame(maxWidth: .infinity)
                        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }.padding(14).background(RoomTheme.paleMint.opacity(0.7), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RoomTheme.mint.opacity(0.35), lineWidth: 2))
    }

    private func sourceNames(_ stat: Stat) -> String {
        let names = slots.filter { slot in
            profile.equipped[slot].flatMap(PlayerCatalog.item(id:)).map { stat.value($0.bonuses) > 0 } ?? false
        }.map { GameStrings.text("gear.slot.\($0.rawValue)") }
        return names.isEmpty ? " " : names.joined(separator: " + ")
    }

    // MARK: Middle · wardrobe for one slot

    private func items(for slot: EquipmentSlot) -> [EquipmentItem] {
        let all = PlayerCatalog.equipment.filter { $0.slot == slot }
        return all.filter { profile.ownedEquipmentIDs.contains($0.id) } + all.filter { !profile.ownedEquipmentIDs.contains($0.id) }
    }

    private func wardrobe(_ slot: EquipmentSlot) -> some View {
        let list = items(for: slot)
        let owned = list.filter { profile.ownedEquipmentIDs.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: back) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text(GameStrings.text("mac.profile.wearing"))
                        MacKeyCap(value: "Esc")
                    }.font(.system(size: 13, weight: .heavy)).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoomTheme.track.opacity(0.6), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("profileWardrobeBack")
                Text(GameStrings.text("gear.slot.\(slot.rawValue)")).font(.system(size: 20, weight: .black))
                Spacer()
                Text(GameStrings.format("mac.profile.ownedCount", owned)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            MacSegmented(selection: Binding(get: { slot }, set: { openWardrobe($0) }),
                         options: slots.map { ($0, GameStrings.text("gear.slot.\($0.rawValue)")) })
            ScrollView {
                VStack(spacing: 10) { ForEach(list) { item in wardrobeRow(item) } }.padding(.vertical, 2)
            }
            Button { store.unequipSlot(slot); picked = nil } label: {
                Label(GameStrings.format("mac.profile.takeOff", GameStrings.text("gear.slot.\(slot.rawValue)")), systemImage: "nosign")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy || profile.equipped[slot] == nil)
                .accessibilityIdentifier("profileUnequip")
        }.macContentCard69(padding: 20).frame(maxHeight: .infinity)
    }

    private func wardrobeRow(_ item: EquipmentItem) -> some View {
        let owned = profile.ownedEquipmentIDs.contains(item.id)
        let wearing = profile.equipped[item.slot] == item.id
        let chosen = picked == item.id
        let offer = ShopCatalog.equipmentOffer(itemID: item.id)
        return Button { picked = item.id } label: {
            HStack(spacing: 12) {
                GameIcon(asset: item.displayAssetName, symbol: Self.symbol(item.slot), size: 44, tint: RoomTheme.darkMint)
                    .frame(width: 56, height: 56).background(RoomTheme.paleMint.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(GameStrings.text(item.nameKey)).font(.system(size: 15, weight: .black))
                    bonusPill(item.bonuses)
                }
                Spacer(minLength: 6)
                if wearing {
                    Text(GameStrings.text("mac.profile.wearingTag")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(RoomTheme.paleMint, in: Capsule())
                } else if !owned, let offer {
                    Text(GameStrings.format(offer.unlockLevel > (player?.level ?? 1) ? "mac.profile.lockedAt" : "mac.profile.priceShop",
                                            offer.unlockLevel > (player?.level ?? 1) ? offer.unlockLevel : offer.price) + " ›")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(ExchangePalette.goldInk)
                }
                if chosen && !wearing { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(RoomTheme.mint) }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(chosen ? RoomTheme.mint : RoomTheme.track, lineWidth: chosen ? 3 : 2))
            .opacity(owned ? 1 : 0.6).contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("profileItem_\(item.id)")
            .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Right column

    @ViewBuilder private var rightColumn: some View {
        switch mode {
        case .overview: overviewColumn
        case .wardrobe(let slot): compareColumn(slot)
        case .sources: sourcesColumn
        }
    }

    private var overviewColumn: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label(GameStrings.text("mac.profile.daysTitle"), systemImage: "book.closed.fill").font(.system(size: 16, weight: .heavy))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    dayTile("\(player?.gold ?? 0)", "player.gold", symbol: "dollarsign.circle.fill", tint: RoomTheme.gold)
                    dayTile(GameStrings.format("mac.profile.shiftsValue", player?.completedWorkCount ?? 0), "mac.profile.shifts",
                            symbol: "briefcase.fill", tint: RoomTheme.sky)
                    dayTile(GameStrings.format("mac.profile.catsValue", store.snapshot?.cats.count ?? 0), "mac.profile.cats",
                            symbol: "pawprint.fill", tint: RoomTheme.friendship)
                    dayTile(GameStrings.format("mac.profile.dayValue", dayNumber), "mac.profile.day", symbol: "calendar", tint: RoomTheme.darkMint)
                }
            }.macContentCard69()
            nextLevelCard
            placesCard
            Spacer(minLength: 0)
        }
    }

    private var dayNumber: Int {
        guard let snapshot = store.snapshot else { return 1 }
        return MacTitleMetricsV2.dayNumber(createdAt: snapshot.meta.createdAt, at: max(store.now, snapshot.meta.lastSyncAt))
    }

    private func dayTile(_ value: String, _ key: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 19, weight: .black)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(GameStrings.text(key)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            Spacer(minLength: 0)
        }.padding(12).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
    }

    private var nextLevelCard: some View {
        let level = player?.level ?? 1
        let missing = max(0, WorkCatalog.requiredExperience(forLevel: level) - (player?.exp ?? 0))
        let jobs = WorkCatalog.all.filter { $0.unlockLevel == level + 1 }
        let newGoods = ShopCatalog.equipmentOffers.filter { $0.unlockLevel == level + 1 }.count
            + ShopCatalog.furnitureOffers.filter { $0.unlockLevel == level + 1 }.count
        return VStack(alignment: .leading, spacing: 10) {
            Label(GameStrings.format("mac.profile.next", level + 1), systemImage: "arrow.up.circle.fill")
                .font(.system(size: 16, weight: .heavy)).foregroundStyle(RoomTheme.ink)
            Text(GameStrings.format("mac.profile.needExp", missing)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            if !jobs.isEmpty || newGoods > 0 {
                FlowChips {
                    ForEach(jobs) { job in
                        chip(GameStrings.format("mac.profile.unlockJob", WorkJobPresentation.name(job.id)), symbol: "lock.open.fill", tint: ExchangePalette.goldInk)
                    }
                    if newGoods > 0 { chip(GameStrings.format("mac.profile.shopNew", newGoods), symbol: "storefront.fill", tint: RoomTheme.friendshipDeep) }
                }
            }
            Button(action: exits.work) {
                Label(GameStrings.text("mac.profile.goWork"), systemImage: "briefcase.fill").frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("profileGoWork")
        }.macContentCard69()
    }

    private func chip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4).background(tint.opacity(0.12), in: Capsule())
    }

    private var placesCard: some View {
        let carried = PlayerSupplyKind.allCases.reduce(0) { $0 + (player?.carried($1) ?? 0) }
        let ownedGear = profile.ownedEquipmentIDs.count
        return VStack(alignment: .leading, spacing: 6) {
            Label(GameStrings.text("mac.profile.places"), systemImage: "location.fill").font(.system(size: 16, weight: .heavy)).padding(.bottom, 4)
            placeRow("mac.profile.bag", GameStrings.format("mac.profile.bagStatus", carried), symbol: "backpack.fill", action: exits.bag)
            placeRow("mac.profile.shopGear", GameStrings.format("mac.profile.shopGearStatus", ownedGear, PlayerCatalog.equipment.count),
                     symbol: "storefront.fill", action: exits.shopEquipment)
            placeRow("mac.profile.saves", GameStrings.text(store.hasSaveFailure ? "mac.save.failed" : "mac.save.local"),
                     symbol: "externaldrive.fill", action: exits.saves)
        }.macContentCard69()
    }

    private func placeRow(_ key: String, _ status: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(RoomTheme.darkMint).frame(width: 38, height: 38)
                    .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameStrings.text(key)).font(.system(size: 14, weight: .heavy))
                    Text(status).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(MacProfileRowStyle())
    }

    private func compareColumn(_ slot: EquipmentSlot) -> some View {
        let item = picked.flatMap(PlayerCatalog.item(id:))
        let owned = item.map { profile.ownedEquipmentIDs.contains($0.id) } ?? false
        let wearing = item.map { profile.equipped[slot] == $0.id } ?? false
        var after = profile
        if let item { after.equipped[slot] = item.id; if !after.ownedEquipmentIDs.contains(item.id) { after.ownedEquipmentIDs.append(item.id) } }
        let next = PlayerCatalog.bonuses(for: after)
        return VStack(alignment: .leading, spacing: 12) {
            if let item {
                GameIcon(asset: item.displayAssetName, symbol: Self.symbol(slot), size: 120, tint: RoomTheme.darkMint)
                    .frame(maxWidth: .infinity).frame(height: 170).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 20))
                Text(GameStrings.text(item.nameKey)).font(.system(size: 22, weight: .black))
                Text(GameStrings.text(item.detailKey)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(GameStrings.text("mac.profile.afterTitle")).font(.system(size: 13, weight: .heavy)).padding(.top, 4)
                ForEach(Self.stats, id: \.key) { stat in compareRow(stat, from: stat.value(bonuses), to: stat.value(next)) }
                Text(GameStrings.text(owned ? "mac.profile.saveNote" : "mac.profile.buyNote")).font(.caption).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(GameStrings.text("mac.profile.pickHint")).font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            Spacer(minLength: 0)
            if let item, !owned {
                Button(action: exits.shopEquipment) {
                    Label(GameStrings.text("mac.profile.goShopGear"), systemImage: "storefront.fill").frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("profileItemShop_\(item.id)")
            } else {
                Button(action: equipPicked) {
                    HStack(spacing: 6) {
                        Text(GameStrings.text(wearing ? "mac.profile.alreadyOn" : "mac.profile.equip"))
                        if !wearing { Image(systemName: "return") }
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).disabled(item == nil || wearing || store.isBusy)
                    .accessibilityIdentifier("profileEquip")
            }
            Button(GameStrings.text("mac.profile.keep")) { back() }.buttonStyle(SoftButtonStyle()).frame(maxWidth: .infinity)
        }.macContentCard69().frame(maxHeight: .infinity)
    }

    private func compareRow(_ stat: Stat, from: Int, to: Int) -> some View {
        let tint = to > from ? RoomTheme.darkMint : to < from ? RoomTheme.coralDeep : RoomTheme.ink
        return HStack {
            Text(GameStrings.text(stat.key)).font(.system(size: 13, weight: .heavy))
            Spacer()
            Text(Self.percent(from)).foregroundStyle(RoomTheme.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(RoomTheme.secondary)
            Text(Self.percent(to)).foregroundStyle(tint)
            if to != from { Image(systemName: to > from ? "arrow.up" : "arrow.down").font(.caption.weight(.black)).foregroundStyle(tint) }
        }.font(.system(size: 14, weight: .heavy)).monospacedDigit()
            .padding(.horizontal, 12).padding(.vertical, 9).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sourcesColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(GameStrings.text("mac.profile.sourcesTitle"), systemImage: "sparkles").font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(RoomTheme.darkMint)
                Spacer()
                Button(action: back) { Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).frame(width: 30, height: 30)
                    .background(RoomTheme.track.opacity(0.7), in: Circle()) }.buttonStyle(.plain)
                    .accessibilityLabel(GameStrings.text("common.close")).accessibilityIdentifier("profileSourcesClose")
            }
            HStack {
                Spacer().frame(maxWidth: .infinity)
                ForEach(Self.stats, id: \.key) { stat in
                    Text(GameStrings.text(stat.key)).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                        .frame(width: 58)
                }
            }
            ForEach(slots, id: \.self) { slot in
                let item = profile.equipped[slot].flatMap(PlayerCatalog.item(id:))
                sourceRow(GameStrings.text("gear.slot.\(slot.rawValue)") + " · " + (item.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty")),
                          item?.bonuses ?? EquipmentBonuses(), total: false)
            }
            sourceRow(GameStrings.text("mac.profile.total"), bonuses, total: true)
            if let example { exampleCard(example) }
            Text(GameStrings.text("mac.profile.rule")).font(.caption).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: exits.shopEquipment) {
                Text(GameStrings.text("mac.profile.goShopGear")).frame(maxWidth: .infinity)
            }.buttonStyle(SoftButtonStyle())
        }.macContentCard69().frame(maxHeight: .infinity)
    }

    private func sourceRow(_ title: String, _ value: EquipmentBonuses, total: Bool) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5, weight: .heavy)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(Self.stats, id: \.key) { stat in
                Text(stat.value(value) > 0 ? "−\(stat.value(value))%" : "—").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                    .frame(width: 58)
            }
        }.foregroundStyle(total ? RoomTheme.darkMint : RoomTheme.ink)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(total ? RoomTheme.paleMint : RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
    }

    /// The best job the player can do now, with and without what they wear.
    private var example: WorkQuote? {
        guard let player else { return nil }
        let job = WorkCatalog.all.filter { $0.unlockLevel <= player.level }.max { $0.unlockLevel < $1.unlockLevel }
        return job.flatMap { GameEngine.workQuote(for: player, jobID: $0.id) }
    }

    private func exampleCard(_ quote: WorkQuote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GameStrings.text("mac.profile.exampleTitle")).font(.system(size: 12.5, weight: .heavy))
            Text(GameStrings.format("mac.profile.example", WorkJobPresentation.name(quote.jobID),
                                    WorkJobPresentation.duration(quote.baseDurationSeconds), WorkJobPresentation.duration(quote.durationSeconds),
                                    quote.baseStaminaCost, quote.staminaCost, quote.baseMoodCost, quote.moodCost))
                .font(.caption.weight(.bold)).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(ExchangePalette.goldInk).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(RoomTheme.gold.opacity(0.45), lineWidth: 2))
    }

    // MARK: Avatar picker (P4)

    private var avatarSheet: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().onTapGesture { showsAvatars = false }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(GameStrings.text("mac.profile.changeLook"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 22, weight: .black))
                            .accessibilityAddTraits(.isHeader).accessibilityFocused($avatarSheetFocused)
                        Text(GameStrings.text("mac.profile.lookHint")).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    }
                    Spacer()
                    Button { showsAvatars = false } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
                        .frame(width: 30, height: 30).background(RoomTheme.track.opacity(0.7), in: Circle()) }.buttonStyle(.plain)
                        .accessibilityLabel(GameStrings.text("common.close"))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(PlayerCatalog.avatars) { candidate in avatarCard(candidate) }
                }
                HStack(spacing: 8) {
                    MacKeyCap(value: "←"); MacKeyCap(value: "→"); Text(GameStrings.text("mac.profile.keySelect"))
                    MacKeyCap(value: "↩"); Text(GameStrings.text("mac.profile.keyConfirm"))
                    MacKeyCap(value: "Esc"); Text(GameStrings.text("mac.profile.cancel"))
                    Spacer()
                    Button(GameStrings.text("mac.profile.cancel")) { showsAvatars = false }.buttonStyle(SoftButtonStyle()).fixedSize()
                    Button(GameStrings.text("mac.profile.useLook"), action: useAvatar).buttonStyle(MintButtonStyle()).fixedSize()
                        .disabled(avatarPick == nil || avatarPick == profile.avatarID || store.isBusy)
                        .accessibilityIdentifier("profileUseAvatar")
                }.font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            .padding(24).frame(width: 820)
            .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
            .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("profileAvatarSheet")
        }
    }

    private func avatarCard(_ candidate: PlayerAvatar) -> some View {
        let chosen = avatarPick == candidate.id
        let inUse = profile.avatarID == candidate.id
        return Button { avatarPick = candidate.id } label: {
            VStack(spacing: 6) {
                Image(candidate.assetName).resizable().scaledToFit().frame(height: 150)
                    .frame(maxWidth: .infinity).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
                Text(GameStrings.text(candidate.nameKey)).font(.system(size: 15, weight: .black))
                Text(GameStrings.text(inUse ? "mac.profile.inUse" : "mac.profile.available")).font(.caption.weight(.bold))
                    .foregroundStyle(RoomTheme.secondary)
            }.padding(10).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(chosen ? RoomTheme.mint : .white, lineWidth: chosen ? 3 : 2))
                .overlay(alignment: .topTrailing) {
                    if chosen { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(RoomTheme.mint).padding(10) }
                }
                .contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityIdentifier("avatarSelect_\(candidate.id)")
            .accessibilityLabel(GameStrings.text(candidate.nameKey)).accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Actions

    private func startRename() {
        guard !savingName else { return }
        renameSession += 1
        nameDraft = profile.name ?? ""; nameError = nil; renaming = true
        DispatchQueue.main.async { nameFocused = true }
    }

    private func saveName() {
        guard !store.isBusy, !savingName else { return }
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty name returns to the default greeting, as before.
        let raw: String? = trimmed.isEmpty ? nil : nameDraft
        if let raw, PlayerNameRules.normalized(raw) == nil {
            nameError = GameStrings.text("playerName.invalid"); return
        }
        let session = renameSession
        savingName = true
        Task {
            let saved = await store.renamePlayer(to: raw)
            savingName = false
            guard session == renameSession, renaming else { return }
            if saved { renaming = false; nameError = nil; pageFocused = true }
            else { nameError = GameStrings.text("playerName.saveFailed"); nameFocused = true }
        }
    }

    private func openAvatars() {
        avatarPick = profile.avatarID ?? PlayerCatalog.avatars.first?.id; showsAvatars = true; pageFocused = true
        DispatchQueue.main.async { avatarSheetFocused = true }
    }

    private func useAvatar() {
        guard let avatarPick, avatarPick != profile.avatarID else { showsAvatars = false; return }
        store.selectAvatar(avatarPick); showsAvatars = false
    }

    private func openWardrobe(_ slot: EquipmentSlot) {
        mode = .wardrobe(slot)
        picked = profile.equipped[slot] ?? items(for: slot).first?.id
        pageFocused = true
    }

    private func equipPicked() {
        guard let picked, profile.ownedEquipmentIDs.contains(picked), !store.isBusy else { return }
        store.equipItem(picked)
    }

    /// One step back: avatar picker, rename, then wardrobe or sources, then nothing.
    private func back() {
        if showsAvatars { showsAvatars = false }
        else if renaming { if !savingName { renaming = false } }
        else if mode != .overview { mode = .overview; picked = nil }
        pageFocused = true
    }

    private func handleKey(_ key: KeyPress) -> KeyPress.Result {
        guard !nameFocused else { return .ignored }
        if showsAvatars {
            let ids = PlayerCatalog.avatars.map(\.id)
            let index = avatarPick.flatMap { ids.firstIndex(of: $0) } ?? 0
            switch key.key {
            case .leftArrow: avatarPick = ids[(index + ids.count - 1) % ids.count]; return .handled
            case .rightArrow: avatarPick = ids[(index + 1) % ids.count]; return .handled
            case .return: useAvatar(); return .handled
            case .escape: showsAvatars = false; return .handled
            default: return .ignored
            }
        }
        guard case .wardrobe(let slot) = mode else { return key.key == .escape && mode != .overview ? { back(); return .handled }() : .ignored }
        let list = items(for: slot).map(\.id)
        let index = picked.flatMap { list.firstIndex(of: $0) } ?? 0
        switch key.key {
        case .upArrow: if !list.isEmpty { picked = list[max(0, index - 1)] }; return .handled
        case .downArrow: if !list.isEmpty { picked = list[min(list.count - 1, index + 1)] }; return .handled
        case .leftArrow, .rightArrow:
            let all = slots, at = all.firstIndex(of: slot) ?? 0
            openWardrobe(all[(at + (key.key == .leftArrow ? all.count - 1 : 1)) % all.count]); return .handled
        case .return: equipPicked(); return .handled
        case .escape: back(); return .handled
        default: return .ignored
        }
    }

    // MARK: Helpers

    fileprivate struct Stat { let key: String; let symbol: String; let value: (EquipmentBonuses) -> Int }
    private static let stats: [Stat] = [
        .init(key: "mac.profile.duration", symbol: "timer", value: { $0.durationReductionPercent }),
        .init(key: "mac.profile.stamina", symbol: "bolt.fill", value: { $0.staminaReductionPercent }),
        .init(key: "mac.profile.mood", symbol: "face.smiling.fill", value: { $0.moodReductionPercent })
    ]
    private static func percent(_ value: Int) -> String { value > 0 ? "−\(value)%" : "—" }
    static func bonusText(_ value: EquipmentBonuses) -> String? {
        let parts = stats.compactMap { stat in stat.value(value) > 0 ? GameStrings.text(stat.key) + " −\(stat.value(value))%" : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    static func symbol(_ slot: EquipmentSlot) -> String {
        switch slot { case .head: "hat.cap.fill"; case .body: "tshirt.fill"; case .feet: "shoe.fill"; case .accessory: "key.fill" }
    }
    private var statusValue: String {
        player?.activeWork != nil ? "working" : player?.activeSleep != nil ? "sleeping" : "idle"
    }
    private var statusKey: String { player?.activeNap != nil ? "mac.profile.napping" : "player.status.\(statusValue)" }
    private var statusSymbol: String {
        player?.activeWork != nil ? "briefcase.fill" : player?.activeSleep != nil ? "moon.zzz.fill"
            : player?.activeNap != nil ? "cup.and.saucer.fill" : "sun.max.fill"
    }
}

/// Whole-row hover and press tint for profile rows.
private struct MacProfileRowStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.04 : hovering ? -0.015 : 0)
            .onHover { hovering = $0 }
    }
}

/// Chips that wrap onto more lines when they run out of width.
private struct FlowChips<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { FlowLayout(spacing: 6) { content } }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}

extension Notification.Name { static let macProfileEscape = Notification.Name("MacProfileEscape") }
#endif
