import AVFoundation
import Foundation
import Observation
import CatGameCore
#if os(iOS)
import UIKit
#endif

/// One audio owner per app process. Preferences are committed by GameStore;
/// players and audio-session state are intentionally never part of a game save.
@MainActor
@Observable
final class GameAudioController: NSObject {
    private(set) var settings = AudioSettings()
    private(set) var isForeground = false
    private(set) var currentTrack: GameMusicTrack = .home
    private(set) var musicPlaying = false
    #if DEBUG
    private(set) var effectPlayCount = 0
    private(set) var hapticPlayCount = 0
    private(set) var effectPlayCounts: [String: Int] = [:]
    private(set) var lastEffect = ""
    private(set) var backgroundPauseCount = 0
    private(set) var assetLoadFailures = 0
    #endif
    private(set) var interrupted = false
    private(set) var routePaused = false

    @ObservationIgnored private var music: AVAudioPlayer?
    @ObservationIgnored private var loadedTrack: GameMusicTrack?
    @ObservationIgnored private var fadingMusic: AVAudioPlayer?
    @ObservationIgnored private var fadeTask: Task<Void, Never>?
    @ObservationIgnored private var effects: [GameSoundEffect: [AVAudioPlayer]] = [:]
    @ObservationIgnored private var lastPlayed: [GameSoundEffect: TimeInterval] = [:]
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var currentHour = 12
    @ObservationIgnored private var previewPaused = false
    @ObservationIgnored private var ducked = false
    @ObservationIgnored private var duckTask: Task<Void, Never>?
    @ObservationIgnored private var lastCatPlayed: TimeInterval = -100
    @ObservationIgnored private var lastHapticAt: TimeInterval = -100
    @ObservationIgnored private var sessionActive = false
    @ObservationIgnored private var activationInFlight = false
    @ObservationIgnored private var recoveringInterruption = false
    @ObservationIgnored private var sessionGeneration: UInt = 0
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "com.stationcat.catlife.audio-session")
    @ObservationIgnored private var pendingEffects: [PendingEffect] = []

    private struct PendingEffect {
        let effect: GameSoundEffect
        let requestedAt: TimeInterval
    }

    override init() {
        super.init()
        #if os(iOS)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(receivedInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(receivedRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(receivedMediaReset(_:)),
                           name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        center.addObserver(self, selector: #selector(receivedSecondaryHint(_:)),
                           name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
        #endif
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func configure(settings: AudioSettings, track: GameMusicTrack, foreground: Bool, ready: Bool, now: Date = Date()) {
        #if DEBUG
        if isForeground && !foreground { backgroundPauseCount += 1 }
        #endif
        let becameActive = !isForeground && foreground
        self.settings = settings
        currentHour = Calendar.current.component(.hour, from: now)
        currentTrack = GameAudioPolicy.track(track, settings: settings, hour: currentHour)
        isForeground = foreground
        self.ready = ready
        if becameActive { routePaused = false }
        for (effect, players) in effects {
            let volume = GameAudioPolicy.effectVolume(effect, settings: settings)
            for player in players {
                player.volume = volume
                if volume == 0 { player.stop(); player.currentTime = 0 }
            }
        }
        pendingEffects.removeAll { GameAudioPolicy.effectVolume($0.effect, settings: settings) == 0 }
        if !foreground || !ready {
            pauseAll()
            deactivateSession()
            return
        }
        if becameActive { recoverInterruptedSession() }
        reconcileMusic()
    }

    /// Resume on a new explicit action without emitting its effect before the
    /// saved action or scene animation reaches the appropriate sound cue.
    func noteUserInteraction() {
        guard ready, isForeground, routePaused || interrupted else { return }
        routePaused = false
        recoverInterruptedSession()
        reconcileMusic()
    }

    func play(_ effect: GameSoundEffect, userInitiated: Bool = false) {
        guard ready, isForeground else { return }
        if userInitiated { noteUserInteraction() }
        guard !routePaused, !interrupted || recoveringInterruption else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // A saved reward can also level up; adjacent cues share one physical feedback.
        #if os(iOS)
        if settings.haptics, effect.successHaptic || effect.lightHaptic, now - lastHapticAt >= 0.12 {
            if effect.successHaptic { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            else if effect.lightHaptic { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            lastHapticAt = now
            #if DEBUG
            hapticPlayCount += 1
            #endif
        }
        #endif
        guard GameAudioPolicy.effectVolume(effect, settings: settings) > 0 else { return }
        if effect.isCatVoice {
            let pendingCat = pendingEffects.last(where: { $0.effect.isCatVoice })?.requestedAt ?? -100
            guard now - max(lastCatPlayed, pendingCat) >= 4 else { return }
        }
        pendingEffects.removeAll { now - $0.requestedAt > 0.5 }
        let lastRequested = pendingEffects.last(where: { $0.effect == effect })?.requestedAt ?? -100
        guard now - max(lastPlayed[effect] ?? -100, lastRequested) >= minimumGap(for: effect) else { return }
        if !sessionActive {
            // Keep the first fresh cue while activation yields the main actor.
            // Never replay a backlog after a slow activation or a lifecycle change.
            if pendingEffects.count >= GameAudioPolicy.simultaneousEffects {
                guard let index = GameAudioPolicy.replacementIndex(for: effect, active: pendingEffects.map(\.effect)) else { return }
                pendingEffects.remove(at: index)
            }
            pendingEffects.append(PendingEffect(effect: effect, requestedAt: now))
            requestSessionActivation(recoveringInterruption: recoveringInterruption)
            return
        }
        playPreparedEffect(effect)
    }

    private func minimumGap(for effect: GameSoundEffect) -> TimeInterval {
        effect.isCatVoice ? 4 : 0.12
    }

    private func playPreparedEffect(_ effect: GameSoundEffect) {
        guard ready, isForeground, sessionActive, !interrupted, !routePaused,
              GameAudioPolicy.effectVolume(effect, settings: settings) > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - (lastPlayed[effect] ?? -100) >= minimumGap(for: effect),
              !effect.isCatVoice || now - lastCatPlayed >= 4 else { return }
        if effects[effect] == nil { effects[effect] = (0..<2).compactMap { _ in makePlayer(effect.fileName) } }
        let active = effects.flatMap { effect, players in
            players.filter(\.isPlaying).map { (effect: effect, player: $0) }
        }
        if active.count >= GameAudioPolicy.simultaneousEffects {
            guard let index = GameAudioPolicy.replacementIndex(for: effect, active: active.map(\.effect)) else { return }
            active[index].player.stop()
        }
        guard let player = effects[effect]?.first(where: { !$0.isPlaying }) else { return }
        player.currentTime = 0
        player.volume = GameAudioPolicy.effectVolume(effect, settings: settings)
        if player.play() {
            lastPlayed[effect] = now
            if effect.isCatVoice { lastCatPlayed = now }
            if effect.ducksMusic { duckMusic() }
        #if DEBUG
            effectPlayCount += 1
            effectPlayCounts[effect.rawValue, default: 0] += 1
            lastEffect = effect.rawValue
        #endif
        }
    }

    func toggleMusicPreview() {
        guard ready, isForeground, settings.musicEnabled, settings.musicVolume > 0 else { return }
        let shouldPause = musicPlaying
        noteUserInteraction()
        previewPaused = shouldPause
        reconcileMusic()
    }

    func endMusicPreview() {
        previewPaused = false
        reconcileMusic()
    }

    private var musicVolume: Float {
        GameAudioPolicy.musicVolume(settings: settings, hour: currentHour, ducked: ducked)
    }

    private func duckMusic() {
        duckTask?.cancel()
        ducked = true
        music?.setVolume(musicVolume, fadeDuration: 0.08)
        duckTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1_200)) } catch { return }
            guard let self else { return }
            self.ducked = false
            self.music?.setVolume(self.musicVolume, fadeDuration: 0.25)
        }
    }

    private func reconcileMusic() {
        guard ready, isForeground, !interrupted, !routePaused else { pauseAll(); return }
        guard hasAudibleOutput else {
            pauseAll()
            deactivateSession()
            return
        }
        // Prepare once on welcome/foreground entry even when only effects are
        // enabled, so the first interaction normally already has an active session.
        guard sessionActive else {
            pauseMusic()
            requestSessionActivation()
            return
        }
        guard settings.musicEnabled, settings.musicVolume > 0, !previewPaused else {
            pauseMusic()
            return
        }
        // Ambient mixes with other audio; avoid layering our BGM over a podcast/music app.
        #if os(iOS)
        guard !AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint else { pauseMusic(); return }
        #endif
        if loadedTrack != currentTrack || music == nil {
            guard let next = makePlayer(currentTrack.fileName) else { pauseMusic(); return }
            next.numberOfLoops = -1
            next.volume = 0
            guard next.play() else { musicPlaying = false; return }
            fadeTask?.cancel()
            fadingMusic?.stop()
            fadingMusic = music
            fadingMusic?.setVolume(0, fadeDuration: 1.2)
            music = next
            loadedTrack = currentTrack
            next.setVolume(musicVolume, fadeDuration: 1.2)
            fadeTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(1_250)) } catch { return }
                self?.fadingMusic?.stop()
                self?.fadingMusic = nil
            }
        } else if let music {
            if !music.isPlaying {
                music.volume = 0
                _ = music.play()
            }
            music.setVolume(musicVolume, fadeDuration: 0.25)
        }
        musicPlaying = music?.isPlaying == true
    }

    private func makePlayer(_ name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf", subdirectory: "Audio") else {
        #if DEBUG
            assetLoadFailures += 1
        #endif
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            return player
        } catch {
        #if DEBUG
            assetLoadFailures += 1
        #endif
            return nil
        }
    }

    private var hasAudibleOutput: Bool {
        (settings.musicEnabled && settings.musicVolume > 0)
            || (settings.effectsEnabled && settings.effectsVolume > 0)
            || (settings.catEnabled && settings.catVolume > 0)
    }

    private func requestSessionActivation(recoveringInterruption: Bool = false) {
        guard ready, isForeground, !routePaused, hasAudibleOutput,
              !interrupted || recoveringInterruption,
              !sessionActive, !activationInFlight else { return }
        activationInFlight = true
        self.recoveringInterruption = interrupted && recoveringInterruption
        let generation = sessionGeneration
        // Synchronous AVAudioSession calls may wait for system audio services.
        // A serial worker keeps those waits off MainActor on every supported iOS.
        #if os(macOS)
        completeSessionActivation(succeeded: true, generation: generation)
        #else
        sessionQueue.async { [weak self] in
            let succeeded: Bool
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, mode: .default)
                try session.setActive(true)
                succeeded = true
            } catch {
                succeeded = false
            }
            Task { @MainActor [weak self] in
                self?.completeSessionActivation(succeeded: succeeded, generation: generation)
            }
        }
        #endif
    }

    private func completeSessionActivation(succeeded: Bool, generation: UInt) {
        // Invalidation queues deactivation behind any in-flight activation;
        // a stale completion must never publish active state or restart players.
        guard generation == sessionGeneration else { return }
        activationInFlight = false
        let wasRecovering = recoveringInterruption
        recoveringInterruption = false
        guard succeeded else {
            sessionActive = false
            pendingEffects.removeAll()
            musicPlaying = false
            return // Retry only on a later foreground/configuration/user event.
        }
        sessionActive = true
        if wasRecovering { interrupted = false }
        guard ready, isForeground, !interrupted, !routePaused, hasAudibleOutput else {
            pauseAll()
            deactivateSession()
            return
        }
        reconcileMusic()
        let queued = pendingEffects
        pendingEffects.removeAll()
        for request in queued where ProcessInfo.processInfo.systemUptime - request.requestedAt <= 0.5 {
            playPreparedEffect(request.effect)
        }
    }

    private func recoverInterruptedSession() {
        // iOS does not guarantee an ended notification for every interruption.
        // A foreground return or explicit action may try again; an ongoing
        // higher-priority session can reject activation and must stay paused.
        guard interrupted else { return }
        requestSessionActivation(recoveringInterruption: true)
    }

    private func deactivateSession() {
        let needsDeactivation = sessionActive || activationInFlight
        sessionGeneration &+= 1
        sessionActive = false
        activationInFlight = false
        recoveringInterruption = false
        pendingEffects.removeAll()
        guard needsDeactivation else { return }
        #if os(iOS)
        sessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    private func pauseMusic() {
        duckTask?.cancel()
        ducked = false
        fadeTask?.cancel()
        fadingMusic?.stop()
        fadingMusic = nil
        music?.pause()
        musicPlaying = false
    }

    private func stopEffects() {
        for player in effects.values.flatMap({ $0 }) { player.stop(); player.currentTime = 0 }
    }

    private func pauseAll() { pauseMusic(); stopEffects() }

    #if os(iOS)
    @objc nonisolated private func receivedInterruption(_ notification: Notification) {
        let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
        let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
        Task { @MainActor [weak self] in
            guard let self, let type else { return }
            if type == AVAudioSession.InterruptionType.began.rawValue {
                self.interrupted = true
                self.pauseAll()
                self.deactivateSession()
            } else if type == AVAudioSession.InterruptionType.ended.rawValue {
                self.interrupted = false
                if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.reconcileMusic()
                } else {
                    self.routePaused = true // Wait for an explicit user action.
                    self.pauseAll()
                    self.deactivateSession()
                }
            }
        }
    }

    @objc nonisolated private func receivedRouteChange(_ notification: Notification) {
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
        Task { @MainActor [weak self] in
            guard let self, reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            self.routePaused = true
            self.pauseAll()
            self.deactivateSession()
        }
    }

    @objc nonisolated private func receivedMediaReset(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pauseAll()
            self.deactivateSession()
            self.music = nil
            self.loadedTrack = nil
            self.effects = [:]
            self.interrupted = false
            self.reconcileMusic()
        }
    }

    @objc nonisolated private func receivedSecondaryHint(_ notification: Notification) {
        Task { @MainActor [weak self] in
            // Notifications aren't delivered while we're inactive. Always
            // query the live hint in reconcileMusic rather than caching begin.
            self?.reconcileMusic()
        }
    }
    #endif
}
