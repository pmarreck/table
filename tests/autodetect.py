"""Executable-level detection contract shared by implementations."""
import subprocess
import sys

binary = sys.argv[1]


def run(args, data):
    return subprocess.run([binary, *args], input=data, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=10)


source = b"name,value\nAlice,2\n"
for format in ("csv", "tsv", "markdown", "ir", "ascii", "ansi"):
    args = ["--from", "csv", "--to", format]
    if format in ("ascii", "ansi"):
        args += ["--terminal-width", "80", "--color", "always" if format == "ansi" else "never"]
    fixture = run(args, source)
    assert fixture.returncode == 0, fixture.stderr
    for prefix in ([], ["--from", "auto"]):
        args = prefix + ["--to", "csv"]
        if format in ("ascii", "ansi"):
            args += ["--allow-lossy"]
        actual = run(args, fixture.stdout)
        assert actual.returncode == 0, (format, actual.stderr)
        assert actual.stdout == source, (format, actual.stdout)

for data in (b"", b"name\nAlice\n", b"a,b\tc\n1,2\t3\n"):
    actual = run(["--to", "csv"], data)
    assert actual.returncode != 0 and not actual.stdout and b"--from" in actual.stderr

# The destination cannot resolve ambiguity; explicit selection can.
for destination in ("csv", "tsv", "ir"):
    actual = run(["--to", destination], b"a,b\tc\n1,2\t3\n")
    assert actual.returncode != 0 and not actual.stdout
actual = run(["--from", "tsv", "--to", "csv"], b"a,b\tc\n1,2\t3\n")
assert actual.returncode == 0 and actual.stdout == b'"a,b",c\n"1,2",3\n'
actual = run(["--to", "ir", "--no-header"], b"a,b\n")
assert actual.returncode == 0 and actual.stdout == b"\x1cT1a\x1fb\x1e\x1c"
actual = run(["--to", "csv"], b"\x1cT1broken")
assert actual.returncode != 0 and not actual.stdout
actual = run(["--to", "csv"], b"\xff,2\n")
assert actual.returncode != 0 and not actual.stdout
# Unicode borders remain recognizable when ANSI styling is disabled.
plain_unicode = run(["--from", "csv", "--to", "ansi", "--color", "never"], source)
assert plain_unicode.returncode == 0
actual = run(["--to", "csv", "--allow-lossy"], plain_unicode.stdout)
assert actual.returncode == 0 and actual.stdout == source
actual = run(["--to", "csv"], b"+------+---+\n| name | n |\n+------+---+\n| A    | 2 |\n+------+---+\n")
assert actual.returncode != 0 and b"--allow-lossy" in actual.stderr
