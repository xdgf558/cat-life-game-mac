import SwiftUI
import SpriteKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import CatGameCore

/// Display-only choices and summaries; the accepted Core session remains authoritative.
enum PlayDesign68Presentation {
    static func tutorialAvailable(in snapshot: GameSnapshot?) -> Bool {
        guard let snapshot else { return false }
        return !snapshot.catPlay.tutorialCompleted
            && (snapshot.catPlay.tutorialCatID == nil || snapshot.catPlay.tutorialCatID == snapshot.activeCatID)
    }
    static func speedSegment(for kind: CatPlayInputKind) -> Int {
        // Core exposes classified input, not numeric speed; the amber segment adds no new threshold.
        switch kind { case .still, .moveAndPause: 0; case .slowMove: 1; case .tooFast: 3 }
    }
    static func stageHeight(available: CGFloat, accessibility: Bool) -> CGFloat {
        max(140, min(accessibility ? 240 : 320, available - (accessibility ? 240 : 200)))
    }

    static func responseKey(for rhythm: CatPlayRhythm, session: CatPlaySession, definition: CatHabitDefinition?) -> String {
        guard session.observedRhythms.contains(rhythm) else { return "play68.notObserved" }
        guard let definition else { return "play68.observed" }
        let matched = session.completeResponse && rhythm == definition.play
        return "catHabits.playHint.\(rhythm.rawValue).\(matched ? "match" : "compare")"
    }
}

@MainActor
struct CatPlayTogetherView: View {
    let store: GameStore
    let session: CatPlaySession
    @State private var controller: CatPlayTogetherController?

    var body: some View {
        Group {
            if let controller { CatPlayTogetherContent(store: store, controller: controller) }
            else { ProgressView(GameStrings.text("catHabits.playOpened")).frame(maxWidth: .infinity, maxHeight: .infinity).background(RoomTheme.friendshipPaper) }
        }
        .task {
            if controller == nil { controller = CatPlayTogetherController(store: store, session: session) }
        }
    }
}

@MainActor
private struct CatPlayTogetherContent: View {
    let store: GameStore
    let controller: CatPlayTogetherController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.gameReduceMotionOverride) private var motionOverride
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var cat: CatState? { store.snapshot?.cats.first { $0.id == controller.session.catID } }
    private var effectiveReducedMotion: Bool {
        #if DEBUG
        motionOverride || reduceMotion || (ProcessInfo.processInfo.arguments.contains("--ui-testing")
                         && ProcessInfo.processInfo.arguments.contains("--reduce-motion-test"))
        #else
        motionOverride || reduceMotion
        #endif
    }
    private var hasFailure: Bool { controller.failed || store.hasSaveFailure }
    private var motionColor: Color {
        if controller.phase == "tooFast" { return RoomTheme.coralDeep }
        return ["pouncing", "satisfied"].contains(controller.phase) ? RoomTheme.friendshipDeep : RoomTheme.darkMint
    }

    var body: some View {
        GeometryReader { geometry in
        ScrollView {
            VStack(spacing: 16) {
                if let receipt = controller.result {
                    if store.habitStudyMode && !controller.continuedStudy { studyQuestion }
                    else { result(receipt) }
                } else if controller.ending {
                    ProgressView(GameStrings.text("catHabits.saving")).padding(30)
                } else {
                    rhythmSteps
                    stage(height: PlayDesign68Presentation.stageHeight(available: geometry.size.height, accessibility: dynamicTypeSize.isAccessibilitySize))
                    Text(GameStrings.text("catHabits.dragHint")).font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if dynamicTypeSize.isAccessibilitySize && (!store.habitStudyMode || effectiveReducedMotion) {
                        Text(GameStrings.text(controller.motionKey)).font(.subheadline.weight(.bold)).foregroundStyle(motionColor)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("playTogetherReaction")
                    }
                    if controller.session.isTutorial { tutorialTip }
                    if controller.working { ProgressView(GameStrings.text("catHabits.saving")) }
                }
                if hasFailure { failureCard }
            }.padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .id(controller.result == nil ? "play-stage" : "play-result")
        .accessibilityIdentifier("playTogetherScroll")
        }
        .safeAreaInset(edge: .top, spacing: 0) { if controller.result == nil { header } }
        .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        .background(LinearGradient(colors: [RoomTheme.friendshipPaper, RoomTheme.cream], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink)
        .environment(\.locale, Locale(identifier: store.language.rawValue)).interactiveDismissDisabled(true)
        .saveRecoveryAlert(store: store)
        .task {
            controller.scene.reducedMotion = effectiveReducedMotion
            while !Task.isCancelled && controller.result == nil {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                controller.tick()
            }
        }
        .onChange(of: scenePhase) { _, phase in controller.setVisible(phase == .active) }
        .onChange(of: effectiveReducedMotion) { _, value in controller.scene.reducedMotion = value }
        .onChange(of: controller.phase) { _, value in
            #if os(iOS)
            if UIAccessibility.isVoiceOverRunning && ["pouncing", "waiting", "tooFast", "satisfied"].contains(value) {
                UIAccessibility.post(notification: .announcement, argument: GameStrings.text(controller.motionKey))
            }
            #elseif os(macOS)
            if ["pouncing", "waiting", "tooFast", "satisfied"].contains(value) {
                NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                    userInfo: [.announcement: GameStrings.text(controller.motionKey), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
            }
            #endif
        }
        .onDisappear { controller.finish() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { controller.finish() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .heavy)).frame(width: 44, height: 44)
                    .background(RoomTheme.paper, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(GameStrings.text("catHabits.finish"))
                .accessibilityIdentifier("playTogetherClose")
                .disabled(controller.ending)
            Text(cat.map { GameStrings.format("play68.title", GameStrings.catName($0)) } ?? GameStrings.text("catHabits.playTogether"))
                .font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
            Text(GameStrings.format("catHabits.seconds", Int(ceil(controller.remaining))))
                .font(.subheadline.weight(.heavy)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 86 : 56)
                .padding(10).background(RoomTheme.paper, in: Capsule()).accessibilityIdentifier("playTogetherTime")
        }.padding(.horizontal, 16).padding(.vertical, 10).background(RoomTheme.friendshipPaper)
    }
    private var actionBar: some View {
        VStack(spacing: 8) {
            if controller.result == nil && !controller.ending {
                if dynamicTypeSize.isAccessibilitySize { VStack(spacing: 8) { controls } }
                else { HStack(spacing: 12) { controls } }
                Text(GameStrings.text(controller.current.paidAt != nil ? "play68.paidTag"
                                      : controller.session.isTutorial ? "play68.freeTag" : "play68.oneToy"))
                    .font(.caption2.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(GameStrings.text(controller.current.paidAt != nil ? "catHabits.paidHint"
                                        : controller.session.isTutorial ? "catHabits.freeHint" : "catHabits.costHint"))
            }
            if controller.result != nil {
                Button { close() } label: { actionLabel("catGrowth.goHome") }.buttonStyle(MintButtonStyle())
                    .accessibilityIdentifier("playTogetherFinishButton")
            } else {
                Button {
                    if hasFailure && controller.ending { close() } else { controller.finish() }
                } label: { actionLabel(hasFailure && controller.ending ? "catGrowth.goHome" : "catHabits.finish") }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(controller.ending && !hasFailure).accessibilityIdentifier("playTogetherFinishButton")
            }
        }.padding(16).background(RoomTheme.cream)
            .accessibilityElement(children: .contain).accessibilityIdentifier("playTogetherActionBar")
    }
    private func actionLabel(_ key: String) -> some View {
        Text(GameStrings.text(key)).font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
    }
    private var rhythmSteps: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { VStack(spacing: 8) { steps } }
            else { HStack(spacing: 8) { steps } }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("playTogetherRhythmProgress")
    }
    @ViewBuilder private var steps: some View {
        ForEach(CatPlayRhythm.allCases, id: \.self) { rhythm in
            let observed = controller.current.observedRhythms.contains(rhythm)
            let active = controller.activeRhythm == rhythm
            Label(GameStrings.text("catHabits.control.\(rhythm.rawValue)"), systemImage: observed ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.bold)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(observed ? RoomTheme.darkMint : RoomTheme.secondary).padding(.horizontal, 9).padding(.vertical, 5)
                .background(observed ? RoomTheme.mint.opacity(0.1) : RoomTheme.paper, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(active ? RoomTheme.mint : .white, lineWidth: 2))
                .accessibilityValue(observed ? GameStrings.text("common.done") : GameStrings.text("catHabits.learning"))
                .accessibilityIdentifier("playTogetherStep_\(rhythm.rawValue)")
        }
    }
    private func stage(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                CatPlayCanvas(scene: controller.scene, size: geometry.size,
                              active: scenePhase == .active && !controller.ending && !hasFailure)
                    .overlay(alignment: .top) {
                        if !dynamicTypeSize.isAccessibilitySize && (!store.habitStudyMode || effectiveReducedMotion) {
                            Label(GameStrings.text(controller.motionKey), systemImage: controller.phase == "tooFast" ? "tortoise.fill" : "eye.fill")
                                .font(.subheadline.weight(.bold)).foregroundStyle(motionColor)
                                .fixedSize(horizontal: false, vertical: true).padding(12)
                                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(motionColor.opacity(0.3), lineWidth: 2))
                                .padding(14).allowsHitTesting(false)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(GameStrings.text(controller.motionKey))
                                .accessibilityIdentifier("playTogetherReaction")
                        }
                    }
                    .overlay {
                        if !controller.hasDragged && controller.activeRhythm == nil {
                            Image(systemName: "hand.draw.fill").font(.system(size: 26)).foregroundStyle(RoomTheme.friendshipDeep)
                                .padding(10).background(Circle().strokeBorder(RoomTheme.friendship, lineWidth: 2))
                                .position(x: geometry.size.width * 0.67, y: geometry.size.height * 0.53)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
            }
            .frame(height: height)
            .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text("catHabits.stageAccessibility"))
            .accessibilityValue(TownEventAccessibility.value(GameStrings.text(controller.motionKey),
                diagnostic: "\(controller.phase)|\(controller.scene.pounces)|\(controller.current.effects.toysSpent)|\(controller.current.observedRhythms.count)"))
            .accessibilityIdentifier("playTogetherStage")
            .accessibilityAction(named: Text(GameStrings.text("catHabits.control.slowMove"))) { controller.control(.slowMove) }
            .accessibilityAction(named: Text(GameStrings.text("catHabits.control.moveAndPause"))) { controller.control(.moveAndPause) }
            PlaySpeedGauge68(kind: controller.speedKind).padding(12)
        }
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 28)).clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 3))
    }
    @ViewBuilder private var controls: some View {
        ForEach(CatPlayRhythm.allCases, id: \.self) { rhythm in
            Button { controller.control(rhythm) } label: {
                Label(GameStrings.text("catHabits.control.\(rhythm.rawValue)"), systemImage: rhythm == .slowMove ? "arrow.left.arrow.right" : "pause.circle.fill")
                    .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 54)
            }.buttonStyle(SoftButtonStyle())
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(controller.activeRhythm == rhythm ? RoomTheme.mint : .clear, lineWidth: 2))
                .disabled(controller.phase == "pouncing" || controller.demonstrating || controller.working || hasFailure)
                .accessibilityIdentifier("playTogether_\(rhythm.rawValue)")
        }
    }
    private var tutorialTip: some View {
        Text(GameStrings.text(tutorialHint)).font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("playTogetherTutorialHint")
            .accessibilityValue(TownEventAccessibility.value(GameStrings.text(tutorialHint),
                diagnostic: String(store.snapshot?.catPlay.tutorialRhythms.count ?? 0)))
    }
    private var tutorialHint: String {
        let tried = store.snapshot?.catPlay.tutorialRhythms ?? []
        if !tried.contains(.slowMove) { return "catHabits.tutorial.slow" }
        if !tried.contains(.moveAndPause) { return "catHabits.tutorial.pause" }
        return "catHabits.tutorial.done"
    }
    private var failureCard: some View {
        VStack(spacing: 12) {
            Text(GameStrings.text("catHabits.saveFailed")).font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                .fixedSize(horizontal: false, vertical: true)
            Button(GameStrings.text("save.retry")) { controller.retry(); store.retrySaving() }
                .buttonStyle(SoftButtonStyle()).accessibilityIdentifier("playTogetherRetry")
            Button(GameStrings.text("catGrowth.goHome")) { close() }.buttonStyle(SoftButtonStyle())
        }.padding(16).gameCard().accessibilityIdentifier("playTogetherSaveFailed")
    }
    private var studyQuestion: some View {
        VStack(spacing: 18) {
            Image(systemName: "pawprint.fill").font(.system(size: 32)).foregroundStyle(RoomTheme.friendship)
            Text(GameStrings.text("catHabits.studyQuestion")).font(.headline.weight(.heavy))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { controller.continuedStudy = true } label: {
                Text(GameStrings.text("catHabits.continue")).font(.headline).frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("playTogetherContinue")
        }.padding(24).gameCard()
    }

    private func result(_ receipt: CatPlayReceipt) -> some View {
        VStack(spacing: 16) {
            if let cat {
                GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 88)
                    .padding(12).background(RoomTheme.paper, in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .accessibilityHidden(true)
            }
            Text(GameStrings.text("catHabits.resultTitle")).font(.title.weight(.heavy)).accessibilityAddTraits(.isHeader)
            Text(GameStrings.text(receipt.session.observedRhythms.count == 2
                                  ? (cat?.habits.playConfirmed == true ? "play68.confirmedSummary" : "catHabits.tutorial.done")
                                  : "play68.partialSummary"))
                .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let cat, let memory = cat.habits.memories.last(where: { !controller.initialMemoryKinds.contains($0.kind) }) {
                memoryCard(memory)
                    .onAppear {
                        store.companionMemories.acknowledge(catID: cat.id, kind: memory.kind, generation: controller.generation)
                    }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(GameStrings.text("play68.responses")).font(.subheadline.weight(.heavy)).foregroundStyle(RoomTheme.secondary)
                ForEach(CatPlayRhythm.allCases, id: \.self) { rhythm in responseRow(rhythm, receipt: receipt) }
            }.padding(16).gameCard(cornerRadius: 25).accessibilityIdentifier("playTogetherResponses")
            clueCard
            if dynamicTypeSize.isAccessibilitySize { VStack(spacing: 10) { receiptTiles(receipt.session.effects) } }
            else { HStack(alignment: .top, spacing: 8) { receiptTiles(receipt.session.effects) } }
            if receipt.session.isTutorial {
                Text(GameStrings.text("catHabits.freeHint")).font(.footnote).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if receipt.session.paidAt == nil {
                Text(GameStrings.text("catHabits.noSpend")).font(.footnote).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let effects = receipt.session.effects
            if effects.intimacy > 0 || effects.energySpent > 0 {
                Text((effects.intimacy > 0 ? GameStrings.text("stat.bond") + " +\(effects.intimacy)" : "")
                     + (effects.intimacy > 0 && effects.energySpent > 0 ? " · " : "")
                     + (effects.energySpent > 0 ? GameStrings.text("rest.energy") + " −\(effects.energySpent)" : ""))
                    .font(.footnote.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(GameStrings.text("catHabits.restNextHint"), systemImage: "lightbulb.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        }
        .frame(maxWidth: .infinity).accessibilityElement(children: .contain).accessibilityIdentifier("playTogetherResult")
        .accessibilityValue(TownEventAccessibility.value(GameStrings.text("catHabits.resultTitle"),
            diagnostic: "\(receipt.catID)|\(receipt.session.observedRhythms.count)|\(receipt.session.effects.toysSpent)"))
    }
    private func responseRow(_ rhythm: CatPlayRhythm, receipt: CatPlayReceipt) -> some View {
        let key = PlayDesign68Presentation.responseKey(for: rhythm, session: receipt.session,
                                                      definition: cat.flatMap { CatHabitCatalog.definition(for: $0.id) })
        let matched = receipt.session.observedRhythms.contains(rhythm) && receipt.session.completeResponse
            && cat.flatMap { CatHabitCatalog.definition(for: $0.id)?.play } == rhythm
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: rhythm == .slowMove ? "arrow.left.arrow.right" : "pause.circle.fill")
                .font(.system(size: 19, weight: .bold)).foregroundStyle(matched ? RoomTheme.friendshipDeep : RoomTheme.secondary)
                .frame(width: 36, height: 40).background(.white, in: RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(GameStrings.text("catHabits.control.\(rhythm.rawValue)")).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                Text(GameStrings.text(key)).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(cat?.habits.lastPlayObservation?.sessionID == receipt.id && cat?.habits.lastPlayObservation?.rhythm == rhythm
                                             ? "habitLatestHint" : "playTogetherResponse_\(rhythm.rawValue)")
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(matched ? RoomTheme.friendshipPaper : RoomTheme.cream, in: RoundedRectangle(cornerRadius: 18))
    }
    private var clueCard: some View {
        let count = cat?.habits.playClueSessionIDs.count ?? 0
        let preference = cat?.habits.playConfirmed == true ? cat.flatMap { CatHabitCatalog.definition(for: $0.id)?.play } : nil
        return VStack(alignment: .leading, spacing: 10) {
            Text(GameStrings.text("catHabits.play") + " · " + (preference.map { GameStrings.text("catHabits.playConfirmed.\($0.rawValue)") }
                                                           ?? GameStrings.text("catHabits.learning")))
                .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            Text(GameStrings.format("catHabits.clues", count)).font(.caption.weight(.semibold))
                .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(0..<CatHabitCatalog.cluesToConfirm, id: \.self) { index in
                    Circle().fill(index < count ? RoomTheme.friendship : .clear)
                        .overlay(Circle().strokeBorder(RoomTheme.friendshipBorder, style: StrokeStyle(lineWidth: 2, dash: index < count ? [] : [4, 3])))
                        .frame(width: 18, height: 18)
                }
            }.accessibilityHidden(true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(.white, lineWidth: 3))
            .accessibilityElement(children: .combine).accessibilityIdentifier("habitPlayProgress")
            .accessibilityValue(TownEventAccessibility.value(GameStrings.format("catHabits.clues", count), diagnostic: "\(count)/2"))
    }
    private func memoryCard(_ memory: CatMemory) -> some View {
        HStack(alignment: .top, spacing: 14) {
            GameIcon(asset: "icon-play", symbol: "heart.fill", size: 45).padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 10)).rotationEffect(.degrees(effectiveReducedMotion ? 0 : -5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(GameStrings.text("play68.newMemory")).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.friendshipDeep)
                Text(GameStrings.text(memory.kind.titleKey)).font(.headline.weight(.heavy))
                Text(GameStrings.text(memory.kind.bodyKey)).font(.subheadline).foregroundStyle(RoomTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 3))
            .accessibilityElement(children: .combine).accessibilityIdentifier("catMemory_\(memory.kind.rawValue)")
    }
    @ViewBuilder private func receiptTiles(_ effects: CatPlayEffects) -> some View {
        receiptTile(symbol: "leaf.fill", title: GameStrings.text("play68.toyLabel"),
                    value: effects.toysSpent == 0 ? GameStrings.text("play68.noToyUsed") : GameStrings.format("play68.toyUses", effects.toysSpent),
                    tint: RoomTheme.gold)
            .accessibilityIdentifier("playTogetherToyCost").accessibilityValue(String(effects.toysSpent))
        receiptTile(symbol: "face.smiling.fill", title: GameStrings.text("catHabits.catMood"),
                    value: effects.catMood == 0 ? "0" : "+\(effects.catMood)", tint: RoomTheme.friendshipDeep)
            .accessibilityIdentifier("playTogetherCatMood").accessibilityValue(String(effects.catMood))
        receiptTile(symbol: "heart.fill", title: GameStrings.text("catHabits.playerMood"),
                    value: effects.playerMood == 0 ? "0" : "+\(effects.playerMood)", tint: RoomTheme.darkMint)
            .accessibilityIdentifier("playTogetherPlayerMood").accessibilityValue(String(effects.playerMood))
    }
    private func receiptTile(symbol: String, title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 19, weight: .bold)).accessibilityHidden(true)
            Text(value).font(.headline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            Text(title).font(.caption.weight(.bold)).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(tint).multilineTextAlignment(.center).padding(12).frame(maxWidth: .infinity, minHeight: 96)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 20)).accessibilityElement(children: .combine)
    }
    private func close() {
        controller.finish(); store.isShowingPlayTogether = false
        store.isShowingSettings = false; store.inspectedCatID = nil; store.activeSheet = nil
    }
}

@MainActor
private struct PlaySpeedGauge68: View {
    let kind: CatPlayInputKind
    private let names = ["still", "slowMove", "fast", "tooFast"]
    private let colors = [Color(red: 0.76, green: 0.88, blue: 0.94), RoomTheme.mint, RoomTheme.gold, RoomTheme.coral]
    private var index: Int { PlayDesign68Presentation.speedSegment(for: kind) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack { title; Spacer(); current }
                VStack(alignment: .leading, spacing: 5) { title; current }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) { ForEach(names.indices, id: \.self) { colors[$0] } }.frame(height: 10).clipShape(Capsule())
                    Circle().fill(.white).overlay(Circle().strokeBorder(colors[index], lineWidth: 3)).frame(width: 20, height: 20)
                        .offset(x: max(0, geometry.size.width * (CGFloat(index) + 0.5) / 4 - 10))
                }
            }.frame(height: 20).accessibilityHidden(true)
            HStack(alignment: .top, spacing: 4) {
                ForEach(names, id: \.self) { name in
                    Text(GameStrings.text("play68.speed.\(name)")).font(.caption2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
                }
            }.foregroundStyle(RoomTheme.secondary).accessibilityHidden(true)
        }.padding(12).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text("play68.toySpeed"))
            .accessibilityValue(GameStrings.text("play68.speed.\(names[index])"))
            .accessibilityHint(GameStrings.text("play68.speedAccessibility")).accessibilityIdentifier("playTogetherSpeed")
    }
    private var title: some View { Text(GameStrings.text("play68.toySpeed")).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary) }
    private var current: some View { Text(GameStrings.text("play68.speed.\(names[index])")).font(.caption.weight(.heavy)).foregroundStyle(index == 3 ? RoomTheme.coralDeep : RoomTheme.darkMint) }
}

#if os(iOS)
@MainActor
private struct CatPlayCanvas: UIViewRepresentable {
    let scene: CatPlayTogetherScene
    let size: CGSize
    let active: Bool
    func makeUIView(context: Context) -> SKView {
        let view = SKView(); view.backgroundColor = .clear; view.preferredFramesPerSecond = 30
        view.isAccessibilityElement = false; view.accessibilityElementsHidden = true
        scene.size = size; view.presentScene(scene); view.isPaused = !active
        return view
    }
    func updateUIView(_ view: SKView, context: Context) {
        if abs(scene.size.width - size.width) > 0.01 || abs(scene.size.height - size.height) > 0.01 { scene.size = size }
        view.isPaused = !active; scene.isPaused = !active
    }
    static func dismantleUIView(_ view: SKView, coordinator: ()) { view.isPaused = true }
}
#elseif os(macOS)
@MainActor
private struct CatPlayCanvas: NSViewRepresentable {
    let scene: CatPlayTogetherScene
    let size: CGSize
    let active: Bool
    func makeNSView(context: Context) -> SKView {
        let view = SKView(); view.preferredFramesPerSecond = 30
        view.allowsTransparency = true; view.setAccessibilityElement(false)
        scene.size = size; view.presentScene(scene); view.isPaused = !active
        return view
    }
    func updateNSView(_ view: SKView, context: Context) {
        if scene.size != size { scene.size = size }
        view.isPaused = !active; scene.isPaused = !active
    }
    static func dismantleNSView(_ view: SKView, coordinator: ()) { view.isPaused = true }
}
#endif
