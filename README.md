# LocalWriter

An English writing assistant for macOS 14+, built with Swift and AppKit. **Qwen3 4B handles spelling, grammar, and sentence rewrites locally.** The app does not use macOS spellchecking or autocorrection.

## Run

```sh
scripts/build-app.sh
open dist/LocalWriter.app --args --practice
```

The practice editor uses the same debounce, model analysis, underline overlay, hover panel, and acceptance workflow as external editors. It does not require macOS Accessibility permission. Its status line shows model progress and actionable failures. Hover a red underline to accept a correction; hover a sentence to request a rewrite.

For Slack, Codex, and other apps, click **✎ → Grant Accessibility Access…** and enable LocalWriter in System Settings → Privacy & Security → Accessibility. Focus the message editor and pause typing. The app requests Chromium/Electron accessibility trees when inspecting an editor.

The menu shows **Disable for Codex** when enabled and **Enable for Codex** when disabled, alongside the current state. It captures the app when the menu opens, so clicking the action cannot accidentally target a different app. Pause and resume also have distinct labels.

### Development signing

Builds are ad-hoc signed. macOS can invalidate an existing Accessibility grant when the binary changes. A checked box for an older build does not prove the rebuilt app is trusted. Remove the old LocalWriter entry and add the rebuilt app if its diagnostics report missing access. A stable signing identity is needed for a smoother update experience.

## Model setup

This development workspace contains the official Ollama runtime and Qwen3 4B weights in `.local-runtime/`, ignored by Git. The app automatically starts that project-local runtime when available. **Start Local Model** starts it again; **Check Again** retries analysis. The app must remain in `dist/` for automatic discovery of the project-local runtime.

Alternatively, install [Ollama](https://ollama.com/download/mac), launch it, then run:

```sh
scripts/setup-model.sh
```

To run the project-local server manually:

```sh
scripts/start-model.sh
```

The server listens on `127.0.0.1:11434`. The bundled-runtime startup and start script disable cloud features and history. Draft analysis sends the current editor text only to this loopback endpoint; rewrites send the selected sentence. No draft text is written to app logs or storage. Model downloads require internet; inference does not.

## How corrections work

After a typing pause, the model returns conservatively corrected text in structured JSON. The app computes word-level differences and UTF-16 ranges locally. Accepting a correction requires the original editor and entire draft to still match the analyzed snapshot. Typing cancels outdated requests. Password fields and excluded apps are skipped.

The practice editor applies edits through NSTextView with undo support. External editors use macOS Accessibility selected-text replacement without clipboard or keystroke fallbacks.

## Limits

- Slack and Codex live compatibility still needs verification with Accessibility granted to the current build. Detection, word coordinates, and selected-text replacement depend on what each editor exposes.
- Missing permissions, unreadable fields, missing word coordinates, model failures, and disabled apps are reported in the menu instead of silently appearing to work.
- External drafts are limited to 4,000 UTF-16 code units. Sentence hover currently supports single-line sentences; wrapped ranges need more work.
- Model suggestions are fallible and are applied only when explicitly accepted.
- Google Docs canvas integration is not implemented.
- No launch-at-login registration, installer, notarization, or automatic model-download UI yet.

## Development and checks

No third-party Swift dependencies. Command Line Tools are sufficient.

```sh
scripts/check.sh
scripts/build-app.sh
dist/LocalWriter.app/Contents/MacOS/LocalWriter --check-model
dist/LocalWriter.app/Contents/MacOS/LocalWriter --check-editor
dist/LocalWriter.app/Contents/MacOS/LocalWriter --practice-check
```

- `CoreChecks`: Unicode ranges, stale edits, word differences including insertions and deletions, and app enable/disable states.
- `--check-editor`: real-model spelling and grammar, native word coordinates, overlay visibility, acceptance, and stale-edit rejection.
- `--practice-check`: opens a synthetic practice draft and exercises the running background loop, checks rendered red underline pixels, and accepts a correction. Requires the local model server; closes the test app afterward.
- **Editor Diagnostics…** reports Accessibility metadata without editor text. `--diagnose` also exposes this for development.

`WritingCore` owns edit validation, word differences, sentence ranges, and app availability state. `Accessibility.swift` adapts native and external editors. `Overlay.swift` draws underlines and suggestion panels. `App.swift` coordinates menus, debounce, hover, and asynchronous checks. `LocalModel.swift` owns model requests and the optional project-local runtime.
