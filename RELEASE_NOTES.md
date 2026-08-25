# OfflineVoice v0.4.0

**The fastest local dictation for Mac.** Private, offline voice input — now near-instant.

OfflineVoice turns your speech into text in any app — hold one key, talk, release, and
the text is pasted at your cursor. Because it runs entirely on your Mac, it's faster
*and* more private than cloud-based tools. No account, no subscription, no cloud upload.

🔗 **Website:** https://www.offlinevoice.ai
⬇️ **Download:** [OfflineVoice-mac.dmg](https://www.offlinevoice.ai/downloads/OfflineVoice-mac.dmg)

---

## What's new in 0.4.0

**Punctuation that follows your voice.** Long dictations used to come out as one
unbroken wall of text — hard to read, awkward to send to anyone. Now OfflineVoice
listens to the natural pauses in your speech and punctuates accordingly:

- **Speak naturally, get real sentences.** A short breath becomes a comma; a longer
  pause between thoughts becomes a period (with the next word capitalized in English,
  full-width 「，」「。」 in Chinese). No need to say "comma" or "period" out loud.
- **Still instant.** This is pure arithmetic over word timings the recognition engine
  already produces — no extra model, no post-processing pass, no added latency. The
  hold-to-talk → release → paste flow is exactly as fast as before.
- **Works in both modes.** Speed (Apple on-device) and Accuracy (Whisper) both get
  pause-aware punctuation, and it never doubles up marks the engine already placed —
  numbers, dates, and the engine's own formatting are left untouched.

## Two recognition modes

Choose your engine in **Privacy & Local AI**:

- **Speed (default)** — Apple's native on-device recognition. Near-instant, the
  lightest option, with zero extra downloads.
- **Accuracy** — Whisper (large-v3 turbo). More accurate for English and technical or
  specialized content. The model downloads once on first use, then works fully offline.

Either way, everything runs on your Mac.

## Highlights

- **The fastest local dictation** — Speed mode returns text almost instantly.
- **100% local** — transcription runs on-device (Apple on-device, or optional Whisper).
  Your audio and text never leave your Mac.
- **Works in any app** — pastes into the focused text field across your Mac apps.
- **Hold-to-talk** — hold **Right Option** (configurable), speak, release to paste.
- **Signed & notarized** — Developer ID signed and Apple notarized; double-click to
  open with no Gatekeeper warning.

## Requirements

- **Apple Silicon Mac (M1 or newer)** — Intel Macs are not supported.
- **macOS 14 (Sonoma) or later.**
- **~2 GB free disk** — only if you choose **Accuracy** mode. The Whisper model is
  downloaded once on first use (~1.5 GB) and cached for offline use afterward. Speed
  mode needs no download.

## Install

1. Download and open the DMG, drag **OfflineVoice** to Applications, and launch it.
2. Grant **Microphone**, **Speech Recognition**, and **Accessibility** when prompted
   (Accessibility is what lets OfflineVoice paste into other apps).
3. Hold **Right Option**, speak, release.

## Privacy

100% local. Transcription happens on your Mac (Apple on-device, or optional Whisper).
OfflineVoice does not upload your audio, does not sync transcripts, and does not train
on your data. Model files are cached locally after first download and work offline.
See the [privacy policy](https://www.offlinevoice.ai/#privacy-policy).
