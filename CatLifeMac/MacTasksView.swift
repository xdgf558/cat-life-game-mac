import SwiftUI
import CatGameCore

/// 2.51: the desktop task sheet. The sheet bar already shows the title and Done, so this page has no header of its
/// own: one summary strip (today's ring, hint, ready count, coins), the category tabs, then one compact row per task.
@MainActor
struct MacTasksView: View {
    @Bindable var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var category: GameTaskCategory = .daily
    @State private var claimingTaskID: String?
    @State private var reward: TaskClaimReceipt?
    @State private var isVisible = false
    @State private var presentationID = UUID()

    var body: some View {
        ZStack {
            if let snapshot = store.snapshot {
                VStack(spacing: 10) {
                    summary(snapshot)
                    tabs(snapshot)
                    ScrollView {
                        VStack(spacing: 8) {
                            list(snapshot)
                            if category == .tutorial {
                                Text(GameStrings.text("tasks.legacyNotice"))
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 4)
                            }
                        }
                        .padding(.horizontal, 2).padding(.bottom, 14)
                    }
                    .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("tasksScroll")
                }
                .padding(.horizontal, 16).padding(.top, 14)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
                .accessibilityHidden(reward != nil)
            }
            if let reward {
                TaskRewardView(receipt: reward) { self.reward = nil }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.88).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoomTheme.cream).fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; presentationID = UUID(); reward = nil }
    }

    // MARK: Summary strip

    private func summary(_ snapshot: GameSnapshot) -> some View {
        let daily = GameTaskCatalog.all.filter { $0.category == .daily && GameTaskCatalog.isUnlocked($0, in: snapshot) }
        let completed = daily.filter { TaskCardPresentation.progress($0, in: snapshot) >= $0.target }.count
        let claimable = GameTaskCatalog.all.filter { GameTaskCatalog.isClaimable($0, in: snapshot) }.count
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(RoomTheme.track, lineWidth: 5)
                Circle().trim(from: 0, to: daily.isEmpty ? 0 : CGFloat(completed) / CGFloat(daily.count))
                    .stroke(RoomTheme.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: -1) {
                    Text("\(completed)/\(daily.count)").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                    Text(GameStrings.text("tasks.todayLabel")).font(.system(size: 9, weight: .bold))
                        .foregroundStyle(RoomTheme.secondary)
                }
            }
            .frame(width: 46, height: 46)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.format("tasks.dailyProgress", completed, daily.count))
            .accessibilityIdentifier("tasksDailySummary").accessibilityValue("\(completed)/\(daily.count)")
            VStack(alignment: .leading, spacing: 3) {
                Text(GameStrings.text("tasks.subtitle")).font(.system(size: 14, weight: .heavy)).lineLimit(1)
                Label(GameStrings.text("tasks.refreshHint"), systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
                    .help(GameStrings.text("tasks.dayRule"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if claimable > 0 {
                Label(GameStrings.format("tasks.claimableCount", claimable), systemImage: "gift.fill")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white).lineLimit(1).fixedSize()
                    .padding(.horizontal, 9).padding(.vertical, 5).background(RoomTheme.gold, in: Capsule())
            }
            Label("\(snapshot.player.gold)", systemImage: "dollarsign.circle.fill")
                .font(.system(size: 13, weight: .heavy)).monospacedDigit().lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoomTheme.gold.opacity(0.18), in: Capsule())
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: snapshot.player.gold)
                .accessibilityLabel(GameStrings.text("resource.gold"))
                .accessibilityIdentifier("tasksWallet").accessibilityValue("\(snapshot.player.gold)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
        .gameCard(cornerRadius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tasksClaimableSummary").accessibilityValue("\(claimable)")
    }

    // MARK: Category tabs

    private func tabs(_ snapshot: GameSnapshot) -> some View {
        HStack(spacing: 3) {
            ForEach(GameTaskCategory.allCases, id: \.rawValue) { item in
                let available = GameTaskCatalog.all.filter { $0.category == item && GameTaskCatalog.isClaimable($0, in: snapshot) }.count
                let selected = category == item
                Button { category = item } label: {
                    HStack(spacing: 5) {
                        Image(systemName: categorySymbol(item)).font(.system(size: 11, weight: .heavy))
                        Text(GameStrings.text("tasks.category.\(item.rawValue)")).lineLimit(1).minimumScaleFactor(0.7)
                        if available > 0 {
                            Text("\(available)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
                                .background(RoomTheme.coral, in: Capsule()).accessibilityHidden(true)
                        }
                    }
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(selected ? RoomTheme.darkMint : RoomTheme.secondary)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(selected ? RoomTheme.paper : .clear, in: Capsule())
                    .compositingGroup()
                    .shadow(color: selected ? RoomTheme.ink.opacity(0.1) : .clear, radius: 0, y: 2)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("taskCategory_\(item.rawValue)")
                .accessibilityLabel(GameStrings.text("tasks.category.\(item.rawValue)"))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityValue(GameStrings.format("tasks.claimableCount", available))
            }
        }
        .padding(3).background(RoomTheme.chipBg, in: Capsule())
    }

    // MARK: Task rows

    @ViewBuilder private func list(_ snapshot: GameSnapshot) -> some View {
        let remaining = GameTaskCatalog.remainingTasks(in: snapshot, category: category).enumerated().sorted {
            let firstReady = GameTaskCatalog.isClaimable($0.element, in: snapshot)
            let secondReady = GameTaskCatalog.isClaimable($1.element, in: snapshot)
            return firstReady == secondReady ? $0.offset < $1.offset : firstReady
        }.map(\.element)
        // The daily rule already sits in the summary strip.
        if let hint = categoryHintKey {
            Text(GameStrings.text(hint))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 2)
        }
        if remaining.isEmpty {
            Label(GameStrings.text(category == .daily ? "tasks.empty.daily" : "tasks.empty.permanent"),
                  systemImage: "moon.stars.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(RoomTheme.darkMint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).gameCard(cornerRadius: 16)
                .accessibilityIdentifier("tasksEmptyState")
        } else {
            ForEach(remaining, id: \.id) { task in
                MacTaskRow(task: task, snapshot: snapshot, isBusy: store.isBusy || claimingTaskID != nil,
                           isClaiming: claimingTaskID == task.id,
                           claim: { claim(task, dayKey: snapshot.tasks.dailyDayKey) },
                           go: { store.goToTaskDestination(task.destination) })
            }
        }
        if let nextLevel = GameTaskCatalog.nextUnlockLevel(in: snapshot, category: category) {
            let count = GameTaskCatalog.all.filter {
                $0.category == category && $0.requiredLevel == nextLevel && !GameTaskCatalog.isClaimed($0, in: snapshot)
            }.count
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                Text(GameStrings.format("tasks.nextUnlockCount", nextLevel, count)).font(.system(size: 12, weight: .heavy))
                Spacer(minLength: 8)
                Text(GameStrings.format("tasks.currentLevelHint", snapshot.player.level))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(RoomTheme.secondary).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tasksNextUnlock").accessibilityValue("\(nextLevel)")
        }
    }

    private var categoryHintKey: String? {
        switch category {
        case .tutorial: "tasks.tutorialHint"
        case .daily: nil
        case .achievement: "tasks.achievementHint"
        }
    }

    private func categorySymbol(_ category: GameTaskCategory) -> String {
        switch category { case .tutorial: "flag.fill"; case .daily: "sun.max.fill"; case .achievement: "trophy.fill" }
    }

    private func claim(_ task: GameTaskDefinition, dayKey: String?) {
        guard claimingTaskID == nil, !store.isBusy else { return }
        claimingTaskID = task.id
        let requestID = presentationID
        Task { @MainActor in
            let result = await store.claimTaskWithReceipt(id: task.id, expectedDayKey: dayKey)
            claimingTaskID = nil
            guard let result, isVisible, requestID == presentationID else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.16)) { reward = result }
            store.playFeedback(.claim)
        }
    }
}

/// One task on a single line: icon, title with its reward, a two-line detail, a slim progress bar, and the action.
private struct MacTaskRow: View {
    let task: GameTaskDefinition
    let snapshot: GameSnapshot
    let isBusy: Bool
    let isClaiming: Bool
    let claim: () -> Void
    let go: () -> Void
    private var ready: Bool { GameTaskCatalog.isClaimable(task, in: snapshot) }
    private var progress: Int { TaskCardPresentation.progress(task, in: snapshot) }

    var body: some View {
        HStack(spacing: 12) {
            GameIconTile(symbol: TaskCardPresentation.symbol(task.destination),
                         tint: TaskCardPresentation.tint(task.destination),
                         background: TaskCardPresentation.background(task.destination), size: 38)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(GameStrings.text("task.\(task.id).title")).font(.system(size: 14, weight: .heavy)).lineLimit(1)
                    rewards
                }
                Text(GameStrings.text("task.\(task.id).detail"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        Capsule().fill(RoomTheme.track).overlay(alignment: .leading) {
                            Capsule().fill(ready ? RoomTheme.gold : RoomTheme.mint)
                                .frame(width: geometry.size.width * CGFloat(progress) / CGFloat(max(1, task.target)))
                        }
                    }
                    .frame(height: 6)
                    Text("\(progress)/\(task.target)")
                        .font(.system(size: 11, weight: .heavy)).monospacedDigit().foregroundStyle(RoomTheme.secondary).fixedSize()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(GameStrings.format("tasks.progress", progress, task.target))
                .accessibilityValue("\(progress)/\(task.target)").accessibilityIdentifier("taskProgress_\(task.id)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action.frame(width: 104)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(ready ? RoomTheme.rewardPaper : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ready ? RoomTheme.rewardBorder : .white, lineWidth: ready ? 2 : 1.5))
        .compositingGroup()
        .shadow(color: RoomTheme.ink.opacity(0.07), radius: 0, y: 3)
        .accessibilityElement(children: .contain).accessibilityLabel(GameStrings.text("task.\(task.id).title"))
        .accessibilityIdentifier("taskCard_\(task.id)")
    }

    private var rewards: some View {
        HStack(spacing: 6) {
            Label("\(task.goldReward)", systemImage: "dollarsign.circle.fill").foregroundStyle(RoomTheme.secondary)
                .accessibilityLabel(GameStrings.format("tasks.rewardGold", task.goldReward))
            Label(GameStrings.format("tasks.rewardExperience", task.expReward), systemImage: "star.fill")
                .foregroundStyle(RoomTheme.darkMint)
        }
        .labelStyle(TightLabelStyle()).font(.system(size: 11, weight: .heavy)).lineLimit(1).fixedSize()
        .padding(.horizontal, 7).padding(.vertical, 2).background(RoomTheme.track.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .combine).accessibilityIdentifier("taskRewards_\(task.id)")
    }

    @ViewBuilder private var action: some View {
        if ready {
            Button(action: claim) {
                Label(GameStrings.text(isClaiming ? "common.saving" : "tasks.claim"), systemImage: "gift.fill")
                    .labelStyle(TightLabelStyle()).font(.system(size: 12, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 32)
                    .background(RoomTheme.gold, in: Capsule())
                    .compositingGroup().shadow(color: RoomTheme.secondary.opacity(0.6), radius: 0, y: 2)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(isBusy).opacity(isBusy && !isClaiming ? 0.5 : 1)
            .accessibilityIdentifier("taskClaim_\(task.id)")
        } else {
            Button(action: go) {
                HStack(spacing: 3) {
                    Text(GameStrings.text("tasks.destination.\(task.destination.rawValue)")).lineLimit(1).minimumScaleFactor(0.75)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy))
                }
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoomTheme.paleMint.opacity(0.55), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(isBusy).accessibilityIdentifier("taskGo_\(task.id)")
        }
    }
}

private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}
