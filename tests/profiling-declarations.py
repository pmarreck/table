#!/usr/bin/env python3
"""Check that each declared growth adapter has both affinity configurations."""
import copy
import json
import subprocess
import sys


def validate(names, manifest):
    assert names and len(names) == len(set(names)), "missing or duplicate adapter names"
    expected = {f"{name}-{cores}": cores for name in names for cores in (1, 12)}
    cases = [case for case in manifest["cases"] if case["mode"] == "cg"]
    actual = [case["name"] for case in cases]
    assert len(actual) == len(set(actual)), "duplicate growth case"
    assert set(actual) == set(expected), f"growth case mismatch: expected {set(expected)}, got {set(actual)}"
    for case in cases:
        assert case["cores"] == expected[case["name"]], f"wrong cores: {case['name']}"
        assert case["metric"] == "wall_ns", f"wrong metric: {case['name']}"
        assert case["command"] == ["table-perf", "{case}", "{sizes}", "{seed}"], f"wrong command: {case['name']}"
        sizes = case["sizes"]
        assert len(sizes) >= 3 and all(b == 2 * a for a, b in zip(sizes, sizes[1:])) and sizes[0] > 0, f"wrong sizes: {case['name']}"
        assert len(case["bounds"]) == 2 and 0 < case["bounds"][0] < case["bounds"][1], f"wrong bounds: {case['name']}"


def expect_rejected(names, manifest):
    try:
        validate(names, manifest)
    except AssertionError:
        return
    raise AssertionError("invalid growth declaration was accepted")


names = subprocess.check_output([sys.argv[1], "--list"], text=True).splitlines()
with open("profiling.json", encoding="utf-8") as file:
    manifest = json.load(file)
validate(names, manifest)
growth = next(case for case in manifest["cases"] if case["mode"] == "cg")
missing = copy.deepcopy(manifest)
missing["cases"].remove(growth)
expect_rejected(names, missing)
duplicate = copy.deepcopy(manifest)
duplicate["cases"].append(copy.deepcopy(growth))
expect_rejected(names, duplicate)
wrong_cores = copy.deepcopy(manifest)
next(case for case in wrong_cores["cases"] if case["mode"] == "cg")["cores"] = 99
expect_rejected(names, wrong_cores)
expect_rejected(names + ["undeclared-adapter"], manifest)
