import SwiftUI
import CatGameCore

struct HospitalRecovery {
    let before: CatState
    let after: CatState
    let illness: CatIllness
    let cost: Int
}

struct HospitalTreatingView: View {
    let cat: CatState
    let started: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: scenePhase != .active)) { timeline in
                let elapsed = started.map { max(0, timeline.date.timeIntervalSince($0)) } ?? 0
                let progress = min(1, elapsed / 2)
                VStack(spacing: 24) {
                    ZStack {
                        Circle().stroke(RoomTheme.coralBorder, style: StrokeStyle(lineWidth: 5, dash: [10, 6]))
                            .rotationEffect(.degrees(reduceMotion ? 0 : elapsed * 150))
                            .frame(width: 196, height: 196)
                        HospitalCatPortrait(cat: cat, size: 164)
                            .offset(y: reduceMotion ? 0 : sin(elapsed * .pi * 2) * 3)
                        Image(systemName: "stethoscope").font(.system(size: 25, weight: .bold))
                            .foregroundStyle(.white).frame(width: 50, height: 50)
                            .background(RoomTheme.coral, in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 3))
                            .offset(x: 74, y: -72)
                    }.accessibilityHidden(true).padding(.vertical, 18)
                    Text(GameStrings.format("hospital.treating", GameStrings.catName(cat)))
                        .font(.system(size: 24, weight: .heavy)).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if started == nil {
                        ProgressView().tint(RoomTheme.mint)
                        Text(GameStrings.text("common.saving")).font(.subheadline.weight(.semibold))
                    } else {
                        ProgressView(value: progress).tint(RoomTheme.mint).scaleEffect(y: 2, anchor: .center)
                        HStack(alignment: .top) {
                            step("hospital.step.check", symbol: "stethoscope", active: true, completed: progress > 0.33)
                            Spacer(minLength: 0)
                            step("hospital.step.medicine", symbol: "pills.fill", active: progress >= 0.33, completed: progress > 0.66)
                            Spacer(minLength: 0)
                            step("hospital.step.rest", symbol: "moon.zzz.fill", active: progress >= 0.66, completed: progress >= 1)
                        }
                        Text(GameStrings.text("hospital.treatmentSaved"))
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 24)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("hospitalTreatingState").accessibilityValue(started == nil ? "saving" : "saved")
    }

    private func step(_ key: String, symbol: String, active: Bool, completed: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: completed ? "checkmark" : symbol).font(.system(size: 21, weight: .bold))
                .foregroundStyle(active ? .white : RoomTheme.secondary.opacity(0.5))
                .frame(width: 44, height: 44).background(active ? RoomTheme.mint : RoomTheme.track, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            Text(GameStrings.text(key)).font(.system(size: 12, weight: .heavy))
                .foregroundStyle(active ? RoomTheme.darkMint : RoomTheme.secondary.opacity(0.5))
        }.frame(maxWidth: .infinity)
    }
}

struct HospitalRecoveryView: View {
    let recovery: HospitalRecovery
    let home: () -> Void
    let directory: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(RoomTheme.paleMint.opacity(0.75)).frame(width: 178, height: 178)
                    HospitalCatPortrait(cat: recovery.after, size: 150)
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 29, weight: .bold))
                        .foregroundStyle(.white).frame(width: 54, height: 54)
                        .background(RoomTheme.mint, in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .offset(x: 62, y: 58)
                    Image(systemName: "sparkles").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(RoomTheme.gold).offset(x: -75, y: -62)
                    Image(systemName: "heart.fill").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(RoomTheme.coral).offset(x: 58, y: -72)
                }.accessibilityHidden(true).padding(.top, 8)
                Text(GameStrings.format("hospital.recoveryTitle", GameStrings.catName(recovery.after)))
                    .font(.system(size: 30, weight: .heavy)).multilineTextAlignment(.center)
                    .accessibilityIdentifier("hospitalHealthyState").accessibilityAddTraits(.isHeader)
                Text(GameStrings.format("hospital.recoverySubtitle", GameStrings.text(CatHealthCatalog.definition(for: recovery.illness).nameKey)))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    .multilineTextAlignment(.center)
                resultCard
                Button(action: home) {
                    Label(GameStrings.format("hospital.bringHome", GameStrings.catName(recovery.after)), systemImage: "house.fill")
                        .font(.system(size: 17, weight: .heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("hospitalRecoveryHome")
                Button(action: directory) {
                    Text(GameStrings.text("hospital.returnDirectory")).font(.system(size: 15, weight: .heavy))
                }.buttonStyle(SoftButtonStyle()).accessibilityIdentifier("hospitalRecoveryDirectory")
            }
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background { HospitalRecoveryRays().fill(RoomTheme.paleMint.opacity(0.45)).clipped() }
        .accessibilityIdentifier("hospitalRecoveryScroll")
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label(GameStrings.text("stat.health"), systemImage: "heart.fill").font(.system(size: 15, weight: .heavy))
                Spacer(minLength: 0)
                Text("\(recovery.before.health)").strikethrough().foregroundStyle(RoomTheme.secondary.opacity(0.6))
                Image(systemName: "arrow.right").font(.caption.weight(.bold))
                Text("\(recovery.after.health)").font(.system(size: 24, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text("stat.health"))
            .accessibilityValue("\(recovery.after.health)/100").accessibilityIdentifier("hospitalHealth")
            HStack(spacing: 8) {
                result(GameStrings.format("hospital.protectionShort", Int(CatHealthCatalog.protectionDuration / 3600)),
                       symbol: "checkmark.shield.fill", tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                result(GameStrings.format("hospital.moodGain", max(0, recovery.after.mood - recovery.before.mood)),
                       symbol: "heart.fill", tint: RoomTheme.coralDeep, background: RoomTheme.paleCoral)
                result("−\(recovery.cost)", symbol: "dollarsign.circle.fill", tint: RoomTheme.secondary,
                       background: RoomTheme.gold.opacity(0.2))
                    .accessibilityIdentifier("hospitalRecoveryCost").accessibilityValue("\(recovery.cost)")
            }
            Text(GameStrings.text("hospital.protectionHint"))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("hospitalProtectionHint")
        }
        .padding(16).frame(maxWidth: .infinity).gameCard(cornerRadius: 26)
    }

    private func result(_ text: String, symbol: String, tint: Color, background: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold)).accessibilityHidden(true)
            Text(text).font(.system(size: 11, weight: .heavy)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint).frame(maxWidth: .infinity, minHeight: 64).padding(5)
        .background(background, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct HospitalRecoveryRays: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.height * 0.22)
        let radius = max(rect.width, rect.height) * 2
        var path = Path()
        for index in 0..<18 {
            let angle = Double(index) * .pi / 9
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            path.addLine(to: CGPoint(x: center.x + cos(angle + .pi / 18) * radius, y: center.y + sin(angle + .pi / 18) * radius))
            path.closeSubpath()
        }
        return path
    }
}
