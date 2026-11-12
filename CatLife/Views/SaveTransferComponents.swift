import SwiftUI
import CatGameCore

@MainActor
enum SaveTransferPresentation {
    static func date(_ date: Date, language: GameLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.rawValue)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func player(_ snapshot: GameSnapshot) -> String {
        snapshot.player.profile.name ?? GameStrings.text("player.name.default")
    }

    static func summary(_ snapshot: GameSnapshot) -> String {
        GameStrings.format("saveTransfer.recoverySummary", snapshot.player.level, snapshot.cats.count)
    }
}

struct SaveTransferOutlineButtonStyle: ButtonStyle {
    var tint = RoomTheme.darkMint
    var fill = RoomTheme.paper
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(fill, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(tint.opacity(0.25), lineWidth: 2))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}

struct SaveTransferNotice: View {
    let text: String
    let symbol: String
    var tint = RoomTheme.lilac

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).accessibilityHidden(true)
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(tint)
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(tint.opacity(0.28), lineWidth: 2))
    }
}

struct SaveTransferStats: View {
    let snapshot: GameSnapshot
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6),
                            count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
        LazyVGrid(columns: columns, spacing: 8) {
            stat("saveTransfer.stat.level", value: snapshot.player.level, symbol: "star.fill", tint: RoomTheme.gold)
            stat("saveTransfer.stat.gold", value: snapshot.player.gold, symbol: "dollarsign.circle.fill", tint: RoomTheme.gold)
            stat("saveTransfer.stat.cats", value: snapshot.cats.count, symbol: "cat.fill", tint: RoomTheme.coral)
            stat("saveTransfer.stat.room", value: snapshot.home.roomLevel, symbol: "house.fill", tint: RoomTheme.darkMint)
        }
    }

    private func stat(_ key: String, value: Int, symbol: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.headline).foregroundStyle(tint).accessibilityHidden(true)
            Text("\(value)").font(.headline.weight(.heavy)).monospacedDigit()
            Text(GameStrings.text(key)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
        }
        .padding(.vertical, 12).padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct SaveTransferPostcard: View {
    let filename: String
    var byteCount: Int?
    var subtitle: String?
    var snapshot: GameSnapshot?
    var isRecovery = false
    var prepared = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    stamp
                    fileSize
                    Spacer(minLength: 0)
                    preparedMark
                }
                fileDescription.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 10) {
                    stamp
                    fileDescription
                    Spacer(minLength: 0)
                    fileSize
                    preparedMark
                }
            }
            if let snapshot { SaveTransferStats(snapshot: snapshot) }
        }
        .padding(14)
        .background {
            RoomTheme.rewardPaper
                .overlay(SaveTransferPostcardStripes().stroke(RoomTheme.rewardBorder.opacity(0.2), lineWidth: 12))
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(RoomTheme.rewardBorder,
                                                               style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }

    private var stamp: some View {
        Image(systemName: isRecovery ? "clock.arrow.circlepath" : "pawprint.fill")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(isRecovery ? RoomTheme.lilac : RoomTheme.gold)
            .frame(width: 38, height: 42)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }

    private var fileDescription: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: filename).font(.subheadline.weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var fileSize: some View {
        if let byteCount {
            Text(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder private var preparedMark: some View {
        if prepared {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(RoomTheme.mint)
                .font(.system(size: 20, weight: .bold)).accessibilityHidden(true)
        }
    }
}

private struct SaveTransferPostcardStripes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for x in stride(from: -rect.height, through: rect.width + rect.height, by: 24) {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
        }
        return path
    }
}

struct SaveTransferWorkingView: View {
    var recoveryOnly = false
    var restoring = true

    var body: some View {
        VStack(spacing: 20) {
            ProgressView().controlSize(.large).tint(RoomTheme.mint)
                .frame(width: 78, height: 78)
                .background(RoomTheme.paleMint.opacity(0.4), in: Circle())
            Text(GameStrings.text("saveTransfer.working"))
                .font(.title3.weight(.heavy)).multilineTextAlignment(.center)
            if restoring {
                Text(GameStrings.text("saveTransfer.processIncludes"))
                    .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    step("saveTransfer.step.settle", symbol: "moon.stars")
                    step(recoveryOnly ? "saveTransfer.step.originals" : "saveTransfer.step.recovery", symbol: "checkmark.shield")
                    step("saveTransfer.step.write", symbol: "square.and.arrow.down")
                }
            }
            Text(GameStrings.text("saveTransfer.keepOpen"))
                .font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
        }
        .padding(24).frame(maxWidth: 400).gameCard(cornerRadius: 32)
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoomTheme.ink.opacity(0.18).ignoresSafeArea())
        .accessibilityIdentifier("saveTransferProgress")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func step(_ key: String, symbol: String) -> some View {
        Label(GameStrings.text(key), systemImage: symbol)
            .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
