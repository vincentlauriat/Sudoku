import Foundation

enum Difficulty: String, CaseIterable, Identifiable {
    case easy, medium, hard, expert

    var id: String { rawValue }

    var label: String {
        switch self {
        case .easy: return String(localized: "difficulty.easy")
        case .medium: return String(localized: "difficulty.medium")
        case .hard: return String(localized: "difficulty.hard")
        case .expert: return String(localized: "difficulty.expert")
        }
    }

    /// Target number of given clues left on the board.
    var targetClues: Int {
        switch self {
        case .easy: return 40
        case .medium: return 34
        case .hard: return 28
        case .expert: return 24
        }
    }
}

/// Backtracking solver and puzzle generator over a flat 81-cell grid (0 = empty).
enum SudokuEngine {

    // MARK: - Solving

    /// Returns the solved grid, or nil if unsolvable.
    static func solve(_ grid: [Int]) -> [Int]? {
        guard hasValidGivens(grid) else { return nil }
        var work = grid
        var masks = Masks(grid: grid)
        return solveBacktrack(&work, &masks) ? work : nil
    }

    /// Counts solutions, stopping early at `limit`. Used to guarantee uniqueness.
    static func countSolutions(_ grid: [Int], limit: Int = 2) -> Int {
        guard hasValidGivens(grid) else { return 0 }
        var work = grid
        var masks = Masks(grid: grid)
        var count = 0
        countBacktrack(&work, &masks, &count, limit)
        return count
    }

    /// True when no given digit conflicts with a peer. Checked up front by the
    /// solver: backtracking only prevents *new* conflicts, and refuting a grid
    /// whose givens are already contradictory would require exhausting the
    /// whole search space.
    static func hasValidGivens(_ grid: [Int]) -> Bool {
        var rows = [Int](repeating: 0, count: 9)
        var cols = [Int](repeating: 0, count: 9)
        var boxes = [Int](repeating: 0, count: 9)
        for i in 0..<81 {
            let v = grid[i]
            guard v != 0 else { continue }
            guard (1...9).contains(v) else { return false }
            let bit = 1 << v
            let row = i / 9, col = i % 9, box = Masks.box(row, col)
            if rows[row] & bit != 0 || cols[col] & bit != 0 || boxes[box] & bit != 0 {
                return false
            }
            rows[row] |= bit
            cols[col] |= bit
            boxes[box] |= bit
        }
        return true
    }

    /// Bit set (bits 1...9) of candidate digits for a cell given the current grid.
    static func candidates(in grid: [Int], at index: Int) -> Set<Int> {
        guard grid[index] == 0 else { return [] }
        let masks = Masks(grid: grid)
        let free = masks.freeMask(row: index / 9, col: index % 9)
        return Set((1...9).filter { free & (1 << $0) != 0 })
    }

    // MARK: - Generation

    /// Generates a puzzle with a unique solution. Returns (puzzle, solution).
    static func generate(difficulty: Difficulty) -> (puzzle: [Int], solution: [Int]) {
        var full = Array(repeating: 0, count: 81)
        var masks = Masks(grid: full)
        _ = fillRandom(&full, &masks, index: 0)

        var puzzle = full
        var clues = 81
        // Remove cells in random order while the solution stays unique.
        for index in (0..<81).shuffled() {
            guard clues > difficulty.targetClues else { break }
            let saved = puzzle[index]
            puzzle[index] = 0
            if countSolutions(puzzle) == 1 {
                clues -= 1
            } else {
                puzzle[index] = saved
            }
        }
        return (puzzle, full)
    }

    // MARK: - Private

    /// Row/column/box occupancy as bitmasks for O(1) candidate lookups.
    private struct Masks {
        var rows = [Int](repeating: 0, count: 9)
        var cols = [Int](repeating: 0, count: 9)
        var boxes = [Int](repeating: 0, count: 9)

        init(grid: [Int]) {
            for i in 0..<81 where grid[i] != 0 {
                place(grid[i], row: i / 9, col: i % 9)
            }
        }

        static func box(_ row: Int, _ col: Int) -> Int { (row / 3) * 3 + col / 3 }

        mutating func place(_ v: Int, row: Int, col: Int) {
            let bit = 1 << v
            rows[row] |= bit
            cols[col] |= bit
            boxes[Self.box(row, col)] |= bit
        }

        mutating func remove(_ v: Int, row: Int, col: Int) {
            let bit = ~(1 << v)
            rows[row] &= bit
            cols[col] &= bit
            boxes[Self.box(row, col)] &= bit
        }

        func freeMask(row: Int, col: Int) -> Int {
            ~(rows[row] | cols[col] | boxes[Self.box(row, col)]) & 0b1111111110
        }
    }

    /// Index of the empty cell with the fewest candidates, or nil if the grid is full.
    private static func bestEmptyCell(_ grid: [Int], _ masks: Masks) -> (index: Int, free: Int)? {
        var best: (index: Int, free: Int, count: Int)?
        for i in 0..<81 where grid[i] == 0 {
            let free = masks.freeMask(row: i / 9, col: i % 9)
            let count = free.nonzeroBitCount
            if count == 0 { return (i, 0) }
            if best == nil || count < best!.count {
                best = (i, free, count)
                if count == 1 { break }
            }
        }
        return best.map { ($0.index, $0.free) }
    }

    private static func solveBacktrack(_ grid: inout [Int], _ masks: inout Masks) -> Bool {
        guard let (index, free) = bestEmptyCell(grid, masks) else { return true }
        if free == 0 { return false }
        let row = index / 9, col = index % 9
        for v in 1...9 where free & (1 << v) != 0 {
            grid[index] = v
            masks.place(v, row: row, col: col)
            if solveBacktrack(&grid, &masks) { return true }
            masks.remove(v, row: row, col: col)
            grid[index] = 0
        }
        return false
    }

    private static func countBacktrack(_ grid: inout [Int], _ masks: inout Masks, _ count: inout Int, _ limit: Int) {
        guard count < limit else { return }
        guard let (index, free) = bestEmptyCell(grid, masks) else {
            count += 1
            return
        }
        if free == 0 { return }
        let row = index / 9, col = index % 9
        for v in 1...9 where free & (1 << v) != 0 {
            grid[index] = v
            masks.place(v, row: row, col: col)
            countBacktrack(&grid, &masks, &count, limit)
            masks.remove(v, row: row, col: col)
            grid[index] = 0
            if count >= limit { return }
        }
    }

    /// Fills the grid completely with a randomized backtracking pass.
    private static func fillRandom(_ grid: inout [Int], _ masks: inout Masks, index: Int) -> Bool {
        guard index < 81 else { return true }
        let row = index / 9, col = index % 9
        let free = masks.freeMask(row: row, col: col)
        for v in (1...9).shuffled() where free & (1 << v) != 0 {
            grid[index] = v
            masks.place(v, row: row, col: col)
            if fillRandom(&grid, &masks, index: index + 1) { return true }
            masks.remove(v, row: row, col: col)
            grid[index] = 0
        }
        return false
    }
}
