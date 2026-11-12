#if os(macOS)
import SwiftUI
import CatGameCore

@MainActor
struct MacHomeView: View {
    let store: GameStore
    let scene: RoomScene
    let preferences: MacPreferences
    let isActive: Bool
    let onTasks: () -> Void
    let onInventory: () -> Void
    let onCats: () -> Void
    let onRest: (String) -> Void
    let onContext: (MacRoomContextAction) -> Void
    let onFixedStructure: (MacRoomStructure) -> Void
    @State private var need = CatNeedPresentation()
    @State private var cameraRevision = 0
    @State private var recent: [MacHomeLogEntry] = []
    private var daily: [GameTaskDefinition] {
        guard let snapshot = store.snapshot else { return [] }
        return Array(GameTaskCatalog.all.filter { $0.category == .daily && GameTaskCatalog.isUnlocked($0, in: snapshot) && !GameTaskCatalog.isClaimed($0, in: snapshot) }.prefix(3))
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 16) {
                stage.frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    VStack(spacing: 14) {
                        catCard
                        tasks
                        if let cat = store.cat, let memory = cat.habits.pinnedMemory { PinnedHabitPrompt(store: store, cat: cat, memory: memory) }
                        homeLog
                    }
                }.frame(width: geometry.size.width < 1270 ? 320 : 372)
                    .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macHomePage")
        .onChange(of: store.toast) { _, message in
            guard let message else { return }
            recent.append(MacHomeLogEntry(text: message, at: store.now)); if recent.count > 3 { recent.removeFirst() }
        }
    }
    private var stage: some View {
        GeometryReader { geometry in
            ZStack {
                MacRoomCanvas(store: store, scene: scene, isActive: isActive, frameLimit: preferences.frameLimit,
                              wheelReversed: preferences.wheelReversed, contextMenus: preferences.contextMenus,
                              hoverHints: preferences.hoverHints,
                              isDaylight: !preferences.followDaylight || !MacTitleMetricsV2.isNight(at: store.now),
                              needPresentation: need,
                              onRestRequest: onRest, onContextAction: onContext,
                              onViewChanged: { cameraRevision += 1 }, onFixedStructure: onFixedStructure)
                CatNeedBubble(reducedMotion: preferences.reduceMotion, store: store, presentation: need, canvasSize: geometry.size,
                              isActive: isActive, canAct: { !store.isBusy }, bottomInset: 96)
            }
            .overlay(alignment: .top) { stageHeader.padding(16) }
            .overlay(alignment: .bottom) { stageFooter.padding(16) }
        }
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white, lineWidth: 3).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .contain)
    }
    private var stageHeader: some View {
        HStack(spacing: 10) {
            if (store.snapshot?.home.roomLevel ?? 1) >= 6 {
                HStack(spacing: 4) {
                    ForEach(HomeFloor.allCases, id: \.self) { floor in
                        Button { Task { _ = await store.changeHomeFloor(to: floor) } } label: {
                            Text(GameStrings.text(floor == .ground ? "mac.floor.ground" : "mac.floor.upper"))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .foregroundStyle(store.visibleHomeFloor == floor ? .white : RoomTheme.ink)
                                .background(store.visibleHomeFloor == floor ? RoomTheme.mint : RoomTheme.paper, in: Capsule())
                        }.buttonStyle(.plain).disabled(store.isBusy)
                            .accessibilityIdentifier("macFloor_" + floor.rawValue)
                    }
                }.padding(3).background(.white.opacity(0.7), in: Capsule())
            } else {
                Label(GameStrings.text("mac.floor.ground"), systemImage: "house.fill")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9).background(RoomTheme.mint, in: Capsule())
            }
            Label(GameStrings.format("mac.home.v2.catsHome", (store.visibleRoomCatIDs?.count).flatMap { $0 > 0 ? $0 : nil } ?? (store.snapshot?.cats.count ?? 0)),
                  systemImage: "pawprint.fill")
                .font(.system(size: 13, weight: .heavy, design: .rounded)).padding(.horizontal, 13).padding(.vertical, 9)
                .background(RoomTheme.paper, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 2))
            Spacer(minLength: 8)
            Button { store.beginDecorating() } label: {
                HStack(spacing: 8) {
                    Label(GameStrings.text("layout.edit"), systemImage: "sofa.fill")
                    MacKeyCap(value: preferences.binding(for: .decorate).label)
                }
            }.buttonStyle(MacCompactButtonStyle()).disabled(store.isBusy)
                .accessibilityIdentifier("macDecorate")
        }
    }

    private var stageFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                hint { MacKeyCap(value: preferences.binding(for: .viewLeft).label); MacKeyCap(value: preferences.binding(for: .viewRight).label)
                    Text(GameStrings.text("mac.home.v2.turn")) }
                Spacer(minLength: 8); viewCapsule; Spacer(minLength: 8)
                hint { MacKeyCap(value: GameStrings.text("mac.home.v2.wheelKey")); Text(GameStrings.text("mac.home.v2.zoom"))
                    MacKeyCap(value: preferences.binding(for: .focusCat).label); Text(GameStrings.text("mac.home.v2.closeShort"))
                    MacKeyCap(value: GameStrings.text("mac.home.v2.rightKey")); Text(GameStrings.text("mac.home.v2.menu")) }
            }
            viewCapsule
        }
    }
    private func hint<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 5) { content() }.font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundStyle(RoomTheme.secondary)
            .padding(.horizontal, 10).padding(.vertical, 7).background(.white.opacity(0.72), in: Capsule())
            .fixedSize().accessibilityHidden(true)
    }
    private var viewCapsule: some View {
        let angles: [RoomViewAngle] = [.left, .front, .right]
        let whole = scene.isWholeRoomView
        return HStack(spacing: 10) {
            Button { scene.turnRoomView(by: -1); cameraRevision += 1 } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34).background(RoomTheme.paleMint, in: Circle()) }
                .buttonStyle(.plain).accessibilityLabel(GameStrings.text("mac.command.viewLeft")).accessibilityIdentifier("macViewLeft")
            VStack(spacing: 4) {
                Text(GameStrings.text(scene.roomViewAngle == .front ? "roomView.angle.front" : scene.roomViewAngle == .left ? "roomView.angle.left" : "roomView.angle.right"))
                    .font(.system(size: 14, weight: .heavy, design: .rounded)).fixedSize()
                HStack(spacing: 4) {
                    ForEach(angles, id: \.self) { angle in
                        Capsule().fill(angle == scene.roomViewAngle ? RoomTheme.mint : RoomTheme.track)
                            .frame(width: angle == scene.roomViewAngle ? 16 : 6, height: 6)
                    }
                }.accessibilityHidden(true)
            }.frame(minWidth: 86)
            Button { scene.turnRoomView(by: 1); cameraRevision += 1 } label: { Image(systemName: "chevron.right").frame(width: 34, height: 34).background(RoomTheme.paleMint, in: Circle()) }
                .buttonStyle(.plain).accessibilityLabel(GameStrings.text("mac.command.viewRight")).accessibilityIdentifier("macViewRight")
            Rectangle().fill(RoomTheme.track).frame(width: 1, height: 28)
            Button {
                if whole { scene.showCatCloseUp() } else { scene.showWholeRoom() }
                cameraRevision += 1
            } label: {
                Label(whole ? GameStrings.format("mac.home.v2.closeCat", store.cat.map(GameStrings.catName) ?? "")
                            : GameStrings.text("mac.home.whole"),
                      systemImage: whole ? "plus.magnifyingglass" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 0.64, green: 0.40, blue: 0.16))
                    .padding(.horizontal, 14).padding(.vertical, 9).background(RoomTheme.cream, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier(whole ? "macCloseUp" : "macWholeRoom")
        }.foregroundStyle(RoomTheme.darkMint).padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoomTheme.paper, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 2))
            .compositingGroup().shadow(color: RoomTheme.ink.opacity(0.1), radius: 0, y: 3)
            .fixedSize().id(cameraRevision)
    }

    private func companionSummary(_ cat: CatState) -> String {
        var details = [GameStrings.text("hospital.coat.\(cat.appearance.rawValue)"),
                       GameStrings.text("catGrowth.bond.\(CatBondStage.stage(for: cat.intimacy).rawValue)")]
        if let growth = cat.growthState {
            details.append(CatGrowthPresentation.age(growth.ageDays(at: store.snapshot?.meta.lastSyncAt ?? store.now)))
        }
        return details.joined(separator: " · ")
    }

    private var catCard: some View {
        MacPanel {
            if let cat = store.cat {
                let need = CatNeed.current(in: store)
                HStack(alignment: .top, spacing: 12) {
                    Button { store.inspectCat() } label: {
                        GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 64)
                            .frame(width: 72, height: 72).background(RoomTheme.paleMint.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(RoomTheme.mint, lineWidth: 3))
                    }.buttonStyle(.plain).accessibilityIdentifier("macCatProfile")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GameStrings.text("mac.home.v2.caring")).font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                        Text(GameStrings.catName(cat)).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(companionSummary(cat)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if (store.snapshot?.cats.count ?? 0) > 1 {
                        Button(action: nextCompanion) {
                            HStack(spacing: 5) { Image(systemName: "arrow.triangle.2.circlepath"); Text(GameStrings.text("mac.home.v2.switch"))
                                MacKeyCap(value: preferences.binding(for: .nextCat).label) }
                                .font(.system(size: 12, weight: .heavy)).padding(.horizontal, 9).padding(.vertical, 7)
                                .background(RoomTheme.cream, in: Capsule())
                        }.buttonStyle(.plain).disabled(store.isBusy).accessibilityIdentifier("macSwitchCompanion")
                    } else {
                        Button(action: onCats) { Image(systemName: "person.text.rectangle").padding(8).background(RoomTheme.cream, in: Circle()) }
                            .buttonStyle(.plain).help(GameStrings.text("mac.home.switchCat"))
                    }
                }
                VStack(spacing: 9) {
                    metric("stat.satiety", icon: "fork.knife.circle.fill", value: cat.satiety, color: RoomTheme.gold)
                    metric("stat.cleanliness", icon: "sparkles", value: cat.cleanliness, color: RoomTheme.sky)
                    metric("stat.mood", icon: "face.smiling.inverse", value: cat.mood, color: RoomTheme.friendship)
                    metric("mac.home.energy", icon: "moon.fill", value: cat.energy, color: Color(red: 0.55, green: 0.42, blue: 0.75))
                }
                if cat.healthState?.illness != nil { Button { store.openHospital(catID: cat.id) } label: { Label(GameStrings.text("hospital.healthAlert"), systemImage: "cross.case.fill") }.foregroundStyle(RoomTheme.coral) }
                if let rest = cat.activeRest {
                    HStack {
                        Label(GameStrings.text("mac.home.resting"), systemImage: "moon.zzz.fill")
                        Spacer()
                        Text("\(max(0, Int(rest.endsAt.timeIntervalSince(store.now))))s").monospacedDigit()
                        Button(GameStrings.text("mac.home.wake")) { scene.leaveFurnitureRest() }
                    }.font(.caption)
                }
                HStack(spacing: 8) {
                    care("care.feed", asset: "bowl-full", key: .feed, wanted: need == .food || need == .buyFood, name: GameStrings.catName(cat)) { store.feed() }.accessibilityIdentifier("macFeed")
                    care("care.clean", asset: "icon-clean", key: .clean, wanted: need == .clean, name: GameStrings.catName(cat)) { store.clean() }.accessibilityIdentifier("macClean")
                    care("care.play", asset: "icon-play", key: .play, wanted: need == .play, name: GameStrings.catName(cat)) { store.presentPlayChoices() }.accessibilityIdentifier("macPlay")
                }.disabled(store.isBusy).frame(minHeight: 88).padding(.top, 6)
            }
        }
    }
    private func nextCompanion() {
        guard let cats = store.snapshot?.cats, let index = cats.firstIndex(where: { $0.id == store.cat?.id }), cats.count > 1 else { return }
        Task { _ = await store.selectCompanion(catID: cats[(index + 1) % cats.count].id) }
    }
    private var homeLog: some View {
        MacPanel {
            Label(GameStrings.text("mac.home.v2.log"), systemImage: "clock.arrow.circlepath").font(.system(size: 16, weight: .heavy, design: .rounded))
            if recent.isEmpty { Text(GameStrings.text("mac.home.quiet")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(RoomTheme.secondary) }
            ForEach(recent.suffix(3).reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(entry.age(at: store.now)).font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary).frame(width: 48, alignment: .leading)
                    Text(entry.text).font(.system(size: 12.5, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func metric(_ key: String, icon: String, value: Int, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(color).frame(width: 18)
            Text(GameStrings.text(key)).font(.system(size: 13, weight: .heavy)).frame(width: 44, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.75)
            MacCapsuleProgress(value: Double(value), tint: color)
            Text("\(value)").font(.system(size: 13, weight: .heavy, design: .rounded)).monospacedDigit().frame(width: 28, alignment: .trailing)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.text(key)).accessibilityValue("\(value) / 100")
            .accessibilityIdentifier("macHomeStat_" + key)
    }
    private func care(_ title: String, asset: String, key: MacCommand, wanted: Bool, name: String, action: @escaping () -> Void) -> some View {
        let stock = key == .feed ? store.snapshot?.inventory.food ?? 0
            : key == .clean ? store.snapshot?.inventory.litter ?? 0 : store.snapshot?.inventory.toys ?? 0
        let shape = RoundedRectangle(cornerRadius: 18)
        return Button(action: action) {
            VStack(spacing: 6) {
                GameIcon(asset: asset, symbol: "pawprint.fill", size: 36)
                Text(GameStrings.text(title)).font(.system(size: 14, weight: .heavy))
            }.frame(maxWidth: .infinity).padding(.top, 24).padding(.bottom, 12)
                .background(wanted ? Color(red: 1, green: 0.95, blue: 0.96) : RoomTheme.cream.opacity(0.7), in: shape)
                .overlay(shape.stroke(wanted ? RoomTheme.friendship : .white, lineWidth: wanted ? 3 : 2))
                .overlay(alignment: .topLeading) { MacKeyCap(value: preferences.binding(for: key).label).padding(6) }
                .overlay(alignment: .topTrailing) {
                    Text("×\(stock)").font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(RoomTheme.secondary).padding(8).accessibilityHidden(true)
                }
                .overlay(alignment: .top) {
                    if wanted {
                        Text(GameStrings.format("mac.home.v2.wants", name)).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoomTheme.friendship, in: Capsule()).offset(y: -10)
                    }
                }
                .compositingGroup().shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 3)
                .contentShape(shape)
        }.buttonStyle(.plain).accessibilityLabel(GameStrings.text(title))
            .accessibilityValue(GameStrings.format("shop.owned", stock))
    }
    private var tasks: some View {
        MacPanel {
            let all = (store.snapshot.map { snapshot in GameTaskCatalog.all.filter { $0.category == .daily && GameTaskCatalog.isUnlocked($0, in: snapshot) } }) ?? []
            let done = store.snapshot.map { snapshot in all.filter { GameTaskCatalog.isClaimable($0, in: snapshot) || GameTaskCatalog.isClaimed($0, in: snapshot) }.count } ?? 0
            HStack {
                Label(GameStrings.text("mac.home.tasks"), systemImage: "checklist").font(.system(size: 16, weight: .heavy, design: .rounded))
                Spacer()
                Button(action: onTasks) {
                    HStack(spacing: 4) { Text("\(done) / \(all.count)"); Text(GameStrings.text("mac.home.all")); Image(systemName: "chevron.right") }
                        .font(.system(size: 12.5, weight: .heavy))
                }.buttonStyle(.plain).accessibilityIdentifier("macShowTasks").foregroundStyle(RoomTheme.darkMint)
            }
            if daily.isEmpty { Label(GameStrings.text("mac.home.tasksDone"), systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(RoomTheme.darkMint) }
            if let snapshot = store.snapshot {
                ForEach(daily) { task in
                    let claimable = GameTaskCatalog.isClaimable(task, in: snapshot)
                    HStack(spacing: 10) {
                        Image(systemName: claimable ? "checkmark.circle.fill" : "circle.fill")
                            .font(.system(size: 17)).foregroundStyle(claimable ? RoomTheme.mint : RoomTheme.track)
                        Text(GameStrings.text("task.\(task.id).title")).font(.system(size: 13, weight: .bold))
                            .strikethrough(claimable).foregroundStyle(claimable ? RoomTheme.secondary : RoomTheme.ink)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 6)
                        if claimable {
                            Button { Task { _ = await store.claimTask(id: task.id, expectedDayKey: snapshot.tasks.dailyDayKey) } } label: {
                                Text(GameStrings.text("tasks.claim")).font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 5).background(RoomTheme.gold, in: Capsule())
                            }.buttonStyle(.plain).disabled(store.isBusy)
                        } else {
                            Text("\(min(task.target, GameTaskCatalog.progress(for: task, in: snapshot))) / \(task.target)")
                                .font(.system(size: 12.5, weight: .heavy, design: .rounded)).foregroundStyle(RoomTheme.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

@MainActor
struct MacHomeLogEntry: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let at: Date
    func age(at now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(at) / 60))
        if minutes < 1 { return GameStrings.text("mac.home.v2.justNow") }
        if minutes < 60 { return GameStrings.format("mac.home.v2.minutes", minutes) }
        return GameStrings.format("mac.home.v2.hours", minutes / 60)
    }
}
#endif
