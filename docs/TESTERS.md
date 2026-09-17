# LocalWriter 0.4.0 — tester setup

This beta supports **Apple Silicon Macs (M1/M2/M3/M4), macOS 14 or later**. The included app is arm64; it does not run on Intel Macs. It checks English, French and German locally using Qwen3 4B. No Git checkout, Python, Xcode or Apple developer tools are needed.

## What to download

- `LocalWriter-0.4.0-arm64-beta.dmg`: the Mac app, these instructions and the extension ZIP.
- `LocalWriter-Chrome-0.4.0.zip`: also available separately for convenience.

This is a **ad-hoc-signed, unnotarized beta**, not a production-signed release. macOS may block the first launch. If you trust the sender and intended to install this beta, Apple's documented process is to try opening it, then use **System Settings → Privacy & Security → Open Anyway**. Managed Macs may not permit this. Do not disable Gatekeeper or install a root certificate. See https://support.apple.com/en-us/102445.

## 1. Install the local model

1. Install Ollama from https://ollama.com/download/mac and launch it.
2. Open Terminal and run:

   ```sh
   ollama pull qwen3:4b
   ```

3. Leave Ollama running while using LocalWriter. The initial model download needs Internet and several gigabytes of disk space; the model is **not bundled in the DMG**. Subsequent analysis runs on this Mac via `127.0.0.1:11434`.

## 2. Install the Mac app

1. Open the DMG and drag **LocalWriter.app** onto **Applications**.
2. Launch LocalWriter from Applications, not from the mounted DMG.
3. Find **✎** in the menu bar. There is no Dock window or automatic login startup.
4. Choose **Grant Accessibility Access…** and enable LocalWriter in **System Settings → Privacy & Security → Accessibility** for Slack, Notes and other native editors.
5. Choose **Open Practice Editor** and try `This is a speling mistake.` Click the suggestion to replace the word. Select a phrase to request a whole-phrase rewrite.

The app's **Start Local Model** action currently starts the repository-local runtime used by the developer. On a tester installation, launch the separate **Ollama app** as described above.

## 3. Connect and install the Chrome extension

1. From LocalWriter's **✎** menu, choose **Install Chrome Bridge…**, then **Install**. This copies the native bridge into your user Application Support folder and allows only this LocalWriter extension to launch it. No administrator password is needed.
2. Extract `LocalWriter-Chrome-0.4.0.zip` into a permanent folder, such as `~/LocalWriter-Chrome`. If using the ZIP from the DMG, copy it to the Mac before extracting. **Keep the extracted folder** while the extension is installed.
3. Open `chrome://extensions`, turn on **Developer mode**, choose **Load unpacked**, and select the extracted folder containing `manifest.json`.
4. Open **LocalWriter** from Chrome's Extensions menu. Check for **Connected to LocalWriter on your Mac**.
5. Click **Enable automatically on websites** and approve Chrome's website-access request if you want checking in all tabs. Alternatively, enable individual tabs manually.
6. **Disable for [site]** excludes a site. Internal Chrome pages are not supported.
7. In the Mac app menu, use **Disable for Google Chrome** while using the extension, to avoid duplicate overlays.

This extension is loaded unpacked for testing; it is not published in the Chrome Web Store. Do not try to drag the ZIP into Chrome as a packaged extension. Its expected ID is `pkcahnmnafkepdcfepmbnboaadnbkhnl`.

## Languages and dictionary

Choose **Language** in the Mac menu or **Writing language** in Chrome: Automatic, English, Français or Deutsch. Add a word using **Add to dictionary** in a correction card, or **Personal dictionary** in the menu/popup. Remove words there too. Settings and dictionary are shared locally between the app and extension.

## Suggested tests

- English: `She go to work yesterday.`
- French: `Je suis aller au bureau hier.`
- German: `Ich habe gestern ein Buch gelest.`
- In a disposable Google Doc, select a full sentence, review the suggestion and click to replace it.
- Add a custom word to the dictionary, then check that nearby grammar is still corrected.
- Try undo, scrolling, changing a selection during analysis, and excluding a site.

Review suggestions before accepting them. Google Docs support is experimental and currently checks visible text up to 4,000 UTF-16 units. Repeated or offscreen selections may be refused. App compatibility depends on exposed accessibility information. Whole-selection replacement in Google Docs has a recent fix that still needs broader live testing.

When reporting a problem, include app/extension version, macOS version, editor/browser, language, and a **non-sensitive** example sentence. The Mac menu has **Editor Diagnostics…**. Do not send private documents or messages as test samples.

## Updating

1. Quit LocalWriter from **✎ → Quit LocalWriter**.
2. Replace the app in Applications with the newer version; launch it.
3. Run **Install Chrome Bridge…** again to update Chrome's installed copy.
4. Replace the extracted extension files, click **Reload** on LocalWriter's card in `chrome://extensions`, then reload editor tabs. If the folder moved, remove the old extension and load the new folder.
5. Automatic activation resumes where permitted; manually enabled tabs need reactivation.

## Troubleshooting and removal

- **Model unavailable:** launch Ollama and make sure `ollama pull qwen3:4b` completed.
- **Native host exited / not found:** rerun **Install Chrome Bridge…** from the installed app. Keep the bridge in Application Support.
- **Accessibility checked but not working:** quit the app, remove its stale Accessibility entry and add the current Applications copy. Do not grant access to an old copy on the DMG.
- **Old behavior after update:** reload both the extension and the document.

To remove: quit and delete the app; remove LocalWriter in `chrome://extensions`; delete only `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.johnbgood.localwriter.json` and `~/Library/Application Support/LocalWriter/NativeMessaging/`. Preferences remain in `~/Library/Application Support/LocalWriter/preferences.json` unless you remove them. Ollama and its models are separate installations.
