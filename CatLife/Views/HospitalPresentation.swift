import SwiftUI
import CatGameCore

struct HospitalHeader: View {
    let title: String
    let back: String
    let gold: Int
    var isSaving = false
    var backID = "hospitalBackButton"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: action) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .heavy))
                    Text(GameStrings.text(back)).font(.system(size: 12, weight: .heavy))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 12).frame(minHeight: 44).gameCard(cornerRadius: 24)
            }.buttonStyle(.plain).disabled(isSaving).opacity(isSaving ? 0.4 : 1)
                .accessibilityIdentifier(backID)
            Label(GameStrings.text(title), systemImage: "cross.case.fill")
                .font(.system(size: 17, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.65)
                .padding(.horizontal, 12).frame(minHeight: 46)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(LinearGradient(colors: [.white, RoomTheme.paleCoral.opacity(0.6)],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: RoomTheme.coral, radius: 0, y: 4)
                }
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RoomTheme.coralBorder, lineWidth: 3))
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("hospitalPageTitle")
            Spacer(minLength: 0)
            Label("\(gold)", systemImage: "dollarsign.circle.fill")
                .font(.system(size: 14, weight: .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .padding(.horizontal, 10).frame(minHeight: 36).gameCard(cornerRadius: 22)
                .accessibilityLabel(GameStrings.text("resource.gold")).accessibilityValue("\(gold)")
                .accessibilityIdentifier("hospitalWallet")
        }
        .foregroundStyle(RoomTheme.ink).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
        .background(RoomTheme.cream)
    }
}

struct HospitalCatPortrait: View {
    let cat: CatState
    let size: CGFloat
    var status = false

    var body: some View {
        GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance),
                 symbol: "cat.fill", size: size * 0.84, tint: RoomTheme.gold)
            .frame(width: size, height: size)
            .background(cat.appearance == .orange ? RoomTheme.gold.opacity(0.2) : RoomTheme.track, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .overlay(alignment: .bottomTrailing) {
                if status, cat.healthState?.illness != nil || (cat.healthState?.protectedUntil ?? .distantPast) > Date() {
                    Image(systemName: cat.healthState?.illness == nil ? "checkmark.shield.fill" : "bandage.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 25, height: 25)
                        .background(cat.healthState?.illness == nil ? RoomTheme.mint : RoomTheme.coral, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2)).offset(x: 2, y: 2)
                }
            }
            .accessibilityHidden(true)
    }
}

@MainActor
struct HospitalStatusPill: View {
    let cat: CatState
    let now: Date
    private var sick: Bool { cat.healthState?.illness != nil }
    private var atRisk: Bool { !sick && (cat.healthState?.protectedUntil ?? .distantPast) <= now && (cat.healthState?.riskPoints ?? 0) > 0 }

    var body: some View {
        Label(CatHealthPresentation.status(for: cat, now: now),
              systemImage: sick ? "bandage.fill" : atRisk ? "heart.fill" : "checkmark.shield.fill")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(sick ? RoomTheme.coralDeep : atRisk ? RoomTheme.secondary : RoomTheme.darkMint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(sick ? RoomTheme.paleCoral : atRisk ? RoomTheme.gold.opacity(0.2) : RoomTheme.paleMint, in: Capsule())
    }
}

@MainActor
enum CatHealthPresentation {
    static func status(for cat: CatState, now: Date) -> String {
        if let illness = cat.healthState?.illness {
            return GameStrings.text(CatHealthCatalog.definition(for: illness).nameKey)
        }
        if let health = cat.healthState, health.protectedUntil > now {
            let hours = max(1, Int(ceil(health.protectedUntil.timeIntervalSince(now) / 3600)))
            return GameStrings.format("hospital.protectedHours", hours)
        }
        return GameStrings.text((cat.healthState?.riskPoints ?? 0) > 0 ? "hospital.atRisk" : "hospital.well")
    }
}

enum HospitalCareNeed: String, CaseIterable {
    case satiety, cleanliness, energy

    init(illness: CatIllness) {
        switch illness { case .stomachache: self = .satiety; case .skinProblem: self = .cleanliness; case .cold: self = .energy }
    }
    var illness: CatIllness {
        switch self { case .satiety: .stomachache; case .cleanliness: .skinProblem; case .energy: .cold }
    }
    var nameKey: String { "stat.\(rawValue)" }
    var symbol: String {
        switch self { case .satiety: "fork.knife"; case .cleanliness: "sparkles"; case .energy: "moon.zzz.fill" }
    }
    var tint: Color {
        switch self { case .satiety: RoomTheme.gold; case .cleanliness: RoomTheme.sky; case .energy: RoomTheme.lilac }
    }
    func value(_ cat: CatState) -> Int {
        switch self { case .satiety: cat.satiety; case .cleanliness: cat.cleanliness; case .energy: cat.energy }
    }
}

struct HospitalHealthBar: View {
    let health: Int
    let sick: Bool

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(RoomTheme.track)
                    if sick {
                        Canvas { context, size in
                            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(RoomTheme.paleMint))
                            for x in stride(from: -size.height, to: size.width, by: 12) {
                                var stripe = Path()
                                stripe.move(to: CGPoint(x: x, y: size.height))
                                stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                                context.stroke(stripe, with: .color(RoomTheme.mint.opacity(0.22)), lineWidth: 6)
                            }
                        }
                        .frame(width: geometry.size.width * CGFloat(CatHealthCatalog.treatedHealth) / 100)
                    }
                    Capsule().fill(sick ? RoomTheme.coral : RoomTheme.mint)
                        .frame(width: geometry.size.width * CGFloat(health) / 100)
                    if sick {
                        Rectangle().fill(RoomTheme.coralDeep.opacity(0.6)).frame(width: 2)
                            .offset(x: geometry.size.width * CGFloat(CatHealthCatalog.minimumIllnessHealth) / 100)
                    }
                }.clipShape(Capsule())
            }.frame(height: 14)
            if sick {
                HStack {
                    Text(GameStrings.format("hospital.minimumHealth", CatHealthCatalog.minimumIllnessHealth))
                        .foregroundStyle(RoomTheme.secondary)
                    Spacer(minLength: 8)
                    Text(GameStrings.format("hospital.afterHealth", CatHealthCatalog.treatedHealth))
                        .foregroundStyle(RoomTheme.darkMint)
                }.font(.system(size: 10, weight: .bold))
            }
        }
    }
}
