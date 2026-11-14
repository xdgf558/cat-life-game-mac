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
                VStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(RoomTheme.coralBorder, style: StrokeStyle(lineWidth: 5, dash: [10, 6]))
                            .rotationEffect(.degrees(reduceMotion ? 0 : elapsed * 150))
                            .frame(width: 136, height: 136)
                        HospitalCatPortrait(cat: cat, size: 112)
                            .offset(y: reduceMotion ? 0 : sin(elapsed * .pi * 2) * 3)
                        Image(systemName: "stethoscope").font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white).frame(width: 36, height: 36)
                            .background(RoomTheme.coral, in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                            .offset(x: 52, y: -50)
                    }.accessibilityHidden(true).padding(.vertical, 6)
                    Text(GameStrings.format("hospital.treating", GameStrings.catName(cat)))
                        .font(.system(size: 20, weight: .heavy)).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if started == nil {
                        ProgressView().tint(RoomTheme.mint)
                        Text(GameStrings.text("common.saving")).font(.subheadline.weight(.semibold))
                    } else {
                        ProgressView(value: progress).tint(RoomTheme.mint).scaleEffect(y: 1.5, anchor: .center)
                            .frame(maxWidth: 420)
                        HStack(alignment: .top) {
                            step("hospital.step.check", symbol: "stethoscope", active: true, completed: progress > 0.33)
                            Spacer(minLength: 0)
                            step("hospital.step.medicine", symbol: "pills.fill", active: progress >= 0.33, completed: progress > 0.66)
                            Spacer(minLength: 0)
                            step("hospital.step.rest", symbol: "moon.zzz.fill", active: progress >= 0.66, completed: progress >= 1)
                        }.frame(maxWidth: 420)
                        Text(GameStrings.text("hospital.treatmentSaved"))
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
                .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("hospitalTreatingState").accessibilityValue(started == nil ? "saving" : "saved")
    }

    private func step(_ key: String, symbol: String, active: Bool, completed: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: completed ? "checkmark" : symbol).font(.system(size: 16, weight: .bold))
                .foregroundStyle(active ? .white : RoomTheme.secondary.opacity(0.5))
                .frame(width: 36, height: 36).background(active ? RoomTheme.mint : RoomTheme.track, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            Text(GameStrings.text(key)).font(.system(size: 12, weight: .heavy))
                .foregroundStyle(active ? RoomTheme.darkMint : RoomTheme.secondary.opacity(0.5))
        }.frame(maxWidth: .infinity)
    }
}

/// The result after treatment: one card (portrait, headline, health change, effect chips) and the two exits.
struct HospitalRecoveryView: View {
    let recovery: HospitalRecovery
    let home: () -> Void
    let directory: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                resultCard
                HStack(spacing: 10) {
                    Button(action: directory) {
                        Text(GameStrings.text("hospital.returnDirectory")).font(.system(size: 14, weight: .heavy))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }.buttonStyle(SoftButtonStyle()).frame(maxWidth: 200)
                        .accessibilityIdentifier("hospitalRecoveryDirectory")
                    Button(action: home) {
                        Label(GameStrings.format("hospital.bringHome", GameStrings.catName(recovery.after)), systemImage: "house.fill")
                            .font(.system(size: 15, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("hospitalRecoveryHome")
                }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("hospitalRecoveryScroll")
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                HospitalCatPortrait(cat: recovery.after, size: 72)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.shield.fill").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white).frame(width: 28, height: 28)
                            .background(RoomTheme.mint, in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .offset(x: 4, y: 4)
                    }
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "sparkles").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(RoomTheme.gold).offset(x: -8, y: -6)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(GameStrings.format("hospital.recoveryTitle", GameStrings.catName(recovery.after)))
                        .font(.system(size: 22, weight: .heavy)).lineLimit(2).minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("hospitalHealthyState").accessibilityAddTraits(.isHeader)
                    Text(GameStrings.format("hospital.recoverySubtitle", GameStrings.text(CatHealthCatalog.definition(for: recovery.illness).nameKey)))
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Label(GameStrings.text("stat.health"), systemImage: "heart.fill")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(recovery.before.health)").font(.system(size: 13, weight: .bold)).strikethrough()
                            .foregroundStyle(RoomTheme.secondary.opacity(0.6))
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(RoomTheme.secondary)
                        Text("\(recovery.after.health)").font(.system(size: 26, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                    }.monospacedDigit()
                }
                .fixedSize()
                .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text("stat.health"))
                .accessibilityValue("\(recovery.after.health)/100").accessibilityIdentifier("hospitalHealth")
            }
            HStack(spacing: 6) {
                chip(GameStrings.format("hospital.protectionShort", Int(CatHealthCatalog.protectionDuration / 3600)),
                     symbol: "checkmark.shield.fill", tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                chip(GameStrings.format("hospital.moodGain", max(0, recovery.after.mood - recovery.before.mood)),
                     symbol: "heart.fill", tint: RoomTheme.coralDeep, background: RoomTheme.paleCoral)
                chip("−\(recovery.cost)", symbol: "dollarsign.circle.fill", tint: RoomTheme.secondary,
                     background: RoomTheme.gold.opacity(0.2))
                    .accessibilityIdentifier("hospitalRecoveryCost").accessibilityValue("\(recovery.cost)")
            }
            Text(GameStrings.text("hospital.protectionHint"))
                .font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("hospitalProtectionHint")
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            HospitalRecoveryRays().fill(RoomTheme.paleMint.opacity(0.4)).allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .gameCard(cornerRadius: 22)
    }

    private func chip(_ text: String, symbol: String, tint: Color, background: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11.5, weight: .heavy)).lineLimit(1)
            .foregroundStyle(tint).padding(.horizontal, 10).padding(.vertical, 6)
            .background(background, in: Capsule())
    }
}

/// Soft rays fanning out from the portrait in the result card's top-left corner.
private struct HospitalRecoveryRays: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.minX + 52, y: rect.minY + 52)
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
