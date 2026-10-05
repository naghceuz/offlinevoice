#!/usr/bin/env bash
# Downloads the SenseVoice model bundled into OfflineVoice.app (the default
# "Speed" engine). The files are gitignored (228 MB). Build order:
#   scripts/fetch-models.sh  →  xcodegen generate  →  xcodebuild
# package-mac.sh runs this automatically. Every file is pinned to one upstream
# revision and verified by SHA-256 — a wrong size or hash is rejected whether
# it came from the primary host or the mirror. See Resources/SenseVoice-NOTICE.md
# for provenance and the model licence.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS="$ROOT_DIR/Resources/models"

# SenseVoice: one pinned Hugging Face revision; hf-mirror.com is a drop-in
# mirror for regions where huggingface.co is slow or blocked.
SV_REPO="csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
SV_REV="2365baeacb507f821a0c8120fcee3d484dba7a07"
# Silero VAD (speech/no-speech gate before transcription): the ONNX export
# that sherpa-onnx publishes; gh-proxy.com fronts GitHub for slow regions.
VAD_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx"

# subdir | name | size | sha256 | url (primary) | url (fallback)
FILES=(
  "sense-voice|model.int8.onnx|239233841|c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51|https://huggingface.co/$SV_REPO/resolve/$SV_REV/model.int8.onnx|https://hf-mirror.com/$SV_REPO/resolve/$SV_REV/model.int8.onnx"
  "sense-voice|tokens.txt|315894|f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc|https://huggingface.co/$SV_REPO/resolve/$SV_REV/tokens.txt|https://hf-mirror.com/$SV_REPO/resolve/$SV_REV/tokens.txt"
  "silero-vad|silero_vad.onnx|643854|9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6|$VAD_URL|https://gh-proxy.com/$VAD_URL"
)

verify() {
  local path="$1" size="$2" sha="$3"
  [[ -f "$path" ]] || return 1
  [[ "$(stat -f %z "$path")" == "$size" ]] || return 1
  [[ "$(shasum -a 256 "$path" | cut -d' ' -f1)" == "$sha" ]] || return 1
}

fetch() {
  local subdir="$1" name="$2" size="$3" sha="$4"
  shift 4
  local dest="$MODELS/$subdir"
  local target="$dest/$name"
  mkdir -p "$dest"
  if verify "$target" "$size" "$sha"; then
    echo "==> $subdir/$name already present and verified, skipping"
    return 0
  fi
  rm -f "$target"
  local url
  for url in "$@"; do
    echo "==> Downloading $subdir/$name from ${url%%/resolve/*}"
    if curl -fL --retry 3 --progress-bar -o "$target.part" "$url" \
       && verify "$target.part" "$size" "$sha"; then
      mv -f "$target.part" "$target"
      echo "==> $subdir/$name verified (sha256 ok)"
      return 0
    fi
    echo "    download failed or checksum mismatch, trying next source" >&2
    rm -f "$target.part"
  done
  echo "ERROR: could not obtain a verified copy of $subdir/$name" >&2
  return 1
}

for entry in "${FILES[@]}"; do
  IFS='|' read -r subdir name size sha url1 url2 <<<"$entry"
  fetch "$subdir" "$name" "$size" "$sha" "$url1" "$url2"
done
cp "$ROOT_DIR/Resources/SenseVoice-NOTICE.md" "$MODELS/sense-voice/NOTICE.md"
cp "$ROOT_DIR/Resources/SileroVAD-NOTICE.md" "$MODELS/silero-vad/NOTICE.md"
echo "Models ready in $MODELS"
