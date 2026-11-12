import SwiftUI
import CatGameCore

/// Work navigation and presentation. Quotes and all durable actions stay in GameStore/Core.
@MainActor
struct WorkDestinationView: View {
    @Bindable var store: GameStore
    @State private var careerPath: [CareerRoute] = []
    @State private var selectedJobID = "job_flyer"
    @State private var careerSearch = ""
    @State private var careerFilter = CareerDirectory.Filter.all
    @State private var careerPage = 0
    @State private var gridPage = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum CareerRoute: Hashable { case jobs, job(String), rest, result }

    var body: some View {
        NavigationStack(path: $careerPath) {
            ScrollView {
                work.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("destinationScroll")
            .background(RoomTheme.cream)
            .navigationTitle(GameStrings.text("work.title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: CareerRoute.self) { route in
                switch route {
                case .jobs: careerChoices
                case .job(let id): careerDetail(id)
                case .rest: restPage
                case .result: workResult
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { startShiftBar }
        }
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink)
        #if DEBUG
        .overlay(alignment: .topLeading) { AudioDiagnosticsView(store: store) }
        #endif
        .onChange(of: store.pendingWorkResultID, initial: true) { _, id in
            guard let id, id == store.snapshot?.player.lastWorkResult?.id else { return }
            careerPath = [.result]
            store.consumeWorkResultPresentation()
        }
    }

    private var selectedJob: WorkJob { WorkCatalog.job(id: selectedJobID) ?? WorkCatalog.all[0] }
    private var playerLevel: Int { store.snapshot?.player.level ?? 1 }
    private var playerExp: Int { store.snapshot?.player.exp ?? 0 }

    private var work: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                GamePageHeading(title: GameStrings.text("work.title"),
                                subtitle: GameStrings.text("redesign.work.subtitle"),
                                asset: "icon-work",
                                symbol: "briefcase.fill", tint: RoomTheme.gold,
                                background: RoomTheme.gold.opacity(0.2))
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Label("\(store.snapshot?.player.stamina ?? 0)", systemImage: "bolt.fill")
                        .foregroundStyle(RoomTheme.darkMint)
                        .accessibilityLabel(GameStrings.text("player.stamina"))
                        .accessibilityValue("\(store.snapshot?.player.stamina ?? 0)")
                        .accessibilityIdentifier("workStaminaSummary")
                    Label("\(store.snapshot?.player.mood ?? 0)", systemImage: "face.smiling.fill")
                        .foregroundStyle(RoomTheme.ink)
                        .accessibilityLabel(GameStrings.text("player.mood"))
                        .accessibilityValue("\(store.snapshot?.player.mood ?? 0)")
                        .accessibilityIdentifier("workMoodSummary")
                }
                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                .fixedSize().padding(10).background(RoomTheme.paper, in: Capsule())
            }
            careerProgress
            if let active = store.snapshot?.player.activeWork { activeWorkCard(active) }
            HStack {
                Text(GameStrings.text("career.jobs")).font(.system(size: 17, weight: .heavy))
                Spacer()
                Button { careerPath = [.jobs] } label: {
                    Label(GameStrings.text("redesign.work.search"), systemImage: "magnifyingglass")
                        .font(.system(size: 13, weight: .bold)).frame(minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
                .accessibilityIdentifier("careerChooseJobButton")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                ForEach(Array(WorkCatalog.all[CareerDirectory.pageRange(gridPage, count: WorkCatalog.all.count)])) { job in
                    WorkCareerCard(job: job, quote: preview(job), selected: selectedJobID == job.id,
                                   unlocked: playerLevel >= job.unlockLevel, playerLevel: playerLevel) {
                        selectedJobID = job.id
                    }
                    .disabled(playerLevel < job.unlockLevel)
                    .accessibilityIdentifier("workJobTile_\(job.id)")
                }
            }
            HStack(spacing: 8) {
                Button { gridPage = max(0, gridPage - 1) } label: {
                    Image(systemName: "chevron.left").frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(gridPage == 0).accessibilityLabel(GameStrings.text("career.page.previous"))
                .accessibilityIdentifier("workGridPrevious")
                Text(GameStrings.format("career.page.indicator", gridPage + 1, CareerDirectory.pageCount(for: WorkCatalog.all.count)))
                    .font(.caption.weight(.bold)).monospacedDigit()
                    .accessibilityIdentifier("workGridPage")
                    .accessibilityValue("\(gridPage + 1)/\(CareerDirectory.pageCount(for: WorkCatalog.all.count))")
                Button { gridPage += 1 } label: {
                    Image(systemName: "chevron.right").frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(gridPage + 1 >= CareerDirectory.pageCount(for: WorkCatalog.all.count))
                .accessibilityLabel(GameStrings.text("career.page.next"))
                .accessibilityIdentifier("workGridNext")
            }
            .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
            VStack(spacing: 0) {
                workEntry("career.details", symbol: "info.circle", id: "workDetailsButton") {
                    careerPath = [.job(store.snapshot?.player.activeWork?.jobID ?? selectedJobID)]
                }
                Divider().padding(.leading, 48)
                workEntry("work.rest.open", symbol: "moon.stars.fill", id: "workRestButton",
                          subtitle: store.snapshot?.player.activeSleep == nil ? nil : GameStrings.text("sleep.sleeping")) {
                    careerPath = [.rest]
                }
                if store.snapshot?.player.lastWorkResult != nil {
                    Divider().padding(.leading, 48)
                    workEntry("career.previousResult", symbol: "checkmark.seal.fill", id: "careerPreviousResultButton") {
                        careerPath = [.result]
                    }
                }
            }
            .gameCard()
        }
    }

    private func workEntry(_ key: String, symbol: String, id: String, subtitle: String? = nil,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameStrings.text(key)).font(.subheadline.weight(.semibold))
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(RoomTheme.secondary) }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
        .accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }

    private var startShiftBar: some View {
        VStack(spacing: 8) {
            if let active = store.snapshot?.player.activeWork {
                Text(GameStrings.format("career.nextJob", WorkJobPresentation.name(selectedJobID)))
                    .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    .accessibilityIdentifier("careerNextJobName").accessibilityValue(selectedJobID)
                Label(GameStrings.format("redesign.work.inProgress", duration(until: active.endsAt)), systemImage: "clock.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(RoomTheme.darkMint)
                    .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityIdentifier("workInProgressButton")
            } else {
                let quote = preview(selectedJob)
                HStack(spacing: 8) {
                    Text(WorkJobPresentation.name(selectedJobID))
                        .font(.system(size: 14, weight: .heavy)).lineLimit(1)
                        .accessibilityIdentifier("selectedCareerName").accessibilityValue(selectedJobID)
                    Spacer(minLength: 2)
                    Text(workDurationText(quote?.durationSeconds ?? selectedJob.durationMinutes * 60))
                        .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                        .accessibilityIdentifier("workQuoteDurationSeconds")
                        .accessibilityValue(String(quote?.durationSeconds ?? selectedJob.durationMinutes * 60))
                }
                workCosts(selectedJob, quote: quote)
                if store.snapshot?.player.activeSleep != nil {
                    Text(GameStrings.text("work.sleeping")).font(.caption).foregroundStyle(RoomTheme.coral)
                } else if (store.snapshot?.player.stamina ?? 0) < (quote?.staminaCost ?? selectedJob.staminaCost) {
                    Text(GameStrings.format("career.lowStamina", quote?.staminaCost ?? selectedJob.staminaCost))
                        .font(.caption).foregroundStyle(RoomTheme.coral)
                }
                Button { store.startWork(jobID: selectedJobID) } label: {
                    Label {
                        Text(GameStrings.text("work.start"))
                    } icon: {
                        GameIcon(asset: "icon-work", symbol: "briefcase.fill", size: 24, tint: .white)
                    }
                    .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle())
                .disabled(store.isBusy || store.snapshot?.player.activeSleep != nil
                          || (store.snapshot?.player.stamina ?? 0) < (quote?.staminaCost ?? selectedJob.staminaCost)
                          || playerLevel < selectedJob.unlockLevel)
                .accessibilityIdentifier("startWorkButton")
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .frame(maxWidth: 560).frame(maxWidth: .infinity)
        .background(RoomTheme.cream)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workStartBar")
    }

    private func activeWorkCard(_ active: ActiveWork) -> some View {
        let seconds = Int(max(1, min(315_360_000, active.endsAt.timeIntervalSince(active.startedAt))))
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 8)
                Circle().trim(from: 0, to: progress(active))
                    .stroke(RoomTheme.wood, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    GameIcon(asset: WorkJobPresentation.asset(active.jobID),
                             symbol: WorkJobPresentation.symbol(active.jobID), size: 24, tint: .white)
                    Text(duration(until: active.endsAt))
                        .font(.system(size: 19, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
                        .accessibilityIdentifier("workCountdown")
                }
            }
            .frame(width: 84, height: 84)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("activeWorkDurationSeconds").accessibilityValue(String(seconds))
            VStack(alignment: .leading, spacing: 7) {
                Text(WorkJobPresentation.name(active.jobID)).font(.system(size: 19, weight: .heavy))
                    .accessibilityIdentifier("selectedCareerName").accessibilityValue(active.jobID)
                Label(GameStrings.format("redesign.work.reward", active.goldReward), systemImage: "dollarsign.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(GameStrings.format("career.expReward", active.expReward)).font(.caption.weight(.bold))
                Text(workDurationText(seconds)).font(.caption)
                    .accessibilityIdentifier("workQuoteDurationSeconds").accessibilityValue(String(seconds))
                if let quote = active.quote {
                    HStack(spacing: 8) {
                        Text(GameStrings.text("player.stamina") + " −\(quote.staminaCost)")
                            .accessibilityIdentifier("workQuoteStaminaCost").accessibilityValue("\(quote.staminaCost)")
                        Text(GameStrings.text("player.mood") + " −\(quote.moodCost)")
                            .accessibilityIdentifier("workQuoteMoodCost").accessibilityValue("\(quote.moodCost)")
                    }.font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28).fill(RoomTheme.mint)
                .shadow(color: RoomTheme.darkMint, radius: 0, y: 4)
        }
    }

    private var careerProgress: some View {
        HStack(spacing: 14) {
            Text("\(playerLevel)").font(.system(size: 25, weight: .heavy)).monospacedDigit()
                .foregroundStyle(.white).frame(width: 48, height: 48)
                .background(RoomTheme.mint, in: Circle())
                .overlay(Circle().stroke(RoomTheme.paleMint, lineWidth: 3)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(GameStrings.format("career.level", playerLevel)).font(.system(size: 15, weight: .heavy))
                        .accessibilityIdentifier("playerLevel").accessibilityValue("\(playerLevel)")
                    Spacer(minLength: 4)
                    let required = max(1, WorkCatalog.requiredExperience(forLevel: playerLevel))
                    Text("\(playerExp) / \(required)").font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(RoomTheme.secondary).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .accessibilityLabel(GameStrings.format("career.exp", playerExp, required))
                        .accessibilityIdentifier("playerExperience").accessibilityValue("\(playerExp)")
                }
                ProgressView(value: Double(playerExp), total: Double(max(1, WorkCatalog.requiredExperience(forLevel: playerLevel))))
                    .tint(RoomTheme.gold).scaleEffect(x: 1, y: 1.8)
            }
        }
        .padding(18).gameCard(cornerRadius: 28)
    }

    private func shiftSeconds(_ job: WorkJob, captured: ActiveWork?, quote: WorkQuote?) -> Int {
        captured.map { Int(max(1, min(315_360_000, $0.endsAt.timeIntervalSince($0.startedAt)))) }
            ?? quote?.durationSeconds ?? job.durationMinutes * 60
    }

    private func preview(_ job: WorkJob) -> WorkQuote? {
        store.snapshot.flatMap { GameEngine.workQuote(for: $0.player, jobID: job.id) }
    }

    private func workDurationText(_ seconds: Int) -> String {
        WorkJobPresentation.duration(seconds)
    }

    private func workCosts(_ job: WorkJob, quote: WorkQuote?) -> some View {
        HStack(spacing: 14) {
            Text(GameStrings.text("player.stamina") + " −\(quote?.staminaCost ?? job.staminaCost)")
                .accessibilityIdentifier("workQuoteStaminaCost").accessibilityValue("\(quote?.staminaCost ?? job.staminaCost)")
            Text(GameStrings.text("player.mood") + " −\(quote?.moodCost ?? job.moodCost)")
                .accessibilityIdentifier("workQuoteMoodCost").accessibilityValue("\(quote?.moodCost ?? job.moodCost)")
        }.font(.footnote).foregroundStyle(RoomTheme.secondary)
    }

    private var careerChoices: some View {
        WorkCareerDirectoryView(playerLevel: playerLevel, selectedJobID: selectedJobID, language: store.language,
            careerSearch: $careerSearch, careerFilter: $careerFilter, careerPage: $careerPage) { id in
                careerPath.append(.job(id))
            }
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                careerBackButton("careerJobsBackButton")
            }
    }

    private func careerDetail(_ id: String) -> some View {
        ScrollView {
            if let job = WorkCatalog.job(id: id) {
                let active = store.snapshot?.player.activeWork.flatMap { $0.jobID == id ? $0 : nil }
                let quote = active == nil ? preview(job) : active?.quote
                let seconds = shiftSeconds(job, captured: active, quote: quote)
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        GameIcon(asset: WorkJobPresentation.asset(job.id),
                                 symbol: WorkJobPresentation.symbol(job.id), size: 36, tint: RoomTheme.darkMint)
                        Text(WorkJobPresentation.name(job.id)).font(.title2.weight(.bold))
                            .accessibilityIdentifier("careerJobName_\(job.id)")
                    }
                    Text(GameStrings.text("jobs.\(job.id).detail")).foregroundStyle(RoomTheme.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        detailValue("career.duration", value: workDurationText(seconds),
                                    id: "careerDurationSeconds_\(job.id)", accessibilityValue: String(seconds))
                        detailValue("career.reward", value: GameStrings.format("career.gold", active?.goldReward ?? job.goldReward))
                        detailValue("career.experience", value: GameStrings.format("career.expReward", active?.expReward ?? job.expReward))
                        if active == nil || quote != nil {
                            detailValue("career.costs", value: GameStrings.format("career.cost", quote?.staminaCost ?? job.staminaCost,
                                                                                 quote?.moodCost ?? job.moodCost))
                        }
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(GameStrings.text("player.bonuses")).font(.headline)
                        if let quote {
                            if active != nil || !quote.equipmentIDs.isEmpty {
                                Text(GameStrings.text(active == nil ? "work.benefitsApplied" : "work.fixedShift"))
                                    .font(.subheadline).foregroundStyle(RoomTheme.secondary)
                            }
                            if quote.equipmentIDs.isEmpty {
                                Text(GameStrings.text("player.noBonuses")).font(.subheadline)
                            } else {
                                ForEach(quote.equipmentIDs, id: \.self) { itemID in
                                    if let item = PlayerCatalog.item(id: itemID) {
                                        Label(GameStrings.text(item.nameKey), systemImage: "checkmark.circle")
                                            .font(.subheadline).foregroundStyle(RoomTheme.darkMint)
                                    }
                                }
                                if quote.bonuses.durationReductionPercent > 0 {
                                    Text(GameStrings.format("player.bonus.duration", quote.bonuses.durationReductionPercent)).font(.subheadline)
                                }
                                if quote.bonuses.staminaReductionPercent > 0 {
                                    Text(GameStrings.format("player.bonus.stamina", quote.bonuses.staminaReductionPercent)).font(.subheadline)
                                }
                                if quote.bonuses.moodReductionPercent > 0 {
                                    Text(GameStrings.format("player.bonus.mood", quote.bonuses.moodReductionPercent)).font(.subheadline)
                                }
                            }
                            if seconds != quote.baseDurationSeconds {
                                Text(GameStrings.format("work.baseDuration", workDurationText(quote.baseDurationSeconds)))
                                    .font(.footnote).foregroundStyle(RoomTheme.secondary)
                            }
                        } else if active != nil {
                            Text(GameStrings.text("work.fixedShift")).font(.subheadline).foregroundStyle(RoomTheme.secondary)
                        }
                    }
                    if playerLevel < job.unlockLevel {
                        Label(GameStrings.format("career.unlock", job.unlockLevel), systemImage: "lock.fill")
                            .font(.headline).foregroundStyle(RoomTheme.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(GameStrings.format("career.unlock", job.unlockLevel))
                            .accessibilityIdentifier("careerLocked_\(job.id)")
                    } else {
                        Label(GameStrings.format("career.unlock", job.unlockLevel), systemImage: "checkmark.circle")
                            .font(.subheadline).foregroundStyle(RoomTheme.darkMint)
                    }
                    if store.snapshot?.player.activeWork != nil {
                        Text(GameStrings.text("career.workingHint")).font(.footnote).foregroundStyle(RoomTheme.secondary)
                    }
                    Button {
                        selectedJobID = job.id
                        careerPath.removeAll()
                    } label: {
                        Label(GameStrings.text(selectedJobID == job.id ? "career.selected" : "career.select"),
                              systemImage: selectedJobID == job.id ? "checkmark.circle.fill" : "arrow.right.circle")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MintButtonStyle()).disabled(playerLevel < job.unlockLevel)
                    .accessibilityIdentifier("careerSelect_\(job.id)")
                    Text(GameStrings.text("work.offline")).font(.footnote).foregroundStyle(RoomTheme.secondary)
                }
                .padding(20).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
            } else if let active = store.snapshot?.player.activeWork, active.jobID == id {
                // Legacy contracts may outlive a catalog entry. Show their
                // captured terms without inventing a current job or costs.
                VStack(alignment: .leading, spacing: 20) {
                    Text(GameStrings.format("work.remaining", duration(until: active.endsAt)))
                        .font(.title2.weight(.bold)).monospacedDigit()
                    let seconds = Int(max(1, min(315_360_000, active.endsAt.timeIntervalSince(active.startedAt))))
                    VStack(alignment: .leading, spacing: 16) {
                        detailValue("career.duration", value: workDurationText(seconds),
                                    id: "careerDurationSeconds_\(id)", accessibilityValue: String(seconds))
                        detailValue("career.reward", value: GameStrings.format("career.gold", active.goldReward))
                        detailValue("career.experience", value: GameStrings.format("career.expReward", active.expReward))
                    }
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
                    Text(GameStrings.text("work.offline")).font(.footnote).foregroundStyle(RoomTheme.secondary)
                }
                .padding(20).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("careerDetailScroll").background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("career.details")).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            careerBackButton("careerDetailBackButton")
        }
    }

    private func detailValue(_ key: String, value: String, id: String = "", accessibilityValue: String? = nil) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(GameStrings.text(key)).foregroundStyle(RoomTheme.secondary)
                Spacer(minLength: 4)
                Text(value).fontWeight(.semibold)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(GameStrings.text(key)).foregroundStyle(RoomTheme.secondary)
                Text(value).fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(key)).accessibilityValue(accessibilityValue ?? value)
        .accessibilityIdentifier(id)
    }

    @ToolbarContentBuilder private func careerBackButton(_ id: String) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                if !careerPath.isEmpty { careerPath.removeLast() }
            } label: {
                Label(GameStrings.text("common.back"), systemImage: "chevron.left")
            }
            .foregroundStyle(RoomTheme.darkMint).accessibilityIdentifier(id)
        }
    }

    private var restPage: some View {
        WorkRestView(store: store)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                careerBackButton("workRestBackButton")
            }
    }

    private var workResult: some View {
        WorkResultView(store: store, onHome: { store.activeSheet = nil }) { careerPath.removeAll() }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { careerPath.removeAll() } label: {
                        Label(GameStrings.text("common.back"), systemImage: "chevron.left")
                    }.foregroundStyle(RoomTheme.darkMint)
                }
            }
    }

    private func duration(until deadline: Date) -> String {
        let reference = max(store.now, store.snapshot?.meta.lastSyncAt ?? store.now)
        let seconds = Int(min(315_360_000, max(0, ceil(deadline.timeIntervalSince(reference)))))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func progress(_ work: ActiveWork) -> Double {
        let total = max(1, work.endsAt.timeIntervalSince(work.startedAt))
        let reference = max(store.now, store.snapshot?.meta.lastSyncAt ?? store.now)
        return max(0, min(1, reference.timeIntervalSince(work.startedAt) / total))
    }
}
