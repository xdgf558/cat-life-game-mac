#if os(macOS)
import SwiftUI
import CatGameCore

/// Desktop cat profile (from the room, the cats page or `I`) in one wide sheet instead of the
/// phone's long scroll. Left: who the cat is, companion, growth and the six care stats.
/// Right: little habits, memories and the pinned guide (shared `CatHabitsSection`, compact).
/// Rename, growth and health open in place under a back bar, so the sheet keeps one Done button.
@MainActor
struct MacCatProfileView: View {
    @Bindable var store: GameStore
    let catID: String
    let close: () -> Void

    private enum Nested { case rename, growth, health }
    @State private var nested: Nested?
    @State private var isSaving = false
    @State private var selectionFailed = false
    private var cat: CatState? { store.snapshot?.cats.first { $0.id == catID } }
    private var isCompanion: Bool { store.cat?.id == catID }

    var body: some View {
        Group {
            if let nested { nestedPage(nested) }
            else if let cat { overview(cat) }
            else {
                Text(GameStrings.text("catProfile.missing")).foregroundStyle(RoomTheme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                SaveStatusBanner(store: store)
                if let toast = store.toast, !toast.isEmpty {
                    Text(toast).font(.footnote).multilineTextAlignment(.center)
                        .padding(10).frame(maxWidth: .infinity)
                        .background(RoomTheme.paper).accessibilityIdentifier("sheetToast")
                }
            }
        }
        .saveRecoveryAlert(store: store, isActive: !store.isPresentingAdoptionConfirmation
                           && !store.isPresentingHabitGuide && !store.isPresentingHabitMemory)
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .background(RoomTheme.cream)
        .onChange(of: store.saveSceneGeneration) { _, _ in nested = nil }
        .accessibilityIdentifier("macCatProfile")
    }

    // MARK: Overview

    private func overview(_ cat: CatState) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollView {
                VStack(spacing: 10) {
                    identity(cat)
                    companion
                    growthRow
                    stats(cat)
                }.padding(.bottom, 4)
            }
            .scrollIndicators(.never).frame(width: 316)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) { CatHabitsSection(store: store, cat: cat, compact: true) }.padding(.bottom, 4)
                }
                .task {
                    guard store.inspectedMemoryCatID == catID else { return }
                    await Task.yield()
                    proxy.scrollTo("catMemoriesAnchor", anchor: .top)
                    store.inspectedMemoryCatID = nil
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
    }

    private func identity(_ cat: CatState) -> some View {
        HStack(spacing: 12) {
            GameIcon(asset: CatArtwork.asset("cat-idle", appearance: cat.appearance), symbol: "cat.fill", size: 76, tint: RoomTheme.gold)
                .background(RoomTheme.wood.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(verbatim: GameStrings.catName(cat)).font(.system(size: 21, weight: .heavy))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityIdentifier("catProfileName").accessibilityValue(Text(verbatim: GameStrings.catName(cat)))
                    Spacer(minLength: 0)
                    Button { nested = .rename } label: {
                        Image(systemName: "pencil").font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                            .frame(width: 28, height: 28).background(RoomTheme.paleMint.opacity(0.75), in: Circle())
                    }
                    .buttonStyle(.plain).disabled(isSaving)
                    .help(GameStrings.text("catName.edit"))
                    .accessibilityLabel(GameStrings.text("catName.edit")).accessibilityIdentifier("catRenameButton")
                }
                HStack(spacing: 6) {
                    CatCollectionCoatPill(appearance: cat.appearance)
                    if isCompanion {
                        Label(GameStrings.text("cat.companionActive"), systemImage: "heart.fill")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(RoomTheme.mint, in: Capsule())
                            .fixedSize()
                    }
                }
                Text(CatProfileView.status(for: cat)).font(.system(size: 12.5, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("catProfileStatus")
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 20)
    }

    /// The companion button only shows while this cat isn't the companion; the pill above says so otherwise.
    @ViewBuilder private var companion: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !isCompanion {
                Button {
                    guard !isSaving, !store.isBusy else { return }
                    isSaving = true; selectionFailed = false
                    Task { selectionFailed = !(await store.selectCompanion(catID: catID)); isSaving = false }
                } label: {
                    Label(GameStrings.text(isSaving ? "common.saving" : "cat.companionSelect"), systemImage: "house.fill")
                        .font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle()).disabled(isSaving || store.isBusy)
                .accessibilityIdentifier("catCompanionButton").accessibilityValue("available")
            }
            Text(GameStrings.text(selectionFailed ? "cat.companionFailed" : "cat.companionHint"))
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(selectionFailed ? RoomTheme.coralDeep : RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .accessibilityIdentifier("catCompanionHint").accessibilityValue(selectionFailed ? "failed" : "ready")
        }
    }

    private var growthRow: some View {
        Button { nested = .growth } label: {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                    .frame(width: 32, height: 32).background(RoomTheme.paleMint, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(GameStrings.text("catGrowth.title")).font(.system(size: 13.5, weight: .heavy))
                    Text(GameStrings.text("catGrowth.entryHint")).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            }
            .padding(10).gameCard(cornerRadius: 18).contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain).disabled(isSaving).accessibilityIdentifier("catGrowthEntry")
    }

    private func stats(_ cat: CatState) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            group("catProfile.daily")
            stat("stat.satiety", cat.satiety, tint: RoomTheme.gold, id: "catProfileSatiety")
            stat("stat.cleanliness", cat.cleanliness, tint: RoomTheme.sky, id: "catProfileCleanliness")
            stat("rest.energy", cat.energy, tint: RoomTheme.lilac, id: "catProfileEnergy")
            group("catProfile.wellbeing").padding(.top, 4)
            stat("stat.mood", cat.mood, tint: RoomTheme.coral, id: "catProfileMood")
            stat("stat.bond", cat.intimacy, tint: RoomTheme.friendship, id: "catProfileIntimacy")
            Button { nested = .health } label: {
                HStack(spacing: 6) {
                    stat("stat.health", cat.health, tint: RoomTheme.mint, id: "catProfileHealth")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                        .frame(width: 20, height: 20).background(RoomTheme.paleMint, in: Circle())
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(isSaving)
            .help(GameStrings.text("hospital.profileEntry"))
            .accessibilityLabel(GameStrings.text("hospital.profileEntry")).accessibilityValue("\(cat.health)/100")
            .accessibilityIdentifier("catHealthButton")
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 20)
    }

    private func group(_ key: String) -> some View {
        Text(GameStrings.text(key)).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
    }

    private func stat(_ key: String, _ value: Int, tint: Color, id: String) -> some View {
        HStack(spacing: 8) {
            Text(GameStrings.text(key)).font(.system(size: 12.5, weight: .bold)).frame(width: 52, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.75)
            MacCapsuleProgress(value: Double(value), tint: tint).frame(height: 7)
            Text("\(value)").font(.system(size: 12, weight: .heavy)).monospacedDigit()
                .foregroundStyle(RoomTheme.secondary).frame(width: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(key)).accessibilityValue("\(value)").accessibilityIdentifier(id)
    }

    // MARK: Rename, growth, health

    private func nestedPage(_ nested: Nested) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { self.nested = nil } label: {
                    Label(GameStrings.text("common.back"), systemImage: "chevron.left").font(.system(size: 13, weight: .heavy))
                }
                .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint).disabled(isSaving)
                .accessibilityIdentifier("macCatProfileBack")
                Text(GameStrings.text(title(nested))).font(.system(size: 14, weight: .heavy))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            switch nested {
            case .rename:
                CatNameEditorView(store: store, catID: catID, isSaving: $isSaving)
            case .growth:
                CatGrowthView(store: store, catID: catID, isSaving: $isSaving) {
                    close(); store.inspectedCatID = nil; store.activeSheet = nil
                }
            case .health:
                HospitalCatDetailView(store: store, catID: catID, isSaving: $isSaving) {
                    close(); store.inspectedCatID = nil; store.activeSheet = .work
                }
            }
        }
    }

    private func title(_ nested: Nested) -> String {
        switch nested {
        case .rename: "catName.title"
        case .growth: "catGrowth.title"
        case .health: "hospital.healthDetails"
        }
    }
}
#endif
