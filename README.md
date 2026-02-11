# Scene (Native macOS Prototype)

A standalone macOS SwiftUI prototype for long-form writing workflows with:

- Binder-style chapter/scene structure
- Scene editor
- Compendium (characters, locations, lore, items, notes)
- AI text generation from a beat prompt
- Workshop chat interface with multi-session conversations

## Current Scope

This is an infrastructure-focused foundation intended for iterative development. It includes:

- Data model and app store architecture
- Local JSON persistence under `~/Library/Application Support/SceneApp/project.json`
- Pluggable AI provider layer
  - `Local Mock` provider for offline testing
  - `OpenAI-Compatible API` provider for local/remote chat-completion endpoints
- Modular SwiftUI views for binder, editor, compendium, workshop chat, and settings

## Build & Run

```bash
cd /Users/karpov/compwork/Scene
swift build
swift run SceneApp
```

## Notes

- The app defaults to `Local Mock` so generation works without API keys.
- For real generation, open Settings and switch provider to `OpenAI-Compatible API`, then configure endpoint/model/key.
- Prompt templates support placeholders:
  - `{beat}`
  - `{scene}`
  - `{context}`
