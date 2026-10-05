import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "run-speech-acceptance.py"
SPEC = importlib.util.spec_from_file_location("speech_acceptance", SCRIPT)
speech_acceptance = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(speech_acceptance)


class SpeechAcceptanceMetricTests(unittest.TestCase):
    def test_english_metric_counts_non_ascii_hallucination_as_error(self):
        reference = "Please send the meeting notes."
        hypothesis = "Please send the meeting notes. 中文幻觉"

        score = speech_acceptance.word_error_rate(reference, hypothesis)

        self.assertGreater(score, 0)

    def test_transcription_output_rejects_extra_stdout_lines(self):
        output = '{"text":"hello","durationMilliseconds":42}\nunexpected output\n'

        with self.assertRaises(ValueError):
            speech_acceptance.parse_transcription_output(output)


if __name__ == "__main__":
    unittest.main()
