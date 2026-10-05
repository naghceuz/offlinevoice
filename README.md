# OfflineVoice

<p align="center">
  <img src="assets/banner.png" alt="OfflineVoice — the fastest local voice dictation for Mac" width="100%">
</p>

OfflineVoice is the fastest local voice dictation for Mac. Hold one hotkey and speak, transcription runs entirely on your machine, and the text is pasted straight into the focused input field. Because nothing leaves your Mac, it is both faster and more private than tools that depend on the cloud.

No cloud. No account. No subscription. Your audio and text never leave the device. **Free and open source (GPL-3.0).**

<p align="center">
  <a href="https://www.offlinevoice.ai/api/download">
    <img src="https://img.shields.io/badge/Download%20for%20Mac-.dmg-ffd000?style=for-the-badge&logo=apple&logoColor=black&labelColor=1a1a1a" alt="Download for Mac">
  </a>
  &nbsp;
  <a href="https://www.offlinevoice.ai">
    <img src="https://img.shields.io/badge/Website-offlinevoice.ai-1a1a1a?style=for-the-badge" alt="Website">
  </a>
</p>

<p align="center">
  <sub>macOS 13+ · Apple Silicon · signed &amp; notarized — just double-click to open.</sub>
</p>

```text
Hold key → on-device ASR → paste
```

> One click: **[⬇ Download OfflineVoice for Mac (.dmg)](https://www.offlinevoice.ai/api/download)** — or build from source below.

The current repo contains two deliverables:

- `OfflineVoice.app`: the macOS Dock app with a menu-bar status icon.
- `website/`: the public landing page with a real Download for Mac button.

## What Works Today

- Local macOS app build through Xcode.
- Branded App icon, Dock-visible app shell, and menu-bar status icon.
- First-run onboarding for positioning, permissions, and the hotkey.
- Main window with Home, Settings, Shortcuts, Privacy & Local AI, and About pages.
- Global push-to-talk with default `Right Option`, editable from the app UI.
- Microphone and Accessibility permission status with settings shortcuts (Speech Recognition is only requested by Native mode).
- Three on-device recognition modes you choose from the Speed & Accuracy page:
  - **Speed** (default): SenseVoiceSmall, bundled inside the app. One model that detects Chinese (Mandarin and Cantonese), English, Japanese and Korean by itself — including mixed Chinese/English in a single sentence — with punctuation. Nothing to download, nothing to configure.
  - **Accuracy**: Whisper (large-v3 turbo), an alternative for English and technical or specialized content. The model downloads once to your machine on first use, then works offline.
  - **Native**: Apple's built-in on-device recognizer. No model files, but it is bound to your Mac's system language and cannot follow a language switch.
- Works in any app: the recognized text is pasted into the focused input field.
- Website landing page for the "fastest local voice dictation for Mac" positioning.
- Website download button goes through `/api/download` (counted) and redirects to the latest GitHub Release asset.
- DMG packaging script: a Developer ID build is written to `dist/release/` for `gh release create`, while an unsigned local build goes to `dist/local-preview/`.

## Requirements

- macOS 13+
- Xcode
- Node.js 20+ for the website
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to regenerate `OfflineVoice.xcodeproj` from `project.yml`
- `scripts/fetch-models.sh` once per checkout: it downloads the pinned SenseVoice model (228 MB, SHA-256 verified) into the gitignored `Resources/models/` folder that gets bundled into the app. See `Resources/SenseVoice-NOTICE.md` for the model's provenance and licence.

Speed mode's model ships inside the app, so nothing is downloaded at runtime. Accuracy mode downloads the Whisper model on first use and caches it locally for offline use afterwards. Native mode needs no files but only recognizes the system language.

## Local Website Development

```bash
cd website
npm install
npm run dev
```

Open the printed local URL. The Download for Mac button points to:

```text
/downloads/OfflineVoice-mac.dmg
```

In development this resolves to:

```text
website/public/downloads/OfflineVoice-mac.dmg
```

## Build the Website

```bash
cd website
npm run build
```

The static site is emitted to `website/dist/`.

## Deploy the Website

The current Vercel project is `owens-projects-ba5444b1/website`.

```bash
npx vercel deploy --prod --cwd website --scope owens-projects-ba5444b1 --yes
```

Public preview:

```text
https://website-owens-projects-ba5444b1.vercel.app
```

## Build the Mac App

```bash
./scripts/fetch-models.sh   # once; verifies the bundled speech model
xcodegen generate
xcodebuild \
  -project OfflineVoice.xcodeproj \
  -scheme OfflineVoice \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  build
```

The app is created at:

```text
build/Build/Products/Release/OfflineVoice.app
```

If you only changed Swift files, `xcodegen generate` is usually not required. Run it after changing `project.yml`, assets, bundle settings, package dependencies, or Info.plist generation settings. The model folder must exist before XcodeGen runs (it is a folder reference), which is why `fetch-models.sh` comes first.

## Generate the Installer DMG

Run the packaging script from the repo root:

```bash
./scripts/package-mac.sh
```

The script:

1. Builds the Release app.
2. Copies `OfflineVoice.app` into a DMG staging folder.
3. Adds the OfflineVoice DMG volume icon when available.
4. Ad-hoc signs the staged app for local testing.
5. Creates the downloadable DMG.
6. Writes a SHA-256 checksum next to it.

Generated files:

```text
website/public/downloads/OfflineVoice-mac.dmg
website/public/downloads/OfflineVoice-mac.dmg.sha256
```

## Update the Website Download

To publish a new local website download:

```bash
./scripts/package-mac.sh
cd website
npm run build
```

Deploy or serve `website/dist/`. Vite copies `website/public/downloads/OfflineVoice-mac.dmg` into the built site automatically.

## Public Trial Checklist

Before sending a link to another Mac user:

```bash
./scripts/package-mac.sh
cd website
npm run build
npm run dev
```

Then verify:

1. Open the local website.
2. Click **Download for Mac** and confirm it redirects to the GitHub Release DMG.
3. Open the DMG and drag `OfflineVoice.app` to Applications, or open it from the mounted image for a quick smoke test.
4. Approve any macOS security prompts on first launch.
5. Approve Microphone access.
6. Use the menu-bar icon to open Accessibility settings if needed, then enable OfflineVoice.
7. Put the cursor in any input field, hold `Right Option`, speak, and release.

## First-Run Permissions

OfflineVoice is a Dock-visible Mac app with an optional menu-bar status icon.

Nothing is requested at launch. Onboarding asks for the two permissions one after the other, each on its own screen, and moves on by itself once a permission is granted; neither can be skipped because the app does not work without them.

1. Open `OfflineVoice.app`.
2. **Microphone** screen: the macOS prompt appears on its own — click *Allow*.
3. **Accessibility** screen: the macOS prompt appears on its own — choose *Open System Settings*, turn OfflineVoice on, and come back; the screen continues automatically. (If a prompt was dismissed, the screen offers an *Open … Settings* button, since macOS only shows each prompt once.)
4. Confirm the default shortcut or record a new one.
5. Put the cursor in any text field, hold the shortcut, speak, and release.

Microphone access is required for transcription (Native mode additionally asks for Speech Recognition access). Accessibility is required for the global push-to-talk key and automatic paste.

## App Settings

OfflineVoice v0.5.1 stores user settings at:

```text
~/.config/offlinevoice/config.json
```

The app UI manages:

- First-run onboarding completion.
- Launch at login.
- Menu-bar icon visibility.
- Auto paste and clipboard restore behavior.
- Primary dictation shortcut.
- Recognition mode (Speed or Accuracy) and the Whisper model used in Accuracy mode.

Switching recognition mode reloads the transcription engine in place — no restart needed. The next dictation simply waits for the new engine to finish loading.

## Signed & Notarized Distribution

Public OfflineVoice builds are signed with a Developer ID certificate and notarized by Apple, so the DMG opens with a simple double-click and no Gatekeeper warning.

Local builds you produce yourself without signing credentials are ad-hoc signed for testing only. If macOS blocks an unsigned local build:

1. Right-click `OfflineVoice.app` and choose **Open**, then confirm **Open** in the dialog.
2. Or open **System Settings ▸ Privacy & Security** and click **Open Anyway**.
3. You only need to do this once.

### Signing & notarizing for public distribution

`scripts/package-mac.sh` produces an ad-hoc DMG by default. To ship a signed,
notarized DMG that opens without any Gatekeeper prompt, you need an Apple
Developer Program membership and a **Developer ID Application** certificate in
your keychain, then store notary credentials once:

```bash
xcrun notarytool store-credentials "OfflineVoice-Notary" \
  --apple-id <apple-id> --team-id <TEAMID> --password <app-specific-password>
```

Then run the packager with both env vars set — it signs with the Hardened
Runtime + entitlements, notarizes, and staples the ticket:

```bash
DEVELOPER_ID_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="OfflineVoice-Notary" \
  ./scripts/package-mac.sh
```

Setting only `DEVELOPER_ID_IDENTITY` signs + verifies but skips notarization;
setting neither falls back to the ad-hoc build.

## Temporary Choices and Follow-Ups

- The public download is a GitHub Release asset; the website only counts and redirects.
- Translate and Ask Anything are visible as future shortcut modes but disabled in v0.5.1.
- Launch at login uses `SMAppService`.
- Switching recognition mode from the UI is persisted and reloads the engine in place.
- The website product preview is a designed placeholder until real screenshots or a screen recording are captured.
- A proper release flow should produce versioned artifacts, checksums, release notes, and notarized DMGs.
