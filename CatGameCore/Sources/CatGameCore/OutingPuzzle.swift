import Foundation

/// 2.10 garden puzzles. A puzzle is only (kind, seed, tier, hints): its board is regenerated from
/// those, so the save stays tiny and a resumed puzzle is exactly the same one. The board UI and
/// the engine share `OutingPuzzlePlay`, so the stars shown are the stars the engine awards.
public enum OutingPuzzleKind: String, Codable, CaseIterable, Sendable {
    /// 花圃 · 花苗排排种: each row and column gets one of each seedling.
    case planting
    /// 树荫 · 松鼠藏的橡果: flip leaves, numbers count nearby acorns.
    case acorns
    /// 小径 · 推石过水洼: push pebbles into puddles to reach the keepsake.
    case pebbles
    /// 树荫 · 光斑引路: turn the leaf mirrors so sunlight reaches the cushion.
    case sunbeam

    public var titleKey: String { "outing.puzzle.\(rawValue).title" }
    public var rulesKey: String { "outing.puzzle.\(rawValue).rules" }
}

public struct OutingPuzzle: Codable, Equatable, Sendable {
    public let kind: OutingPuzzleKind
    public let spot: OutingSpot
    public let seed: UInt64
    /// 0...2, from how many trips the player has taken.
    public let tier: Int
    /// How many times the cat can help (one, two at the cat's favourite spot).
    public let hints: Int

    public init(kind: OutingPuzzleKind, spot: OutingSpot, seed: UInt64, tier: Int, hints: Int) {
        self.kind = kind; self.spot = spot; self.seed = seed; self.tier = tier; self.hints = hints
    }

    var isValid: Bool { (0...2).contains(tier) && (0...3).contains(hints) }
}

public enum OutingPuzzleMove: Codable, Equatable, Sendable {
    case place(cell: Int, symbol: Int)
    case flip(cell: Int)
    /// 0 up, 1 right, 2 down, 3 left.
    case step(direction: Int)
    case turn(cell: Int)
    /// The cat helps: one correct seedling, one safe leaf, the next good step, or one mirror set right.
    case hint
}

// MARK: Boards

public struct OutingPlantingBoard: Equatable, Sendable {
    public static let size = 4
    public let solution: [Int]
    public let givens: [Bool]
}

public struct OutingAcornBoard: Equatable, Sendable {
    public static let size = 5
    public let acorns: Set<Int>
    /// Acorns around each cell (8 neighbours).
    public let numbers: [Int]
    /// The sunny patch already uncovered at the start (flooded from a zero).
    public let start: Int
}

public struct OutingPebbleBoard: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let walls: Set<Int>
    public let puddles: Set<Int>
    public let pebbles: Set<Int>
    public let cat: Int
    public let goal: Int
    public let par: Int
}

public struct OutingSunbeamBoard: Equatable, Sendable {
    public let size: Int
    /// The row where sunlight enters from the left edge.
    public let sourceRow: Int
    public let target: Int
    public let blocks: Set<Int>
    /// Mirror cells and their starting orientation (0 = "/", 1 = "\").
    public let mirrors: [Int: Int]
    /// The fewest-turns solution (orientation per mirror cell).
    public let solution: [Int: Int]
    public let par: Int
}

public enum OutingPuzzleBoard: Equatable, Sendable {
    case planting(OutingPlantingBoard)
    case acorns(OutingAcornBoard)
    case pebbles(OutingPebbleBoard)
    case sunbeam(OutingSunbeamBoard)
}

extension OutingPuzzle {
    public func makeBoard() -> OutingPuzzleBoard {
        var random = OutingRandom(seed: seed, step: 1)
        switch kind {
        case .planting: return .planting(OutingPuzzleGenerator.planting(tier: tier, random: &random))
        case .acorns: return .acorns(OutingPuzzleGenerator.acorns(tier: tier, random: &random))
        case .pebbles: return .pebbles(OutingPuzzleGenerator.pebbles(tier: tier, random: &random))
        case .sunbeam: return .sunbeam(OutingPuzzleGenerator.sunbeam(tier: tier, random: &random))
        }
    }
}

// MARK: Play

/// The live state of a puzzle. The board view applies the player's moves to it; the engine
/// replays the same moves from scratch to check the answer and count the stars.
public struct OutingPuzzlePlay: Equatable, Sendable {
    public let puzzle: OutingPuzzle
    public let board: OutingPuzzleBoard
    public private(set) var moves: [OutingPuzzleMove] = []
    public private(set) var hintsUsed = 0
    /// Planting: wilted seedlings. Acorns: acorns that rolled away.
    public private(set) var mistakes = 0
    /// Pebbles: steps. Sunbeam: turns (the cat's help is free).
    public private(set) var count = 0
    public private(set) var planted: [Int?] = []
    public private(set) var revealed: Set<Int> = []
    public private(set) var rolled: Set<Int> = []
    public private(set) var cat = 0
    public private(set) var pebbles: Set<Int> = []
    public private(set) var filled: Set<Int> = []
    public private(set) var mirrors: [Int: Int] = [:]

    public static let maximumMoves = 400

    public init(puzzle: OutingPuzzle) {
        self.init(puzzle: puzzle, board: puzzle.makeBoard())
    }

    public init(puzzle: OutingPuzzle, board: OutingPuzzleBoard) {
        self.puzzle = puzzle
        self.board = board
        switch board {
        case .planting(let b): planted = b.solution.indices.map { b.givens[$0] ? b.solution[$0] : nil }
        case .acorns(let b): revealed = OutingPuzzleGenerator.flood(from: b.start, board: b, into: [])
        case .pebbles(let b): cat = b.cat; pebbles = b.pebbles
        case .sunbeam(let b): mirrors = b.mirrors
        }
    }

    public var hintsLeft: Int { max(0, puzzle.hints - hintsUsed) }

    public var isSolved: Bool {
        switch board {
        case .planting: return planted.allSatisfy { $0 != nil }
        case .acorns(let b): return revealed.count == OutingAcornBoard.size * OutingAcornBoard.size - b.acorns.count
        case .pebbles(let b): return cat == b.goal
        case .sunbeam(let b): return OutingPuzzleGenerator.beam(b, mirrors: mirrors).reached
        }
    }

    /// The count each star needs: at most `three` for ★★★, at most `two` for ★★.
    public var starTargets: (three: Int, two: Int) {
        switch board {
        case .planting: return (0, 2)
        case .acorns: return (0, 1)
        case .pebbles(let b): return (b.par, b.par + max(3, b.par / 4))
        case .sunbeam(let b): return (b.par, b.par + 2)
        }
    }

    /// What the stars are counted on: mistakes, steps or turns.
    public var scored: Int {
        switch board {
        case .planting, .acorns: return mistakes
        case .pebbles, .sunbeam: return count
        }
    }

    public var stars: Int {
        guard isSolved else { return 0 }
        let targets = starTargets
        return scored <= targets.three ? 3 : scored <= targets.two ? 2 : 1
    }

    /// Applies one move. Returns false (and changes nothing) for a move the rules don't allow.
    @discardableResult
    public mutating func apply(_ move: OutingPuzzleMove) -> Bool {
        guard !isSolved, moves.count < Self.maximumMoves else { return false }
        let applied: Bool
        switch (board, move) {
        case (.planting(let b), .place(let cell, let symbol)): applied = place(cell, symbol, b)
        case (.acorns(let b), .flip(let cell)): applied = flip(cell, b)
        case (.pebbles(let b), .step(let direction)): applied = step(direction, b)
        case (.sunbeam(let b), .turn(let cell)): applied = turn(cell, b)
        case (_, .hint): applied = hint()
        default: applied = false
        }
        if applied { moves.append(move) }
        return applied
    }

    private mutating func place(_ cell: Int, _ symbol: Int, _ b: OutingPlantingBoard) -> Bool {
        guard planted.indices.contains(cell), planted[cell] == nil, (0..<OutingPlantingBoard.size).contains(symbol) else { return false }
        if b.solution[cell] == symbol { planted[cell] = symbol } else { mistakes += 1 }
        return true
    }

    private mutating func flip(_ cell: Int, _ b: OutingAcornBoard) -> Bool {
        let total = OutingAcornBoard.size * OutingAcornBoard.size
        guard (0..<total).contains(cell), !revealed.contains(cell), !rolled.contains(cell) else { return false }
        if b.acorns.contains(cell) { rolled.insert(cell); mistakes += 1 }
        else { revealed = OutingPuzzleGenerator.flood(from: cell, board: b, into: revealed) }
        return true
    }

    private mutating func step(_ direction: Int, _ b: OutingPebbleBoard) -> Bool {
        guard let next = OutingPuzzleGenerator.pebbleStep(b, cat: cat, pebbles: pebbles, filled: filled, direction: direction)
        else { return false }
        (cat, pebbles, filled) = next
        count += 1
        return true
    }

    private mutating func turn(_ cell: Int, _ b: OutingSunbeamBoard) -> Bool {
        guard let orientation = mirrors[cell] else { return false }
        mirrors[cell] = 1 - orientation
        count += 1
        return true
    }

    private mutating func hint() -> Bool {
        guard hintsUsed < puzzle.hints else { return false }
        switch board {
        case .planting(let b):
            guard let cell = planted.indices.first(where: { planted[$0] == nil }) else { return false }
            planted[cell] = b.solution[cell]
        case .acorns(let b):
            let total = OutingAcornBoard.size * OutingAcornBoard.size
            let safe = (0..<total).filter { !b.acorns.contains($0) && !revealed.contains($0) }
            let touching = safe.first { cell in OutingPuzzleGenerator.neighbours(cell, size: OutingAcornBoard.size).contains { revealed.contains($0) } }
            guard let cell = touching ?? safe.first else { return false }
            revealed = OutingPuzzleGenerator.flood(from: cell, board: b, into: revealed)
        case .pebbles(let b):
            guard let direction = OutingPuzzleGenerator.nextPebbleStep(b, cat: cat, pebbles: pebbles, filled: filled),
                  let next = OutingPuzzleGenerator.pebbleStep(b, cat: cat, pebbles: pebbles, filled: filled, direction: direction)
            else { return false }
            (cat, pebbles, filled) = next
            count += 1
        case .sunbeam(let b):
            guard let cell = mirrors.keys.sorted().first(where: { mirrors[$0] != b.solution[$0] }) else { return false }
            mirrors[cell] = b.solution[cell]
        }
        hintsUsed += 1
        return true
    }

    /// Sunbeam: the cells the light passes through right now (for drawing the beam).
    public var beamPath: [Int] {
        guard case .sunbeam(let b) = board else { return [] }
        return OutingPuzzleGenerator.beam(b, mirrors: mirrors).cells
    }

    /// The same puzzle with the last move taken back (pebble undo). Replaying keeps every counter honest.
    public func withoutLastMove() -> OutingPuzzlePlay {
        Self.replay(puzzle, moves: Array(moves.dropLast())) ?? OutingPuzzlePlay(puzzle: puzzle, board: board)
    }

    /// Replays a submitted answer from the start. Nil if any move breaks the rules.
    public static func replay(_ puzzle: OutingPuzzle, moves: [OutingPuzzleMove]) -> OutingPuzzlePlay? {
        guard moves.count <= maximumMoves else { return nil }
        var play = OutingPuzzlePlay(puzzle: puzzle)
        for move in moves { guard play.apply(move) else { return nil } }
        return play
    }
}

// MARK: Generators

enum OutingPuzzleGenerator {
    static func shuffled(_ count: Int, _ random: inout OutingRandom) -> [Int] {
        var items = Array(0..<count)
        guard count > 1 else { return items }
        for index in stride(from: count - 1, to: 0, by: -1) { items.swapAt(index, random.int(0...index)) }
        return items
    }

    static func neighbours(_ cell: Int, size: Int) -> [Int] {
        let row = cell / size, column = cell % size
        var result: [Int] = []
        for dr in -1...1 { for dc in -1...1 where dr != 0 || dc != 0 {
            let r = row + dr, c = column + dc
            if (0..<size).contains(r), (0..<size).contains(c) { result.append(r * size + c) }
        } }
        return result
    }

    // 花苗排排种: a 4×4 Latin square with as few seedlings given as still leaves one answer.
    static func planting(tier: Int, random: inout OutingRandom) -> OutingPlantingBoard {
        let n = OutingPlantingBoard.size
        let klein = random.percent() < 50
        let rows = shuffled(n, &random), columns = shuffled(n, &random), symbols = shuffled(n, &random)
        var solution = [Int](repeating: 0, count: n * n)
        for r in 0..<n { for c in 0..<n {
            let base = klein ? (rows[r] ^ columns[c]) : (rows[r] + columns[c]) % n
            solution[r * n + c] = symbols[base]
        } }
        var givens = [Bool](repeating: true, count: n * n)
        let target = [8, 7, 6][min(2, max(0, tier))]
        for cell in shuffled(n * n, &random) where givens.filter({ $0 }).count > target {
            givens[cell] = false
            if solutions(solution: solution, givens: givens) != 1 { givens[cell] = true }
        }
        return OutingPlantingBoard(solution: solution, givens: givens)
    }

    static func solutions(solution: [Int], givens: [Bool]) -> Int {
        let n = OutingPlantingBoard.size
        var grid: [Int?] = solution.indices.map { givens[$0] ? solution[$0] : nil }
        var found = 0
        func fill(_ cell: Int) {
            if found > 1 { return }
            guard cell < n * n else { found += 1; return }
            if grid[cell] != nil { fill(cell + 1); return }
            let r = cell / n, c = cell % n
            for symbol in 0..<n {
                let clash = (0..<n).contains { grid[r * n + $0] == symbol || grid[$0 * n + c] == symbol }
                if clash { continue }
                grid[cell] = symbol
                fill(cell + 1)
                grid[cell] = nil
            }
        }
        fill(0)
        return found
    }

    // 松鼠藏的橡果: acorns placed so the whole field can be worked out without guessing.
    static func acorns(tier: Int, random: inout OutingRandom) -> OutingAcornBoard {
        let n = OutingAcornBoard.size, total = n * n
        let count = [3, 4, 5][min(2, max(0, tier))]
        var fallback: OutingAcornBoard?
        for _ in 0..<400 {
            let acorns = Set(shuffled(total, &random).prefix(count))
            let numbers = (0..<total).map { cell in neighbours(cell, size: n).filter { acorns.contains($0) }.count }
            let zeros = (0..<total).filter { !acorns.contains($0) && numbers[$0] == 0 }
            guard let start = random.pick(zeros) else { continue }
            let board = OutingAcornBoard(acorns: acorns, numbers: numbers, start: start)
            if fallback == nil { fallback = board }
            if deducible(board) { return board }
        }
        return fallback ?? OutingAcornBoard(acorns: [0, 4, 20], numbers: (0..<total).map { cell in
            neighbours(cell, size: n).filter { [0, 4, 20].contains($0) }.count
        }, start: 12)
    }

    static func flood(from cell: Int, board: OutingAcornBoard, into revealed: Set<Int>) -> Set<Int> {
        var result = revealed
        var queue = [cell]
        while let next = queue.popLast() {
            guard !result.contains(next), !board.acorns.contains(next) else { continue }
            result.insert(next)
            if board.numbers[next] == 0 { queue += neighbours(next, size: OutingAcornBoard.size) }
        }
        return result
    }

    /// Single-cell and subset deductions plus the acorn count: can a careful player finish it?
    static func deducible(_ board: OutingAcornBoard) -> Bool {
        let n = OutingAcornBoard.size, total = n * n
        var revealed = flood(from: board.start, board: board, into: [])
        var known: Set<Int> = []
        var progress = true
        while progress {
            progress = false
            if revealed.count == total - board.acorns.count { return true }
            var constraints: [(cells: Set<Int>, need: Int)] = []
            for cell in revealed where board.numbers[cell] > 0 {
                let around = neighbours(cell, size: n)
                let unknown = Set(around.filter { !revealed.contains($0) && !known.contains($0) })
                guard !unknown.isEmpty else { continue }
                constraints.append((unknown, board.numbers[cell] - around.filter { known.contains($0) }.count))
            }
            let unknownAll = Set((0..<total).filter { !revealed.contains($0) && !known.contains($0) })
            constraints.append((unknownAll, board.acorns.count - known.count))
            var safe: Set<Int> = [], mines: Set<Int> = []
            for c in constraints {
                if c.need == 0 { safe.formUnion(c.cells) }
                if c.need == c.cells.count { mines.formUnion(c.cells) }
            }
            for a in constraints { for b in constraints where a.cells != b.cells && a.cells.isSubset(of: b.cells) {
                let rest = b.cells.subtracting(a.cells), need = b.need - a.need
                if need == 0 { safe.formUnion(rest) }
                if need == rest.count { mines.formUnion(rest) }
            } }
            for cell in safe where !revealed.contains(cell) {
                revealed = flood(from: cell, board: board, into: revealed); progress = true
            }
            for cell in mines where !known.contains(cell) { known.insert(cell); progress = true }
        }
        return revealed.count == total - board.acorns.count
    }

    // 推石过水洼: hand-picked from levels a solver checked offline (`scripts/pebble_levels.py`).
    static func pebbles(tier: Int, random: inout OutingRandom) -> OutingPebbleBoard {
        let pool = OutingPebbleLevels.all.filter { $0.tier == min(2, max(0, tier)) }
        let level = random.pick(pool) ?? OutingPebbleLevels.all[0]
        let width = level.rows[0].count
        var walls: Set<Int> = [], puddles: Set<Int> = [], pebbles: Set<Int> = []
        var cat = 0, goal = 0
        for (r, row) in level.rows.enumerated() { for (c, ch) in row.enumerated() {
            let cell = r * width + c
            switch ch {
            case "#": walls.insert(cell)
            case "~": puddles.insert(cell)
            case "o": pebbles.insert(cell)
            case "C": cat = cell
            case "G": goal = cell
            default: break
            }
        } }
        return OutingPebbleBoard(width: width, height: level.rows.count, walls: walls, puddles: puddles,
                                 pebbles: pebbles, cat: cat, goal: goal, par: level.par)
    }

    static func pebbleStep(_ b: OutingPebbleBoard, cat: Int, pebbles: Set<Int>, filled: Set<Int>,
                           direction: Int) -> (Int, Set<Int>, Set<Int>)? {
        guard (0...3).contains(direction) else { return nil }
        let delta = [(-1, 0), (0, 1), (1, 0), (0, -1)][direction]
        func move(_ cell: Int) -> Int? {
            let r = cell / b.width + delta.0, c = cell % b.width + delta.1
            guard (0..<b.height).contains(r), (0..<b.width).contains(c) else { return nil }
            return r * b.width + c
        }
        guard let target = move(cat), !b.walls.contains(target) else { return nil }
        if b.puddles.contains(target) && !filled.contains(target) { return nil }
        guard pebbles.contains(target) else { return (target, pebbles, filled) }
        guard let beyond = move(target), !b.walls.contains(beyond), !pebbles.contains(beyond) else { return nil }
        var nextPebbles = pebbles, nextFilled = filled
        nextPebbles.remove(target)
        if b.puddles.contains(beyond) && !filled.contains(beyond) { nextFilled.insert(beyond) } else { nextPebbles.insert(beyond) }
        return (target, nextPebbles, nextFilled)
    }

    /// Breadth-first: the first step of a shortest way to the keepsake from here, if there is one.
    static func nextPebbleStep(_ b: OutingPebbleBoard, cat: Int, pebbles: Set<Int>, filled: Set<Int>) -> Int? {
        struct Key: Hashable { let cat: Int; let pebbles: [Int]; let filled: [Int] }
        if cat == b.goal { return nil }
        let start = Key(cat: cat, pebbles: pebbles.sorted(), filled: filled.sorted())
        var first: [Key: Int] = [start: -1]
        var queue = [start], head = 0
        while head < queue.count, first.count < 200_000 {
            let key = queue[head]; head += 1
            for direction in 0...3 {
                guard let next = pebbleStep(b, cat: key.cat, pebbles: Set(key.pebbles), filled: Set(key.filled), direction: direction)
                else { continue }
                let nextKey = Key(cat: next.0, pebbles: next.1.sorted(), filled: next.2.sorted())
                guard first[nextKey] == nil else { continue }
                let origin = key == start ? direction : first[key]!
                if next.0 == b.goal { return origin }
                first[nextKey] = origin
                queue.append(nextKey)
            }
        }
        return nil
    }

    // 光斑引路: a sunbeam path with a few turns, decoy mirrors and bushes, then scrambled.
    /// "/" turns up↔right and down↔left; "\" turns up↔left and down↔right.
    static func reflect(_ direction: Int, orientation: Int) -> Int {
        orientation == 0 ? [1, 0, 3, 2][direction] : [3, 2, 1, 0][direction]
    }

    static func beam(_ b: OutingSunbeamBoard, mirrors: [Int: Int]) -> (cells: [Int], reached: Bool) {
        let n = b.size
        var r = b.sourceRow, c = 0, direction = 1
        var cells: [Int] = []
        for _ in 0..<(n * n * 4) {
            guard (0..<n).contains(r), (0..<n).contains(c) else { return (cells, false) }
            let cell = r * n + c
            cells.append(cell)
            if cell == b.target { return (cells, true) }
            if b.blocks.contains(cell) { return (cells, false) }
            if let orientation = mirrors[cell] { direction = reflect(direction, orientation: orientation) }
            let delta = [(-1, 0), (0, 1), (1, 0), (0, -1)][direction]
            r += delta.0; c += delta.1
        }
        return (cells, false)
    }

    static func sunbeam(tier: Int, random: inout OutingRandom) -> OutingSunbeamBoard {
        let level = min(2, max(0, tier))
        let n = level == 0 ? 4 : 5
        let turns = [2, 3, 4][level], decoys = [1, 2, 3][level], bushes = [0, 1, 2][level]
        for _ in 0..<300 {
            guard let board = sunbeamAttempt(n: n, turns: turns, decoys: decoys, bushes: bushes, random: &random) else { continue }
            return board
        }
        // A plain two-mirror board, always solvable.
        let mirrors = [0 * 4 + 2: 0, 2 * 4 + 2: 1]
        return OutingSunbeamBoard(size: 4, sourceRow: 0, target: 2 * 4 + 3, blocks: [], mirrors: mirrors,
                                  solution: [2: 1, 10: 1], par: 1)
    }

    private static func sunbeamAttempt(n: Int, turns: Int, decoys: Int, bushes: Int,
                                       random: inout OutingRandom) -> OutingSunbeamBoard? {
        let deltas = [(-1, 0), (0, 1), (1, 0), (0, -1)]
        let sourceRow = random.int(0...(n - 1))
        var r = sourceRow, c = 0, direction = 1
        var visited: Set<Int> = [r * n + c]
        var solution: [Int: Int] = [:]
        func advance() -> Bool {
            r += deltas[direction].0; c += deltas[direction].1
            guard (0..<n).contains(r), (0..<n).contains(c), !visited.contains(r * n + c) else { return false }
            visited.insert(r * n + c)
            return true
        }
        for _ in 0..<turns {
            for _ in 0..<random.int(0...2) { guard advance() else { return nil } }
            let next = random.percent() < 50 ? (direction + 1) % 4 : (direction + 3) % 4
            let orientation = reflect(direction, orientation: 0) == next ? 0 : 1
            solution[r * n + c] = orientation
            direction = next
            guard advance() else { return nil }
        }
        for _ in 0..<random.int(0...1) { guard advance() else { return nil } }
        let target = r * n + c
        guard solution[target] == nil else { return nil }
        var free = shuffled(n * n, &random).filter { !visited.contains($0) }
        guard free.count >= decoys + bushes else { return nil }
        var mirrors = solution
        for cell in free.prefix(decoys) { mirrors[cell] = random.int(0...1) }
        free.removeFirst(decoys)
        let blocks = Set(free.prefix(bushes))
        // Scramble until the light misses.
        let cells = mirrors.keys.sorted()
        var start = mirrors
        for _ in 0..<20 {
            for cell in cells { start[cell] = random.int(0...1) }
            let probe = OutingSunbeamBoard(size: n, sourceRow: sourceRow, target: target, blocks: blocks, mirrors: start,
                                           solution: [:], par: 0)
            if !beam(probe, mirrors: start).reached { break }
        }
        let probe = OutingSunbeamBoard(size: n, sourceRow: sourceRow, target: target, blocks: blocks, mirrors: start,
                                       solution: [:], par: 0)
        guard !beam(probe, mirrors: start).reached else { return nil }
        // Fewest turns from the scrambled start (ties: the lowest mask, so every device agrees).
        var best: (turns: Int, config: [Int: Int])?
        for mask in 0..<(1 << cells.count) {
            let turned = mask.nonzeroBitCount
            if let best, turned >= best.turns { continue }
            var config = start
            for (bit, cell) in cells.enumerated() where mask & (1 << bit) != 0 { config[cell] = 1 - start[cell]! }
            if beam(probe, mirrors: config).reached { best = (turned, config) }
        }
        guard let best, best.turns > 0 else { return nil }
        return OutingSunbeamBoard(size: n, sourceRow: sourceRow, target: target, blocks: blocks, mirrors: start,
                                  solution: best.config, par: best.turns)
    }
}
