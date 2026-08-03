import SwiftUI

struct BoardView: View {
    @ObservedObject var game: GameViewModel

    var body: some View {
        let conflicts = game.conflicts
        let selectedValue = game.selected.map { game.cells[$0].value } ?? 0

        VStack(spacing: 0) {
            ForEach(0..<9) { row in
                HStack(spacing: 0) {
                    ForEach(0..<9) { col in
                        let i = row * 9 + col
                        CellView(
                            state: game.cells[i],
                            isSelected: game.selected == i,
                            isPeer: isPeer(of: i),
                            isSameValue: selectedValue != 0 && game.cells[i].value == selectedValue && game.selected != i,
                            isConflict: conflicts.contains(i),
                            isWrong: game.cells[i].value != 0 && game.cells[i].value != game.solution[i]
                        )
                        .onTapGesture { game.select(i) }
                        .overlay(alignment: .trailing) {
                            if col == 2 || col == 5 {
                                Rectangle().fill(Color.primary).frame(width: 2)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if row == 2 || row == 5 {
                                Rectangle().fill(Color.primary).frame(height: 2)
                            }
                        }
                    }
                }
            }
        }
        .border(Color.primary, width: 2)
        .aspectRatio(1, contentMode: .fit)
    }

    private func isPeer(of index: Int) -> Bool {
        guard let s = game.selected, s != index else { return false }
        let row = index / 9, col = index % 9
        let sr = s / 9, sc = s % 9
        return row == sr || col == sc || (row / 3 == sr / 3 && col / 3 == sc / 3)
    }
}

struct CellView: View {
    let state: CellState
    let isSelected: Bool
    let isPeer: Bool
    let isSameValue: Bool
    let isConflict: Bool
    let isWrong: Bool

    var body: some View {
        ZStack {
            background
            if state.value != 0 {
                Text("\(state.value)")
                    .font(.system(size: 26, weight: state.isGiven ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(foreground)
            } else if !state.notes.isEmpty {
                notesGrid
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .border(Color.primary.opacity(0.2), width: 0.5)
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.35) }
        if isConflict { return Color.red.opacity(0.18) }
        if isSameValue { return Color.accentColor.opacity(0.18) }
        if isPeer { return Color.primary.opacity(0.06) }
        return Color.clear
    }

    private var foreground: Color {
        if isWrong { return .red }
        return state.isGiven ? .primary : .accentColor
    }

    private var notesGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<3) { r in
                HStack(spacing: 0) {
                    ForEach(0..<3) { c in
                        let d = r * 3 + c + 1
                        Text(state.notes.contains(d) ? "\(d)" : " ")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(2)
    }
}
