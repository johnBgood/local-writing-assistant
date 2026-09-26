# LocalWriter

An English, French and German writing assistant for macOS 14+, built with Swift and AppKit. **Qwen3 4B handles spelling, grammar, and sentence rewrites locally.** The app does not use macOS spellchecking or autocorrection.

## Download and install — no build required

**[Download the Mac app (DMG)](https://github.com/johnBgood/local-writing-assistant/releases/download/v0.4.7/LocalWriter-0.4.7-arm64-beta.dmg)** · **[Download the Chrome extension (ZIP)](https://github.com/johnBgood/local-writing-assistant/releases/download/v0.4.7/LocalWriter-Chrome-0.4.7.zip)** · [All releases](https://github.com/johnBgood/local-writing-assistant/releases)

The beta requires **an Apple Silicon Mac and macOS 14+**. No Git, Xcode, Python or compilation is needed.

1. Install [Ollama](https://ollama.com/download/mac), launch it once and run `ollama pull qwen3:4b` in Terminal. This one-time model download is separate from the app.
2. Open the DMG, drag **LocalWriter.app** into **Applications**, and launch it. The app starts Ollama and loads the model automatically on subsequent launches.
3. In the **✎** menu, choose **Grant Accessibility Access…** for native apps. Use **Open Practice Editor** to try a correction.
4. For Chrome, choose **Install Chrome Bridge… → Install** in the Mac app. Extract the extension ZIP into a permanent folder, open `chrome://extensions`, enable **Developer mode**, and use **Load unpacked** to select that folder.
5. Open the extension and choose **Enable automatically on websites**. In the Mac app, **Disable for Google Chrome** avoids duplicate underlines.

This beta is **not notarized**: macOS may require **System Settings → Privacy & Security → Open Anyway** after the first launch attempt. The Chrome extension is installed unpacked, not through the Chrome Web Store. The DMG also includes the extension ZIP and setup guide.

See the [full installation and troubleshooting guide](docs/TESTERS.md), or [instructions en français](docs/INSTALLATION.fr.md). Source-build instructions below are optional.

## Build and run from source

Requirements: **macOS 14+**, a **Swift 6 or newer toolchain** (recent Xcode Command Line Tools), Git and Python 3. Apple Silicon is the tested platform. Node.js is optional for extension tests. Install the Apple tools with `xcode-select --install` if needed; check your toolchain with `swift --version`.

1. Install [Ollama for macOS](https://ollama.com/download/mac) and launch it.
2. Clone the repository and download the local model:

   ```sh
   git clone https://github.com/johnBgood/local-writing-assistant.git
   cd local-writing-assistant
   scripts/setup-model.sh
   ```

3. Build and launch the menu-bar app:

   ```sh
   scripts/build-app.sh
   open dist/LocalWriter.app
   ```

After this one-time setup, LocalWriter automatically starts Ollama if needed and preloads Qwen3 when the app opens. The menu shows startup progress or a setup error; **✎ !** means the model needs attention. The first model download needs Internet and several gigabytes of disk space; model weights are not included in the repository. No paid API key is required. Run subsequent commands from the repository root.

LocalWriter appears as **✎** in the menu bar. To open its practice editor, use **Open Practice Editor**, or launch it with:

```sh
open dist/LocalWriter.app --args --practice
```

Voir aussi le [guide complet en français](docs/INSTALLATION.fr.md).

## Install the Chrome extension from source

The extension needs no npm install or JavaScript build step.

1. Build the Mac app above, then choose **✎ → Install Chrome Bridge… → Install**. Alternatively, run `python3 scripts/install-extension-host.py` from the repository root.
2. Open `chrome://extensions`, enable **Developer mode**, click **Load unpacked**, and select the repository's **extension** folder. Keep that folder on disk.
3. Open LocalWriter from Chrome's Extensions menu and check for **Connected to LocalWriter on your Mac**. Keep LocalWriter open when it manages the model server.
4. Choose **Open practice editors** to test a correction and replacement.
5. Click **Enable automatically on websites** and accept Chrome's website-access request to enable checking across tabs. You can exclude individual sites using **Disable for [site]**, or use manual activation instead.
6. In the Mac app menu, select **Disable for Google Chrome** to avoid duplicate native and extension underlines.

The bridge is installed in your user Application Support folder and allows only this extension's stable ID. It does not need an administrator password. Google Docs support is experimental. See [extension details and limitations](extension/README.md).

## Share a beta with testers

Share the [GitHub release page](https://github.com/johnBgood/local-writing-assistant/releases/tag/v0.4.7) with testers; it contains the DMG, extension ZIP, setup guide and checksums. See [tester installation instructions](docs/TESTERS.md). To generate your own packages from source:

```sh
scripts/build-app.sh
python3 scripts/package-testers.py
```

Packaging is intended for an Apple Silicon Mac. Output in `dist/testers/` includes an Apple Silicon DMG, an extension ZIP, `START-HERE.md` and `SHA256SUMS.txt`. Send testers the DMG (which also contains the extension ZIP and instructions), or share the ZIP separately. Release downloads are hosted as GitHub release assets, keeping binaries out of the source history.

The beta is ad-hoc-signed and **not notarized**. Ollama/Qwen3 must be installed separately. The Chrome extension is distributed unpacked and is not published in the Chrome Web Store.

## Using the app

The practice editor uses the same debounce, model analysis, underline overlay, hover panel, and acceptance workflow as external editors. It does not require macOS Accessibility permission. Its status line shows model progress and actionable failures. Hover a red underline to accept a correction; hover a sentence to request a rewrite.

For Slack, Codex, and other apps, click **✎ → Grant Accessibility Access…** and enable LocalWriter in System Settings → Privacy & Security → Accessibility. Focus the message editor and pause typing. The app requests Chromium/Electron accessibility trees when inspecting an editor.

The menu shows **Disable for Codex** when enabled and **Enable for Codex** when disabled, alongside the current state. It captures the app when the menu opens, so clicking the action cannot accidentally target a different app. Pause and resume also have distinct labels.

### Development signing

Fresh clones use ad-hoc signing. A rebuild can invalidate the previous macOS Accessibility grant. If diagnostics report missing access despite a checked box, quit LocalWriter, remove its old Accessibility entry, and add the current app.

For a stable local development identity, optionally run this after your first build:

```sh
python3 scripts/sign-app.py dist/LocalWriter.app --setup
scripts/build-app.sh
```

This creates a private local certificate and keychain in the Git-ignored `.local-signing/` directory; it does not install a trusted root certificate or provide Apple Developer ID signing/notarization. Subsequent builds reuse that identity. Grant Accessibility access to the final app. `python3 scripts/check-signing.py` verifies identity stability across two builds.

## Model and privacy

Ollama serves `qwen3:4b` at `127.0.0.1:11434`. If the Ollama app is not running, you can start the server in a terminal with `scripts/start-model.sh`; keep that terminal open. Do not start a second server on the same port.

An optional project-local runtime in `.local-runtime/` is supported, but is not included in Git or required by the source setup above. At launch, LocalWriter first reuses an existing server, otherwise starts the project-local runtime or an installed Ollama CLI (Applications, Homebrew or PATH). It checks that Qwen3 is downloaded and preloads it. **Start Local Model** retries after a setup error. Closing LocalWriter stops only the server it started; independently running Ollama is left alone. Keep LocalWriter open when the Chrome extension relies on its server. Automatic discovery of the project-local runtime requires keeping the app in `dist/`.

Draft analysis sends editor text to the loopback endpoint; rewrites send the selected text. Drafts are not written to app logs or persistent storage. Model downloads require Internet; inference does not. Signing material, model weights and build artifacts are excluded from Git.

## Update a source installation

Quit LocalWriter, then run:

```sh
git pull --ff-only
scripts/build-app.sh
python3 scripts/install-extension-host.py
open dist/LocalWriter.app
```

If you do not use Chrome, skip the bridge installation command. Otherwise, click **Reload** on LocalWriter's card in `chrome://extensions` and reload open editor tabs. The bridge uses an installed copy of the binary, so reinstall it after rebuilding. Automatic activation resumes on permitted sites; manually enabled tabs need reactivation.

## Languages and personal dictionary

The Mac menu **Language** and Chrome popup **Writing language** share one setting: automatic detection, English, Français or Deutsch. Language detection runs locally; corrections and rewrites preserve the original language. Mixed-language passages and very short fragments can be ambiguous.

Click **Add “… ” to dictionary** on a correction card, or use **Personal dictionary** in the Mac menu / Chrome popup to add or remove a word. Accepted words are protected during correction and rewriting; surrounding grammar can still be corrected. Preferences and words are saved locally in `~/Library/Application Support/LocalWriter/preferences.json`, shared by the app and native bridge. Changes take effect on the next check; refocus the browser tab after changing settings in the Mac menu.

`python3 scripts/check-multilingual.py` tests real model corrections and rewrites in all three languages plus dictionary protection with a neighboring grammar error. It temporarily changes language and adds a test word, then restores the previous settings.

## How corrections work

After a typing pause, the model returns conservatively corrected text in structured JSON. The app computes word-level differences and UTF-16 ranges locally. Accepting a correction requires the original editor and entire draft to still match the analyzed snapshot. Typing cancels outdated requests. Password fields and excluded apps are skipped.

Rich-list accessibility markers are excluded from model input and mapped back to original UTF-16 offsets. Sentence ranges exclude non-editable bullet glyphs; replacement falls back to a matching text child when an editor refuses a container-relative selection. Changes spanning removed list decorations are rejected.

Whitespace-only changes are ignored. Phrase corrections retain one replacement range while drawing separate underlines beneath their words, never across blank lines. Hovering a sentence highlights its words in blue and offers a meaning-preserving rewrite; accepting it replaces the complete sentence. Selecting text in a native editor also requests a rewrite automatically once the selection settles. The suggestion is invalidated when the selection, editor or draft changes. This requires the editor to expose its selected range through Accessibility.

Editor discovery uses shared accessibility roles and focused descendants, without app-specific editor branches. Ambiguous or incomplete container searches do not select an arbitrary editor.

Rich editors can advertise word bounds but return zero-sized rectangles. LocalWriter then maps their static text descendants back to the draft (allowing whitespace paragraph separators) and queries those text ranges. Mismatched text and whole-editor rectangles are rejected.

The practice editor applies edits through NSTextView with undo support. External editors use an exact, verified selection followed immediately by a targeted Command-V paste. Rich lists prefer the matching text child to avoid slow or ineffective container selections. LocalWriter rechecks the editor, draft and selection before pasting, then verifies the resulting text. The previous clipboard formats are restored unless a newer clipboard copy has occurred. No Return key is sent. Changes are reported as successful only after the resulting draft matches the expected text.

## Limits

- Chrome's standard textarea and Slack's rich composer have been verified with a live model correction and precise word coordinates. Codex compatibility still needs verification. Detection, word coordinates, and selected-text replacement depend on what each editor exposes.
- Missing permissions, unreadable fields, missing word coordinates, model failures, and disabled apps are reported in the menu instead of silently appearing to work.
- External drafts are limited to 4,000 UTF-16 code units. Sentence hover uses individual word positions across lines; editors must expose accurate range geometry.
- Model suggestions are fallible and are applied only when explicitly accepted.
- Native Google Docs canvas integration is unavailable; the Chrome companion has an experimental separate adapter.
- No launch-at-login registration, notarization, or automatic model-download UI yet.

## Development and checks

No third-party Swift dependencies. Command Line Tools with Swift 6 or newer are sufficient. Core checks run without the model; model/editor checks require Ollama and Qwen3.

```sh
scripts/check.sh
scripts/check-runtime.sh
scripts/check-overlay.sh
scripts/build-app.sh
dist/LocalWriter.app/Contents/MacOS/LocalWriter --check-model
dist/LocalWriter.app/Contents/MacOS/LocalWriter --check-editor
dist/LocalWriter.app/Contents/MacOS/LocalWriter --practice-check
```

- `scripts/check-runtime.sh`: isolated startup, server reuse, missing model/installation and warmup failure checks. `dist/LocalWriter.app/Contents/MacOS/LocalWriter --check-runtime` verifies startup and preload against the real local installation.
- `CoreChecks`: Unicode ranges, stale edits, word differences including insertions and deletions, and app enable/disable states.
- `--check-editor`: real-model spelling and grammar, native word coordinates, overlay visibility, acceptance, and stale-edit rejection.
- `--practice-check`: opens a synthetic practice draft and exercises the running background loop, checks rendered red underline pixels, and accepts a correction. Requires the local model server; closes the test app afterward.
- `--scroll-check`: scrolls the native practice editor and verifies geometry redraw within 120 ms, independent of model analysis. Native wheel/trackpad scrolling uses a temporary 30 Hz geometry refresh instead of the idle polling interval.
- `--selection-check`: verifies automatic selected-text rewriting and full-range acceptance in the native practice editor with the real local model.
- `--check-clipboard`: uses an isolated test pasteboard to verify preservation of text and binary formats and that newer clipboard copies are not overwritten.
- **Editor Diagnostics…** reports Accessibility metadata without editor text. `--diagnose` also exposes this for development.
- Use `open -n -g dist/LocalWriter.app --args --probe-editor --app com.google.Chrome --report /tmp/localwriter-probe.txt` for a targeted, text-free geometry/model diagnostic. LaunchServices preserves the app's Accessibility identity; a direct shell invocation may inherit different permission attribution.

`WritingCore` owns edit validation, word differences, sentence ranges, and app availability state. `Accessibility.swift` adapts native and external editors. `Overlay.swift` draws underlines and suggestion panels. `App.swift` coordinates menus, debounce, hover, and asynchronous checks. `LocalModel.swift` owns model requests and the optional project-local runtime.

## Chrome extension (local prototype)

The `extension/` directory contains an unpacked Manifest V3 companion using the same local Qwen3 model via a narrowly scoped native messaging host. Standard browser fields have inline corrections; Google Docs has an experimental visible-text adapter plus selection checking and copy-back. Automatic activation is available with optional website permission, and individual sites can be excluded. See [extension setup and limitations](extension/README.md).

### Sentence rewriting

Sentence suggestions ask the local model for clearer, more concise wording, even when the grammar is correct. Automatic underlines still focus on spelling and grammar. If a rewrite only changes spacing, capitalization or punctuation, LocalWriter retries once and then reports that no useful rewording was found instead of offering the same text as a replacement. Model quality can vary; review suggestions before accepting them.

Run `python3 scripts/check-rewrites.py` after building with Ollama running to check real-model rewrites in English, French and German.
