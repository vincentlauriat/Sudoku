import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameViewModel()
    @FocusState private var boardFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 12) {
                statusBar
                BoardView(game: game)
                    .frame(width: 460, height: 460)
                    .focusable()
                    .focused($boardFocused)
                    .onKeyPress { press in handleKey(press) }
                    .overlay { if game.isWon { victoryOverlay } }
            }
            SidePanel(game: game)
                .frame(width: 210)
        }
        .padding(20)
        .onAppear { boardFocused = true }
    }

    private var statusBar: some View {
        HStack {
            Label(game.difficulty.label, systemImage: "square.grid.3x3")
            Spacer()
            Label(game.formattedTime, systemImage: "clock")
                .monospacedDigit()
            Spacer()
            Label("\(game.errorCount)", systemImage: "xmark.circle")
                .foregroundStyle(game.errorCount > 0 ? .red : .secondary)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var victoryOverlay: some View {
        VStack(spacing: 12) {
            Text("🎉")
                .font(.system(size: 48))
            Text("victory.title")
                .font(.title.bold())
            Text(String(format: String(localized: "victory.subtitle"), game.difficulty.label, game.formattedTime))
                .foregroundStyle(.secondary)
            if game.isNewRecord {
                Text("victory.record")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            Button("victory.new-game") {
                game.newGame(difficulty: game.difficulty)
                boardFocused = true
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 20)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow: game.moveSelection(dRow: -1, dCol: 0); return .handled
        case .downArrow: game.moveSelection(dRow: 1, dCol: 0); return .handled
        case .leftArrow: game.moveSelection(dRow: 0, dCol: -1); return .handled
        case .rightArrow: game.moveSelection(dRow: 0, dCol: 1); return .handled
        case .delete, .deleteForward: game.erase(); return .handled
        default:
            if let d = press.characters.first?.wholeNumberValue, (1...9).contains(d) {
                game.enter(d)
                return .handled
            }
            if press.characters == "n" {
                game.notesMode.toggle()
                return .handled
            }
            return .ignored
        }
    }
}
