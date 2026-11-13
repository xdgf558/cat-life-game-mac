import SwiftUI

struct TaskRewardView: View {
    let receipt: TaskClaimReceipt
    let dismiss: () -> Void
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        ZStack {
            RoomTheme.ink.opacity(0.32).ignoresSafeArea().onTapGesture(perform: dismiss).accessibilityHidden(true)
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        Circle().fill(RoomTheme.gold.opacity(0.12)).frame(width: 116, height: 116)
                        Circle().fill(RoomTheme.gold.opacity(0.2)).frame(width: 96, height: 96)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                        Image(systemName: "gift").font(.system(size: 45, weight: .bold)).foregroundStyle(RoomTheme.gold)
                        Image(systemName: "sparkles").font(.system(size: 20, weight: .bold))
                            .foregroundStyle(RoomTheme.mint).offset(x: 49, y: -38)
                    }.accessibilityHidden(true)
                    Text(GameStrings.text("tasks.rewardTitle")).font(.system(size: 25, weight: .heavy))
                        .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader).accessibilityFocused($focused)
                    Text(GameStrings.format("tasks.rewardTask", GameStrings.text("task.\(receipt.taskID).title")))
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        reward("resource.gold", value: receipt.goldAwarded, tint: RoomTheme.secondary, background: RoomTheme.gold.opacity(0.2))
                            .accessibilityIdentifier("taskRewardGold").accessibilityValue("\(receipt.goldAwarded)")
                        reward("career.experience", value: receipt.experienceAwarded, tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                            .accessibilityIdentifier("taskRewardExperience").accessibilityValue("\(receipt.experienceAwarded)")
                    }
                    Button(action: dismiss) {
                        Text(GameStrings.text("tasks.rewardDone")).font(.system(size: 17, weight: .heavy)).frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("taskRewardDone")
                }
                .padding(22).frame(maxWidth: 370).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 3))
                .compositingGroup()
                .shadow(color: RoomTheme.ink.opacity(0.16), radius: 20, y: 12)
                .padding(24).frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("taskRewardCelebration").accessibilityValue(receipt.taskID)
        .onAppear { focused = true }
        .task(id: voiceOver) {
            guard !voiceOver else { return }
            do { try await Task.sleep(for: .milliseconds(2400)) } catch { return }
            dismiss()
        }
    }

    private func reward(_ key: String, value: Int, tint: Color, background: Color) -> some View {
        VStack(spacing: 5) {
            Text(GameStrings.text(key)).font(.system(size: 12, weight: .heavy))
            Text("+\(value)").font(.system(size: 26, weight: .heavy)).monospacedDigit()
        }
        .foregroundStyle(tint).padding(12).frame(maxWidth: .infinity)
        .background(background, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
