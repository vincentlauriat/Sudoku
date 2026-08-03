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
            Spacer()
        }
    }

    private var newGameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nouvelle partie")
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
                Label("Effacer", systemImage: "delete.left")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $game.notesMode) {
                Label("Notes (N)", systemImage: "pencil")
            }
            .toggleStyle(.switch)
            Button {
                game.hint()
            } label: {
                Label("Indice", systemImage: "lightbulb")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var autoPlaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mode Auto")
                .font(.headline)
            Button {
                game.toggleAutoPlay()
            } label: {
                Label(
                    game.isAutoPlaying ? "Pause" : "Résoudre tout seul",
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
            Text("Vitesse : \(String(format: "%.2f", game.autoSpeed)) s/coup")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
