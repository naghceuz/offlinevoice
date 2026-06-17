<div align="center">

<img src="assets/banner.png" alt="OfflineVoice" width="680">

# OfflineVoice

**Speak anywhere. Type nowhere.**
Private, offline voice input for your Mac.

[**↓ Download for Mac**](https://www.offlinevoice.ai/downloads/OfflineVoice-mac.dmg) · [offlinevoice.ai](https://www.offlinevoice.ai) · [Latest release](../../releases/latest)

</div>

---

Hold one key, talk, release — your speech becomes polished text in any app.
Transcription and cleanup run **entirely on your Mac**. No account, no
subscription, no cloud upload.

## Download

OfflineVoice is **signed with an Apple Developer ID and notarized by Apple**, so
it opens normally with no Gatekeeper warning.

- 🌐 **Official site:** https://www.offlinevoice.ai
- ⬇️ **Direct download (macOS):** [OfflineVoice-mac.dmg](https://www.offlinevoice.ai/downloads/OfflineVoice-mac.dmg)
- 📦 **GitHub release:** [Releases](../../releases/latest)

> Only download from these official channels.

## Screenshots

![OfflineVoice — speak anywhere, type nowhere](assets/hero.png)

![Works in every app](assets/apps.png)

![Local-first privacy](assets/privacy.png)

## Why OfflineVoice

- **100% local** — speech recognition (WhisperKit) and optional cleanup run on
  your Mac. Audio and text never leave the device.
- **Works in every app** — pastes into the focused field across native Mac apps.
- **Hold‑to‑talk** — hold **Right Option** (configurable), speak, release to paste.
- **Chinese + English** — built for Chinese, English, and mixed‑language dictation.
- **Per‑app tone & hotwords** — a writing tone per app, plus a local dictionary
  to fix recurring mis‑hears.
- **No account, no subscription.**

## System requirements

**Required**

- **Apple Silicon Mac (M1 or newer).** Intel Macs are not supported — on‑device
  transcription runs on the Apple Neural Engine / Metal via WhisperKit.
- **macOS 14 (Sonoma) or later.**
- **~2 GB free disk** — the local Whisper model is downloaded once on first use
  (~1.5 GB) and cached for offline use afterward.
- Internet access on first launch to download the model; fully offline after that.

**Recommended**

- **16 GB unified memory** for a comfortable experience, especially if you also
  run the optional Ollama cleanup. Dictation alone works on 8 GB.

**Optional**

- [Ollama](https://ollama.com) running `qwen2.5:7b-instruct` for filler‑word and
  punctuation cleanup. Without it you still get the raw local transcription.

## Install

1. Open the DMG and drag **OfflineVoice** to Applications, then launch it.
2. Grant **Microphone** and **Accessibility** when prompted (Accessibility is what
   lets OfflineVoice paste into other apps).
3. Hold **Right Option**, speak, release.

## FAQ

**Does it run on Intel Macs?**
No. OfflineVoice requires an Apple Silicon Mac (M1 or newer). Transcription runs
on the Apple Neural Engine, which Intel Macs don't have.

**Does it need the internet?**
Only once, to download the local model on first launch. After that the core
dictation loop runs fully offline.

**Is the download safe to open?**
Yes — it's signed with an Apple Developer ID and notarized by Apple, so it opens
with no Gatekeeper warning. Only download from the official channels above.

**Do I need Ollama?**
No. Ollama is optional and only used to clean up filler words and punctuation.
Without it you still get the raw local transcription.

**Which languages does it handle?**
Chinese, English, and mixed Chinese‑English dictation.

## Privacy

OfflineVoice does not upload your audio, does not sync transcripts, and does not
train on your data. Model files are cached locally after first download.
Full [privacy policy](https://www.offlinevoice.ai/#privacy-policy).

---

<div align="center">

Official channels only — **[offlinevoice.ai](https://www.offlinevoice.ai)** · GitHub Releases

</div>
