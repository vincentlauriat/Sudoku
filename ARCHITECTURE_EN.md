# Architecture — Sudoku for macOS

> Source of truth. French mirror: [ARCHITECTURE.md](ARCHITECTURE.md).

## Overview

A native macOS app in pure SwiftUI, zero external dependencies, organized in three strict
layers. The Xcode project is generated from `project.yml` by
[xcodegen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is disposable and
git-ignored.

```mermaid
flowchart TB
    subgraph Views ["Views (SwiftUI)"]
        CV[ContentView<br/>layout · keyboard · victory]
        BV[BoardView / CellView<br/>9×9 grid rendering]
        SP[SidePanel<br/>difficulty · pad · auto-play]
    end
    subgraph ViewModel ["State (@MainActor)"]
        VM[GameViewModel<br/>cells · timer · errors · notes<br/>hints · auto-play Task]
    end
    subgraph Engine ["Engine (pure Swift, UI-free)"]
        E[SudokuEngine<br/>bitmask solver · countSolutions<br/>generator · candidates]
    end
    CV --> VM
    BV --> VM
    SP --> VM
    VM --> E
```

## Layers

### 1. Engine — `Sources/Engine/SudokuEngine.swift`

Pure, stateless, `enum`-namespaced functions over a flat `[Int]` of 81 cells (0 = empty).
No Foundation types beyond `Array`/`Set`, no SwiftUI import — it compiles standalone with
`swiftc`, which is exactly how it is smoke-tested.

| API | Role |
|---|---|
| `solve(_:) -> [Int]?` | Backtracking solver (MRV + bitmasks) |
| `countSolutions(_:limit:)` | Solution counter with early cutoff — the uniqueness oracle |
| `generate(difficulty:)` | Full random grid → hole digging with uniqueness guarantee |
| `candidates(in:at:)` | Candidate digits for one cell (used by auto-play move ordering) |

Internal `Masks` struct: one `Int` bitmask per row/column/box; candidate lookup is
`~(rows | cols | boxes) & 0b1111111110`.

### 2. State — `Sources/GameViewModel.swift`

A single `@MainActor ObservableObject` holding the entire game state:

- `cells: [CellState]` — value, given flag, pencil marks per cell
- Derived: `conflicts` (recomputed per render), `grid`, `formattedTime`
- Timer via Combine (`Timer.publish`), paused on victory
- Error policy: an entry differing from the stored solution increments `errorCount`
  immediately (the digit renders red)
- Auto-play: a cancellable `Task` — documented in detail in
  [docs/AUTOPLAY.md](docs/AUTOPLAY.md)

### 3. Views — `Sources/Views/`

Dumb rendering over the view model. `ContentView` owns keyboard handling
(`.onKeyPress`: digits, arrows, Delete, `N`) and the victory overlay; `BoardView` draws the
grid with peer/same-value/conflict highlighting; `SidePanel` hosts difficulty buttons, the
number pad, notes toggle, hint, and the auto-play controls.

## Key design decisions

| Decision | Rationale |
|---|---|
| Flat `[Int]` (81) instead of `[[Int]]` | Simpler indexing (`row*9+col`), trivially copyable, fast equality |
| Solution stored at generation time | Instant hints, instant error detection, O(1) auto-play values |
| Uniqueness via capped solution counting | Guarantees a well-formed puzzle at every difficulty |
| MRV heuristic in both solver and auto-play | Fast search *and* human-looking play from one idea |
| xcodegen instead of committed `.xcodeproj` | Reviewable project definition, no merge conflicts |
| Difficulty = clue count (40/34/28/24) | Simple, predictable; harder metrics (technique-based grading) are out of scope |

## Testing

`Tests/EngineTests.swift` (XCTest, hosted in the app):

- solves a known reference puzzle to its documented solution
- rejects contradictory grids
- detects ambiguity via `countSolutions`
- generates all four difficulties with exact clue counts and verified unique solutions
- candidate computation respects row/column/box peers
- view-model behaviour: win detection with zero errors, error counting

## Build & release

- Debug: `xcodegen generate && xcodebuild -scheme Sudoku build`
- Release: `Scripts/release.sh` — Release build (unsigned), `ditto` to clean staging,
  Developer ID codesign with Hardened Runtime + timestamp, DMG in `release/`, `notarytool`
  submit + staple, independent `spctl`/`stapler` verification.
- App icon: rendered programmatically by `Scripts/generate-icon.swift` (AppKit/CoreGraphics)
  → `Resources/AppIcon.icns`.
