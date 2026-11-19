#if os(macOS)
import SwiftUI
import CatGameCore

/// C1–C4: the crafting table. Held blueprints on the left, the chosen one in the middle (materials,
/// uses, success rate and what it can roll), the craft skill and the material bag on the right.
@MainActor
struct MacCraftTable: View {
    let store: GameStore
    @Binding var selected: String?
    let working: Bool
    let craft: (String) -> Void
    let exits: MacMagicExits
    let openWheel: () -> Void
    let openBook: () -> Void
    @State private var sourceMaterial: CraftMaterial?

    /// Wearable blueprints the player has held, in book order.
    static func list(_ craft: CraftState) -> [BlueprintDefinition] {
        CraftCatalog.craftableBlueprints.filter { craft.hasEverHeld($0.id) }
    }
    private var state: CraftState { store.snapshot?.craft ?? CraftState() }
    private var definition: BlueprintDefinition? { selected.flatMap(CraftCatalog.blueprint(id:)).flatMap { state.hasEverHeld($0.id) && $0.isCraftable ? $0 : nil } }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            listColumn.frame(width: 236)
            Group {
                if let definition { detail(definition) } else { emptyDetail }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                VStack(spacing: 10) {
                    MacCraftSkillCard(craft: state, compact: true)
                    MacMaterialBag(craft: state, highlight: Set(definition.map { state.shortfall(for: $0).map(\.material) } ?? []),
                                   picked: shownMaterial, pick: { sourceMaterial = $0 }, compact: true)
                    if let material = shownMaterial { sources(material) }
                }
            }.scrollIndicators(.never).frame(width: 272)
        }
        .onChange(of: selected) { _, _ in sourceMaterial = nil }
    }

    private var shownMaterial: CraftMaterial? {
        sourceMaterial ?? definition.flatMap { state.shortfall(for: $0).first?.material }
    }

    // MARK: List

    private var listColumn: some View {
        let list = Self.list(state)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(GameStrings.text("craft.table.title")).font(.system(size: 16, weight: .black))
                Spacer()
                Text(GameStrings.format("craft.table.held", list.filter { state.usesLeft($0.id) > 0 }.count))
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            }
            ScrollView {
                VStack(spacing: 4) { ForEach(list) { row($0) } }.padding(.vertical, 2)
            }
            Button(action: openBook) {
                HStack {
                    Label(GameStrings.format("craft.table.all", CraftCatalog.blueprints.count), systemImage: "book.closed.fill")
                    Spacer()
                    Text(GameStrings.text("craft.book.title") + " ›").foregroundStyle(RoomTheme.darkMint)
                }.font(.system(size: 12, weight: .heavy)).padding(10).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("craftOpenBook")
        }.macContentCard69(padding: 12).frame(maxHeight: .infinity)
    }

    private func row(_ definition: BlueprintDefinition) -> some View {
        let chosen = selected == definition.id
        let readiness = state.readiness(for: definition)
        let line: String
        var muted = false
        switch readiness {
        case .usedUp: line = GameStrings.text("craft.usedUp"); muted = true
        case .skillTooLow(let level):
            line = GameStrings.format("craft.lockedSkill", level) + " · " + GameStrings.format("craft.usesLeftShort", state.usesLeft(definition.id))
            muted = true
        default:
            line = GameStrings.format("craft.rateShort", state.successPercent(for: definition)) + " · "
                + GameStrings.format("craft.usesLeftShort", state.usesLeft(definition.id))
        }
        return Button { selected = definition.id } label: {
            HStack(spacing: 8) {
                MacBlueprintIcon(definition: definition, size: 36).opacity(muted ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(GameStrings.text(definition.nameKey)).font(.system(size: 13.5, weight: .heavy)).lineLimit(1)
                        MacTierChip(tier: definition.tier)
                    }
                    Text(line).font(.system(size: 11, weight: .bold)).lineLimit(1)
                        .foregroundStyle(readiness == .usedUp ? RoomTheme.coralDeep : RoomTheme.secondary)
                }
                Spacer(minLength: 0)
                if readiness == .ready {
                    Circle().fill(RoomTheme.coral).frame(width: 8, height: 8)
                }
                if state.goalBlueprintID == definition.id {
                    Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(RoomTheme.coralDeep)
                }
            }
            .padding(6).frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? RoomTheme.gold.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chosen ? RoomTheme.gold : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("craftRow_\(definition.id)")
    }

    private var emptyDetail: some View {
        VStack(spacing: 14) {
            Image(systemName: "scroll").font(.system(size: 44, weight: .bold)).foregroundStyle(RoomTheme.gold)
            Text(GameStrings.text("craft.table.empty")).font(.system(size: 18, weight: .heavy))
            Text(GameStrings.text("craft.table.emptyHint")).font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360)
            HStack(spacing: 10) {
                Button(action: exits.garden) { Label(GameStrings.text("craft.route.goGarden"), systemImage: "pawprint.fill") }
                    .buttonStyle(SoftButtonStyle()).fixedSize()
                Button(action: openWheel) { Label(GameStrings.text("craft.station.wheel"), systemImage: "circle.dashed.inset.filled") }
                    .buttonStyle(MintButtonStyle()).fixedSize()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).macContentCard69(padding: 24)
    }

    // MARK: Detail

    private func detail(_ definition: BlueprintDefinition) -> some View {
        let readiness = state.readiness(for: definition)
        return VStack(spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        MacBlueprintIcon(definition: definition, size: 64, asItem: true)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(GameStrings.text(definition.nameKey)).font(.system(size: 20, weight: .black))
                                MacBlueprintTags(definition: definition)
                            }
                            Text(GameStrings.text(definition.detailKey)).font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(RoomTheme.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if readiness == .usedUp {
                        usedUp(definition)
                    } else {
                        sectionTitle("craft.detail.materials")
                        HStack(spacing: 6) { ForEach(definition.costs) { costTile($0) } }
                        odds(definition)
                        sectionTitle("craft.detail.attributes")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 6)], spacing: 6) {
                            ForEach(CraftCatalog.attributes(for: definition.tier), id: \.self) { attribute in
                                HStack(spacing: 6) {
                                    Image(systemName: MacCraftStyle.symbol(attribute)).font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(MacCraftStyle.tint(attribute))
                                    Text(GameStrings.text(attribute.titleKey)).font(.system(size: 11.5, weight: .heavy)).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(MacCraftStyle.rangeText(attribute)).font(.system(size: 11.5, weight: .black)).monospacedDigit()
                                }.padding(.horizontal, 10).padding(.vertical, 6).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        qualityRow(definition)
                    }
                }.padding(.bottom, 2)
            }.scrollIndicators(.never)
            craftButton(definition, readiness: readiness)
        }.macContentCard69(padding: 14).frame(maxHeight: .infinity)
    }

    private func sectionTitle(_ key: String) -> some View {
        Text(GameStrings.text(key)).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
    }

    private func costTile(_ cost: CraftCost) -> some View {
        let have = state.count(of: cost.material), enough = have >= cost.count
        return HStack(spacing: 6) {
            MacMaterialArt(material: cost.material, size: 26)
            Text(GameStrings.text(cost.material.titleKey)).font(.system(size: 12.5, weight: .heavy)).lineLimit(1)
            Spacer(minLength: 4)
            Text(verbatim: "\(have)/\(cost.count)").font(.system(size: 13.5, weight: .black)).monospacedDigit()
                .foregroundStyle(enough ? RoomTheme.darkMint : RoomTheme.coralDeep)
        }
        .padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity)
        .background((enough ? RoomTheme.paleMint : RoomTheme.paleCoral).opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(enough ? RoomTheme.mint.opacity(0.4) : RoomTheme.coral, lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }

    /// Success rate and the uses left on this copy, in one card.
    private func odds(_ definition: BlueprintDefinition) -> some View {
        let base = definition.tier.baseSuccessPercent
        let skill = state.skillLevel
        let streak = (state.blueprints[definition.id]?.failureStreak ?? 0) * CraftCatalog.failureBonusPercent
        let total = state.successPercent(for: definition)
        let skillPart = max(0, min(skill.successBonus, total - base))
        let streakPart = max(0, total - base - skillPart)
        let left = state.usesLeft(definition.id), cap = definition.tier.usesPerCopy
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(GameStrings.text("craft.detail.rate")).font(.system(size: 12.5, weight: .heavy))
                Text(verbatim: "\(total)%").font(.system(size: 22, weight: .black)).monospacedDigit().foregroundStyle(RoomTheme.darkMint)
                Spacer(minLength: 6)
                Text(GameStrings.format("craft.detail.rateParts", GameStrings.text(definition.tier.titleKey), base, skill.level, skillPart)
                     + (streak > 0 ? " " + GameStrings.format("craft.detail.rateStreak", streakPart) : ""))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                HStack(spacing: 0) {
                    Rectangle().fill(RoomTheme.mint).frame(width: width * CGFloat(base) / 100)
                    Rectangle().fill(RoomTheme.mint.opacity(0.5)).frame(width: width * CGFloat(skillPart) / 100)
                    Rectangle().fill(RoomTheme.gold.opacity(0.6)).frame(width: width * CGFloat(streakPart) / 100)
                    Rectangle().fill(RoomTheme.paleCoral)
                }.clipShape(Capsule())
            }.frame(height: 8).accessibilityHidden(true)
            Text(GameStrings.format("craft.detail.ifFail", CraftCatalog.failureBonusPercent))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.coralDeep).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(RoomTheme.rewardBorder.opacity(0.5))
            HStack(spacing: 8) {
                Image(systemName: "scroll.fill").font(.system(size: 12)).foregroundStyle(ExchangePalette.goldInk)
                Text(GameStrings.text("craft.detail.usesLeft")).font(.system(size: 12, weight: .heavy))
                // Up to 8 diamonds; a copy stacked past that (up to 16) just shows the number.
                if max(cap, left) <= 8 {
                    HStack(spacing: 2) {
                        ForEach(0..<max(cap, left), id: \.self) { index in
                            Image(systemName: index < left ? "diamond.fill" : "diamond").font(.system(size: 8, weight: .bold))
                                .foregroundStyle(index < left ? ExchangePalette.goldInk : RoomTheme.secondary.opacity(0.5))
                        }
                    }.accessibilityHidden(true)
                }
                Text(verbatim: "\(left)").font(.system(size: 14, weight: .black)).monospacedDigit().foregroundStyle(RoomTheme.coralDeep)
                Spacer(minLength: 4)
                Text(GameStrings.format("craft.detail.usesRule", GameStrings.text(definition.tier.titleKey), cap)
                        .replacingOccurrences(of: "\n", with: " · "))
                    .font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.75)
            }.accessibilityElement(children: .combine)
        }
        .padding(12).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(RoomTheme.rewardBorder, lineWidth: 1.5))
        .accessibilityElement(children: .combine).accessibilityIdentifier("craftRate")
    }

    private func qualityRow(_ definition: BlueprintDefinition) -> some View {
        let odds = CraftCatalog.qualityOdds(tier: definition.tier, skillLevel: state.skillLevel.level)
        return HStack(spacing: 6) {
            ForEach(OutingDecorQuality.allCases, id: \.self) { quality in
                HStack(spacing: 4) {
                    Text(GameStrings.text(quality.titleKey) + " · \(odds[quality] ?? 0)%").font(.system(size: 11.5, weight: .heavy))
                    Text(GameStrings.format("craft.detail.attributeCount", CraftCatalog.attributeCount(tier: definition.tier, quality: quality)))
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(MacCraftStyle.tint(quality)).padding(.vertical, 6).padding(.horizontal, 4).frame(maxWidth: .infinity)
                .background(MacCraftStyle.tint(quality).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MacCraftStyle.tint(quality).opacity(0.4), lineWidth: 1.2))
            }
        }.accessibilityElement(children: .combine)
    }

    private func usedUp(_ definition: BlueprintDefinition) -> some View {
        let made = state.blueprints[definition.id]?.craftedCount ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Label(GameStrings.text("craft.usedUp.title"), systemImage: "scroll").font(.system(size: 17, weight: .heavy))
                .foregroundStyle(RoomTheme.coralDeep)
            Text(GameStrings.format("craft.usedUp.body", made)).font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            routeRow("circle.dashed.inset.filled", GameStrings.text("craft.route.wheel"), action: openWheel)
            routeRow("sparkles", GameStrings.format("craft.route.stardust", definition.tier.stardustPrice), action: openWheel)
            if definition.source != .luck {
                routeRow("flag.fill", MacCraftStyle.sourceText(definition.source, store: store) + " · " + GameStrings.text("craft.route.firstOnly"), action: nil)
            }
        }.padding(14).background(RoomTheme.paleCoral.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }

    private func craftButton(_ definition: BlueprintDefinition, readiness: CraftState.Readiness) -> some View {
        let percent = state.successPercent(for: definition)
        let title: String
        switch readiness {
        case .ready: title = GameStrings.format("craft.button.make", percent)
        case .lacksMaterials:
            let first = state.shortfall(for: definition).first
            title = first.map { GameStrings.format("craft.button.lack", GameStrings.text($0.material.titleKey), $0.count) } ?? ""
        case .usedUp: title = GameStrings.text("craft.usedUp")
        case .skillTooLow(let level):
            let need = CraftCatalog.skillLevels.first { $0.level == level }?.minimumExperience ?? 0
            title = GameStrings.format("craft.button.skill", level, max(0, need - state.experience))
        case .neverHeld, .notYetOpen: title = GameStrings.text("craft.button.unavailable")
        }
        return Button { craft(definition.id) } label: {
            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small).tint(.white) } else { Image(systemName: "hammer.fill") }
                Text(working ? GameStrings.text("common.saving") : title)
                if readiness == .ready, !working { MacKeyCap(value: "↩") }
            }.font(.system(size: 16, weight: .heavy)).frame(maxWidth: .infinity)
        }
        .buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction)
        .disabled(readiness != .ready || working || store.isBusy)
        .accessibilityIdentifier("craftButton")
    }

    // MARK: Where materials come from

    private func sources(_ material: CraftMaterial) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(GameStrings.format("craft.where.title", GameStrings.text(material.titleKey)), systemImage: "map.fill")
                .font(.system(size: 14, weight: .heavy))
            switch material {
            case .fabric:
                routeRow("briefcase.fill", GameStrings.format("craft.route.work", CraftCatalog.workFabricChance), action: exits.work)
            case .thread, .wood, .dye:
                let spot = OutingSpot.allCases.first { CraftCatalog.material(at: $0) == material } ?? .flowerBed
                routeRow("pawprint.fill", GameStrings.format("craft.route.garden", GameStrings.text(spot.titleKey)), action: exits.garden)
            case .stardust:
                routeRow("scroll.fill", GameStrings.text("craft.route.overflow"), action: nil)
            }
            routeRow("circle.dashed.inset.filled", GameStrings.text("craft.route.wheel"), action: openWheel)
        }.macContentCard69(padding: 12).accessibilityIdentifier("craftSources")
    }

    private func routeRow(_ symbol: String, _ text: String, action: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.darkMint).frame(width: 28, height: 28)
                .background(RoomTheme.paleMint.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            Text(text).font(.system(size: 12, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action {
                Button(GameStrings.text("craft.route.go") + " ›", action: action).buttonStyle(.plain)
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            }
        }
    }
}

/// 初级 / 中级 / 高级.
struct MacTierChip: View {
    let tier: CraftTier
    var body: some View {
        Text(GameStrings.text(tier.titleKey)).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 2).background(MacCraftStyle.tint(tier), in: Capsule())
    }
}

/// The craft skill: level, proficiency to the next level, and what each level unlocks.
struct MacCraftSkillCard: View {
    let craft: CraftState
    /// Only the current and the next level instead of all five.
    var compact = false
    var body: some View {
        let level = craft.skillLevel
        let next = CraftCatalog.nextSkillLevel(experience: craft.experience)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(GameStrings.text("craft.skill.title"), systemImage: "graduationcap.fill").font(.system(size: 15, weight: .heavy))
                Spacer()
                Text("Lv\(level.level) " + GameStrings.text(level.titleKey)).font(.system(size: 14, weight: .black)).foregroundStyle(ExchangePalette.goldInk)
            }
            if let next {
                MacCapsuleProgress(value: Double(craft.experience - level.minimumExperience),
                                   total: Double(next.minimumExperience - level.minimumExperience), tint: RoomTheme.gold)
                Text(GameStrings.format("craft.skill.progress", craft.experience, next.minimumExperience))
                    .font(.system(size: 11.5, weight: .heavy)).foregroundStyle(ExchangePalette.goldInk).monospacedDigit()
            } else {
                Text(GameStrings.text("craft.skill.max")).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(ExchangePalette.goldInk)
            }
            Text(GameStrings.text("craft.skill.rule")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(compact ? CraftCatalog.skillLevels.filter { $0.level == level.level || $0.level == level.level + 1 } : CraftCatalog.skillLevels) { item in
                let reached = craft.experience >= item.minimumExperience
                HStack(spacing: 8) {
                    Text("\(item.level)").font(.system(size: 11, weight: .black)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(reached ? RoomTheme.gold : RoomTheme.track, in: Circle())
                    Text(GameStrings.text(item.titleKey)).font(.system(size: 12, weight: .heavy)).frame(width: 40, alignment: .leading)
                    Text(GameStrings.text(item.unlockKey)).font(.system(size: 11, weight: .bold)).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(reached ? RoomTheme.ink : RoomTheme.secondary.opacity(0.7))
                .padding(.vertical, 3).padding(.horizontal, 6)
                .background(item.level == level.level ? RoomTheme.gold.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }.macContentCard69(padding: compact ? 12 : 16).accessibilityElement(children: .combine).accessibilityIdentifier("craftSkill")
    }
}

extension MacCraftStyle {
    static func symbol(_ attribute: HandmadeAttribute) -> String {
        switch attribute {
        case .footprint: "pawprint.fill"
        case .outingStamina: "bolt.fill"
        case .dailyMood: "face.smiling.fill"
        case .bond: "heart.fill"
        case .napRecovery: "cup.and.saucer.fill"
        case .workGold: "dollarsign.circle.fill"
        }
    }
    static func tint(_ attribute: HandmadeAttribute) -> Color {
        switch attribute {
        case .footprint: RoomTheme.darkMint
        case .outingStamina: RoomTheme.mint
        case .dailyMood: RoomTheme.friendship
        case .bond: RoomTheme.coral
        case .napRecovery: RoomTheme.lilac
        case .workGold: RoomTheme.gold
        }
    }
}

// MARK: - Book

/// C5: six themes × three blueprints, each with its tier, uses and status; details on the right.
@MainActor
struct MacBlueprintBook: View {
    let store: GameStore
    @Binding var selected: String?
    let openCraft: (String) -> Void
    let openWheel: () -> Void
    let exchange: () -> Void
    let wardrobe: () -> Void

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }
    private var definition: BlueprintDefinition? { selected.flatMap(CraftCatalog.blueprint(id:)) ?? CraftCatalog.blueprints.first }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(CraftTier.allCases, id: \.self) { tier in
                        VStack(alignment: .leading, spacing: 2) {
                            MacTierChip(tier: tier)
                            Text(GameStrings.format("craft.book.tierLine", min(CraftCatalog.maximumSuccessPercent,
                                                                                tier.baseSuccessPercent + craft.skillLevel.successBonus),
                                                    tier.usesPerCopy))
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(CraftTheme.allCases) { theme in
                            HStack(spacing: 8) {
                                Text(GameStrings.text(theme.titleKey)).font(.system(size: 12.5, weight: .heavy))
                                    .foregroundStyle(MacCraftStyle.tint(theme)).frame(width: 58, alignment: .leading)
                                ForEach(CraftCatalog.blueprints(in: theme)) { card($0) }
                            }
                        }
                    }.padding(.vertical, 2)
                }.scrollIndicators(.never)
            }.macContentCard69(padding: 16).frame(maxWidth: .infinity, maxHeight: .infinity)
            if let definition { detail(definition).frame(width: 340) }
        }
    }

    private func status(_ definition: BlueprintDefinition) -> (String, Color) {
        switch craft.readiness(for: definition) {
        case .ready: return (GameStrings.text("craft.status.ready"), RoomTheme.coral)
        case .lacksMaterials:
            let have = definition.costs.filter { craft.count(of: $0.material) >= $0.count }.count
            return (GameStrings.format("craft.status.materials", have, definition.costs.count), RoomTheme.secondary)
        case .usedUp: return (GameStrings.text("craft.usedUp"), RoomTheme.coralDeep)
        case .neverHeld: return (GameStrings.text("craft.status.notLearned"), RoomTheme.secondary.opacity(0.7))
        case .skillTooLow(let level): return (GameStrings.format("craft.lockedSkill", level), RoomTheme.secondary)
        case .notYetOpen: return (GameStrings.text("craft.status.decorLater"), RoomTheme.secondary.opacity(0.7))
        }
    }

    private func card(_ definition: BlueprintDefinition) -> some View {
        let chosen = definition.id == self.definition?.id
        let held = craft.hasEverHeld(definition.id)
        let (line, tint) = status(definition)
        return Button { selected = definition.id } label: {
            HStack(spacing: 8) {
                MacBlueprintIcon(definition: definition, size: 38, dim: !held)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(GameStrings.text(definition.nameKey)).font(.system(size: 12.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                        MacTierChip(tier: definition.tier)
                    }
                    Text(held && definition.isCraftable && craft.usesLeft(definition.id) > 0
                         ? GameStrings.format("craft.usesLeftShort", craft.usesLeft(definition.id)) + " · " + line : line)
                        .font(.system(size: 10.5, weight: .bold)).foregroundStyle(tint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? RoomTheme.gold.opacity(0.12) : RoomTheme.cream.opacity(held ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chosen ? RoomTheme.gold : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("bookCard_\(definition.id)")
    }

    private func detail(_ definition: BlueprintDefinition) -> some View {
        let readiness = craft.readiness(for: definition)
        let held = craft.hasEverHeld(definition.id)
        let isGoal = craft.goalBlueprintID == definition.id
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        // The pattern, with a peek at what it makes in the corner.
                        MacBlueprintIcon(definition: definition, size: 70)
                            .overlay(alignment: .bottomTrailing) {
                                MacBlueprintIcon(definition: definition, size: 30, asItem: true)
                                    .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 9))
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white, lineWidth: 1.5))
                                    .offset(x: 8, y: 8)
                            }
                            .padding(.trailing, 8).padding(.bottom, 8)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(GameStrings.text(definition.nameKey)).font(.system(size: 20, weight: .black))
                            MacBlueprintTags(definition: definition)
                        }
                    }
                    Text(GameStrings.text(definition.detailKey)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status(definition).0).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(status(definition).1)
                    Text(GameStrings.text("craft.detail.materials")).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    MacCostRow(definition: definition, craft: craft)
                    if case .skillTooLow(let level) = readiness {
                        Text(GameStrings.format("craft.book.skillNote", level, GameStrings.text(definition.tier.titleKey)))
                            .font(.system(size: 11.5, weight: .bold)).foregroundStyle(ExchangePalette.goldInk).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(GameStrings.text("craft.book.routes")).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    if definition.isCraftable {
                        if definition.source != .luck {
                            route("flag.fill", MacCraftStyle.sourceText(definition.source, store: store), done: craft.grantedSources.contains(definition.id),
                                  later: !definition.source.isAvailable)
                        }
                        route("circle.dashed.inset.filled", GameStrings.text("craft.route.wheel"), done: false, later: false)
                        route("sparkles", GameStrings.format("craft.route.stardust", definition.tier.stardustPrice), done: false, later: false)
                    } else {
                        route("flag.fill", MacCraftStyle.sourceText(definition.source, store: store), done: craft.grantedSources.contains(definition.id),
                              later: !definition.source.isAvailable)
                        Text(GameStrings.text("craft.book.decorNote")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.scrollIndicators(.never)
            // Decor can't be crafted yet, so it can't be a goal (an old goal can still be cleared).
            if definition.isCraftable || isGoal {
                Button { Task { await store.setCraftGoal(isGoal ? nil : definition.id) } } label: {
                    Label(GameStrings.text(isGoal ? "craft.goal.clear" : "craft.goal.set"), systemImage: isGoal ? "pin.slash.fill" : "pin.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy).accessibilityIdentifier("bookGoal")
            }
            if held && definition.isCraftable {
                HStack(spacing: 8) {
                    if definition.product.slot != nil {
                        Button(action: wardrobe) { Label(GameStrings.text("craft.book.tryOn"), systemImage: "hanger").frame(maxWidth: .infinity) }
                            .buttonStyle(SoftButtonStyle())
                    }
                    Button { openCraft(definition.id) } label: {
                        Label(GameStrings.text("craft.book.goCraft"), systemImage: "hammer.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("bookGoCraft")
                }
            } else if definition.isCraftable {
                Button(action: exchange) {
                    Label(GameStrings.format("craft.book.exchange", definition.tier.stardustPrice), systemImage: "sparkles").frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).disabled(craft.count(of: .stardust) < definition.tier.stardustPrice)
            }
        }.macContentCard69(padding: 18).frame(maxHeight: .infinity)
    }

    private func route(_ symbol: String, _ text: String, done: Bool, later: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol).font(.system(size: 13, weight: .bold))
                .foregroundStyle(done ? RoomTheme.mint : later ? RoomTheme.secondary.opacity(0.6) : RoomTheme.darkMint).frame(width: 22)
            Text(text + (later ? " · " + GameStrings.text("craft.route.later") : "")).font(.system(size: 12, weight: .bold))
                .foregroundStyle(later ? RoomTheme.secondary : RoomTheme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(10).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Result

/// C2 / C3: what the last try made, or what came back after a miss.
@MainActor
struct MacCraftResultCard: View {
    let store: GameStore
    let working: Bool
    let wear: (HandmadeItem) -> Void
    let keep: () -> Void
    let retry: (String) -> Void

    private var craft: CraftState { store.snapshot?.craft ?? CraftState() }

    var body: some View {
        if let attempt = craft.lastAttempt, let definition = CraftCatalog.blueprint(id: attempt.blueprintID) {
            Group {
                if attempt.succeeded, let item = attempt.itemID.flatMap(craft.item(id:)) {
                    success(attempt, definition: definition, item: item)
                } else {
                    failure(attempt, definition: definition)
                }
            }
            .padding(22).frame(width: 460).modifier(MacMagicCardChrome())
            .accessibilityIdentifier("craftResult").accessibilityValue(attempt.succeeded ? "success" : "failed")
        }
    }

    private func success(_ attempt: CraftAttemptResult, definition: BlueprintDefinition, item: HandmadeItem) -> some View {
        VStack(spacing: 12) {
            Text(GameStrings.text("craft.success.kicker")).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint).tracking(1.2)
            MacBlueprintIcon(definition: definition, size: 96, asItem: true)
                .padding(6).overlay(Circle().strokeBorder(MacCraftStyle.tint(item.quality), lineWidth: 4).padding(-6))
            Text(GameStrings.format("craft.success.title", GameStrings.text(definition.nameKey))).font(.system(size: 21, weight: .heavy))
                .accessibilityAddTraits(.isHeader)
            Text(GameStrings.text(item.quality.titleKey)).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 4).background(MacCraftStyle.tint(item.quality), in: Capsule())
            VStack(spacing: 6) {
                ForEach(item.attributes, id: \.attribute) { roll in
                    HStack {
                        Image(systemName: MacCraftStyle.symbol(roll.attribute)).foregroundStyle(MacCraftStyle.tint(roll.attribute))
                        Text(GameStrings.text(roll.attribute.titleKey)).font(.system(size: 13, weight: .heavy))
                        Spacer()
                        Text(MacCraftStyle.valueText(roll.attribute, roll.value)).font(.system(size: 15, weight: .black)).monospacedDigit()
                        Text("(" + MacCraftStyle.rangeText(roll.attribute) + ")").font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    }.padding(.horizontal, 12).padding(.vertical, 8).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            experienceLine(attempt)
            MacBeforeAfterRow(title: GameStrings.text("craft.result.uses"), before: attempt.usesBefore, after: attempt.usesAfter)
            Text(GameStrings.text("craft.success.note")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button(action: keep) {
                    HStack(spacing: 8) { Text(GameStrings.text("craft.success.keep")); MacKeyCap(value: "esc") }
                }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction).disabled(working)
                if definition.product.slot != nil {
                    Button { wear(item) } label: {
                        HStack(spacing: 8) { Image(systemName: "hanger"); Text(GameStrings.text("craft.success.wear")); MacKeyCap(value: "↩") }
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction).disabled(working || store.isBusy)
                        .accessibilityIdentifier("craftWearNow")
                }
            }
        }
    }

    private func failure(_ attempt: CraftAttemptResult, definition: BlueprintDefinition) -> some View {
        let canRetry = craft.readiness(for: definition) == .ready
        return VStack(spacing: 12) {
            Text(GameStrings.text("craft.fail.kicker")).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep).tracking(1.2)
            Image(systemName: "wand.and.rays.inverse").font(.system(size: 38, weight: .bold)).foregroundStyle(RoomTheme.coral)
                .frame(width: 84, height: 84).background(RoomTheme.paleCoral.opacity(0.6), in: Circle())
            Text(GameStrings.format("craft.fail.title", GameStrings.text(definition.nameKey))).font(.system(size: 21, weight: .heavy))
                .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            Text(GameStrings.text("craft.fail.body")).font(.system(size: 12.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                materialColumn("craft.fail.back", attempt.refunded, tint: RoomTheme.darkMint)
                materialColumn("craft.fail.used", attempt.spent, tint: RoomTheme.coralDeep)
            }
            experienceLine(attempt)
            MacBeforeAfterRow(title: GameStrings.text("craft.fail.nextRate"), before: attempt.successPercent, after: attempt.nextSuccessPercent, suffix: "%")
            HStack(spacing: 10) {
                Button(action: keep) {
                    HStack(spacing: 8) { Text(GameStrings.text("craft.fail.stop")); MacKeyCap(value: "esc") }
                }.buttonStyle(SoftButtonStyle()).keyboardShortcut(.cancelAction).disabled(working)
                Button { retry(definition.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text(canRetry ? GameStrings.format("craft.fail.retry", attempt.nextSuccessPercent) : GameStrings.text("craft.fail.cannotRetry"))
                        if canRetry { MacKeyCap(value: "↩") }
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).keyboardShortcut(.defaultAction).disabled(!canRetry || working || store.isBusy)
                    .accessibilityIdentifier("craftRetry")
            }
        }
    }

    private func materialColumn(_ key: String, _ values: [String: Int], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(GameStrings.text(key)).font(.system(size: 12, weight: .heavy)).foregroundStyle(tint)
            ForEach(CraftMaterial.allCases.filter { (values[$0.rawValue] ?? 0) > 0 }) { material in
                HStack {
                    Image(systemName: material.symbol).foregroundStyle(MacCraftStyle.tint(material))
                    Text(GameStrings.text(material.titleKey)).font(.system(size: 12.5, weight: .heavy))
                    Spacer()
                    Text(verbatim: "×\(values[material.rawValue] ?? 0)").font(.system(size: 13, weight: .black)).monospacedDigit()
                }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .topLeading).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func experienceLine(_ attempt: CraftAttemptResult) -> some View {
        let before = CraftCatalog.skillLevel(experience: attempt.experienceBefore)
        let after = CraftCatalog.skillLevel(experience: attempt.experienceAfter)
        let learned = attempt.learnedBlueprintIDs.compactMap(CraftCatalog.blueprint(id:)).map { GameStrings.text($0.nameKey) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "graduationcap.fill").foregroundStyle(ExchangePalette.goldInk)
                Text(after.level > before.level
                     ? GameStrings.format("craft.result.levelUp", after.level, GameStrings.text(after.titleKey))
                     : GameStrings.format("craft.result.experience", attempt.experienceAfter - attempt.experienceBefore, attempt.experienceAfter))
                    .font(.system(size: 13, weight: .heavy))
                Spacer()
            }
            if after.level > before.level {
                Text(GameStrings.text(after.unlockKey)).font(.system(size: 11.5, weight: .bold)).foregroundStyle(ExchangePalette.goldInk)
            }
            if !learned.isEmpty {
                Text(GameStrings.format("craft.grants.line", learned.joined(separator: "、"))).font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(RoomTheme.darkMint)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
#endif
