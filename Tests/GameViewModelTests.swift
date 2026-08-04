import XCTest
@testable import Sudoku

@MainActor
final class GameViewModelTests: XCTestCase {

    /// Fresh, isolated UserDefaults so tests never touch the player's real data.
    private func freshDefaults() -> UserDefaults {
        let name = "GameViewModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func firstEmptyCell(of game: GameViewModel) throws -> Int {
        try XCTUnwrap((0..<81).first { !game.cells[$0].isGiven })
    }

    func testUndoRedoRoundTrip() throws {
        let game = GameViewModel(defaults: freshDefaults())
        let i = try firstEmptyCell(of: game)
        XCTAssertFalse(game.canUndo)

        game.select(i)
        game.enter(game.solution[i])
        XCTAssertTrue(game.canUndo)
        XCTAssertFalse(game.canRedo)

        game.undo()
        XCTAssertEqual(game.cells[i].value, 0)
        XCTAssertTrue(game.canRedo)

        game.redo()
        XCTAssertEqual(game.cells[i].value, game.solution[i])
        XCTAssertFalse(game.canRedo)
    }

    func testNewMoveClearsRedoBranch() throws {
        let game = GameViewModel(defaults: freshDefaults())
        let i = try firstEmptyCell(of: game)
        game.select(i)
        game.enter(game.solution[i])
        game.undo()
        game.enter(game.solution[i])
        XCTAssertFalse(game.canRedo)
    }

    func testSaveAndRestoreAcrossInstances() throws {
        let defaults = freshDefaults()
        let first = GameViewModel(defaults: defaults)
        let i = try firstEmptyCell(of: first)
        first.select(i)
        first.enter(first.solution[i])

        let second = GameViewModel(defaults: defaults)
        XCTAssertEqual(second.cells, first.cells)
        XCTAssertEqual(second.solution, first.solution)
        XCTAssertEqual(second.difficulty, first.difficulty)
        XCTAssertEqual(second.errorCount, first.errorCount)
    }

    func testWinRecordsStatsAndClearsSave() {
        let defaults = freshDefaults()
        let game = GameViewModel(defaults: defaults)
        for i in 0..<81 where !game.cells[i].isGiven {
            game.select(i)
            game.enter(game.solution[i])
        }
        XCTAssertTrue(game.isWon)
        XCTAssertTrue(game.isNewRecord)
        let level = game.stats[game.difficulty.rawValue]
        XCTAssertEqual(level?.gamesWon, 1)
        XCTAssertNotNil(level?.bestTime)
        XCTAssertNil(defaults.data(forKey: "savedGame"), "the saved game must be cleared on win")

        // A fresh instance starts a new game instead of restoring the won one.
        let next = GameViewModel(defaults: defaults)
        XCTAssertFalse(next.isWon)
        XCTAssertEqual(next.stats[game.difficulty.rawValue]?.gamesWon, 1)
    }
}
