#!/usr/bin/env python3
"""Run the OfflineVoice app's headless ASR path against its bundled corpus."""

import argparse
import json
import subprocess
import sys
import unicodedata
from pathlib import Path


def edit_distance(left, right):
    previous = list(range(len(right) + 1))
    for row, left_item in enumerate(left, start=1):
        current = [row]
        for column, right_item in enumerate(right, start=1):
            current.append(
                min(
                    previous[column] + 1,
                    current[column - 1] + 1,
                    previous[column - 1] + (left_item != right_item),
                )
            )
        previous = current
    return previous[-1]


def normalized_characters(text):
    return [
        character
        for character in text.lower()
        if unicodedata.category(character)[0] not in {"P", "S", "Z"}
    ]


def character_error_rate(reference, hypothesis):
    expected = normalized_characters(reference)
    actual = normalized_characters(hypothesis)
    return edit_distance(expected, actual) / len(expected) if expected else float(bool(actual))


def word_error_rate(reference, hypothesis):
    expected = word_tokens(reference)
    actual = word_tokens(hypothesis)
    return edit_distance(expected, actual) / len(expected) if expected else float(bool(actual))


def word_tokens(text):
    tokens = []
    ascii_word = []
    for character in text.lower():
        if character.isascii() and character.isalnum():
            ascii_word.append(character)
            continue
        if ascii_word:
            tokens.append("".join(ascii_word))
            ascii_word = []
        if character.isalnum():
            tokens.append(character)
    if ascii_word:
        tokens.append("".join(ascii_word))
    return tokens


def resource(resources, filename):
    for candidate in (resources / filename, resources / "benchmark" / filename):
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"Bundled acceptance resource is missing: {filename}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--summary", type=Path)
    args = parser.parse_args()

    executable = args.app / "Contents" / "MacOS" / "OfflineVoice"
    resources = args.app / "Contents" / "Resources"
    references_path = resource(resources, "references.json")
    samples = json.loads(references_path.read_text(encoding="utf-8"))["samples"]

    try:
        malformed = subprocess.run(
            [str(executable), "--transcribe-file"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except subprocess.TimeoutExpired:
        print("FAIL: missing audio path opened or hung the GUI", file=sys.stderr)
        return 1
    if malformed.returncode == 0 or "requires a WAV file path" not in malformed.stderr:
        print("FAIL: missing audio path did not return the expected usage error", file=sys.stderr)
        return 1

    rows = []
    failures = []
    for sample in samples:
        audio = resource(resources, sample["file"])
        completed = subprocess.run(
            [str(executable), "--transcribe-file", str(audio)],
            capture_output=True,
            text=True,
            timeout=90,
            check=False,
        )
        if completed.returncode != 0:
            detail = completed.stderr.strip() or f"exit code {completed.returncode}"
            failures.append(f'{sample["file"]}: {detail}')
            rows.append((sample["file"], sample["lang"], "ERROR", "—", detail))
            continue

        try:
            output = json.loads(completed.stdout.strip().splitlines()[-1])
            hypothesis = output["text"]
            duration = int(output["durationMilliseconds"])
        except (IndexError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            failures.append(f'{sample["file"]}: invalid JSON output ({error})')
            rows.append((sample["file"], sample["lang"], "ERROR", "—", completed.stdout.strip()))
            continue

        if sample["lang"] == "en":
            metric_name = "WER"
            score = word_error_rate(sample["text"], hypothesis)
            threshold = 0.25
        else:
            metric_name = "CER"
            score = character_error_rate(sample["text"], hypothesis)
            threshold = 0.20 if sample["lang"] == "zh" else 0.25

        if not hypothesis.strip() or score > threshold:
            failures.append(
                f'{sample["file"]}: {metric_name} {score:.1%} exceeds {threshold:.0%}; '
                f'got {hypothesis!r}'
            )
        rows.append(
            (sample["file"], sample["lang"], f"{metric_name} {score:.1%}", f"{duration} ms", hypothesis)
        )

    lines = [
        "## Speech recognition acceptance",
        "",
        "| Audio | Language | Quality | Engine time | Transcript |",
        "|---|---|---:|---:|---|",
    ]
    for filename, language, quality, duration, transcript in rows:
        safe_transcript = str(transcript).replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {filename} | {language} | {quality} | {duration} | {safe_transcript} |")
    lines.append("")
    lines.append("Result: **FAILED**" if failures else "Result: **PASSED**")
    report = "\n".join(lines) + "\n"
    print(report)
    if args.summary:
        with args.summary.open("a", encoding="utf-8") as summary:
            summary.write(report)

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
