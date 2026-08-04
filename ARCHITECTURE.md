# Architecture — Sudoku pour macOS

> Miroir français. Source de vérité : [ARCHITECTURE_EN.md](ARCHITECTURE_EN.md).

## Vue d'ensemble

Application macOS native en SwiftUI pur, organisée en trois couches strictes, avec une seule
dépendance externe : [Sparkle 2](https://sparkle-project.org) pour les mises à jour intégrées
(ajoutée via SPM dans `project.yml`). Le projet Xcode est généré depuis `project.yml` par
[xcodegen](https://github.com/yonaskolb/XcodeGen) — le `.xcodeproj` est jetable et ignoré par git.

```mermaid
flowchart TB
    subgraph Views ["Vues (SwiftUI)"]
        CV[ContentView<br/>layout · clavier · victoire]
        BV[BoardView / CellView<br/>rendu de la grille 9×9]
        SP[SidePanel<br/>niveaux · pavé · mode auto]
    end
    subgraph ViewModel ["État (@MainActor)"]
        VM[GameViewModel<br/>cases · chrono · erreurs · notes<br/>indices · Task du mode auto<br/>undo/redo · persistance · stats]
    end
    subgraph Engine ["Moteur (Swift pur, sans UI)"]
        E[SudokuEngine<br/>solveur bitmask · countSolutions<br/>générateur · candidates]
    end
    CV --> VM
    BV --> VM
    SP --> VM
    VM --> E
```

## Couches

### 1. Moteur — `Sources/Engine/SudokuEngine.swift`

Fonctions pures et sans état, sous namespace `enum`, sur un `[Int]` plat de 81 cases
(0 = vide). Aucun import SwiftUI — le fichier compile en standalone avec `swiftc`, ce qui sert
de smoke-test.

| API | Rôle |
|---|---|
| `solve(_:) -> [Int]?` | Solveur backtracking (MRV + bitmasks) |
| `countSolutions(_:limit:)` | Compteur de solutions avec coupure — l'oracle d'unicité |
| `generate(difficulty:)` | Grille complète aléatoire → creusage avec garantie d'unicité |
| `candidates(in:at:)` | Chiffres candidats d'une case (utilisé par l'ordre des coups du mode auto) |

Struct interne `Masks` : un bitmask `Int` par ligne/colonne/bloc ; les candidats d'une case
s'obtiennent par `~(rows | cols | boxes) & 0b1111111110`.

### 2. État — `Sources/GameViewModel.swift`

Un unique `ObservableObject` `@MainActor` portant tout l'état de la partie :

- `cells: [CellState]` — valeur, indice de départ, notes par case
- Dérivés : `conflicts` (recalculé à chaque rendu), `grid`, `formattedTime`
- Chrono via Combine (`Timer.publish`), suspendu à la victoire
- Politique d'erreur : une saisie différente de la solution stockée incrémente
  immédiatement `errorCount` (le chiffre s'affiche en rouge)
- Mode auto : une `Task` annulable — détaillée dans [docs/AUTOPLAY.md](docs/AUTOPLAY.md)
- Undo/redo : piles de snapshots de `cells` (plafond 200), empilés avant chaque mutation ;
  un nouveau coup invalide la branche redo ; `errorCount` n'est jamais décrémenté par un undo
- Persistance : la partie en cours (`SavedGame`, Codable) est écrite dans `UserDefaults` à
  chaque coup et chaque tick du chrono, restaurée dans `init`, purgée à la victoire
- Statistiques : `LevelStats` (parties gagnées, meilleur temps) par niveau, aussi dans
  `UserDefaults` ; les parties terminées par le mode auto sont exclues

### 3. Vues — `Sources/Views/`

Rendu pur au-dessus du view model. `ContentView` gère le clavier (`.onKeyPress` : chiffres,
flèches, Suppr, `N`) et l'overlay de victoire ; `BoardView` dessine la grille avec les
surlignages pairs/même valeur/conflits ; `SidePanel` porte les niveaux, le pavé numérique, les
notes, l'indice, undo/redo (⌘Z / ⇧⌘Z), les contrôles du mode auto et les statistiques du
niveau courant. `UpdaterCommands.swift` fait le pont entre le `canCheckForUpdates` de Sparkle
et un item de menu SwiftUI.

## Localisation

L'UI est localisée en français (langue de développement) et en anglais via
`Resources/fr.lproj` et `en.lproj/Localizable.strings`, avec des clés sémantiques
(`difficulty.easy`, `tools.undo`, `victory.record`, …). Les `Text`/`Label`/`Button` SwiftUI
résolvent les clés implicitement via `LocalizedStringKey` ; les chaînes formatées passent par
`String(localized:)` + `String(format:)`. La documentation du repo reste en anglais.

## Mises à jour intégrées (Sparkle)

- `SPUStandardUpdaterController` démarré au lancement ; « Rechercher les mises à jour… »
  dans le menu de l'app (`CommandGroup(after: .appInfo)`).
- Feed : `SUFeedURL` → https://vincentlauriat.github.io/Sudoku/appcast.xml —
  `docs/appcast.xml`, servi par le site GitHub Pages existant et régénéré par
  `Scripts/release.sh` à chaque release.
- Les mises à jour sont signées EdDSA (`sign_update`) avec la clé privée du trousseau de
  connexion, compte **« Sudoku »** — ne jamais la régénérer ; la moitié publique est
  `SUPublicEDKey` dans `project.yml`.
- Sparkle compare `sparkle:version` au `CFBundleVersion` (`CURRENT_PROJECT_VERSION`), qui
  doit donc augmenter à chaque release.

## Décisions clés

| Décision | Justification |
|---|---|
| `[Int]` plat (81) plutôt que `[[Int]]` | Indexation simple (`row*9+col`), copie triviale, égalité rapide |
| Solution stockée à la génération | Indices instantanés, détection d'erreur immédiate, valeurs du mode auto en O(1) |
| Unicité par comptage de solutions borné | Garantit un puzzle bien formé à tous les niveaux |
| Heuristique MRV (solveur **et** mode auto) | Recherche rapide *et* jeu d'apparence humaine avec une seule idée |
| xcodegen plutôt que `.xcodeproj` commité | Définition de projet lisible en revue, zéro conflit de merge |
| Difficulté = nombre d'indices (40/34/28/24) | Simple et prévisible ; la gradation par techniques est hors périmètre |

## Tests

XCTest, hébergé dans l'app — 11 tests. `Tests/EngineTests.swift` :

- résout un puzzle de référence connu vers sa solution documentée
- rejette les grilles contradictoires
- détecte l'ambiguïté via `countSolutions`
- génère les quatre niveaux avec le bon nombre d'indices et une solution unique vérifiée
- le calcul de candidats respecte ligne/colonne/bloc
- comportement du view model : victoire sans erreur, comptage d'erreurs

`Tests/GameViewModelTests.swift` (suite `UserDefaults` isolée par test) :

- aller-retour undo/redo, branche redo invalidée par un nouveau coup
- sauvegarde/restauration entre instances du view model
- la victoire enregistre les statistiques et purge la sauvegarde

## Build & release

- Debug : `xcodegen generate && xcodebuild -scheme Sudoku build`
- Release : `Scripts/release.sh` — build Release (non signé), `ditto` vers un staging propre,
  binaires imbriqués de Sparkle.framework signés du plus profond au plus englobant, codesign
  Developer ID avec Hardened Runtime + timestamp, DMG dans `release/`, soumission
  `notarytool` + staple, `sign_update` EdDSA + génération de `docs/appcast.xml`,
  vérification indépendante `spctl`/`stapler`.
- Icône : rendue programmatiquement par `Scripts/generate-icon.swift` (AppKit/CoreGraphics)
  → `Resources/AppIcon.icns`.
