"""Check canonical SDK diagnostics and recovery through tool transports."""

import json
import pathlib
import subprocess
import sys

compiler, project = sys.argv[1:]
source = "use stdlib/missing_sdk_probe.{value} fn main() -> i64 { 0 }"
request = {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
    "name": "diagnostics", "arguments": {"source": source}}}
result = subprocess.run([compiler, "mcp"], cwd=project, input=json.dumps(request).encode(),
                        capture_output=True, check=True, timeout=30)
assert not result.stderr, result.stderr.decode()
diagnostics = json.loads(result.stdout)["result"]["items"]
assert len(diagnostics) == 1
diagnostic = diagnostics[0]["diagnostic"]
assert diagnostic["code"] == "E5016" and diagnostic["class"] == "link"
assert diagnostic["primary"]["source"]["path"] == "stdlib/missing_sdk_probe.weft"
assert {field["name"]: field["value"] for field in diagnostic["fields"]} == {
    "path": "stdlib/missing_sdk_probe.weft", "reason": "missing"}

uri = (pathlib.Path(project) / "main.weft").as_uri()
messages = [
    {"id": 1, "method": "initialize", "params": {}},
    {"method": "textDocument/didOpen", "params": {"textDocument": {
        "uri": uri, "version": 1, "text": source}}},
    {"method": "textDocument/didChange", "params": {"textDocument": {
        "uri": uri, "version": 2}, "contentChanges": [{"text": "fn main() -> i64 { 42 }"}]}},
    {"id": 2, "method": "shutdown", "params": None},
    {"method": "exit", "params": None},
]
frames = []
for message in messages:
    body = json.dumps({"jsonrpc": "2.0", **message}).encode()
    frames.append(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
result = subprocess.run([compiler, "lsp"], cwd=project, input=b"".join(frames),
                        capture_output=True, check=True, timeout=30)
assert not result.stderr, result.stderr.decode()
output = result.stdout
responses = []
while output:
    header, output = output.split(b"\r\n\r\n", 1)
    length = int(header.split(b":", 1)[1])
    responses.append(json.loads(output[:length]))
    output = output[length:]
published = [message["params"] for message in responses
             if message.get("method") == "textDocument/publishDiagnostics"]
assert any(any(d.get("code") == "E5016" for d in item["diagnostics"]) for item in published), published
assert published[-1]["diagnostics"] == [], published
assert any(message.get("id") == 2 and message.get("result", False) is None for message in responses)
print("SDK tool diagnostics passed: structured MCP provenance and LSP recovery")
