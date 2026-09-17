# LocalWriter

An English, French and German writing assistant for macOS 14+, built with Swift and AppKit. **Qwen3 4B handles spelling, grammar, and sentence rewrites locally.** The app does not use macOS spellchecking or autocorrection.

## Installation

Voir le [guide complet en français : app Mac, modèle, extension Chrome, mises à jour et dépannage](docs/INSTALLATION.fr.md).

## Run

```sh
scripts/build-app.sh
open dist/LocalWriter.app --args --practice
```

The practice editor uses the same debounce, model analysis, underline overlay, hover panel, and acceptance workflow as external editors. It does not require macOS Accessibility permission. Its status line shows model progress and actionable failures. Hover a red underline to accept a correction; hover a sentence to request a rewrite.

For Slack, Codex, and other apps, click **✎ → Grant Accessibility Access…** and enable LocalWriter in System Settings → Privacy & Security → Accessibility. Focus the message editor and pause typing. The app requests Chromium/Electron accessibility trees when inspecting an editor.

The menu shows **Disable for Codex** when enabled and **Enable for Codex** when disabled, alongside the current state. It captures the app when the menu opens, so clicking the action cannot accidentally target a different app. Pause and resume also have distinct labels.

### Development signing

This workspace now uses a persistent local signing certificate. Fresh clones without that identity fall back to ad-hoc signing; macOS can invalidate their existing Accessibility grant when the binary changes. A checked box for an older build does not prove the rebuilt app is trusted. Remove the old LocalWriter entry and add the rebuilt app if its diagnostics report missing access. A stable signing identity is needed for a smoother update experience.

An optional project-local signing setup is prepared in `scripts/sign-app.py`. It creates a private certificate and keychain only with an explicitly approved `--setup` invocation. It does not add a trusted root certificate. The keychain is locked after use; `.local-signing/` is ignored by Git. After setup, builds reuse a certificate-pinned identity and do not silently fall back to ad-hoc signing. Setup is installed on this development machine. `python3 scripts/check-signing.py` verifies that two distinct builds have different code hashes but the same certificate-pinned identity.

The confirmed failure was macOS TCC retaining a requirement for an older code hash while the running build had a different hash. After choosing the final signing identity, reset only this app's stale entry with `tccutil reset Accessibility com.johnbgood.localwriter`, then grant the current app access once. Resetting this entry revokes its existing grant; it does not grant access automatically.

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

## Languages and personal dictionary

The Mac menu **Language** and Chrome popup **Writing language** share one setting: automatic detection, English, Français or Deutsch. Language detection runs locally; corrections and rewrites preserve the original language. Mixed-language passages and very short fragments can be ambiguous.

Click **Add “… ” to dictionary** on a correction card, or use **Personal dictionary** in the Mac menu / Chrome popup to add or remove a word. Accepted words are protected during correction and rewriting; surrounding grammar can still be corrected. Preferences and words are saved locally in `~/Library/Application Support/LocalWriter/preferences.json`, shared by the app and native bridge. Changes take effect on the next check; refocus the browser tab after changing settings in the Mac menu.

`python3 scripts/check-multilingual.py` tests real model corrections and rewrites in all three languages plus dictionary protection with a neighboring grammar error. It temporarily changes language and adds a test word, then restores the previous settings.

## How corrections work

After a typing pause, the model returns conservatively corrected text in structured JSON. The app computes word-level differences and UTF-16 ranges locally. Accepting a correction requires the original editor and entire draft to still match the analyzed snapshot. Typing cancels outdated requests. Password fields and excluded apps are skipped.

Whitespace-only changes are ignored. Phrase corrections retain one replacement range while drawing separate underlines beneath their words, never across blank lines. Hovering a sentence highlights its words in blue and offers a meaning-preserving rewrite; accepting it replaces the complete sentence. Selecting text in a native editor also requests a rewrite automatically once the selection settles. The suggestion is invalidated when the selection, editor or draft changes. This requires the editor to expose its selected range through Accessibility.

Editor discovery uses shared accessibility roles and focused descendants, without app-specific editor branches. Ambiguous or incomplete container searches do not select an arbitrary editor.

Rich editors can advertise word bounds but return zero-sized rectangles. LocalWriter then maps their static text descendants back to the draft (allowing whitespace paragraph separators) and queries those text ranges. Mismatched text and whole-editor rectangles are rejected.

The practice editor applies edits through NSTextView with undo support. External editors first use macOS Accessibility selected-text replacement, waiting for the requested selection and verifying the resulting draft. If that operation is unsupported or leaves the draft unchanged, LocalWriter verifies the same editor, text, and selection again and pastes the accepted suggestion using a targeted Command-V event. The previous clipboard formats are restored unless a newer clipboard copy has occurred. No Return key is sent. Changes are reported as successful only after the resulting draft matches the expected text.

## Limits

- Chrome's standard textarea and Slack's rich composer have been verified with a live model correction and precise word coordinates. Slack correction acceptance and Codex compatibility still need verification. Detection, word coordinates, and selected-text replacement depend on what each editor exposes.
- Missing permissions, unreadable fields, missing word coordinates, model failures, and disabled apps are reported in the menu instead of silently appearing to work.
- External drafts are limited to 4,000 UTF-16 code units. Sentence hover uses individual word positions across lines; editors must expose accurate range geometry.
- Model suggestions are fallible and are applied only when explicitly accepted.
- Native Google Docs canvas integration is unavailable; the Chrome companion has an experimental separate adapter.
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
- `--selection-check`: verifies automatic selected-text rewriting and full-range acceptance in the native practice editor with the real local model.
- `--check-clipboard`: uses an isolated test pasteboard to verify preservation of text and binary formats and that newer clipboard copies are not overwritten.
- **Editor Diagnostics…** reports Accessibility metadata without editor text. `--diagnose` also exposes this for development.
- Use `open -n -g dist/LocalWriter.app --args --probe-editor --app com.google.Chrome --report /tmp/localwriter-probe.txt` for a targeted, text-free geometry/model diagnostic. LaunchServices preserves the app's Accessibility identity; a direct shell invocation may inherit different permission attribution.

`WritingCore` owns edit validation, word differences, sentence ranges, and app availability state. `Accessibility.swift` adapts native and external editors. `Overlay.swift` draws underlines and suggestion panels. `App.swift` coordinates menus, debounce, hover, and asynchronous checks. `LocalModel.swift` owns model requests and the optional project-local runtime.

## Chrome extension (local prototype)

The `extension/` directory contains an unpacked Manifest V3 companion using the same local Qwen3 model via a narrowly scoped native messaging host. Standard browser fields have inline corrections; Google Docs has an experimental visible-text adapter plus selection checking and copy-back. Automatic activation is available with optional website permission, and individual sites can be excluded. See [extension setup and limitations](extension/README.md).
