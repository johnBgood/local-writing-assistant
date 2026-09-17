# LocalWriter Chrome — local prototype

This Manifest V3 extension uses the same Qwen3 client and UTF-16 corrections as the Mac app through Chrome Native Messaging. It requests access to the active tab only when you enable it; it has no all-sites permission, remote code, analytics, or cloud inference.

## Install

1. Build the app with `scripts/build-app.sh`. Keep LocalWriter and its local model running.
2. Register the narrowly scoped native host with `python3 scripts/install-extension-host.py`. This writes one per-user host manifest allowing only this extension's stable ID. It also writes the launcher to ignored `dist/`.
3. Open `chrome://extensions`, turn on Developer mode, choose **Load unpacked**, and select this `extension` directory.
4. Open LocalWriter from Chrome's Extensions menu. It should report **Connected to LocalWriter on your Mac**.
5. Choose **Open practice editors** to test native messaging, analysis, underlines and replacement end-to-end.

The public manifest key keeps the unpacked extension ID stable. No private signing key is stored. The Mac app must remain in this checkout's `dist/`; rerun host registration after moving the checkout. A fresh machine also needs Ollama/Qwen3 installed as described in the root README.

## Ordinary web editors

Click **Enable underlines on this tab**, then focus a textarea, text input, or contenteditable editor. Pause typing, hover or click a red underline, then click the replacement card. Enablement lasts until reload. **Disable underlines on this tab** stops analysis and clears marks. Restricted Chrome pages cannot be enabled.

To avoid duplicate native and browser underlines, use the Mac menu's **Disable for Google Chrome** while testing the extension. Native apps such as Slack and Notes continue to use LocalWriter normally.

Passwords, non-text input types, readonly and disabled fields are excluded. Drafts are limited to 4,000 UTF-16 units. Framework-managed editors can reject DOM replacements; the extension verifies the result instead of claiming success. Shadow-root editors and cross-origin frames without granted access are not supported.

## Google Docs — selection workflow only

**Automatic inline Google Docs underlines/replacement are not implemented.** Its canvas editor and invisible input cannot safely use the generic adapter.

Select text and use **Use selected text** in the extension panel, or right-click and choose **Check with LocalWriter**. If Docs does not expose the selection, copy it and paste it into the panel. Choose **Check text** or **Improve wording**, then click the resulting card to copy it and paste it over the selection in Docs. The panel never automatically changes the document.

Only the text submitted for checking goes to the local native bridge. Context-menu selections are held temporarily in Chrome's in-memory session storage until the review page consumes them. No document text is stored in persistent extension storage or logged by the host. Copying a suggestion intentionally replaces the clipboard.

## Checks

- `node scripts/check-extension.mjs`: Unicode offsets, stale edits and overlapping corrections.
- `python3 scripts/check-extension.py`: native framing, input validation, actual Qwen3 correction.
- `node --check extension/{background,content,popup,core}.js` (run separately for each file).
- **Open practice editors**: manual live Chrome check; automated protocol tests alone do not verify UI installation or third-party compatibility.

## Uninstall

Remove LocalWriter from `chrome://extensions`. Delete only `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.johnbgood.localwriter.json` to revoke its native messaging registration. Other native hosts are unaffected.
