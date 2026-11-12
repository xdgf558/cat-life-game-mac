import SwiftUI
import CatGameCore

@MainActor
struct CatProfileView: View {
    @Bindable var store: GameStore
    let catID: String
    @Binding var isSaving: Bool
    let health: () -> Void
    let rename: () -> Void
    let growth: () -> Void
    @State private var selectionFailed = false
    private var cat: CatState? { store.snapshot?.cats.first { $0.id == catID } }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 16) {
                if let cat {
                    HStack(spacing: 14) {
                        GameIcon(asset: CatArtwork.asset("cat-idle", appearance: cat.appearance),
                                 symbol: "cat.fill", size: 76, tint: RoomTheme.gold)
                            .background(RoomTheme.wood.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(verbatim: GameStrings.catName(cat))
                                    .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("catProfileName")
                                    .accessibilityValue(Text(verbatim: GameStrings.catName(cat)))
                                Button(action: rename) {
                                    Image(systemName: "pencil").font(.body.weight(.semibold))
                                        .foregroundStyle(RoomTheme.darkMint).frame(width: 44, height: 44)
                                        .background(RoomTheme.paleMint.opacity(0.65), in: Circle())
                                }
                                .buttonStyle(.plain).disabled(isSaving)
                                .accessibilityLabel(GameStrings.text("catName.edit"))
                                .accessibilityIdentifier("catRenameButton")
                            }
                            Text(GameStrings.text("hospital.coat.\(cat.appearance.rawValue)"))
                                .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
                            Text(Self.status(for: cat)).font(.footnote).foregroundStyle(RoomTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("catProfileStatus")
                        }
                    }
                    .padding(16).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
                    Button {
                        guard !isSaving, !store.isBusy else { return }
                        isSaving = true
                        selectionFailed = false
                        Task {
                            selectionFailed = !(await store.selectCompanion(catID: catID))
                            isSaving = false
                        }
                    } label: {
                        Label(GameStrings.text(isSaving ? "common.saving" :
                            (store.cat?.id == catID ? "cat.companionActive" : "cat.companionSelect")),
                              systemImage: store.cat?.id == catID ? "checkmark.circle.fill" : "house.fill")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MintButtonStyle())
                    .disabled(isSaving || store.isBusy || store.cat?.id == catID)
                    .accessibilityIdentifier("catCompanionButton")
                    .accessibilityValue(store.cat?.id == catID ? "active" : "available")
                    Text(GameStrings.text(selectionFailed ? "cat.companionFailed" : "cat.companionHint"))
                        .font(.footnote).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("catCompanionHint").accessibilityValue(selectionFailed ? "failed" : "ready")
                    Button(action: growth) {
                        HStack(spacing: 12) {
                            Image(systemName: "leaf.fill").font(.title2).foregroundStyle(RoomTheme.darkMint)
                                .frame(width: 44, height: 44).background(RoomTheme.paleMint, in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(GameStrings.text("catGrowth.title")).font(.subheadline.weight(.bold))
                                Text(GameStrings.text("catGrowth.entryHint"))
                                    .font(.caption).foregroundStyle(RoomTheme.secondary)
                            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                        }
                        .padding(14).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
                    }
                    .buttonStyle(.plain).disabled(isSaving)
                    .accessibilityIdentifier("catGrowthEntry")
                    CatHabitsSection(store: store, cat: cat)
                    attributeGroup("catProfile.daily") {
                        stat("stat.satiety", value: cat.satiety, identifier: "catProfileSatiety")
                        stat("stat.cleanliness", value: cat.cleanliness, identifier: "catProfileCleanliness")
                        stat("rest.energy", value: cat.energy, identifier: "catProfileEnergy")
                    }
                    attributeGroup("catProfile.wellbeing") {
                        stat("stat.mood", value: cat.mood, identifier: "catProfileMood")
                        stat("stat.bond", value: cat.intimacy, identifier: "catProfileIntimacy")
                        HStack(spacing: 10) {
                            stat("stat.health", value: cat.health, identifier: "catProfileHealth")
                            Button(action: health) {
                                Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                                    .foregroundStyle(RoomTheme.darkMint).frame(width: 44, height: 44)
                                    .background(RoomTheme.paleMint, in: Circle())
                            }
                            .buttonStyle(.plain).disabled(isSaving)
                            .accessibilityLabel(GameStrings.text("hospital.profileEntry"))
                            .accessibilityValue("\(cat.health)/100")
                            .accessibilityIdentifier("catHealthButton")
                        }
                    }
                } else {
                    Text(GameStrings.text("catProfile.missing")).foregroundStyle(RoomTheme.secondary)
                        .padding(24).frame(maxWidth: .infinity)
                }
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(RoomTheme.cream)
        .accessibilityIdentifier("catProfileScroll").accessibilityValue(catID)
        .navigationTitle(GameStrings.text("catProfile.title")).navigationBarTitleDisplayMode(.inline)
        .task {
            guard store.inspectedMemoryCatID == catID else { return }
            await Task.yield()
            guard store.inspectedCatID == catID, store.inspectedMemoryCatID == catID else { return }
            proxy.scrollTo("catMemoriesAnchor", anchor: .top)
            store.inspectedMemoryCatID = nil
        }
        }
    }

    static func status(for cat: CatState) -> String {
        if let illness = cat.healthState?.illness {
            return GameStrings.text(CatHealthCatalog.definition(for: illness).nameKey)
        }
        if cat.activeRest != nil { return GameStrings.format("rest.recovering", cat.energy) }
        if cat.satiety < 50 { return GameStrings.text("cat.hungry") }
        if cat.cleanliness < 40 { return GameStrings.text("cat.cleanNeeded") }
        if cat.mood < 40 { return GameStrings.text("cat.playNeeded") }
        if cat.satiety >= 95 { return GameStrings.text("cat.full") }
        return GameStrings.text("cat.content")
    }

    private func attributeGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(GameStrings.text(title)).font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
            content()
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
    }

    private func stat(_ title: String, value: Int, identifier: String) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(GameStrings.text(title)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(value) / 100").font(.footnote.monospacedDigit()).foregroundStyle(RoomTheme.secondary)
            }
            ProgressView(value: Double(value), total: 100).tint(RoomTheme.mint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(title)).accessibilityValue("\(value)")
        .accessibilityIdentifier(identifier)
    }
}

@MainActor
struct CatNameEditorView: View {
    @Bindable var store: GameStore
    let catID: String
    @Binding var isSaving: Bool
    @State private var draft = ""
    @State private var savedDraft = ""
    @State private var statusKey: String?
    @FocusState private var fieldFocused: Bool

    private var cat: CatState? { store.snapshot?.cats.first { $0.id == catID } }
    private var normalizedDraft: String? { CatNameRules.normalized(draft) }
    private var displayName: String { cat.map(GameStrings.catName) ?? "" }
    private var canSave: Bool {
        !isSaving && !store.isBusy && cat != nil && normalizedDraft != nil && normalizedDraft != cat?.customName
    }
    private var canReset: Bool {
        !isSaving && !store.isBusy && cat != nil && (cat?.customName != nil || !draft.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(GameStrings.text(cat == nil ? "catProfile.missing" : "catName.hint"))
                    .font(.subheadline).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    Text(GameStrings.text("catName.fieldLabel")).font(.headline)
                    TextField(GameStrings.text("catName.placeholder"), text: $draft)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(isSaving || cat == nil).focused($fieldFocused)
                        .submitLabel(.done).onSubmit { fieldFocused = false }
                        .padding(14).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel(GameStrings.text("catName.fieldLabel"))
                        .accessibilityIdentifier("catNameField")
                    HStack(alignment: .top, spacing: 12) {
                        Text(GameStrings.text(normalizedDraft == nil && !draft.isEmpty ? "catName.invalid" : "catName.unsavedHint"))
                            .font(.footnote).foregroundStyle(RoomTheme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("catNameValidation")
                            .accessibilityValue(normalizedDraft == nil ? "invalid" : "valid")
                        Spacer(minLength: 0)
                        Text(GameStrings.format("catName.count", draft.trimmingCharacters(in: .whitespacesAndNewlines).count,
                                                CatNameRules.maximumLength))
                            .font(.footnote.monospacedDigit()).foregroundStyle(RoomTheme.secondary).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(GameStrings.text("catName.preview"))
                            .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                        Text(verbatim: normalizedDraft ?? displayName)
                            .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("catNamePreview")
                            .accessibilityValue(Text(verbatim: normalizedDraft ?? displayName))
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.paleMint.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                    Button { save(reset: false) } label: {
                        Text(GameStrings.text(isSaving ? "common.saving" : "catName.save"))
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MintButtonStyle()).disabled(!canSave).opacity(canSave ? 1 : 0.45)
                    .accessibilityIdentifier("catNameSaveButton")
                    Button { save(reset: true) } label: {
                        Text(GameStrings.text("catName.reset")).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle()).disabled(!canReset).opacity(canReset ? 1 : 0.45)
                    .accessibilityIdentifier("catNameResetButton")
                    if let statusKey {
                        Text(GameStrings.text(statusKey)).font(.footnote.weight(.medium))
                            .foregroundStyle(RoomTheme.darkMint).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("catNameStatus").accessibilityValue(statusKey)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(RoomTheme.cream).scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("catNameScroll")
        .navigationTitle(GameStrings.text("catName.title")).navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draft = cat?.customName ?? ""
            savedDraft = draft
            statusKey = nil
        }
        .onChange(of: draft) { _, value in
            if value != savedDraft || statusKey == "catName.saveFailed" { statusKey = nil }
        }
    }

    private func save(reset: Bool) {
        guard !isSaving, !store.isBusy, cat != nil else { return }
        let proposed = reset ? nil : normalizedDraft
        guard reset || proposed != nil else { return }
        isSaving = true
        fieldFocused = false
        statusKey = nil
        Task {
            if await store.renameCat(id: catID, to: proposed) {
                savedDraft = cat?.customName ?? ""
                draft = savedDraft
                statusKey = reset ? "catName.resetDone" : "catName.saved"
            } else {
                statusKey = "catName.saveFailed"
            }
            isSaving = false
        }
    }
}
