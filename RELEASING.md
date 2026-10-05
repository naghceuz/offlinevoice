# Releasing OfflineVoice (macOS)

The complete checklist for shipping a new version to **all** channels: the
website download, GitHub Releases, and the docs. Follow it top to bottom.

## 0. One-time setup (per machine)

These live in the login keychain of the Mac that releases, so they persist
between releases but are **lost when you move to a new Mac** (private keys
never leave the machine). On a fresh machine, redo both before step 4:

- **Developer ID certificate** (login keychain):
  `Developer ID Application: Guanchen Zhang (H6E9M3Z7YM)`
  Check with `security find-identity -v -p codesigning`. If missing, create a
  new one in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ "+" ▸
  Developer ID Application (the old one stays valid for already-shipped builds).
- **Notarization credentials** (login keychain, stored once via
  `xcrun notarytool store-credentials`): profile name **`OfflineVoice-Notary`**.
  Verify it's alive with:
  ```bash
  xcrun notarytool history --keychain-profile "OfflineVoice-Notary"
  ```
  Only if that errors do you need to re-store credentials (README →
  "Signing & notarizing for public distribution").
- **Vercel CLI login + project link** (gitignored `website/.vercel/`): on a fresh
  machine `cd website && npx vercel login && npx vercel link` to re-attach the
  `owens-projects-ba5444b1/website` project. The website no longer hosts the
  DMG (see step 6/7), so there is nothing else to restore.

## 1. Bump the version

Edit `project.yml` (macOS target only, three spots):

- `info.properties.CFBundleShortVersionString`
- `settings.base.MARKETING_VERSION`
- `settings.base.CURRENT_PROJECT_VERSION` (increment by 1)

Then fetch/verify the bundled speech model and regenerate the Xcode project +
Info.plist (the model directory must exist before XcodeGen runs):

```bash
./scripts/fetch-models.sh   # no-op when the pinned files are already verified
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
`dist/release/OfflineVoice-mac.dmg` (≈ 185 MB: the SenseVoice model is inside
the app). Notarization waits on Apple and typically takes a few minutes. Verify:

```bash
xcrun stapler validate dist/release/OfflineVoice-mac.dmg
```

## 5. Commit & push

Commit source + docs, then push `main`. The DMG itself is **gitignored**
(`dist/`); it reaches users only as a GitHub Release asset (step 6).

## 6. GitHub Release

```bash
git tag vX.Y.Z && git push origin vX.Y.Z
gh release create vX.Y.Z \
  dist/release/OfflineVoice-mac.dmg \
  dist/release/OfflineVoice-mac.dmg.sha256 \
  --title "OfflineVoice vX.Y.Z" \
  --notes-file RELEASE_NOTES.md
```

**This step is what ships the download.** `www.offlinevoice.ai/api/download`
counts the click and redirects to
`github.com/naghceuz/offlinevoice/releases/latest/download/OfflineVoice-mac.dmg`,
which always resolves to the newest release — no website deploy is needed for
users to get the new build. Mark the release as the latest (the default).

## 7. Deploy the website (only if the site itself changed)

The site does not serve the DMG any more, so this is only needed when
`website/` changed (copy, version string in the footer, …). Production deploys
go through the Vercel CLI from `website/`:

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
