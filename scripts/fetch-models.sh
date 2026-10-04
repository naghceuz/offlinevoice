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
DEST="$ROOT_DIR/Resources/models/sense-voice"
REPO="csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17"
REVISION="2365baeacb507f821a0c8120fcee3d484dba7a07"
# Primary host first; hf-mirror.com is a drop-in mirror for regions where
# huggingface.co is slow or blocked. Both must produce the same hashes.
HOSTS=("https://huggingface.co" "https://hf-mirror.com")

# name | size | sha256
FILES=(
  "model.int8.onnx|239233841|c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
  "tokens.txt|315894|f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"
)

mkdir -p "$DEST"

verify() {
  local path="$1" size="$2" sha="$3"
  [[ -f "$path" ]] || return 1
  [[ "$(stat -f %z "$path")" == "$size" ]] || return 1
  [[ "$(shasum -a 256 "$path" | cut -d' ' -f1)" == "$sha" ]] || return 1
}

fetch() {
  local name="$1" size="$2" sha="$3"
  local target="$DEST/$name"
  if verify "$target" "$size" "$sha"; then
    echo "==> $name already present and verified, skipping"
    return 0
  fi
  rm -f "$target"
  local host
  for host in "${HOSTS[@]}"; do
    local url="$host/$REPO/resolve/$REVISION/$name"
    echo "==> Downloading $name from $host"
    if curl -fL --retry 3 --progress-bar -o "$target.part" "$url" \
       && verify "$target.part" "$size" "$sha"; then
      mv -f "$target.part" "$target"
      echo "==> $name verified (sha256 ok)"
      return 0
    fi
    echo "    download failed or checksum mismatch from $host, trying next" >&2
    rm -f "$target.part"
  done
  echo "ERROR: could not obtain a verified copy of $name" >&2
  return 1
}

for entry in "${FILES[@]}"; do
  IFS='|' read -r name size sha <<<"$entry"
  fetch "$name" "$size" "$sha"
done
cp "$ROOT_DIR/Resources/SenseVoice-NOTICE.md" "$DEST/NOTICE.md"
echo "SenseVoice model ready in $DEST"
