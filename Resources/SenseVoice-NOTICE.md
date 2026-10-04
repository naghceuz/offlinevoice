# Bundled speech model: SenseVoiceSmall (sherpa-onnx int8 export)

OfflineVoice.app ships a copy of the SenseVoiceSmall speech-recognition model
inside `Contents/Resources/models/sense-voice/`. The model is **not** part of the
OfflineVoice source code and is **not** covered by OfflineVoice's GPL-3.0 licence.

| | |
|---|---|
| Model | SenseVoiceSmall (zh / yue / en / ja / ko, auto language ID) |
| Authors | FunAudioLLM / Tongyi Speech Team, Alibaba — https://github.com/FunAudioLLM/SenseVoice |
| Paper | https://arxiv.org/abs/2407.04051 |
| Model licence | FunASR Model Open Source License Agreement — https://github.com/modelscope/FunASR?tab=readme-ov-file#license (attribution per §2.2) |
| ONNX export | https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17 (converted by Fangjun Kuang for sherpa-onnx) |
| Pinned revision | `2365baeacb507f821a0c8120fcee3d484dba7a07` |
| `model.int8.onnx` | 239,233,841 bytes, SHA-256 `c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51` |
| `tokens.txt` | 315,894 bytes, SHA-256 `f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc` |
| Runtime | sherpa-onnx (Apache-2.0) — https://github.com/k2-fsa/sherpa-onnx |

`scripts/fetch-models.sh` downloads exactly this revision and refuses any file
whose SHA-256 does not match the table above.
