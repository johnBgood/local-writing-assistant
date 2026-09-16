# LocalWriter

An English writing assistant for macOS 14+, built with Swift and AppKit. Text processing stays on the Mac: spelling uses NSSpellChecker, and sentence rewrites use a local Qwen3 4B model through Ollama.

## Run

```sh
scripts/build-app.sh
open dist/LocalWriter.app
```

Click the **✎** menu-bar icon, then **Grant Accessibility Access…**. Enable LocalWriter under System Settings → Privacy & Security → Accessibility. Reopen the app if macOS does not recognize the permission immediately. Development builds are ad-hoc signed; rebuilding may require granting access again.

Focus an editable field in another app and pause typing. Hover a red underline for spelling suggestions. Hover a single-line sentence, then choose **Suggest a clearer sentence** for a local rewrite. Changes are applied only when clicked and only if the original editor and text still match.

The menu includes pause/resume, per-app exclusion, and a practice editor. The practice editor uses native macOS spelling; the cross-app overlay deliberately excludes LocalWriter itself.

## Local model

Install [Ollama](https://ollama.com/download/mac), launch it, then run:

```sh
scripts/setup-model.sh
```

The development machine also has a project-local runtime and downloaded model in `.local-runtime/` (ignored by Git). To start that runtime:

```sh
scripts/start-model.sh
```

Keep the server running while using rewrites. It listens on `127.0.0.1:11434`. The start script disables Ollama cloud features and history. The app sends only the chosen sentence, never the whole editor, to this local endpoint. Model downloads require internet; inference does not.

## Current capabilities and limits

- Native menu-bar app, red spelling underlines, hover suggestions, click-to-apply, and local sentence rewrites.
- Debounces typing, cancels outdated rewrites, validates UTF-16 ranges, rejects stale edits, skips secure text fields, and supports per-app exclusions.
- Only the focused text field is analyzed, with a 20,000 UTF-16 code-unit limit.
- Editors must expose text, range coordinates, and writable selected text through macOS Accessibility. Missing capabilities are handled without clipboard or simulated keystroke fallbacks.
- Slack is a target integration; live Slack compatibility requires verification after Accessibility access is granted. Do not assume all Electron editors expose the required attributes.
- Sentence hover currently supports single-line sentences. Wrapped sentences need per-line geometry work.
- Spelling runs in the background; grammar/style improvements are currently on demand through sentence rewrites.
- Google Docs canvas integration is **not implemented**. A dedicated browser integration is still needed.
- No launch-at-login registration, installer, notarization, or automatic model download UI yet.
- No editor text is written to app logs or storage. Preferences store only excluded app IDs and optional model selection.

## Development

No third-party Swift dependencies. Works with Command Line Tools; Xcode is optional.

```sh
scripts/check.sh
scripts/build-app.sh
dist/LocalWriter.app/Contents/MacOS/LocalWriter --check-model
```

`CoreChecks` is a framework-free executable test suite, so it runs on Command Line Tools installations without XCTest. It checks Unicode/emoji ranges, stale edits, mismatched original text, invalid ranges, and sentence offsets.

Source layout:

- `WritingCore`: text-edit validation and sentence ranges.
- `Accessibility.swift`: focused editor discovery, range bounds, and guarded replacement.
- `Overlay.swift`: transparent underline window and nonactivating suggestion panel.
- `App.swift`: menu, debounce, hover tracking, and rewrite lifecycle.
- `LocalModel.swift`: loopback Ollama client with structured output.
