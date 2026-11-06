"""Check fixture correctness, manifest coverage and refusal of wrong work."""
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location("benchmark", "scripts/table-benchmark.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
binary = pathlib.Path(sys.argv[1]).resolve()
with open("profiling.json") as file:
    manifest = json.load(file)
cases = [case for case in manifest["cases"] if case["command"][0] == "table-benchmark"]
expected = {f"{i}-{w}-{c}" for i in adapter.IMPLEMENTATIONS for w in adapter.WORKLOADS for c in (1, 12)}
assert len(cases) == len(expected) and {case["name"] for case in cases} == expected
for case in cases:
    assert case["cores"] == int(case["name"].rsplit("-", 1)[1])
    assert case["command"] == ["table-benchmark", "{case}", "{sizes}", "{seed}"]
for workload in adapter.WORKLOADS:
    # Run the actual fixed workload sizes, including all expected output bytes.
    n = 1 if workload == "startup" else 4096
    digest, samples = adapter.measure(binary, workload, n)
    assert len(digest) == 64 and len(samples) == 5 and all(value > 0 for value in samples)
with tempfile.TemporaryDirectory() as temporary:
    wrong = pathlib.Path(temporary) / "wrong"
    wrong.write_text(f"#!{sys.executable}\nprint('fabricated output')\n")
    wrong.chmod(0o700)
    try:
        adapter.measure(wrong, "csv-tsv", 4096)
    except RuntimeError:
        pass
    else:
        raise AssertionError("benchmark accepted incorrect output")
