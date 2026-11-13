import SwiftUI
import CatGameCore

/// Profile and wardrobe are views of the same saved player state. All changes
/// go through the store's atomic commit path before being shown as equipped.
@MainActor
struct PlayerProfileView: View {
    @Bindable var store: GameStore
    @State private var path: [Route] = []
    @State private var isShowingAttributes = false
    @State private var avatarGender: AvatarGender?
    @State private var playerNameDraft = ""
    @State private var savedPlayerNameDraft = ""
    @State private var playerNameStatusKey: String?
    @State private var isSavingPlayerName = false
    @FocusState private var playerNameFieldFocused: Bool

    private enum Route: Hashable { case name, avatars, wardrobe, bonuses, equipment(EquipmentSlot) }
    private var player: PlayerState? { store.snapshot?.player }
    private var profile: PlayerProfile { player?.profile ?? PlayerProfile() }
    private var avatar: PlayerAvatar? { profile.avatarID.flatMap(PlayerCatalog.avatar(id:)) }
    private var bonuses: EquipmentBonuses { PlayerCatalog.bonuses(for: profile) }
    private var slots: [EquipmentSlot] { [.head, .body, .feet, .accessory] }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    identityDetails
                    portrait
                    bonusSummary
                    overviewStats
                }
                .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("profileScroll")
            .background(RoomTheme.cream)
            .navigationTitle(GameStrings.text("player.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(path.isEmpty ? .hidden : .visible, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .name: playerNamePage
                case .avatars: avatarPicker
                case .wardrobe: wardrobePage
                case .bonuses: bonusesPage
                case .equipment(let slot): equipmentPicker(slot)
                }
            }

        }
        .saveRecoveryAlert(store: store, isActive: !isShowingAttributes && !store.onboarding.isPresented)
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .sheet(isPresented: $isShowingAttributes) { attributesSheet }
    }

    private var portrait: some View {
        VStack(spacing: 12) {
            ProfileDressingStage(avatar: avatar, profile: profile,
                                 showAttributes: { isShowingAttributes = true },
                                 chooseSlot: { slot in
                if PlayerCatalog.equipment.contains(where: {
                    $0.slot == slot && profile.ownedEquipmentIDs.contains($0.id)
                }) {
                    path.append(.equipment(slot))
                } else {
                    store.activeSheet = .shop
                }
            })
            HStack(spacing: 10) {
                Button { path.append(.avatars) } label: {
                    Label(GameStrings.text(avatar == nil ? "player.avatar.choose" : "player.appearance"),
                          systemImage: "person.crop.rectangle")
                        .font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                }
                .buttonStyle(SoftButtonStyle()).accessibilityIdentifier("profileChooseAvatar")
                Button { path.append(.wardrobe) } label: {
                    Label(GameStrings.text("player.wardrobe"), systemImage: "tshirt.fill")
                        .font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                }
                .buttonStyle(SoftButtonStyle()).accessibilityIdentifier("profileWardrobeButton")
                .accessibilityValue(GameStrings.format("player.equippedCount", profile.equipped.count, slots.count))
            }
        }
    }

    private var identityDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 2) {
                    Text(verbatim: store.playerDisplayName)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.75)
                        .accessibilityIdentifier("profilePlayerName")
                        .accessibilityValue(Text(verbatim: store.playerDisplayName))
                    Button { path.append(.name) } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(GameStrings.text("playerName.edit"))
                    .accessibilityIdentifier("profileRenameButton")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    summaryResource(symbol: "bolt.fill", value: player?.stamina ?? 0,
                                    tint: RoomTheme.mint, label: "player.stamina")
                    summaryResource(symbol: "face.smiling.fill", value: player?.mood ?? 0,
                                    tint: RoomTheme.gold, label: "player.mood")
                }
                .padding(.horizontal, 10).frame(minHeight: 38)
                .background(RoomTheme.paper, in: Capsule())
                .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
            }
            HStack(spacing: 6) {
                Text(GameStrings.format("career.level", player?.level ?? 1))
                    .accessibilityIdentifier("profileLevelSummary")
                    .accessibilityValue("\(player?.level ?? 1)")
                Text("·").accessibilityHidden(true)
                Text(GameStrings.text("redesign.profile.dressUp"))
            }
            .font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            HStack(spacing: 6) {
                Text(avatar.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("player.avatar.unselected"))
                    .accessibilityIdentifier("profileAvatarName").accessibilityValue(profile.avatarID ?? "none")
                Spacer(minLength: 0)
                Label(GameStrings.text(statusKey), systemImage: statusSymbol)
                    .accessibilityIdentifier("profileStatus").accessibilityValue(statusValue)
            }
            .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
        }
    }

    private func summaryResource(symbol: String, value: Int, tint: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text("\(value)").monospacedDigit()
        }
        .font(.system(size: 15, weight: .heavy))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(label)).accessibilityValue("\(value)")
    }

    private var bonusSummary: some View {
        Button { path.append(.bonuses) } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.system(size: 17, weight: .bold))
                Text(profile.equipped.isEmpty ? GameStrings.text("player.noBonuses")
                     : GameStrings.format("redesign.profile.activeBonuses", bonuses.durationReductionPercent,
                                          bonuses.staminaReductionPercent, bonuses.moodReductionPercent))
                    .font(.system(size: 12, weight: .bold)).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .foregroundStyle(RoomTheme.darkMint).padding(14).frame(maxWidth: .infinity, minHeight: 44)
            .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain).accessibilityIdentifier("profileBonusesButton")
        .accessibilityLabel(GameStrings.text("player.bonuses"))
        .accessibilityValue(profile.equipped.isEmpty ? GameStrings.text("player.noBonuses")
            : GameStrings.format("redesign.profile.activeBonuses", bonuses.durationReductionPercent,
                                 bonuses.staminaReductionPercent, bonuses.moodReductionPercent))
    }

    private var overviewStats: some View {
        HStack(spacing: 10) {
            overviewStat("player.gold", value: player?.gold ?? 0, identifier: "profileOverviewGold")
            overviewStat("player.completedWorkTitle", value: player?.completedWorkCount ?? 0,
                         identifier: "profileOverviewWork")
            overviewStat("redesign.profile.catCount", value: store.snapshot?.cats.count ?? 0,
                         identifier: "profileOverviewCats")
        }
    }

    private func overviewStat(_ key: String, value: Int, identifier: String) -> some View {
        VStack(spacing: 6) {
            Text("\(value)").font(.system(size: 25, weight: .heavy)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(GameStrings.text(key)).font(.system(size: 11, weight: .bold))
                .foregroundStyle(RoomTheme.secondary).lineLimit(2).multilineTextAlignment(.center)
        }
        .padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 80)
        .gameCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(key)).accessibilityValue("\(value)")
        .accessibilityIdentifier(identifier)
    }

    private var attributesSheet: some View {
        NavigationStack {
            ScrollView {
                attributes
                    .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("profileAttributesSheet")
            .background(RoomTheme.cream)
            .navigationTitle(GameStrings.text("player.stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(GameStrings.text("common.done")) { isShowingAttributes = false }
                        .foregroundStyle(RoomTheme.darkMint)
                        .accessibilityIdentifier("profileAttributesCloseButton")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { SaveStatusBanner(store: store) }
        .saveRecoveryAlert(store: store)
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
        .presentationBackground(RoomTheme.cream)
    }

    private var wardrobePage: some View {
        ScrollView(.vertical, showsIndicators: true) {
            wardrobe.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("profileWardrobeScroll").background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("player.wardrobe"))
        .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .toolbar { sectionBackButton }
    }

    private var bonusesPage: some View {
        ScrollView {
            bonusCard.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("profileBonusesScroll").background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("player.bonuses"))
        .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .toolbar { sectionBackButton }
    }

    private var sectionBackButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { if !path.isEmpty { path.removeLast() } } label: {
                Label(GameStrings.text("common.back"), systemImage: "chevron.left").frame(minHeight: 44)
            }
            .foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("profileSectionBackButton")
        }
    }

    private var normalizedPlayerNameDraft: String? {
        PlayerNameRules.normalized(playerNameDraft)
    }

    private var canSavePlayerName: Bool {
        !isSavingPlayerName && !store.isBusy && normalizedPlayerNameDraft != nil
            && normalizedPlayerNameDraft != profile.name
    }

    private var canResetPlayerName: Bool {
        !isSavingPlayerName && !store.isBusy && (profile.name != nil || !playerNameDraft.isEmpty)
    }

    private var playerNamePage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(GameStrings.text("playerName.hint"))
                    .font(.subheadline).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    Text(GameStrings.text("playerName.fieldLabel")).font(.headline)
                    TextField(GameStrings.text("playerName.placeholder"), text: $playerNameDraft)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        // Keep marked Chinese input untouched. Validation and
                        // counting use a derived value; only a saved name is trimmed.
                        .disabled(isSavingPlayerName)
                        .focused($playerNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { playerNameFieldFocused = false }
                        .padding(14)
                        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel(GameStrings.text("playerName.fieldLabel"))
                        .accessibilityIdentifier("playerNameField")

                    HStack(alignment: .top, spacing: 12) {
                        Text(GameStrings.text(normalizedPlayerNameDraft == nil && !playerNameDraft.isEmpty
                                              ? "playerName.invalid" : "playerName.unsavedHint"))
                            .font(.footnote).foregroundStyle(RoomTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("playerNameValidation")
                            .accessibilityValue(normalizedPlayerNameDraft == nil ? "invalid" : "valid")
                        Spacer(minLength: 0)
                        Text(GameStrings.format("playerName.count",
                            playerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).count,
                            PlayerNameRules.maximumLength))
                            .font(.footnote.monospacedDigit()).foregroundStyle(RoomTheme.secondary)
                            .fixedSize()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(GameStrings.text("playerName.preview"))
                            .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                        Text(verbatim: normalizedPlayerNameDraft ?? store.playerDisplayName)
                            .font(.title2.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("playerNamePreview")
                            .accessibilityValue(Text(verbatim: normalizedPlayerNameDraft ?? store.playerDisplayName))
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.paleMint.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))

                    Button { savePlayerName(reset: false) } label: {
                        Text(GameStrings.text(isSavingPlayerName ? "common.saving" : "playerName.save"))
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MintButtonStyle())
                    .disabled(!canSavePlayerName)
                    .opacity(canSavePlayerName ? 1 : 0.45)
                    .accessibilityIdentifier("playerNameSaveButton")

                    Button { savePlayerName(reset: true) } label: {
                        Text(GameStrings.text("playerName.reset"))
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(!canResetPlayerName)
                    .opacity(canResetPlayerName ? 1 : 0.45)
                    .accessibilityIdentifier("playerNameResetButton")

                    if let playerNameStatusKey {
                        Text(GameStrings.text(playerNameStatusKey))
                            .font(.footnote.weight(.medium)).foregroundStyle(RoomTheme.darkMint)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("playerNameStatus")
                            .accessibilityValue(playerNameStatusKey)
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            }
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("playerNameScroll")
        .scrollDismissesKeyboard(.interactively)
        .background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("playerName.title"))
        .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    guard !isSavingPlayerName else { return }
                    playerNameFieldFocused = false
                    if !path.isEmpty { path.removeLast() }
                } label: {
                    Label(GameStrings.text("common.back"), systemImage: "chevron.left")
                        .frame(minHeight: 44)
                }
                .foregroundStyle(RoomTheme.darkMint).disabled(isSavingPlayerName)
                .accessibilityIdentifier("playerNameBackButton")
            }
        }
        .onAppear {
            playerNameDraft = profile.name ?? ""
            savedPlayerNameDraft = playerNameDraft
            playerNameStatusKey = nil
        }
        .onChange(of: playerNameDraft) { _, value in
            if value != savedPlayerNameDraft || playerNameStatusKey == "playerName.saveFailed" {
                playerNameStatusKey = nil
            }
        }
    }

    private func savePlayerName(reset: Bool) {
        guard !isSavingPlayerName, !store.isBusy else { return }
        let proposed = reset ? nil : normalizedPlayerNameDraft
        guard reset || proposed != nil else { return }
        isSavingPlayerName = true
        playerNameFieldFocused = false
        playerNameStatusKey = nil
        Task {
            if await store.renamePlayer(to: proposed) {
                savedPlayerNameDraft = profile.name ?? ""
                playerNameDraft = savedPlayerNameDraft
                playerNameStatusKey = reset ? "playerName.resetDone" : "playerName.saved"
            } else {
                // Retain the draft for retry. This page owns the failure message;
                // the public profile continues to show only committed state.
                playerNameStatusKey = "playerName.saveFailed"
            }
            isSavingPlayerName = false
        }
    }

    private var attributes: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(GameStrings.text("player.level")).font(.subheadline)
                Spacer()
                Text(GameStrings.format("career.level", player?.level ?? 1)).font(.title3.weight(.bold))
                    .accessibilityIdentifier("profileLevel").accessibilityValue(Text(verbatim: String(player?.level ?? 1)))
            }
            let required = max(1, WorkCatalog.requiredExperience(forLevel: player?.level ?? 1))
            ProgressView(value: Double(player?.exp ?? 0), total: Double(required)).tint(RoomTheme.mint)
            Text(GameStrings.format("career.exp", player?.exp ?? 0, required))
                .font(.footnote).foregroundStyle(RoomTheme.secondary)
                .accessibilityIdentifier("profileExp").accessibilityValue(Text(verbatim: String(player?.exp ?? 0)))
            Divider()
            statBar("player.stamina", value: player?.stamina ?? 0, symbol: "bolt.fill", tint: RoomTheme.darkMint, id: "profileStamina")
            statBar("player.mood", value: player?.mood ?? 0, symbol: "face.smiling.fill", tint: RoomTheme.gold, id: "profileMood")
            HStack {
                smallStat("player.gold", value: "\(player?.gold ?? 0)", id: "profileGold")
                Spacer()
                smallStat("player.completedWorkTitle", value: "\(player?.completedWorkCount ?? 0)", id: "profileCompletedWork")
            }.padding(.top, 4)
        }
        .padding(20).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
    }

    private var wardrobe: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GameStrings.format("player.equippedCount", profile.equipped.count, slots.count))
                .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
                .accessibilityIdentifier("profileEquippedCount").accessibilityValue("\(profile.equipped.count)")
            Text(GameStrings.text("gear.hint")).font(.footnote).foregroundStyle(RoomTheme.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(slots, id: \.self) { slot in
                    Button { path.append(.equipment(slot)) } label: { slotTile(slot) }
                        .buttonStyle(.plain).accessibilityIdentifier("equipmentSlot_\(slot.rawValue)")
                        .accessibilityLabel(GameStrings.text("gear.slot.\(slot.rawValue)"))
                        .accessibilityValue(profile.equipped[slot] ?? "none")
                }
            }
            Text(GameStrings.text("player.starterGift")).font(.footnote).foregroundStyle(RoomTheme.secondary)
            if PlayerCatalog.starterEquipmentIDs.allSatisfy(profile.ownedEquipmentIDs.contains) {
                Button { store.equipStarterSet() } label: {
                    Label(GameStrings.text(starterSetEquipped ? "gear.equipped" : "player.equipAll"),
                          systemImage: starterSetEquipped ? "checkmark.circle.fill" : "sparkles")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle()).disabled(store.isBusy || starterSetEquipped)
                .accessibilityIdentifier("profileEquipAllButton")
            }
        }
        .padding(20).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
    }

    private func slotTile(_ slot: EquipmentSlot) -> some View {
        let item = profile.equipped[slot].flatMap(PlayerCatalog.item(id:))
        return VStack(spacing: 8) {
            Text(GameStrings.text("gear.slot.\(slot.rawValue)")).font(.caption.weight(.semibold))
            GameIcon(asset: item?.displayAssetName ?? "", symbol: slotSymbol(slot), size: 66, tint: RoomTheme.secondary.opacity(0.45))
            Text(item.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
                .font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                .frame(minHeight: 36)
        }
        .padding(10).frame(maxWidth: .infinity)
        .background(item == nil ? RoomTheme.cream : RoomTheme.paleMint.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            if item != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(RoomTheme.darkMint).padding(8) }
        }
    }

    private var bonusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            bonusRow("player.bonus.duration", amount: bonuses.durationReductionPercent, id: "profileDurationBonus")
            bonusRow("player.bonus.stamina", amount: bonuses.staminaReductionPercent, id: "profileStaminaBonus")
            bonusRow("player.bonus.mood", amount: bonuses.moodReductionPercent, id: "profileMoodBonus")
            Text(GameStrings.text(profile.equipped.isEmpty ? "player.noBonuses" : "player.bonus.hint"))
                .font(.footnote).foregroundStyle(RoomTheme.secondary)
            Text(GameStrings.text("player.nextShiftHint")).font(.footnote).foregroundStyle(RoomTheme.secondary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.paleMint.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
    }

    private var avatarPicker: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text(GameStrings.text("player.avatar.hint")).font(.subheadline).foregroundStyle(RoomTheme.secondary)
                HStack(spacing: 4) {
                    genderButton(nil, key: "all", identifier: "avatarFilterAll")
                    genderButton(.male, key: "male", identifier: "avatarFilterMale")
                    genderButton(.female, key: "female", identifier: "avatarFilterFemale")
                }.padding(4).background(RoomTheme.paleMint.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
                Text(avatar.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("player.avatar.unselected"))
                    .font(.footnote).foregroundStyle(RoomTheme.darkMint)
                    .accessibilityIdentifier("avatarSelectedID").accessibilityValue(profile.avatarID ?? "none")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(PlayerCatalog.avatars.filter { avatarGender == nil || $0.gender == avatarGender }) { candidate in
                        Button { store.selectAvatar(candidate.id) } label: {
                            VStack(spacing: 10) {
                                Image(candidate.assetName).resizable().scaledToFit().frame(height: 162).accessibilityHidden(true)
                                Text(GameStrings.text(candidate.nameKey)).font(.subheadline.weight(.bold))
                                Text(GameStrings.text(candidate.detailKey)).font(.caption).foregroundStyle(RoomTheme.secondary)
                                Label(GameStrings.text(profile.avatarID == candidate.id ? "player.selected" : "player.selectAvatar"),
                                      systemImage: profile.avatarID == candidate.id ? "checkmark.circle.fill" : "circle")
                                    .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
                            }
                            .multilineTextAlignment(.center).padding(14).frame(maxWidth: .infinity)
                            .background(profile.avatarID == candidate.id ? RoomTheme.paleMint : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain).disabled(store.isBusy)
                        .accessibilityIdentifier("avatarSelect_\(candidate.id)")
                        .accessibilityLabel(GameStrings.text(candidate.nameKey))
                        .accessibilityAddTraits(profile.avatarID == candidate.id ? .isSelected : [])
                    }
                }
            }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("avatarPickerScroll").background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("player.avatar.title"))
        .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .toolbar { backButton }
    }

    private func equipmentPicker(_ slot: EquipmentSlot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(GameStrings.text("player.nextShiftHint")).font(.subheadline).foregroundStyle(RoomTheme.secondary)
                let equipped = profile.equipped[slot].flatMap(PlayerCatalog.item(id:))
                Label(equipped.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"), systemImage: "checkmark.circle")
                    .font(.headline).foregroundStyle(RoomTheme.darkMint)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(equipped.map { GameStrings.text($0.nameKey) } ?? GameStrings.text("gear.empty"))
                    .accessibilityIdentifier("equippedItem_\(slot.rawValue)").accessibilityValue(equipped?.id ?? "none")
                let items = PlayerCatalog.equipment.filter { $0.slot == slot && profile.ownedEquipmentIDs.contains($0.id) }
                if items.isEmpty { Text(GameStrings.text("gear.noItems")).foregroundStyle(RoomTheme.secondary) }
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 16) {
                        GameIcon(asset: item.displayAssetName, symbol: slotSymbol(slot), size: 140, tint: RoomTheme.darkMint)
                            .frame(maxWidth: .infinity)
                        Text(GameStrings.text(item.nameKey)).font(.title2.weight(.bold))
                        Text(GameStrings.text(item.detailKey)).font(.subheadline).foregroundStyle(RoomTheme.secondary)
                        if item.bonuses.durationReductionPercent > 0 { bonusRow("player.bonus.duration", amount: item.bonuses.durationReductionPercent) }
                        if item.bonuses.staminaReductionPercent > 0 { bonusRow("player.bonus.stamina", amount: item.bonuses.staminaReductionPercent) }
                        if item.bonuses.moodReductionPercent > 0 { bonusRow("player.bonus.mood", amount: item.bonuses.moodReductionPercent) }
                        if equipped?.id == item.id {
                            Button { store.unequipSlot(slot) } label: {
                                Text(GameStrings.text("gear.unequip")).font(.headline).frame(maxWidth: .infinity)
                            }.buttonStyle(SoftButtonStyle()).disabled(store.isBusy)
                                .accessibilityIdentifier("unequipSlot_\(slot.rawValue)")
                        } else {
                            Button { store.equipItem(item.id) } label: {
                                Text(GameStrings.text("gear.equip")).font(.headline).frame(maxWidth: .infinity)
                            }.buttonStyle(MintButtonStyle()).disabled(store.isBusy)
                                .accessibilityIdentifier("equipItem_\(item.id)")
                        }
                    }.padding(20).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
                }
            }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("equipmentScroll").background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("gear.slot.\(slot.rawValue)"))
        .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .toolbar { backButton }
    }

    private var backButton: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { path.removeLast() } label: {
                Label(GameStrings.text("common.back"), systemImage: "chevron.left")
            }.foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier("profileBackButton")
        }
    }

    private func genderButton(_ gender: AvatarGender?, key: String, identifier: String) -> some View {
        Button { avatarGender = gender } label: {
            Text(GameStrings.text("gender.\(key)")).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(avatarGender == gender ? RoomTheme.paper : .clear, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
            .accessibilityAddTraits(avatarGender == gender ? .isSelected : [])
    }

    private func statBar(_ key: String, value: Int, symbol: String, tint: Color, id: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Label(GameStrings.text(key), systemImage: symbol).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(value) / 100").font(.subheadline.weight(.bold)).monospacedDigit()
                    .accessibilityIdentifier(id).accessibilityValue("\(value)")
            }
            ProgressView(value: Double(value), total: 100).tint(tint)
        }
    }

    private func smallStat(_ key: String, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(GameStrings.text(key)).font(.caption).foregroundStyle(RoomTheme.secondary)
            Text(value).font(.title3.weight(.bold)).accessibilityIdentifier(id).accessibilityValue(Text(verbatim: value))
        }
    }

    private func bonusRow(_ key: String, amount: Int, id: String = "") -> some View {
        Text(GameStrings.format(key, amount)).font(.subheadline.weight(.semibold))
            .foregroundStyle(RoomTheme.darkMint)
            .accessibilityIdentifier(id).accessibilityValue("\(amount)")
    }

    private var starterSetEquipped: Bool {
        PlayerCatalog.starterEquipmentIDs.allSatisfy { id in
            guard let item = PlayerCatalog.item(id: id) else { return false }
            return profile.equipped[item.slot] == id
        }
    }

    private var statusValue: String { player?.activeWork != nil ? "working" : player?.activeSleep != nil ? "sleeping" : "idle" }
    private var statusKey: String { "player.status.\(statusValue)" }
    private var statusSymbol: String { player?.activeWork != nil ? "briefcase.fill" : player?.activeSleep != nil ? "moon.zzz.fill" : "sun.max.fill" }
    private func slotSymbol(_ slot: EquipmentSlot) -> String {
        switch slot { case .head: "hat.cap.fill"; case .body: "tshirt.fill"; case .feet: "shoe.fill"; case .accessory: "key.fill" }
    }
}
