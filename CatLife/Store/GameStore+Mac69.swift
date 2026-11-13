import CatGameCore

extension GameStore {
    @discardableResult
    func cancelWork() async -> Bool {
        await performPersistedAction { GameEngine.cancelWork(&$0, now: $1) }
    }
}
