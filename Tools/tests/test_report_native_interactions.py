import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPORT = Path(__file__).resolve().parents[1] / "report_native_interactions.py"


class NativeInteractionReportTests(unittest.TestCase):
    def report(self, log):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ui-tests.log"
            path.write_text(log)
            result = subprocess.run([sys.executable, str(REPORT), str(path)],
                                    capture_output=True, text=True, check=True)
            return result.stdout

    def test_compilation_failure_before_tests_is_visible_without_dumping_log(self):
        result = self.report(
            "arbitrary runner environment data must not be published\n"
            "/checkout/Erhu/App/InteractionProbeView.swift:71:22: error: cannot convert "
            "value of type 'KeyPath<EnvironmentValues, Bool>' to expected argument "
            "type 'WritableKeyPath<EnvironmentValues, Bool>'\n")
        self.assertIn("::error::/InteractionProbeView.swift:71:22: error:", result)
        self.assertIn("No individual test results were reported", result)
        self.assertNotIn("arbitrary runner environment data", result)

    def test_test_outcomes_remain_distinct(self):
        result = self.report(
            "Test Case '-[ErhuInteractionTests.LibraryInteractionTests testFullPlayer]' started.\n"
            "Test Case '-[ErhuInteractionTests.LibraryInteractionTests testFullPlayer]' passed.\n"
            "Test case 'LibraryInteractionTests.testClose()' failed on 'iPhone'\n")
        self.assertIn("LibraryInteractionTests.testFullPlayer: passed", result)
        self.assertIn("LibraryInteractionTests.testClose: failed", result)
        self.assertNotIn("No individual test results", result)


if __name__ == "__main__":
    unittest.main()
