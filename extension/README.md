# LocalWriter Chrome — local prototype

This Manifest V3 extension uses the same Qwen3 client and UTF-16 corrections as the Mac app through Chrome Native Messaging. It requests access to the active tab only when you enable it; it has no all-sites permission, remote code, analytics, or cloud inference.

## Install

Pour toutes les étapes sur un nouveau Mac et la procédure de mise à jour, voir le [guide d’installation en français](../docs/INSTALLATION.fr.md).

1. Build the app with `scripts/build-app.sh`. Keep LocalWriter and its local model running.
2. Register the narrowly scoped native host with `python3 scripts/install-extension-host.py`. This writes one per-user host manifest allowing only this extension's stable ID. It installs a bridge executable and launcher under `~/Library/Application Support/LocalWriter/NativeMessaging/`, outside protected Documents/Desktop folders.
3. Open `chrome://extensions`, turn on Developer mode, choose **Load unpacked**, and select this `extension` directory.
4. Open LocalWriter from Chrome's Extensions menu. It should report **Connected to LocalWriter on your Mac**.
5. Choose **Open practice editors** to test native messaging, analysis, underlines and replacement end-to-end.

The public manifest key keeps the unpacked extension ID stable. No private signing key is stored. Rerun host registration after rebuilding the app to update the installed bridge. The installed bridge does not depend on the checkout location. A fresh machine also needs Ollama/Qwen3 installed as described in the root README.

## Ordinary web editors

Click **Enable underlines on this tab**, then focus a textarea, text input, or contenteditable editor. Pause typing, hover or click a red underline, then click the replacement card. Enablement lasts until reload. **Disable underlines on this tab** stops analysis and clears marks. Restricted Chrome pages cannot be enabled.

To avoid duplicate native and browser underlines, use the Mac menu's **Disable for Google Chrome** while testing the extension. Native apps such as Slack and Notes continue to use LocalWriter normally.

Passwords, non-text input types, readonly and disabled fields are excluded. Drafts are limited to 4,000 UTF-16 units. Framework-managed editors can reject DOM replacements; the extension verifies the result instead of claiming success. Shadow-root editors and cross-origin frames without granted access are not supported.

## Google Docs — experimental inline adapter

Choose **Enable underlines on this tab** in a Google Doc. The separate Docs adapter reads positioned SVG text annotations and checks visible text (up to 4,000 UTF-16 units). It measures word advances against the annotation bounds, updates on document mutation/scroll/resize, and uses the same local model and suggestion cards. It never treats Docs’ invisible typing iframe as the document value.

Replacement first selects the displayed range, asks Docs’ copy handler to confirm the exact selected text using an in-memory clipboard event, then sends the replacement through its paste handler. It leaves the system clipboard alone, aborts if the selection or document differs, and verifies the resulting text. Inline spelling and grammar replacements have been verified in a live Chrome Google Doc; the presence of annotations and support for clipboard events can vary. If text annotations are absent, the adapter reports that limitation. It does not enable or impersonate another extension.

Select a phrase with the mouse or keyboard and pause to request a whole-selection rewrite. The card shows the proposed wording and replaces the full selection when clicked. Changing the selection or document invalidates the proposal. Selections must currently match a unique phrase within the visible text; repeated or offscreen selections are rejected safely. This new selection workflow still needs live validation after reloading the extension.

Only currently rendered visible text is analyzed, so scrolling may change the checked context. Complex layouts and scripts other than English are not verified. Reloading the document requires enabling LocalWriter again.

Select text and use **Use selected text** in the extension panel, or right-click and choose **Check with LocalWriter**. If Docs does not expose the selection, copy it and paste it into the panel. Choose **Check text** or **Improve wording**, then click the resulting card to copy it and paste it over the selection in Docs. The panel never automatically changes the document.

Only the text submitted for checking goes to the local native bridge. Context-menu selections are held temporarily in Chrome's in-memory session storage until the review page consumes them. No document text is stored in persistent extension storage or logged by the host. Copying a suggestion intentionally replaces the clipboard.

## Checks

- `node scripts/check-extension.mjs`: Unicode offsets, stale edits and overlapping corrections.
- `python3 scripts/check-extension.py`: native framing, input validation, actual Qwen3 correction.
- `node --check extension/{background,content,popup,core}.js` (run separately for each file).
- **Open practice editors**: manual live Chrome check; automated protocol tests alone do not verify UI installation or third-party compatibility.

## Uninstall

Remove LocalWriter from `chrome://extensions`. Delete only `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.johnbgood.localwriter.json` to revoke its native messaging registration. Delete `~/Library/Application Support/LocalWriter/NativeMessaging/` to remove its installed executable and launcher. Other native hosts are unaffected.
