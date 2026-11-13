import SwiftUI
import CatGameCore

struct TownMapCanvas: View {
    let width: CGFloat
    let selected: TownPlace
    let layer: TownLayer
    let status: TownMapStatus
    let now: Date
    let night: Bool
    let animates: Bool
    let choose: (TownPlace) -> Void
    private var scale: CGFloat { width / TownMapLayout.size.width }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("town-map-landscape").resizable().scaledToFill()
                .frame(width: TownMapLayout.size.width, height: TownMapLayout.size.height).clipped().accessibilityHidden(true)
            terrain.accessibilityHidden(true)
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !animates)) { context in
                decorations(time: animates ? context.date.timeIntervalSinceReferenceDate : 0)
            }.allowsHitTesting(false).accessibilityHidden(true)
            ForEach(TownMapLayout.readingOrder) { place in
                let frame = TownMapLayout.frame(for: place)
                TownPlot(place: place, selected: selected == place,
                         inLayer: layer == .all || place.layer == layer || place.isEmpty,
                          badge: status.badge(for: place, now: now), badgeTint: status.badgeTint(for: place),
                          showsActivityDot: (place == .board || place == .plaza) && status.hasNewTownActivity,
                          animates: animates) { choose(place) }
                    .position(x: frame.midX, y: frame.midY)
                    .zIndex(selected == place ? 3 : place == .home ? 2 : 1)
                    .accessibilitySortPriority(Double(TownMapLayout.readingOrder.count - (TownMapLayout.readingOrder.firstIndex(of: place) ?? 0)))
            }
            if night { nightLighting.allowsHitTesting(false).accessibilityHidden(true).zIndex(4) }
            // Real one-point layout rows give ScrollViewReader an exact target; positioned artwork can report the whole canvas.
            scrollAnchors
        }
        .frame(width: TownMapLayout.size.width, height: TownMapLayout.size.height).scaleEffect(scale, anchor: .topLeading)
        .frame(width: width, height: TownMapLayout.size.height * scale, alignment: .topLeading)
        .accessibilityElement(children: .contain).accessibilityIdentifier("townMapCanvas").accessibilityValue(animates ? "animated" : "static")
    }

    private var scrollAnchors: some View {
        let places = TownMapLayout.readingOrder.sorted { TownMapLayout.frame(for: $0).midY < TownMapLayout.frame(for: $1).midY }
        return VStack(spacing: 0) {
            ForEach(places.indices, id: \.self) { index in
                let previous = index == 0 ? 0 : TownMapLayout.frame(for: places[index - 1]).midY + 1
                Color.clear.frame(height: max(0, TownMapLayout.frame(for: places[index]).midY - previous))
                Color.clear.frame(height: 1).id(places[index])
            }
        }.frame(width: 1).allowsHitTesting(false).accessibilityHidden(true)
    }

    private var terrain: some View {
        Canvas { context, _ in
            for point in [CGPoint(x: 24, y: 375), CGPoint(x: 363, y: 385), CGPoint(x: 22, y: 550),
                          CGPoint(x: 367, y: 545), CGPoint(x: 25, y: 1215), CGPoint(x: 366, y: 1235),
                          CGPoint(x: 35, y: 1790), CGPoint(x: 350, y: 1780)] {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 23, y: point.y + 20, width: 48, height: 13)), with: .color(RoomTheme.ink.opacity(0.10)))
                context.fill(Path(roundedRect: CGRect(x: point.x - 4, y: point.y, width: 8, height: 26), cornerRadius: 3), with: .color(TownPalette.woodEdge))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 22, y: point.y - 28, width: 44, height: 48)), with: .color(Color(red: 0.30, green: 0.64, blue: 0.39)))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 17, y: point.y - 25, width: 26, height: 32)), with: .color(Color(red: 0.42, green: 0.73, blue: 0.48)))
            }
            for point in [CGPoint(x: 50, y: 1370), CGPoint(x: 345, y: 1375), CGPoint(x: 110, y: 585), CGPoint(x: 284, y: 570)] {
                for offset in [-5.0, 5.0] {
                    context.fill(Path(ellipseIn: CGRect(x: point.x + offset, y: point.y, width: 10, height: 10)), with: .color(RoomTheme.friendship.opacity(0.75)))
                    context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y + offset, width: 10, height: 10)), with: .color(RoomTheme.friendship.opacity(0.75)))
                }
                context.fill(Path(ellipseIn: CGRect(x: point.x + 2, y: point.y + 2, width: 6, height: 6)), with: .color(RoomTheme.wood))
            }
            var river = Path()
            river.move(to: CGPoint(x: -20, y: 430))
            river.addCurve(to: CGPoint(x: 410, y: 450), control1: CGPoint(x: 110, y: 410), control2: CGPoint(x: 240, y: 500))
            context.stroke(river, with: .color(Color(red: 0.41, green: 0.73, blue: 0.86)), lineWidth: 54)
            context.stroke(river, with: .color(.white.opacity(0.42)), style: StrokeStyle(lineWidth: 3, dash: [18, 22]))
            let road = roads()
            context.stroke(road, with: .color(Color(red: 0.85, green: 0.76, blue: 0.61)), style: StrokeStyle(lineWidth: 40, lineCap: .round, lineJoin: .round))
            context.stroke(road, with: .color(Color(red: 0.95, green: 0.89, blue: 0.76)), style: StrokeStyle(lineWidth: 32, lineCap: .round, lineJoin: .round))
            var center = Path()
            center.move(to: CGPoint(x: 205, y: 1380)); center.addLine(to: CGPoint(x: 195, y: 340))
            context.stroke(center, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 14]))
            context.fill(Path(roundedRect: CGRect(x: 168, y: 414, width: 54, height: 92), cornerRadius: 7), with: .color(TownPalette.woodEdge))
            context.fill(Path(roundedRect: CGRect(x: 173, y: 418, width: 44, height: 84), cornerRadius: 4), with: .color(RoomTheme.wood))
            for y in stride(from: 432, through: 488, by: 14) {
                var plank = Path(); plank.move(to: CGPoint(x: 173, y: CGFloat(y))); plank.addLine(to: CGPoint(x: 217, y: CGFloat(y)))
                context.stroke(plank, with: .color(TownPalette.woodEdge), lineWidth: 2)
            }
            for point in [CGPoint(x: 232, y: 330), CGPoint(x: 232, y: 610), CGPoint(x: 160, y: 1380)] {
                context.fill(Path(roundedRect: CGRect(x: point.x - 2, y: point.y, width: 4, height: 33), cornerRadius: 2), with: .color(RoomTheme.ink.opacity(0.7)))
                context.fill(Path(ellipseIn: CGRect(x: point.x - 6, y: point.y - 8, width: 12, height: 12)), with: .color(Color(red: 1, green: 0.9, blue: 0.6)))
            }
        }
    }

    private func roads() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 205, y: 1580)); path.addCurve(to: CGPoint(x: 195, y: 340), control1: CGPoint(x: 187, y: 1100), control2: CGPoint(x: 204, y: 600))
        let branches: [(CGPoint, CGPoint, CGPoint)] = [
            (.init(x: 195, y: 340), .init(x: 150, y: 320), .init(x: 95, y: 300)),
            (.init(x: 195, y: 340), .init(x: 240, y: 320), .init(x: 300, y: 305)),
            (.init(x: 195, y: 700), .init(x: 280, y: 720), .init(x: 312, y: 810)),
            (.init(x: 195, y: 700), .init(x: 110, y: 720), .init(x: 76, y: 810)),
            (.init(x: 195, y: 900), .init(x: 120, y: 930), .init(x: 92, y: 1010)),
            (.init(x: 195, y: 900), .init(x: 280, y: 930), .init(x: 310, y: 1010)),
            (.init(x: 205, y: 1380), .init(x: 120, y: 1400), .init(x: 92, y: 1510)),
            (.init(x: 205, y: 1380), .init(x: 300, y: 1400), .init(x: 325, y: 1510)),
            (.init(x: 205, y: 1580), .init(x: 235, y: 1610), .init(x: 241, y: 1700)),
            (.init(x: 205, y: 1580), .init(x: 110, y: 1610), .init(x: 68, y: 1700))]
        for (start, control, end) in branches { path.move(to: start); path.addQuadCurve(to: end, control: control) }
        return path
    }

    private func decorations(time: TimeInterval) -> some View {
        let phase = time.truncatingRemainder(dividingBy: 22) / 22 * 2 * Double.pi
        let bob = animates ? sin(time * 2 * Double.pi / 1.8) * 3 : 0
        return ZStack(alignment: .topLeading) {
            ForEach(0..<2) { index in
                Image(systemName: "cloud.fill").font(.system(size: index == 0 ? 58 : 42))
                    .foregroundStyle(.white.opacity(0.7))
                    .position(x: animates ? CGFloat((time * 8 + Double(index * 215)).truncatingRemainder(dividingBy: 490) - 50) : CGFloat(80 + index * 220),
                              y: CGFloat(55 + index * 55))
            }
            GameIcon(asset: "cat-avatar", symbol: "cat.fill", size: 29)
                .background(RoomTheme.paper, in: Circle()).overlay(Circle().stroke(.white, lineWidth: 2))
                .position(x: 195, y: CGFloat(580 + 215 * sin(phase)))
            VStack(spacing: 1) {
                Text(GameStrings.text("townMap.youAreHere")).font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3)
                    .background(RoomTheme.mint, in: Capsule()).overlay(Capsule().stroke(.white, lineWidth: 2))
                Circle().fill(RoomTheme.paper).frame(width: 46, height: 46).overlay {
                    if let avatar = status.snapshot?.player.profile.avatarID.flatMap(PlayerCatalog.avatar(id:)) {
                        Image(avatar.assetName).resizable().scaledToFit().frame(width: 85, height: 85).offset(y: 21)
                    } else { Image(systemName: "person.fill").font(.title2).foregroundStyle(RoomTheme.darkMint) }
                }.clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 3))
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 11)).foregroundStyle(.white).offset(y: -3)
            }.position(x: 195, y: CGFloat(1155 + bob))
        }
    }

    private var nightLighting: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.12, green: 0.14, blue: 0.32).opacity(0.40)
            ForEach(TownMapLayout.readingOrder.filter { !$0.isEmpty && !$0.isFuture }) { place in
                let frame = TownMapLayout.frame(for: place)
                Circle().fill(RadialGradient(colors: [Color.yellow.opacity(0.65), .clear], center: .center, startRadius: 0, endRadius: 28))
                    .frame(width: 56, height: 56).position(x: frame.midX, y: frame.minY + frame.width * 0.58)
            }
            ForEach(0..<3) { index in
                let point = [CGPoint(x: 232, y: 330), CGPoint(x: 232, y: 610), CGPoint(x: 160, y: 1380)][index]
                Circle().fill(RadialGradient(colors: [Color.yellow.opacity(0.85), .clear], center: .center, startRadius: 0, endRadius: 22))
                    .frame(width: 44, height: 44).position(point)
            }
            ForEach(0..<6) { index in
                Image(systemName: "sparkle").font(.system(size: 9 + CGFloat(index % 3) * 3))
                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.79))
                    .position(x: CGFloat(35 + index * 61), y: CGFloat(30 + index % 3 * 30))
            }
        }
    }
}
