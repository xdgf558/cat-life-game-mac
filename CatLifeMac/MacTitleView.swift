#if os(macOS)
import AppKit
import SwiftUI
import CatGameCore

@MainActor
struct MacTitleView: View {
    let store: GameStore
    let scene: RoomScene?
    let preferences: MacPreferences
    let hadSave: Bool
    let isActive: Bool
    var lastSeenAt: Date? = nil
    let onContinue: () -> Void
    let onNew: () -> Void
    let onLoad: () -> Void
    let onSettings: () -> Void
    let onQuit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.gameReduceMotionOverride) private var motionOverride
    @State private var previewScene: RoomScene?
    @State private var appIcon: NSImage?
    @State private var appeared = false
    @State private var ambient = false
    @State private var showsLoading = false
    @State private var entering = false
    @State private var entryTask: Task<Void, Never>?
    @State private var selected = MacTitleActionV2.continueGame
    @State private var hovered: MacTitleActionV2?
    @FocusState private var focused: MacTitleActionV2?

    private var reducedMotion: Bool { systemReduceMotion || motionOverride || preferences.reduceMotion }
    private var animated: Bool { !reducedMotion && isActive }
    private var night: Bool { preferences.followDaylight && MacTitleMetricsV2.isNight(at: store.now) }
    private var previewReady: Bool { !store.isLoading && !store.loadFailed && store.snapshot != nil && scene != nil }
    private var previewIdentity: String { store.saveSceneGeneration.uuidString + store.visibleHomeFloor.rawValue + "\(previewReady)" }
    private var actions: [MacTitleActionV2] {
        if store.loadFailed { return [.retry, .load, .settings, .quit] }
        return hadSave ? [.continueGame, .newGame, .load, .settings, .quit] : [.newGame, .load, .settings, .quit]
    }

    private var selection: MacTitleActionV2 { actions.contains(selected) ? selected : actions.first ?? .newGame }

    var body: some View {
        GeometryReader { geometry in
            let layout = MacTitleLayoutV2(size: geometry.size)
            ZStack(alignment: .topLeading) {
                backdrop(size: geometry.size)
                if store.isLoading {
                    if showsLoading { loadingCover.frame(width: geometry.size.width, height: geometry.size.height).transition(.opacity) }
                } else {
                    room(in: layout.room)
                        .opacity(appeared ? 1 : 0).offset(y: appeared || reducedMotion ? 0 : 20)
                    leftWash
                    menu(compact: layout.compact).frame(width: layout.menuWidth, height: layout.menuHeight, alignment: .top)
                        .position(x: layout.menuX + layout.menuWidth / 2, y: layout.menuY + layout.menuHeight / 2)
                        .opacity(entering ? 0 : 1)
                    if hadSave, store.snapshot != nil {
                        clockChip.padding(.top, 26).padding(.trailing, 34).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    footer.padding(.leading, layout.menuX).padding(.trailing, 28).padding(.bottom, 26)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .opacity(entering ? 0 : 1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .foregroundStyle(RoomTheme.ink).fontDesign(.rounded)
        .accessibilityIdentifier("macTitlePage")
        .onAppear { appIcon = NSApp.applicationIconImage }
        .task(id: store.isLoading) { await updateLoadingPresentation() }
        .task(id: previewIdentity) {
            previewScene = previewReady ? RoomScene(size: CGSize(width: 970, height: 780)) : nil
        }
        .onChange(of: hadSave) { _, _ in selectDefaultAction() }
        .onChange(of: focused) { _, action in if let action { selected = action } }
        .onMoveCommand { direction in
            if direction == .up { moveSelection(-1) }
            else if direction == .down { moveSelection(1) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macTitleConfirm)) { _ in perform(selection) }
        .onChange(of: isActive) { _, active in if !active { ambient = false } else { startAmbient() } }
        .onChange(of: reducedMotion) { _, _ in startAmbient() }
        .animation(.easeInOut(duration: reducedMotion ? 0.18 : 0.35), value: entering)
        .onDisappear { entryTask?.cancel(); previewScene = nil }
    }

    private func backdrop(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: night
                ? [Color(red: 0.17, green: 0.19, blue: 0.35), Color(red: 0.30, green: 0.31, blue: 0.53), Color(red: 0.89, green: 0.74, blue: 0.62)]
                : [Color(red: 0.86, green: 0.93, blue: 0.94), Color(red: 0.96, green: 0.94, blue: 0.86), RoomTheme.cream],
                startPoint: .top, endPoint: .bottom)
            if night {
                ForEach(0..<11, id: \.self) { index in
                    Image(systemName: "star.fill").font(.system(size: index.isMultiple(of: 3) ? 4 : 3))
                        .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.80))
                        .opacity(animated ? (ambient ? 0.75 : 0.35) : 0.65)
                        .position(x: size.width * (0.39 + CGFloat(index % 6) * 0.11), y: 55 + CGFloat(index / 6) * 105 + CGFloat(index % 3) * 24)
                }
                Image(systemName: "moon.fill").font(.system(size: 58)).foregroundStyle(Color(red: 1, green: 0.94, blue: 0.76))
                    .shadow(color: .yellow.opacity(0.22), radius: 28).position(x: size.width - 190, y: 158)
            } else {
                ForEach(0..<3, id: \.self) { index in
                    LinearGradient(colors: [Color(red: 1, green: 0.94, blue: 0.75).opacity(0.34), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(width: [90.0, 50, 130][index], height: size.height)
                        .rotationEffect(.degrees(24)).blur(radius: 6)
                        .opacity(animated ? (ambient ? 0.75 : 0.45) : 0.6)
                        .position(x: size.width * (0.45 + CGFloat(index) * 0.09), y: size.height * 0.38)
                        .blendMode(.screen)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    private var leftWash: some View {
        LinearGradient(stops: [.init(color: RoomTheme.cream, location: 0), .init(color: RoomTheme.cream, location: 0.33),
                               .init(color: RoomTheme.cream.opacity(0.86), location: 0.39), .init(color: RoomTheme.cream.opacity(0.55), location: 0.45),
                               .init(color: RoomTheme.cream.opacity(0.22), location: 0.52), .init(color: .clear, location: 0.60)],
                       startPoint: .leading, endPoint: .trailing)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
    private func room(in rect: CGRect) -> some View {
        ZStack {
            if let previewScene, previewReady {
                MacRoomCanvas(store: store, scene: previewScene, isActive: isActive && !entering,
                    readOnlyPreview: true, initialViewAngle: .right, frameLimit: preferences.frameLimit,
                    contextMenus: false, hoverHints: false, isDaylight: !night,
                    usableRect: CGRect(x: 26, y: 26, width: max(1, rect.width - 52), height: max(1, rect.height - 52)))
            }
            if night {
                RadialGradient(colors: [Color(red: 1, green: 0.79, blue: 0.46).opacity(0.20), .clear],
                               center: .center, startRadius: 0, endRadius: rect.width * 0.42)
                    .blendMode(.screen).allowsHitTesting(false)
            }
        }.frame(width: rect.width, height: rect.height)
            .scaleEffect(entering && !reducedMotion ? 1.15 : 1, anchor: .center)
            .position(x: rect.midX, y: rect.midY).allowsHitTesting(false).accessibilityHidden(true)
    }
    private func menu(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            woodenSign(compact: compact).frame(height: compact ? 124 : 154)
                .rotationEffect(.degrees(animated && ambient ? 0.45 : 0), anchor: .top)
                .offset(y: appeared || reducedMotion ? 0 : -14).opacity(appeared ? 1 : 0)
            Spacer().frame(height: compact ? 8 : 16)
            if store.loadFailed {
                loadFailure
            } else if hadSave {
                continueButton(compact: compact)
                newGameButton(compact: compact)
            } else {
                firstGameButton(compact: compact)
            }
            HStack(spacing: 10) {
                utilityButton(.load, symbol: "folder.fill")
                utilityButton(.settings, symbol: "gearshape.fill")
                utilityButton(.quit, symbol: "power")
            }.frame(height: compact ? 46 : 52)
            keyboardHints
            Spacer(minLength: 0)
        }.opacity(appeared ? 1 : 0)
    }
    private func woodenSign(compact: Bool, icon: Bool = true) -> some View {
        Image("wood-plaque").resizable().scaledToFit()
            .overlay {
                HStack(spacing: compact ? 10 : 14) {
                    if icon { applicationIcon(size: compact ? 58 : 70) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(GameStrings.text("mac.title.name")).font(.system(size: compact ? 36 : 42, weight: .heavy, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.65)
                        if icon { Text(GameStrings.text("mac.title.tagline")).font(.system(size: compact ? 12 : 14.5, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8) }
                    }
                }.padding(.leading, icon ? 43 : 38).padding(.trailing, 38).padding(.top, 13)
            }
            .overlay(alignment: .topTrailing) {
                if icon { Image(systemName: "pawprint.fill").font(.system(size: 28)).foregroundStyle(RoomTheme.mint)
                    .rotationEffect(.degrees(18)).shadow(color: .white, radius: 0, y: 2).offset(x: -8, y: 8).accessibilityHidden(true) }
            }
            .shadow(color: RoomTheme.ink.opacity(0.16), radius: 12, y: 9)
            .accessibilityElement(children: .combine)
    }
    private func applicationIcon(size: CGFloat) -> some View {
        Group {
            if let appIcon { Image(nsImage: appIcon).resizable().scaledToFit() }
            else { Image("app-icon-preview").resizable().scaledToFit() }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.25))
            .overlay(RoundedRectangle(cornerRadius: size * 0.25).stroke(.white, lineWidth: 3))
            .accessibilityHidden(true)
    }
    private func continueButton(compact: Bool) -> some View {
        menuButton(.continueGame, primary: true) {
            HStack(spacing: 13) {
                if let cat = store.cat {
                    GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: compact ? 58 : 70)
                        .padding(3).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(GameStrings.text("mac.title.continue"), systemImage: "play.fill")
                        .font(.system(size: compact ? 19 : 22, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 5) { summaryChips }
                        VStack(alignment: .leading, spacing: 4) { summaryChips }
                    }
                    if let lastSeenAt {
                        Text(GameStrings.format("mac.title.v2.lastSeen", MacTitleMetricsV2.lastSeen(lastSeenAt, language: store.language)))
                            .font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                MacKeyCap(value: "↩")
            }.padding(.horizontal, 17).padding(.vertical, 10).frame(minHeight: compact ? 92 : 104)
        }
    }
    @ViewBuilder private var summaryChips: some View {
        if let snapshot = store.snapshot {
            chip(GameStrings.format("mac.title.v2.day", MacTitleMetricsV2.dayNumber(createdAt: snapshot.meta.createdAt, at: max(store.now, snapshot.meta.lastSyncAt))))
            chip(GameStrings.format("career.level", snapshot.player.level))
            chip(GameStrings.format("mac.home.cats", snapshot.cats.count))
        }
    }
    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.horizontal, 8).padding(.vertical, 3).background(.white.opacity(0.20), in: Capsule())
    }
    private func newGameButton(compact: Bool) -> some View {
        menuButton(.newGame) { Label(GameStrings.text("mac.title.new"), systemImage: "plus.circle.fill")
            .font(.system(size: 16, weight: .heavy)).frame(maxWidth: .infinity, minHeight: compact ? 48 : 54) }
    }
    private func firstGameButton(compact: Bool) -> some View {
        menuButton(.newGame, primary: true) {
            HStack(spacing: 14) {
                Image(systemName: "house.fill").font(.system(size: 34))
                VStack(alignment: .leading, spacing: 5) {
                    Text(GameStrings.text("mac.title.new")).font(.system(size: compact ? 21 : 23, weight: .heavy))
                    Text(GameStrings.text("mac.title.v2.firstHint")).font(.system(size: 12, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                MacKeyCap(value: "↩")
            }.padding(.horizontal, 20).frame(minHeight: 92)
        }
    }
    private func utilityButton(_ action: MacTitleActionV2, symbol: String) -> some View {
        menuButton(action) {
            Label(GameStrings.text(action.titleKey), systemImage: symbol).font(.system(size: 14, weight: .heavy))
                .lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private var loadFailure: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(GameStrings.text(store.macRoomRepairFailed ? "mac.room.repairFailed"
                : store.needsNewerVersion ? "save.newerVersionTitle" : "mac.title.loadFailed"), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.coralDeep).fixedSize(horizontal: false, vertical: true)
            menuButton(.retry, primary: true) { Label(GameStrings.text("common.retry"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 44) }
        }.padding(16).background(RoomTheme.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: 20))
    }
    private var keyboardHints: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { selectionHint; confirmHint; settingsHint; quitHint }
            VStack(alignment: .leading, spacing: 6) { HStack(spacing: 6) { selectionHint; confirmHint }; HStack(spacing: 6) { settingsHint; quitHint } }
        }.font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary).padding(.top, 4)
    }
    private var selectionHint: some View { HStack(spacing: 3) { MacKeyCap(value: "↑"); MacKeyCap(value: "↓"); Text(GameStrings.text("mac.title.v2.select")) } }
    private var confirmHint: some View { HStack(spacing: 3) { MacKeyCap(value: "↩"); Text(GameStrings.text("mac.title.v2.confirm")) } }
    private var settingsHint: some View { HStack(spacing: 3) { MacKeyCap(value: preferences.binding(for: .settings).label); Text(GameStrings.text("mac.page.settings")) } }
    private var quitHint: some View { HStack(spacing: 3) { MacKeyCap(value: "⌘Q"); Text(GameStrings.text("mac.title.v2.quit")) } }
    private var clockChip: some View {
        Label {
            Text(MacTitleMetricsV2.clock(at: store.now, home: store.homeDisplayName, language: store.language))
        } icon: {
            Image(systemName: night ? "moon.stars.fill" : "sun.max.fill").foregroundStyle(RoomTheme.gold)
        }
            .font(.system(size: 13, weight: .heavy)).padding(.horizontal, 15).padding(.vertical, 9)
            .background(RoomTheme.paper.opacity(0.94), in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 2))
    }
    private var footer: some View {
        HStack(spacing: 16) {
            Label(GameStrings.text(store.hasSaveFailure ? "mac.save.failed" : "mac.save.steamOffline"),
                  systemImage: store.hasSaveFailure ? "exclamationmark.triangle.fill" : "externaldrive.fill")
            Text(AppVersion.current.localizedDisplay)
            Label(GameStrings.text("mac.title.v2.language"), systemImage: "character.bubble.fill")
        }.font(.system(size: 12, weight: .bold)).foregroundStyle(RoomTheme.secondary)
    }
    private var loadingCover: some View {
        VStack(spacing: 18) {
            applicationIcon(size: 132)
            woodenSign(compact: false, icon: false).frame(width: 400, height: 125)
            HStack(spacing: 14) {
                ForEach(0..<5, id: \.self) { index in
                    Image(systemName: "pawprint.fill").font(.system(size: 26))
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -12 : 8))
                        .foregroundStyle(index < MacTitleMetricsV2.litPaws(progress: store.startupProgress) ? RoomTheme.mint : RoomTheme.secondary.opacity(0.24))
                }
            }.padding(.top, 8).accessibilityElement(children: .ignore)
                .accessibilityLabel(GameStrings.text("mac.title.v2.loading"))
                .accessibilityValue("\(Int(min(1, max(0, store.startupProgress)) * 100))%")
            Text(GameStrings.text("mac.title.v2.loading")).font(.system(size: 14, weight: .bold)).foregroundStyle(RoomTheme.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RadialGradient(colors: [Color(red: 1, green: 0.96, blue: 0.89), Color(red: 0.94, green: 0.89, blue: 0.78)],
                                       center: .center, startRadius: 0, endRadius: 850))
            .accessibilityIdentifier("macTitleLoading")
    }
    private func menuButton<Content: View>(_ action: MacTitleActionV2, primary: Bool = false,
                                          @ViewBuilder content: () -> Content) -> some View {
        let button = Button { perform(action) } label: { content() }
            .buttonStyle(MacTitleButtonStyleV2(primary: primary, selected: selection == action,
                hovered: hovered == action, animated: animated))
            .disabled(store.isBusy || entering)
        return Group {
            if selection == action { button.keyboardShortcut(.defaultAction) } else { button }
        }
        .focused($focused, equals: action)
        .opacity(appeared ? 1 : 0).offset(y: appeared || reducedMotion ? 0 : 6)
        .animation(reducedMotion ? .easeOut(duration: 0.18)
            : .easeOut(duration: 0.3).delay(Double(actions.firstIndex(of: action) ?? 0) * 0.06), value: appeared)
        .onHover { hovering in hovered = hovering ? action : nil }
        .accessibilityIdentifier(action.accessibilityID)
    }
    private func selectDefaultAction() { selected = actions.first ?? .newGame; focused = selected }
    private func moveSelection(_ delta: Int) {
        guard !store.isLoading, !entering, let current = actions.firstIndex(of: selection) else { return }
        let next = min(actions.count - 1, max(0, current + delta))
        selected = actions[next]; focused = selected
    }
    private func perform(_ action: MacTitleActionV2) {
        guard !store.isLoading, !store.isBusy, !entering, actions.contains(action) else { return }
        selected = action
        switch action {
        case .continueGame:
            entering = true
            entryTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(reducedMotion ? 180 : 350)) } catch { return }
                guard !Task.isCancelled else { return }; onContinue()
            }
        case .newGame: onNew()
        case .load: onLoad()
        case .settings: onSettings()
        case .quit: onQuit()
        case .retry: Task { await store.load() }
        }
    }
    private func updateLoadingPresentation() async {
        if store.isLoading {
            showsLoading = false; appeared = false
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard !Task.isCancelled, store.isLoading else { return }
            withAnimation(.easeOut(duration: 0.18)) { showsLoading = true }
        } else {
            showsLoading = false; entering = false; selectDefaultAction()
            withAnimation(.easeOut(duration: reducedMotion ? 0.18 : 0.4)) { appeared = true }
            startAmbient()
        }
    }
    private func startAmbient() {
        ambient = false
        guard animated, !store.isLoading else { return }
        withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { ambient = true }
    }
}

private enum MacTitleActionV2: Hashable {
    case continueGame, newGame, load, settings, quit, retry
    var titleKey: String { switch self {
        case .continueGame: "mac.title.continue"; case .newGame: "mac.title.new"; case .load: "mac.title.load"
        case .settings: "mac.page.settings"; case .quit: "mac.title.quit"; case .retry: "common.retry"
    } }
    var accessibilityID: String { switch self {
        case .continueGame: "macContinue"; case .newGame: "macNewGame"; case .load: "macTitleLoad"
        case .settings: "macTitleSettings"; case .quit: "macTitleQuit"; case .retry: "macTitleRetry"
    } }
}
private struct MacTitleButtonStyleV2: ButtonStyle {
    let primary: Bool
    let selected: Bool
    let hovered: Bool
    let animated: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(primary ? .white : RoomTheme.ink)
            .background(primary ? RoomTheme.mint : RoomTheme.paper.opacity(0.97), in: RoundedRectangle(cornerRadius: primary ? 24 : 18))
            .overlay(RoundedRectangle(cornerRadius: primary ? 24 : 18).stroke(selected ? RoomTheme.mint : .white.opacity(0.85), lineWidth: selected ? 3 : 2))
            .compositingGroup()
            .shadow(color: primary ? RoomTheme.darkMint : RoomTheme.ink.opacity(0.13), radius: 0, y: configuration.isPressed ? 1 : (primary ? 6 : 4))
            .offset(y: hovered && animated ? -2 : 0).opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct MacTitleLayoutV2 {
    let compact: Bool
    let menuX: CGFloat
    let menuY: CGFloat
    let menuWidth: CGFloat
    let menuHeight: CGFloat
    let room: CGRect
    init(size: CGSize) {
        compact = size.width < 1360 || size.height < 800
        menuX = compact ? 52 : 76
        menuY = compact ? 52 : 78
        menuWidth = compact ? 400 : 430
        menuHeight = compact ? 490 : 560
        let roomX: CGFloat = compact ? 420 : 470
        room = CGRect(x: roomX, y: compact ? 40 : 56, width: max(1, size.width - roomX), height: max(1, size.height - (compact ? 66 : 86)))
    }
}
@MainActor
enum MacTitleMetricsV2 {
    static func isNight(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date); return hour >= 19 || hour < 6
    }
    static func dayNumber(createdAt: Date, at date: Date, calendar: Calendar = .current) -> Int {
        max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: createdAt), to: calendar.startOfDay(for: max(createdAt, date))).day ?? 0) + 1)
    }
    static func litPaws(progress: Double) -> Int { progress.isFinite ? Int(ceil(min(1, max(0, progress)) * 5)) : 0 }
    static func lastSeen(_ date: Date, language: GameLanguage) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: language.rawValue)
        formatter.setLocalizedDateFormatFromTemplate("MMMdjm"); return formatter.string(from: date)
    }
    static func clock(at date: Date, home: String, language: GameLanguage) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let period = hour < 6 ? "night" : hour < 12 ? "morning" : hour < 19 ? "afternoon" : "evening"
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: language.rawValue); formatter.dateFormat = "HH:mm"
        return GameStrings.format("mac.title.v2.clock." + period, formatter.string(from: date), home)
    }
}
extension Notification.Name { static let macTitleConfirm = Notification.Name("CatLifeMac.titleConfirm") }
#endif
