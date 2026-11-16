#if os(macOS)
import AppKit
import SwiftUI
import CatGameCore

/// 2.6: the opening animation, shown over the title screen on first launch (Settings can replay it).
/// Three shots, all computed from the time since it started:
///   1. the morning Cat Town street, a slow pan;
///   2. the home's window, cats popping up over the sill one by one;
///   3. the emblem stamps down, the game's name and tagline fade in, then everything fades to the title.
/// A click or any key skips it. With reduce motion the pans, pops and stamp become plain fades.
/// New art (`intro-town-wide`, `intro-home-window`, `intro-emblem`) is used when present; until then the
/// garden map, the café interior with a drawn sill, and the app icon stand in.
@MainActor
struct MacIntroView: View {
    let store: GameStore
    let reducedMotion: Bool
    let onFinish: () -> Void
    @State private var start = Date()
    @State private var finished = false
    @State private var cues: Task<Void, Never>?
    @FocusState private var focused: Bool

    static let duration: Double = 10.6
    private static let townEnd = 3.4, homeEnd = 6.6, logoEnd = 9.6
    /// The sill line in `intro-home-window` (and the drawn stand-in), as a fraction of the height.
    private static let sill: CGFloat = 0.70
    /// Cats popping up over the sill: breed, horizontal position, height as a fraction of the screen, delay.
    private static let peekers: [(CatAppearance, CGFloat, CGFloat, Double)] = [
        (.orange, 0.50, 0.34, 0.5), (.cow, 0.33, 0.25, 1.0), (.blue, 0.67, 0.25, 1.3),
        (.siamese, 0.18, 0.19, 1.6), (.silver, 0.82, 0.19, 1.9)
    ]

    private static func has(_ asset: String) -> Bool { NSImage(named: asset) != nil }
    private var townAsset: String { Self.has("intro-town-wide") ? "intro-town-wide" : "outing-garden-map" }
    private var homeArt: Bool { Self.has("intro-home-window") }

    var body: some View {
        TimelineView(.animation(paused: finished)) { context in
            let t = max(0, context.date.timeIntervalSince(start))
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    Color.black
                    town(t, size: size)
                    home(t, size: size)
                    logo(t, size: size)
                    skip(t)
                }
                .frame(width: size.width, height: size.height).clipped()
            }
            .opacity(1 - Self.ease(Self.progress(t, Self.logoEnd, Self.duration)))
        }
        .ignoresSafeArea()
        .fontDesign(.rounded)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress { _ in finish(); return .handled }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GameStrings.text("intro.title"))
        .accessibilityIdentifier("macIntro")
        .onAppear { begin() }
        .onDisappear { cues?.cancel() }
    }

    // MARK: Shots

    private func town(_ t: Double, size: CGSize) -> some View {
        let pan = Self.ease(Self.progress(t, 0, Self.townEnd + 0.5))
        let visible = Self.progress(t, 0, 0.9) * (1 - Self.progress(t, Self.townEnd - 0.3, Self.townEnd + 0.5))
        return ZStack {
            Image(townAsset).resizable().scaledToFill().frame(width: size.width, height: size.height)
                .scaleEffect(reducedMotion ? 1.04 : 1.04 + 0.10 * pan)
                .offset(x: reducedMotion ? 0 : (0.5 - pan) * size.width * 0.05)
            caption("intro.caption.town", t: t, from: 0.9, to: Self.townEnd - 0.3, size: size)
        }
        .opacity(visible)
    }

    private func home(_ t: Double, size: CGSize) -> some View {
        let push = Self.ease(Self.progress(t, Self.townEnd - 0.3, Self.logoEnd))
        let sillY = size.height * Self.sill
        return ZStack {
            Group {
                if homeArt {
                    Image("intro-home-window").resizable().scaledToFill()
                } else {
                    // Stand-in: the café's warm room, softened, with a drawn sill in front.
                    Image("cafe-interior").resizable().scaledToFill().overlay(RoomTheme.paper.opacity(0.22))
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(reducedMotion ? 1.05 : 1.02 + 0.10 * push)
            ZStack {
                ForEach(Array(Self.peekers.enumerated()), id: \.offset) { _, peeker in
                    let height = size.height * peeker.2
                    let rise = reducedMotion ? Self.progress(t, Self.townEnd + peeker.3, Self.townEnd + peeker.3 + 0.4)
                        : Self.easeOutBack(Self.progress(t, Self.townEnd + peeker.3, Self.townEnd + peeker.3 + 0.55))
                    Image(CatArtwork.asset("cat-avatar", appearance: peeker.0)).resizable().scaledToFit()
                        .frame(height: height)
                        .position(x: size.width * peeker.1, y: sillY - height * 0.36 + (reducedMotion ? 0 : (1 - rise) * height))
                        .opacity(reducedMotion ? rise : min(1, rise * 3))
                }
            }
            .frame(width: size.width, height: size.height)
            .mask(alignment: .top) { Rectangle().frame(height: sillY) }
            if !homeArt {
                RoundedRectangle(cornerRadius: 8).fill(RoomTheme.wood)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(RoomTheme.secondary.opacity(0.35), lineWidth: 3))
                    .frame(width: size.width * 0.86, height: size.height * 0.07)
                    .position(x: size.width / 2, y: sillY + size.height * 0.03)
                    .shadow(color: RoomTheme.ink.opacity(0.2), radius: 0, y: 5)
            }
            caption("intro.caption.home", t: t, from: Self.townEnd + 2.2, to: Self.homeEnd - 0.2, size: size)
        }
        .opacity(Self.progress(t, Self.townEnd - 0.3, Self.townEnd + 0.5))
    }

    private func logo(_ t: Double, size: CGSize) -> some View {
        let stamp = Self.progress(t, Self.homeEnd + 0.2, Self.homeEnd + 0.75)
        let emblem = min(size.width, size.height) * 0.24
        let name = Self.progress(t, Self.homeEnd + 0.8, Self.homeEnd + 1.4)
        let tagline = Self.progress(t, Self.homeEnd + 1.3, Self.homeEnd + 1.9)
        return ZStack {
            RoomTheme.cream.opacity(0.88 * Self.ease(Self.progress(t, Self.homeEnd - 0.3, Self.homeEnd + 0.5)))
            VStack(spacing: 14) {
                emblemImage.frame(width: emblem, height: emblem)
                    .scaleEffect(reducedMotion ? 1 : 1.8 - 0.8 * Self.easeOutBack(stamp))
                    .rotationEffect(.degrees(reducedMotion ? 0 : -8 * (1 - stamp)))
                    .opacity(Self.progress(t, Self.homeEnd + 0.2, Self.homeEnd + 0.4))
                    .shadow(color: RoomTheme.ink.opacity(0.18), radius: 0, y: 6)
                Text(GameStrings.text("mac.title.name")).font(.system(size: min(52, size.width * 0.05), weight: .heavy))
                    .foregroundStyle(RoomTheme.ink)
                    .opacity(name).offset(y: reducedMotion ? 0 : 14 * (1 - Self.ease(name)))
                Text(GameStrings.text("mac.title.tagline")).font(.system(size: min(20, size.width * 0.02), weight: .bold))
                    .foregroundStyle(RoomTheme.darkMint)
                    .opacity(tagline).offset(y: reducedMotion ? 0 : 10 * (1 - Self.ease(tagline)))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var emblemImage: some View {
        if Self.has("intro-emblem") {
            Image("intro-emblem").resizable().scaledToFit()
        } else if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon).resizable().scaledToFit()
        }
    }

    private func caption(_ key: String, t: Double, from: Double, to: Double, size: CGSize) -> some View {
        Text(GameStrings.text(key)).font(.system(size: min(26, size.width * 0.024), weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(RoomTheme.ink.opacity(0.35), in: Capsule())
            .opacity(Self.progress(t, from, from + 0.6) * (1 - Self.progress(t, to - 0.4, to)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, size.height * 0.07)
            .accessibilityHidden(true)
    }

    private func skip(_ t: Double) -> some View {
        Button { finish() } label: {
            HStack(spacing: 4) {
                Text(GameStrings.text("intro.skip"))
                Image(systemName: "chevron.right.2").font(.system(size: 10, weight: .heavy))
            }
            .font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6).background(RoomTheme.ink.opacity(0.35), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).accessibilityIdentifier("macIntroSkip")
        .opacity(0.85 * Self.progress(t, 1.0, 1.6) * (1 - Self.progress(t, Self.logoEnd - 0.4, Self.logoEnd)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(24)
    }

    // MARK: Timing

    private func begin() {
        start = Date()
        finished = false
        focused = true
        cues?.cancel()
        cues = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.townEnd + 0.55))
            guard !Task.isCancelled else { return }
            store.playFeedback(.pet)
            try? await Task.sleep(for: .seconds(Self.homeEnd + 0.6 - (Self.townEnd + 0.55)))
            guard !Task.isCancelled else { return }
            store.playFeedback(.claim)
            try? await Task.sleep(for: .seconds(Self.duration - (Self.homeEnd + 0.6)))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        cues?.cancel()
        onFinish()
    }

    private static func progress(_ t: Double, _ from: Double, _ to: Double) -> Double {
        min(1, max(0, (t - from) / max(0.001, to - from)))
    }
    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    private static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}

extension Notification.Name { static let macReplayIntro = Notification.Name("MacReplayIntro") }
#endif
