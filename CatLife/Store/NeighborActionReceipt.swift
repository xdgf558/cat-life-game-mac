import Foundation
import CatGameCore

/// Only the durable neighbor action is included; prior time synchronization is excluded.
struct NeighborActionReceipt: Equatable, Sendable {
    let neighborID: String
    let success: ActionSuccess
    let saveSceneGeneration: UUID
    let friendshipGained: Int
    let stageReached: FriendshipStage?
    let goldAwarded: Int
    let foodAwarded: Int
    let litterAwarded: Int
    let toyUsesAwarded: Int
}
