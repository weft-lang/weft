"""Canonical output for generated Weft sources.

Generators emit readable source templates. The checked-in form is exactly what
the checkout's formatter produces for that template, so a regenerated table,
its --check comparison and the repository gate's formatter dogfood agree.
"""

from __future__ import annotations

import os
import pathlib
import subprocess

REPO = pathlib.Path(__file__).resolve().parent.parent


def formatter() -> pathlib.Path:
    """Return the formatter binary: $WEFT when set, else the checkout root."""
    override = os.environ.get("WEFT")
    return pathlib.Path(override) if override else REPO / "weft"


def canonical(source: bytes) -> bytes:
    """Format generated source through `weft fmt`, rejecting unparseable text."""
    result = subprocess.run(
        [str(formatter()), "fmt"],
        input=source,
        capture_output=True,
        cwd=REPO,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise SystemExit(f"generated source does not format:\n{detail}")
    return result.stdout

