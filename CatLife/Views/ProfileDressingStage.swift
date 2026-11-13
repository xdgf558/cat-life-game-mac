import SwiftUI
import CatGameCore

/// Slot controls frame the existing artwork; gear bonuses remain data-driven.
@MainActor
struct ProfileDressingStage: View {
    let avatar: PlayerAvatar?
    let profile: PlayerProfile
    let showAttributes: () -> Void
    let chooseSlot: (EquipmentSlot) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 14) {
                portrait(width: 200, height: 280)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(EquipmentSlot.allCases, id: \.self) { slot in
                        slotButton(slot, width: 100)
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity)
            .gameCard(cornerRadius: 32)
        } else {
            GeometryReader { geometry in
                let width = geometry.size.width
                let slotWidth: CGFloat = width < 330 ? 64 : 76
                ZStack {
                    RoundedRectangle(cornerRadius: 32).fill(RoomTheme.chipBg)
                        .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
                    Circle().fill(RoomTheme.paper.opacity(0.8))
                        .frame(width: width * 0.68, height: width * 0.68)
                    Ellipse().fill(RoomTheme.ink.opacity(0.10))
                        .frame(width: width * 0.40, height: 18)
                        .offset(y: geometry.size.height / 2 - 30)
                    portrait(width: width - slotWidth * 2 - 24,
                             height: geometry.size.height - 42)
                    HStack {
                        VStack {
                            slotButton(.head, width: slotWidth)
                            Spacer()
                            slotButton(.feet, width: slotWidth)
                        }
                        Spacer(minLength: 0)
                        VStack {
                            slotButton(.body, width: slotWidth)
                            Spacer()
                            slotButton(.accessory, width: slotWidth)
                        }
                    }
                    .padding(.horizontal, 10).padding(.top, 30).padding(.bottom, 84)
                }
                .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white, lineWidth: 3))
            }
            .frame(height: 400)
        }
    }

    private func portrait(width: CGFloat, height: CGFloat) -> some View {
        // The six square PNGs have transparent sides: the full figure occupies
        // at most 49% of their width and about 94% of their height. Size the art
        // by height, while keeping the visible figure between the slot buttons.
        let artSide = min(height - 48, width / 0.49)
        return Button(action: showAttributes) {
            VStack(spacing: 6) {
                if let avatar {
                    Image(avatar.assetName).resizable().scaledToFit()
                        .frame(width: artSide, height: artSide)
                        .frame(width: width, height: artSide)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 58, weight: .light))
                        .foregroundStyle(RoomTheme.darkMint.opacity(0.7))
                        .frame(width: width, height: artSide)
                }
                Label(GameStrings.text("player.attributes.open"), systemImage: "info.circle.fill")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                    .multilineTextAlignment(.center).lineLimit(2)
                    .frame(minHeight: 28)
            }
            .frame(width: width, height: height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text("player.attributes.open"))
        .accessibilityIdentifier("profileAttributesButton")
    }

    private func slotButton(_ slot: EquipmentSlot, width: CGFloat) -> some View {
        let item = profile.equipped[slot].flatMap(PlayerCatalog.item(id:))
        return Button { chooseSlot(slot) } label: {
            VStack(spacing: 5) {
                GameIcon(asset: item?.displayAssetName ?? "", symbol: symbol(slot),
                         size: 40, tint: item == nil ? RoomTheme.secondary : tint(slot))
                    .padding(4)
                    .background(item == nil ? RoomTheme.track : tint(slot).opacity(0.16),
                                in: RoundedRectangle(cornerRadius: 15))
                Text(GameStrings.text("gear.slot.\(slot.rawValue)"))
                    .font(.system(size: 11, weight: .heavy)).lineLimit(2)
                    .minimumScaleFactor(0.8).multilineTextAlignment(.center)
            }
            .padding(.vertical, 10).frame(width: width).frame(minHeight: 84)
            .background {
                RoundedRectangle(cornerRadius: 22).fill(RoomTheme.paper)
                    .shadow(color: RoomTheme.ink.opacity(0.10), radius: 0, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(item == nil ? RoomTheme.wood.opacity(0.7) : .white,
                                  style: StrokeStyle(lineWidth: 2, dash: item == nil ? [5, 4] : []))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GameStrings.text("gear.slot.\(slot.rawValue)"))
        .accessibilityValue(item.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
        .accessibilityIdentifier("profileStageSlot_\(slot.rawValue)")
    }

    private func symbol(_ slot: EquipmentSlot) -> String {
        switch slot { case .head: "hat.cap.fill"; case .body: "tshirt.fill"; case .feet: "shoe.fill"; case .accessory: "key.fill" }
    }

    private func tint(_ slot: EquipmentSlot) -> Color {
        switch slot { case .head: RoomTheme.sky; case .body: RoomTheme.mint; case .feet: RoomTheme.gold; case .accessory: RoomTheme.lilac }
    }
}
