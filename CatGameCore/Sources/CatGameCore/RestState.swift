import Foundation

public struct PlayerSleep: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var staminaUpdatedAt: Date
    public var moodUpdatedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
        staminaUpdatedAt = startedAt
        moodUpdatedAt = startedAt
    }
}

public struct CatRest: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var furnitureID: String
    public var startedAt: Date
    public var endsAt: Date
    public var energyReward: Int
    /// Already settled reward, including points discarded by the stat cap.
    public var energyGranted: Int
    /// The end of the interval already excluded from normal energy decay.
    public var energyPausedUntil: Date
    public var observation: CatRestObservation?

    public init(id: String = UUID().uuidString, furnitureID: String,
                startedAt: Date, endsAt: Date, energyReward: Int,
                energyGranted: Int = 0, energyPausedUntil: Date? = nil, observation: CatRestObservation? = nil) {
        self.id = id
        self.furnitureID = furnitureID
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.energyReward = energyReward
        self.energyGranted = energyGranted
        self.energyPausedUntil = energyPausedUntil ?? startedAt
        self.observation = observation
    }
}
