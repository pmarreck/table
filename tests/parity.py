"""Direct byte/status parity plus external-oracle acceptance for all CLIs."""
import csv
import io
import os
import random
import subprocess
import sys

pair_diagnostic = sys.argv[1:2] == ["--pair"]
binaries = sys.argv[2:] if pair_diagnostic else sys.argv[1:]
assert len(binaries) == (2 if pair_diagnostic else 4), "full qualification requires all four CLIs; --pair is diagnostic only"
env = dict(os.environ, COLUMNS="80", TERM="dumb", NO_COLOR="1")
env.pop("TSV_TO_ANSI_TABLE_GLYPHS", None)


def run(binary, args, data):
    result = subprocess.run([binary, *args], input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, env=env, timeout=15)
    return result.returncode, result.stdout, result.stderr


count = 0
def compare(args, data):
    global count
    expected = run(binaries[0], args, data)
    for binary in binaries[1:]:
        actual = run(binary, args, data)
        assert actual == expected, (binary, args, data[:200], expected, actual)
    count += 1


formats = ("csv", "tsv", "markdown", "ir", "ascii", "ansi")
source = "name,value\n界,é\nA,12\n".encode()
for source_format in formats:
    status, fixture, _ = run(binaries[0], ["--from", "csv", "--to", source_format], source)
    assert status == 0
    for destination in formats:
        args = ["--from", source_format, "--to", destination]
        if source_format in ("ascii", "ansi"):
            args += ["--allow-lossy"]
        compare(args, fixture)
    compare(["--to", "csv"] + (["--allow-lossy"] if source_format in ("ascii", "ansi") else []), fixture)

for args in ([], ["--help"], ["--wat"], ["--to"], ["--from"], ["--to", "bad"], ["--to="], ["--to", ""],
             ["--to=csv", "--from=bad"], ["--to", "csv", "--color", "never"],
             ["--from", "csv", "--to", "csv", "--allow-lossy"],
             ["--from", "csv", "--to", "csv", "--visual-glyphs", "bad"]):
    compare(args, b"")
for source_format in formats:
    for data in (b"", b"\n", b"a\tb\n1\n", b'a,b\n"unterminated', b"\xff", b"\x1cT1\x1d\x1c",
                 b"\x1cT1\x1bq\x1e\x1c", b"\x1cT1x\x1c", b"\x1b]0;bad\x07", b"a\rb", b"h\n---\nx\n"):
        args = ["--from", source_format, "--to", "csv"]
        if source_format in ("ascii", "ansi"):
            args += ["--allow-lossy"]
        compare(args, data)
    compare(["--from", source_format, "--to", "csv", "--no-header"], b"")

rng = random.Random(20261106)
alphabet = "ab,\"\r\n\t\\|界é\x00\x1b\x1c\x1d\x1e\x1f"
for _ in range(35):
    rows = [["h1", "h2", "h3"]] + [["".join(rng.choice(alphabet) for _ in range(rng.randrange(18))) for _ in range(3)] for _ in range(3)]
    buffer = io.StringIO(newline="")
    csv.writer(buffer, lineterminator="\r\n").writerows(rows)
    data = buffer.getvalue().encode()
    for destination in ("csv", "tsv", "ir", "markdown", "ascii", "ansi"):
        compare(["--from", "csv", "--to", destination], data)

for mode in ("never", "always", "auto"):
    for options in ([], ["--plain"], ["--widths", "6,5"], ["--widths", "4,5", "--align", "right,left"],
                    ["--terminal-width", "10"], ["--color", "bad"], ["--overflow", "bad"]):
        for from_format, data in (("tsv", b"name\tvalue\nAlice\t12\n"), ("csv", b"name,value\nAlice,12\n")):
            compare(["--from", from_format, "--to", "ascii", "--color", mode, *options], data)

for data in (b"", b"a\n", b"a,b\tc\n1,2\t3\n", b"\x1cT1broken", b"\xff"):
    compare(["--to", "csv"], data)

# Self-identification has deliberately different ABI metadata where applicable.
for binary in binaries:
    status, about, err = run(binary, ["--about"], b"")
    assert status == 0 and not err and len(about.splitlines()) == 1 and b"PF=" in about
print(f"{'Diagnostic' if pair_diagnostic else 'Full'} parity: {count} cases agree across {len(binaries)} CLIs")
