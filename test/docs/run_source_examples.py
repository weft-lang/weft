"""Check every public example and execute each self-checking program."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


def main():
    compiler = str(Path(os.environ.get("WEFT", "./weft")).resolve())
    compile_timeout = int(os.environ.get("WEFT_TEST_COMPILE_TIMEOUT", "120"))
    run_timeout = int(os.environ.get("WEFT_TEST_RUN_TIMEOUT", "120"))
    sources = sorted(Path("examples").glob("*.weft"))
    if not sources:
        raise RuntimeError("No public source examples found")

    def run(command, timeout):
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        if result.returncode != 0:
            raise RuntimeError(
                f"{command[0]} exited {result.returncode}\n{result.stdout}{result.stderr}"
            )
        return result.stdout

    run([compiler, "check", *(str(source) for source in sources)], compile_timeout)
    expected_output = {
        "hello": "Hello, world!\n",
        "iterator_pipeline": (
            "sum: 60\n"
            "double-digit sum: 33\n"
            "single-digit sum: 45\n"
            "first double digit: 10\n"
            "8 -> 9\n9 -> 10\n10 -> 11\n"
        ),
    }
    executed = 0
    with tempfile.TemporaryDirectory(prefix="weft-source-examples-") as directory:
        for source in sources:
            if not re.search(r"^\s*fn\s+main\s*\(", source.read_text(), re.MULTILINE):
                print(f"  ok {source} (module checked)", flush=True)
                continue
            # Distinct products stay alive until the entire run finishes, so
            # macOS cannot reuse an executed inode's cached signature state.
            product = Path(directory) / source.stem
            try:
                run([compiler, "build", str(source), "-o", str(product)], compile_timeout)
                output = run([str(product)], run_timeout)
                expected = expected_output.get(source.stem, "")
                if output != expected:
                    raise RuntimeError(f"expected stdout {expected!r}, received {output!r}")
            except (RuntimeError, subprocess.TimeoutExpired) as error:
                raise RuntimeError(f"{source}: {error}") from error
            executed += 1
            print(f"  ok {source} (run)", flush=True)
    print(f"Source example summary: {len(sources)} checked, {executed} executed, 0 failed")


if __name__ == "__main__":
    main()
