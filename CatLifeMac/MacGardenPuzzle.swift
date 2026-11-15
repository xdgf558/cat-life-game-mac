import SwiftUI
import CatGameCore

/// 2.10 garden puzzles: the card over the map and its four boards. The card plays on its own
/// `OutingPuzzlePlay`; only the finished move list goes to the engine, which replays it from the
/// puzzle's seed, so the stars shown here are the stars the engine awards. Leaving the garden
/// mid-puzzle keeps the puzzle (same seed, same board) but not the moves made so far.
@MainActor
struct MacOutingPuzzleCard: View {
    let puzzle: OutingPuzzle
    let cat: CatState
    let working: Bool
    let onSolved: ([OutingPuzzleMove]) -> Void
    let onSkip: () -> Void

    @State private var play: OutingPuzzlePlay
    /// Keyboard cursor on grid boards (planting, acorns, sunbeam).
    @State private var cursor = 0
    /// Planting: the seedling a click plants.
    @State private var seedling = 0
    /// Acorns: clicks mark instead of flipping. Marks are only a note for the player.
    @State private var marking = false
    @State private var marks: Set<Int> = []
    /// A wilted seedling or a rolled-away acorn, shown for a moment.
    @State private var flash: Int?
    @FocusState private var focused: Bool
    @Environment(\.gameReduceMotionOverride) private var reduceMotion

    init(puzzle: OutingPuzzle, cat: CatState, working: Bool,
         onSolved: @escaping ([OutingPuzzleMove]) -> Void, onSkip: @escaping () -> Void) {
        self.puzzle = puzzle; self.cat = cat; self.working = working
        self.onSolved = onSolved; self.onSkip = onSkip
        let play = OutingPuzzlePlay(puzzle: puzzle)
        _play = State(initialValue: play)
        if case .acorns(let b) = play.board { _cursor = State(initialValue: b.start) }
    }

    private var kind: OutingPuzzleKind { puzzle.kind }
    private var name: String { GameStrings.catName(cat) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(GameStrings.text(kind.rulesKey)).font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
            targetsRow
            board.frame(maxWidth: .infinity)
            if play.isSolved { solvedPanel } else { toolbar }
            Text(GameStrings.text(play.isSolved ? "outing.puzzle.keys.solved" : "outing.puzzle.\(kind.rawValue).keys"))
                .font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary.opacity(0.8))
                .frame(maxWidth: .infinity)
        }
        .padding(18).frame(width: 540)
        .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white, lineWidth: 3))
        .focusable().focusEffectDisabled().focused($focused)
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear { focused = true }
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("outingPuzzleCard")
    }

    // MARK: Frame

    private var header: some View {
        HStack(spacing: 10) {
            GameIcon(asset: "puzzle-\(kind.rawValue)", symbol: Self.symbol(kind), size: 32, tint: Self.tint(kind))
                .frame(width: 44, height: 44).background(RoomTheme.rewardPaper, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(GameStrings.format("outing.puzzle.kicker", GameStrings.text(puzzle.spot.titleKey)))
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                Text(GameStrings.text(kind.titleKey)).font(.system(size: 18, weight: .heavy))
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                CatCollectionPortrait(appearance: cat.appearance, size: 34)
                Text(GameStrings.format("outing.puzzle.helpLeft", name, play.hintsLeft))
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.friendshipDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 3)
            .background(RoomTheme.friendshipPaper, in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    private var targetsRow: some View {
        let targets = play.starTargets
        return HStack(spacing: 8) {
            chip(GameStrings.format("outing.puzzle.\(kind.rawValue).targets", targets.three, targets.two),
                 tint: RoomTheme.gold, background: RoomTheme.rewardPaper)
            chip(GameStrings.format("outing.puzzle.\(kind.rawValue).counter", play.scored),
                 tint: RoomTheme.darkMint, background: RoomTheme.paleMint)
                .accessibilityIdentifier("outingPuzzleCounter")
            if case .acorns(let b) = play.board {
                chip(GameStrings.format("outing.puzzle.acorns.count", b.acorns.count), tint: RoomTheme.secondary, background: RoomTheme.chipBg)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, tint: Color, background: Color) -> some View {
        Text(text).font(.system(size: 11.5, weight: .heavy)).monospacedDigit().foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4).background(background, in: Capsule())
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: hint) {
                Label(GameStrings.text("outing.puzzle.hint") + "  H", systemImage: "pawprint.fill")
                    .font(.system(size: 12.5, weight: .heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(SoftButtonStyle()).disabled(play.hintsLeft == 0 || working)
            .accessibilityIdentifier("outingPuzzleHint")
            if case .pebbles = play.board {
                Button(action: undo) {
                    Label(GameStrings.text("outing.puzzle.undo") + "  U", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 12.5, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle()).disabled(play.moves.isEmpty || working)
                .accessibilityIdentifier("outingPuzzleUndo")
                Button(action: reset) {
                    Label(GameStrings.text("outing.puzzle.reset") + "  R", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12.5, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle()).disabled(play.moves.isEmpty || working)
                .accessibilityIdentifier("outingPuzzleReset")
            }
            if case .acorns = play.board {
                Button { marking.toggle(); focused = true } label: {
                    Label(GameStrings.text(marking ? "outing.puzzle.marking" : "outing.puzzle.mark") + "  M",
                          systemImage: marking ? "mappin.circle.fill" : "mappin.circle")
                        .font(.system(size: 12.5, weight: .heavy)).frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle()).disabled(working)
                .accessibilityIdentifier("outingPuzzleMark")
            }
            Button(action: onSkip) {
                VStack(spacing: 1) {
                    Text(GameStrings.text("outing.puzzle.skip")).font(.system(size: 12.5, weight: .heavy))
                    Text(GameStrings.text("outing.puzzle.skipHint")).font(.system(size: 10, weight: .semibold)).opacity(0.8)
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain).foregroundStyle(RoomTheme.secondary).disabled(working)
            .accessibilityIdentifier("outingPuzzleSkip")
        }
    }

    private var solvedPanel: some View {
        let stars = play.stars
        return VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: index < stars ? "star.fill" : "star")
                        .font(.system(size: 22, weight: .heavy)).foregroundStyle(RoomTheme.gold)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GameStrings.format("outing.puzzle.starsLabel", stars))
            Text(GameStrings.text("outing.puzzle.solved")).font(.system(size: 16, weight: .heavy))
            Text(GameStrings.format("outing.puzzle.stars.\(stars)", name)).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button(action: finish) {
                Text(GameStrings.text("outing.puzzle.finish") + "  ↩").font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity)
            }
            .buttonStyle(MintButtonStyle()).disabled(working).accessibilityIdentifier("outingPuzzleFinish")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain).accessibilityIdentifier("outingPuzzleSolved")
    }

    // MARK: Moves

    private func apply(_ move: OutingPuzzleMove) {
        guard !working, !play.isSolved else { return }
        var next = play
        guard next.apply(move) else { return }
        let missed = next.mistakes > play.mistakes
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { play = next }
        if missed, case .place(let cell, _) = move { show(flash: cell) }
        if missed, case .flip(let cell) = move { show(flash: cell) }
        focused = true
    }

    private func show(flash cell: Int) {
        flash = cell
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.9 : 0.6))
            if flash == cell { flash = nil }
        }
    }

    private func hint() { apply(.hint) }

    private func undo() {
        guard !working, !play.isSolved, !play.moves.isEmpty else { return }
        play = play.withoutLastMove(); focused = true
    }

    private func reset() {
        guard !working, !play.isSolved else { return }
        play = OutingPuzzlePlay(puzzle: puzzle, board: play.board); focused = true
    }

    private func finish() {
        guard play.isSolved, !working else { return }
        onSolved(play.moves)
    }

    private func handleKey(_ key: KeyPress) -> KeyPress.Result {
        if key.key == .return || key.key == .init("\u{3}") {
            if play.isSolved { finish(); return .handled }
            if case .acorns = play.board { flipOrMark(cursor) } else if case .sunbeam = play.board { apply(.turn(cell: cursor)) }
            return .handled
        }
        guard !play.isSolved, !working else { return .ignored }
        if key.modifiers.contains(.command) {
            if key.characters.lowercased() == "z" { undo(); return .handled }
            return .ignored
        }
        let direction: Int? = switch key.key {
        case .upArrow: 0
        case .rightArrow: 1
        case .downArrow: 2
        case .leftArrow: 3
        default: nil
        }
        let character = key.characters.lowercased()
        if case .pebbles = play.board {
            let wasd = ["w": 0, "d": 1, "s": 2, "a": 3][character]
            if let direction = direction ?? wasd { apply(.step(direction: direction)); return .handled }
            if character == "u" { undo(); return .handled }
            if character == "r" { reset(); return .handled }
        } else if let direction {
            moveCursor(direction); return .handled
        }
        switch character {
        case "h": hint(); return .handled
        case " ":
            if case .acorns = play.board { flipOrMark(cursor) } else if case .sunbeam = play.board { apply(.turn(cell: cursor)) }
            return .handled
        case "m":
            if case .acorns = play.board { toggleMark(cursor); return .handled }
        case "1", "2", "3", "4":
            if case .planting = play.board, let symbol = Int(character) {
                seedling = symbol - 1
                apply(.place(cell: cursor, symbol: symbol - 1))
                return .handled
            }
        default: break
        }
        return .ignored
    }

    private var gridSize: Int {
        switch play.board {
        case .planting: OutingPlantingBoard.size
        case .acorns: OutingAcornBoard.size
        case .sunbeam(let b): b.size
        case .pebbles(let b): b.width
        }
    }

    private func moveCursor(_ direction: Int) {
        let n = gridSize
        var r = cursor / n, c = cursor % n
        switch direction {
        case 0: r = max(0, r - 1)
        case 1: c = min(n - 1, c + 1)
        case 2: r = min(n - 1, r + 1)
        default: c = max(0, c - 1)
        }
        cursor = r * n + c
    }

    private func flipOrMark(_ cell: Int) {
        if marking { toggleMark(cell); return }
        guard !marks.contains(cell) else { return }
        apply(.flip(cell: cell))
    }

    private func toggleMark(_ cell: Int) {
        guard !play.revealed.contains(cell), !play.rolled.contains(cell) else { return }
        if marks.contains(cell) { marks.remove(cell) } else { marks.insert(cell) }
        focused = true
    }

    // MARK: Boards

    @ViewBuilder private var board: some View {
        switch play.board {
        case .planting(let b): plantingBoard(b)
        case .acorns(let b): acornBoard(b)
        case .pebbles(let b): pebbleBoard(b)
        case .sunbeam(let b): sunbeamBoard(b)
        }
    }

    private func cellLabel(_ cell: Int, columns: Int, _ content: String) -> String {
        GameStrings.format("outing.puzzle.cell", cell / columns + 1, cell % columns + 1) + " · " + content
    }

    private func cursorRing(_ cell: Int) -> some View {
        RoundedRectangle(cornerRadius: 10).strokeBorder(cursor == cell && focused ? RoomTheme.darkMint : .clear, lineWidth: 3)
    }

    // 花苗排排种

    private func plantingBoard(_ b: OutingPlantingBoard) -> some View {
        let n = OutingPlantingBoard.size, side: CGFloat = 58
        return VStack(spacing: 10) {
            VStack(spacing: 4) {
                ForEach(0..<n, id: \.self) { r in
                    HStack(spacing: 4) {
                        ForEach(0..<n, id: \.self) { c in plantingCell(r * n + c, b: b, side: side) }
                    }
                }
            }
            .padding(6).background(RoomTheme.wood.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 8) {
                ForEach(0..<n, id: \.self) { symbol in
                    Button { seedling = symbol; focused = true } label: {
                        HStack(spacing: 5) {
                            Text("\(symbol + 1)").font(.system(size: 10.5, weight: .heavy).monospaced()).foregroundStyle(.white)
                                .frame(width: 18, height: 18).background(Self.seedlingTint(symbol), in: Circle())
                            seedlingIcon(symbol, size: 20)
                            Text(GameStrings.text("outing.puzzle.seedling.\(symbol)")).font(.system(size: 11.5, weight: .heavy))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(seedling == symbol ? RoomTheme.paleMint : RoomTheme.cream, in: Capsule())
                        .overlay(Capsule().strokeBorder(seedling == symbol ? RoomTheme.mint : RoomTheme.track, lineWidth: 2))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("outingPuzzleSeedling_\(symbol)")
                    .accessibilityAddTraits(seedling == symbol ? .isSelected : [])
                }
            }
        }
    }

    private func plantingCell(_ cell: Int, b: OutingPlantingBoard, side: CGFloat) -> some View {
        let planted = play.planted[cell]
        let given = b.givens[cell]
        return Button {
            cursor = cell
            if planted == nil { apply(.place(cell: cell, symbol: seedling)) } else { focused = true }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(given ? RoomTheme.cork.opacity(0.75) : RoomTheme.cream)
                if let planted { seedlingIcon(planted, size: side * 0.72) }
                else if flash == cell {
                    GameIcon(asset: "puzzle-wilted", symbol: "leaf.arrow.triangle.circlepath", size: side * 0.62, tint: RoomTheme.coral)
                }
                cursorRing(cell)
            }
            .frame(width: side, height: side)
            .background(flash == cell ? RoomTheme.paleCoral : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).disabled(working || play.isSolved)
        .accessibilityLabel(cellLabel(cell, columns: OutingPlantingBoard.size,
                                      planted.map { GameStrings.text("outing.puzzle.seedling.\($0)") } ?? GameStrings.text("outing.puzzle.a11y.empty")))
        .accessibilityIdentifier("outingPuzzleCell_\(cell)")
    }

    private func seedlingIcon(_ symbol: Int, size: CGFloat) -> some View {
        GameIcon(asset: "puzzle-seedling-\(symbol)", symbol: ["camera.macro", "sun.max.fill", "drop.fill", "leaf.fill"][symbol],
                 size: size, tint: Self.seedlingTint(symbol))
    }

    static func seedlingTint(_ symbol: Int) -> Color {
        [RoomTheme.coral, RoomTheme.gold, RoomTheme.sky, RoomTheme.mint][symbol % 4]
    }

    // 松鼠藏的橡果

    private func acornBoard(_ b: OutingAcornBoard) -> some View {
        let n = OutingAcornBoard.size, side: CGFloat = 50
        return VStack(spacing: 4) {
            ForEach(0..<n, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<n, id: \.self) { c in acornCell(r * n + c, b: b, side: side) }
                }
            }
        }
        .padding(6).background(RoomTheme.wood.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    private func acornCell(_ cell: Int, b: OutingAcornBoard, side: CGFloat) -> some View {
        let revealed = play.revealed.contains(cell)
        let rolled = play.rolled.contains(cell)
        let showAcorn = rolled || (play.isSolved && b.acorns.contains(cell))
        let marked = marks.contains(cell)
        let label: String = if showAcorn { GameStrings.text("outing.puzzle.a11y.acorn") }
            else if revealed { GameStrings.format("outing.puzzle.a11y.near", b.numbers[cell]) }
            else if marked { GameStrings.text("outing.puzzle.a11y.marked") }
            else { GameStrings.text("outing.puzzle.a11y.leaf") }
        return Button {
            cursor = cell
            if !revealed && !rolled { flipOrMark(cell) } else { focused = true }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(revealed || showAcorn ? (rolled ? RoomTheme.paleCoral : RoomTheme.cream) : RoomTheme.cork.opacity(0.55))
                if showAcorn {
                    GameIcon(asset: "puzzle-acorn", symbol: "circle.hexagongrid.fill", size: side * 0.68,
                             tint: rolled ? RoomTheme.coralDeep : RoomTheme.secondary)
                } else if revealed {
                    if b.numbers[cell] > 0 {
                        Text("\(b.numbers[cell])").font(.system(size: 19, weight: .heavy, design: .rounded))
                            .foregroundStyle(Self.numberTint(b.numbers[cell]))
                    }
                } else {
                    GameIcon(asset: "puzzle-leaf", symbol: "leaf.fill", size: side * 0.78, tint: RoomTheme.darkMint)
                    if marked {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(RoomTheme.coralDeep, .white).offset(x: side * 0.24, y: -side * 0.24)
                    }
                }
                cursorRing(cell)
            }
            .frame(width: side, height: side)
            .background(flash == cell ? RoomTheme.paleCoral : .clear, in: RoundedRectangle(cornerRadius: 10))
            .scaleEffect(flash == cell && !reduceMotion ? 1.08 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).disabled(working || play.isSolved)
        .accessibilityLabel(cellLabel(cell, columns: OutingAcornBoard.size, label))
        .accessibilityIdentifier("outingPuzzleCell_\(cell)")
    }

    static func numberTint(_ number: Int) -> Color {
        [RoomTheme.sky, RoomTheme.darkMint, RoomTheme.coral, RoomTheme.lilac][min(3, max(0, number - 1))]
    }

    // 推石过水洼

    private func pebbleBoard(_ b: OutingPebbleBoard) -> some View {
        let side: CGFloat = b.width > 6 ? 42 : 46
        return HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 3) {
                ForEach(0..<b.height, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<b.width, id: \.self) { c in pebbleCell(r * b.width + c, b: b, side: side) }
                    }
                }
            }
            .padding(6).background(RoomTheme.mint.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            directionPad
        }
    }

    private func pebbleCell(_ cell: Int, b: OutingPebbleBoard, side: CGFloat) -> some View {
        let puddle = b.puddles.contains(cell), filled = play.filled.contains(cell)
        let content: String
        let base: Color
        if b.walls.contains(cell) { content = "outing.puzzle.a11y.bush"; base = RoomTheme.paleMint }
        else if puddle && !filled { content = "outing.puzzle.a11y.puddle"; base = RoomTheme.sky.opacity(0.16) }
        else if filled { content = "outing.puzzle.a11y.stone"; base = RoomTheme.cream }
        else { content = "outing.puzzle.a11y.path"; base = RoomTheme.cream }
        var parts = [GameStrings.text(content)]
        if play.pebbles.contains(cell) { parts.append(GameStrings.text("outing.puzzle.a11y.pebble")) }
        if cell == b.goal { parts.append(GameStrings.text("outing.puzzle.a11y.keepsake")) }
        if cell == play.cat { parts.append(GameStrings.catName(cat)) }
        let direction = adjacentDirection(from: play.cat, to: cell, width: b.width)
        return Button {
            if let direction { apply(.step(direction: direction)) } else { focused = true }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(base)
                if b.walls.contains(cell) {
                    GameIcon(asset: "puzzle-bush", symbol: "tree.fill", size: side * 0.9, tint: RoomTheme.darkMint)
                } else if puddle && !filled {
                    GameIcon(asset: "puzzle-puddle", symbol: "drop.fill", size: side * 0.92, tint: RoomTheme.sky)
                } else if filled {
                    GameIcon(asset: "puzzle-stone", symbol: "circle.dashed", size: side * 0.84, tint: RoomTheme.secondary.opacity(0.6))
                }
                if cell == b.goal && cell != play.cat {
                    GameIcon(asset: "puzzle-keepsake", symbol: "gift.fill", size: side * 0.72, tint: RoomTheme.gold)
                }
                if play.pebbles.contains(cell) {
                    GameIcon(asset: "puzzle-pebble", symbol: "circle.fill", size: side * 0.78, tint: Color(white: 0.62))
                }
                if cell == play.cat {
                    CatCollectionPortrait(appearance: cat.appearance, size: side * 0.9)
                }
            }
            .frame(width: side, height: side)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).disabled(working || play.isSolved)
        .accessibilityLabel(cellLabel(cell, columns: b.width, parts.joined(separator: ", ")))
        .accessibilityIdentifier("outingPuzzleCell_\(cell)")
    }

    private func adjacentDirection(from: Int, to: Int, width: Int) -> Int? {
        let fr = from / width, fc = from % width, tr = to / width, tc = to % width
        switch (tr - fr, tc - fc) {
        case (-1, 0): return 0
        case (0, 1): return 1
        case (1, 0): return 2
        case (0, -1): return 3
        default: return nil
        }
    }

    private var directionPad: some View {
        VStack(spacing: 4) {
            padButton(0, "arrow.up")
            HStack(spacing: 4) { padButton(3, "arrow.left"); Color.clear.frame(width: 38, height: 38); padButton(1, "arrow.right") }
            padButton(2, "arrow.down")
        }
    }

    private func padButton(_ direction: Int, _ symbol: String) -> some View {
        Button { apply(.step(direction: direction)) } label: {
            Image(systemName: symbol).font(.system(size: 15, weight: .heavy)).foregroundStyle(RoomTheme.darkMint)
                .frame(width: 38, height: 38).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(RoomTheme.track, lineWidth: 2))
        }
        .buttonStyle(.plain).disabled(working || play.isSolved)
        .accessibilityLabel(GameStrings.text("outing.puzzle.direction.\(direction)"))
        .accessibilityIdentifier("outingPuzzleStep_\(direction)")
    }

    // 光斑引路

    private func sunbeamBoard(_ b: OutingSunbeamBoard) -> some View {
        let n = b.size, side: CGFloat = n > 4 ? 50 : 58, gap: CGFloat = 4
        let span = CGFloat(n) * side + CGFloat(n - 1) * gap
        let path = play.beamPath
        let lit = play.isSolved
        return HStack(spacing: 6) {
            VStack(spacing: gap) {
                ForEach(0..<n, id: \.self) { r in
                    Group {
                        if r == b.sourceRow {
                            GameIcon(asset: "puzzle-sun", symbol: "sun.max.fill", size: 32, tint: RoomTheme.gold)
                                .accessibilityLabel(GameStrings.text("outing.puzzle.a11y.sun"))
                        } else { Color.clear }
                    }
                    .frame(width: 30, height: side)
                }
            }
            ZStack(alignment: .topLeading) {
                VStack(spacing: gap) {
                    ForEach(0..<n, id: \.self) { r in
                        HStack(spacing: gap) {
                            ForEach(0..<n, id: \.self) { c in sunbeamCell(r * n + c, b: b, side: side, lit: lit) }
                        }
                    }
                }
                beamShape(path, b: b, side: side, gap: gap)
                    .stroke(RoomTheme.gold.opacity(lit ? 0.95 : 0.75), style: StrokeStyle(lineWidth: lit ? 7 : 5, lineCap: .round, lineJoin: .round))
                    .shadow(color: RoomTheme.gold.opacity(lit ? 0.8 : 0.35), radius: lit ? 8 : 4)
                    .frame(width: span, height: span)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .frame(width: span, height: span)
            .padding(6).background(RoomTheme.mint.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func sunbeamCell(_ cell: Int, b: OutingSunbeamBoard, side: CGFloat, lit: Bool) -> some View {
        let mirror = play.mirrors[cell]
        let content: String = if cell == b.target { GameStrings.text("outing.puzzle.a11y.cushion") }
            else if b.blocks.contains(cell) { GameStrings.text("outing.puzzle.a11y.bush") }
            else if let mirror { GameStrings.text("outing.puzzle.a11y.mirror.\(mirror)") }
            else { GameStrings.text("outing.puzzle.a11y.path") }
        return Button {
            cursor = cell
            if mirror != nil { apply(.turn(cell: cell)) } else { focused = true }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(b.blocks.contains(cell) ? RoomTheme.paleMint : RoomTheme.cream)
                if cell == b.target {
                    ZStack {
                        Circle().fill(RoomTheme.friendshipPaper).frame(width: side * 0.78, height: side * 0.78)
                            .shadow(color: RoomTheme.gold.opacity(lit ? 0.9 : 0), radius: lit ? 10 : 0)
                        if lit { CatCollectionPortrait(appearance: cat.appearance, size: side * 0.7) }
                        else { GameIcon(asset: "puzzle-cushion", symbol: "pawprint.fill", size: side * 0.72, tint: RoomTheme.friendship) }
                    }
                } else if b.blocks.contains(cell) {
                    GameIcon(asset: "puzzle-bush", symbol: "tree.fill", size: side * 0.88, tint: RoomTheme.darkMint)
                } else if let mirror {
                    Capsule().fill(RoomTheme.mint).frame(width: side * 0.82, height: side * 0.2)
                        .overlay(Capsule().strokeBorder(RoomTheme.darkMint, lineWidth: 2))
                        .rotationEffect(.degrees(mirror == 0 ? -45 : 45))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: mirror)
                }
                cursorRing(cell)
            }
            .frame(width: side, height: side)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain).disabled(working || play.isSolved)
        .accessibilityLabel(cellLabel(cell, columns: b.size, content))
        .accessibilityIdentifier("outingPuzzleCell_\(cell)")
    }

    /// The light from the left edge through each lit cell's centre; past the last cell it runs
    /// half a cell further (off the board, or up to a bush).
    private func beamShape(_ cells: [Int], b: OutingSunbeamBoard, side: CGFloat, gap: CGFloat) -> Path {
        let n = b.size, pitch = side + gap
        func centre(_ cell: Int) -> CGPoint { CGPoint(x: CGFloat(cell % n) * pitch + side / 2, y: CGFloat(cell / n) * pitch + side / 2) }
        var path = Path()
        path.move(to: CGPoint(x: -10, y: CGFloat(b.sourceRow) * pitch + side / 2))
        var direction = 1
        for (index, cell) in cells.enumerated() {
            path.addLine(to: centre(cell))
            if index > 0 {
                let previous = cells[index - 1]
                let dr = cell / n - previous / n, dc = cell % n - previous % n
                direction = dr < 0 ? 0 : dc > 0 ? 1 : dr > 0 ? 2 : 3
            }
            if let orientation = play.mirrors[cell] {
                direction = (orientation == 0 ? [1, 0, 3, 2] : [3, 2, 1, 0])[direction]
            }
        }
        if let last = cells.last, last != b.target, !b.blocks.contains(last) {
            let delta = [(0.0, -1.0), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0)][direction]
            let point = centre(last)
            path.addLine(to: CGPoint(x: point.x + delta.0 * (side / 2 + gap), y: point.y + delta.1 * (side / 2 + gap)))
        }
        return path
    }

    // MARK: Look

    static func symbol(_ kind: OutingPuzzleKind) -> String {
        switch kind {
        case .planting: "camera.macro"
        case .acorns: "leaf.fill"
        case .pebbles: "circle.grid.cross.fill"
        case .sunbeam: "sun.max.fill"
        }
    }

    static func tint(_ kind: OutingPuzzleKind) -> Color {
        switch kind {
        case .planting: RoomTheme.coral
        case .acorns: RoomTheme.darkMint
        case .pebbles: RoomTheme.sky
        case .sunbeam: RoomTheme.gold
        }
    }
}

/// The line above a puzzle step's result: which puzzle, and its stars (or that it was skipped).
struct MacOutingPuzzleBadge: View {
    let kind: OutingPuzzleKind
    let stars: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: MacOutingPuzzleCard.symbol(kind)).font(.system(size: 12, weight: .bold))
                .foregroundStyle(MacOutingPuzzleCard.tint(kind))
            Text(GameStrings.text(kind.titleKey)).font(.system(size: 12, weight: .heavy))
            if stars > 0 {
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < stars ? "star.fill" : "star").font(.system(size: 11, weight: .heavy))
                    }
                }
                .foregroundStyle(RoomTheme.gold)
            } else {
                Text(GameStrings.text("outing.log.puzzleSkipped")).font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4).background(RoomTheme.rewardPaper, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text(kind.titleKey) + " · "
                            + (stars > 0 ? GameStrings.format("outing.puzzle.starsLabel", stars) : GameStrings.text("outing.log.puzzleSkipped")))
        .accessibilityIdentifier("outingPuzzleBadge")
    }
}
