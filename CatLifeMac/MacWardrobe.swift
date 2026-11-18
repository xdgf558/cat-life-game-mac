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
                // Layers sit on the fitted image itself, so the anchors follow the art at any size.
                Image(avatar.assetName).resizable().scaledToFit()
                    .accessibilityLabel(GameStrings.text(avatar.nameKey))
                    .overlay {
                        GeometryReader { geometry in
                            ForEach(Self.order, id: \.self) { slot in
                                if let definition = blueprint(for: slot) { layer(definition, slot: slot, size: geometry.size) }
                            }
                        }.accessibilityHidden(true)
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

    /// Where each avatar's head sits, measured on its art: head centre x, the line a hat brim rests on,
    /// head width, the neck (scarf / necklace) and the wearer's left chest (brooch).
    private struct BodyPoints {
        let headX: CGFloat, brimY: CGFloat, headWidth: CGFloat
        let neck: CGPoint, chest: CGPoint
    }
    private static let bodies: [String: BodyPoints] = [
        "female_forest": .init(headX: 640, brimY: 140, headWidth: 330, neck: CGPoint(x: 640, y: 345), chest: CGPoint(x: 735, y: 440)),
        "female_sunny": .init(headX: 715, brimY: 185, headWidth: 300, neck: CGPoint(x: 750, y: 430), chest: CGPoint(x: 790, y: 500)),
        "female_scholarly": .init(headX: 640, brimY: 175, headWidth: 380, neck: CGPoint(x: 615, y: 395), chest: CGPoint(x: 690, y: 470)),
        "male_sunny": .init(headX: 680, brimY: 175, headWidth: 430, neck: CGPoint(x: 640, y: 430), chest: CGPoint(x: 730, y: 540)),
        // Wider and lower so a new hat covers the bucket hat drawn on this avatar.
        "male_forest": .init(headX: 640, brimY: 240, headWidth: 440, neck: CGPoint(x: 615, y: 380), chest: CGPoint(x: 735, y: 455)),
        "male_scholarly": .init(headX: 640, brimY: 160, headWidth: 370, neck: CGPoint(x: 650, y: 395), chest: CGPoint(x: 720, y: 500))
    ]

    /// The wear image's square frame (side and centre, in avatar canvas pixels). Each piece's width is a
    /// multiple of the head width; `pin` is the point of the wear canvas that lands on the body point
    /// (hats: the brim's bottom edge, drawn at 70% of the wear canvas).
    static func placement(_ blueprintID: String, avatarID: String) -> (width: CGFloat, center: CGPoint)? {
        guard let body = bodies[avatarID] else { return nil }
        let width: CGFloat, pin: CGPoint, point: CGPoint
        switch blueprintID {
        case "gardenHat":
            width = body.headWidth * 1.55; pin = CGPoint(x: 0.5, y: 0.7); point = CGPoint(x: body.headX, y: body.brimY)
        case "rainHat":
            width = body.headWidth * 1.26; pin = CGPoint(x: 0.5, y: 0.7); point = CGPoint(x: body.headX, y: body.brimY - body.headWidth * 0.04)
        case "catEarBand":
            width = body.headWidth * 1.24; pin = CGPoint(x: 0.5, y: 0.7); point = CGPoint(x: body.headX, y: body.brimY + body.headWidth * 0.1)
        case "butterflyBrooch":
            width = body.headWidth * 0.38; pin = CGPoint(x: 0.5, y: 0.5); point = body.chest
        case "woolScarf":
            width = body.headWidth * 0.93; pin = CGPoint(x: 0.5, y: 0.16); point = body.neck
        case "luckyCharm":
            width = body.headWidth * 0.8; pin = CGPoint(x: 0.5, y: 0.1); point = body.neck
        default:
            return nil
        }
        return (width, CGPoint(x: point.x + (0.5 - pin.x) * width, y: point.y + (0.5 - pin.y) * width))
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

/// 3.0 衣柜: its own page under 我的档案. The figure on the left (a try-on is announced under it, never
/// on the clothes), the four appearance slots in the middle, the closet for the chosen slot on the right.
/// Esc ends a try-on first, then goes back to the profile tab.
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
            HStack(alignment: .top, spacing: 16) {
                stageColumn.frame(width: narrow ? 340 : 400)
                slotsColumn.frame(maxWidth: .infinity)
                MacWardrobeCloset(store: store, slot: slot, pick: $pick, selectSlot: { select($0) }, openMagic: openMagic)
                    .frame(width: narrow ? 320 : 360)
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
                RadialGradient(colors: [RoomTheme.paper, RoomTheme.friendshipPaper, RoomTheme.wood.opacity(0.3)],
                               center: .center, startRadius: 20, endRadius: 360)
                Ellipse().fill(RoomTheme.ink.opacity(0.09)).frame(width: 190, height: 24)
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, tryOn == nil ? 22 : 64)
                MacAvatarFigure(avatar: avatar, craft: craft, tryOn: tryOn)
                    .padding(.top, 40).padding(.bottom, tryOn == nil ? 16 : 58).padding(.horizontal, 12)
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
            .clipShape(RoundedRectangle(cornerRadius: 22))
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

    // MARK: Slots

    private var slotsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(GameStrings.text("wardrobe.lookTitle"), systemImage: "hanger").font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(RoomTheme.friendshipDeep)
                Text(GameStrings.text("wardrobe.lookDetail")).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(EquipmentSlot.allCases, id: \.self) { item in slotCard(item) }
            }
            Toggle(isOn: Binding(get: { craft.showsWorkGearWhenEmpty },
                                 set: { value in Task { await store.setShowsWorkGearWhenEmpty(value) } })) {
                Text(GameStrings.text("wardrobe.showGear")).font(.system(size: 12.5, weight: .heavy))
            }
            .toggleStyle(.switch).tint(RoomTheme.mint).disabled(store.isBusy)
            .padding(.horizontal, 14).padding(.vertical, 10).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("wardrobeShowGear")
            Spacer(minLength: 0)
            Button(action: back) {
                HStack(spacing: 10) {
                    Image(systemName: "briefcase.fill").foregroundStyle(RoomTheme.sky)
                    Text(GameStrings.text("wardrobe.gearHint")).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text(GameStrings.text("wardrobe.toProfile") + " ›").font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                }
                .padding(12).background(RoomTheme.sky.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).accessibilityIdentifier("wardrobeToProfile")
        }.macContentCard69(padding: 18).frame(maxHeight: .infinity)
    }

    private func slotCard(_ item: EquipmentSlot) -> some View {
        let worn = craft.appearance[item].flatMap(craft.item(id:))
        let definition = worn?.blueprint
        let chosen = slot == item
        let gear = profile.equipped[item].flatMap(PlayerCatalog.item(id:))
        let fallback = craft.showsWorkGearWhenEmpty
            ? GameStrings.format("wardrobe.followGear", gear.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
            : GameStrings.text("wardrobe.ownClothes")
        return Button { select(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(GameStrings.text("craft.slot.\(item.rawValue)")).font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(chosen ? RoomTheme.friendshipDeep : RoomTheme.secondary)
                    Spacer()
                    if worn != nil {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(RoomTheme.mint)
                    }
                }
                Group {
                    if let definition {
                        MacBlueprintIcon(definition: definition, size: 72)
                    } else {
                        Image(systemName: "nosign").font(.system(size: 24)).foregroundStyle(RoomTheme.secondary.opacity(0.5))
                            .frame(width: 72, height: 72)
                            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    }
                }.frame(maxWidth: .infinity)
                Text(definition.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("wardrobe.none"))
                    .font(.system(size: 15, weight: .black)).lineLimit(1).frame(maxWidth: .infinity)
                Text(worn.map(MacWardrobeCloset.summary) ?? fallback).font(.system(size: 11, weight: .bold))
                    .foregroundStyle(worn == nil ? RoomTheme.secondary : RoomTheme.darkMint)
                    .lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(chosen ? RoomTheme.friendshipPaper : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(chosen ? RoomTheme.friendship : RoomTheme.track, lineWidth: chosen ? 3 : 2))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityLabel(GameStrings.text("craft.slot.\(item.rawValue)"))
        .accessibilityValue(definition.map { GameStrings.text($0.nameKey) } ?? fallback)
        .accessibilityIdentifier("wardrobeSlot_\(item.rawValue)")
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
                            MacBlueprintIcon(definition: definition, size: 36)
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

/// The closet for one appearance slot (W1 right column / W2 try-on).
@MainActor
struct MacWardrobeCloset: View {
    let store: GameStore
    let slot: EquipmentSlot
    @Binding var pick: MacClosetPick
    /// Main-actor isolated, so it is Sendable and can back the segmented control's Binding.
    let selectSlot: @MainActor (EquipmentSlot) -> Void
    let openMagic: () -> Void

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }
    private var workGear: EquipmentItem? { store.snapshot?.player.profile.equipped[slot].flatMap(PlayerCatalog.item(id:)) }

    /// Made pieces first (worn on top), then blueprints held for the slot, then "none".
    static func picks(_ craft: CraftState, slot: EquipmentSlot) -> [MacClosetPick] {
        let made = craft.handmade.filter { $0.blueprint?.product.slot == slot }
            .sorted { (craft.isWorn($0.id) ? 0 : 1, $1.madeAt) < (craft.isWorn($1.id) ? 0 : 1, $0.madeAt) }
        let tryOns = CraftCatalog.craftableBlueprints.filter { $0.product.slot == slot && craft.hasEverHeld($0.id) }
        return made.map { .item($0.id) } + tryOns.map { .tryOn($0.id) } + [.none]
    }

    static func summary(_ item: HandmadeItem) -> String {
        GameStrings.text(item.quality.titleKey) + " · "
            + item.attributes.map { GameStrings.text($0.attribute.titleKey) + " " + MacCraftStyle.valueText($0.attribute, $0.value) }
                .joined(separator: " · ")
    }

    var body: some View {
        let list = Self.picks(craft, slot: slot)
        let madeCount = craft.handmade.filter { $0.blueprint?.product.slot != nil }.count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(GameStrings.text("wardrobe.title"), systemImage: "hanger").font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(RoomTheme.friendshipDeep)
                Spacer()
                Text(GameStrings.format("wardrobe.madeCount", madeCount)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            MacSegmented(selection: Binding(get: { slot }, set: selectSlot),
                         options: EquipmentSlot.allCases.map { ($0, GameStrings.text("craft.slot.\($0.rawValue)")) })
            ScrollView {
                VStack(spacing: 8) { ForEach(list, id: \.self) { row($0) } }.padding(.vertical, 2)
            }
            detail
            buttons
        }.macContentCard69().frame(maxHeight: .infinity).accessibilityIdentifier("wardrobeCloset")
    }

    private func row(_ value: MacClosetPick) -> some View {
        let chosen = pick == value
        return Button { pick = value } label: {
            HStack(spacing: 10) {
                switch value {
                case .item(let id):
                    if let item = craft.item(id: id), let definition = item.blueprint {
                        MacBlueprintIcon(definition: definition, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GameStrings.text(definition.nameKey)).font(.system(size: 14, weight: .heavy))
                            Text(Self.summary(item)).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.darkMint).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        tag(craft.isWorn(id) ? "wardrobe.wearing" : "wardrobe.inCloset", tint: craft.isWorn(id) ? RoomTheme.darkMint : RoomTheme.secondary)
                    }
                case .tryOn(let id):
                    if let definition = CraftCatalog.blueprint(id: id) {
                        MacBlueprintIcon(definition: definition, size: 42).opacity(0.7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GameStrings.text(definition.nameKey)).font(.system(size: 14, weight: .heavy))
                            Text(GameStrings.text("wardrobe.blueprintOnly")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        }
                        Spacer(minLength: 4)
                        tag("wardrobe.tryOn", tint: RoomTheme.friendship)
                    }
                case .none:
                    Image(systemName: "nosign").font(.system(size: 16)).foregroundStyle(RoomTheme.secondary).frame(width: 42, height: 42)
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GameStrings.format("wardrobe.noneFor", GameStrings.text("craft.slot.\(slot.rawValue)"))).font(.system(size: 14, weight: .heavy))
                        Text(fallbackLine).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? RoomTheme.friendshipPaper : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(chosen ? RoomTheme.friendship : RoomTheme.track, lineWidth: chosen ? 3 : 2))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var fallbackLine: String {
        craft.showsWorkGearWhenEmpty
            ? GameStrings.format("wardrobe.followGear", workGear.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
            : GameStrings.text("wardrobe.ownClothes")
    }

    private func tag(_ key: String, tint: Color) -> some View {
        Text(GameStrings.text(key)).font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 4).background(tint.opacity(0.12), in: Capsule())
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
                    Text(GameStrings.text("wardrobe.bonusNote")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
#endif
