"""Exercise one formatting policy through CLI, isolated workers, MCP and LSP."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


weft = str(Path(sys.argv[1]).resolve())
standalone = str(Path(sys.argv[2]).resolve())
source = (
    "fn combine(first: i64, second: i64, third: i64, fourth: i64) -> i64 "
    "{ first + second + third + fourth }\n"
)


def run(args, data="", cwd=None):
    return subprocess.run(args, input=data, text=True, capture_output=True, timeout=120, cwd=cwd)


def success(args, data=""):
    result = run(args, data)
    assert result.returncode == 0, (args, result.stderr)
    assert not result.stderr, (args, result.stderr)
    return result.stdout


def mcp(width, present=True):
    arguments = {"source": source}
    if present:
        arguments["max_line_length"] = width
    request = {
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": {"name": "format_source", "arguments": arguments},
    }
    return json.loads(success([weft, "mcp"], json.dumps(request)))


def frame(request):
    body = json.dumps(request, ensure_ascii=False)
    return f"Content-Length: {len(body.encode('utf-8'))}\r\n\r\n{body}"


def lsp(width, present=True):
    options = {"tabSize": 2, "insertSpaces": True}
    if present:
        options["maxLineLength"] = width
    uri = "file:///formatter-options.weft"
    messages = [
        {"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
            "textDocument": {"uri": uri, "version": 1, "text": source},
        }},
        {"jsonrpc": "2.0", "id": 2, "method": "textDocument/formatting", "params": {
            "textDocument": {"uri": uri}, "options": options,
        }},
    ]
    # subprocess text mode normalizes CRLF; content lengths still count only bodies.
    output = success([weft, "lsp"], "".join(map(frame, messages))).encode("utf-8")
    while output:
        header, output = output.split(b"\n\n", 1)
        length = int(header.split(b":", 1)[1].strip())
        body, output = output[:length], output[length:]
        response = json.loads(body)
        if response.get("id") == 2:
            return response
    raise AssertionError("LSP formatting response missing")


expected = {}
for width in (None, 1, 32, 98, 120, 1000):
    args = [] if width is None else ["--max-line-length", str(width)]
    formatted = success([weft, "fmt", *args], source)
    expected[width] = formatted
    assert success([weft, "fmt", *args], formatted) == formatted
    assert success([standalone, *args], source) == formatted
    assert mcp(width, width is not None)["result"]["formatted"] == formatted
    assert lsp(width, width is not None)["result"][0]["newText"] == formatted
assert expected[None] == expected[98]
assert expected[32] != expected[120]

for width in (0, -1, 1.5, "98", None, True, [], {}, 9223372036854775808):
    assert mcp(width)["error"]["code"] == -32602, width
    assert lsp(width)["error"]["code"] == -32602, width

with tempfile.TemporaryDirectory(prefix="weft-formatter-options-") as directory:
    root = Path(directory)
    a = root / "a.weft"
    nested = root / "nested"
    nested.mkdir()
    b = nested / "b.weft"
    a.write_text(source)
    b.write_text(source)
    invalid = [
        ["--max-line-length"],
        ["--max-line-length", "32", "--max-line-length", "80"],
        ["--check", "--write"],
        ["--unknown-option"],
    ] + [["--max-line-length", value] for value in (
        "0", "-1", "wat", "1.5", "1e2", "9223372036854775808",
    )]
    for args in invalid:
        result = run([weft, "fmt", "--write", str(root), *args])
        assert result.returncode != 0 and not result.stdout, args
        assert a.read_text() == source and b.read_text() == source, args
    assert success([weft, "fmt", str(a), "--max-line-length", "32"]) == expected[32]
    assert success([weft, "fmt", "--max-line-length", "32", "--", str(a)]) == expected[32]
    success([weft, "fmt", "--write", str(root), "--max-line-length", "32"])
    assert a.read_text() == b.read_text() == expected[32]
    success([weft, "fmt", "--check", "--max-line-length", "32", str(root)])

    dash = root / "-literal.weft"
    dash.write_text(source)
    result = run([weft, "fmt", "--write", "--max-line-length", "32", "--", dash.name], cwd=root)
    assert result.returncode == 0 and not result.stdout and not result.stderr, result
    assert dash.read_text() == expected[32]
    result = run([weft, "fmt", "--check", "--max-line-length", "32", "--", dash.name], cwd=root)
    assert result.returncode == 0 and not result.stdout and not result.stderr, result

    # Layout may add neutral separators, but grouped/tuple arity, precedence,
    # nested calls, and block-local statement separation retain native meaning.
    program = (
        source + "fn main() -> i64 { "
        "let pair = (combine(1, 2, 3, 4), combine(5, 6, 7, 8)) "
        "let singleton = (6,) pair.0 + pair.1 + singleton.0 }\n"
    )
    original = root / "original.weft"
    formatted = root / "formatted.weft"
    original.write_text(program)
    formatted.write_text(success([weft, "fmt", "--max-line-length", "32"], program))
    for path in (original, formatted):
        binary = str(path.with_suffix(""))
        success([weft, "build", str(path), "-o", binary])
        result = run([binary])
        assert result.returncode == 42 and not result.stdout and not result.stderr, result

print("  ok formatter_width_cli_workers_mcp_lsp_standalone_and_native_meaning")
