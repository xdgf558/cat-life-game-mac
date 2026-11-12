import SwiftUI
import CatGameCore

@MainActor
struct SettingsSoundPage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var settings: AudioSettings
    let track: GameMusicTrack
    let musicPlaying: Bool
    let saving: Bool
    let previewDisabled: Bool
    let onChange: () -> Void
    let onCommit: () -> Void
    let onMusicPreview: () -> Void
    let onEffectsPreview: () -> Void
    let onCatPreview: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            nowPlaying
            control(.music, preview: onMusicPreview)
            control(.effects, preview: onEffectsPreview)
            control(.cat, preview: onCatPreview)
            VStack(spacing: 0) {
                option("audio.sceneMusic", symbol: "map.fill", tint: RoomTheme.mint,
                       keyPath: \.sceneMusic, id: "audioSceneMusicToggle")
                Divider().overlay(RoomTheme.wood.opacity(0.2))
                option("audio.nightQuiet", symbol: "moon.stars.fill", tint: RoomTheme.lilac,
                       keyPath: \.nightQuiet, id: "audioNightQuietToggle")
                Divider().overlay(RoomTheme.wood.opacity(0.2))
                option("audio.haptics", symbol: "iphone.radiowaves.left.and.right", tint: RoomTheme.coral,
                       keyPath: \.haptics, id: "audioHapticsToggle")
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 24).fill(RoomTheme.paper)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white, lineWidth: 2))
                    .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
            }
            if saving {
                ProgressView(GameStrings.text("common.saving"))
                    .font(.footnote).tint(RoomTheme.darkMint)
                    .accessibilityIdentifier("audioSaveStatus")
            }
            Text(GameStrings.text("audio.systemHint"))
                .font(.footnote).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !musicPlaying || reduceMotion)) { context in
                ZStack {
                    Circle().fill(RoomTheme.darkMint)
                    Circle().stroke(.white, lineWidth: 3)
                    Circle().fill(RoomTheme.paper).frame(width: 14, height: 14)
                    Circle().fill(.white.opacity(0.35)).frame(width: 4, height: 4).offset(y: -17)
                }
                .rotationEffect(.degrees(musicPlaying && !reduceMotion ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) * 90 : 0))
            }
            .frame(width: 50, height: 50).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(GameStrings.text(musicPlaying ? "audio.nowPlaying" : "audio.paused") + " · " + GameStrings.text(track.sceneKey))
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                Text(track.title).font(.system(size: 16, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
                Text(GameStrings.text("audio.sceneHint"))
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onMusicPreview) {
                Image(systemName: musicPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 44, height: 44)
                    .background(RoomTheme.paper, in: Circle())
            }
            .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
            .disabled(previewDisabled || !settings.musicEnabled || settings.musicVolume == 0)
            .accessibilityLabel(GameStrings.text(musicPlaying ? "audio.pauseMusic" : "audio.resumeMusic"))
            .accessibilityIdentifier("audioNowPlayingButton")
        }
        .padding(14).foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(RoomTheme.mint)
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.5), lineWidth: 2))
                .shadow(color: RoomTheme.darkMint, radius: 0, y: 4)
        }
        .accessibilityIdentifier("audioNowPlayingCard")
    }

    private func control(_ channel: SettingsAudioControl.Channel, preview: @escaping () -> Void) -> some View {
        SettingsAudioControl(channel: channel, compact: false, settings: $settings,
                             onChange: onChange, onCommit: onCommit,
                             onPreview: preview, previewDisabled: previewDisabled)
    }

    private func option(_ key: String, symbol: String, tint: Color,
                        keyPath: WritableKeyPath<AudioSettings, Bool>, id: String) -> some View {
        Toggle(isOn: Binding(get: { settings[keyPath: keyPath] }, set: { value in
            guard settings[keyPath: keyPath] != value else { return }
            settings[keyPath: keyPath] = value
            onChange()
            onCommit()
        })) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(GameStrings.text(key)).font(.system(size: 14, weight: .heavy))
                    Text(GameStrings.text(key + "Detail")).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(RoomTheme.mint).padding(.vertical, 12)
        .accessibilityIdentifier(id)
    }
}
