# Bundled voice-activity model: Silero VAD

OfflineVoice.app ships the Silero VAD model inside
`Contents/Resources/models/silero-vad/`. It decides whether a capture contains
speech at all before anything is transcribed, so a hotkey tap in a quiet room
produces nothing instead of a hallucinated word. It is not part of the
OfflineVoice source code and is not covered by OfflineVoice's GPL-3.0 licence.

| | |
|---|---|
| Model | Silero VAD (ONNX) |
| Authors | Silero Team — https://github.com/snakers4/silero-vad |
| Licence | MIT |
| Distribution used | https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models (`silero_vad.onnx`) |
| `silero_vad.onnx` | 643,854 bytes, SHA-256 `9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6` |
| Runtime | sherpa-onnx (Apache-2.0) — https://github.com/k2-fsa/sherpa-onnx |

`scripts/fetch-models.sh` downloads exactly this file and refuses any copy
whose SHA-256 does not match.
