#!/usr/bin/env python3
"""Bootstrap acceptance must prove SDK presence as well as binary convergence."""
import json
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


GATE = Path(__file__).resolve().parents[1] / "tools/verify_bootstrap_sdk.sh"
SDK = {"kind": "embedded", "archive_version": 1, "digest": "sha256:" + "a" * 64}


class BootstrapSdkGate(unittest.TestCase):
    def run_gate(self, *identities, failed_inspection=False):
        with tempfile.TemporaryDirectory(prefix="weft bootstrap sdk ") as work:
            compilers = []
            for index, identity in enumerate(identities):
                compiler = Path(work) / f"compiler {index}"
                payload = json.dumps(identity, separators=(",", ":"))
                compiler.write_text(
                    "#!/usr/bin/env bash\n"
                    '[ "$#" -eq 2 ] && [ "$1" = version ] && [ "$2" = --json ] || exit 2\n'
                    f"printf '%s\\n' {shlex.quote(payload)}\n"
                    f"exit {1 if failed_inspection else 0}\n"
                )
                compiler.chmod(0o700)
                compilers.append(str(compiler))
            return subprocess.run(
                ["bash", str(GATE), *compilers], text=True, capture_output=True
            )

    def test_three_generations_share_sdk_not_other_product_metadata(self):
        result = self.run_gate(*[
            {"compiler_version": str(index), "sdk": SDK} for index in range(3)
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(SDK["digest"], result.stdout)

    def test_single_detached_candidate(self):
        result = self.run_gate({"sdk": SDK})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_no_products_is_not_a_proof(self):
        result = self.run_gate()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("usage:", result.stderr)

    def test_absent_checkout_and_malformed_identities(self):
        for identity in [
            {}, "not a product identity", {"sdk": {"kind": "absent"}},
            {"sdk": {"kind": "checkout", "root": "."}},
            {"sdk": {**SDK, "archive_version": 0}},
            {"sdk": {**SDK, "digest": "sha256:short"}},
            {"sdk": {**SDK, "digest": "sha256:" + "g" * 64}},
        ]:
            with self.subTest(identity=identity):
                result = self.run_gate({"sdk": SDK}, identity)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("--embed-sdk", result.stderr)

    def test_different_snapshot_or_archive_version(self):
        for changed in [
            {**SDK, "digest": "sha256:" + "b" * 64},
            {**SDK, "archive_version": 2},
        ]:
            with self.subTest(sdk=changed):
                result = self.run_gate({"sdk": SDK}, {"sdk": changed})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("different SDK snapshot", result.stderr)

    def test_failed_inspection_cannot_pass_with_valid_stdout(self):
        result = self.run_gate({"sdk": SDK}, failed_inspection=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot inspect", result.stderr)


if __name__ == "__main__":
    unittest.main()
