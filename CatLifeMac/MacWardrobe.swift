#if os(macOS)
import SwiftUI
import CatGameCore

/// What the closet has picked for one slot: a made piece, a blueprint to try on, or nothing.
enum MacClosetPick: Hashable {
    case item(String), tryOn(String), none
}

/// The player's full-body art with handmade clothes layered on (W1 / W2). A piece's art arrives later
/// as `wear-<blueprint>` (one transparent layer on the shared avatar canvas); until then a badge on the
/// body part stands in. Layer order follows the art guide: shoes, top, accessory, then hat.
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
        .overlay(alignment: .top) {
            if tryOn != nil {
                Label(GameStrings.text("wardrobe.tryingOn"), systemImage: "eye.fill").font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoomTheme.friendship, in: Capsule()).padding(.top, 6)
                    .accessibilityIdentifier("wardrobeTryOnBadge")
            }
        }
    }

    @ViewBuilder private func layer(_ definition: BlueprintDefinition, slot: EquipmentSlot, size: CGSize) -> some View {
        if UIImage(named: "wear-\(definition.id)") != nil {
            Image("wear-\(definition.id)").resizable().scaledToFit().frame(width: size.width, height: size.height)
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

    /// Head top, chest, left chest and feet on the shared avatar canvas.
    static func anchor(_ slot: EquipmentSlot) -> CGPoint {
        switch slot {
        case .head: CGPoint(x: 0.5, y: 0.1)
        case .body: CGPoint(x: 0.5, y: 0.45)
        case .accessory: CGPoint(x: 0.64, y: 0.36)
        case .feet: CGPoint(x: 0.5, y: 0.92)
        }
    }
}

/// One appearance slot in the profile's middle column.
struct MacAppearanceRow: View {
    let slot: EquipmentSlot
    let craft: CraftState
    let workGear: EquipmentItem?
    let selected: Bool
    let open: () -> Void

    var body: some View {
        let item = craft.appearance[slot].flatMap(craft.item(id:))
        let definition = item?.blueprint
        let fallback = craft.showsWorkGearWhenEmpty
            ? GameStrings.format("wardrobe.followGear", workGear.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
            : GameStrings.text("wardrobe.ownClothes")
        return Button(action: open) {
            HStack(spacing: 12) {
                Group {
                    if let definition {
                        MacBlueprintIcon(definition: definition, size: 46)
                    } else {
                        Image(systemName: "nosign").font(.system(size: 17)).foregroundStyle(RoomTheme.secondary.opacity(0.6))
                            .frame(width: 46, height: 46)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameStrings.text("craft.slot.\(slot.rawValue)")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    Text(definition.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("wardrobe.none"))
                        .font(.system(size: 15, weight: .black)).lineLimit(1)
                    Text(item.map(MacWardrobeCloset.summary) ?? fallback).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(item == nil ? RoomTheme.secondary : RoomTheme.darkMint).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? RoomTheme.friendship : RoomTheme.track, lineWidth: selected ? 3 : 2))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GameStrings.text("craft.slot.\(slot.rawValue)"))
        .accessibilityValue(definition.map { GameStrings.text($0.nameKey) } ?? fallback)
        .accessibilityIdentifier("profileLook_\(slot.rawValue)")
    }
}

/// The closet for one appearance slot (W1 right column / W2 try-on).
@MainActor
struct MacWardrobeCloset: View {
    let store: GameStore
    let slot: EquipmentSlot
    @Binding var pick: MacClosetPick
    let selectSlot: (EquipmentSlot) -> Void
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
