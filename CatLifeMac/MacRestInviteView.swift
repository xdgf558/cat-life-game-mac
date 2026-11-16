#if os(macOS)
import SwiftUI
import CatGameCore

/// 2.61: the nap invitation shown when the player picks a bed or cushion in the room, in place of the
/// grey system dialog. A night-sky scene with the cat and the furniture, the cat's energy, what a full
/// nap is good for, then 再等等 (Esc, via the root) and 去休息 (Return, its default action; ⌘↩ via the root too).
@MainActor
struct MacRestInviteView: View {
    let cat: CatState
    let furniture: FurnitureItem
    let reducedMotion: Bool
    /// Why the nap cannot start right now (eating, saving, the room still preparing), read live.
    let reason: () -> String?
    let confirm: () -> Void
    let cancel: () -> Void
    @State private var shown = false
    @FocusState private var focus: Control?
    private enum Control: Hashable { case cancel, confirm }

    var body: some View {
        ZStack {
            RoomTheme.ink.opacity(shown ? 0.24 : 0).ignoresSafeArea()
                .contentShape(Rectangle()).onTapGesture(perform: cancel)
                .accessibilityHidden(true)
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                card(reason: reason(), time: context.date.timeIntervalSinceReferenceDate)
            }
            .scaleEffect(shown || reducedMotion ? 1 : 0.9)
            .offset(y: shown || reducedMotion ? 0 : 14)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            // With keyboard navigation on, focus starts inside the card rather than on the room behind it.
            focus = reason() == nil ? .confirm : .cancel
            withAnimation(reducedMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.72)) { shown = true }
        }
    }

    private func card(reason: String?, time: Double) -> some View {
        VStack(spacing: 14) {
            hero(time: time)
            VStack(spacing: 3) {
                Text(GameStrings.text("mac.rest.kicker")).font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(RoomTheme.lilac).tracking(1.2)
                Text(GameStrings.format("mac.rest.ask", GameStrings.catName(cat)))
                    .font(.system(size: 21, weight: .heavy)).foregroundStyle(RoomTheme.ink)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            energy
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.gold)
                Text(GameStrings.text("mac.rest.hint")).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let reason {
                Label(GameStrings.text(reason), systemImage: "hourglass").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(RoomTheme.coralDeep).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoomTheme.paleCoral.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("macRestInviteReason")
            }
            HStack(spacing: 10) {
                Button(action: cancel) {
                    HStack(spacing: 8) {
                        Text(GameStrings.text("mac.rest.later")).font(.system(size: 14, weight: .heavy))
                        MacKeyCap(value: "esc")
                    }
                }
                .buttonStyle(SoftButtonStyle()).focused($focus, equals: .cancel)
                .accessibilityIdentifier("macRestInviteCancel")
                Button(action: confirm) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 13, weight: .bold))
                        Text(GameStrings.text("mac.rest.confirm")).font(.system(size: 14, weight: .heavy))
                        MacKeyCap(value: "↩")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MintButtonStyle()).disabled(reason != nil)
                // Plain Return, as the ↩ cap says; the game's own confirm binding (⌘↩) also reaches it via the root.
                .keyboardShortcut(.defaultAction).focused($focus, equals: .confirm)
                .accessibilityIdentifier("macRestInviteConfirm")
            }
        }
        .padding(18).frame(width: 384)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white, lineWidth: 3))
        .compositingGroup()
        .shadow(color: RoomTheme.ink.opacity(0.14), radius: 0, y: 7)
        .shadow(color: RoomTheme.ink.opacity(0.2), radius: 26, y: 14)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("macRestInvite")
    }

    /// Dusk sky with the cat looking over at the furniture; the zZ drift up unless motion is reduced.
    private func hero(time: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [RoomTheme.lilac.opacity(0.30), RoomTheme.sky.opacity(0.16), RoomTheme.cream],
                                     startPoint: .top, endPoint: .bottom))
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                Image(systemName: "sparkle").font(.system(size: star.2, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .position(x: 348 * star.0, y: 140 * star.1)
            }
            Image(systemName: "moon.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(RoomTheme.gold)
                .rotationEffect(.degrees(-20)).position(x: 348 - 34, y: 30)
            Ellipse().fill(RoomTheme.ink.opacity(0.08)).frame(width: 250, height: 22).position(x: 174, y: 116)
            GameIcon(asset: FurnitureArtwork68.assetName(for: furniture), symbol: "bed.double.fill", size: 110)
                .position(x: 222, y: 72)
            GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 66)
                .padding(5).background(.white, in: Circle())
                .overlay(Circle().strokeBorder(RoomTheme.lilac.opacity(0.35), lineWidth: 2))
                .shadow(color: RoomTheme.ink.opacity(0.12), radius: 0, y: 3)
                .position(x: 92, y: 70)
            sleepyZ(time: time).position(x: 140, y: 34)
            Label(GameStrings.furnitureName(furniture), systemImage: "bed.double.fill")
                .font(.system(size: 11.5, weight: .heavy)).foregroundStyle(RoomTheme.lilac)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.92), in: Capsule())
                .position(x: 174, y: 124)
        }
        .frame(width: 348, height: 140)
        .accessibilityHidden(true)
    }

    private func sleepyZ(time: Double) -> some View {
        let phase = reducedMotion ? 0 : (time.truncatingRemainder(dividingBy: 2) / 2)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3) { index in
                Text("z").font(.system(size: CGFloat(11 + index * 4), weight: .black))
                    .foregroundStyle(RoomTheme.lilac.opacity(0.55 + 0.15 * Double(index)))
                    .offset(y: CGFloat(-index * 6) - (reducedMotion ? 0 : CGFloat(sin((phase + Double(index) * 0.2) * .pi * 2)) * 2))
            }
        }
        .animation(reducedMotion ? nil : .easeInOut(duration: 0.5), value: phase)
    }

    private var energy: some View {
        let value = max(0, min(100, cat.energy))
        let moodKey = value >= 70 ? "mac.rest.energy.high" : value >= 35 ? "mac.rest.energy.mid" : "mac.rest.energy.low"
        return HStack(spacing: 10) {
            Image(systemName: "moon.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.lilac)
            Text(GameStrings.text("mac.rest.energy")).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(RoomTheme.ink)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(RoomTheme.track)
                    Capsule().fill(RoomTheme.lilac.opacity(0.75)).frame(width: max(8, geometry.size.width * CGFloat(value) / 100))
                }
            }
            .frame(height: 8)
            Text("\(value)").font(.system(size: 12.5, weight: .heavy).monospacedDigit()).foregroundStyle(RoomTheme.ink)
            Text(GameStrings.text(moodKey)).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.lilac)
                .padding(.horizontal, 8).padding(.vertical, 3).background(RoomTheme.lilac.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.format("home68.rest.energy", value) + ", " + GameStrings.text(moodKey))
    }

    /// x, y as fractions of the hero, and size.
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.18, 9), (0.30, 0.10, 7), (0.55, 0.16, 10), (0.70, 0.08, 6), (0.95, 0.40, 8), (0.04, 0.55, 6)
    ]
}
#endif
