#if os(macOS)
import SwiftUI
import CatGameCore

/// What the closet has picked for one slot: a made piece, a blueprint to try on, or nothing.
enum MacClosetPick: Hashable {
    case item(String), tryOn(String), none
}

/// The player's full-body art with handmade clothes layered on (W1 / W2). Hats and accessories have a
/// front-view `wear-<blueprint>` image placed by each avatar's own head / neck / chest points (the six
/// avatars do not share a pose). Tops and shoes, and anything without wear art, show a badge on the
/// body part instead. Layer order follows the art guide: shoes, top, accessory, then hat.
struct MacAvatarFigure: View {
    let avatar: PlayerAvatar?
    let craft: CraftState
    /// A blueprint being tried on, shown in its slot in place of what is worn.
    var tryOn: String? = nil

    private static let order: [EquipmentSlot] = [.feet, .body, .accessory, .head]

    private func blueprint(for slot: EquipmentSlot) -> BlueprintDefinition? {
        if let tryOn, let definition = CraftCatalog.blueprint(id: tryOn), definition.product.slot == slot { return definition }
        return craft.appearance[slot].flatMap(craft.item(id:))?.blueprint
    }

    var body: some View {
        Group {
            if let avatar {
                // The heads touch the top of the art, so a hat's crown rises above it: keep that headroom.
                // Layers sit on the fitted image itself, so the anchors follow the art at any size.
                Color.clear.aspectRatio(1 / (1 + Self.headroom), contentMode: .fit)
                    .overlay(alignment: .bottom) {
                        Image(avatar.assetName).resizable().scaledToFit()
                            .accessibilityLabel(GameStrings.text(avatar.nameKey))
                            .overlay {
                                GeometryReader { geometry in
                                    ForEach(Self.order, id: \.self) { slot in
                                        if let definition = blueprint(for: slot) { layer(definition, slot: slot, size: geometry.size) }
                                    }
                                }.accessibilityHidden(true)
                            }
                    }
            } else {
                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 72, weight: .light))
                    .foregroundStyle(RoomTheme.darkMint.opacity(0.7))
            }
        }
    }

    @ViewBuilder private func layer(_ definition: BlueprintDefinition, slot: EquipmentSlot, size: CGSize) -> some View {
        if let avatar, let place = Self.placement(definition.id, avatarID: avatar.id), UIImage(named: "wear-\(definition.id)") != nil {
            // Points are in the avatar art's 1254-pixel canvas; the fitted image is square.
            let scale = size.width / Self.canvas
            Image("wear-\(definition.id)").resizable().scaledToFit()
                .frame(width: place.width * scale, height: place.width * scale)
                .mask {
                    // A headband's ends fade where they would tuck behind the hair.
                    LinearGradient(stops: [.init(color: .black, location: place.fadeFrom),
                                           .init(color: .black.opacity(place.fadeFrom < 1 ? 0 : 1), location: min(1, place.fadeFrom + 0.12))],
                                   startPoint: .top, endPoint: .bottom)
                }
                .position(x: place.center.x * scale, y: place.center.y * scale)
        } else {
            let anchor = Self.anchor(slot)
            Image(systemName: definition.symbol).font(.system(size: max(14, size.width * 0.07), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: max(30, size.width * 0.14), height: max(30, size.width * 0.14))
                .background(MacCraftStyle.tint(definition.theme), in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: RoomTheme.ink.opacity(0.18), radius: 0, y: 2)
                .position(x: size.width * anchor.x, y: size.height * anchor.y)
        }
    }

    private static let canvas: CGFloat = 1254
    /// Room above the art for hat crowns, as a fraction of its width.
    static let headroom: CGFloat = 0.12

    /// Where each avatar's head sits, measured on its art: head centre x, the top of the hair, the hair's
    /// width a little below the top, the neck (scarf / necklace) and the wearer's left chest (brooch).
    private struct BodyPoints {
        let headX: CGFloat, headTop: CGFloat, headWidth: CGFloat
        let neck: CGPoint, chest: CGPoint
    }
    private static let bodies: [String: BodyPoints] = [
        "female_forest": .init(headX: 628, headTop: 46, headWidth: 340, neck: CGPoint(x: 640, y: 345), chest: CGPoint(x: 735, y: 440)),
        "female_sunny": .init(headX: 640, headTop: 74, headWidth: 330, neck: CGPoint(x: 750, y: 430), chest: CGPoint(x: 790, y: 500)),
        "female_scholarly": .init(headX: 644, headTop: 46, headWidth: 356, neck: CGPoint(x: 615, y: 395), chest: CGPoint(x: 690, y: 470)),
        "male_sunny": .init(headX: 668, headTop: 39, headWidth: 392, neck: CGPoint(x: 640, y: 430), chest: CGPoint(x: 730, y: 540)),
        // Wider and lower so a new hat covers the bucket hat drawn on this avatar.
        "male_forest": .init(headX: 630, headTop: 60, headWidth: 430, neck: CGPoint(x: 615, y: 380), chest: CGPoint(x: 735, y: 455)),
        "male_scholarly": .init(headX: 612, headTop: 49, headWidth: 340, neck: CGPoint(x: 650, y: 395), chest: CGPoint(x: 720, y: 500))
    ]

    /// The wear image's square frame (side and centre, in avatar canvas pixels), checked against all six
    /// avatars. Hats are sized so the crown (not the brim) matches the head, and the brim sits about a
    /// third of the way down it, so the hat is worn rather than perched; `pin` is the point of the wear
    /// canvas that lands on the body point. `fadeFrom` fades a headband's ends from that height down.
    static func placement(_ blueprintID: String, avatarID: String) -> (width: CGFloat, center: CGPoint, fadeFrom: CGFloat)? {
        guard let body = bodies[avatarID] else { return nil }
        let width: CGFloat, pin: CGPoint, point: CGPoint
        var fadeFrom: CGFloat = 1
        func head(_ depth: CGFloat) -> CGPoint { CGPoint(x: body.headX, y: body.headTop + body.headWidth * depth) }
        switch blueprintID {
        case "gardenHat":
            width = body.headWidth * 1.9; pin = CGPoint(x: 0.5, y: 0.66); point = head(0.3)
        case "rainHat":
            width = body.headWidth * 1.5; pin = CGPoint(x: 0.5, y: 0.68); point = head(0.34)
        case "catEarBand":
            width = body.headWidth * 1.6; pin = CGPoint(x: 0.5, y: 0.25); point = head(0); fadeFrom = 0.46
        case "butterflyBrooch":
            width = body.headWidth * 0.38; pin = CGPoint(x: 0.5, y: 0.5); point = body.chest
        case "woolScarf":
            width = body.headWidth * 0.8; pin = CGPoint(x: 0.5, y: 0.16)
            point = CGPoint(x: body.neck.x, y: body.neck.y - body.headWidth * 0.04)
        case "luckyCharm":
            width = body.headWidth * 0.8; pin = CGPoint(x: 0.5, y: 0.1); point = body.neck
        default:
            return nil
        }
        return (width, CGPoint(x: point.x + (0.5 - pin.x) * width, y: point.y + (0.5 - pin.y) * width), fadeFrom)
    }

    /// Badge spots for pieces without wear art: head top, chest, left chest and feet.
    static func anchor(_ slot: EquipmentSlot) -> CGPoint {
        switch slot {
        case .head: CGPoint(x: 0.5, y: 0.1)
        case .body: CGPoint(x: 0.5, y: 0.45)
        case .accessory: CGPoint(x: 0.64, y: 0.36)
        case .feet: CGPoint(x: 0.5, y: 0.92)
        }
    }
}

/// 3.0 衣柜, redrawn in 3.12 as a real wardrobe: an arched mirror with the figure on the left (a try-on is
/// announced under it, never on the clothes), the wooden cabinet in the middle (tops on the hanging rail;
/// hats on the top shelf, accessories in the drawer, shoes on the rack), and the picked piece's card on
/// the right. Esc ends a try-on first, then goes back to the profile tab.
@MainActor
struct MacWardrobePage: View {
    let store: GameStore
    let openMagic: () -> Void
    let back: () -> Void
    @Binding var isNested: Bool
    @State private var slot: EquipmentSlot = .head
    @State private var pick: MacClosetPick = .none
    @FocusState private var focused: Bool

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }
    private var profile: PlayerProfile { store.snapshot?.player.profile ?? PlayerProfile() }
    private var avatar: PlayerAvatar? { profile.avatarID.flatMap(PlayerCatalog.avatar(id:)) }
    private var tryOn: String? {
        guard case .tryOn(let id) = pick else { return nil }
        return id
    }

    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 1240
            HStack(alignment: .top, spacing: 14) {
                stageColumn.frame(width: narrow ? 300 : 360)
                MacWardrobeCabinet(craft: craft, slot: slot, pick: pick, busy: store.isBusy,
                                   choose: { next, value in slot = next; pick = value; focused = true },
                                   setShowsGear: { value in Task { await store.setShowsWorkGearWhenEmpty(value) } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MacWardrobeCloset(store: store, slot: slot, pick: $pick, openMagic: openMagic, back: back)
                    .frame(width: narrow ? 300 : 340)
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear { select(.head); focused = true; isNested = true }
        .onDisappear { isNested = false }
        .onReceive(NotificationCenter.default.publisher(for: .macProfileEscape)) { _ in escape() }
        .accessibilityElement(children: .contain).accessibilityIdentifier("macWardrobePage")
    }

    // MARK: Figure

    private var stageColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(GameStrings.text("wardrobe.now"), systemImage: "person.fill").font(.system(size: 16, weight: .heavy))
            ZStack {
                // The mirror: soft glass, one diagonal sheen, the figure standing on a small rug.
                LinearGradient(colors: [Color(red: 0.93, green: 0.96, blue: 0.97), RoomTheme.paper, RoomTheme.friendshipPaper],
                               startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.45), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70).rotationEffect(.degrees(24)).offset(x: -70, y: -40).allowsHitTesting(false)
                Ellipse().fill(MacWardrobePalette.rug.opacity(0.35)).frame(width: 200, height: 26)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, tryOn == nil ? 18 : 60)
                MacAvatarFigure(avatar: avatar, craft: craft, tryOn: tryOn)
                    .padding(.top, 24).padding(.bottom, tryOn == nil ? 12 : 54).padding(.horizontal, 18)
            }
            .overlay(alignment: .bottom) {
                if let id = tryOn, let definition = CraftCatalog.blueprint(id: id) {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                        Text(GameStrings.format("wardrobe.tryOnBanner", GameStrings.text(definition.nameKey))).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        MacKeyCap(value: "esc")
                    }
                    .font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoomTheme.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 1.5))
                    .padding(12)
                    .accessibilityIdentifier("wardrobeTryOnBadge")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(MacWardrobePalette.mirror)
            .overlay(MacWardrobePalette.mirror.strokeBorder(MacWardrobePalette.brass.opacity(0.8), lineWidth: 2).padding(7))
            .overlay(MacWardrobePalette.mirror.strokeBorder(MacWardrobePalette.frame, lineWidth: 8))
            .shadow(color: MacWardrobePalette.frameDark.opacity(0.25), radius: 0, y: 4)
            handmadeBonuses
        }.macContentCard69(padding: 18).frame(maxHeight: .infinity)
    }

    private var handmadeBonuses: some View {
        let active = HandmadeAttribute.allCases.filter { craft.bonus($0) > 0 }
        return VStack(alignment: .leading, spacing: 6) {
            Text(GameStrings.text("wardrobe.handmadeBonus")).font(.system(size: 12, weight: .heavy))
            if active.isEmpty {
                Text(GameStrings.text("wardrobe.noHandmadeBonus")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(active, id: \.self) { attribute in
                        Label(GameStrings.text(attribute.titleKey) + " " + MacCraftStyle.valueText(attribute, craft.bonus(attribute)),
                              systemImage: MacCraftStyle.symbol(attribute))
                            .font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.friendshipPaper.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func select(_ next: EquipmentSlot) {
        slot = next
        pick = craft.appearance[next].map { .item($0) } ?? MacWardrobeCloset.picks(craft, slot: next).first ?? .none
        focused = true
    }

    /// Esc: a try-on goes back to what is worn; otherwise back to the profile tab.
    private func escape() {
        if tryOn != nil { pick = craft.appearance[slot].map { .item($0) } ?? .none } else { back() }
        focused = true
    }

    /// Arrows pick and switch slots, ↩ wears, ⌫ takes off.
    private func handleKey(_ key: KeyPress) -> KeyPress.Result {
        let list = MacWardrobeCloset.picks(craft, slot: slot)
        let index = list.firstIndex(of: pick) ?? 0
        switch key.key {
        case .upArrow: if !list.isEmpty { pick = list[max(0, index - 1)] }; return .handled
        case .downArrow: if !list.isEmpty { pick = list[min(list.count - 1, index + 1)] }; return .handled
        case .leftArrow, .rightArrow:
            let all = EquipmentSlot.allCases, at = all.firstIndex(of: slot) ?? 0
            select(all[(at + (key.key == .leftArrow ? all.count - 1 : 1)) % all.count]); return .handled
        case .return:
            if case .item(let id) = pick, craft.appearance[slot] != id, !store.isBusy {
                Task { await store.setAppearance(slot: slot, itemID: id) }
            }
            return .handled
        case .delete, .deleteForward:
            if craft.appearance[slot] != nil, !store.isBusy { Task { await store.setAppearance(slot: slot, itemID: nil) } }
            return .handled
        case .escape: escape(); return .handled
        default: return .ignored
        }
    }
}

/// The wardrobe's front door on the profile page: what is worn in each slot, and a way in.
struct MacWardrobeEntry: View {
    let craft: CraftState
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(GameStrings.text("wardrobe.title"), systemImage: "hanger").font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(RoomTheme.friendshipDeep)
                    Text(GameStrings.text("wardrobe.entryDetail")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                HStack(spacing: 6) {
                    ForEach(EquipmentSlot.allCases, id: \.self) { slot in
                        if let definition = craft.appearance[slot].flatMap(craft.item(id:))?.blueprint {
                            MacBlueprintIcon(definition: definition, size: 36, asItem: true)
                        } else {
                            Image(systemName: "nosign").font(.system(size: 12)).foregroundStyle(RoomTheme.secondary.opacity(0.5))
                                .frame(width: 36, height: 36)
                                .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        }
                    }
                }
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.friendshipPaper.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).accessibilityIdentifier("profileOpenWardrobe")
    }
}

/// The picked piece's card (the right column): what it is, its durability and what to do with it.
@MainActor
struct MacWardrobeCloset: View {
    let store: GameStore
    let slot: EquipmentSlot
    @Binding var pick: MacClosetPick
    let openMagic: () -> Void
    /// Back to the profile tab, where the work gear is changed.
    let back: () -> Void
    /// 3.1: the piece being mended (D2), fixed when the sheet opens.
    @State private var repairing: HandmadeItem?

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }
    private var workGear: EquipmentItem? { store.snapshot?.player.profile.equipped[slot].flatMap(PlayerCatalog.item(id:)) }

    /// Made pieces first (about to break, then worn, on top), then blueprints held for the slot, then "none".
    static func picks(_ craft: CraftState, slot: EquipmentSlot) -> [MacClosetPick] {
        func rank(_ item: HandmadeItem) -> Int { item.stage == .fragile ? 0 : craft.isWorn(item.id) ? 1 : 2 }
        let made = craft.handmade.filter { $0.blueprint?.product.slot == slot }
            .sorted { (rank($0), $1.madeAt) < (rank($1), $0.madeAt) }
        let tryOns = CraftCatalog.craftableBlueprints.filter { $0.product.slot == slot && craft.hasEverHeld($0.id) }
        return made.map { .item($0.id) } + tryOns.map { .tryOn($0.id) } + [.none]
    }

    static func summary(_ item: HandmadeItem) -> String {
        GameStrings.text(item.quality.titleKey) + " · "
            + item.attributes.map { GameStrings.text($0.attribute.titleKey) + " " + MacCraftStyle.valueText($0.attribute, $0.value) }
                .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(GameStrings.text("craft.slot.\(slot.rawValue)"), systemImage: MacWardrobePalette.symbol(slot))
                    .font(.system(size: 16, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                Spacer()
                if let worn = craft.appearance[slot].flatMap(craft.item(id:))?.blueprint {
                    Text(GameStrings.format("wardrobe.wearingNow", GameStrings.text(worn.nameKey)))
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            hero
            detail
            Spacer(minLength: 0)
            buttons
            Button(action: back) {
                HStack(spacing: 8) {
                    Image(systemName: "briefcase.fill").foregroundStyle(RoomTheme.sky)
                    Text(GameStrings.text("wardrobe.gearHint")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text(GameStrings.text("wardrobe.toProfile") + " ›").font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                }
                .padding(10).background(RoomTheme.sky.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("wardrobeToProfile")
        }.macContentCard69().frame(maxHeight: .infinity).accessibilityIdentifier("wardrobeCloset")
        .sheet(item: $repairing) { item in
            MacRepairSheet(store: store, item: item, skillLevel: craft.skillLevel.level) { repairing = nil }
        }
    }

    /// The picked piece large, like a label card pinned to the wardrobe door.
    @ViewBuilder private var hero: some View {
        let definition: BlueprintDefinition? = {
            switch pick {
            case .item(let id): return craft.item(id: id)?.blueprint
            case .tryOn(let id): return CraftCatalog.blueprint(id: id)
            case .none: return nil
            }
        }()
        VStack(spacing: 6) {
            if let definition {
                MacBlueprintIcon(definition: definition, size: 96, asItem: true)
                    .opacity({ if case .tryOn = pick { return 0.75 } else { return 1 } }())
            } else {
                Image(systemName: "nosign").font(.system(size: 30)).foregroundStyle(RoomTheme.secondary.opacity(0.5))
                    .frame(width: 96, height: 96)
                    .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            }
            if case .none = pick {
                Text(GameStrings.format("wardrobe.noneFor", GameStrings.text("craft.slot.\(slot.rawValue)"))).font(.system(size: 15, weight: .black))
                Text(fallbackLine).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity)
        .background(MacWardrobePalette.inner.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MacWardrobePalette.shelf.opacity(0.5), lineWidth: 1.5))
    }

    private var fallbackLine: String {
        craft.showsWorkGearWhenEmpty
            ? GameStrings.format("wardrobe.followGear", workGear.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
            : GameStrings.text("wardrobe.ownClothes")
    }

    @ViewBuilder private var detail: some View {
        switch pick {
        case .item(let id):
            if let item = craft.item(id: id), let definition = item.blueprint {
                VStack(alignment: .leading, spacing: 6) {
                    Text(GameStrings.text(definition.nameKey)).font(.system(size: 15, weight: .black))
                    Text(GameStrings.format("wardrobe.madeOn", item.madeAt.formatted(.dateTime.month().day())))
                        .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    MacBlueprintTags(definition: definition)
                    MacDurabilityBar(durability: item.durability, cap: item.durabilityCap)
                    Text(GameStrings.text(craft.isWorn(item.id) ? "gear.wearsWhenWorn" : "gear.restsInCloset"))
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    if item.repairTarget(skillLevel: craft.skillLevel.level).durability > item.durability,
                       item.repairs < CraftCatalog.maximumRepairs {
                        Button { repairing = item } label: {
                            Label(GameStrings.text("gear.repair.button"), systemImage: "wrench.and.screwdriver.fill")
                                .font(.system(size: 12, weight: .heavy)).frame(maxWidth: .infinity)
                        }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy).accessibilityIdentifier("gearRepair")
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
            }
        case .tryOn(let id):
            if let definition = CraftCatalog.blueprint(id: id) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(GameStrings.format("wardrobe.tryOnTitle", GameStrings.text(definition.nameKey))).font(.system(size: 14, weight: .black))
                    MacCostRow(definition: definition, craft: craft)
                    Text(GameStrings.text("wardrobe.tryOnNote")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 14))
            }
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder private var buttons: some View {
        let worn = craft.appearance[slot]
        HStack(spacing: 10) {
            Button { Task { await store.setAppearance(slot: slot, itemID: nil) } } label: {
                HStack(spacing: 6) { Text(GameStrings.text("wardrobe.takeOff")); MacKeyCap(value: "⌫") }
            }.buttonStyle(SoftButtonStyle()).fixedSize(horizontal: true, vertical: false)
                .disabled(worn == nil || store.isBusy).accessibilityIdentifier("wardrobeTakeOff")
            switch pick {
            case .item(let id):
                Button { Task { await store.setAppearance(slot: slot, itemID: id) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: worn == id ? "checkmark" : "hanger")
                        Text(GameStrings.text(worn == id ? "wardrobe.alreadyOn" : "wardrobe.wear"))
                        if worn != id { MacKeyCap(value: "↩") }
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(worn == id || store.isBusy).accessibilityIdentifier("wardrobeWear")
            case .tryOn:
                Button(action: openMagic) {
                    Label(GameStrings.text("wardrobe.goCraft"), systemImage: "hammer.fill").frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("wardrobeGoCraft")
            case .none:
                Button { Task { await store.setAppearance(slot: slot, itemID: nil) } } label: {
                    Text(GameStrings.text(worn == nil ? "wardrobe.alreadyOn" : "wardrobe.wearNone")).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).disabled(worn == nil || store.isBusy)
            }
        }
        let isTryOn: Bool = { if case .tryOn = pick { return true } else { return false } }()
        let nothingMade = !Self.picks(craft, slot: slot).contains { if case .item = $0 { return true } else { return false } }
        if !isTryOn && nothingMade {
            Button(action: openMagic) {
                HStack {
                    Image(systemName: "scroll.fill").foregroundStyle(ExchangePalette.goldInk)
                    Text(GameStrings.text("wardrobe.noneMade")).font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text(GameStrings.text("wardrobe.goMagic") + " ›").font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                }.padding(10).background(RoomTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }
    }
}

// MARK: 3.12 wardrobe cabinet

/// Wood, brass and the arched mirror shared by the wardrobe page.
enum MacWardrobePalette {
    static let frame = Color(red: 0.64, green: 0.44, blue: 0.29)
    static let frameDark = Color(red: 0.45, green: 0.29, blue: 0.18)
    static let inner = Color(red: 0.96, green: 0.90, blue: 0.81)
    static let back = Color(red: 0.91, green: 0.82, blue: 0.70)
    static let shelf = Color(red: 0.78, green: 0.58, blue: 0.40)
    static let brass = Color(red: 0.86, green: 0.68, blue: 0.32)
    static let rug = Color(red: 0.86, green: 0.55, blue: 0.55)
    static let mirror = UnevenRoundedRectangle(topLeadingRadius: 150, bottomLeadingRadius: 22,
                                               bottomTrailingRadius: 22, topTrailingRadius: 150, style: .continuous)
    static func symbol(_ slot: EquipmentSlot) -> String {
        switch slot {
        case .head: "hat.widebrim.fill"
        case .body: "tshirt.fill"
        case .accessory: "sparkles"
        case .feet: "shoe.2.fill"
        }
    }
}

/// The wardrobe itself: a wooden cabinet with its doors open. Tops hang on the rail on the left; hats on
/// the top shelf, accessories in the drawer and shoes on the rack on the right. Each piece (made, a
/// blueprint to try on, or "none") is a tile; the worn one has a tick, a fragile one a red dot.
@MainActor
struct MacWardrobeCabinet: View {
    let craft: CraftState
    let slot: EquipmentSlot
    let pick: MacClosetPick
    let busy: Bool
    let choose: (EquipmentSlot, MacClosetPick) -> Void
    let setShowsGear: (Bool) -> Void

    var body: some View {
        let made = craft.handmade.filter { $0.blueprint?.product.slot != nil }.count
        VStack(spacing: 0) {
            // The crown moulding with the brass name plate.
            HStack(spacing: 8) {
                Label(GameStrings.text("wardrobe.title"), systemImage: "cabinet.fill").font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(MacWardrobePalette.frameDark)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(MacWardrobePalette.brass.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(MacWardrobePalette.brass, lineWidth: 1.5))
                Spacer()
                Text(GameStrings.format("wardrobe.madeCount", made)).font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(MacWardrobePalette.inner)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            HStack(alignment: .top, spacing: 10) {
                compartment(.body, hanging: true).frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 10) {
                    compartment(.head, hanging: false)
                    compartment(.accessory, hanging: false)
                    compartment(.feet, hanging: false)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(10)
            .background(MacWardrobePalette.back, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 12)
            // The bottom drawer: what an empty slot shows.
            Toggle(isOn: Binding(get: { craft.showsWorkGearWhenEmpty }, set: setShowsGear)) {
                Text(GameStrings.text("wardrobe.showGear")).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.ink)
            }
            .toggleStyle(.switch).controlSize(.small).tint(RoomTheme.mint).disabled(busy)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(MacWardrobePalette.inner, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .top) { Capsule().fill(MacWardrobePalette.brass).frame(width: 46, height: 5).offset(y: -2) }
            .padding(12)
            .accessibilityIdentifier("wardrobeShowGear")
        }
        .background(
            LinearGradient(colors: [MacWardrobePalette.frame, MacWardrobePalette.frameDark], startPoint: .top, endPoint: .bottom),
            in: UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 14, bottomTrailingRadius: 14, topTrailingRadius: 30,
                                       style: .continuous))
        .shadow(color: MacWardrobePalette.frameDark.opacity(0.3), radius: 0, y: 6)
        .accessibilityElement(children: .contain).accessibilityIdentifier("wardrobeCabinet")
    }

    /// One part of the cabinet. The rail compartment draws a rod and hooks; shelves draw a board below.
    private func compartment(_ part: EquipmentSlot, hanging: Bool) -> some View {
        let picks = MacWardrobeCloset.picks(craft, slot: part)
        let chosen = part == slot
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: MacWardrobePalette.symbol(part)).font(.system(size: 10, weight: .bold))
                Text(GameStrings.text("craft.slot.\(part.rawValue)")).font(.system(size: 11.5, weight: .heavy))
            }
            .foregroundStyle(MacWardrobePalette.frameDark)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(MacWardrobePalette.brass.opacity(chosen ? 0.55 : 0.3), in: Capsule())
            .accessibilityAddTraits(.isHeader)
            if hanging {
                Capsule().fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 6).padding(.horizontal, 2)
            }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: hanging ? 84 : 70), spacing: 8)], alignment: .leading, spacing: hanging ? 12 : 8) {
                    ForEach(picks, id: \.self) { value in tile(value, part: part, hanging: hanging) }
                }.padding(.vertical, 2)
            }
            if !hanging {
                // The shelf board.
                RoundedRectangle(cornerRadius: 2).fill(MacWardrobePalette.shelf).frame(height: 5)
                    .shadow(color: MacWardrobePalette.frameDark.opacity(0.25), radius: 0, y: 2)
            }
        }
        .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MacWardrobePalette.inner, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(chosen ? RoomTheme.friendship : MacWardrobePalette.shelf.opacity(0.45),
                                                                 lineWidth: chosen ? 2.5 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GameStrings.text("craft.slot.\(part.rawValue)"))
        .accessibilityIdentifier("wardrobeSlot_\(part.rawValue)")
    }

    private func tile(_ value: MacClosetPick, part: EquipmentSlot, hanging: Bool) -> some View {
        let picked = part == slot && pick == value
        let item: HandmadeItem? = { if case .item(let id) = value { return craft.item(id: id) } else { return nil } }()
        let definition: BlueprintDefinition? = {
            switch value {
            case .item: return item?.blueprint
            case .tryOn(let id): return CraftCatalog.blueprint(id: id)
            case .none: return nil
            }
        }()
        let worn = item.map { craft.isWorn($0.id) } ?? (value == .none && craft.appearance[part] == nil)
        let isTryOn: Bool = { if case .tryOn = value { return true } else { return false } }()
        let name = definition.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("wardrobe.tileNone")
        return Button { choose(part, value) } label: {
            VStack(spacing: 4) {
                if hanging {
                    Image(systemName: "hanger").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.5))
                        .frame(height: 12).padding(.bottom, -2)
                }
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let definition {
                            MacBlueprintIcon(definition: definition, size: 52, asItem: true).opacity(isTryOn ? 0.55 : 1)
                        } else {
                            Image(systemName: "nosign").font(.system(size: 18)).foregroundStyle(RoomTheme.secondary.opacity(0.55))
                                .frame(width: 52, height: 52)
                                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        }
                    }
                    if worn && value != .none {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(.white, RoomTheme.mint).offset(x: 5, y: -5)
                    } else if item?.stage == .fragile {
                        Circle().fill(RoomTheme.coralDeep).frame(width: 11, height: 11).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 3, y: -3)
                    }
                }
                Text(name).font(.system(size: 10.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(isTryOn ? RoomTheme.secondary : RoomTheme.ink)
                if let item {
                    MacDurabilityBar(durability: item.durability, cap: item.durabilityCap, compact: true, barOnly: true)
                } else if isTryOn {
                    Text(GameStrings.text("wardrobe.tryOn")).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(RoomTheme.friendship)
                }
            }
            .padding(6).frame(maxWidth: .infinity)
            .background(picked ? RoomTheme.friendshipPaper : RoomTheme.paper.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(picked ? RoomTheme.friendship : item?.stage == .fragile ? RoomTheme.coral : .clear,
                                                                     lineWidth: picked ? 2.5 : 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityValue(worn ? GameStrings.text("wardrobe.wearing") : isTryOn ? GameStrings.text("wardrobe.tryOn") : "")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: 3.1 durability

/// A handmade piece's days of wear: a bar coloured by stage, with "N / M 天 · 阶段".
struct MacDurabilityBar: View {
    let durability: Int
    let cap: Int
    var compact = false
    /// Tiles have no room for the words; the bar alone (VoiceOver still reads them).
    var barOnly = false
    private var stage: DurabilityStage { .of(durability: durability, cap: cap) }

    static func tint(_ stage: DurabilityStage) -> Color {
        switch stage {
        case .fresh: RoomTheme.darkMint
        case .handy: RoomTheme.mint
        case .worn: RoomTheme.gold
        case .fragile: RoomTheme.coralDeep
        }
    }

    var body: some View {
        let fraction = cap > 0 ? min(1, max(0, CGFloat(durability) / CGFloat(cap))) : 0
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            if !barOnly {
            HStack(spacing: 6) {
                Text(GameStrings.text(stage.titleKey)).font(.system(size: compact ? 10.5 : 12, weight: .heavy))
                    .foregroundStyle(Self.tint(stage))
                Spacer(minLength: 4)
                Text(GameStrings.format("gear.days", durability, cap)).font(.system(size: compact ? 10.5 : 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(RoomTheme.secondary)
            }.lineLimit(1).minimumScaleFactor(0.8)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(RoomTheme.track)
                    Capsule().fill(Self.tint(stage)).frame(width: max(compact ? 4 : 6, geometry.size.width * fraction))
                }
            }.frame(height: compact ? 5 : 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text("gear.durability"))
        .accessibilityValue(GameStrings.text(stage.titleKey) + ", " + GameStrings.format("gear.days", durability, cap))
    }
}

/// D2: mend one piece. Before / after are taken when the sheet opens, so they don't jump while it closes.
@MainActor
struct MacRepairSheet: View {
    let store: GameStore
    let item: HandmadeItem
    let skillLevel: Int
    let close: () -> Void
    @State private var saving = false
    @State private var failed = false
    /// Saved: the sheet is closing, so the spent materials must not flash "not enough".
    @State private var completed = false

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }

    var body: some View {
        let definition = item.blueprint
        let target = item.repairTarget(skillLevel: skillLevel)
        let costs = definition.map(CraftCatalog.repairCosts(for:)) ?? []
        let enough = completed || costs.allSatisfy { craft.count(of: $0.material) >= $0.count }
        let needed = target.durability > item.durability && item.repairs < CraftCatalog.maximumRepairs
        VStack(spacing: 14) {
            Text(GameStrings.text("gear.repair.kicker")).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint).tracking(1.2)
            if let definition {
                MacBlueprintIcon(definition: definition, size: 72, asItem: true)
                Text(GameStrings.format("gear.repair.title", GameStrings.text(definition.nameKey))).font(.system(size: 20, weight: .heavy))
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(GameStrings.text("gear.repair.now")).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                MacDurabilityBar(durability: item.durability, cap: item.durabilityCap)
                Text(GameStrings.text("gear.repair.after")).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                MacDurabilityBar(durability: target.durability, cap: target.cap)
            }
            .padding(14).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
            MacBeforeAfterRow(title: GameStrings.text("gear.repair.cap"), before: item.durabilityCap, after: target.cap)
            VStack(alignment: .leading, spacing: 6) {
                Text(GameStrings.text("gear.repair.costs")).font(.system(size: 12, weight: .heavy))
                HStack(spacing: 6) {
                    ForEach(costs) { cost in
                        let have = craft.count(of: cost.material), ok = completed || have >= cost.count
                        HStack(spacing: 4) {
                            MacMaterialArt(material: cost.material, size: 18)
                            Text(GameStrings.text(cost.material.titleKey)).font(.system(size: 12, weight: .heavy))
                            Text(verbatim: "\(have)/\(cost.count)").font(.system(size: 12, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(ok ? RoomTheme.darkMint : RoomTheme.coralDeep)
                        .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity)
                        .background((ok ? RoomTheme.paleMint : RoomTheme.paleCoral).opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(GameStrings.text(cost.material.titleKey) + " \(have) / \(cost.count)")
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(GameStrings.text(skillLevel >= CraftCatalog.repairMasterLevel ? "gear.repair.noteMaster" : "gear.repair.note"))
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if failed || (!saving && (!enough || !needed)) {
                Label(GameStrings.text(failed ? "gear.repair.failed" : !needed ? "gear.error.repairNotNeeded" : "gear.error.repairMaterials"),
                      systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.coralDeep)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoomTheme.paleCoral.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("gearRepairBlocked")
            }
            HStack(spacing: 10) {
                Button(action: close) {
                    HStack(spacing: 8) { Text(GameStrings.text("common.cancel")); MacKeyCap(value: "esc") }
                }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction).disabled(saving)
                Button(action: repair) {
                    HStack(spacing: 8) {
                        if saving { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "wrench.and.screwdriver.fill") }
                        Text(GameStrings.text(saving ? "common.saving" : "gear.repair.confirm"))
                        if !saving { MacKeyCap(value: "↩") }
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(saving || !enough || !needed || store.isBusy).accessibilityIdentifier("gearRepairConfirm")
            }
        }
        .padding(22).frame(width: 440)
        .background(RoomTheme.paper).foregroundStyle(RoomTheme.ink).fontDesign(.rounded)
        .interactiveDismissDisabled(saving)
        .accessibilityElement(children: .contain).accessibilityIdentifier("gearRepairSheet")
    }

    private func repair() {
        guard !saving else { return }
        saving = true; failed = false
        Task {
            let done = await store.repairHandmade(item.id)
            if done { completed = true }
            saving = false
            if done { close() } else { failed = true }
        }
    }
}

/// D3: the morning goodbye card for a piece that wore out. The piece is already gone from the save.
struct MacHandmadeFarewellCard: View {
    let farewell: HandmadeFarewell
    /// The blueprint's uses now (it may have changed since that morning).
    let usesLeft: Int
    let busy: Bool
    let makeAnother: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let definition = CraftCatalog.blueprint(id: farewell.blueprintID)
        let name = definition.map { GameStrings.text($0.nameKey) } ?? ""
        ZStack {
            RoomTheme.ink.opacity(0.35).ignoresSafeArea().accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(GameStrings.text("gear.farewell.kicker")).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.secondary).tracking(1.2)
                if let definition {
                    MacBlueprintIcon(definition: definition, size: 84, asItem: true).saturation(0.2).opacity(0.75)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "bandage.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(RoomTheme.coral)
                                .padding(6).background(.white, in: Circle()).offset(x: 6, y: 6)
                        }
                }
                Text(GameStrings.format("gear.farewell.title", name)).font(.system(size: 21, weight: .heavy))
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
                Text(farewell.repairs > 0 ? GameStrings.format("gear.farewell.daysRepaired", farewell.daysWorn, farewell.repairs)
                                          : GameStrings.format("gear.farewell.days", farewell.daysWorn))
                    .font(.system(size: 12.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 6) {
                    Text(GameStrings.text("gear.farewell.lost")).font(.system(size: 12, weight: .heavy))
                    HStack(spacing: 6) {
                        Text(GameStrings.text(farewell.quality.titleKey)).font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(MacCraftStyle.tint(farewell.quality).opacity(0.6), in: Capsule())
                        ForEach(farewell.attributes, id: \.attribute) { roll in
                            Text(GameStrings.text(roll.attribute.titleKey) + " " + MacCraftStyle.valueText(roll.attribute, roll.value))
                                .font(.system(size: 11.5, weight: .bold)).strikethrough().foregroundStyle(RoomTheme.secondary).lineLimit(1)
                        }
                    }
                    Text(GameStrings.text("gear.farewell.look")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
                if let material = farewell.refunded {
                    HStack(spacing: 8) {
                        MacMaterialArt(material: material, size: 22)
                        Text(GameStrings.format("gear.farewell.refund", GameStrings.text(material.titleKey))).font(.system(size: 12.5, weight: .heavy))
                        Spacer()
                        Text(verbatim: "+1").font(.system(size: 15, weight: .black)).foregroundStyle(RoomTheme.darkMint)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9).background(RoomTheme.paleMint.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(usesLeft > 0 ? GameStrings.format("gear.farewell.uses", usesLeft) : GameStrings.text("gear.farewell.usedUp"),
                          systemImage: "scroll.fill").font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(usesLeft > 0 ? RoomTheme.darkMint : RoomTheme.coralDeep)
                    if usesLeft > 0, let definition {
                        Text(GameStrings.text("gear.farewell.needs")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        HStack(spacing: 6) {
                            ForEach(definition.costs) { cost in
                                HStack(spacing: 3) {
                                    MacMaterialArt(material: cost.material, size: 16)
                                    Text(verbatim: "×\(cost.count)").font(.system(size: 11.5, weight: .heavy)).monospacedDigit()
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(GameStrings.text(cost.material.titleKey) + " \(cost.count)")
                            }
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background((usesLeft > 0 ? RoomTheme.paleMint : RoomTheme.paleCoral).opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                HStack(spacing: 10) {
                    Button(action: dismiss) {
                        HStack(spacing: 8) { Text(GameStrings.text("craft.grants.ok")); MacKeyCap(value: "esc") }
                    }.buttonStyle(SoftButtonStyle()).disabled(busy).accessibilityIdentifier("gearFarewellOK")
                    Button(action: makeAnother) {
                        HStack(spacing: 8) {
                            Image(systemName: usesLeft > 0 ? "hammer.fill" : "magnifyingglass")
                            Text(GameStrings.text(usesLeft > 0 ? "gear.farewell.makeAnother" : "gear.farewell.findBlueprint"))
                            MacKeyCap(value: "↩")
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).disabled(busy).accessibilityIdentifier("gearFarewellMake")
                }
            }
            .padding(22).frame(width: 440).modifier(MacMagicCardChrome())
            .foregroundStyle(RoomTheme.ink).fontDesign(.rounded)
            .accessibilityIdentifier("gearFarewellCard")
        }
    }
}
#endif
