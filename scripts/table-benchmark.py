#!/usr/bin/env python3
"""Shared CLI benchmark adapter; correctness is checked outside timed intervals."""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

IMPLEMENTATIONS = ("rust", "zig", "roc")
WORKLOADS = ("startup", "csv-tsv", "csv-ir", "markdown-csv", "ascii-csv", "autodetect-csv")


def fixture(workload, n):
    csv = b"name,count\n" + b"alpha,42\n" * n
    if workload in ("startup", "csv-tsv"):
        return ["--from", "csv", "--to", "tsv"], csv, b"name\tcount\n" + b"alpha\t42\n" * n
    if workload == "csv-ir":
        return ["--from", "csv", "--to", "ir"], csv, b"\x1cT1\x1dname\x1fcount\x1e" + b"alpha\x1f42\x1e" * n + b"\x1c"
    if workload == "markdown-csv":
        return ["--from", "markdown", "--to", "csv"], b"| name | count |\n| --- | --- |\n" + b"| alpha | 42 |\n" * n, csv
    if workload == "ascii-csv":
        return ["--from", "ascii", "--to", "csv", "--allow-lossy"], b"+-------+-------+\n| name  | count |\n+-------+-------+\n" + b"| alpha | 42    |\n" * n + b"+-------+-------+\n", csv
    if workload == "autodetect-csv":
        return ["--to", "csv"], csv, csv
    raise ValueError(f"unknown workload: {workload}")


def measure(binary, workload, n):
    args, data, expected = fixture(workload, n)
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    samples = []
    for _ in range(5):
        start = time.monotonic_ns()
        result = subprocess.run([str(binary), *args], input=data, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=30)
        elapsed = time.monotonic_ns() - start
        if result.returncode or result.stdout != expected:
            raise RuntimeError(f"incorrect {workload} conversion: exit={result.returncode}, stderr={result.stderr[:200]!r}")
        if hashlib.sha256(binary.read_bytes()).hexdigest() != digest:
            raise RuntimeError("benchmark executable changed during measurement")
        samples.append(elapsed)
    return digest, samples


def main():
    if sys.argv[1:] == ["--list"]:
        for implementation in IMPLEMENTATIONS:
            for workload in WORKLOADS:
                for cores in (1, 12):
                    print(f"{implementation}-{workload}-{cores}")
        return
    case, sizes, _seed = sys.argv[1:]
    implementation, rest = case.split("-", 1)
    workload, cores = rest.rsplit("-", 1)
    assert implementation in IMPLEMENTATIONS and workload in WORKLOADS and cores in ("1", "12")
    n = int(sizes)
    assert n == (1 if workload == "startup" else 4096)
    binary = pathlib.Path(os.environ[f"TABLE_BENCHMARK_{implementation.upper()}"]).resolve(strict=True)
    digest, samples = measure(binary, workload, n)
    print(json.dumps({"schema": "performance-measurement/v1", "correct": True,
                      "build_mode": "release", "implementation": implementation,
                      "binary_sha256": digest, "phase": "fresh CLI process launch through collected output and exit; validation excluded",
                      "rows": [{"size": n, "samples": {"wall_ns": samples}}]}))


if __name__ == "__main__":
    main()
