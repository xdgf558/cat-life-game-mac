import SwiftUI
import CatGameCore

@MainActor
struct MacWorkView: View {
    let store: GameStore
    var onHome: () -> Void = {}
    var preferences: MacPreferences? = nil
    @State private var selectedID = WorkCatalog.all[0].id
    @State private var confirmsCancellation = false
    @State private var canceling = false
    @State private var showsRest = false

    private var selected: WorkJob { WorkCatalog.job(id: selectedID) ?? WorkCatalog.all[0] }
    private var active: ActiveWork? { store.snapshot?.player.activeWork }
    private var displayed: WorkJob { active.flatMap { WorkCatalog.job(id: $0.jobID) } ?? selected }
    private var quote: WorkQuote? {
        if let active { return active.quote }
        return store.snapshot.flatMap { GameEngine.workQuote(for: $0.player, jobID: selectedID) }
    }
    private var mayStart: Bool {
        guard let state = store.snapshot else { return false }
        return !store.isBusy && active == nil && state.player.activeSleep == nil
            && state.player.level >= selected.unlockLevel && state.player.stamina >= (quote?.staminaCost ?? selected.staminaCost)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            jobs.frame(width: 280)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            summary.frame(width: 285)
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
        .confirmationDialog(GameStrings.text("mac.work.cancelTitle"), isPresented: $confirmsCancellation) {
            Button(GameStrings.text("mac.work.cancel"), role: .destructive) {
                canceling = true
                Task { _ = await store.cancelWork(); canceling = false }
            }
        } message: { Text(GameStrings.text("mac.work.cancelDetail")) }
    }

    private var jobs: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(GameStrings.text("mac.work.jobs"), systemImage: "briefcase.fill").font(.headline)
                Spacer()
                Button { moveSelection(-1) } label: { Text(keyLabel(.listUp)) }
                    .help(GameStrings.text("mac.content.previous"))
                    .accessibilityLabel(GameStrings.text("mac.content.previous"))
                Button { moveSelection(1) } label: { Text(keyLabel(.listDown)) }
                    .help(GameStrings.text("mac.content.next"))
                    .accessibilityLabel(GameStrings.text("mac.content.next"))
            }
            ScrollView {
                VStack(spacing: 8) { ForEach(WorkCatalog.all) { job in jobRow(job) } }
            }
        }.macContentCard69().frame(maxHeight: .infinity)
    }

    private func jobRow(_ job: WorkJob) -> some View {
        let unlocked = (store.snapshot?.player.level ?? 1) >= job.unlockLevel
        let preview = store.snapshot.flatMap { GameEngine.workQuote(for: $0.player, jobID: job.id) }
        return Button { selectedID = job.id } label: {
            HStack(spacing: 10) {
                GameIcon(asset: WorkJobPresentation.asset(job.id), symbol: WorkJobPresentation.symbol(job.id), size: 44)
                    .padding(6).background(RoomTheme.wood.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Text(WorkJobPresentation.name(job.id)).font(.system(size: 15, weight: .heavy))
                        if WorkJobPresentation.isNew(job.id) {
                            Text(GameStrings.text("jobs.newBadge")).font(.system(size: 8, weight: .heavy))
                                .padding(4).foregroundStyle(.white).background(RoomTheme.friendship, in: Capsule())
                        }
                    }
                    Text(WorkJobPresentation.duration(preview?.durationSeconds ?? job.durationMinutes * 60) + " · " + GameStrings.text("player.stamina") + " −\(preview?.staminaCost ?? job.staminaCost)")
                        .font(.caption).foregroundStyle(RoomTheme.secondary)
                    if !unlocked {
                        Label(GameStrings.format("career.unlock", job.unlockLevel), systemImage: "lock.fill")
                            .font(.caption2).foregroundStyle(RoomTheme.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text("+\(job.goldReward)").font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.gold)
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background((active?.jobID ?? selectedID) == job.id ? RoomTheme.paleMint.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder((active?.jobID ?? selectedID) == job.id ? RoomTheme.mint : .clear, lineWidth: 2))
                .opacity(unlocked ? 1 : 0.55).contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityIdentifier("macJob_\(job.id)")
            .accessibilityAddTraits((active?.jobID ?? selectedID) == job.id ? .isSelected : [])
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView {
                if let active {
                    working(active)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        jobHero
                        Text(WorkJobPresentation.name(displayed.id)).font(.system(size: 28, weight: .heavy))
                        Text(GameStrings.text("jobs.\(displayed.id).detail")).foregroundStyle(RoomTheme.secondary)
                        metrics
                        preview
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            actionBar
        }.macContentCard69(padding: 22)
    }

    private var jobHero: some View {
        GameIcon(asset: WorkJobPresentation.asset(displayed.id), symbol: WorkJobPresentation.symbol(displayed.id), size: 156)
            .frame(maxWidth: .infinity).frame(height: 220)
            .background(RoomTheme.sky.opacity(0.16), in: RoundedRectangle(cornerRadius: 24))
    }

    private func working(_ work: ActiveWork) -> some View {
        // One clock format for the whole run (mm:ss); the ring fills smoothly between one-second ticks.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = max(1, work.endsAt.timeIntervalSince(work.startedAt))
            let remaining = max(0, work.endsAt.timeIntervalSince(max(context.date, store.snapshot?.meta.lastSyncAt ?? context.date)))
            let seconds = Int(ceil(remaining))
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(RoomTheme.track, lineWidth: 26)
                    Circle().trim(from: 0, to: max(0.002, min(1, 1 - remaining / duration)))
                        .stroke(RoomTheme.mint, style: StrokeStyle(lineWidth: 26, lineCap: .butt)).rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: seconds)
                    VStack(spacing: 8) {
                        GameIcon(asset: WorkJobPresentation.asset(work.jobID), symbol: WorkJobPresentation.symbol(work.jobID), size: 54)
                        Text(seconds > 0 ? MacWorkClock.text(seconds) : GameStrings.text("mac.work.v2.settling"))
                            .font(.system(size: seconds > 0 ? 64 : 26, weight: .heavy, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText(countsDown: true)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(GameStrings.format("mac.work.v2.total", WorkJobPresentation.duration(Int(duration.rounded()))))
                            .font(.system(size: 13.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    }.padding(40)
                }.frame(width: 286, height: 286).padding(13)
                    .accessibilityElement(children: .ignore).accessibilityIdentifier("macWorkCountdown")
                    .accessibilityLabel(GameStrings.text("mac.work.inProgress"))
                    .accessibilityValue(MacWorkClock.text(seconds))
                Text(GameStrings.format("mac.work.v2.doing", WorkJobPresentation.name(work.jobID)))
                    .font(.system(size: 26, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                Text(GameStrings.text("mac.work.background")).font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    rewardChip(GameStrings.format("mac.work.v2.goldAfter", work.goldReward), symbol: "dollarsign.circle.fill", tint: RoomTheme.gold)
                    rewardChip("+\(work.expReward) " + GameStrings.text("mac.work.experience"), symbol: "star.fill", tint: RoomTheme.lilac)
                    if preferences?.notificationsEnabled == true {
                        rewardChip(GameStrings.text("mac.work.v2.notifyOn"), symbol: "bell.fill", tint: RoomTheme.darkMint)
                    }
                }
            }.frame(maxWidth: .infinity).padding(.top, 12)
        }
    }
    private func rewardChip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 12, weight: .heavy)).foregroundStyle(tint)
            .padding(.horizontal, 11).padding(.vertical, 6).background(tint.opacity(0.13), in: Capsule())
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            metric("mac.work.duration", WorkJobPresentation.duration(quote?.durationSeconds ?? displayed.durationMinutes * 60), "timer", RoomTheme.secondary)
            metric("player.stamina", "−\(quote?.staminaCost ?? displayed.staminaCost)", "bolt.fill", RoomTheme.darkMint)
            metric("player.mood", "−\(quote?.moodCost ?? displayed.moodCost)", "face.smiling.fill", RoomTheme.friendshipDeep)
            metric("mac.work.gold", "+\(active?.goldReward ?? displayed.goldReward)", "dollarsign.circle.fill", RoomTheme.gold)
            metric("mac.work.experience", "+\(active?.expReward ?? displayed.expReward)", "star.fill", RoomTheme.lilac)
        }
    }

    private func metric(_ key: String, _ value: String, _ symbol: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title3).accessibilityHidden(true)
            Text(value).font(.system(size: 17, weight: .heavy)).monospacedDigit()
            Text(GameStrings.text(key)).font(.caption).foregroundStyle(RoomTheme.secondary)
        }.padding(.vertical, 14).frame(maxWidth: .infinity)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 18)).foregroundStyle(color)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GameStrings.text("mac.work.after")).font(.headline)
            HStack {
                Label("\(store.snapshot?.player.stamina ?? 0) → \(max(0, (store.snapshot?.player.stamina ?? 0) - (quote?.staminaCost ?? selected.staminaCost)))", systemImage: "bolt.fill")
                Spacer()
                Label(GameStrings.format("mac.work.rewardUpTo", selected.goldReward), systemImage: "dollarsign.circle.fill")
            }.font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.darkMint)
            Text(GameStrings.text("mac.work.background")).font(.caption).foregroundStyle(RoomTheme.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 20))
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
            if !mayStart { Text(startHint).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.coralDeep) }
            Button { store.startWork(jobID: selected.id) } label: {
                HStack {
                    Image(systemName: "briefcase.fill")
                    Text(GameStrings.text("work.start"))
                    Text(keyLabel(.confirm)).font(.caption.monospaced()).padding(5).background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                }.frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).disabled(!mayStart)
                .accessibilityIdentifier("macStartWork")
        }
    }

    private var startHint: String {
        if (store.snapshot?.player.level ?? 1) < selected.unlockLevel { return GameStrings.format("career.unlock", selected.unlockLevel) }
        if store.snapshot?.player.activeSleep != nil { return GameStrings.text("work.sleeping") }
        return GameStrings.format("career.lowStamina", quote?.staminaCost ?? selected.staminaCost)
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 15) {
                    Label(GameStrings.text("mac.work.today"), systemImage: "calendar.badge.checkmark").font(.headline)
                    HStack {
                        metric("mac.work.count", "\(store.snapshot?.tasks.dailyWorkCount ?? 0)", "briefcase.fill", RoomTheme.darkMint)
                        metric("mac.work.total", "\(store.snapshot?.player.completedWorkCount ?? 0)", "checkmark.seal.fill", RoomTheme.secondary)
                    }
                }.macContentCard69()
                Button { showsRest = true } label: {
                    Label(GameStrings.text("work.rest.open"), systemImage: store.snapshot?.player.activeSleep == nil ? "moon.stars.fill" : "sun.max.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(SoftButtonStyle()).accessibilityIdentifier("macWorkRest")
                equipment
                VStack(alignment: .leading, spacing: 14) {
                    Label(GameStrings.text("mac.work.latest"), systemImage: "clock.arrow.circlepath").font(.headline)
                    if let result = store.snapshot?.player.lastWorkResult {
                        Text(WorkJobPresentation.name(result.jobID)).font(.headline)
                        Text(result.completedAt, style: .date).font(.caption).foregroundStyle(RoomTheme.secondary)
                        HStack {
                            Label("+\(result.goldReward)", systemImage: "dollarsign.circle.fill").foregroundStyle(RoomTheme.gold)
                            Spacer()
                            Label("+\(result.expReward)", systemImage: "star.fill").foregroundStyle(RoomTheme.lilac)
                        }.font(.headline)
                    } else {
                        Text(GameStrings.text("mac.work.noResult")).foregroundStyle(RoomTheme.secondary)
                    }
                }.macContentCard69()
            }
        }
    }

    private var equipment: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(GameStrings.text("mac.work.equipment"), systemImage: "tshirt.fill").font(.headline)
            ForEach(EquipmentSlot.allCases, id: \.self) { slot in
                if let id = store.snapshot?.player.profile.equipped[slot], let item = PlayerCatalog.item(id: id) {
                    HStack(spacing: 8) {
                        GameIcon(asset: item.displayAssetName, symbol: "tshirt.fill", size: 36)
                        Text(GameStrings.text(item.nameKey)).font(.caption.weight(.bold))
                        Spacer(minLength: 0)
                        Text(GameStrings.text(item.detailKey)).font(.caption2).foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.trailing)
                    }
                }
            }
            if store.snapshot?.player.profile.equipped.isEmpty != false {
                Text(GameStrings.text("mac.work.noEquipment")).font(.caption).foregroundStyle(RoomTheme.secondary)
            }
        }.macContentCard69()
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
