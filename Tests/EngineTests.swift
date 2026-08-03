import XCTest
@testable import Sudoku

final class EngineTests: XCTestCase {

    /// A well-known puzzle (from Wikipedia's Sudoku article) and its unique solution.
    private let knownPuzzle: [Int] = [
        5, 3, 0, 0, 7, 0, 0, 0, 0,
        6, 0, 0, 1, 9, 5, 0, 0, 0,
        0, 9, 8, 0, 0, 0, 0, 6, 0,
        8, 0, 0, 0, 6, 0, 0, 0, 3,
        4, 0, 0, 8, 0, 3, 0, 0, 1,
        7, 0, 0, 0, 2, 0, 0, 0, 6,
        0, 6, 0, 0, 0, 0, 2, 8, 0,
        0, 0, 0, 4, 1, 9, 0, 0, 5,
        0, 0, 0, 0, 8, 0, 0, 7, 9,
    ]

    private func assertValidSolution(_ grid: [Int], file: StaticString = #filePath, line: UInt = #line) {
        for k in 0..<9 {
            let row = Set(grid[k * 9..<(k + 1) * 9])
            let col = Set(stride(from: k, to: 81, by: 9).map { grid[$0] })
            let boxOrigin = (k / 3) * 27 + (k % 3) * 3
            let box = Set([0, 1, 2, 9, 10, 11, 18, 19, 20].map { grid[boxOrigin + $0] })
            XCTAssertEqual(row, Set(1...9), "row \(k)", file: file, line: line)
            XCTAssertEqual(col, Set(1...9), "col \(k)", file: file, line: line)
            XCTAssertEqual(box, Set(1...9), "box \(k)", file: file, line: line)
        }
    }

    func testSolvesKnownPuzzle() throws {
        let solved = try XCTUnwrap(SudokuEngine.solve(knownPuzzle))
        assertValidSolution(solved)
        // Givens must be preserved.
        for i in 0..<81 where knownPuzzle[i] != 0 {
            XCTAssertEqual(solved[i], knownPuzzle[i])
        }
        XCTAssertEqual(solved[2], 4) // first row of the documented solution: 5 3 4 6 7 8 9 1 2
        XCTAssertEqual(solved[8], 2)
    }

    func testUnsolvableGridReturnsNil() {
        var grid = Array(repeating: 0, count: 81)
        grid[0] = 5
        grid[1] = 5 // two 5s in the same row
        XCTAssertFalse(SudokuEngine.hasValidGivens(grid))
        XCTAssertNil(SudokuEngine.solve(grid))
        XCTAssertEqual(SudokuEngine.countSolutions(grid), 0)
        XCTAssertTrue(SudokuEngine.hasValidGivens(knownPuzzle))
    }

    func testCountSolutionsDetectsAmbiguity() {
        // An empty grid has a huge number of solutions; counting is capped at the limit.
        XCTAssertEqual(SudokuEngine.countSolutions(Array(repeating: 0, count: 81), limit: 2), 2)
        XCTAssertEqual(SudokuEngine.countSolutions(knownPuzzle), 1)
    }

    func testGenerationForAllDifficulties() throws {
        for difficulty in Difficulty.allCases {
            let (puzzle, solution) = SudokuEngine.generate(difficulty: difficulty)
            assertValidSolution(solution)
            XCTAssertEqual(puzzle.filter { $0 != 0 }.count, difficulty.targetClues, "\(difficulty) clue count")
            XCTAssertEqual(SudokuEngine.countSolutions(puzzle), 1, "\(difficulty) must have a unique solution")
            // Every clue matches the stored solution.
            for i in 0..<81 where puzzle[i] != 0 {
                XCTAssertEqual(puzzle[i], solution[i])
            }
            XCTAssertEqual(SudokuEngine.solve(puzzle), solution)
        }
    }

    func testCandidatesRespectPeers() {
        var grid = Array(repeating: 0, count: 81)
        grid[0] = 1 // row 0
        grid[10] = 2 // same box as cell 1... (row 1, col 1)
        grid[19] = 3 // col 1 (row 2, col 1)
        let candidates = SudokuEngine.candidates(in: grid, at: 1) // row 0, col 1
        XCTAssertFalse(candidates.contains(1)) // same row
        XCTAssertFalse(candidates.contains(2)) // same box
        XCTAssertFalse(candidates.contains(3)) // same column
        XCTAssertTrue(candidates.contains(4))
        XCTAssertTrue(SudokuEngine.candidates(in: grid, at: 0).isEmpty) // filled cell
    }

    @MainActor
    func testViewModelWinAndErrorTracking() {
        let game = GameViewModel()
        game.newGame(difficulty: .easy)
        // Fill everything from the solution: must win with zero errors.
        for i in 0..<81 where !game.cells[i].isGiven {
            game.select(i)
            game.enter(game.solution[i])
        }
        XCTAssertTrue(game.isWon)
        XCTAssertEqual(game.errorCount, 0)
    }

    @MainActor
    func testViewModelCountsErrors() {
        let game = GameViewModel()
        game.newGame(difficulty: .easy)
        guard let i = (0..<81).first(where: { !game.cells[$0].isGiven }) else {
            return XCTFail("no empty cell")
        }
        game.select(i)
        let wrong = game.solution[i] == 9 ? 1 : game.solution[i] + 1
        game.enter(wrong)
        XCTAssertEqual(game.errorCount, 1)
    }
}
