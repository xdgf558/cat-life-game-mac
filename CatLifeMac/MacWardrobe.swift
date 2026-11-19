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
                            .background {
                                // A hat's back half (the brim behind the head) goes behind the avatar.
                                GeometryReader { geometry in
                                    if let definition = blueprint(for: .head) { layer(definition, slot: .head, size: geometry.size, part: "-back") }
                                }.accessibilityHidden(true)
                            }
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

    /// `part` "-back" draws only a two-layer piece's back image (nothing otherwise). The front pass uses
    /// `wear-<id>-front` when the art comes in two layers, or the single `wear-<id>` image.
    @ViewBuilder private func layer(_ definition: BlueprintDefinition, slot: EquipmentSlot, size: CGSize, part: String = "") -> some View {
        let single = "wear-\(definition.id)"
        let asset = part == "-back" ? single + "-back" : UIImage(named: single + "-front") != nil ? single + "-front" : single
        if let avatar, let place = Self.placement(definition.id, avatarID: avatar.id), UIImage(named: asset) != nil {
            // Points are in the avatar art's 1254-pixel canvas; the fitted image is square.
            let scale = size.width / Self.canvas
            Image(asset).resizable().scaledToFit()
                .frame(width: place.width * scale, height: place.width * scale)
                .position(x: place.center.x * scale, y: place.center.y * scale)
        } else if part.isEmpty {
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
    static let headroom: CGFloat = 0.16

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
    /// canvas that lands on the body point.
    static func placement(_ blueprintID: String, avatarID: String) -> (width: CGFloat, center: CGPoint)? {
        guard let body = bodies[avatarID] else { return nil }
        let width: CGFloat, pin: CGPoint, point: CGPoint
        func head(_ depth: CGFloat) -> CGPoint { CGPoint(x: body.headX, y: body.headTop + body.headWidth * depth) }
        switch blueprintID {
        // Hats and the headband come in two layers (back behind the avatar, front in front), drawn so the
        // crown's bottom ring is 46% of the canvas wide and centred at (50%, 66%).
        case "gardenHat":
            width = body.headWidth * 2.0; pin = CGPoint(x: 0.5, y: 0.66); point = head(0.28)
        case "rainHat":
            width = body.headWidth * 1.65; pin = CGPoint(x: 0.5, y: 0.66); point = head(0.3)
        case "catEarBand":
            width = body.headWidth * 1.6; pin = CGPoint(x: 0.5, y: 0.25); point = head(0.02)
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
        // One little room sized from the space it gets: wallpaper and a wooden floor, the standing mirror
        // and the wardrobe on the floor with a few home pieces around them, and the picked piece's strip below.
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let strip: CGFloat = 104, gap: CGFloat = 12
            let roomHeight = max(320, height - strip - gap)
            let floor = roomHeight * 0.12
            let decor = width > 1000
            let mirrorHeight = roomHeight - 54 - floor * 0.5
            let mirrorWidth = min(mirrorHeight * 0.6, width * 0.26)
            let side: CGFloat = decor ? 110 + 86 + 44 : 0
            let cabinetWidth = max(360, min(mirrorHeight * 0.95 * 1.4286, width - mirrorWidth - side - 70))
            VStack(spacing: gap) {
                ZStack(alignment: .bottom) {
                    MacWardrobeRoom(floor: floor)
                    HStack(alignment: .bottom, spacing: 22) {
                        mirror.frame(width: mirrorWidth, height: mirrorWidth / 0.6)
                        if decor {
                            VStack(spacing: 10) {
                                Image("furniture-garden-leaf-wreath").resizable().scaledToFit().frame(width: 84)
                                Spacer(minLength: 0)
                                Image("furniture-garden-clay-pot").resizable().scaledToFit().frame(width: 62).padding(.bottom, -14)
                                Image("furniture-flower-stool").resizable().scaledToFit().frame(width: 100)
                            }
                            .frame(width: 110, height: mirrorWidth / 0.6 * 0.82).accessibilityHidden(true)
                        }
                        MacWardrobeCabinet(craft: craft, slot: slot, pick: pick, busy: store.isBusy,
                                           choose: { next, value in slot = next; pick = value; focused = true },
                                           setShowsGear: { value in Task { await store.setShowsWorkGearWhenEmpty(value) } })
                            .frame(width: cabinetWidth, height: cabinetWidth / 1.4286)
                        if decor {
                            Image("furniture-plant").resizable().scaledToFit().frame(width: 86).accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, floor * 0.5)
                }
                .overlay(alignment: .topLeading) {
                    if decor {
                        Image("furniture-garden-wind-chime").resizable().scaledToFit().frame(height: roomHeight * 0.22)
                            .padding(.leading, 14).accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .top) { mirrorFoot.frame(maxWidth: 420).frame(height: 34).padding(.top, 10) }
                .frame(width: width, height: roomHeight)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                MacWardrobeCloset(store: store, slot: slot, pick: $pick, openMagic: openMagic, back: back)
                    .frame(width: width, height: strip)
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

    /// The standing mirror (`wardrobe-mirror`): its glass is see-through, so the glass tint and the figure
    /// are drawn behind it, clipped to the arch the art leaves open (x 10–90%, y 6–92%).
    private var mirror: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let glass = CGRect(x: size.width * 0.1, y: size.height * 0.06, width: size.width * 0.8, height: size.height * 0.86)
            // The glass reflects the room: pale wall, the wooden floor, a rug, and the figure standing on it.
            let floorTop = glass.height * 0.8
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.92, green: 0.95, blue: 0.96), RoomTheme.paper], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [MacWardrobePalette.shelf.opacity(0.55), MacWardrobePalette.frame.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: glass.height - floorTop).offset(y: floorTop)
                Ellipse().fill(MacWardrobePalette.rug.opacity(0.55)).frame(width: glass.width * 0.78, height: glass.height * 0.07)
                    .offset(y: glass.height * 0.86)
                MacAvatarFigure(avatar: avatar, craft: craft, tryOn: tryOn)
                    .frame(width: glass.width * 0.86)
                    .frame(height: glass.height * 0.895, alignment: .bottom)
                LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: glass.width * 0.2).rotationEffect(.degrees(24)).offset(x: -glass.width * 0.3, y: glass.height * 0.05)
                    .allowsHitTesting(false)
            }
            .frame(width: glass.width, height: glass.height)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: glass.width / 2, bottomLeadingRadius: 6,
                                              bottomTrailingRadius: 6, topTrailingRadius: glass.width / 2))
            .position(x: glass.midX, y: glass.midY)
            Image("wardrobe-mirror").resizable().frame(width: size.width, height: size.height)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain).accessibilityLabel(GameStrings.text("wardrobe.now"))
    }

    /// Under the mirror: the try-on notice while trying something on, otherwise the worn handmade bonuses.
    @ViewBuilder private var mirrorFoot: some View {
        if let id = tryOn, let definition = CraftCatalog.blueprint(id: id) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                Text(GameStrings.format("wardrobe.tryOnBanner", GameStrings.text(definition.nameKey))).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                MacKeyCap(value: "esc")
            }
            .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep)
            .padding(.horizontal, 14).frame(maxHeight: .infinity)
            .background(RoomTheme.friendshipPaper.opacity(0.96), in: Capsule())
            .overlay(Capsule().strokeBorder(RoomTheme.friendshipBorder, lineWidth: 1.5))
            .accessibilityElement(children: .combine).accessibilityIdentifier("wardrobeTryOnBadge")
        } else {
            let active = HandmadeAttribute.allCases.filter { craft.bonus($0) > 0 }
            let line = active.isEmpty ? GameStrings.text("wardrobe.noHandmadeBonus")
                : active.map { GameStrings.text($0.titleKey) + " " + MacCraftStyle.valueText($0, craft.bonus($0)) }.joined(separator: " · ")
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(RoomTheme.friendshipDeep)
                Text(GameStrings.text("wardrobe.handmadeBonus") + "：").foregroundStyle(RoomTheme.friendshipDeep)
                Text(line).foregroundStyle(active.isEmpty ? RoomTheme.secondary : RoomTheme.ink).lineLimit(1).minimumScaleFactor(0.75)
            }
            .font(.system(size: 11.5, weight: .heavy))
            .padding(.horizontal, 14).frame(maxHeight: .infinity)
            .background(RoomTheme.paper.opacity(0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(RoomTheme.track, lineWidth: 1.5))
            .help(line)
            .accessibilityElement(children: .combine)
        }
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
        HStack(spacing: 14) {
            art
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Label(GameStrings.text("craft.slot.\(slot.rawValue)"), systemImage: MacWardrobePalette.symbol(slot))
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(RoomTheme.friendshipPaper, in: Capsule())
                    Text(title).font(.system(size: 16, weight: .black)).lineLimit(1).minimumScaleFactor(0.8)
                }
                info
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                buttons
                Button(action: back) {
                    Label(GameStrings.text("wardrobe.workGearLink"), systemImage: "briefcase.fill")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                }.buttonStyle(.plain).help(GameStrings.text("wardrobe.gearHint")).accessibilityIdentifier("wardrobeToProfile")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MacWardrobePalette.shelf.opacity(0.45), lineWidth: 1.5))
        .accessibilityElement(children: .contain).accessibilityIdentifier("wardrobeCloset")
        .sheet(item: $repairing) { item in
            MacRepairSheet(store: store, item: item, skillLevel: craft.skillLevel.level) { repairing = nil }
        }
    }

    private var definition: BlueprintDefinition? {
        switch pick {
        case .item(let id): craft.item(id: id)?.blueprint
        case .tryOn(let id): CraftCatalog.blueprint(id: id)
        case .none: nil
        }
    }
    private var title: String {
        switch pick {
        case .item, .tryOn: definition.map { GameStrings.text($0.nameKey) } ?? ""
        case .none: GameStrings.format("wardrobe.noneFor", GameStrings.text("craft.slot.\(slot.rawValue)"))
        }
    }

    private var art: some View {
        Group {
            if let definition {
                MacPieceArt(definition: definition, size: 70).opacity({ if case .tryOn = pick { return 0.7 } else { return 1 } }())
            } else {
                Image(systemName: "nosign").font(.system(size: 24)).foregroundStyle(RoomTheme.secondary.opacity(0.5))
            }
        }
        .frame(width: 84, height: 84)
        .background(MacWardrobePalette.inner.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MacWardrobePalette.shelf.opacity(0.5), lineWidth: 1.5))
    }

    /// One or two short lines; longer notes are in the tooltip.
    @ViewBuilder private var info: some View {
        switch pick {
        case .item(let id):
            if let item = craft.item(id: id) {
                Text(Self.summary(item)).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.darkMint).lineLimit(1)
                MacDurabilityBar(durability: item.durability, cap: item.durabilityCap, compact: true).frame(maxWidth: 260)
                    .help(GameStrings.text(craft.isWorn(item.id) ? "gear.wearsWhenWorn" : "gear.restsInCloset"))
            }
        case .tryOn:
            if let definition {
                MacCostRow(definition: definition, craft: craft).frame(maxWidth: 300)
                Text(GameStrings.text("wardrobe.tryOnNote")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8).help(GameStrings.text("wardrobe.tryOnNote"))
            }
        case .none:
            Text(fallbackLine).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(2)
        }
    }

    @ViewBuilder private var buttons: some View {
        let worn = craft.appearance[slot]
        HStack(spacing: 8) {
            if case .item(let id) = pick, let item = craft.item(id: id),
               item.repairTarget(skillLevel: craft.skillLevel.level).durability > item.durability,
               item.repairs < CraftCatalog.maximumRepairs {
                Button { repairing = item } label: {
                    Label(GameStrings.text("gear.repair.button"), systemImage: "wrench.and.screwdriver.fill")
                }.buttonStyle(SoftButtonStyle()).fixedSize().disabled(store.isBusy).accessibilityIdentifier("gearRepair")
            }
            Button { Task { await store.setAppearance(slot: slot, itemID: nil) } } label: {
                HStack(spacing: 6) { Text(GameStrings.text("wardrobe.takeOff")); MacKeyCap(value: "⌫") }
            }.buttonStyle(SoftButtonStyle()).fixedSize()
                .disabled(worn == nil || store.isBusy).accessibilityIdentifier("wardrobeTakeOff")
            switch pick {
            case .item(let id):
                Button { Task { await store.setAppearance(slot: slot, itemID: id) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: worn == id ? "checkmark" : "hanger")
                        Text(GameStrings.text(worn == id ? "wardrobe.alreadyOn" : "wardrobe.wear"))
                        if worn != id { MacKeyCap(value: "↩") }
                    }.frame(minWidth: 120)
                }.buttonStyle(MintButtonStyle()).fixedSize().keyboardShortcut(.defaultAction)
                    .disabled(worn == id || store.isBusy).accessibilityIdentifier("wardrobeWear")
            case .tryOn:
                Button(action: openMagic) {
                    Label(GameStrings.text("wardrobe.goCraft"), systemImage: "hammer.fill").lineLimit(1).frame(minWidth: 120)
                }.buttonStyle(MintButtonStyle()).fixedSize().accessibilityIdentifier("wardrobeGoCraft")
            case .none:
                Button { Task { await store.setAppearance(slot: slot, itemID: nil) } } label: {
                    Text(GameStrings.text(worn == nil ? "wardrobe.alreadyOn" : "wardrobe.wearNone")).lineLimit(1).frame(minWidth: 120)
                }.buttonStyle(MintButtonStyle()).fixedSize().disabled(worn == nil || store.isBusy)
            }
        }
    }

    private var fallbackLine: String {
        craft.showsWorkGearWhenEmpty
            ? GameStrings.format("wardrobe.followGear", workGear.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
            : GameStrings.text("wardrobe.ownClothes")
    }
}

/// A piece's own art, as large as given, with no badge behind it (falls back to the blueprint icon).
struct MacPieceArt: View {
    let definition: BlueprintDefinition
    let size: CGFloat
    var body: some View {
        if UIImage(named: "blueprint-\(definition.id)") != nil {
            Image("blueprint-\(definition.id)").resizable().scaledToFit().frame(width: size, height: size)
        } else {
            MacBlueprintIcon(definition: definition, size: size, asItem: true)
        }
    }
}

// MARK: 3.12 wardrobe cabinet

/// The wardrobe's room: soft striped wallpaper, a skirting board and a plank floor.
struct MacWardrobeRoom: View {
    let floor: CGFloat
    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(red: 0.99, green: 0.95, blue: 0.88), Color(red: 0.97, green: 0.90, blue: 0.82)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { context, size in
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: 0, width: 14, height: size.height)), with: .color(RoomTheme.friendship.opacity(0.06)))
                    x += 44
                }
            }
            VStack(spacing: 0) {
                Rectangle().fill(MacWardrobePalette.frameDark.opacity(0.35)).frame(height: 6)
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .linearGradient(Gradient(colors: [MacWardrobePalette.shelf, MacWardrobePalette.frame]),
                                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    var y: CGFloat = size.height / 3
                    while y < size.height {
                        context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1.5)), with: .color(MacWardrobePalette.frameDark.opacity(0.25)))
                        y += size.height / 3
                    }
                }
            }
            .frame(height: floor)
        }
        .accessibilityHidden(true)
    }
}

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

/// The wardrobe itself, drawn on `wardrobe-cabinet` (an open wooden wardrobe). Its art leaves fixed areas
/// free (fractions of the picture): the rail on the left for tops, and on the right the hat shelf, the
/// accessory drawer and the shoe rack. Each piece (made, a blueprint to try on, or "none") is a tile set
/// into its area; the worn one has a tick, a fragile one a red dot. The name plate and the bottom drawer
/// carry the title and the "show work gear" switch.
@MainActor
struct MacWardrobeCabinet: View {
    let craft: CraftState
    let slot: EquipmentSlot
    let pick: MacClosetPick
    let busy: Bool
    let choose: (EquipmentSlot, MacClosetPick) -> Void
    /// Main-actor isolated, so it is Sendable and can back the switch's Binding.
    let setShowsGear: @MainActor (Bool) -> Void

    /// Areas of the 2000 × 1400 art, as fractions (see ArtSource/Wardrobe312/README.md).
    private static let areas: [EquipmentSlot: CGRect] = [
        .body: CGRect(x: 0.06, y: 0.12, width: 0.43, height: 0.74),
        .head: CGRect(x: 0.51, y: 0.12, width: 0.43, height: 0.24),
        .accessory: CGRect(x: 0.51, y: 0.38, width: 0.43, height: 0.23),
        .feet: CGRect(x: 0.51, y: 0.63, width: 0.43, height: 0.23)
    ]
    /// Where tiles stand inside each area: below the rail, on the shelf, in the drawer tray, on the rack.
    private static let floors: [EquipmentSlot: (top: CGFloat, bottom: CGFloat)] = [
        .body: (0.08, 0.02), .head: (0.18, 0.03), .accessory: (0.16, 0.06), .feet: (0.16, 0.12)
    ]

    var body: some View {
        let made = craft.handmade.filter { $0.blueprint?.product.slot != nil }.count
        Color.clear.aspectRatio(2000 / 1400, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let size = geometry.size
                    Image("wardrobe-cabinet").resizable().frame(width: size.width, height: size.height).accessibilityHidden(true)
                    // A picnic basket resting on the floor of the hanging side.
                    Image("furniture-garden-picnic-basket").resizable().scaledToFit().frame(width: size.width * 0.1)
                        .position(x: size.width * 0.42, y: size.height * 0.815).accessibilityHidden(true)
                    // The brass name plate in the cornice (x 39–61%, y 2–8%).
                    Text(GameStrings.text("wardrobe.title") + " · " + GameStrings.format("wardrobe.madeCount", made))
                        .font(.system(size: max(11, size.height * 0.03), weight: .heavy)).foregroundStyle(MacWardrobePalette.frameDark)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: size.width * 0.18, height: size.height * 0.05)
                        .position(x: size.width * 0.5, y: size.height * 0.05)
                    ForEach(EquipmentSlot.allCases, id: \.self) { part in
                        if let area = Self.areas[part] {
                            let frame = CGRect(x: area.minX * size.width, y: area.minY * size.height,
                                               width: area.width * size.width, height: area.height * size.height)
                            compartment(part, in: frame.size).frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                    // The bottom drawer, left of its handle (y 88–100%).
                    Toggle(isOn: Binding(get: { craft.showsWorkGearWhenEmpty }, set: setShowsGear)) {
                        Text(GameStrings.text("wardrobe.showGear")).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .toggleStyle(.switch).controlSize(.mini).tint(RoomTheme.mint).disabled(busy)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(MacWardrobePalette.inner.opacity(0.92), in: Capsule())
                    .frame(width: size.width * 0.36)
                    .position(x: size.width * 0.24, y: size.height * 0.94)
                    .accessibilityIdentifier("wardrobeShowGear")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityElement(children: .contain).accessibilityIdentifier("wardrobeCabinet")
    }

    /// One area of the cabinet: its name tag and its tiles. The rail area wraps tiles in rows; shelves
    /// line them up in one row that scrolls sideways when there are more than fit.
    private func compartment(_ part: EquipmentSlot, in size: CGSize) -> some View {
        let picks = MacWardrobeCloset.picks(craft, slot: part)
        let chosen = part == slot
        let hanging = part == .body
        let floor = Self.floors[part] ?? (0.1, 0.05)
        let tileHeight = hanging ? min(108, size.width * 0.3) : max(52, size.height * (1 - floor.top - floor.bottom))
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? RoomTheme.friendship : .clear, lineWidth: 3)
            Group {
                if hanging {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: tileHeight * 0.8), spacing: 8)], alignment: .leading, spacing: 10) {
                            ForEach(picks, id: \.self) { value in tile(value, part: part, hanging: true, icon: tileHeight * 0.58).frame(height: tileHeight) }
                        }.padding(.horizontal, 8)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(picks, id: \.self) { value in
                                tile(value, part: part, hanging: false, icon: tileHeight * 0.6).frame(width: tileHeight * 0.86, height: tileHeight)
                            }
                        }.padding(.horizontal, 8)
                    }
                }
            }
            .padding(.top, size.height * floor.top).padding(.bottom, size.height * floor.bottom)
            HStack(spacing: 4) {
                Image(systemName: MacWardrobePalette.symbol(part)).font(.system(size: 9.5, weight: .bold))
                Text(GameStrings.text("craft.slot.\(part.rawValue)")).font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(MacWardrobePalette.frameDark)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(MacWardrobePalette.inner.opacity(chosen ? 1 : 0.85), in: Capsule())
            .overlay(Capsule().strokeBorder(chosen ? RoomTheme.friendship : MacWardrobePalette.brass.opacity(0.7), lineWidth: 1.2))
            .padding(6)
            .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GameStrings.text("craft.slot.\(part.rawValue)"))
        .accessibilityIdentifier("wardrobeSlot_\(part.rawValue)")
    }

    private func tile(_ value: MacClosetPick, part: EquipmentSlot, hanging: Bool, icon: CGFloat = 52) -> some View {
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
                            MacPieceArt(definition: definition, size: icon).opacity(isTryOn ? 0.6 : 1)
                        } else {
                            Image(systemName: "nosign").font(.system(size: 18)).foregroundStyle(RoomTheme.secondary.opacity(0.55))
                                .frame(width: icon, height: icon)
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
            .background(picked ? RoomTheme.friendshipPaper.opacity(0.92) : Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
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
