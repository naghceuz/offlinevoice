# Releasing OfflineVoice (macOS)

The complete checklist for shipping a new version to **all** channels: the
website download, GitHub Releases, and the docs. Follow it top to bottom —
every credential below is already set up on this Mac; nothing needs to be
re-created between releases.

## 0. One-time setup (already done — do NOT redo)

These exist on this machine and persist across releases:

- **Developer ID certificate** (login keychain):
  `Developer ID Application: Guanchen Zhang (H6E9M3Z7YM)`
- **Notarization credentials** (login keychain, stored once via
  `xcrun notarytool store-credentials`): profile name **`OfflineVoice-Notary`**.
  Verify it's alive with:
  ```bash
  xcrun notarytool history --keychain-profile "OfflineVoice-Notary"
  ```
  Only if that errors do you need to re-store credentials (README →
  "Signing & notarizing for public distribution").

## 1. Bump the version

Edit `project.yml` (macOS target only, three spots):

- `info.properties.CFBundleShortVersionString`
- `settings.base.MARKETING_VERSION`
- `settings.base.CURRENT_PROJECT_VERSION` (increment by 1)

Then regenerate the Xcode project + Info.plist:

```bash
xcodegen generate
```

## 2. Update docs & version strings

- `RELEASE_NOTES.md` — rewrite the title + "What's new in X.Y.Z" section
  (the rest of the file is evergreen boilerplate).
- `README.md` — two version references (search for the old version).
- `website/src/App.jsx` — footer version string.

## 3. Test

```bash
xcodebuild test -project OfflineVoice.xcodeproj -scheme OfflineVoice \
  -destination 'platform=macOS' -only-testing:OfflineVoiceTests
```

## 4. Build, sign, notarize, package

```bash
DEVELOPER_ID_IDENTITY="Developer ID Application: Guanchen Zhang (H6E9M3Z7YM)" \
NOTARY_PROFILE="OfflineVoice-Notary" \
  ./scripts/package-mac.sh
```

This writes the notarized, stapled DMG + `.sha256` to
`website/public/downloads/OfflineVoice-mac.dmg` (the file the website serves).
Notarization waits on Apple and typically takes a few minutes. Verify:

```bash
xcrun stapler validate website/public/downloads/OfflineVoice-mac.dmg
```

## 5. Commit & push

Commit source + docs, then push `main`. Note the DMG itself is **gitignored**
(`website/public/downloads/` — "built locally, not source"); it reaches users
via the Vercel deploy (step 7, which uploads local files regardless of
gitignore) and the GitHub Release assets (step 6), never via git.

## 6. GitHub Release

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
gh release create vX.Y.Z \
  website/public/downloads/OfflineVoice-mac.dmg \
  website/public/downloads/OfflineVoice-mac.dmg.sha256 \
  --title "OfflineVoice vX.Y.Z" \
  --notes-file RELEASE_NOTES.md
```

## 7. Deploy the website (serves the new DMG)

Production deploys go through the Vercel CLI from `website/` — this is the
step that actually updates what users download from offlinevoice.ai:

```bash
cd website && npx vercel --prod
```

Run this in a **regular Terminal window**, not inside an AI-agent session:
Vercel CLI ≥59 detects agent environments and rejects production deploys
with a misleading "Not authorized" (auth is actually fine — verify with
`npx vercel whoami` if unsure).

## 8. Post-release sanity check

- Download from https://www.offlinevoice.ai/api/download and confirm the DMG
  mounts and the app reports the new version.
- `gh release view vX.Y.Z` shows both assets.
