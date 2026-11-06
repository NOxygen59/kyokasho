# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
"""Le script de tranche Catalyst doit se reprendre après un échec, sans se croire terminé."""

import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "tools" / "mac_onnx_catalyst_slice.sh"
SLICE = "ios-arm64_x86_64-maccatalyst"


class SliceScriptTests(unittest.TestCase):
    def make_xcframework(self, root: Path) -> Path:
        xc = root / "SourcePackages/artifacts/onnxruntime-swift-package-manager/onnxruntime/onnxruntime.xcframework"
        binary = xc / "macos-arm64_x86_64/onnxruntime.framework/Versions/A/onnxruntime"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"faux binaire")  # fait échouer `lipo` : seule la reprise est testée ici
        with (xc / "Info.plist").open("wb") as target:
            plistlib.dump({"AvailableLibraries": []}, target)
        return xc

    def run_script(self, root: Path) -> subprocess.CompletedProcess:
        return subprocess.run(["/bin/zsh", str(SCRIPT), str(root)], capture_output=True, text=True, check=False)

    def test_failed_attempt_leaves_nothing_and_is_not_reported_as_done(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            xc = self.make_xcframework(root)
            for _ in range(2):
                self.assertNotEqual(self.run_script(root).returncode, 0)
                self.assertFalse((xc / SLICE).exists())

    def test_folder_without_index_entry_is_not_trusted(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            xc = self.make_xcframework(root)
            (xc / SLICE).mkdir()
            result = self.run_script(root)
            self.assertNotIn("déjà présente", result.stdout)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
