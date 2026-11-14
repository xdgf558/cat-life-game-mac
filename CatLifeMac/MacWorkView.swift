import SwiftUI
import CatGameCore

@MainActor
struct MacWorkView: View {
    let store: GameStore
    var onHome: () -> Void = {}
    var preferences: MacPreferences? = nil
    var exits = MacRecoveryExits()
    var onTown: (() -> Void)? = nil
    @State private var selectedID = WorkCatalog.all[0].id
    @State private var confirmsCancellation = false
    @State private var canceling = false
    @State private var showsRest = false
    /// Points a rice ball would waste, while its overflow confirmation is open.
    @State private var riceBallWaste: Int?

    private var selected: WorkJob { WorkCatalog.job(id: selectedID) ?? WorkCatalog.all[0] }
    private var active: ActiveWork? { store.snapshot?.player.activeWork }
    private var displayed: WorkJob { active.flatMap { WorkCatalog.job(id: $0.jobID) } ?? selected }
    private var quote: WorkQuote? {
        if let active { return active.quote }
        return store.snapshot.flatMap { GameEngine.workQuote(for: $0.player, jobID: selectedID) }
    }
    private var mayStart: Bool {
        guard let state = store.snapshot else { return false }
        return !store.isBusy && active == nil && state.player.activeSleep == nil && state.player.activeNap == nil
            && state.player.level >= selected.unlockLevel && state.player.stamina >= (quote?.staminaCost ?? selected.staminaCost)
    }

    var body: some View {
        VStack(spacing: 14) {
            MacPlaceBanner(store: store, place: .work, height: 132, onTown: onTown) { bannerStats }
            HStack(alignment: .top, spacing: 14) {
                jobs.frame(width: 260)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                summary.frame(width: 260)
            }
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded))
        .foregroundStyle(RoomTheme.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macWorkPage")
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacContentCommand"))) { note in
            guard !confirmsCancellation, !canceling, !showsRest, let raw = note.object as? String, let command = MacCommand(rawValue: raw) else { return }
            switch command {
            case .listUp: moveSelection(-1)
            case .listDown: moveSelection(1)
            case .confirm: if active != nil { onHome() } else if mayStart { store.startWork(jobID: selected.id) }
            default: break
            }
        }
        .sheet(isPresented: $showsRest) {
            NavigationStack {
                WorkRestView(store: store)
                    .safeAreaInset(edge: .top, spacing: 0) { SaveStatusBanner(store: store) }
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button(GameStrings.text("common.done")) { showsRest = false }
                            .keyboardShortcut(.cancelAction).disabled(store.isBusy)
                            .accessibilityIdentifier("macWorkRestClose")
                    } }
            }.frame(width: 600, height: 640)
                .interactiveDismissDisabled(store.isBusy)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("macWorkRestSheet")
        }
        .onChange(of: store.saveSceneGeneration) { _, _ in showsRest = false }
        .confirmationDialog(GameStrings.format("recover.wasteHint", riceBallWaste ?? 0),
                            isPresented: Binding(get: { riceBallWaste != nil }, set: { if !$0 { riceBallWaste = nil } })) {
            Button(GameStrings.text("recover.use.anyway")) { riceBallWaste = nil; store.usePlayerSupply(.riceBall, allowingWaste: true) }
            Button(GameStrings.text("recover.use.keep"), role: .cancel) { riceBallWaste = nil }
        }
        .confirmationDialog(GameStrings.text("mac.work.cancelTitle"), isPresented: $confirmsCancellation) {
            Button(GameStrings.text("mac.work.cancel"), role: .destructive) {
                canceling = true
                Task { _ = await store.cancelWork(); canceling = false }
            }
        } message: { Text(GameStrings.text("mac.work.cancelDetail")) }
    }

    private var jobs: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(GameStrings.text("mac.work.jobs"), systemImage: "briefcase.fill").font(.system(size: 14, weight: .heavy))
                Spacer()
                Button { moveSelection(-1) } label: { Text(keyLabel(.listUp)) }
                    .help(GameStrings.text("mac.content.previous"))
                    .accessibilityLabel(GameStrings.text("mac.content.previous"))
                Button { moveSelection(1) } label: { Text(keyLabel(.listDown)) }
                    .help(GameStrings.text("mac.content.next"))
                    .accessibilityLabel(GameStrings.text("mac.content.next"))
            }.controlSize(.small)
            ScrollView {
                VStack(spacing: 4) { ForEach(WorkCatalog.all) { job in jobRow(job) } }
            }
        }.macContentCard69(padding: 12).frame(maxHeight: .infinity)
    }

    /// One compact line per job: icon, name, time · stamina, and the reward (or the level it unlocks at).
    private func jobRow(_ job: WorkJob) -> some View {
        let unlocked = (store.snapshot?.player.level ?? 1) >= job.unlockLevel
        let preview = store.snapshot.flatMap { GameEngine.workQuote(for: $0.player, jobID: job.id) }
        let chosen = (active?.jobID ?? selectedID) == job.id
        return Button { selectedID = job.id } label: {
            HStack(spacing: 9) {
                GameIcon(asset: WorkJobPresentation.asset(job.id), symbol: WorkJobPresentation.symbol(job.id), size: 32)
                    .padding(4).background(RoomTheme.wood.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(WorkJobPresentation.name(job.id)).font(.system(size: 13.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                        if WorkJobPresentation.isNew(job.id) {
                            Text(GameStrings.text("jobs.newBadge")).font(.system(size: 8, weight: .heavy))
                                .padding(.horizontal, 4).padding(.vertical, 2).foregroundStyle(.white).background(RoomTheme.friendship, in: Capsule())
                        }
                    }
                    Text(WorkJobPresentation.duration(preview?.durationSeconds ?? job.durationMinutes * 60) + " · " + GameStrings.text("player.stamina") + " −\(preview?.staminaCost ?? job.staminaCost)")
                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(1).minimumScaleFactor(0.75)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if unlocked {
                    Text("+\(job.goldReward)").font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.gold).monospacedDigit()
                } else {
                    Label("Lv\(job.unlockLevel)", systemImage: "lock.fill").font(.system(size: 10.5, weight: .heavy))
                        .foregroundStyle(RoomTheme.secondary).labelStyle(.titleAndIcon)
                        .help(GameStrings.format("career.unlock", job.unlockLevel))
                }
            }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(chosen ? RoomTheme.paleMint.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(chosen ? RoomTheme.mint : .clear, lineWidth: 2))
                .opacity(unlocked ? 1 : 0.6).contentShape(RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain).accessibilityIdentifier("macJob_\(job.id)")
            .accessibilityAddTraits(chosen ? .isSelected : [])
            .accessibilityHint(unlocked ? "" : GameStrings.format("career.unlock", job.unlockLevel))
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let active {
                ScrollView { working(active) }
            } else {
                HStack(spacing: 12) {
                    GameIcon(asset: WorkJobPresentation.asset(displayed.id), symbol: WorkJobPresentation.symbol(displayed.id), size: 40)
                        .frame(width: 52, height: 52)
                        .background(RoomTheme.sky.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(WorkJobPresentation.name(displayed.id)).font(.system(size: 22, weight: .heavy))
                        Text(GameStrings.text("jobs.\(displayed.id).detail")).font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(RoomTheme.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                metrics
                ScrollView {
                    if staminaShort > 0 { lowStamina } else { preview }
                }
            }
            actionBar
        }.macContentCard69(padding: 18)
    }

    /// Today's work at a glance on the scene banner; while working, a live countdown leads.
    private var bannerStats: some View {
        HStack(spacing: 6) {
            if let active {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, active.endsAt.timeIntervalSince(max(context.date, store.snapshot?.meta.lastSyncAt ?? context.date)))
                    let seconds = Int(ceil(remaining))
                    MacBannerChip(text: seconds > 0 ? GameStrings.format("place.work.remaining", MacWorkClock.text(seconds))
                                                    : GameStrings.text("mac.work.v2.settling"),
                                  symbol: "timer", tint: RoomTheme.darkMint)
                }
            }
            MacBannerChip(text: GameStrings.format("place.work.todayCount", store.snapshot?.tasks.dailyWorkCount ?? 0),
                          symbol: "briefcase.fill", tint: RoomTheme.secondary)
            MacBannerChip(text: GameStrings.format("place.work.todayIncome", store.snapshot?.tasks.dailyWorkGold ?? 0),
                          symbol: "dollarsign.circle.fill", tint: RoomTheme.gold)
            let stamina = store.snapshot?.player.stamina ?? 0
            MacBannerChip(text: GameStrings.format("place.work.stamina", stamina), symbol: "bolt.fill",
                          tint: stamina < (quote?.staminaCost ?? selected.staminaCost) ? RoomTheme.coralDeep : RoomTheme.darkMint)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("macWorkBannerStats")
    }

    private func working(_ work: ActiveWork) -> some View {
        // One clock format for the whole run (mm:ss); the ring fills smoothly between one-second ticks.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = max(1, work.endsAt.timeIntervalSince(work.startedAt))
            let remaining = max(0, work.endsAt.timeIntervalSince(max(context.date, store.snapshot?.meta.lastSyncAt ?? context.date)))
            let seconds = Int(ceil(remaining))
            VStack(spacing: 12) {
                ZStack {
                    Circle().stroke(RoomTheme.track, lineWidth: 16)
                    Circle().trim(from: 0, to: max(0.002, min(1, 1 - remaining / duration)))
                        .stroke(RoomTheme.mint, style: StrokeStyle(lineWidth: 16, lineCap: .butt)).rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: seconds)
                    VStack(spacing: 4) {
                        GameIcon(asset: WorkJobPresentation.asset(work.jobID), symbol: WorkJobPresentation.symbol(work.jobID), size: 34)
                        Text(seconds > 0 ? MacWorkClock.text(seconds) : GameStrings.text("mac.work.v2.settling"))
                            .font(.system(size: seconds > 0 ? 40 : 20, weight: .heavy, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(GameStrings.format("mac.work.v2.total", WorkJobPresentation.duration(Int(duration.rounded()))))
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    }.padding(26)
                }.frame(width: 184, height: 184).padding(6)
                    .accessibilityElement(children: .ignore).accessibilityIdentifier("macWorkCountdown")
                    .accessibilityLabel(GameStrings.text("mac.work.inProgress"))
                    .accessibilityValue(MacWorkClock.text(seconds))
                Text(GameStrings.format("mac.work.v2.doing", WorkJobPresentation.name(work.jobID)))
                    .font(.system(size: 21, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                Text(GameStrings.text("mac.work.background")).font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    rewardChip(GameStrings.format("mac.work.v2.goldAfter", work.goldReward), symbol: "dollarsign.circle.fill", tint: RoomTheme.gold)
                    rewardChip("+\(work.expReward) " + GameStrings.text("mac.work.experience"), symbol: "star.fill", tint: RoomTheme.lilac)
                    if preferences?.notificationsEnabled == true {
                        rewardChip(GameStrings.text("mac.work.v2.notifyOn"), symbol: "bell.fill", tint: RoomTheme.darkMint)
                    }
                }
            }.frame(maxWidth: .infinity).padding(.top, 4)
        }
    }
    private func rewardChip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12, weight: .heavy)).foregroundStyle(tint)
            .padding(.horizontal, 11).padding(.vertical, 6).background(tint.opacity(0.13), in: Capsule())
    }

    private var metrics: some View {
        HStack(spacing: 6) {
            metric("mac.work.duration", WorkJobPresentation.duration(quote?.durationSeconds ?? displayed.durationMinutes * 60), "timer", RoomTheme.secondary)
            metric("player.stamina", "−\(quote?.staminaCost ?? displayed.staminaCost)", "bolt.fill", RoomTheme.darkMint)
            metric("player.mood", "−\(quote?.moodCost ?? displayed.moodCost)", "face.smiling.fill", RoomTheme.friendshipDeep)
            metric("mac.work.gold", "+\(active?.goldReward ?? displayed.goldReward)", "dollarsign.circle.fill", RoomTheme.gold)
            metric("mac.work.experience", "+\(active?.expReward ?? displayed.expReward)", "star.fill", RoomTheme.lilac)
        }
    }

    private func metric(_ key: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 16, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Label(GameStrings.text(key), systemImage: symbol).font(.system(size: 10.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                .opacity(0.85)
        }.padding(.vertical, 9).padding(.horizontal, 4).frame(maxWidth: .infinity)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameStrings.text("mac.work.after")).font(.system(size: 13.5, weight: .heavy))
            HStack {
                Label("\(store.snapshot?.player.stamina ?? 0) → \(max(0, (store.snapshot?.player.stamina ?? 0) - (quote?.staminaCost ?? selected.staminaCost)))", systemImage: "bolt.fill")
                Spacer()
                Label(GameStrings.format("mac.work.rewardUpTo", selected.goldReward), systemImage: "dollarsign.circle.fill")
            }.font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            Text(GameStrings.text("mac.work.background")).font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var actionBar: some View {
        if active != nil {
            HStack(spacing: 12) {
                Button(GameStrings.text("mac.work.cancel")) { confirmsCancellation = true }
                    .buttonStyle(SoftButtonStyle()).disabled(store.isBusy || canceling)
                    .accessibilityIdentifier("macCancelWork")
                Button(GameStrings.text("mac.work.waitAtHome"), action: onHome)
                    .buttonStyle(MintButtonStyle()).accessibilityIdentifier("macWorkWaitAtHome")
            }
        } else {
            if !mayStart && staminaShort == 0 { Text(startHint).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep) }
            Button { store.startWork(jobID: selected.id) } label: {
                HStack {
                    Image(systemName: staminaShort > 0 ? "bolt.slash.fill" : "briefcase.fill")
                    Text(staminaShort > 0 ? GameStrings.format("work.low.button", staminaShort) : GameStrings.text("work.start"))
                    Text(keyLabel(.confirm)).font(.caption.monospaced()).padding(5).background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }.frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).disabled(!mayStart)
                .accessibilityIdentifier("macStartWork")
        }
    }

    private var startHint: String {
        if (store.snapshot?.player.level ?? 1) < selected.unlockLevel { return GameStrings.format("career.unlock", selected.unlockLevel) }
        if store.snapshot?.player.activeSleep != nil { return GameStrings.text("work.sleeping") }
        if store.snapshot?.player.activeNap != nil { return GameStrings.text("work.napping") }
        return GameStrings.format("career.lowStamina", quote?.staminaCost ?? selected.staminaCost)
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 10) {
                recoveryToday
                equipment
                latest
            }.padding(.bottom, 4)
        }.scrollIndicators(.never)
    }

    private var latest: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(GameStrings.text("mac.work.latest"), systemImage: "clock.arrow.circlepath").font(.system(size: 13.5, weight: .heavy))
            if let result = store.snapshot?.player.lastWorkResult {
                HStack(alignment: .firstTextBaseline) {
                    Text(WorkJobPresentation.name(result.jobID)).font(.system(size: 13, weight: .heavy)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(result.completedAt, style: .date).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                }
                HStack(spacing: 6) {
                    rewardChip("+\(result.goldReward)", symbol: "dollarsign.circle.fill", tint: RoomTheme.gold)
                    rewardChip("+\(result.expReward)", symbol: "star.fill", tint: RoomTheme.lilac)
                }
            } else {
                Text(GameStrings.text("mac.work.noResult")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            }
        }.macContentCard69(padding: 12)
    }

    /// Stamina still missing for the selected, unlocked job (0 when it can be afforded or is locked).
    private var staminaShort: Int {
        guard let player = store.snapshot?.player, active == nil, player.level >= selected.unlockLevel else { return 0 }
        return max(0, (quote?.staminaCost ?? selected.staminaCost) - player.stamina)
    }
    private var lighterJob: WorkJob? {
        guard let player = store.snapshot?.player else { return nil }
        return WorkCatalog.all.filter { job in
            job.id != selected.id && player.level >= job.unlockLevel
                && (GameEngine.workQuote(for: player, jobID: job.id)?.staminaCost ?? job.staminaCost) <= player.stamina
        }.max { $0.goldReward < $1.goldReward }
    }
    private var lowStamina: some View {
        let snapshot = store.snapshot
        let player = snapshot?.player ?? PlayerState(staminaUpdatedAt: .now)
        let cost = quote?.staminaCost ?? selected.staminaCost
        let left = snapshot?.suppliesLeftToday ?? 0
        let riceBalls = player.carried(.riceBall)
        let riceBall = PlayerSupplyCatalog.definition(.riceBall)
        return VStack(alignment: .leading, spacing: 9) {
            Label(GameStrings.format("work.low.title", cost, player.stamina), systemImage: "bolt.trianglebadge.exclamationmark.fill")
                .font(.system(size: 13.5, weight: .heavy)).foregroundStyle(RoomTheme.coralDeep)
                .fixedSize(horizontal: false, vertical: true)
            MacCapsuleProgress(value: Double(player.stamina), total: Double(max(1, cost)), tint: RoomTheme.coral).frame(height: 7)
            Text(GameStrings.text("work.low.options")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
            if left > 0 {
                if riceBalls > 0 {
                    option("fork.knife", RoomTheme.gold, GameStrings.format("work.low.eat", riceBall.effect.stamina),
                           GameStrings.format("work.low.eatDetail", riceBalls), badge: GameStrings.text("work.low.fastest")) { eatRiceBall() }
                } else {
                    option("cart.fill", RoomTheme.gold, GameStrings.text("work.low.buy"),
                           GameStrings.format("work.low.buyDetail", riceBall.price, riceBall.effect.stamina), badge: nil, action: exits.shop)
                }
            }
            if snapshot?.napUsedToday != true && player.activeNap == nil {
                option("cup.and.saucer.fill", RoomTheme.lilac, GameStrings.text("recover.exit.cafe"),
                       GameStrings.format("recover.exit.cafeDetail", Int(CafeCatalog.napDuration / 60), CafeCatalog.napPrice), badge: nil, action: exits.cafe)
            }
            option("moon.zzz.fill", RoomTheme.darkMint, GameStrings.text("recover.exit.rest"), GameStrings.text("recover.exit.restDetail"), badge: nil) { showsRest = true }
            }
            if let lighter = lighterJob {
                Button { selectedID = lighter.id } label: {
                    Label(GameStrings.format("work.low.lighter", WorkJobPresentation.name(lighter.id)), systemImage: "arrow.down.forward.circle")
                        .font(.caption.weight(.bold))
                }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paleCoral.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain).accessibilityIdentifier("macWorkLowStamina")
    }
    private func option(_ symbol: String, _ tint: Color, _ title: String, _ detail: String, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                    .frame(width: 30, height: 30).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title).font(.system(size: 12.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                        if let badge {
                            Text(badge).font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).lineLimit(1)
                                .padding(.horizontal, 5).padding(.vertical, 1).background(RoomTheme.coral, in: Capsule())
                        }
                    }
                    Text(detail).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
            }.padding(8).frame(maxWidth: .infinity)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 12)).contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(store.isBusy).help(detail)
    }
    /// Overflow goes through the same explicit confirm as the bag and the top-bar popover.
    private func eatRiceBall() {
        guard !store.isBusy, let player = store.snapshot?.player else { return }
        let effect = PlayerSupplyCatalog.definition(.riceBall).effect
        let waste = effect.total - effect.applied(to: player).total
        if waste > 0 { riceBallWaste = waste } else { store.usePlayerSupply(.riceBall) }
    }
    /// Today's supplies, the café nap and the rest button in one card.
    private var recoveryToday: some View {
        let snapshot = store.snapshot
        return VStack(alignment: .leading, spacing: 8) {
            Label(GameStrings.text("work.today.recovery"), systemImage: "heart.circle.fill").font(.system(size: 13.5, weight: .heavy))
            MacRecoveryDots(used: snapshot?.suppliesUsedToday ?? 0)
            Label(GameStrings.text(snapshot?.player.activeNap != nil ? "recover.exit.cafeNapping"
                                   : snapshot?.napUsedToday == true ? "recover.exit.cafeUsed" : "cafe.napAvailable"),
                  systemImage: "cup.and.saucer.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.lilac)
                .fixedSize(horizontal: false, vertical: true)
            Button { showsRest = true } label: {
                Label(GameStrings.text("work.rest.open"), systemImage: snapshot?.player.activeSleep == nil ? "moon.stars.fill" : "sun.max.fill")
                    .font(.system(size: 13, weight: .heavy)).frame(maxWidth: .infinity)
            }.buttonStyle(SoftButtonStyle()).accessibilityIdentifier("macWorkRest")
        }.macContentCard69(padding: 12)
    }

    /// The outfit's combined bonus up top, then one small icon per worn piece (hover for its effect).
    private var equipment: some View {
        let profile = store.snapshot?.player.profile
        let worn = EquipmentSlot.allCases.compactMap { slot in profile?.equipped[slot].flatMap(PlayerCatalog.item(id:)) }
        let total = profile.map(PlayerCatalog.bonuses(for:))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(GameStrings.text("mac.work.equipment"), systemImage: "tshirt.fill").font(.system(size: 13.5, weight: .heavy))
                Spacer(minLength: 4)
                Button(GameStrings.text("bag.dressUp") + " ›") { exits.profile() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    .accessibilityIdentifier("macWorkDressUp")
            }
            if worn.isEmpty {
                Text(GameStrings.text("mac.work.noEquipment")).font(.system(size: 11, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let total {
                    HStack(spacing: 5) {
                        bonusFigure("mac.profile.duration", total.durationReductionPercent)
                        bonusFigure("mac.profile.stamina", total.staminaReductionPercent)
                        bonusFigure("mac.profile.mood", total.moodReductionPercent)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(worn, id: \.id) { item in
                        GameIcon(asset: item.displayAssetName, symbol: "tshirt.fill", size: 30)
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 10))
                            .help(GameStrings.text(item.nameKey) + " · " + (MacProfilePage.bonusText(item.bonuses) ?? GameStrings.text(item.detailKey)))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(GameStrings.text(item.nameKey))
                            .accessibilityValue(MacProfilePage.bonusText(item.bonuses) ?? "")
                    }
                }
            }
        }.macContentCard69(padding: 12)
    }

    private func bonusFigure(_ key: String, _ value: Int) -> some View {
        VStack(spacing: 1) {
            Text(value > 0 ? "−\(value)%" : "—").font(.system(size: 14, weight: .heavy)).monospacedDigit()
                .foregroundStyle(value > 0 ? RoomTheme.darkMint : RoomTheme.secondary)
            Text(GameStrings.text(key)).font(.system(size: 9.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }.padding(.vertical, 6).frame(maxWidth: .infinity)
            .background(RoomTheme.paleMint.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .combine)
    }

    private func keyLabel(_ command: MacCommand) -> String { (preferences?.binding(for: command) ?? command.defaultBinding).label }

    private func moveSelection(_ delta: Int) {
        let index = WorkCatalog.all.firstIndex { $0.id == selectedID } ?? 0
        selectedID = WorkCatalog.all[min(WorkCatalog.all.count - 1, max(0, index + delta))].id
    }
}

extension View {
    func macContentCard69(padding: CGFloat = 18) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white, lineWidth: 2))
            .compositingGroup()
            .shadow(color: RoomTheme.ink.opacity(0.09), radius: 0, y: 4)
    }
}

enum MacWorkClock {
    static func text(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%02d:%02d", value / 60, value % 60)
    }
}
