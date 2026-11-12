import SwiftUI
import CatGameCore

@MainActor
struct WorkRestView: View {
    let store: GameStore

    var body: some View {
        ScrollView {
            playerRest.padding(20).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("workRestScroll").background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("sleep.title")).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
    }

    private var playerRest: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(GameStrings.text("sleep.title"), systemImage: "moon.stars.fill")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(RoomTheme.darkMint)
            Text(GameStrings.text("sleep.subtitle"))
                .font(.subheadline).foregroundStyle(RoomTheme.secondary)
            stat("sleep.stamina", value: store.snapshot?.player.stamina ?? 0)
                .accessibilityIdentifier("playerStamina")
            stat("sleep.mood", value: store.snapshot?.player.mood ?? 0)
                .accessibilityIdentifier("playerMood")

            let sleeping = store.snapshot?.player.activeSleep != nil
            let working = store.snapshot?.player.activeWork != nil
            Text(sleeping ? GameStrings.text("sleep.sleeping") :
                    (store.snapshot?.player.activeWork.map {
                        GameStrings.format("career.working", WorkJobPresentation.name($0.jobID))
                    } ?? GameStrings.text("sleep.awake")))
                .font(.headline)
                .accessibilityIdentifier("sleepStatus")
                .accessibilityValue(sleeping ? "asleep" : (working ? "working" : "awake"))

            if let sleep = store.snapshot?.player.activeSleep {
                Text(GameStrings.format("sleep.elapsed", sleepDuration(since: sleep.startedAt)))
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    .accessibilityIdentifier("sleepElapsed")
                Text(GameStrings.text("sleep.offline"))
                    .font(.footnote).foregroundStyle(RoomTheme.secondary)
                Button { store.wakeUp() } label: {
                    Label(GameStrings.text("sleep.wake"), systemImage: "sun.max.fill")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle())
                .disabled(store.isBusy)
                .accessibilityIdentifier("sleepWakeButton")
            } else {
                if working {
                    Text(GameStrings.text("sleep.workActive"))
                        .font(.footnote).foregroundStyle(RoomTheme.secondary)
                }
                Button { store.startSleep() } label: {
                    Label(GameStrings.text("sleep.start"), systemImage: "moon.fill")
                        .font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(store.isBusy || working)
                .accessibilityIdentifier("sleepStartButton")
            }
            Text(GameStrings.text("sleep.rate"))
                .font(.footnote).foregroundStyle(RoomTheme.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
    }

    private func sleepDuration(since startedAt: Date) -> String {
        let reference = max(store.now, store.snapshot?.meta.lastSyncAt ?? store.now)
        let interval = max(0, reference.timeIntervalSince(startedAt))
        let seconds = Int(min(interval, 315_360_000))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    private func stat(_ title: String, value: Int) -> some View {
        HStack(spacing: 16) {
            Text(GameStrings.text(title)).font(.system(size: 15, weight: .semibold))
                .frame(width: 76, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.8)
            ProgressView(value: Double(value), total: 100).tint(RoomTheme.mint)
            Text("\(value)").font(.system(size: 15, weight: .semibold)).monospacedDigit().frame(width: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(GameStrings.text(title))
        .accessibilityValue("\(value)")
    }
}
