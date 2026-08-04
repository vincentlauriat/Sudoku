import SwiftUI

struct SidePanel: View {
    @ObservedObject var game: GameViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            newGameSection
            Divider()
            numberPad
            Divider()
            toolsSection
            Divider()
            autoPlaySection
            Divider()
            statsSection
            Spacer()
        }
    }

    private var newGameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("new-game.title")
                .font(.headline)
            ForEach(Difficulty.allCases) { level in
                Button {
                    game.newGame(difficulty: level)
                } label: {
                    Text(level.label)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var numberPad: some View {
        VStack(spacing: 6) {
            ForEach(0..<3) { r in
                HStack(spacing: 6) {
                    ForEach(0..<3) { c in
                        let d = r * 3 + c + 1
                        Button("\(d)") { game.enter(d) }
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            Button {
                game.erase()
            } label: {
                Label("pad.erase", systemImage: "delete.left")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $game.notesMode) {
                Label("tools.notes", systemImage: "pencil")
            }
            .toggleStyle(.switch)
            Button {
                game.hint()
            } label: {
                Label("tools.hint", systemImage: "lightbulb")
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 6) {
                Button {
                    game.undo()
                } label: {
                    Label("tools.undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!game.canUndo)
                Button {
                    game.redo()
                } label: {
                    Label("tools.redo", systemImage: "arrow.uturn.forward")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!game.canRedo)
            }
        }
    }

    private var autoPlaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("auto.title")
                .font(.headline)
            Button {
                game.toggleAutoPlay()
            } label: {
                Label(
                    game.isAutoPlaying ? "auto.pause" : "auto.solve",
                    systemImage: game.isAutoPlaying ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .tint(game.isAutoPlaying ? .orange : .green)
            .buttonStyle(.borderedProminent)
            HStack {
                Image(systemName: "tortoise")
                Slider(
                    value: Binding(
                        get: { 1.05 - game.autoSpeed },
                        set: { game.autoSpeed = 1.05 - $0 }
                    ),
                    in: 0.05...1.0
                )
                Image(systemName: "hare")
            }
            .foregroundStyle(.secondary)
            Text(String(format: String(localized: "auto.speed"), game.autoSpeed))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statsSection: some View {
        let level = game.stats[game.difficulty.rawValue] ?? LevelStats()
        return VStack(alignment: .leading, spacing: 4) {
            Text("stats.title")
                .font(.headline)
            Text(
                level.bestTime.map {
                    String(format: String(localized: "stats.best"), GameViewModel.timeString($0))
                } ?? String(localized: "stats.none")
            )
            Text(String(format: String(localized: "stats.won"), level.gamesWon))
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
