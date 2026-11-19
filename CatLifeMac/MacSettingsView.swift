#if os(macOS)
import AppKit
import SwiftUI
import CatGameCore

@MainActor
struct MacSettingsView: View {
    @Bindable var store: GameStore
    @Bindable var preferences: MacPreferences
    let windowController: MacWindowController
    var onTitle: () -> Void
    var onReplayTour: () -> Void = {}
    @State private var selected = Section.display
    @State private var audioDraft = AudioSettings()
    @State private var audioSaveTask: Task<Void, Never>?
    @State private var audioRequest = 0
    @State private var audioSaving = false
    @State private var audioFailure = false
    @State private var showsSaves = false
    @State private var notificationDenied = false
    @State private var requestingNotifications = false
    @State private var bindingError: String?
    @State private var homeName = ""
    @State private var savingHomeName = false
    @State private var homeNameSaved = false

    private enum Section: String, CaseIterable, Identifiable {
        case display, audio, controls, game, saves, language, about
        var id: String { rawValue }
        @MainActor var title: String { GameStrings.text("mac.settings." + rawValue) }
        var symbol: String {
            switch self {
            case .display: "display"
            case .audio: "speaker.wave.2.fill"
            case .controls: "keyboard.fill"
            case .game: "gamecontroller.fill"
            case .saves: "externaldrive.badge.checkmark"
            case .language: "character.bubble.fill"
            case .about: "info.circle.fill"
            }
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            sidebar.frame(width: 188)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(selected.title, systemImage: selected.symbol).font(.system(size: 20, weight: .heavy, design: .rounded))
                    content
                }
                .padding(.horizontal, 22).padding(.vertical, 18).frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .gameCard(cornerRadius: 24)
            .accessibilityIdentifier("macSettingsContent")
        }
        .font(.system(size: 14, weight: .semibold, design: .rounded)).tint(RoomTheme.mint)
        .foregroundStyle(RoomTheme.ink)
        .onAppear {
            audioDraft = store.pendingAudioSettings ?? store.audioSettings
            homeName = store.homeDisplayName
        }
        .onChange(of: audioDraft) { _, _ in scheduleAudioSave() }
        .onChange(of: store.saveSceneGeneration) { _, _ in
            audioRequest += 1; audioSaveTask?.cancel(); audioSaving = false; audioFailure = false
            audioDraft = store.audioSettings; homeName = store.homeDisplayName
        }
        .onDisappear { audioSaveTask?.cancel(); commitAudio() }
        .onReceive(NotificationCenter.default.publisher(for: .macFlushSettings69)) { note in
            audioSaveTask?.cancel()
            (note.object as? MacSettingsFlushRequest)?.save = commitAudio()
        }
        .sheet(isPresented: $showsSaves) {
            SaveManagementView(store: store)
                .frame(minWidth: 740, minHeight: 640)
                .fontDesign(.rounded).foregroundStyle(RoomTheme.ink)
        }
        .alert(GameStrings.text("mac.settings.shortcutError"), isPresented: Binding(get: { bindingError != nil }, set: { if !$0 { bindingError = nil } })) {
            Button(GameStrings.text("common.done")) { bindingError = nil }
        } message: { Text(bindingError ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Section.allCases) { section in
                Button { selected = section } label: {
                    Label(section.title, systemImage: section.symbol)
                        .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .padding(.horizontal, 10)
                        .foregroundStyle(selected == section ? RoomTheme.darkMint : RoomTheme.ink)
                        .background(selected == section ? RoomTheme.paleMint : .clear, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain).accessibilityAddTraits(selected == section ? .isSelected : [])
                .accessibilityIdentifier("macSettingsTab_" + section.rawValue)
            }
            Spacer(minLength: 16)
            Button(GameStrings.text("mac.settings.returnTitle"), action: onTitle)
                .buttonStyle(SoftButtonStyle()).controlSize(.small).accessibilityIdentifier("macReturnTitle")
            Text(AppVersion.current.localizedDisplay + " · Mac")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).padding(.top, 6)
        }
        .padding(10).frame(maxHeight: .infinity).gameCard(cornerRadius: 20)
    }
    @ViewBuilder private var content: some View {
        switch selected {
        case .display: displayContent
        case .audio: audioContent
        case .controls: controlsContent
        case .game: gameContent
        case .saves: savesContent
        case .language: languageContent
        case .about: aboutContent
        }
    }
    private var displayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
        group("mac.settings.group.window") {
            row("mac.settings.windowMode", detail: "mac.settings.windowModeHint") {
                MacSegmented(selection: $preferences.windowMode, options: MacWindowMode.allCases.map { ($0, GameStrings.text($0.titleKey)) })
                .onChange(of: preferences.windowMode) { _, _ in windowController.apply() }
                .accessibilityIdentifier("macWindowMode")
            }
            row("mac.settings.windowSize", detail: "mac.settings.windowSizeHint") {
                Menu {
                    ForEach([CGSize(width: 1280, height: 720), .init(width: 1440, height: 900), .init(width: 1920, height: 1080)], id: \.width) { size in
                        Button("\(Int(size.width)) × \(Int(size.height))") { windowController.setContentSize(size) }
                    }
                } label: { Text(currentWindowSize).frame(minWidth: 165) }
                .disabled(preferences.windowMode != .windowed).accessibilityIdentifier("macWindowSize")
            }
            row("mac.settings.scale", detail: "mac.settings.scaleHint") {
                MacSegmented(selection: $preferences.interfaceScale, options: [(1.0, "100%"), (1.25, "125%"), (1.5, "150%")]).accessibilityIdentifier("macInterfaceScale")
            }
            row("mac.settings.frameLimit", detail: "mac.settings.frameLimitHint") {
                MacSegmented(selection: $preferences.frameLimit, options: [30, 60, 120].map { ($0, String($0)) }).accessibilityIdentifier("macFrameLimit")
            }
            toggleRow("mac.settings.onTop", detail: "mac.settings.onTopHint", value: $preferences.alwaysOnTop, id: "macAlwaysOnTop", last: true)
                .onChange(of: preferences.alwaysOnTop) { _, _ in windowController.apply() }
        }
        group("mac.settings.group.visual") {
            toggleRow("mac.settings.reduceMotion", detail: "mac.settings.reduceMotionHint", value: $preferences.reduceMotion, id: "macReduceMotion")
            toggleRow("mac.settings.daylight", detail: "mac.settings.daylightHint", value: $preferences.followDaylight, id: "macFollowDaylight")
            row("mac.settings.intro", detail: "mac.settings.introHint", last: true) {
                Button(GameStrings.text("mac.settings.introPlay")) { NotificationCenter.default.post(name: .macReplayIntro, object: nil) }
                    .buttonStyle(SoftButtonStyle()).controlSize(.small).fixedSize().accessibilityIdentifier("macReplayIntro")
            }
        }
            HStack { Spacer(); Button(GameStrings.text("mac.settings.restoreDisplay")) { preferences.restoreDisplay(); windowController.apply() }.buttonStyle(SoftButtonStyle()).controlSize(.small).fixedSize() }
        }
    }
    private var currentWindowSize: String {
        let size = windowController.window?.contentView?.bounds.size ?? CGSize(width: 1440, height: 900)
        return "\(Int(size.width)) × \(Int(size.height))"
    }
    private var audioContent: some View {
        VStack(alignment: .leading, spacing: 12) {
        group("mac.settings.group.volume") {
            audioRow("audio.music", enabled: $audioDraft.musicEnabled, volume: $audioDraft.musicVolume, preview: store.previewMusic)
            audioRow("audio.effects", enabled: $audioDraft.effectsEnabled, volume: $audioDraft.effectsVolume, preview: store.previewSoundEffect)
            audioRow("audio.cat", enabled: $audioDraft.catEnabled, volume: $audioDraft.catVolume, last: true, preview: store.previewCatVoice)
        }
        group("mac.settings.group.music") {
            row("audio.musicChoice", detail: "audio.musicChoiceDetail") {
                Menu {
                    Button { audioDraft.musicChoice = nil } label: { choiceLabel("audio.musicChoice.scene", picked: audioDraft.musicChoice == nil) }
                    Divider()
                    ForEach(GameMusicTrack.pickable, id: \.self) { track in
                        Button { audioDraft.musicChoice = track.rawValue } label: { choiceLabel(track.nameKey, picked: audioDraft.musicChoice == track.rawValue) }
                    }
                } label: { Text(GameStrings.text(pickedMusicKey)).frame(minWidth: 165) }
                .fixedSize().disabled(!audioDraft.musicEnabled).accessibilityIdentifier("macMusicChoice")
            }
            toggleRow("audio.sceneMusic", detail: "audio.sceneMusicDetail", value: $audioDraft.sceneMusic, id: "macSceneMusic")
                .disabled(pickedMusicKey != "audio.musicChoice.scene")
            toggleRow("audio.nightQuiet", detail: "audio.nightQuietDetail", value: $audioDraft.nightQuiet, id: "macQuietHours")
            toggleRow("mac.settings.backgroundAudio", detail: "mac.settings.backgroundAudioHint", value: $preferences.backgroundAudio, id: "macBackgroundAudio", last: true)
        }
            HStack {
                if audioSaving { ProgressView().controlSize(.small); Text(GameStrings.text("common.saving")) }
                else if audioFailure { Label(GameStrings.text("save.writeTitle"), systemImage: "exclamationmark.triangle.fill").foregroundStyle(RoomTheme.coral) }
                else { Label(GameStrings.text("mac.settings.audioSaved"), systemImage: "checkmark.circle.fill").foregroundStyle(RoomTheme.darkMint) }
                Spacer()
                if audioFailure { Button(GameStrings.text("save.retry")) { commitAudio() } }
            }
            .font(.system(size: 12, weight: .bold))
        }
        .disabled(store.isDecorating || store.saveTransferInProgress)
    }
    /// The picked song's name, or "follow the scene" (also for a name this build does not know).
    private var pickedMusicKey: String {
        guard let track = audioDraft.musicChoice.flatMap(GameMusicTrack.init(rawValue:)), GameMusicTrack.pickable.contains(track)
        else { return "audio.musicChoice.scene" }
        return track.nameKey
    }
    @ViewBuilder private func choiceLabel(_ key: String, picked: Bool) -> some View {
        if picked { Label(GameStrings.text(key), systemImage: "checkmark") } else { Text(GameStrings.text(key)) }
    }
    private func audioRow(_ key: String, enabled: Binding<Bool>, volume: Binding<Double>, last: Bool = false,
                          preview: @escaping () -> Void) -> some View {
        row(key, last: last) {
            HStack(spacing: 10) {
                Toggle("", isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                Slider(value: volume, in: 0...1).frame(width: 170).disabled(!enabled.wrappedValue)
                Text("\(Int(volume.wrappedValue * 100))%").font(.system(size: 12.5, weight: .bold)).monospacedDigit().frame(width: 40)
                Button(action: preview) { Image(systemName: "play.fill").frame(width: 24, height: 24) }
                    .disabled(!enabled.wrappedValue || volume.wrappedValue == 0)
                    .accessibilityLabel(GameStrings.text("mac.settings.previewAudio"))
            }
        }
    }
    private var controlsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            group("mac.settings.group.input") {
                toggleRow("mac.settings.reverseWheel", detail: "mac.settings.reverseWheelHint", value: $preferences.wheelReversed, id: "macReverseWheel")
                toggleRow("mac.settings.contextMenus", detail: "mac.settings.contextMenusHint", value: $preferences.contextMenus, id: "macContextMenus")
                toggleRow("mac.settings.hoverHints", detail: "mac.settings.hoverHintsHint", value: $preferences.hoverHints, id: "macHoverHints", last: true)
            }
            Text(GameStrings.text("mac.settings.rebindHint")).font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach([("mac.shortcuts.navigation", Array(MacCommand.allCases.filter { $0.scope == .global })),
                     ("mac.shortcuts.home", Array(MacCommand.allCases.filter { [.feed, .clean, .play, .nextCat, .viewLeft, .viewRight, .focusCat, .catProfile, .decorate].contains($0) })),
                     ("mac.shortcuts.build", Array(MacCommand.allCases.filter { [.rotateLeft, .rotateRight, .nudgeLeft, .nudgeRight, .nudgeUp, .nudgeDown, .grid, .putAway, .confirm, .undo, .redo, .save, .search].contains($0) })),
                     ("mac.shortcuts.more", [.listUp, .listDown, .previousPage, .nextPage, .returnHome, .recovery])], id: \.0) { heading, commands in
                VStack(alignment: .leading, spacing: 0) {
                    Text(GameStrings.text(heading)).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.secondary).padding(.bottom, 6)
                    ForEach(commands, id: \.self) { command in shortcutRow(command) }
                }
            }
            }
            HStack {
                Spacer()
                Button(GameStrings.text("mac.settings.restoreShortcuts")) { preferences.restoreShortcuts() }
                    .buttonStyle(SoftButtonStyle()).controlSize(.small).fixedSize().accessibilityIdentifier("macRestoreShortcuts")
            }
        }
    }
    private func shortcutRow(_ command: MacCommand) -> some View {
        HStack {
            Text(GameStrings.text(command.titleKey)).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85); Spacer()
            MacShortcutRecorder(label: preferences.binding(for: command).label) { binding in
                guard let conflict = preferences.rebind(command, to: binding) else { return }
                switch conflict {
                case .reserved: bindingError = GameStrings.text("mac.settings.shortcutReserved")
                case .unsupported: bindingError = GameStrings.text("mac.settings.shortcutUnsupported")
                case .duplicate(let other): bindingError = GameStrings.format("mac.settings.shortcutDuplicate", GameStrings.text(other.titleKey))
                }
            }
            .frame(width: 108, height: 26).accessibilityIdentifier("macShortcut_" + command.rawValue)
        }
        .frame(minHeight: 34).padding(.horizontal, 10)
        .background(RoomTheme.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
        .padding(.bottom, 3)
    }
    private var gameContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GameStrings.text("mac.settings.gameHint")).font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
        group {
            row("settings.homeName", detail: homeNameSaved ? "homeName.saved" : nil) {
                HStack(spacing: 10) {
                    TextField(GameStrings.text("settings.homeName"), text: $homeName).textFieldStyle(.roundedBorder).frame(width: 230).accessibilityIdentifier("macHomeNameField")
                    Button(GameStrings.text("homeName.save")) { saveHomeName() }.disabled(store.isBusy || savingHomeName).accessibilityIdentifier("macSaveHomeName")
                }
            }
            row("mac.settings.tour", detail: "mac.settings.tourHint") {
                Button(GameStrings.text("mac.settings.tourReplay"), action: onReplayTour)
                    .disabled(store.isBusy || store.isDecorating || !store.hasEnteredHome).accessibilityIdentifier("macReplayTour")
            }
            row("mac.settings.notifications", detail: "mac.settings.notificationsHint", last: true) {
                Toggle("", isOn: Binding(get: { preferences.notificationsEnabled }, set: { enabled in
                    guard !requestingNotifications else { return }
                    if !enabled { preferences.notificationsEnabled = false; return }
                    requestingNotifications = true
                    Task { @MainActor in
                        preferences.notificationsEnabled = await MacNotifications.requestPermission()
                        notificationDenied = !preferences.notificationsEnabled
                        requestingNotifications = false
                    }
                })).labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(requestingNotifications).accessibilityIdentifier("macNotifications")
            }
        }
            if notificationDenied { Text(GameStrings.text("mac.settings.notificationDenied")).foregroundStyle(RoomTheme.coral) }
        }
    }
    private var savesContent: some View {
        group {
            row("mac.settings.localSaves", detail: "mac.settings.localSavesHint", last: true) {
                Button(GameStrings.text("saveTransfer.title")) { showsSaves = true }
                    .buttonStyle(MintButtonStyle()).fixedSize().disabled(store.isBusy || store.isDecorating || store.saveTransferInProgress)
                    .accessibilityIdentifier("macOpenSaveManagement")
            }
        }
    }
    private var languageContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GameStrings.text("settings.languageHint")).font(.system(size: 12, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            HStack(spacing: 10) {
            ForEach(GameLanguage.allCases, id: \.self) { language in
                Button { store.setLanguage(language) } label: {
                    HStack {
                        Text(language == .simplifiedChinese ? "简体中文" : language == .traditionalChinese ? "繁體中文" : "English")
                        Spacer(); if store.language == language { Image(systemName: "checkmark.circle.fill") }
                    }
                    .font(.system(size: 14, weight: .heavy))
                    .padding(.horizontal, 14).padding(.vertical, 11).frame(maxWidth: 220)
                    .foregroundStyle(store.language == language ? RoomTheme.darkMint : RoomTheme.ink)
                    .background(store.language == language ? RoomTheme.paleMint : RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(store.language == language ? RoomTheme.mint : RoomTheme.track, lineWidth: 1.5))
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain).disabled(store.isBusy || store.saveTransferInProgress)
                .accessibilityAddTraits(store.language == language ? .isSelected : [])
                .accessibilityIdentifier("macLanguage_" + language.rawValue)
            }
            }
        }
    }
    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image("app-icon-preview").resizable().scaledToFit().frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 6) {
                    Text(GameStrings.text("home.name")).font(.title2.weight(.heavy))
                    Text(AppVersion.current.localizedDisplay + " · macOS").foregroundStyle(RoomTheme.secondary)
                }
            }
            Text(GameStrings.text("mac.settings.aboutHint")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary)
            #if APP_STORE
            Link(destination: URL(string: "https://github.com/xdgf558/cat-life-game-mac/blob/main/PRIVACY.md")!) {
                Label(GameStrings.text("mac.settings.privacyPolicy"), systemImage: "hand.raised")
            }
            .accessibilityIdentifier("macPrivacyPolicy")
            #endif
            ForEach(AppRelease.recent) { release in
                VStack(alignment: .leading, spacing: 5) {
                    Text(release.version + " · " + release.localizedDate).font(.system(size: 14, weight: .heavy))
                    Text(GameStrings.text("releases.\(release.build).body")).font(.system(size: 12.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
    /// One setting: title and a short hint on the left, its control on the right. `last` drops the divider.
    private func row<Content: View>(_ title: String, detail: String? = nil, last: Bool = false,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(GameStrings.text(title)).font(.system(size: 14, weight: .heavy))
                if let detail { Text(GameStrings.text(detail)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(RoomTheme.wood.opacity(0.3)).frame(height: 1) } }
    }
    private func toggleRow(_ title: String, detail: String, value: Binding<Bool>, id: String, last: Bool = false) -> some View {
        row(title, detail: detail, last: last) { Toggle("", isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityIdentifier(id) }
    }
    /// A titled card of rows.
    private func group<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(GameStrings.text(title)).font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    .padding(.leading, 4).accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16).padding(.vertical, 2)
                .background(RoomTheme.cream.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(RoomTheme.track.opacity(0.8), lineWidth: 1))
        }
    }
    private func scheduleAudioSave() {
        audioSaveTask?.cancel()
        audioSaveTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            commitAudio()
        }
    }
    @discardableResult
    private func commitAudio() -> Task<Void, Never>? {
        guard store.snapshot != nil, audioDraft != store.audioSettings || audioFailure
                || (store.pendingAudioSettings != nil && store.pendingAudioSettings != audioDraft) else { return nil }
        audioRequest += 1; let request = audioRequest, generation = store.saveSceneGeneration, draft = audioDraft
        audioSaving = true
        return Task { @MainActor in
            let saved = await store.updateAudioSettings(draft)
            guard request == audioRequest, generation == store.saveSceneGeneration else { return }
            audioSaving = false; audioFailure = !saved
        }
    }
    private func saveHomeName() {
        savingHomeName = true; homeNameSaved = false
        Task { @MainActor in
            homeNameSaved = await store.setHomeName(homeName)
            savingHomeName = false
        }
    }
}
@MainActor
final class MacSettingsFlushRequest { var save: Task<Void, Never>? }

extension Notification.Name {
    static let macFlushSettings69 = Notification.Name("CatLifeMac.flushSettings")
}
#endif
