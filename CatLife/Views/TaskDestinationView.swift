import SwiftUI
import CatGameCore

@MainActor
struct TaskDestinationView: View {
    @Bindable var store: GameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var category: GameTaskCategory = .daily
    @State private var page = 0
    @State private var claimingTaskID: String?
    @State private var reward: TaskClaimReceipt?
    @State private var isVisible = false
    @State private var presentationID = UUID()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    if let snapshot = store.snapshot {
                        VStack(alignment: .leading, spacing: 14) {
                            summary(snapshot)
                            categoryPicker(snapshot)
                            Text(GameStrings.text(categoryHintKey))
                                .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            taskList(snapshot)
                            if category == .tutorial {
                                Text(GameStrings.text("tasks.legacyNotice"))
                                    .font(.footnote).foregroundStyle(RoomTheme.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
                    }
                }
                .scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("tasksScroll")
            }
            .accessibilityHidden(reward != nil)
            if let reward {
                TaskRewardView(receipt: reward) { self.reward = nil }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.88).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .background(RoomTheme.cream).fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            presentationID = UUID()
            reward = nil
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { store.activeSheet = nil } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .heavy))
                    .frame(width: 44, height: 44).gameCard(cornerRadius: 22)
            }
            .buttonStyle(.plain).accessibilityLabel(GameStrings.text("common.back"))
            .accessibilityIdentifier("tasksBackButton")
            Label(GameStrings.text("tasks.title"), systemImage: "checklist")
                .font(.system(size: 18, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 14).frame(minHeight: 46)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [RoomTheme.wood.opacity(0.8), RoomTheme.wood],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: RoomTheme.secondary.opacity(0.8), radius: 0, y: 4)
                }
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RoomTheme.secondary.opacity(0.55), lineWidth: 3))
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("tasksPageTitle")
            Spacer(minLength: 0)
            Label("\(store.snapshot?.player.gold ?? 0)", systemImage: "dollarsign.circle.fill")
                .font(.system(size: 14, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 10).frame(minHeight: 36).gameCard(cornerRadius: 22)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: store.snapshot?.player.gold)
                .accessibilityLabel(GameStrings.text("resource.gold"))
                .accessibilityIdentifier("tasksWallet").accessibilityValue("\(store.snapshot?.player.gold ?? 0)")
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
    }

    private var categoryHintKey: String {
        switch category {
        case .tutorial: "tasks.tutorialHint"
        case .daily: "tasks.dayRule"
        case .achievement: "tasks.achievementHint"
        }
    }

    private func summary(_ snapshot: GameSnapshot) -> some View {
        let daily = GameTaskCatalog.all.filter { $0.category == .daily && GameTaskCatalog.isUnlocked($0, in: snapshot) }
        let completed = daily.filter { TaskCardPresentation.progress($0, in: snapshot) >= $0.target }.count
        let claimable = GameTaskCatalog.all.filter { GameTaskCatalog.isClaimable($0, in: snapshot) }.count
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(RoomTheme.track, lineWidth: 8)
                Circle().trim(from: 0, to: daily.isEmpty ? 0 : CGFloat(completed) / CGFloat(daily.count))
                    .stroke(RoomTheme.mint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(completed)/\(daily.count)").font(.system(size: 16, weight: .heavy)).monospacedDigit()
                    Text(GameStrings.text("tasks.todayLabel")).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(RoomTheme.secondary)
                }
            }
            .frame(width: 56, height: 56).padding(4)
            .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.format("tasks.dailyProgress", completed, daily.count))
            .accessibilityIdentifier("tasksDailySummary").accessibilityValue("\(completed)/\(daily.count)")
            VStack(alignment: .leading, spacing: 6) {
                Text(GameStrings.text("tasks.subtitle")).font(.system(size: 15, weight: .heavy))
                Label(GameStrings.text("tasks.refreshHint"), systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                if claimable > 0 {
                    Label(GameStrings.format("tasks.claimableCount", claimable), systemImage: "gift.fill")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5).background(RoomTheme.gold, in: Capsule())
                }
            }
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 26)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tasksClaimableSummary").accessibilityValue("\(claimable)")
    }

    private func categoryPicker(_ snapshot: GameSnapshot) -> some View {
        HStack(spacing: 4) {
            ForEach(GameTaskCategory.allCases, id: \.rawValue) { item in
                let available = GameTaskCatalog.all.filter { $0.category == item && GameTaskCatalog.isClaimable($0, in: snapshot) }.count
                Button {
                    category = item
                    page = 0
                } label: {
                    Label(GameStrings.text("tasks.category.\(item.rawValue)"), systemImage: categorySymbol(item))
                        .font(.system(size: 13, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(category == item ? RoomTheme.darkMint : RoomTheme.secondary)
                        .background(category == item ? RoomTheme.paper : .clear, in: Capsule())
                        .compositingGroup()
                        .shadow(color: category == item ? RoomTheme.ink.opacity(0.1) : .clear, radius: 0, y: 3)
                        .overlay(alignment: .topTrailing) {
                            if available > 0 {
                                Text("\(available)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                                    .background(RoomTheme.coral, in: Capsule()).overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                                    .offset(y: -3).accessibilityHidden(true)
                            }
                        }.contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("taskCategory_\(item.rawValue)")
                .accessibilityLabel(GameStrings.text("tasks.category.\(item.rawValue)"))
                .accessibilityAddTraits(category == item ? .isSelected : [])
                .accessibilityValue(GameStrings.format("tasks.claimableCount", available))
            }
        }.padding(4).background(RoomTheme.chipBg, in: Capsule())
    }

    private func taskList(_ snapshot: GameSnapshot) -> some View {
        let remaining = GameTaskCatalog.remainingTasks(in: snapshot, category: category).enumerated().sorted {
            let firstReady = GameTaskCatalog.isClaimable($0.element, in: snapshot)
            let secondReady = GameTaskCatalog.isClaimable($1.element, in: snapshot)
            return firstReady == secondReady ? $0.offset < $1.offset : firstReady
        }.map(\.element)
        let pageCount = max(1, (remaining.count + 2) / 3)
        let currentPage = min(page, pageCount - 1)
        return VStack(spacing: 14) {
            if remaining.isEmpty {
                Label(GameStrings.text(category == .daily ? "tasks.empty.daily" : "tasks.empty.permanent"),
                      systemImage: "moon.stars.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20).gameCard()
                    .accessibilityIdentifier("tasksEmptyState")
            } else {
                ForEach(Array(remaining.dropFirst(currentPage * 3).prefix(3)), id: \.id) { task in
                    TaskGoalCard(task: task, snapshot: snapshot, isBusy: store.isBusy || claimingTaskID != nil,
                                 isClaiming: claimingTaskID == task.id,
                                 claim: { claim(task, dayKey: snapshot.tasks.dailyDayKey) },
                                 go: { store.goToTaskDestination(task.destination) })
                }
                if pageCount > 1 { pagination(currentPage, count: pageCount) }
            }
            if let nextLevel = GameTaskCatalog.nextUnlockLevel(in: snapshot, category: category) {
                let count = GameTaskCatalog.all.filter {
                    $0.category == category && $0.requiredLevel == nextLevel && !GameTaskCatalog.isClaimed($0, in: snapshot)
                }.count
                VStack(alignment: .leading, spacing: 6) {
                    Label(GameStrings.format("tasks.nextUnlockCount", nextLevel, count), systemImage: "lock.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text(GameStrings.format("tasks.currentLevelHint", snapshot.player.level))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                }
                .fixedSize(horizontal: false, vertical: true).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.paper.opacity(0.5), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RoomTheme.wood, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                .accessibilityIdentifier("tasksNextUnlock").accessibilityValue("\(nextLevel)")
            }
        }
        .onChange(of: remaining.count) { _, _ in page = min(page, pageCount - 1) }
    }

    private func pagination(_ currentPage: Int, count: Int) -> some View {
        HStack(spacing: 12) {
            Button { page = currentPage - 1 } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.disabled(currentPage == 0).accessibilityLabel(GameStrings.text("tasks.previousPage"))
                .accessibilityIdentifier("tasksPreviousPage")
            Text(GameStrings.format("tasks.page", currentPage + 1, count))
                .font(.subheadline.weight(.semibold)).monospacedDigit().frame(maxWidth: .infinity)
                .accessibilityIdentifier("tasksPageIndicator").accessibilityValue("\(currentPage + 1)/\(count)")
            Button { page = currentPage + 1 } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }.disabled(currentPage == count - 1).accessibilityLabel(GameStrings.text("tasks.nextPage"))
                .accessibilityIdentifier("tasksNextPage")
        }.buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
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
