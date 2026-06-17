# OfflineVoice v0.2.0

**Speak anywhere. Type nowhere.** Private, offline voice input for your Mac.

OfflineVoice turns your speech into polished text in any app — hold one key, talk,
release, and the text is pasted at your cursor. Transcription and cleanup run
entirely on your Mac. No account, no subscription, no cloud upload.

🔗 **Website:** https://www.offlinevoice.ai
⬇️ **Download:** [OfflineVoice-mac.dmg](https://www.offlinevoice.ai/downloads/OfflineVoice-mac.dmg)

---

## Highlights

- **100% local** — speech recognition (WhisperKit) and optional cleanup (Ollama) run
  on-device. Your audio and text never leave your Mac.
- **Works in every app** — pastes into the focused text field across native Mac apps.
- **Hold-to-talk** — hold **Right Option** (configurable), speak, release to paste.
- **Chinese + English** — built for Chinese, English, and mixed-language dictation.
- **Per-app tone & hotwords** — pick a writing tone per app and fix recurring
  mis-hears with a local dictionary.
- **Signed & notarized** — opens normally, no Gatekeeper warning.

## What's new in 0.2

- Dock-visible app with a menu-bar status icon and a guided first-run onboarding.
- Full main window: Home, Settings, Shortcuts, Privacy & Local AI, Dictionary,
  Personalization, About.
- Configurable hold-to-talk key (dropdown picker with Confirm).
- Live engine/model switching — no restart needed.
- Clear handling when Accessibility isn't granted yet: your dictation is copied to
  the clipboard (press ⌘V) with an in-app prompt to enable auto-paste.
- Developer ID signing + Apple notarization.
- Reliability fixes: state guards against rapid key presses, safe clipboard restore,
  model-load error surfacing with retry.

## Requirements

- **Apple Silicon Mac (M1 or newer)** — Intel Macs are not supported.
- **macOS 14 (Sonoma) or later.**
- **~2 GB free disk** — the local Whisper model is downloaded once on first use
  (~1.5 GB) and cached for offline use afterward.
- *Recommended:* 16 GB unified memory (8 GB works for dictation alone).
- *(Optional)* [Ollama](https://ollama.com) running `qwen2.5:7b-instruct` for
  filler-word/punctuation cleanup. Without it, you get the raw local transcription.

## Install

1. Download and open the DMG, drag **OfflineVoice** to Applications, and launch it.
2. Grant **Microphone** and **Accessibility** when prompted (Accessibility is what
   lets OfflineVoice paste into other apps).
3. Hold **Right Option**, speak, release.

## Known limitations

- Translate and Ask Anything are future modes, disabled in v0.2.
- This is an early preview — feedback welcome.

## Privacy

OfflineVoice does not upload your audio, does not sync transcripts, and does not
train on your data. Model files are cached locally after first download.
See the [privacy policy](https://www.offlinevoice.ai/#privacy-policy).
