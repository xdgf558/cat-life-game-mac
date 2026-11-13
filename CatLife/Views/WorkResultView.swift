import SwiftUI
import CatGameCore

@MainActor
struct WorkResultView: View {
    let store: GameStore
    let onHome: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            if let result = store.snapshot?.player.lastWorkResult {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(RoomTheme.gold.opacity(0.12)).frame(width: 128, height: 128)
                        Circle().fill(RoomTheme.paper).frame(width: 108, height: 108)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                            .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 5)
                        Image(systemName: "medal.fill")
                            .font(.system(size: 50, weight: .bold)).foregroundStyle(RoomTheme.gold)
                        Image(systemName: "sparkles").foregroundStyle(RoomTheme.mint)
                            .font(.system(size: 21, weight: .bold)).offset(x: 55, y: -46)
                        Image(systemName: "star.fill").foregroundStyle(RoomTheme.coral)
                            .font(.system(size: 18)).offset(x: -55, y: 40)
                    }
                    .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text(GameStrings.text("redesign.work.finished"))
                            .font(.system(size: 30, weight: .heavy)).multilineTextAlignment(.center)
                            .accessibilityIdentifier("workResultID").accessibilityValue(result.id)
                        Text(WorkJobPresentation.name(result.jobID))
                            .font(.system(size: 16, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                            .accessibilityIdentifier("workResultJob").accessibilityValue(result.jobID)
                        Text(GameStrings.text("redesign.work.finishedHint"))
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 10) {
                            resultValue("career.resultGold", result.goldReward, id: "workResultGold",
                                        tint: RoomTheme.gold, background: RoomTheme.gold.opacity(0.2))
                            resultValue("career.resultExp", result.expReward, id: "workResultExp",
                                        tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                        }
                        HStack(spacing: 6) {
                            Text(GameStrings.format("career.level", result.levelBefore))
                                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                                .accessibilityIdentifier("workResultLevelBefore").accessibilityValue("\(result.levelBefore)")
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(RoomTheme.secondary)
                                .accessibilityHidden(true)
                            Text(GameStrings.format("career.level", result.levelAfter))
                                .font(.system(size: 14, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                                .accessibilityIdentifier("workResultLevelAfter").accessibilityValue("\(result.levelAfter)")
                            Spacer(minLength: 0)
                            Text("\(result.expAfter) / \(WorkCatalog.requiredExperience(forLevel: result.levelAfter))")
                                .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .accessibilityLabel(GameStrings.format("career.exp", result.expAfter,
                                                        WorkCatalog.requiredExperience(forLevel: result.levelAfter)))
                                .accessibilityIdentifier("workResultExpAfter").accessibilityValue("\(result.expAfter)")
                        }
                        ProgressView(value: Double(result.expAfter),
                                     total: Double(max(1, WorkCatalog.requiredExperience(forLevel: result.levelAfter))))
                            .tint(RoomTheme.gold).scaleEffect(x: 1, y: 2)
                        if result.levelAfter > result.levelBefore {
                            Label(GameStrings.format("redesign.work.levelUp", result.levelAfter), systemImage: "sparkles")
                                .font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoomTheme.paleMint, in: RoundedRectangle(cornerRadius: 12))
                        }
                        if !result.newlyUnlockedJobIDs.isEmpty {
                            Text(GameStrings.text("career.newJobs")).font(.subheadline.weight(.bold))
                            ForEach(result.newlyUnlockedJobIDs, id: \.self) { id in
                                Label {
                                    Text(WorkJobPresentation.name(id))
                                } icon: {
                                    GameIcon(asset: WorkJobPresentation.asset(id),
                                             symbol: WorkJobPresentation.symbol(id), size: 22, tint: RoomTheme.darkMint)
                                }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
                                .accessibilityIdentifier("careerUnlocked_\(id)")
                            }
                        }
                        if let cat = store.cat {
                            HStack(spacing: 8) {
                                GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance),
                                         symbol: "cat.fill", size: 30, tint: RoomTheme.gold)
                                Text(GameStrings.format(cat.satiety < 50 ? "redesign.work.catHungry" : "redesign.work.catWaiting",
                                                        GameStrings.catName(cat)))
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                            }
                        }
                    }
                    .padding(18).gameCard(cornerRadius: 28)
                    VStack(spacing: 5) {
                        Text(GameStrings.text("career.resultSaved"))
                        Text(verbatim: result.completedAt.formatted(.dateTime.month().day().hour().minute()
                            .locale(Locale(identifier: store.language.rawValue))))
                            .accessibilityIdentifier("workResultCompletedAt")
                    }
                    .font(.caption).foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center)
                }
                .padding(20).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("careerResultScroll")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.snapshot?.player.lastWorkResult != nil {
                VStack(spacing: 8) {
                    Button(action: onHome) {
                        Label(GameStrings.format("redesign.work.returnHome", store.cat.map(GameStrings.catName) ?? ""),
                              systemImage: "house.fill")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MintButtonStyle()).accessibilityIdentifier("careerResultHomeButton")
                    Button(action: onDone) {
                        Text(GameStrings.text("redesign.work.repeat")).font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SoftButtonStyle()).accessibilityIdentifier("careerResultDoneButton")
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: 520).frame(maxWidth: .infinity)
                .background(RoomTheme.cream)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("careerResultActions")
            }
        }
        .background(RoomTheme.cream)
        .navigationTitle(GameStrings.text("career.resultTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar(.visible, for: .navigationBar)
    }

    private func resultValue(_ key: String, _ value: Int, id: String, tint: Color, background: Color) -> some View {
        VStack(spacing: 5) {
            Text(GameStrings.text(key)).font(.system(size: 13, weight: .heavy))
            Text("+\(value)").font(.system(size: 30, weight: .heavy)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(tint).frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(background, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(key)).accessibilityValue("\(value)").accessibilityIdentifier(id)
    }
}
