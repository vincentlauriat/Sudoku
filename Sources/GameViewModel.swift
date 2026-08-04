import SwiftUI
import Combine

struct CellState: Codable, Equatable {
    var value: Int = 0
    var isGiven: Bool = false
    var notes: Set<Int> = []
}

/// Snapshot of a game in progress, persisted so the player can quit and resume.
struct SavedGame: Codable {
    var cells: [CellState]
    var solution: [Int]
    var difficulty: String
    var elapsed: TimeInterval
    var errorCount: Int
    var usedAutoPlay: Bool
}

struct LevelStats: Codable, Equatable {
    var gamesWon = 0
    var bestTime: TimeInterval?
}

@MainActor
final class GameViewModel: ObservableObject {
    @Published var cells: [CellState] = Array(repeating: CellState(), count: 81)
    @Published var selected: Int? = nil
    @Published var difficulty: Difficulty = .easy
    @Published var notesMode = false
    @Published var elapsed: TimeInterval = 0
    @Published var errorCount = 0
    @Published var isWon = false
    @Published var isNewRecord = false
    @Published var isAutoPlaying = false
    @Published var autoSpeed: Double = 0.25
    @Published private(set) var stats: [String: LevelStats] = [:]
    @Published private(set) var undoStack: [[CellState]] = []
    @Published private(set) var redoStack: [[CellState]] = []

    private(set) var solution: [Int] = Array(repeating: 0, count: 81)
    private var clock: AnyCancellable?
    private var autoTask: Task<Void, Never>?
    private var usedAutoPlay = false
    private let defaults: UserDefaults

    private static let gameKey = "savedGame"
    private static let statsKey = "levelStats"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.statsKey),
           let decoded = try? JSONDecoder().decode([String: LevelStats].self, from: data) {
            stats = decoded
        }
        if let data = defaults.data(forKey: Self.gameKey),
           let saved = try? JSONDecoder().decode(SavedGame.self, from: data),
           saved.cells.count == 81, saved.solution.count == 81,
           let level = Difficulty(rawValue: saved.difficulty) {
            restore(saved, level: level)
        } else {
            newGame(difficulty: .easy)
        }
    }

    // MARK: - Game lifecycle

    func newGame(difficulty: Difficulty) {
        stopAutoPlay()
        self.difficulty = difficulty
        let (puzzle, solved) = SudokuEngine.generate(difficulty: difficulty)
        solution = solved
        cells = puzzle.map { CellState(value: $0, isGiven: $0 != 0) }
        selected = nil
        errorCount = 0
        elapsed = 0
        isWon = false
        isNewRecord = false
        notesMode = false
        usedAutoPlay = false
        undoStack = []
        redoStack = []
        persist()
        startClock()
    }

    private func restore(_ saved: SavedGame, level: Difficulty) {
        difficulty = level
        cells = saved.cells
        solution = saved.solution
        elapsed = saved.elapsed
        errorCount = saved.errorCount
        usedAutoPlay = saved.usedAutoPlay
        startClock()
    }

    private func startClock() {
        clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isWon else { return }
                self.elapsed += 1
                self.persist()
            }
    }

    var grid: [Int] { cells.map(\.value) }

    /// Indices whose value conflicts with another cell in its row, column or box.
    var conflicts: Set<Int> {
        var result: Set<Int> = []
        for i in 0..<81 {
            let v = cells[i].value
            guard v != 0 else { continue }
            let row = i / 9, col = i % 9
            for j in 0..<81 where j != i && cells[j].value == v {
                let r = j / 9, c = j % 9
                if r == row || c == col || (r / 3 == row / 3 && c / 3 == col / 3) {
                    result.insert(i)
                    break
                }
            }
        }
        return result
    }

    // MARK: - Player input

    func select(_ index: Int) {
        guard !isAutoPlaying else { return }
        selected = index
    }

    func enter(_ digit: Int) {
        guard !isAutoPlaying, !isWon, let i = selected, !cells[i].isGiven else { return }
        if notesMode {
            guard cells[i].value == 0 else { return }
            snapshot()
            if cells[i].notes.contains(digit) {
                cells[i].notes.remove(digit)
            } else {
                cells[i].notes.insert(digit)
            }
            persist()
            return
        }
        guard cells[i].value != digit else { return }
        snapshot()
        cells[i].value = digit
        cells[i].notes = []
        if digit != solution[i] {
            errorCount += 1
        } else {
            clearNotes(around: i, digit: digit)
        }
        checkWin()
        persist()
    }

    func erase() {
        guard !isAutoPlaying, !isWon, let i = selected, !cells[i].isGiven else { return }
        guard cells[i].value != 0 || !cells[i].notes.isEmpty else { return }
        snapshot()
        cells[i].value = 0
        cells[i].notes = []
        persist()
    }

    func moveSelection(dRow: Int, dCol: Int) {
        guard !isAutoPlaying else { return }
        let current = selected ?? 40
        let row = min(8, max(0, current / 9 + dRow))
        let col = min(8, max(0, current % 9 + dCol))
        selected = row * 9 + col
    }

    func hint() {
        guard !isAutoPlaying, !isWon else { return }
        let target = selected.flatMap { cells[$0].isGiven || cells[$0].value == solution[$0] ? nil : $0 }
            ?? (0..<81).filter { cells[$0].value != solution[$0] }.randomElement()
        guard let i = target else { return }
        snapshot()
        selected = i
        cells[i].value = solution[i]
        cells[i].notes = []
        clearNotes(around: i, digit: solution[i])
        checkWin()
        persist()
    }

    // MARK: - Undo / Redo

    var canUndo: Bool { !undoStack.isEmpty && !isAutoPlaying && !isWon }
    var canRedo: Bool { !redoStack.isEmpty && !isAutoPlaying && !isWon }

    func undo() {
        guard canUndo, let previous = undoStack.popLast() else { return }
        redoStack.append(cells)
        cells = previous
        persist()
    }

    func redo() {
        guard canRedo, let next = redoStack.popLast() else { return }
        undoStack.append(cells)
        cells = next
        persist()
    }

    /// Pushed before every board mutation. A new move invalidates the redo branch.
    private func snapshot() {
        undoStack.append(cells)
        redoStack = []
        if undoStack.count > 200 { undoStack.removeFirst() }
    }

    // MARK: - Auto-play (the app solves the board itself)

    func toggleAutoPlay() {
        isAutoPlaying ? stopAutoPlay() : startAutoPlay()
    }

    private func startAutoPlay() {
        guard !isWon else { return }
        isAutoPlaying = true
        usedAutoPlay = true
        autoTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard let i = self.nextAutoMove() else { break }
                self.selected = i
                try? await Task.sleep(for: .seconds(self.autoSpeed))
                guard !Task.isCancelled else { break }
                withAnimation(.easeOut(duration: 0.15)) {
                    self.cells[i].value = self.solution[i]
                    self.cells[i].notes = []
                }
                self.checkWin()
                self.persist()
            }
            self?.isAutoPlaying = false
        }
    }

    func stopAutoPlay() {
        autoTask?.cancel()
        autoTask = nil
        isAutoPlaying = false
    }

    /// Picks the next cell to play: wrong entries first, then the empty cell
    /// with the fewest candidates — the same order a human solver would use.
    private func nextAutoMove() -> Int? {
        if let wrong = (0..<81).first(where: { cells[$0].value != 0 && cells[$0].value != solution[$0] }) {
            return wrong
        }
        let currentGrid = grid
        let empties = (0..<81).filter { currentGrid[$0] == 0 }
        return empties.min { a, b in
            SudokuEngine.candidates(in: currentGrid, at: a).count
                < SudokuEngine.candidates(in: currentGrid, at: b).count
        }
    }

    // MARK: - Persistence & statistics

    /// Saved on every mutation and every clock tick; cleared once the game is won.
    private func persist() {
        guard !isWon else {
            defaults.removeObject(forKey: Self.gameKey)
            return
        }
        let saved = SavedGame(
            cells: cells,
            solution: solution,
            difficulty: difficulty.rawValue,
            elapsed: elapsed,
            errorCount: errorCount,
            usedAutoPlay: usedAutoPlay
        )
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.gameKey)
        }
    }

    /// Games solved by auto-play don't count towards the player's statistics.
    private func recordWin() {
        guard !usedAutoPlay else { return }
        var level = stats[difficulty.rawValue] ?? LevelStats()
        level.gamesWon += 1
        if level.bestTime.map({ elapsed < $0 }) ?? true {
            level.bestTime = elapsed
            isNewRecord = true
        }
        stats[difficulty.rawValue] = level
        if let data = try? JSONEncoder().encode(stats) {
            defaults.set(data, forKey: Self.statsKey)
        }
    }

    // MARK: - Helpers

    private func clearNotes(around index: Int, digit: Int) {
        let row = index / 9, col = index % 9
        for j in 0..<81 {
            let r = j / 9, c = j % 9
            if r == row || c == col || (r / 3 == row / 3 && c / 3 == col / 3) {
                cells[j].notes.remove(digit)
            }
        }
    }

    private func checkWin() {
        guard grid == solution else { return }
        isWon = true
        stopAutoPlay()
        defaults.removeObject(forKey: Self.gameKey)
        recordWin()
    }

    nonisolated static func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var formattedTime: String { Self.timeString(elapsed) }
}
