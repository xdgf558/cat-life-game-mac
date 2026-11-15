import Foundation
import Testing
@testable import CatGameCore

@Suite("2.10 garden puzzles: deterministic, solvable, and checked by replay")
struct OutingPuzzleTests {
    static let seeds: [UInt64] = [1, 7, 42, 2026, 0xDEADBEEF, 9_876_543_210]

    private func puzzles(_ kind: OutingPuzzleKind) -> [OutingPuzzle] {
        Self.seeds.flatMap { seed in (0...2).map { OutingPuzzle(kind: kind, spot: .treeShade, seed: seed, tier: $0, hints: 1) } }
    }

    @Test func boardsComeBackTheSameFromTheSeed() {
        for kind in OutingPuzzleKind.allCases {
            for puzzle in puzzles(kind) { #expect(puzzle.makeBoard() == puzzle.makeBoard()) }
        }
    }

    @Test func plantingHasOneAnswerAndAPerfectRunEarnsThreeStars() {
        for puzzle in puzzles(.planting) {
            var play = OutingPuzzlePlay(puzzle: puzzle)
            guard case .planting(let b) = play.board else { Issue.record("wrong board"); continue }
            #expect(OutingPuzzleGenerator.solutions(solution: b.solution, givens: b.givens) == 1)
            #expect(!play.isSolved)
            for cell in b.solution.indices where play.planted[cell] == nil {
                let applied = play.apply(.place(cell: cell, symbol: b.solution[cell])); #expect(applied)
            }
            #expect(play.isSolved && play.stars == 3)
            #expect(OutingPuzzlePlay.replay(puzzle, moves: play.moves)?.stars == 3)
        }
    }

    @Test func plantingSlipsCostStars() {
        let puzzle = OutingPuzzle(kind: .planting, spot: .flowerBed, seed: 42, tier: 0, hints: 1)
        var play = OutingPuzzlePlay(puzzle: puzzle)
        guard case .planting(let b) = play.board, let cell = play.planted.indices.first(where: { play.planted[$0] == nil })
        else { Issue.record("no empty plot"); return }
        let wrong = (b.solution[cell] + 1) % OutingPlantingBoard.size
        for _ in 0..<3 { let applied = play.apply(.place(cell: cell, symbol: wrong)); #expect(applied) }
        #expect(play.planted[cell] == nil && play.mistakes == 3)
        for index in b.solution.indices where play.planted[index] == nil { play.apply(.place(cell: index, symbol: b.solution[index])) }
        #expect(play.isSolved && play.stars == 1)
    }

    @Test func acornBoardsAreDeducibleAndFlippingEverySafeLeafSolves() {
        for puzzle in puzzles(.acorns) {
            var play = OutingPuzzlePlay(puzzle: puzzle)
            guard case .acorns(let b) = play.board else { Issue.record("wrong board"); continue }
            #expect(b.numbers[b.start] == 0 && !b.acorns.contains(b.start))
            #expect(b.acorns.count == [3, 4, 5][puzzle.tier])
            for cell in 0..<(OutingAcornBoard.size * OutingAcornBoard.size) where !b.acorns.contains(cell) && !play.revealed.contains(cell) {
                let applied = play.apply(.flip(cell: cell)); #expect(applied)
            }
            #expect(play.isSolved && play.stars == 3)
        }
    }

    @Test func everyPebbleLevelIsSolvedInParByTheCatsHints() {
        for (index, level) in OutingPebbleLevels.all.enumerated() {
            let puzzles = Self.seeds.map { OutingPuzzle(kind: .pebbles, spot: .path, seed: $0 &+ UInt64(index), tier: level.tier, hints: 1) }
            for puzzle in puzzles {
                guard case .pebbles(let b) = puzzle.makeBoard() else { Issue.record("wrong board"); continue }
                var cat = b.cat, pebbles = b.pebbles, filled = Set<Int>(), steps = 0
                while cat != b.goal, steps < 80, let direction = OutingPuzzleGenerator.nextPebbleStep(b, cat: cat, pebbles: pebbles, filled: filled),
                      let next = OutingPuzzleGenerator.pebbleStep(b, cat: cat, pebbles: pebbles, filled: filled, direction: direction) {
                    (cat, pebbles, filled) = next; steps += 1
                }
                #expect(cat == b.goal && steps == b.par)
            }
        }
    }

    @Test func pebbleUndoTakesBackOneStep() {
        let puzzle = OutingPuzzle(kind: .pebbles, spot: .path, seed: 2026, tier: 1, hints: 1)
        var play = OutingPuzzlePlay(puzzle: puzzle)
        guard let direction = (0...3).first(where: { var copy = play; return copy.apply(.step(direction: $0)) }) else {
            Issue.record("the cat can't move"); return
        }
        let start = play
        play.apply(.step(direction: direction))
        #expect(play.count == 1)
        #expect(play.withoutLastMove() == start)
    }

    @Test func sunbeamStartsDarkAndTheStoredSolutionLightsTheCushionInPar() {
        for puzzle in puzzles(.sunbeam) {
            var play = OutingPuzzlePlay(puzzle: puzzle)
            guard case .sunbeam(let b) = play.board else { Issue.record("wrong board"); continue }
            #expect(!play.isSolved)
            for cell in b.mirrors.keys.sorted() where play.mirrors[cell] != b.solution[cell] { play.apply(.turn(cell: cell)) }
            #expect(play.isSolved && play.count == b.par && play.stars == 3)
            #expect(play.beamPath.last == b.target)
        }
    }

    @Test func replayRejectsMovesThatBreakTheRulesOrDoNotFinish() {
        let planting = OutingPuzzle(kind: .planting, spot: .flowerBed, seed: 7, tier: 2, hints: 1)
        #expect(OutingPuzzlePlay.replay(planting, moves: [.flip(cell: 0)]) == nil)
        #expect(OutingPuzzlePlay.replay(planting, moves: [.hint, .hint]) == nil)
        #expect(OutingPuzzlePlay.replay(planting, moves: [.hint])?.isSolved == false)
        #expect(OutingPuzzlePlay.replay(planting, moves: Array(repeating: .hint, count: OutingPuzzlePlay.maximumMoves + 1)) == nil)
    }
}
