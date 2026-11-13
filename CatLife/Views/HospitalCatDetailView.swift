import SwiftUI
import CatGameCore

/// Also used by the cat profile's navigation stack.
@MainActor
struct HospitalCatDetailView: View {
    @Bindable var store: GameStore
    let catID: String
    @Binding var isSaving: Bool
    var onBack: (() -> Void)? = nil
    var onDirectory: (() -> Void)? = nil
    let goToWork: () -> Void
    @State private var treatmentFailed = false
    @State private var recovery: HospitalRecovery?
    @State private var presentationStarted: Date?
    @State private var showsRecovery = false
    @State private var presentationTask: Task<Void, Never>?
    @State private var presentationID = UUID()
    @State private var isVisible = false
    private var cat: CatState? { store.snapshot?.cats.first { $0.id == catID } }

    var body: some View {
        VStack(spacing: 0) {
            if let onBack {
                HospitalHeader(title: recovery == nil ? "hospital.healthDetails" : "hospital.title",
                               back: "hospital.backShort", gold: store.snapshot?.player.gold ?? 0,
                               isSaving: isSaving, action: onBack)
            }
            if let recovery, showsRecovery {
                HospitalRecoveryView(recovery: recovery, home: {
                    store.inspectedCatID = nil
                    store.activeSheet = nil
                }, directory: {
                    if let onDirectory { onDirectory() }
                    else { store.openHospital() }
                })
            } else if isSaving, let cat {
                HospitalTreatingView(cat: cat, started: presentationStarted)
            } else {
                details
            }
        }
        .background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("hospital.healthDetails")).navigationBarTitleDisplayMode(.inline)
        .toolbar(onBack == nil ? .visible : .hidden, for: .navigationBar)
        .onAppear {
            isVisible = true
            if onBack == nil { store.isInspectingHealth = true }
        }
        .onDisappear {
            isVisible = false
            if onBack == nil { store.isInspectingHealth = false }
            presentationID = UUID()
            presentationTask?.cancel()
            isSaving = false
        }
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let cat {
                    identity(cat)
                    if let illness = cat.healthState?.illness {
                        diagnosis(cat, illness: illness)
                        plan(cat, illness: illness)
                    } else {
                        Label(GameStrings.text("hospital.healthy"), systemImage: "checkmark.seal.fill")
                            .font(.headline).foregroundStyle(RoomTheme.darkMint)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading).gameCard()
                            .accessibilityIdentifier("hospitalHealthyState")
                        VStack(alignment: .leading, spacing: 10) {
                            Label(GameStrings.text("hospital.careAdvice"), systemImage: "heart.fill")
                                .font(.subheadline).foregroundStyle(RoomTheme.secondary)
                            if let health = cat.healthState, health.protectedUntil > store.now {
                                Text(GameStrings.text("hospital.protectionHint"))
                                    .font(.footnote.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
                                    .accessibilityIdentifier("hospitalProtectionHint")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).gameCard()
                    }
                    if treatmentFailed {
                        Label(GameStrings.text("hospital.treatmentFailed"), systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.coralDeep)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("hospitalTreatmentStatus")
                    }
                } else {
                    Text(GameStrings.text("catProfile.missing")).foregroundStyle(RoomTheme.secondary)
                        .padding(24).frame(maxWidth: .infinity).accessibilityIdentifier("hospitalMissingCat")
                }
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("hospitalDetailScroll").accessibilityValue(catID)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let cat, let illness = cat.healthState?.illness { treatmentAction(cat, illness: illness) }
        }
    }

    private func identity(_ cat: CatState) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                HospitalCatPortrait(cat: cat, size: 76)
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: GameStrings.catName(cat)).font(.system(size: 24, weight: .heavy))
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("hospitalCatName")
                    HospitalStatusPill(cat: cat, now: store.now)
                        .accessibilityIdentifier("hospitalCondition")
                        .accessibilityValue(cat.healthState?.illness?.rawValue ?? "healthy")
                }
            }
            VStack(spacing: 9) {
                HStack {
                    Label(GameStrings.text("stat.health"), systemImage: "heart.fill")
                        .font(.system(size: 14, weight: .heavy))
                    Spacer(minLength: 8)
                    Text("\(cat.health) / 100").font(.system(size: 14, weight: .heavy)).monospacedDigit()
                }
                HospitalHealthBar(health: cat.health, sick: cat.healthState?.illness != nil)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text("stat.health"))
            .accessibilityValue("\(cat.health)/100").accessibilityIdentifier("hospitalHealth")
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 26)
    }

    private func diagnosis(_ cat: CatState, illness: CatIllness) -> some View {
        let definition = CatHealthCatalog.definition(for: illness)
        let need = HospitalCareNeed(illness: illness)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                GameIconTile(symbol: "stethoscope", tint: RoomTheme.coralDeep, background: RoomTheme.paleCoral, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameStrings.text("hospital.diagnosis")).font(.system(size: 12, weight: .bold))
                        .foregroundStyle(RoomTheme.secondary)
                    Text(GameStrings.text(definition.nameKey)).font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(RoomTheme.coralDeep)
                }
            }
            Text(GameStrings.text(definition.detailKey))
                .font(.system(size: 13, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Image(systemName: need.symbol).foregroundStyle(RoomTheme.coral)
                Text(GameStrings.format("hospital.cause", GameStrings.text(need.nameKey)))
                    .font(.system(size: 12, weight: .heavy))
                ProgressView(value: Double(need.value(cat)), total: 100).tint(RoomTheme.coral)
                Text("\(need.value(cat))").font(.system(size: 12, weight: .heavy)).monospacedDigit()
            }
            .padding(10).background(RoomTheme.cream, in: Capsule())
            .accessibilityElement(children: .combine).accessibilityIdentifier("hospitalCause")
            .accessibilityValue("\(need.rawValue):\(need.value(cat))")
            Label(GameStrings.text("hospital.aftercare.\(illness.rawValue)"), systemImage: "info.circle.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.darkMint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 26)
    }

    private func plan(_ cat: CatState, illness: CatIllness) -> some View {
        let cost = CatHealthCatalog.definition(for: illness).treatmentCost
        let gold = store.snapshot?.player.gold ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(GameStrings.text("hospital.treatment"), systemImage: "cross.case.fill")
                    .font(.system(size: 16, weight: .heavy))
                Spacer(minLength: 8)
                Label("\(cost)", systemImage: "dollarsign.circle.fill")
                    .font(.system(size: 17, weight: .heavy)).foregroundStyle(RoomTheme.gold)
                    .accessibilityLabel(GameStrings.text("hospital.treatmentPrice"))
                    .accessibilityIdentifier("hospitalTreatmentCost").accessibilityValue("\(cost)")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                benefit(GameStrings.text("hospital.benefit.cure"), symbol: "bandage.fill", tint: RoomTheme.coralDeep, background: RoomTheme.paleCoral)
                benefit(GameStrings.format("hospital.benefit.health", CatHealthCatalog.treatedHealth), symbol: "heart.fill", tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                benefit(GameStrings.format("hospital.benefit.protection", Int(CatHealthCatalog.protectionDuration / 3600)), symbol: "checkmark.shield.fill", tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                benefit(GameStrings.text("hospital.benefit.mood"), symbol: "heart.fill", tint: RoomTheme.secondary, background: RoomTheme.gold.opacity(0.2))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(GameStrings.format("shop.balance", gold))
                    .accessibilityIdentifier("hospitalGoldCount").accessibilityValue("\(gold)")
                Spacer(minLength: 8)
                if gold >= cost { Text(GameStrings.format("hospital.balanceAfter", gold - cost)) }
            }
            .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 26)
    }

    private func benefit(_ text: String, symbol: String, tint: Color, background: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11, weight: .heavy))
            .fixedSize(horizontal: false, vertical: true).foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: Capsule())
    }

    private func treatmentAction(_ cat: CatState, illness: CatIllness) -> some View {
        let cost = CatHealthCatalog.definition(for: illness).treatmentCost
        let gold = store.snapshot?.player.gold ?? 0
        return VStack(spacing: 10) {
            if gold < cost {
                Label(GameStrings.format("hospital.shortfall", cost, cost - gold), systemImage: "dollarsign.circle.fill")
                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("hospitalInsufficientGold")
                Button(action: goToWork) {
                    Label(GameStrings.text("hospital.goToWork"), systemImage: "briefcase.fill")
                        .font(.system(size: 17, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(TaskGoldButtonStyle()).disabled(store.isBusy)
                .accessibilityIdentifier("hospitalWorkButton")
            } else {
                Button { treat(cat, illness: illness) } label: {
                    HStack(spacing: 9) {
                        Label(GameStrings.text("hospital.treat"), systemImage: "cross.case.fill")
                        Label("\(cost)", systemImage: "dollarsign.circle.fill")
                            .font(.system(size: 14, weight: .heavy)).padding(.horizontal, 9).padding(.vertical, 3)
                            .background(.white.opacity(0.2), in: Capsule())
                    }.font(.system(size: 17, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle()).disabled(isSaving || store.isBusy)
                .accessibilityIdentifier("hospitalTreatButton")
            }
        }
        .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(RoomTheme.cream, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .compositingGroup()
        .shadow(color: RoomTheme.ink.opacity(0.05), radius: 10, y: -4)
    }

    private func treat(_ before: CatState, illness: CatIllness) {
        guard !isSaving, !store.isBusy else { return }
        isSaving = true
        treatmentFailed = false
        let requestID = presentationID
        Task { @MainActor in
            let completed = await store.treatCat(catID: catID)
            guard isVisible, requestID == presentationID else { return }
            guard completed, let after = cat else {
                treatmentFailed = true
                isSaving = false
                return
            }
            recovery = HospitalRecovery(before: before, after: after, illness: illness,
                                        cost: CatHealthCatalog.definition(for: illness).treatmentCost)
            presentationStarted = Date()
            store.playFeedback(.treatStart)
            // Only presentation is cancellable; leaving never cancels the durable transaction.
            presentationTask = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard isVisible, requestID == presentationID else { return }
                showsRecovery = true
                isSaving = false
                store.playFeedback(.treatDone)
                store.playFeedback(.catPurr)
            }
        }
    }
}
