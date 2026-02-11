# Scene (Native macOS App Prototype)

`Scene` is a standalone SwiftUI macOS writing tool prototype (no WebView) with:

- Binder-style chapter/scene navigation
- Scene editor with AI-assisted prose generation
- Compendium (characters, locations, lore, items, notes)
- Workshop chat with multi-session conversations
- Local project persistence

## Requirements

- macOS 14 or newer
- Swift 6 toolchain (`swift --version`) or Xcode 15.4+
- XcodeGen (`brew install xcodegen`) for the autonomous GUI build script

## Project Structure

```text
Scene/
├─ Package.swift
├─ project.yml
├─ README.md
├─ scripts/
│  └─ build-gui-app.sh
├─ Resources/
└─ Sources/SceneApp/
   ├─ SceneApp.swift
   ├─ Models/
   │  ├─ DomainModels.swift
   │  └─ GenerationModels.swift
   ├─ Services/
   │  ├─ AIService.swift
   │  ├─ OpenAICompatibleAIService.swift
   │  └─ PersistenceService.swift
   ├─ Store/
   │  └─ AppStore.swift
   └─ Views/
      ├─ ContentView.swift
      ├─ BinderSidebarView.swift
      ├─ EditorView.swift
      ├─ CompendiumView.swift
      ├─ WorkshopChatView.swift
      └─ SettingsSheetView.swift
```

### Module Roles

- `Models/`: Codable domain objects (project, scenes, compendium, prompts, workshop sessions) and generation request/response models.
- `Services/`: persistence and provider-specific AI integration.
- `Store/AppStore.swift`: central app state, mutations, selection logic, and async generation/chat workflows.
- `Views/`: SwiftUI UI composition for writing workspace, compendium, workshop, and settings.

## Build

```bash
cd /Users/karpov/compwork/Scene
swift build
```

## Run (Development)

```bash
cd /Users/karpov/compwork/Scene
swift run SceneApp
```

## Install

### Option 1: Install via Xcode (recommended for GUI app distribution)

1. Open `Package.swift` in Xcode.
2. Select the `SceneApp` scheme and run once (`Product > Run`).
3. For a distributable app, use `Product > Archive` and then `Distribute App`.
4. Place the generated app in `/Applications` (or `~/Applications`).

### Option 2: Local release executable via SwiftPM

```bash
cd /Users/karpov/compwork/Scene
swift build -c release
```

Binary path:

```text
.build/release/SceneApp
```

You can run this executable directly from Terminal.

### Option 3: Autonomous `.app` build (XcodeGen + xcodebuild)

Generate and build the macOS app bundle in one command:

```bash
cd /Users/karpov/compwork/Scene
./scripts/build-gui-app.sh
```

Output bundle:

```text
dist/SceneApp.app
```

Script options:

```bash
./scripts/build-gui-app.sh --debug
./scripts/build-gui-app.sh --clean --release
```

## Data & Configuration

- Projects are stored as folder bundles with `.sceneproj` extension.
- Each project contains:
  - `manifest.json` (ordering, metadata, settings)
  - `scenes/*.md` (scene text)
  - `compendium/*.md` (entry text)
  - `workshop/*.json` (chat messages)
- The app restores the last opened project on restart.
- Default provider is `Local Mock` (works without API keys).
- To use a real model endpoint, open Settings and select `OpenAI-Compatible API`, then configure:
  - LM Studio default endpoint: `http://localhost:1234/v1`
  - endpoint URL
  - API key
  - model name
  - streaming mode (optional)
  - request timeout (default: 5 minutes)

## Prompt Placeholders

Prompt templates can use:

- `{beat}`
- `{scene}`
- `{context}`
