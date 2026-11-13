import AppKit
import SwiftUI
import CatGameCore

@MainActor
struct MacTownView: View {
    let store: GameStore
    let onEnter: (TownPlace) -> Void
    var preferences: MacPreferences? = nil
    var onNeighbor: ((String) -> Void)? = nil
    @State private var selected: TownPlace = .board
    @State private var layer: TownLayer = .all
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragOrigin: CGSize?
    @State private var magnifyOrigin: CGFloat?
    @State private var inspectedNeighbor: NeighborDefinition?
    private var status: TownMapStatus { TownMapStatus(snapshot: store.snapshot) }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            map.frame(maxWidth: .infinity, maxHeight: .infinity)
            sidebar.frame(width: 325)
        }.font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(RoomTheme.ink)
            .accessibilityElement(children: .contain)
        .accessibilityIdentifier("macTownPage")
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacContentCommand"))) { note in
                guard inspectedNeighbor == nil, let raw = note.object as? String, let command = MacCommand(rawValue: raw) else { return }
                if command == .confirm { enter(selected) }
            }
            .sheet(item: $inspectedNeighbor) { neighbor in
                NavigationStack {
                    NeighborDetailView(store: store, neighborID: neighbor.id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button(GameStrings.text("common.close")) { inspectedNeighbor = nil }
                        } }
                }.frame(width: 640, height: 620)
            }
            .onChange(of: store.saveSceneGeneration) { _, _ in inspectedNeighbor = nil }
    }

    private var map: some View {
        GeometryReader { geometry in
            mapContents(size: geometry.size)
                .background(MacTownWheel69 { delta in
                    let factor = MacRoomPointer.zoomFactor(delta: delta, reversed: preferences?.wheelReversed ?? false)
                    scale = min(2, max(1, scale * factor))
                    offset = MacTownViewport69.clamped(offset, size: geometry.size, scale: scale)
                })
                .clipped()
        }
        .overlay(alignment: .top) { toolbar.padding(14) }
        .overlay(alignment: .bottom) { footer.padding(14) }
        .background(Color(red: 0.76, green: 0.88, blue: 0.71))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.white, lineWidth: 3))
        .accessibilityIdentifier("macTownMap")
    }

    private var toolbar: some View {
        HStack(spacing: 7) {
            ForEach(TownLayer.allCases) { value in
                Button { layer = value } label: {
                    Text(GameStrings.text(value.titleKey)).font(.caption.weight(.heavy))
                        .padding(.horizontal, 13).padding(.vertical, 10)
                        .foregroundStyle(layer == value ? .white : RoomTheme.ink)
                        .background(layer == value ? RoomTheme.mint : RoomTheme.paper, in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("macTownLayer_\(value.rawValue)")
                    .accessibilityAddTraits(layer == value ? .isSelected : [])
            }
            Spacer(minLength: 0)
            TimelineView(.periodic(from: .now, by: 60)) { clock in
                Label {
                    Text(clock.date, format: .dateTime.hour().minute()).monospacedDigit()
                } icon: { Image(systemName: TownMapLayout.isNight(clock.date) ? "moon.stars.fill" : "sun.max.fill") }
                    .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.secondary)
                    .padding(11).background(RoomTheme.paper, in: Capsule())
            }
        }
    }

    private func mapContents(size: CGSize) -> some View {
        ZStack {
            mapGround
            ForEach(TownPlace.allCases) { place in
                let point = MacTownViewport69.position(place)
                marker(place, size: min(size.width * 0.15, size.height * (place.isEmpty ? 0.12 : 0.165)))
                    .position(x: point.x * size.width, y: point.y * size.height)
                    .opacity(layer == .all || layer == place.layer ? 1 : 0.25)
            }
            hereMarker(size: size)
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(scale).offset(offset)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { value in
            if dragOrigin == nil { dragOrigin = offset }
            offset = MacTownViewport69.clamped(CGSize(width: (dragOrigin?.width ?? 0) + value.translation.width,
                height: (dragOrigin?.height ?? 0) + value.translation.height), size: size, scale: scale)
        }.onEnded { _ in dragOrigin = nil })
        .simultaneousGesture(MagnifyGesture().onChanged { value in
            if magnifyOrigin == nil { magnifyOrigin = scale }
            scale = min(2, max(1, (magnifyOrigin ?? 1) * value.magnification))
            offset = MacTownViewport69.clamped(offset, size: size, scale: scale)
        }.onEnded { _ in magnifyOrigin = nil })
    }

    /// A painted town map: grass with soft patches, a winding river, sandy paths that meet at each
    /// building's name plaque, a plank bridge, the plaza paving and trees between the blocks.
    private var mapGround: some View {
        Canvas { context, size in
            let w = size.width, h = size.height, unit = min(w, h)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            var seed: UInt64 = 0x5EED_CA75
            func random() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1) }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.80, green: 0.91, blue: 0.80), Color(red: 0.74, green: 0.87, blue: 0.68), Color(red: 0.71, green: 0.85, blue: 0.64)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            for _ in 0..<26 {   // meadow patches
                let c = p(random(), random()), rw = unit * (0.08 + random() * 0.14)
                context.fill(Path(ellipseIn: CGRect(x: c.x - rw, y: c.y - rw * 0.55, width: rw * 2, height: rw * 1.1)),
                             with: .color(Color(red: 0.86, green: 0.94, blue: 0.80).opacity(0.45)))
            }
            for _ in 0..<90 {   // grass tufts and tiny flowers
                let c = p(random(), random()), r = unit * 0.004
                let palette = [Color(red: 0.55, green: 0.74, blue: 0.50), .white, Color(red: 0.98, green: 0.78, blue: 0.83), Color(red: 1, green: 0.88, blue: 0.5)]
                context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .color(palette[Int(random() * 4) % 4].opacity(0.8)))
            }

            var river = Path()
            river.move(to: p(-0.03, 0.26))
            river.addCurve(to: p(0.5, 0.30), control1: p(0.14, 0.35), control2: p(0.33, 0.24))
            river.addCurve(to: p(1.03, 0.28), control1: p(0.67, 0.36), control2: p(0.86, 0.23))
            let riverWidth = h * 0.085
            context.stroke(river, with: .color(Color(red: 0.93, green: 0.89, blue: 0.74)), style: StrokeStyle(lineWidth: riverWidth + unit * 0.03, lineCap: .round))
            context.stroke(river, with: .color(Color(red: 0.60, green: 0.80, blue: 0.91)), style: StrokeStyle(lineWidth: riverWidth, lineCap: .round))
            context.stroke(river, with: .color(Color(red: 0.72, green: 0.87, blue: 0.95)), style: StrokeStyle(lineWidth: riverWidth * 0.55, lineCap: .round))
            context.stroke(river, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [unit * 0.035, unit * 0.06]))

            var roads = Path()
            roads.move(to: p(0.07, 0.205)); roads.addCurve(to: p(0.93, 0.205), control1: p(0.35, 0.23), control2: p(0.65, 0.18))
            roads.move(to: p(0.52, 0.20)); roads.addCurve(to: p(0.52, 0.52), control1: p(0.50, 0.32), control2: p(0.54, 0.42))
            roads.move(to: p(0.08, 0.525)); roads.addCurve(to: p(0.93, 0.535), control1: p(0.33, 0.56), control2: p(0.66, 0.50))
            roads.move(to: p(0.52, 0.53)); roads.addCurve(to: p(0.52, 0.785), control1: p(0.55, 0.61), control2: p(0.49, 0.70))
            roads.move(to: p(0.04, 0.785)); roads.addCurve(to: p(0.97, 0.79), control1: p(0.30, 0.76), control2: p(0.70, 0.82))
                        for (a, b) in [((0.36, 0.78), (0.36, 0.86)), ((0.665, 0.795), (0.665, 0.87)), ((0.945, 0.79), (0.945, 0.87)),
                           ((0.24, 0.53), (0.16, 0.785)), ((0.80, 0.54), (0.80, 0.785))] {
                roads.move(to: p(a.0, a.1)); roads.addQuadCurve(to: p(b.0, b.1), control: p((a.0 + b.0) / 2 + 0.02, (a.1 + b.1) / 2))
            }
            let road = unit * 0.045
            context.stroke(roads, with: .color(TownPalette.woodEdge.opacity(0.28)), style: StrokeStyle(lineWidth: road + 6, lineCap: .round, lineJoin: .round))
            context.stroke(roads, with: .color(Color(red: 0.95, green: 0.90, blue: 0.78)), style: StrokeStyle(lineWidth: road, lineCap: .round, lineJoin: .round))
            context.stroke(roads, with: .color(TownPalette.woodEdge.opacity(0.18)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 9]))

            // Plank bridge where the main path crosses the river.
            let bridgeCenter = p(0.515, 0.297), bw = road * 1.7, bh = riverWidth + unit * 0.05
            let bridge = CGRect(x: bridgeCenter.x - bw / 2, y: bridgeCenter.y - bh / 2, width: bw, height: bh)
            context.fill(Path(roundedRect: bridge.offsetBy(dx: 0, dy: 4), cornerRadius: 7), with: .color(.black.opacity(0.12)))
            context.fill(Path(roundedRect: bridge, cornerRadius: 7), with: .color(Color(red: 0.80, green: 0.58, blue: 0.36)))
            for row in stride(from: bridge.minY + 6, to: bridge.maxY - 4, by: 8) {
                var plank = Path(); plank.move(to: CGPoint(x: bridge.minX + 3, y: row)); plank.addLine(to: CGPoint(x: bridge.maxX - 3, y: row))
                context.stroke(plank, with: .color(Color(red: 0.62, green: 0.42, blue: 0.24).opacity(0.7)), lineWidth: 1.5)
            }
            for x in [bridge.minX, bridge.maxX] {
                var rail = Path(); rail.move(to: CGPoint(x: x, y: bridge.minY - 2)); rail.addLine(to: CGPoint(x: x, y: bridge.maxY + 2))
                context.stroke(rail, with: .color(Color(red: 0.55, green: 0.36, blue: 0.2)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }

            // Paved plaza circle under the central plaza.
            let plaza = p(0.52, 0.45), pr = unit * 0.13
            context.fill(Path(ellipseIn: CGRect(x: plaza.x - pr, y: plaza.y - pr * 0.55, width: pr * 2, height: pr * 1.1)),
                         with: .color(Color(red: 0.94, green: 0.90, blue: 0.82)))
            context.stroke(Path(ellipseIn: CGRect(x: plaza.x - pr, y: plaza.y - pr * 0.55, width: pr * 2, height: pr * 1.1)),
                           with: .color(TownPalette.woodEdge.opacity(0.25)), lineWidth: 2)
            for index in 0..<14 {
                let a = CGFloat(index) / 14 * .pi * 2
                let c = CGPoint(x: plaza.x + cos(a) * pr * 0.8, y: plaza.y + sin(a) * pr * 0.44)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 2, width: 6, height: 4)), with: .color(TownPalette.woodEdge.opacity(0.18)))
            }

            // Trees between the blocks (canopy, highlight, trunk, contact shadow).
            let trees: [(CGFloat, CGFloat, CGFloat)] = [(0.05, 0.08, 1), (0.37, 0.07, 0.9), (0.67, 0.06, 1), (0.95, 0.10, 1.1),
                (0.035, 0.40, 1), (0.38, 0.41, 0.85), (0.66, 0.40, 0.9), (0.965, 0.42, 1), (0.12, 0.35, 0.75), (0.91, 0.36, 0.8),
                (0.04, 0.62, 1), (0.36, 0.62, 0.9), (0.665, 0.62, 0.95), (0.965, 0.64, 1), (0.03, 0.88, 1.0), (0.47, 0.86, 0.8),
                (0.56, 0.87, 0.75), (0.80, 0.86, 0.85), (0.23, 0.87, 0.8)]
            for (x, y, scale) in trees {
                let c = p(x, y), r = unit * 0.028 * scale
                context.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.1, y: c.y + r * 1.1, width: r * 2.2, height: r * 0.7)), with: .color(.black.opacity(0.10)))
                context.fill(Path(CGRect(x: c.x - r * 0.18, y: c.y + r * 0.3, width: r * 0.36, height: r * 1.0)), with: .color(Color(red: 0.55, green: 0.38, blue: 0.24)))
                for (dx, dy, k) in [(-0.45, 0.1, 0.75), (0.45, 0.1, 0.75), (0, -0.25, 0.9)] as [(CGFloat, CGFloat, CGFloat)] {
                    let rr = r * k
                    context.fill(Path(ellipseIn: CGRect(x: c.x + dx * r - rr, y: c.y + dy * r - rr, width: rr * 2, height: rr * 2)),
                                 with: .color(Color(red: 0.43, green: 0.68, blue: 0.42)))
                }
                context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.85, width: r * 0.7, height: r * 0.55)),
                             with: .color(Color(red: 0.66, green: 0.84, blue: 0.56).opacity(0.9)))
            }
            if TownMapLayout.isNight(store.now) {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.25, green: 0.24, blue: 0.48).opacity(0.10)))
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }

    private func hereMarker(size: CGSize) -> some View {
        let avatar = store.snapshot?.player.profile.avatarID.flatMap(PlayerCatalog.avatar(id:))?.assetName ?? "app-icon-preview"
        let point = MacTownViewport69.position(.home)
        return VStack(spacing: 3) {
            Text(GameStrings.text("mac.town.v2.here")).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3).background(RoomTheme.mint, in: Capsule())
                .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
            GameIcon(asset: avatar, symbol: "person.crop.circle.fill", size: 40)
                .frame(width: 46, height: 46).background(RoomTheme.paper, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 3)).compositingGroup().shadow(color: .black.opacity(0.15), radius: 0, y: 3)
        }.position(x: (point.x + 0.09) * size.width, y: (point.y - 0.03) * size.height)
            .allowsHitTesting(false).accessibilityHidden(true)
    }

    private func marker(_ place: TownPlace, size: CGFloat) -> some View {
        Button { selected = place } label: {
            VStack(spacing: 1) {
                GameIcon(asset: place.asset, symbol: place.symbol, size: size, tint: place.tint)
                    .opacity(place.isFuture ? 0.65 : 1)
                    .background {
                        if selected == place { Ellipse().fill(RoomTheme.gold.opacity(0.22)).frame(width: size * 1.1, height: size * 0.4).offset(y: size * 0.3) }
                    }
                Text(GameStrings.text(place.titleKey)).font(.system(size: 12, weight: .heavy)).padding(.horizontal, 11).padding(.vertical, 6)
                    .foregroundStyle(RoomTheme.ink).background(selected == place ? RoomTheme.wood : RoomTheme.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(selected == place ? RoomTheme.gold : .white, lineWidth: 2))
            }
            .overlay(alignment: .topTrailing) {
                if let badge = status.badge(for: place, now: store.now) {
                    Text(badge).font(.system(size: 9, weight: .heavy)).padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(.white).background(status.badgeTint(for: place), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 2)).offset(x: 15, y: -8)
                }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).simultaneousGesture(TapGesture(count: 2).onEnded { enter(place) })
            .help(preferences?.hoverHints == false ? "" : GameStrings.text("mac.town.placeHint"))
            .accessibilityLabel(GameStrings.text(place.titleKey))
            .accessibilityValue(status.badge(for: place, now: store.now) ?? GameStrings.text(place.statusKey(sickCount: status.sickCount)))
            .accessibilityIdentifier("macTownPlace_\(place.rawValue)")
            .accessibilityAddTraits(selected == place ? .isSelected : [])
            .accessibilityAction(named: Text(GameStrings.text(place.actionKey))) { enter(place) }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                ForEach([("mac.town.v2.click", "mac.town.v2.view"), ("mac.town.v2.double", "mac.town.v2.enter"),
                         ("mac.town.v2.drag", "mac.town.v2.pan"), ("mac.home.v2.wheelKey", "mac.home.v2.zoom")], id: \.0) { key, label in
                    HStack(spacing: 4) { MacKeyCap(value: GameStrings.text(key)); Text(GameStrings.text(label)) }
                }
            }.font(.system(size: 11.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .padding(.horizontal, 10).padding(.vertical, 7).background(RoomTheme.paper.opacity(0.9), in: Capsule())
                .fixedSize().accessibilityHidden(true)
            Spacer(minLength: 0)
            Button { selected = .home; scale = 1; offset = .zero; enter(.home) } label: {
                HStack(spacing: 6) { Image(systemName: "house.fill"); Text(GameStrings.text("town.goHome")); MacKeyCap(value: keyLabel(.returnHome)) }
            }.buttonStyle(MacCompactButtonStyle()).accessibilityIdentifier("macTownHome")
            Button { scale = 1; offset = .zero } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(MacCompactButtonStyle())
                .accessibilityLabel(GameStrings.text("mac.town.resetMap")).help(GameStrings.text("mac.town.resetMap"))
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 14) {
                placeDetail
                neighbors
            }
        }
    }

    private var placeDetail: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 15) {
                GameIcon(asset: selected.asset, symbol: selected.symbol, size: 72, tint: selected.tint)
                    .padding(8).background(selected.tile, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 8) {
                    Text(GameStrings.text(selected.titleKey)).font(.system(size: 24, weight: .heavy)).accessibilityIdentifier("macTownDetailTitle")
                    Text(status.badge(for: selected, now: store.now) ?? GameStrings.text(selected.statusKey(sickCount: status.sickCount)))
                        .font(.caption.weight(.bold)).foregroundStyle(status.badgeTint(for: selected))
                }
            }
            Text(selected == .home ? GameStrings.format("town.homeDescription", store.homeDisplayName) : GameStrings.text(selected.descriptionKey))
                .font(.subheadline).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            if selected == .board || selected == .plaza { eventSummary }
            Button { enter(selected) } label: {
                Label(GameStrings.text(selected.actionKey) + "  " + keyLabel(.confirm), systemImage: selected.symbol).frame(maxWidth: .infinity)
            }.buttonStyle(MintButtonStyle()).disabled(selected.isFuture || selected.isEmpty || store.isBusy)
                .accessibilityIdentifier("macTownEnter")
        }.macContentCard69()
    }

    @ViewBuilder private var eventSummary: some View {
        if let state = store.snapshot {
            if let event = TownEventCatalog.current(in: state) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(GameStrings.format("townEvents.letterFrom", TownEventPresentation.sender(event.neighborID)))
                        .font(.caption).foregroundStyle(RoomTheme.coralDeep)
                    Text(GameStrings.text(event.titleKey)).font(.headline)
                    Text(GameStrings.text(state.community.events.todayReceipt == nil ? "townEvents.available" : "townEvents.completed"))
                        .font(.caption).foregroundStyle(RoomTheme.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoomTheme.letterPaper, in: RoundedRectangle(cornerRadius: 16))
            }
            if let milestone = TownEventCatalog.milestones.first {
                VStack(alignment: .leading, spacing: 7) {
                    Text(GameStrings.format("townEvents.progress", state.community.events.totalCompleted, milestone.target)).font(.caption).foregroundStyle(RoomTheme.friendshipDeep)
                    ProgressView(value: Double(min(state.community.events.totalCompleted, milestone.target)), total: Double(milestone.target)).tint(RoomTheme.friendship)
                }
            }
        }
    }

    private var neighbors: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(GameStrings.text("community.title"), systemImage: "person.2.fill").font(.headline)
                Spacer(minLength: 0)
                Text(GameStrings.format("townMap.visitCount", status.unvisitedNeighbors.count)).font(.caption).foregroundStyle(RoomTheme.secondary)
            }
            ForEach(CommunityCatalog.neighbors) { neighbor in neighborRow(neighbor) }
        }.macContentCard69()
    }

    private func neighborRow(_ neighbor: NeighborDefinition) -> some View {
        let relation = store.snapshot?.community.relationship(for: neighbor.id) ?? NeighborRelationship()
        return Button { if let onNeighbor { onNeighbor(neighbor.id) } else { inspectedNeighbor = neighbor } } label: {
            HStack(spacing: 10) {
                CommunityPortrait(neighbor: neighbor, size: 44).overlay(alignment: .topTrailing) {
                    if !relation.visitedToday { Circle().fill(RoomTheme.mint).frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 2)) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(GameStrings.text(neighbor.nameKey)).font(.headline)
                        Text(GameStrings.text(relation.stage.nameKey)).font(.caption).foregroundStyle(CommunityPalette.tint(neighbor))
                        Spacer(minLength: 0)
                        Text("\(relation.friendship)").font(.caption).foregroundStyle(RoomTheme.secondary)
                    }
                    ProgressView(value: Double(relation.friendship), total: 100).tint(RoomTheme.friendship)
                }.frame(maxWidth: .infinity)
            }.padding(.vertical, 5).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("macNeighbor_\(neighbor.id)")
            .accessibilityHint(GameStrings.text("mac.town.neighborHint"))
    }

    private func keyLabel(_ command: MacCommand) -> String { (preferences?.binding(for: command) ?? command.defaultBinding).label }

    private func enter(_ place: TownPlace) {
        guard !store.isBusy, !place.isFuture, !place.isEmpty else { return }
        selected = place
        onEnter(place)
    }
}

/// Map pan never changes game state or persists a presentation coordinate.
enum MacTownViewport69 {
    static func clamped(_ offset: CGSize, size: CGSize, scale: CGFloat) -> CGSize {
        let x = max(0, size.width * (scale - 1) / 2)
        let y = max(0, size.height * (scale - 1) / 2)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }
    static func position(_ place: TownPlace) -> CGPoint {
        switch place {
        case .work: CGPoint(x: 0.24, y: 0.12)
        case .cafe: CGPoint(x: 0.52, y: 0.125)
        case .shop: CGPoint(x: 0.79, y: 0.12)
        case .board: CGPoint(x: 0.24, y: 0.44)
        case .plaza: CGPoint(x: 0.52, y: 0.43)
        case .market: CGPoint(x: 0.8, y: 0.445)
        case .street: CGPoint(x: 0.16, y: 0.7)
        case .home: CGPoint(x: 0.52, y: 0.7)
        case .hospital: CGPoint(x: 0.8, y: 0.7)
        case .adoption: CGPoint(x: 0.36, y: 0.815)
        case .lot1: CGPoint(x: 0.665, y: 0.83)
        case .lot2: CGPoint(x: 0.945, y: 0.83)
        }
    }
}

/// Observe wheel events inside the map while leaving native SwiftUI buttons clickable.
private struct MacTownWheel69: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.onScroll = onScroll
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak coordinator = context.coordinator] event in
            let handled = MainActor.assumeIsolated {
                guard let coordinator, let view = coordinator.view, let window = view.window,
                      event.window === window, view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return false }
                coordinator.onScroll?(event.scrollingDeltaY)
                return true
            }
            return handled ? nil : event
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onScroll = onScroll }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var onScroll: ((CGFloat) -> Void)?
        var monitor: Any?
    }
}
