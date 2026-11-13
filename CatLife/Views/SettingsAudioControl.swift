import SwiftUI
import CatGameCore

@MainActor
struct SettingsAudioControl: View {
    enum Channel: String {
        case music, effects, cat

        var enabledKeyPath: WritableKeyPath<AudioSettings, Bool> {
            switch self { case .music: \.musicEnabled; case .effects: \.effectsEnabled; case .cat: \.catEnabled }
        }
        var volumeKeyPath: WritableKeyPath<AudioSettings, Double> {
            switch self { case .music: \.musicVolume; case .effects: \.effectsVolume; case .cat: \.catVolume }
        }
        var symbol: String {
            switch self { case .music: "music.note"; case .effects: "sparkles"; case .cat: "cat.fill" }
        }
        var tint: Color {
            switch self { case .music: RoomTheme.darkMint; case .effects: RoomTheme.gold; case .cat: RoomTheme.coral }
        }
        var toggleID: String {
            switch self { case .music: "audioMusicToggle"; case .effects: "audioEffectsToggle"; case .cat: "audioCatToggle" }
        }
        var sliderID: String {
            switch self { case .music: "audioMusicVolume"; case .effects: "audioEffectsVolume"; case .cat: "audioCatVolume" }
        }
        var previewID: String {
            switch self { case .music: "audioMusicPreviewButton"; case .effects: "audioPreviewButton"; case .cat: "audioCatPreviewButton" }
        }
        var titleKey: String { "audio.\(rawValue)" }
        var detailKey: String { "audio.\(rawValue)Detail" }
        var volumeTitleKey: String { "audio.\(rawValue)Volume" }
    }

    let channel: Channel
    let compact: Bool
    @Binding var settings: AudioSettings
    let onChange: () -> Void
    let onCommit: () -> Void
    var onPreview: (() -> Void)?
    var previewDisabled = false

    var body: some View {
        VStack(spacing: compact ? 4 : 12) {
            Toggle(isOn: Binding(
                get: { settings[keyPath: channel.enabledKeyPath] },
                set: { value in
                    guard settings[keyPath: channel.enabledKeyPath] != value else { return }
                    settings[keyPath: channel.enabledKeyPath] = value
                    onChange()
                    onCommit()
                })) {
                HStack(spacing: 10) {
                    GameIconTile(symbol: channel.symbol, tint: channel.tint,
                                 background: channel.tint.opacity(0.15), size: compact ? 36 : 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(GameStrings.text(channel.titleKey)).font(.system(size: 15, weight: .heavy))
                        if !compact {
                            Text(GameStrings.text(channel.detailKey))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RoomTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .tint(RoomTheme.mint)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier(channel.toggleID)

            HStack(spacing: compact ? 10 : 8) {
                Image(systemName: "speaker.wave.1.fill").foregroundStyle(RoomTheme.secondary)
                    .frame(width: compact ? 36 : 18).accessibilityHidden(true)
                Slider(value: Binding(
                    get: { settings[keyPath: channel.volumeKeyPath] },
                    set: { value in
                        guard settings[keyPath: channel.volumeKeyPath] != value else { return }
                        settings[keyPath: channel.volumeKeyPath] = value
                        onChange()
                    }), in: 0...1, step: 0.05,
                       onEditingChanged: { editing in if !editing { onCommit() } })
                    .tint(RoomTheme.mint)
                    .disabled(!settings[keyPath: channel.enabledKeyPath])
                    .accessibilityLabel(GameStrings.text(channel.volumeTitleKey))
                    .accessibilityValue(volumePercent)
                    .accessibilityIdentifier(channel.sliderID)
                Text(volumePercent)
                    .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
                if !compact, let onPreview {
                    Button(action: onPreview) {
                        Label(GameStrings.text("audio.listen"), systemImage: "play.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(RoomTheme.paper, in: Capsule())
                            .overlay(Capsule().stroke(RoomTheme.mint.opacity(0.25), lineWidth: 2))
                    }
                    .buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(previewDisabled || !settings[keyPath: channel.enabledKeyPath]
                              || settings[keyPath: channel.volumeKeyPath] == 0)
                    .accessibilityLabel(GameStrings.text(channel.titleKey) + " · " + GameStrings.text("audio.listen"))
                    .accessibilityIdentifier(channel.previewID)
                }
            }
        }
        .padding(compact ? 0 : 14)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 24).fill(RoomTheme.paper)
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white, lineWidth: 2))
                    .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
            }
        }
        .opacity(compact || settings[keyPath: channel.enabledKeyPath] ? 1 : 0.6)
    }

    private var volumePercent: String {
        "\(Int((settings[keyPath: channel.volumeKeyPath] * 100).rounded()))%"
    }
}
