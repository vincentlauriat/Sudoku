import SwiftUI
import Combine

struct CellState {
    var value: Int = 0
    var isGiven: Bool = false
    var notes: Set<Int> = []
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
    @Published var isAutoPlaying = false
    @Published var autoSpeed: Double = 0.25

    private(set) var solution: [Int] = Array(repeating: 0, count: 81)
    private var clock: AnyCancellable?
    private var autoTask: Task<Void, Never>?

    init() {
        newGame(difficulty: .easy)
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
        notesMode = false
        clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, !self.isWon else { return }
                self.elapsed += 1
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
            if cells[i].value == 0 {
                if cells[i].notes.contains(digit) {
                    cells[i].notes.remove(digit)
                } else {
                    cells[i].notes.insert(digit)
                }
            }
            return
        }
        guard cells[i].value != digit else { return }
        cells[i].value = digit
        cells[i].notes = []
        if digit != solution[i] {
            errorCount += 1
        } else {
            clearNotes(around: i, digit: digit)
        }
        checkWin()
    }

    func erase() {
        guard !isAutoPlaying, !isWon, let i = selected, !cells[i].isGiven else { return }
        cells[i].value = 0
        cells[i].notes = []
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
        selected = i
        cells[i].value = solution[i]
        cells[i].notes = []
        clearNotes(around: i, digit: solution[i])
        checkWin()
    }

    // MARK: - Auto-play (the app solves the board itself)

    func toggleAutoPlay() {
        isAutoPlaying ? stopAutoPlay() : startAutoPlay()
    }

    private func startAutoPlay() {
        guard !isWon else { return }
        isAutoPlaying = true
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
    }

    var formattedTime: String {
        let s = Int(elapsed)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
