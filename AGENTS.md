# Scene Repository Notes

## Scope

- `Scene` is a native macOS SwiftUI app (no WebView) for long-form writing workflows.
- Core domains: binder (chapters/scenes), writing editor, compendium, workshop chat, summaries, prompt templates.

## Project Layout

- `Sources/SceneApp/Models`: domain and request/response models.
- `Sources/SceneApp/Services`: persistence and AI provider integrations.
- `Sources/SceneApp/Store/AppStore.swift`: single source of truth for app state and mutations.
- `Sources/SceneApp/Views`: SwiftUI views and panel/dialog composition.
- `scripts/build-gui-app.sh`: autonomous `.app` build (XcodeGen + xcodebuild).

## Build and Run

- Build: `swift build`
- Run: `swift run SceneApp`
- GUI bundle build: `./scripts/build-gui-app.sh`

Always run `swift build` after UI/state/model edits.

## Persistence Format

- Projects are folder bundles with `.sceneproj`.
- Main files:
  - `manifest.json`
  - `scenes/*.rtf`
  - `compendium/*.md`
  - `workshop/*.json`
- Last opened project path is persisted and restored on launch.

## Context and Prompting

- Scene context selection is scene-local and persisted.
- Context sources currently supported:
  - compendium entries
  - scene summaries
  - chapter summaries
- Selection maps in `StoryProject`:
  - `sceneContextCompendiumSelection`
  - `sceneContextSceneSummarySelection`
  - `sceneContextChapterSummarySelection`
- `AppStore.buildCompendiumContext(for:)` is the shared context builder used by generation/chat paths.

## UI Conventions

- Prefer native SwiftUI patterns and Apple-style spacing/colors.
- Keep views composed into small focused subviews; keep shared logic in `AppStore`.
- For modal editors/selectors, prefer sheet-driven state and avoid duplicated control rows.

## Change Discipline

- Keep edits scoped and avoid unrelated refactors.
- If data model fields change, update:
  - `Models/DomainModels.swift`
  - `Services/PersistenceService.swift`
  - any relevant UI/store bindings
- Verify behavior with local build before commit.

## Commit Style

- Default commit subject format: `type: concise imperative summary`
- Preferred types: `feat`, `fix`, `ui`, `docs`, `chore`
- Use lowercase after `type:`, no trailing period.
- Keep the subject focused and short (prefer ~72 chars or less).
