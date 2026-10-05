# OfflineVoice v0.5.2

**The fastest local dictation for Mac.** Private, offline voice input — now in your language, whichever one you're speaking.

OfflineVoice turns your speech into text in any app — hold one key, talk, release, and
the text is pasted at your cursor. Because it runs entirely on your Mac, it's faster
*and* more private than cloud-based tools. No account, no subscription, no cloud upload.

🔗 **Website:** https://www.offlinevoice.ai
⬇️ **Download:** [OfflineVoice-mac.dmg](https://www.offlinevoice.ai/api/download)

---

## What's new in 0.5.2

**Press, talk — the first word is there.** On external microphones (an Apple Studio
Display, a USB or Bluetooth mic) opening the mic can take half a second, and that
half second used to swallow the start of what you said. OfflineVoice now keeps the
microphone open for ten seconds after each dictation, so the next press captures
instantly — and even includes the half second *before* you pressed. On the first
press after a pause the floating indicator shows a mic icon until audio is really
flowing, then switches to the waveform: wait for the waveform, nothing is lost.

**A tap pastes nothing.** Holding the key without speaking used to paste a stray
word ("The.", "你。"), because speech models hallucinate on room noise. A small
on-device voice-activity model now checks every capture; no speech, no text.

**Switching microphones mid-sentence keeps recording.** Plugging a display in or out,
or changing the input device, no longer turns the rest of a dictation into silence.

## What's new in 0.5.1

**A calmer first launch.** Installing 0.5.0 greeted you with three macOS permission
dialogs at once — microphone, Accessibility and Input Monitoring — stacked on top of
the setup window. Setup now asks for one thing at a time: each permission has its own
screen, the macOS prompt appears by itself when you reach it, and setup moves on as
soon as the permission is granted. Nothing is requested before you have seen what the
app is for, and nothing can be skipped by accident.

Also new: a headless `--transcribe-file <wav>` mode used by the project's cloud
acceptance tests, so every release is checked against real Chinese, English and mixed
samples on a Mac in CI.

## What's new in 0.5.0

**Speak Chinese, English, or both — no setup.** Until now the default engine was
Apple's built-in recognizer, which is tied to your Mac's *system language*: on an
English-language Mac, a Chinese sentence came back as English gibberish. 0.5.0
replaces it with **SenseVoice**, a multilingual model that ships inside the app:

- **Detects the language itself.** Mandarin, Cantonese, English, Japanese and Korean,
  with no language setting to get wrong — and mixed Chinese/English inside one
  sentence ("我想试一下这个 feature 好不好用") comes out as you said it.
- **Still instant.** The model is non-autoregressive, so it decodes a whole sentence
  in one pass: in our tests a 2–8 second clip transcribes in well under 100 ms on
  Apple Silicon, and the model loads in under half a second at launch.
- **Punctuation included.** The engine emits its own punctuation and number
  formatting (full-width marks for Chinese, ASCII for English).
- **Nothing to download.** The 228 MB model is bundled, so the first dictation works
  offline straight after install. The installer is correspondingly larger and is now
  served from GitHub Releases; the website download button redirects there.

Apple's recognizer is still available as the new **Native** mode for people who only
dictate in their system language; **Accuracy** (Whisper) is unchanged.

Also in this release: a fix for a rare case where the app could stay stuck on
"processing" if the model failed to load while you were already holding the key.

## Three recognition modes

Choose your engine in **Speed & Accuracy**:

- **Speed (default)** — SenseVoice, bundled. Multilingual with automatic language
  detection, including mixed Chinese and English. Near-instant.
- **Accuracy** — Whisper (large-v3 turbo). An alternative for English and technical or
  specialized content. The model downloads once on first use, then works fully offline.
- **Native** — Apple's on-device recognizer. No model files, but it only understands
  your Mac's system language.

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
