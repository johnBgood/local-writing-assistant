# Delivery workflow

The maintainer requests that every completed app or extension correction is also published to GitHub with updated downloads. After relevant checks pass:

- Increment the app and extension versions together, and increment the app build number.
- Update download links in README.md, docs/TESTERS.md, docs/INSTALLATION.fr.md and extension/README.md.
- Build using scripts/build-app.sh and package using scripts/package-testers.py. Preserve the existing local signing identity.
- Commit and push the changes, then create a GitHub prerelease targeting the full commit SHA with the DMG, extension ZIP, START-HERE.md and SHA256SUMS.txt.
- Verify all release assets uploaded successfully before reporting publication complete.

Repository: johnBgood/local-writing-assistant. Do not publish local preferences, private drafts, model files or signing credentials. If publishing fails, report what remains unpublished.
