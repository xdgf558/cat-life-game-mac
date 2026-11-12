import Foundation
import Observation
import CatGameCore

enum HomeSheet: String, Identifiable {
    case work, shop, inventory, town, player, upgrade, tasks, hospital
    var id: String { rawValue }
}

enum InventoryCategory: String {
    case supplies, furniture
}

struct RoomFeedback: Equatable {
    let id = UUID()
    let kind: ActionKind
    let catID: String
}

@MainActor
@Observable
final class GameStore {
    private(set) var snapshot: GameSnapshot? { didSet { syncAudio() } }
    private(set) var isLoading = true
    // Completed startup work, not an elapsed-time animation or save field.
    private(set) var startupProgress: Double = 0
    private(set) var startupPhase = "welcome.loadingSave"
    private(set) var isBusy = false
    private(set) var saveTransferInProgress = false
    private(set) var saveSceneGeneration = UUID()
    private(set) var visibleHomeFloor: HomeFloor = .ground {
        didSet { if oldValue != visibleHomeFloor { syncAudio() } }
    }
    private(set) var isChangingHomeFloor = false
    var roomFloorTravelReady = true
    var homeUpgradeCelebration: HomeUpgradeCelebration?
    private(set) var loadFailed = false
    private(set) var needsNewerVersion = false
    // Welcome presentation belongs to this process, not the durable game save.
    private(set) var hasEnteredHome = false
    #if os(macOS)
    private(set) var macPreviousSaveAt: Date?
    private(set) var macRoomRepairFailed = false
    @ObservationIgnored private var macPendingCreatedSnapshots: [GameSnapshot] = []
    #endif
    var startupNotice: String? { notices.startupNotice }
    var showSaveError = false
    var activeSheet: HomeSheet? {
        didSet {
            syncAudio()
            if oldValue != activeSheet {
                catCollectionFilter = nil
                adoptionCatID = nil
                isShowingNeighbors = false
                isShowingMarket = false
                isShowingTownBoard = false
                isPresentingExchange = false
                supplyPicker = nil
                furniturePurchaseNotice = nil
                furniturePurchaseItemID = nil
                playNavigationSound()
            }
        }
    }
    var isShowingSettings = false {
        didSet {
            if oldValue != isShowingSettings {
                supplyPicker = nil
                furniturePurchaseNotice = nil
                furniturePurchaseItemID = nil
                playNavigationSound()
            }
        }
    }
    var inventoryCategory: InventoryCategory = .supplies
    var selectedInventorySupply: SupplyKind = .food
    var supplyPicker: SupplyKind?
    let companionMemories = CompanionMemoryNotices68()
    var inspectedMemoryCatID: String?
    var habitGuideCatID: String?
    var isPresentingHabitGuide = false
    var isPresentingHabitMemory = false
    var showsPlayChoices = false
    var isShowingPlayTogether = false
    var playTogetherSessionID: String?
    var habitStudyMode = false {
        didSet { sharedHomeNoticeDefaults.set(habitStudyMode, forKey: "catlife.habits.studyMode.v1") }
    }
    var habitStudyError = false
    @ObservationIgnored let habitStudyLog: HabitStudyLog
    @ObservationIgnored var pendingCatPlayEnd: PendingCatPlayEnd?
    @ObservationIgnored var recordedFirstHabitAction = false
    var furniturePurchaseNotice: String?
    private(set) var furniturePurchaseItemID: String?
    var selectedStoredFurnitureID: String?
    var isFurnitureTrayExpanded = true
    let arrangement68 = ArrangementEditor68()
    var shopCategory: ShopCategory = .supplies
    var inspectedCatID: String?
    var inspectedCatShowsGrowth = false
    var visibleRoomCatIDs: Set<String>?
    var sharedRoomHasLimitedSpace: Bool {
        guard let snapshot, snapshot.home.roomLevel >= RoomResidentCats.unlockLevel, let visibleRoomCatIDs else { return false }
        return snapshot.cats.contains { !visibleRoomCatIDs.contains($0.id) }
    }
    var catCollectionFilter: CatCollectionView.Filter? {
        didSet { if oldValue != catCollectionFilter { syncAudio() } }
    }
    var adoptionCatID: String?
    var isPresentingAdoptionConfirmation = false
    var isShowingNeighbors = false { didSet { if oldValue != isShowingNeighbors { syncAudio() } } }
    var isShowingMarket = false { didSet { if oldValue != isShowingMarket { syncAudio() } } }
    var isShowingTownBoard = false { didSet { if oldValue != isShowingTownBoard { syncAudio() } } }
    var isPresentingExchange = false
    var isPresentingCommunityGift = false
    var isShowingCommunityGiftShop = false
    let adoptionReminders: GameAdoptionReminderCenter
    let onboarding: GameOnboardingCenter
    var hospitalCatID: String?
    var isInspectingHealth = false { didSet { syncAudio() } }
    private(set) var now = Date()
    var toast: String? { notices.toast }
    private(set) var feedback: RoomFeedback?
    private(set) var isDecorating = false {
        didSet { if oldValue != isDecorating { playNavigationSound() } }
    }
    private(set) var isSavingLayout = false
    var isResolvingLayout = false
    var draftBowlPosition: NormalizedPoint?
    var draftFurniture: [FurniturePlacement]?
    var draftFurnitureOrientations: [String: FurnitureOrientation]?
    var selectedFurnitureID: String?
    var placingFurnitureID: String?
    private(set) var restingFurnitureID: String?
    private(set) var pendingWorkResultID: String?

    @ObservationIgnored private let repository: any GameSaveRepository
    @ObservationIgnored let sharedHomeNoticeDefaults: UserDefaults
    @ObservationIgnored private let audio = GameAudioController()
    @ObservationIgnored private var timerTask: Task<Void, Never>?
    @ObservationIgnored private let notices = GameNoticeCenter()
    @ObservationIgnored private var lastSyncCheck = Date.distantPast
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var foregroundEpoch = 0
    @ObservationIgnored private var pendingSynchronization = false
    // Keep recovery quiet across failed writes and every queued save path.
    @ObservationIgnored private var silentProgressThrough: Date?
    @ObservationIgnored private var loadingInProgress = false
    @ObservationIgnored private var presentedRestSessionID: String?
    @ObservationIgnored private var restTransitions: [RestTransition] = []
    @ObservationIgnored private var restRetryTask: Task<Void, Never>?
    private(set) var saveRetry = SaveRetryState()
    var hasSaveFailure: Bool { saveRetry.failures > 0 }
    var saveRetryIsSlow: Bool { saveRetry.failures >= SaveRetryState.maximumAutomaticAttempts }
    private(set) var pendingAudioSettings: AudioSettings?
    private(set) var audioSettingsSaveFailed = false
    @ObservationIgnored private var audioSaveRequest: AudioSaveRequest?
    @ObservationIgnored private var pendingManualRetry = false

    private struct AudioSaveRequest {
        let id = UUID()
        let settings: AudioSettings
        var attempted = false
        var completion: CheckedContinuation<Bool, Never>?
    }
    #if DEBUG
    @ObservationIgnored private var fixtures = GameStoreFixtures()
    #if os(macOS)
    @ObservationIgnored private var uiTestResetDirectory: URL?
    #endif
    #endif

    private struct RestTransition {
        let id = UUID()
        let catID: String
        let furnitureID: String?
        let sessionID: String
        let occurredAt: Date
        var observation: CatRestObservation? = nil
    }

    private struct SaveContext {
        let original: GameSnapshot
        var candidate: GameSnapshot
        let transitions: [RestTransition]
        let foregroundEpoch: Int
        let playEnd: PendingCatPlayEnd?
    }

    init(directory: URL? = nil) {
        let saveDirectory = directory ?? NativeSaveLocation.currentDirectory
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing")
        let reminderDefaults = testing ? UserDefaults(suiteName: "com.stationcat.catlife.ui-testing")! : .standard
        if testing && arguments.contains("--reset-ui-test-save") && directory == nil {
            reminderDefaults.removeObject(forKey: GameAdoptionReminderCenter.presentedIDsKey)
            reminderDefaults.removeObject(forKey: GameOnboardingCenter.progressKey)
            reminderDefaults.removeObject(forKey: Self.sharedHomeSpaceNoticesKey)
            reminderDefaults.removeObject(forKey: "catlife.home.upperHintSeen.v1")
            reminderDefaults.removeObject(forKey: "catlife.habits.studyMode.v1")
        }
        fixtures = GameStoreFixtures(arguments: arguments, allowsSeeding: directory == nil)
        if testing && arguments.contains("--reset-ui-test-save") && directory == nil {
            #if os(macOS)
            // The delegate acquires the process lock before load clears fixture files.
            uiTestResetDirectory = saveDirectory
            #else
            try? FileManager.default.removeItem(at: saveDirectory)
            do { try fixtures.seedLoadFailureFiles(in: saveDirectory) }
            catch { assertionFailure("Could not prepare isolated load-failure fixture: \(error)") }
            #endif
        }
        #else
        let reminderDefaults = UserDefaults.standard
        #endif
        repository = FileSaveRepository(directory: saveDirectory)
        #if os(macOS)
        habitStudyLog = HabitStudyLog(directory: saveDirectory)
        #else
        habitStudyLog = HabitStudyLog(directory: directory)
        #endif
        sharedHomeNoticeDefaults = reminderDefaults
        adoptionReminders = GameAdoptionReminderCenter(defaults: reminderDefaults)
        onboarding = GameOnboardingCenter(defaults: reminderDefaults)
        habitStudyMode = reminderDefaults.bool(forKey: "catlife.habits.studyMode.v1")
    }

    init(repository: any GameSaveRepository, reminderDefaults: UserDefaults? = nil, studyLog: HabitStudyLog = HabitStudyLog()) {
        self.repository = repository
        habitStudyLog = studyLog
        let defaults = reminderDefaults ?? UserDefaults(suiteName: "com.stationcat.catlife.tests.\(UUID().uuidString)")!
        sharedHomeNoticeDefaults = defaults
        adoptionReminders = GameAdoptionReminderCenter(defaults: defaults)
        onboarding = GameOnboardingCenter(defaults: defaults)
        habitStudyMode = defaults.bool(forKey: "catlife.habits.studyMode.v1")
    }

    /// Read the same repository the store will load; no path assumptions in platform UI.
    var saveDirectory: URL? { (repository as? FileSaveRepository)?.directory }
    var hasSavedProgress: Bool {
        #if DEBUG && os(macOS)
        if uiTestResetDirectory != nil { return false }
        #endif
        guard let files = repository as? FileSaveRepository else { return false }
        return FileManager.default.fileExists(atPath: files.saveURL.path)
            || FileManager.default.fileExists(atPath: files.backupURL.path)
    }

    var cat: CatState? { snapshot?.activeCat }
    var audioSettings: AudioSettings { snapshot?.settings.audio ?? AudioSettings() }

    private func syncAudio() {
        let track: GameMusicTrack
        if !hasEnteredHome { track = .cover }
        else if activeSheet == .hospital || isInspectingHealth { track = .hospital }
        else if activeSheet == .shop { track = .shop }
        else if activeSheet == .town {
            track = isShowingNeighbors || isShowingMarket || isShowingTownBoard || catCollectionFilter != nil ? .town : .promenade
        }
        else if snapshot?.player.activeSleep != nil { track = .sleep }
        else if activeSheet == .work { track = .work }
        else if cat?.activeRest != nil { track = .sleep }
        else { track = visibleHomeFloor == .upper ? .upstairs : .home }
        audio.configure(settings: audioSettings, track: track, foreground: foreground,
                        ready: snapshot != nil && !isLoading && !loadFailed)
    }

    func playNavigationSound() { audio.play(.tap, userInitiated: true) }
    var currentMusicTrack: GameMusicTrack { audio.currentTrack }
    var isMusicPlaying: Bool { audio.musicPlaying }
    func previewMusic() { audio.toggleMusicPreview() }
    func endMusicPreview() { audio.endMusicPreview() }
    func previewCatVoice() { audio.play(.catCoax, userInitiated: true) }
    func previewSoundEffect() { audio.play(.coins, userInitiated: true) }
    func playFeedback(_ sound: GameSoundEffect) { audio.play(sound, userInitiated: true) }
    func playSceneSound(_ sound: GameSoundEffect) {
        audio.play(sound)
        if sound == .feed { audio.play(.catHappy) }
        if sound == .play { audio.play(.catCoax) }
    }

    #if DEBUG
    /// Read-only diagnostics are exposed only by the isolated audio UI test.
    var audioDiagnostics: String {
        let value: [String: Any] = [
            "musicEnabled": audioSettings.musicEnabled, "effectsEnabled": audioSettings.effectsEnabled,
            "musicVolume": audioSettings.musicVolume, "effectsVolume": audioSettings.effectsVolume,
            "catEnabled": audioSettings.catEnabled, "catVolume": audioSettings.catVolume,
            "sceneMusic": audioSettings.sceneMusic, "nightQuiet": audioSettings.nightQuiet,
            "haptics": audioSettings.haptics,
            "isForeground": audio.isForeground, "musicPlaying": audio.musicPlaying,
            "currentTrack": audio.currentTrack.rawValue, "effectPlayCount": audio.effectPlayCount,
            "effectPlayCounts": audio.effectPlayCounts,
            "lastEffect": audio.lastEffect, "backgroundPauseCount": audio.backgroundPauseCount,
            "assetLoadFailures": audio.assetLoadFailures
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    #endif

    @discardableResult
    func updateAudioSettings(_ settings: AudioSettings) async -> Bool {
        guard snapshot != nil, !isDecorating, !saveTransferInProgress else { return false }
        guard audioSaveRequest != nil || audioSettings != settings else { return true }
        return await withCheckedContinuation { completion in
            // Resolve superseded callers without letting an older in-flight
            // commit clear the player's newest intent, even when it is a revert.
            audioSaveRequest?.completion?.resume(returning: false)
            audioSaveRequest = AudioSaveRequest(settings: settings, completion: completion)
            pendingAudioSettings = settings
            audioSettingsSaveFailed = false
            drainPendingSynchronization()
        }
    }

    @discardableResult
    private func processPendingAudioSettings(userInitiated: Bool = false) -> Bool {
        guard !isBusy, let request = audioSaveRequest,
              !request.attempted || userInitiated || saveRetry.permitsAutomaticAttempt(at: Date()),
              var context = saveContext() else { return false }
        let explicitAttempt = userInitiated || !request.attempted
        audioSaveRequest?.attempted = true
        _ = GameEngine.synchronize(&context.candidate, now: Date())
        context.candidate.settings.audio = request.settings
        isBusy = true
        Task {
            do {
                try await commit(context)
                if audioSaveRequest?.id == request.id {
                    audioSaveRequest?.completion?.resume(returning: true)
                    audioSaveRequest = nil
                    pendingAudioSettings = nil
                    audioSettingsSaveFailed = false
                    audio.play(.toggle, userInitiated: true)
                }
            } catch {
                if audioSaveRequest?.id == request.id {
                    audioSaveRequest?.completion?.resume(returning: false)
                    audioSaveRequest?.completion = nil
                    audioSettingsSaveFailed = true
                }
                // A superseded request still records storage health, but only
                // the latest intent may interrupt the player with an alert.
                recordSaveFailure(showAlert: audioSaveRequest?.id == request.id,
                                  userInitiated: explicitAttempt)
            }
            isBusy = false
            drainPendingSynchronization()
        }
        return true
    }
    var foodRequired: Int { cat?.isPregnant == true ? 2 : 1 }
    var totalFood: Int { (snapshot?.inventory.food ?? 0) + (snapshot?.inventory.premiumFood ?? 0) }
    var hasFood: Bool { (snapshot?.inventory.food ?? 0) >= foodRequired || (snapshot?.inventory.premiumFood ?? 0) >= foodRequired }

    var sceneSnapshot: GameSnapshot? {
        guard var value = snapshot else { return nil }
        // The scene is a projection of one floor; the durable save keeps both.
        value.home.bowlPosition = value.home.bowlPosition(on: visibleHomeFloor) ?? value.home.bowlPosition
        value.home.furniture = value.home.placements(on: visibleHomeFloor)
        if let draftBowlPosition { value.home.bowlPosition = draftBowlPosition }
        if let draftFurniture {
            for index in value.inventory.furniture.indices {
                let item = value.inventory.furniture[index]
                let previous = snapshot?.home.furniture.first { $0.itemID == item.id }
                let current = draftFurniture.first { $0.itemID == item.id }
                // The scene omits the other floor; omission is not a move.
                if previous?.floor == visibleHomeFloor || current != nil {
                    value.inventory.furniture[index] = item.applyingPlacement(from: previous, to: current)
                }
            }
            value.home.furniture = draftFurniture
        }
        if let draftFurnitureOrientations {
            for index in value.inventory.furniture.indices {
                if let orientation = draftFurnitureOrientations[value.inventory.furniture[index].id] {
                    value.inventory.furniture[index].orientation = orientation
                }
            }
        }
        return value
    }

    var storedFurniture: [FurnitureItem] {
        guard let value = sceneSnapshot else { return [] }
        let otherFloor = snapshot?.home.furniture.filter { $0.floor != visibleHomeFloor } ?? []
        let placed = Set((value.home.furniture + otherFloor).map(\.itemID))
        return value.inventory.furniture.filter { !placed.contains($0.id) }
    }

    var placedFurnitureCount: Int { sceneSnapshot?.home.furniture.count ?? 0 }

    var furnitureCapacity: Int { furnitureCapacity(on: visibleHomeFloor) }
    var canPlaceMoreFurniture: Bool { availableFurnitureSlots(on: visibleHomeFloor) > 0 }
    var canUpgradeHome: Bool { HomeCatalog.nextLevel(after: snapshot?.home.roomLevel ?? 1) != nil }

    var selectedFurniture: FurnitureItem? {
        guard let id = selectedFurnitureID,
              placingFurnitureID == id || sceneSnapshot?.home.furniture.contains(where: { $0.itemID == id }) == true else { return nil }
        return sceneSnapshot?.inventory.furniture.first { $0.id == id }
    }

    var selectedFurnitureName: String {
        selectedFurniture.map(GameStrings.furnitureName) ?? GameStrings.text("layout.bowl")
    }

    var canStoreSelectedFurniture: Bool {
        isDecorating && selectedFurniture != nil && placingFurnitureID == nil
            && !isBusy && !isSavingLayout && !isResolvingLayout
    }

    var canFlipSelectedFurniture: Bool {
        canStoreSelectedFurniture && selectedFurniture?.kind.supportsRotation == true
    }

    var hasUnsavedLayoutChanges: Bool {
        guard isDecorating, let snapshot else { return false }
        return draftBowlPosition != snapshot.home.bowlPosition(on: visibleHomeFloor)
            || draftFurniture != snapshot.home.placements(on: visibleHomeFloor)
            || (draftFurnitureOrientations ?? [:]).contains { id, direction in
                let original = snapshot.inventory.furniture.first { $0.id == id }
                return original?.orientation != direction || original?.usesLegacyFootprint == true
            }
    }

    func openCatCollection(filter: CatCollectionView.Filter = .all, adoptionID: String? = nil) {
        guard !isDecorating else { return }
        isShowingSettings = false
        inspectedCatID = nil
        activeSheet = .town
        isShowingNeighbors = false
        isShowingMarket = false
        isShowingTownBoard = false
        catCollectionFilter = filter
        adoptionCatID = adoptionID
    }

    var catStatus: String {
        guard let cat else { return "" }
        if let illness = cat.healthState?.illness {
            return GameStrings.text(CatHealthCatalog.definition(for: illness).nameKey)
        }
        if restingFurnitureID != nil {
            return GameStrings.format("rest.recovering", cat.energy)
        }
        if cat.satiety < 50 { return GameStrings.text("cat.hungry") }
        if cat.cleanliness < 40 { return GameStrings.text("cat.cleanNeeded") }
        if cat.mood < 40 { return GameStrings.text("cat.playNeeded") }
        if cat.satiety >= 95 { return GameStrings.text("cat.full") }
        return GameStrings.text("cat.content")
    }

    // Capture the physical arrival/exit time immediately. Save operations are
    // serialized; waiting for an unrelated write must not extend a short rest.
    func setRestingFurniture(id: String?, sessionID: String, catID: String? = nil,
                             observation: CatRestObservation? = nil, occurredAt: Date = Date()) {
        guard let catID = catID ?? cat?.id,
              snapshot?.cats.contains(where: { $0.id == catID }) == true else { return }
        if let id {
            guard catID == cat?.id else { return }
            guard presentedRestSessionID != sessionID else { return }
            restingFurnitureID = id
            presentedRestSessionID = sessionID
        } else if presentedRestSessionID == sessionID {
            restingFurnitureID = nil
            presentedRestSessionID = nil
        }
        restTransitions.append(RestTransition(catID: catID, furnitureID: id,
            sessionID: sessionID, occurredAt: occurredAt,
            observation: foreground && activeSheet == nil && !isShowingSettings
                && inspectedCatID == nil && !isShowingPlayTogether && !showsPlayChoices
                && !showSaveError && homeUpgradeCelebration == nil ? observation : nil))
        processNextRestTransition()
    }

    private func processNextRestTransition() {
        guard !isBusy, !restTransitions.isEmpty,
              saveRetry.permitsAutomaticAttempt(at: Date()), let context = saveContext() else { return }
        if context.candidate == context.original {
            acknowledgeTransitions(context.transitions)
            if pendingCatPlayEnd?.id == context.playEnd?.id { pendingCatPlayEnd = nil }
            drainPendingSynchronization()
            return
        }
        isBusy = true
        Task {
            do {
                try await commit(context)
            } catch {
                recordSaveFailure()
            }
            isBusy = false
            drainPendingSynchronization()
        }
    }

    /// Replay physical rest events before the wall clock or a player action.
    /// Failed exits retain their captured time without blocking navigation.
    private func saveContext() -> SaveContext? {
        guard let original = snapshot else { return nil }
        var candidate = original
        let transitions = restTransitions
        for transition in transitions {
            if let furnitureID = transition.furnitureID {
                _ = GameEngine.startCatRest(&candidate, catID: transition.catID,
                    furnitureID: furnitureID, sessionID: transition.sessionID,
                    observation: transition.observation, now: transition.occurredAt)
            } else {
                _ = GameEngine.endCatRest(&candidate, catID: transition.catID,
                    sessionID: transition.sessionID, now: transition.occurredAt)
            }
        }
        let playEnd = pendingCatPlayEnd
        if let playEnd {
            _ = CatHabitEngine.endPlay(&candidate, catID: playEnd.catID, sessionID: playEnd.sessionID, now: playEnd.occurredAt)
        }
        return SaveContext(original: original, candidate: candidate, transitions: transitions,
                           foregroundEpoch: foregroundEpoch, playEnd: playEnd)
    }

    private func acknowledgeTransitions(_ transitions: [RestTransition]) {
        let ids = Set(transitions.map(\.id))
        restTransitions.removeAll { ids.contains($0.id) }
    }

    private func commit(_ context: SaveContext) async throws {
        #if DEBUG
        try fixtures.checkSave(context.candidate, original: context.original,
                               exitsRest: context.transitions.contains { $0.furnitureID == nil })
        #endif
        try await repository.save(context.candidate)
        if context.candidate.activeCatID != context.original.activeCatID {
            restingFurnitureID = nil
            presentedRestSessionID = nil
            feedback = nil
        }
        snapshot = context.candidate
        recordHabitCommit(from: context.original, to: context.candidate)
        if let end = context.playEnd, pendingCatPlayEnd?.id == end.id { pendingCatPlayEnd = nil }
        acknowledgeTransitions(context.transitions)
        clearSaveFailure()
        let canPlayProgress = silentProgressThrough == nil && foreground && hasEnteredHome && !isLoading
            && context.foregroundEpoch == foregroundEpoch
        refreshAdoptionReminders()
        if canPlayProgress {
            companionMemories.record(from: context.original, to: context.candidate, generation: saveSceneGeneration)
        }
        if canPlayProgress, let sound = GameProgressFeedback.sound(from: context.original, to: context.candidate) {
            audio.play(sound)
        }
        if let receipt = context.candidate.player.lastWorkResult,
           receipt.id != context.original.player.lastWorkResult?.id {
            pendingWorkResultID = receipt.id
            if canPlayProgress { audio.play(.workComplete) }
            showNotice(GameStrings.format("action.workFinished", receipt.goldReward))
        }
        finishSilentCatchUp(context)
    }

    private func finishSilentCatchUp(_ context: SaveContext) {
        guard let through = silentProgressThrough,
              context.foregroundEpoch == foregroundEpoch,
              context.candidate.meta.lastSyncAt >= through else { return }
        silentProgressThrough = nil
    }

    private func refreshAdoptionReminders() {
        guard foreground, hasEnteredHome, !isLoading, let snapshot else { return }
        // Eligibility uses durable state, independently of silent catch-up audio.
        adoptionReminders.consider(snapshot)
    }

    private func clearSaveFailure() {
        saveRetry.succeeded()
        showSaveError = false
        restRetryTask?.cancel()
        restRetryTask = nil
    }

    private func recordSaveFailure(showAlert: Bool = true, userInitiated: Bool = false) {
        let firstFailure = saveRetry.failed(at: Date())
        if showAlert && (firstFailure || userInitiated) { showSaveError = true }
        restRetryTask?.cancel()
        restRetryTask = nil
        let delay = max(0, saveRetry.nextAttempt.timeIntervalSinceNow)
        restRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.restRetryTask = nil
            self.synchronize()
        }
    }

    func retrySaving() {
        // Explicit retry does not wait for the automatic backoff.
        synchronize(userInitiated: true)
    }

    func exportSaveArchive() async throws -> Data {
        guard !isBusy, !isDecorating, var context = saveContext() else { throw SaveTransferError.busy }
        isBusy = true
        saveTransferInProgress = true
        defer { saveTransferInProgress = false; isBusy = false; drainPendingSynchronization() }
        let exportedAt = Date()
        _ = GameEngine.synchronize(&context.candidate, now: exportedAt)
        do {
            if context.candidate != context.original { try await commit(context) }
        } catch {
            // The validated in-memory timeline can still be rescued to another
            // file provider. Keep the autosave failure and its retry state visible.
            recordSaveFailure(showAlert: false, userInitiated: true)
        }
        let saved = context.candidate
        return try await Task.detached(priority: .userInitiated) {
            try NativeSaveTransfer.encode(snapshot: saved, exportedAt: exportedAt)
        }.value
    }

    func preservedNewerSaves() async throws -> [PreservedNewerSave] {
        guard let repository = repository as? any GamePreservedSaveRepository else { throw SaveTransferError.readFailed }
        return try await repository.preservedNewerSaves()
    }

    func exportPreservedNewerSave(id: String) async throws -> Data {
        guard !isBusy, !isDecorating, !saveTransferInProgress else { throw SaveTransferError.busy }
        guard let repository = repository as? any GamePreservedSaveRepository else { throw SaveTransferError.readFailed }
        isBusy = true
        saveTransferInProgress = true
        defer { saveTransferInProgress = false; isBusy = false; drainPendingSynchronization() }
        return try await repository.exportPreservedNewerSave(id: id, exportedAt: Date())
    }

    func importRecoveryPreview() async throws -> NativeSaveArchive? {
        guard let repository = repository as? any GameSaveTransferRepository else { throw SaveTransferError.readFailed }
        guard let recovery = try await repository.loadImportRecovery() else { return nil }
        return try await Task.detached(priority: .userInitiated) {
            try NativeSaveTransfer.decode(NativeSaveTransfer.encode(snapshot: recovery,
                exportedAt: recovery.meta.lastSyncAt))
        }.value
    }

    func importSaveArchive(_ archive: NativeSaveArchive, isRecovery: Bool = false) async throws {
        guard !isBusy, !isDecorating, snapshot != nil else { throw SaveTransferError.busy }
        try await replaceSaveArchive(archive, isRecovery: isRecovery, afterLoadFailure: false)
    }

    func restoreSaveArchiveAfterLoadFailure(_ archive: NativeSaveArchive) async throws {
        guard !isBusy, !isLoading, !loadingInProgress, loadFailed,
              snapshot == nil, !hasEnteredHome else { throw SaveTransferError.busy }
        try await replaceSaveArchive(archive, isRecovery: true, afterLoadFailure: true)
    }

    private func replaceSaveArchive(_ archive: NativeSaveArchive, isRecovery: Bool,
                                    afterLoadFailure: Bool) async throws {
        guard let repository = repository as? any GameSaveTransferRepository else { throw SaveTransferError.writeFailed }
        let importDate = Date()
        try NativeSaveTransfer.validateImportTime(archive, now: importDate)
        // Import replaces a timeline. It must not replay physical events or completion
        // callbacks from the room that is about to be replaced.
        isBusy = true
        saveTransferInProgress = true
        if afterLoadFailure { isLoading = true }
        defer {
            if afterLoadFailure { isLoading = false; syncAudio() }
            saveTransferInProgress = false
            isBusy = false
            drainPendingSynchronization()
        }
        var candidate = archive.snapshot
        if let play = candidate.catPlay.activeSession {
            _ = CatHabitEngine.endPlay(&candidate, catID: play.catID, sessionID: play.id, now: importDate)
        }
        for cat in candidate.cats {
            if let rest = cat.activeRest {
                _ = GameEngine.endCatRest(&candidate, catID: cat.id, sessionID: rest.id, now: importDate)
            }
        }
        _ = GameEngine.synchronize(&candidate, now: importDate)
        do {
            #if os(macOS)
            candidate = try await MacRoomSaveRepair.prepare(candidate, now: importDate)
            #endif
            if afterLoadFailure { try await repository.restoreSnapshotAfterLoadFailure(candidate) }
            else { try await repository.importSnapshot(candidate) }
        } catch SaveRepositoryError.currentSaveReadable {
            throw SaveTransferError.currentSaveReadable
        } catch {
            // Import failure is not a failed autosave: the current timeline remains
            // usable and must never be retried later without a fresh confirmation.
            // The recovery sheet reports startup failures; don't replay them after a successful retry.
            if !afterLoadFailure { showNotice(GameStrings.text("saveTransfer.writeFailed")) }
            throw SaveTransferError.writeFailed
        }
        restTransitions.removeAll()
        companionMemories.clear()
        habitGuideCatID = nil
        isPresentingHabitGuide = false
        isPresentingHabitMemory = false
        inspectedMemoryCatID = nil
        pendingCatPlayEnd = nil
        showsPlayChoices = false
        isShowingPlayTogether = false
        playTogetherSessionID = nil
        audioSaveRequest?.completion?.resume(returning: false)
        audioSaveRequest = nil
        pendingAudioSettings = nil
        audioSettingsSaveFailed = false
        restingFurnitureID = nil
        presentedRestSessionID = nil
        feedback = nil
        pendingWorkResultID = nil
        inspectedCatID = nil
        hospitalCatID = nil
        inspectedCatShowsGrowth = false
        visibleRoomCatIDs = nil
        isInspectingHealth = false
        adoptionCatID = nil
        isPresentingAdoptionConfirmation = false
        isPresentingCommunityGift = false
        isShowingCommunityGiftShop = false
        isShowingNeighbors = false
        isShowingMarket = false
        isShowingTownBoard = false
        adoptionReminders.clearPending()
        isPresentingExchange = false
        supplyPicker = nil
        furniturePurchaseNotice = nil
        furniturePurchaseItemID = nil
        clearSaveFailure()
        now = importDate
        lastSyncCheck = importDate
        silentProgressThrough = nil
        snapshot = candidate
        #if os(macOS)
        macPreviousSaveAt = archive.snapshot.meta.lastSyncAt
        macRoomRepairFailed = false
        macPendingCreatedSnapshots.removeAll()
        #endif
        onboarding.didImport(snapshot: candidate)
        sharedHomeNoticeDefaults.removeObject(forKey: Self.sharedHomeSpaceNoticesKey)
        visibleHomeFloor = .ground
        roomFloorTravelReady = true
        homeUpgradeCelebration = nil
        saveSceneGeneration = UUID()
        GameLocalization.shared.language = candidate.settings.language
            ?? GameLanguage.preferred(in: Locale.preferredLanguages)
        if afterLoadFailure {
            startupProgress = 2.0 / 3
            startupPhase = "welcome.preparingRoom"
            await RoomScene.preloadWelcomeResources()
            startupProgress = 1
            startupPhase = "welcome.ready"
            needsNewerVersion = false
            loadFailed = false
        }
        showNotice(GameStrings.text(afterLoadFailure ? "saveTransfer.failureRestored"
            : (isRecovery ? "saveTransfer.restored" : "saveTransfer.imported")))
        #if os(macOS)
        if candidate.home != archive.snapshot.home { showNotice(GameStrings.text("mac.room.repaired")) }
        #endif
    }

    func showFurnitureNotice(_ key: String) { showNotice(GameStrings.text(key)) }

    func enterHome() {
        guard snapshot != nil, !isLoading, !loadFailed, !hasEnteredHome else { return }
        hasEnteredHome = true
        onboarding.show()
        refreshAdoptionReminders()
        syncAudio()
        audio.play(.enter, userInitiated: true)
        notices.enterHome()
    }

    func load() async {
        guard !loadingInProgress, !isBusy else { return }
        companionMemories.clear()
        habitGuideCatID = nil
        isPresentingHabitGuide = false
        isPresentingHabitMemory = false
        inspectedMemoryCatID = nil
        loadingInProgress = true
        isBusy = true
        isLoading = true
        loadFailed = false
        needsNewerVersion = false
        #if os(macOS)
        macRoomRepairFailed = false
        #endif
        startupProgress = 0
        startupPhase = "welcome.loadingSave"
        defer {
            loadingInProgress = false
            isLoading = false
            isBusy = false
            syncAudio()
            drainPendingSynchronization()
        }
        let loaded: GameSnapshot
        let loadDisposition: SaveLoadDisposition
        do {
            #if DEBUG
            #if os(macOS)
            if let directory = uiTestResetDirectory {
                uiTestResetDirectory = nil
                try MacSaveDirectoryLock.clearUITestFiles(in: directory)
                try fixtures.seedLoadFailureFiles(in: directory)
            }
            #endif
            if let fixture = fixtures.initialSnapshot {
                try await repository.save(fixture)
                fixtures.initialSnapshot = nil
            }
            #endif
            loaded = try await repository.loadOrCreate(now: Date())
            loadDisposition = await repository.lastLoadDisposition
        } catch {
            loadFailed = true
            if case SaveRepositoryError.unsupportedSchemaVersion(let version) = error {
                needsNewerVersion = version > GameSnapshot.currentSchemaVersion
            }
            snapshot = nil
            return
        }
        #if os(macOS)
        let prepared: GameSnapshot
        if case .created = loadDisposition {
            // Match the exact in-memory or encoded/read-back snapshot on a manual retry.
            // No time tolerance can mistake an unrelated imported save for a new home.
            macPendingCreatedSnapshots = [loaded]
            if let data = try? NativeSaveTransfer.encode(snapshot: loaded, exportedAt: loaded.meta.lastSyncAt),
               let diskValue = try? NativeSaveTransfer.decode(data, now: loaded.meta.lastSyncAt).snapshot {
                macPendingCreatedSnapshots.append(diskValue)
            }
        }
        let isNewHome = macPendingCreatedSnapshots.contains(loaded)
        do {
            prepared = try await MacRoomSaveRepair.prepare(loaded, now: Date(), isNewHome: isNewHome)
            if prepared != loaded { try await repository.save(prepared) }
            macPendingCreatedSnapshots.removeAll()
        } catch {
            // A required geometry repair is published only after its durable commit.
            macRoomRepairFailed = true
            loadFailed = true
            snapshot = nil
            return
        }
        #else
        let prepared = loaded
        #endif
        // Ordinary clock reconciliation still keeps a successful read usable on write failure.
        snapshot = prepared
        #if os(macOS)
        if case .created = loadDisposition { macPreviousSaveAt = nil }
        else { macPreviousSaveAt = loaded.meta.lastSyncAt }
        #endif
        onboarding.prepare(snapshot: prepared, disposition: loadDisposition)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--skip-onboarding") {
            onboarding.finish()
        }
        #endif
        GameLocalization.shared.language = prepared.settings.language
            ?? GameLanguage.preferred(in: Locale.preferredLanguages)
        startupProgress = 1.0 / 3
        startupPhase = "welcome.syncing"
        await Task.yield()
        let loadDate = Date()
        if let session = prepared.catPlay.activeSession {
            pendingCatPlayEnd = PendingCatPlayEnd(catID: session.catID, sessionID: session.id, occurredAt: loadDate)
        }
        silentProgressThrough = max(silentProgressThrough ?? .distantPast, loadDate)
        let hadCatRest = loaded.cats.contains { $0.activeRest != nil }
        for cat in prepared.cats {
            if let rest = cat.activeRest {
                restTransitions.append(RestTransition(catID: cat.id, furnitureID: nil,
                    sessionID: rest.id, occurredAt: loadDate))
            }
        }
        if var context = saveContext() {
            _ = GameEngine.synchronize(&context.candidate, now: loadDate)
            if context.candidate != context.original {
                do { try await commit(context) }
                catch { recordSaveFailure() }
            }
        }
        startupProgress = 2.0 / 3
        startupPhase = "welcome.preparingRoom"
        await RoomScene.preloadWelcomeResources()
        startupProgress = 1
        startupPhase = "welcome.ready"
        now = Date()
        lastSyncCheck = now
        if let cat { recordHabitStudy("launch", catID: cat.id) }
        var notices: [String] = []
        #if os(macOS)
        // A brand-new home is seeded with the wide-room layout; only an existing layout was "repaired".
        if !isNewHome, prepared.home != loaded.home {
            notices.append(GameStrings.text("mac.room.repaired"))
        }
        #endif
        if case .recoveredBackup = loadDisposition { notices.append(GameStrings.text("save.recovered")) }
        if hadCatRest { notices.append(GameStrings.text("rest.loadEnded")) }
        if !notices.isEmpty { showNotice(notices.joined(separator: "\n")) }
    }

    func setForeground(_ active: Bool) {
        if foreground != active { foregroundEpoch &+= 1 }
        if !active { adoptionReminders.clearPending() }
        foreground = active
        syncAudio()
        now = Date()
        if !active, let session = snapshot?.catPlay.activeSession, pendingCatPlayEnd?.sessionID != session.id {
            pendingCatPlayEnd = PendingCatPlayEnd(catID: session.catID, sessionID: session.id, occurredAt: now)
        }
        timerTask?.cancel()
        timerTask = nil
        if snapshot != nil { synchronize(playsProgressFeedback: false) }
        #if os(iOS)
        guard active else { return }
        #endif
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                guard let self else { break }
                self.now = Date()
                guard self.snapshot != nil else { continue }
                let workDue = self.snapshot?.player.activeWork.map { $0.endsAt <= self.now } ?? false
                let restDue = self.snapshot?.cats.contains { $0.activeRest.map { $0.endsAt <= self.now } ?? false } ?? false
                if workDue || restDue || self.now.timeIntervalSince(self.lastSyncCheck) >= 60 {
                    self.syncAudio()
                    self.synchronize(playsProgressFeedback: self.foreground)
                }
            }
        }
    }

    func feed() {
        if (snapshot?.inventory.food ?? 0) < foodRequired,
           (snapshot?.inventory.premiumFood ?? 0) >= foodRequired {
            openSupplyPicker(for: .food)
        } else { feed(supply: .food) }
    }
    func feed(supply: SupplyKind) {
        guard !isDecorating, !isBusy, let cat else { return }
        audio.noteUserInteraction()
        guard (snapshot?.inventory.count(supply) ?? 0) >= foodRequired else { showNotice(GameStrings.text(supply == .premiumFood ? "care.premiumFoodRequired" : "care.needFood")); shopCategory = .supplies; activeSheet = .shop; return }
        perform(returnsToRoom: activeSheet == .inventory) { state, now in
            GameEngine.feed(&state, catID: cat.id, supply: supply, now: now)
        }
    }

    func clean() {
        if (snapshot?.inventory.litter ?? 0) == 0, (snapshot?.inventory.premiumLitter ?? 0) > 0 {
            openSupplyPicker(for: .litter)
        } else { clean(supply: .litter) }
    }

    func openSupplyPicker(for supply: SupplyKind) {
        guard !isBusy, !isDecorating, cat != nil, supply != .toy else { return }
        supplyPicker = supply == .food || supply == .premiumFood ? .food : .litter
    }

    func useSupplyFromPicker(_ supply: SupplyKind) async -> Bool {
        let family: SupplyKind = supply == .food || supply == .premiumFood ? .food : .litter
        guard supply != .toy, supplyPicker == family, !isBusy, !isDecorating, let cat else { return false }
        let generation = saveSceneGeneration
        var effects: [String] = []
        var actionKind: ActionKind = .none
        let succeeded = await performPersistedAction(showsSuccessNotice: false) { state, date in
            let synchronized = GameEngine.synchronize(&state, now: date)
            guard synchronized.succeeded else { return synchronized }
            let before = state.cats.first { $0.id == cat.id }
            let result = family == .food ? GameEngine.feed(&state, catID: cat.id, supply: supply, now: date)
                : GameEngine.clean(&state, catID: cat.id, supply: supply, now: date)
            if result.succeeded, let before, let after = state.cats.first(where: { $0.id == cat.id }) {
                actionKind = result.kind
                effects = [("stat.satiety", after.satiety - before.satiety), ("stat.cleanliness", after.cleanliness - before.cleanliness),
                           ("stat.mood", after.mood - before.mood), ("stat.health", after.health - before.health),
                           ("stat.bond", after.intimacy - before.intimacy)]
                    .filter { $0.1 > 0 }.map { GameStrings.text($0.0) + " +\($0.1)" }
            }
            return result
        }
        guard succeeded, generation == saveSceneGeneration else { return false }
        supplyPicker = nil
        if activeSheet == .inventory { activeSheet = nil }
        feedback = RoomFeedback(kind: actionKind, catID: cat.id)
        showNotice(GameStrings.format("supplyPicker.used", GameStrings.text(SupplyCatalog.definition(for: supply).nameKey),
                                     effects.isEmpty ? GameStrings.text("design55.careFull") : effects.joined(separator: " · ")))
        return true
    }
    func clean(supply: SupplyKind) {
        guard !isDecorating, !isBusy, let cat else { return }
        audio.noteUserInteraction()
        guard (snapshot?.inventory.count(supply) ?? 0) > 0 else { showNotice(GameStrings.text(supply == .premiumLitter ? "care.premiumLitterRequired" : "care.needLitter")); shopCategory = .supplies; activeSheet = .shop; return }
        perform(returnsToRoom: activeSheet == .inventory) { state, now in
            GameEngine.clean(&state, catID: cat.id, supply: supply, now: now)
        }
    }

    func play() {
        guard !isShowingPlayTogether else { return }
        guard !isDecorating, !isBusy, let cat else { return }
        audio.noteUserInteraction()
        guard (snapshot?.inventory.toys ?? 0) > 0 else { showNotice(GameStrings.text("care.needToy")); shopCategory = .supplies; activeSheet = .shop; return }
        perform(returnsToRoom: activeSheet == .inventory) { state, now in
            GameEngine.play(&state, catID: cat.id, now: now)
        }
    }

    func buySupply(_ kind: SupplyKind) { perform { GameEngine.buySupply(&$0, kind: kind, now: $1) } }
    func buyFood() { perform { GameEngine.buyFood(&$0, quantity: 1, now: $1) } }
    func buyLitter() { perform { GameEngine.buyLitter(&$0, quantity: 1, now: $1) } }
    func buyToy() { perform { GameEngine.buyToy(&$0, quantity: 1, now: $1) } }
    func buyEquipment(itemID: String) {
        perform { GameEngine.purchaseEquipment(&$0, itemID: itemID, now: $1) }
    }
    func buyFurniture(offerID: String) {
        let generation = saveSceneGeneration
        let ownedIDs = Set(snapshot?.inventory.furniture.map(\.id) ?? [])
        perform(presentSuccess: { [weak self] in
            guard let self, self.saveSceneGeneration == generation,
                  self.activeSheet == .shop, !self.isShowingSettings else { return false }
            self.furniturePurchaseNotice = offerID
            self.furniturePurchaseItemID = self.snapshot?.inventory.furniture.first { !ownedIDs.contains($0.id) }?.id
            return true
        }) { GameEngine.purchaseFurniture(&$0, offerID: offerID, now: $1) }
    }

    func decoratePurchasedFurniture() async {
        guard !isBusy, furniturePurchaseNotice != nil, let itemID = furniturePurchaseItemID,
              storedFurniture.contains(where: { $0.id == itemID }) else { return }
        if availableFurnitureFloor != nil {
            await arrangeInventoryFurniture(id: itemID)
            return
        }
        if canUpgradeHome {
            openHomeUpgrade()
            return
        }
        isShowingSettings = false
        activeSheet = nil
        beginDecorating()
        isFurnitureTrayExpanded = true
        showNotice(furnitureCapacityNotice)
    }
    func upgradeHome(toLevel: Int) {
        guard !isSavingLayout, !isResolvingLayout, placingFurnitureID == nil else { return }
        let generation = saveSceneGeneration
        perform(presentSuccess: { [weak self] in
            guard let self, self.saveSceneGeneration == generation,
                  self.snapshot?.home.roomLevel == toLevel else { return false }
            self.homeUpgradeCelebration = HomeUpgradeCelebration(level: toLevel, rules: self.homeLayoutRules)
            return true
        }) { GameEngine.upgradeHome(&$0, toLevel: toLevel, now: $1) }
    }

    var canChangeHomeFloor: Bool {
        snapshot?.home.availableFloors.count == 2 && !isBusy && !isDecorating
            && !isChangingHomeFloor && !saveTransferInProgress && roomFloorTravelReady
    }

    func changeHomeFloor(to floor: HomeFloor) async {
        guard floor != visibleHomeFloor else { return }
        if isDecorating { showFurnitureNotice("homeFloor.finishLayout"); return }
        if !roomFloorTravelReady { showFurnitureNotice("homeFloor.waitCare"); return }
        guard canChangeHomeFloor, floor != visibleHomeFloor,
              snapshot?.home.availableFloors.contains(floor) == true else { return }
        isChangingHomeFloor = true
        defer { isChangingHomeFloor = false }
        let generation = saveSceneGeneration
        // Finish a real rest durably before carrying the companion upstairs.
        // A failed write leaves both the visible floor and the rest untouched.
        if let cat, cat.activeRest != nil || restingFurnitureID != nil {
            let succeeded = await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
                GameEngine.endCatRest(&$0, catID: cat.id, now: $1)
            }
            guard succeeded else { return }
        }
        guard generation == saveSceneGeneration else { return }
        restingFurnitureID = nil
        presentedRestSessionID = nil
        feedback = nil
        visibleRoomCatIDs = nil
        visibleHomeFloor = floor
        playNavigationSound()
        if floor == .upper, !sharedHomeNoticeDefaults.bool(forKey: "catlife.home.upperHintSeen.v1") {
            sharedHomeNoticeDefaults.set(true, forKey: "catlife.home.upperHintSeen.v1")
            showFurnitureNotice("homeFloor.hint")
        }
    }
    func openHomeUpgrade() {
        guard !isBusy, !isSavingLayout, !isResolvingLayout, placingFurnitureID == nil else { return }
        activeSheet = .upgrade
    }
    func startWork(jobID: String = "job_flyer") {
        perform { GameEngine.startWork(&$0, jobID: jobID, now: $1) }
    }

    func consumeWorkResultPresentation() {
        pendingWorkResultID = nil
    }
    func startSleep() { perform { GameEngine.startSleep(&$0, now: $1) } }
    func wakeUp() { perform { GameEngine.wakeUp(&$0, now: $1) } }

    func beginDecorating() {
        guard !isBusy, let snapshot else { return }
        guard !isDecorating else { return }
        arrangement68.reset()
        draftBowlPosition = snapshot.home.bowlPosition(on: visibleHomeFloor)
        draftFurniture = snapshot.home.placements(on: visibleHomeFloor)
        draftFurnitureOrientations = [:]
        selectedFurnitureID = nil
        selectedStoredFurnitureID = nil
        placingFurnitureID = nil
        isResolvingLayout = false
        isFurnitureTrayExpanded = true
        isDecorating = true
    }

    func openInventory() {
        guard !isSavingLayout else { return }
        inventoryCategory = .supplies
        activeSheet = .inventory
    }

    var language: GameLanguage { GameLocalization.shared.language }
    var homeDisplayName: String { snapshot?.home.name ?? GameStrings.text("home.title") }
    var playerDisplayName: String { snapshot?.player.profile.name ?? GameStrings.text("player.name.default") }

    @discardableResult
    func renamePlayer(to rawName: String?) async -> Bool {
        guard !isBusy, !isDecorating, var context = saveContext() else { return false }
        var candidate = context.candidate
        let name: String?
        if let rawName {
            guard let normalized = PlayerNameRules.normalized(rawName) else { return false }
            name = normalized
        } else {
            name = nil
        }
        guard candidate.player.profile.name != name else { return true }
        // This cosmetic change must preserve the latest career, equipment,
        // home and sound preferences, and publish only after a durable write.
        candidate.player.profile.name = name
        isBusy = true
        defer { isBusy = false; drainPendingSynchronization() }
        do {
            context.candidate = candidate
            try await commit(context)
            audio.play(.tap, userInitiated: true)
            return true
        } catch {
            recordSaveFailure(showAlert: false, userInitiated: true)
            // The name editor keeps the draft and presents an inline error.
            // Its saved display name remains unchanged for a safe retry.
            return false
        }
    }

    @discardableResult
    func renameCat(id: String, to rawName: String?) async -> Bool {
        guard !isBusy, !isDecorating, var context = saveContext(),
              let index = context.candidate.cats.firstIndex(where: { $0.id == id }) else { return false }
        let name: String?
        if let rawName {
            guard let normalized = CatNameRules.normalized(rawName) else { return false }
            name = normalized
        } else {
            name = nil
        }
        guard context.candidate.cats[index].customName != name else { return true }
        context.candidate.cats[index].customName = name
        isBusy = true
        defer { isBusy = false; drainPendingSynchronization() }
        do {
            try await commit(context)
            audio.play(.tap, userInitiated: true)
            return true
        } catch {
            // Keep the durable name; the editor owns its draft for a retry.
            recordSaveFailure(showAlert: false, userInitiated: true)
            return false
        }
    }

    func selectAvatar(_ id: String) {
        perform { GameEngine.selectAvatar(&$0, avatarID: id, now: $1) }
    }

    func equipItem(_ id: String) {
        perform { GameEngine.equipItem(&$0, itemID: id, now: $1) }
    }

    func unequipSlot(_ slot: EquipmentSlot) {
        perform { GameEngine.unequipSlot(&$0, slot: slot, now: $1) }
    }

    func equipStarterSet() {
        perform { GameEngine.equipStarterSet(&$0, now: $1) }
    }

    func openSettings() {
        guard !isBusy, !isDecorating else { return }
        isShowingSettings = true
    }

    func setLanguage(_ language: GameLanguage) {
        guard !isBusy, var context = saveContext(),
              context.candidate.settings.language != language else { return }
        var candidate = context.candidate
        // Use the same serialized save path as care and room changes. Only
        // publish the new preference after a successful atomic save, so an
        // unsuccessful write never presents a language that won't survive restart.
        isBusy = true
        candidate.settings.language = language
        Task {
            do {
                context.candidate = candidate
                try await commit(context)
                GameLocalization.shared.language = language
                showNotice(GameStrings.text("settings.languageSaved"))
            } catch {
                recordSaveFailure(userInitiated: true)
            }
            isBusy = false
            drainPendingSynchronization()
        }
    }

    @discardableResult
    func setHomeName(_ rawName: String?) async -> Bool {
        guard !isBusy, !isDecorating, var context = saveContext() else { return false }
        var candidate = context.candidate
        let name: String?
        if let rawName {
            guard let normalized = HomeNameRules.normalized(rawName) else { return false }
            name = normalized
        } else {
            // Restoring the localized default is explicit; invalid/empty input
            // must never accidentally erase an existing custom name.
            name = nil
        }
        guard candidate.home.name != name else { return true }
        candidate.home.name = name
        isBusy = true
        defer {
            isBusy = false
            drainPendingSynchronization()
        }
        do {
            context.candidate = candidate
            try await commit(context)
            return true
        } catch {
            recordSaveFailure(userInitiated: true)
            return false
        }
    }

    func openFurnitureInventory() {
        guard !isSavingLayout, !isResolvingLayout else { return }
        inventoryCategory = .furniture
        activeSheet = .inventory
    }

    func cancelDecorating() {
        guard isDecorating, !isSavingLayout else { return }
        clearLayoutDraft()
        showNotice(GameStrings.text("layout.restored"))
    }

    private func clearLayoutDraft() {
        arrangement68.reset()
        draftBowlPosition = nil
        draftFurniture = nil
        draftFurnitureOrientations = nil
        selectedFurnitureID = nil
        selectedStoredFurnitureID = nil
        placingFurnitureID = nil
        isResolvingLayout = false
        isDecorating = false
    }

    func finishDecorating() {
        guard !arrangement68.hasInvalidPlacement else {
            showNotice(GameStrings.text("build68.adjustInvalid")); return
        }
        guard arrangement68.pendingRequest == nil else { return }
        guard isDecorating, !isResolvingLayout, placingFurnitureID == nil,
              let point = draftBowlPosition, let furniture = draftFurniture,
              let orientations = draftFurnitureOrientations else { return }
        perform(finishesLayout: true) {
            GameEngine.setRoomLayout(&$0, bowlPosition: point, furniture: furniture,
                                     orientations: orientations, floor: self.visibleHomeFloor, rules: self.homeLayoutRules, now: $1)
        }
    }

    func inspectCat(catID: String? = nil, showGrowth: Bool = false) {
        guard !isDecorating else { return }
        let inspected = catID.flatMap { id in snapshot?.cats.first { $0.id == id } } ?? cat
        let voice: GameSoundEffect = inspected?.healthState?.illness != nil ? .catUnwell
            : ((inspected?.satiety ?? 100) < 50 ? .catHungry : .catHappy)
        audio.play(voice, userInitiated: true)
        inspectedMemoryCatID = nil
        inspectedCatShowsGrowth = showGrowth
        inspectedCatID = inspected?.id
    }

    func openHospital(catID: String? = nil) {
        guard !isDecorating, snapshot != nil else { return }
        hospitalCatID = catID.flatMap { id in snapshot?.cats.contains { $0.id == id } == true ? id : nil }
        inspectedCatID = nil
        isShowingSettings = false
        activeSheet = .hospital
    }

    func openNeighbors() {
        guard !isBusy, !isDecorating, snapshot != nil else { return }
        inspectedCatID = nil
        isShowingSettings = false
        activeSheet = .town
        catCollectionFilter = nil
        adoptionCatID = nil
        isShowingMarket = false
        isShowingTownBoard = false
        isShowingNeighbors = true
    }

    func visitNeighbor(id: String) async -> Bool {
        await visitNeighborWithReceipt(id: id) != nil
    }

    func visitNeighborWithReceipt(id: String,
        presentResult: (@MainActor (NeighborActionReceipt) -> Bool)? = nil) async -> NeighborActionReceipt? {
        await performNeighborAction(id: id, presentResult: presentResult) {
            GameEngine.visitNeighbor(&$0, neighborID: id, now: $1)
        }
    }

    func giveNeighborGift(neighborID: String, giftID: String) async -> Bool {
        await giveNeighborGiftWithReceipt(neighborID: neighborID, giftID: giftID) != nil
    }

    func giveNeighborGiftWithReceipt(neighborID: String, giftID: String,
        presentResult: (@MainActor (NeighborActionReceipt) -> Bool)? = nil) async -> NeighborActionReceipt? {
        await performNeighborAction(id: neighborID, presentResult: presentResult) {
            GameEngine.giveNeighborGift(&$0, neighborID: neighborID, giftID: giftID, now: $1)
        }
    }

    func buyCommunityGift(id: String) async -> Bool {
        await performPersistedAction { GameEngine.buyCommunityGift(&$0, giftID: id, quantity: 1, now: $1) }
    }

    func showCommunityGiftLimit() { showNotice(GameStrings.text("community.giftLimit")) }

    func showNeighborActionResult(_ receipt: NeighborActionReceipt) {
        guard receipt.saveSceneGeneration == saveSceneGeneration else { return }
        let base: String
        if receipt.friendshipGained == 0, receipt.success == .neighborVisited {
            base = GameStrings.text("community.visitClosest")
        } else if receipt.friendshipGained == 0, receipt.success == .neighborGifted {
            base = GameStrings.text("community.giftClosest")
        } else {
            base = message(for: ActionOutcome(success: receipt.success, amount: receipt.friendshipGained))
        }
        let rewards = [("community.rewardGold", receipt.goldAwarded), ("community.rewardFood", receipt.foodAwarded),
                       ("community.rewardLitter", receipt.litterAwarded), ("community.rewardToys", receipt.toyUsesAwarded)]
            .filter { $0.1 > 0 }.map { GameStrings.format($0.0, $0.1) }.joined(separator: " · ")
        let stageNotice = receipt.stageReached.map {
            "\n" + (rewards.isEmpty ? GameStrings.text("community.relationshipUpgraded") + " · " + GameStrings.text($0.nameKey)
                    : GameStrings.format("community.stageReached", GameStrings.text($0.nameKey)))
        } ?? ""
        let rewardNotice = receipt.stageReached == nil ? "" : "\n" + (rewards.isEmpty
            ? GameStrings.text("community.rewardAtCapacity") : rewards)
        showNotice(base + stageNotice + rewardNotice)
    }

    func performNeighborAction(id: String, exchanging offer: ExchangeOffer? = nil,
        presentResult: (@MainActor (NeighborActionReceipt) -> Bool)?,
        _ action: (inout GameSnapshot, Date) -> ActionOutcome) async -> NeighborActionReceipt? {
        let generation = saveSceneGeneration
        var receipt: NeighborActionReceipt?
        let succeeded = await performPersistedAction(showsSuccessNotice: false) {
            let synchronized = GameEngine.synchronize(&$0, now: $1)
            guard synchronized.succeeded else { return synchronized }
            let before = $0
            let outcome = action(&$0, $1)
            if outcome.succeeded, let success = outcome.success {
                let previous = before.community.relationship(for: id)
                let current = $0.community.relationship(for: id)
                let after = $0.inventory
                func reward(_ kind: SupplyKind) -> Int {
                    let spent = offer?.inputs.filter { $0.item == .supply(kind) }.reduce(0) { $0 + $1.quantity } ?? 0
                    let received = offer?.outputs.filter { $0.item == .supply(kind) }.reduce(0) { $0 + $1.quantity } ?? 0
                    // Remove the trade's net stock change, retaining only the actual stage reward.
                    return max(0, after.count(kind) - before.inventory.count(kind) + spent - received)
                }
                receipt = NeighborActionReceipt(neighborID: id, success: success, saveSceneGeneration: generation,
                    friendshipGained: current.friendship - previous.friendship,
                    stageReached: current.stage.level > previous.stage.level ? current.stage : nil,
                    goldAwarded: max(0, $0.player.gold - before.player.gold),
                    foodAwarded: reward(.food),
                    litterAwarded: reward(.litter),
                    toyUsesAwarded: reward(.toy))
            }
            return outcome
        }
        guard succeeded, let receipt, generation == saveSceneGeneration else { return nil }
        if receipt.stageReached != nil { playFeedback(.claim) }
        // Ask after the durable save; visibility may have changed while it was pending.
        if presentResult?(receipt) != true { showNeighborActionResult(receipt) }
        return receipt
    }

    @discardableResult
    func treatCat(catID: String) async -> Bool {
        await performPersistedAction(playsSound: false, showsSuccessNotice: false) { GameEngine.treatCat(&$0, catID: catID, now: $1) }
    }

    @discardableResult
    func adoptCat(catID: String, playsSound: Bool = true, showsSuccessNotice: Bool = true) async -> Bool {
        await performPersistedAction(playsSound: playsSound, showsSuccessNotice: showsSuccessNotice) {
            GameEngine.adoptCat(&$0, catID: catID, now: $1)
        }
    }

    @discardableResult
    func selectCompanion(catID: String) async -> Bool {
        await performPersistedAction { GameEngine.selectCompanion(&$0, catID: catID, now: $1) }
    }

    @discardableResult
    func claimTask(id: String, expectedDayKey: String? = nil) async -> Bool {
        await claimTaskWithReceipt(id: id, expectedDayKey: expectedDayKey) != nil
    }

    func claimTaskWithReceipt(id: String, expectedDayKey: String? = nil) async -> TaskClaimReceipt? {
        var awarded = 0
        let succeeded = await performPersistedAction(playsSound: false, showsSuccessNotice: false) {
            let outcome = GameEngine.claimTask(&$0, id: id, expectedDayKey: expectedDayKey, now: $1)
            awarded = outcome.amount
            return outcome
        }
        guard succeeded, let task = GameTaskCatalog.task(id: id) else { return nil }
        return TaskClaimReceipt(taskID: id, goldAwarded: awarded, experienceAwarded: task.expReward)
    }

    func performPersistedAction(playsSound: Bool = true, showsSuccessNotice: Bool = true,
                                        _ action: (inout GameSnapshot, Date) -> ActionOutcome) async -> Bool {
        guard !isBusy, !isDecorating, var context = saveContext() else { return false }
        isBusy = true
        defer { isBusy = false; drainPendingSynchronization() }
        let outcome = action(&context.candidate, Date())
        do {
            // Publish actions and their rewards only after the entire transaction is durable.
            if context.candidate != context.original { try await commit(context) }
            if outcome.succeeded && playsSound { playCommittedSound(outcome.kind) }
            if !outcome.succeeded { playFailureSound(outcome.failure) }
            if showsSuccessNotice || !outcome.succeeded { showNotice(message(for: outcome)) }
            return outcome.succeeded
        } catch {
            recordSaveFailure(userInitiated: true)
            audio.play(.softError, userInitiated: true)
            return false
        }
    }

    private func perform(finishesLayout: Bool = false, returnsToRoom: Bool = false,
                         presentSuccess: (() -> Bool)? = nil,
                         _ action: @escaping (inout GameSnapshot, Date) -> ActionOutcome) {
        guard !isBusy, var context = saveContext() else { return }
        isBusy = true
        isSavingLayout = finishesLayout
        let actionDate = Date()
        now = actionDate
        _ = GameEngine.synchronize(&context.candidate, now: actionDate)
        let outcome = action(&context.candidate, actionDate)
        guard context.candidate != context.original || outcome.succeeded else {
            isBusy = false
            isSavingLayout = false
            showNotice(message(for: outcome))
            playFailureSound(outcome.failure)
            drainPendingSynchronization()
            return
        }
        Task {
            do {
                try await commit(context)
                if finishesLayout && outcome.succeeded { clearLayoutDraft() }
                if outcome.succeeded {
                    if returnsToRoom && activeSheet == .inventory { activeSheet = nil }
                    feedback = RoomFeedback(kind: outcome.kind, catID: context.candidate.activeCatID)
                    playCommittedSound(outcome.kind)
                }
                if !outcome.succeeded || presentSuccess?() != true { showNotice(message(for: outcome)) }
                if !outcome.succeeded { playFailureSound(outcome.failure) }
            } catch {
                recordSaveFailure(userInitiated: true)
            }
            isBusy = false
            isSavingLayout = false
            drainPendingSynchronization()
        }
    }

    private func synchronize(userInitiated: Bool = false, playsProgressFeedback: Bool = true) {
        if !playsProgressFeedback {
            silentProgressThrough = max(silentProgressThrough ?? .distantPast, Date())
        }
        guard snapshot != nil else { return }
        guard !isBusy else {
            pendingSynchronization = true
            pendingManualRetry = pendingManualRetry || userInitiated
            return
        }
        if processPendingAudioSettings(userInitiated: userInitiated) { return }
        guard userInitiated || saveRetry.permitsAutomaticAttempt(at: Date()) else { return }
        guard var context = saveContext() else { return }
        lastSyncCheck = Date()
        _ = GameEngine.synchronize(&context.candidate, now: lastSyncCheck)
        let needsSave = requiresDurableSave(context.candidate, comparedTo: context.original)
        guard hasSaveFailure || needsSave else {
            acknowledgeTransitions(context.transitions)
            if pendingCatPlayEnd?.id == context.playEnd?.id { pendingCatPlayEnd = nil }
            finishSilentCatchUp(context)
            refreshAdoptionReminders()
            return
        }
        isBusy = true
        Task {
            do {
                if needsSave { try await commit(context) }
                else {
                    // Probe the directory without rewriting the unchanged save
                    // or rotating its checkpoint after a rolled-back action.
                    #if DEBUG
                    try fixtures.checkStorageProbe()
                    #endif
                    try await repository.checkWritable()
                    acknowledgeTransitions(context.transitions)
                    clearSaveFailure()
                    finishSilentCatchUp(context)
                    refreshAdoptionReminders()
                }
            } catch { recordSaveFailure(userInitiated: userInitiated) }
            isBusy = false
            drainPendingSynchronization()
        }
    }

    private func drainPendingSynchronization() {
        guard !isBusy else { return }
        if pendingManualRetry {
            pendingManualRetry = false
            pendingSynchronization = false
            synchronize(userInitiated: true)
            return
        }
        if processPendingAudioSettings() { return }
        if pendingCatPlayEnd != nil { synchronize(); return }
        if !restTransitions.isEmpty {
            processNextRestTransition()
            return
        }
        guard pendingSynchronization else { return }
        pendingSynchronization = false
        synchronize()
    }

    private func playCommittedSound(_ kind: ActionKind) {
        switch kind {
        case .purchase: audio.play(.purchase, userInitiated: true)
        case .workStarted: audio.play(.workStart, userInitiated: true)
        case .workFinished: break // The durable receipt owns this cue, including recovery gating.
        case .layout: audio.play(.place, userInitiated: true)
        case .sleepStarted: audio.play(.sleep, userInitiated: true)
        case .sleepEnded: audio.play(.wake, userInitiated: true)
        case .none: audio.play(.tap, userInitiated: true)
        // Care sounds are emitted by the actor at the actual contact/gesture.
        case .feed, .clean, .play, .catRestStarted, .catRestEnded: break
        }
    }

    private func playFailureSound(_ failure: ActionFailure?) {
        guard let failure else { return }
        audio.play([.shopGoldRequired, .hospitalGoldRequired].contains(failure) ? .shortGold : .softError,
                   userInitiated: true)
    }

    func showNotice(_ message: String) { notices.show(message, ready: hasEnteredHome) }
    var canPresentTownEventResult: Bool { foreground && hasEnteredHome }
    var isHabitInteractionActive: Bool { foreground && hasEnteredHome && !isLoading }

    private func message(for outcome: ActionOutcome) -> String {
        GameActionNotice.message(for: outcome, snapshot: snapshot)
    }
}
