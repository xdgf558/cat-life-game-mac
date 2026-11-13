import CatGameCore

/// Called only after a live, durable transition; loading and foreground catch-up stay quiet.
enum GameProgressFeedback {
    static func sound(from old: GameSnapshot, to new: GameSnapshot) -> GameSoundEffect? {
        if new.player.level > old.player.level { return .levelUp }
        if new.cats.contains(where: { cat in
            cat.healthState?.illness != nil && old.cats.first(where: { $0.id == cat.id })?.healthState?.illness == nil
        }) { return .sickAlert }
        if GameTaskCatalog.all.contains(where: {
            GameTaskCatalog.isClaimable($0, in: new) && !GameTaskCatalog.isClaimable($0, in: old)
        }) { return .taskDone }
        if old.tasks.dailyDayKey != nil, old.tasks.dailyDayKey != new.tasks.dailyDayKey { return .dailyReset }
        if new.activeCatID == old.activeCatID {
            if old.activeCat?.activeRest == nil, new.activeCat?.activeRest != nil { return .catSleepy }
            if let before = old.activeCat, let after = new.activeCat, before.satiety >= 50, after.satiety < 50 {
                return .catHungry
            }
        }
        return nil
    }
}
