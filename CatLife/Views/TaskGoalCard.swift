import SwiftUI
import CatGameCore

struct TaskGoalCard: View {
    let task: GameTaskDefinition
    let snapshot: GameSnapshot
    let isBusy: Bool
    let isClaiming: Bool
    let claim: () -> Void
    let go: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ready: Bool { GameTaskCatalog.isClaimable(task, in: snapshot) }
    private var progress: Int { TaskCardPresentation.progress(task, in: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                GameIconTile(symbol: TaskCardPresentation.symbol(task.destination),
                             tint: TaskCardPresentation.tint(task.destination),
                             background: TaskCardPresentation.background(task.destination), size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(GameStrings.text("task.\(task.id).title")).font(.system(size: 16, weight: .heavy))
                    Text(GameStrings.text("task.\(task.id).detail"))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                GeometryReader { geometry in
                    Capsule().fill(RoomTheme.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(ready ? RoomTheme.gold : RoomTheme.mint)
                                .frame(width: geometry.size.width * CGFloat(progress) / CGFloat(max(1, task.target)))
                        }
                }.frame(height: 9)
                Text("\(progress) / \(task.target)")
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit().foregroundStyle(RoomTheme.secondary)
                    .fixedSize()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.format("tasks.progress", progress, task.target))
            .accessibilityValue("\(progress)/\(task.target)").accessibilityIdentifier("taskProgress_\(task.id)")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { rewards.fixedSize(); Spacer(minLength: 0); action.fixedSize() }
                VStack(alignment: .leading, spacing: 10) { rewards; action.frame(maxWidth: .infinity) }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(ready ? RoomTheme.rewardPaper : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            if ready, !reduceMotion { TaskClaimShimmer().clipShape(RoundedRectangle(cornerRadius: 24)).allowsHitTesting(false) }
        }
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(ready ? RoomTheme.rewardBorder : .white, lineWidth: 2))
        .compositingGroup()
        .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
        .overlay(alignment: .topTrailing) {
            if ready {
                Text(GameStrings.text("tasks.claimable")).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4).background(RoomTheme.gold, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                    .offset(x: -14, y: -7).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain).accessibilityLabel(GameStrings.text("task.\(task.id).title"))
        .accessibilityIdentifier("taskCard_\(task.id)")
    }

    private var rewards: some View {
        HStack(spacing: 6) {
            Label("\(task.goldReward)", systemImage: "dollarsign.circle.fill")
                .foregroundStyle(RoomTheme.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoomTheme.gold.opacity(0.2), in: Capsule())
                .accessibilityLabel(GameStrings.format("tasks.rewardGold", task.goldReward))
            Label(GameStrings.format("tasks.rewardExperience", task.expReward), systemImage: "star.fill")
                .foregroundStyle(RoomTheme.darkMint).padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoomTheme.paleMint, in: Capsule())
        }
        .font(.system(size: 11, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine).accessibilityIdentifier("taskRewards_\(task.id)")
    }

    @ViewBuilder private var action: some View {
        if ready {
            Button(action: claim) {
                Label(GameStrings.text(isClaiming ? "common.saving" : "tasks.claim"), systemImage: "gift.fill")
                    .font(.system(size: 13, weight: .heavy))
            }
            .buttonStyle(TaskGoldButtonStyle(compact: true)).disabled(isBusy)
            .accessibilityIdentifier("taskClaim_\(task.id)")
        } else {
            Button(action: go) {
                HStack(spacing: 5) {
                    Text(GameStrings.text("tasks.destination.\(task.destination.rawValue)"))
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                .padding(.horizontal, 12).frame(minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RoomTheme.mint.opacity(0.24), lineWidth: 2))
                .contentShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain).disabled(isBusy).accessibilityIdentifier("taskGo_\(task.id)")
        }
    }
}

enum TaskCardPresentation {
    static func progress(_ task: GameTaskDefinition, in snapshot: GameSnapshot) -> Int {
        GameTaskCatalog.isClaimed(task, in: snapshot) ? task.target : min(task.target, GameTaskCatalog.progress(for: task, in: snapshot))
    }
    static func symbol(_ destination: GameTaskDestination) -> String {
        switch destination { case .work: "briefcase.fill"; case .care: "cat.fill"; case .furnitureShop: "storefront.fill"; case .upgrade: "house.fill"; case .neighbors: "person.2.fill"; case .market: "arrow.left.arrow.right" }
    }
    static func tint(_ destination: GameTaskDestination) -> Color {
        switch destination { case .work: RoomTheme.gold; case .care: RoomTheme.mint; case .furnitureShop: RoomTheme.coral; case .upgrade: RoomTheme.secondary; case .neighbors: RoomTheme.lilac; case .market: RoomTheme.darkMint }
    }
    static func background(_ destination: GameTaskDestination) -> Color {
        switch destination { case .work: RoomTheme.gold.opacity(0.2); case .care: RoomTheme.paleMint; case .furnitureShop: RoomTheme.paleCoral; case .upgrade: RoomTheme.track; case .neighbors: RoomTheme.lilac.opacity(0.15); case .market: RoomTheme.paleMint }
    }
}

struct TaskGoldButtonStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white)
            .padding(.horizontal, compact ? 12 : 18).padding(.vertical, compact ? 8 : 13)
            .frame(minHeight: compact ? 44 : 52)
            .background(RoomTheme.gold, in: RoundedRectangle(cornerRadius: compact ? 17 : 22))
            .overlay(RoundedRectangle(cornerRadius: compact ? 17 : 22).strokeBorder(.white.opacity(0.4), lineWidth: 2))
            .compositingGroup()
            .shadow(color: RoomTheme.secondary.opacity(isEnabled ? 0.8 : 0.2), radius: 0, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed ? 3 : 0).opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
    }
}

private struct TaskClaimShimmer: View {
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: scenePhase != .active)) { timeline in
            GeometryReader { geometry in
                let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2) / 2.2
                LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 110).rotationEffect(.degrees(12))
                    .offset(x: -140 + (geometry.size.width + 280) * phase)
            }
        }.accessibilityHidden(true)
    }
}
