"""Black-box CLI checks shared by every table implementation."""
import subprocess
import sys
import threading

binary = sys.argv[1]
renderer = sys.argv[2]


def run(args, data=b""):
    return subprocess.run([binary, *args], input=data, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=30, check=False)


def convert(source, destination, data):
    args = ["--from", source, "--to", destination]
    if source in ("ascii", "ansi"):
        args.append("--allow-lossy")
    if destination in ("ascii", "ansi"):
        args.extend(["--color", "never", "--terminal-width", "80"])
    result = run(args, data)
    assert result.returncode == 0, (source, destination, result.stderr)
    return result.stdout


# Exercise every declared format pair with an independently specified result.
csv = b'name,value\n"A, B",12\nZ,3\n'
formats = ("csv", "tsv", "markdown", "ir", "ascii", "ansi")
for source in formats:
    data = convert("csv", source, csv)
    for destination in formats:
        encoded = convert(source, destination, data)
        assert convert(destination, "csv", encoded) == csv, (source, destination)

# The versioned wire grammar is an independent, byte-exact interoperability
# contract, including header presence, empty cells and all reserved bytes.
wire_input = b'head,value\n"\x1b\x1c\x1d\x1e\x1f",\n'
wire_expected = b'\x1cT1\x1dhead\x1fvalue\x1e\x1be\x1bf\x1bg\x1br\x1bu\x1f\x1e\x1c'
assert convert("csv", "ir", wire_input) == wire_expected
assert convert("ir", "csv", wire_expected) == b'head,value\n\x1b\x1c\x1d\x1e\x1f,\n'
without_header = run(["--from", "csv", "--to", "ir", "--no-header"], b'a,b\n')
assert without_header.returncode == 0 and without_header.stdout == b'\x1cT1a\x1fb\x1e\x1c'

# Independent predecessor executable is the oracle for the existing renderer.
tsv = b"Name\tCount\nAlice\t12\nBob\t2\n"
args = ["--color", "never", "--terminal-width", "80"]
expected = subprocess.run([renderer, "--ascii", *args], input=tsv,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=30, check=True)
actual = run(["--from", "tsv", "--to", "ascii", *args], tsv)
assert actual.returncode == 0, actual.stderr
assert actual.stdout == expected.stdout

# Fixed-width rendering must emit a row while stdin remains open.
stream = subprocess.Popen([binary, "--from", "tsv", "--to", "ascii", "--widths", "5,5", "--color", "never"],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
seen = threading.Event()
def watch():
    for line in stream.stdout:
        if b"Alice" in line and b"12" in line:
            seen.set()
            return
reader = threading.Thread(target=watch, daemon=True)
reader.start()
try:
    stream.stdin.write(b"Name\tCount\nAlice\t12\n")
    stream.stdin.flush()
    assert seen.wait(10), "fixed-width output did not stream before EOF"
    stream.stdin.close()
    assert stream.wait(timeout=10) == 0, stream.stderr.read()
finally:
    if stream.poll() is None:
        stream.kill()
        stream.wait()
    reader.join(timeout=10)
    stream.stdout.close()
    stream.stderr.close()

# Errors must remain visible and avoid partial buffered output.
invalid = [
    (["--from", "csv", "--to", "tsv"], b'head\n"line\nline"\n'),
    (["--from", "csv", "--to", "csv"], b'a,b\n1\n'),
    (["--from", "ascii", "--to", "csv"], b'+---+\n| x |\n+---+\n'),
    (["--from", "ansi", "--to", "csv", "--allow-lossy"], b'\x1b]0;bad\x07'),
]
for args, data in invalid:
    result = run(args, data)
    assert result.returncode != 0 and result.stderr and not result.stdout, (args, result)

result = run(["--from", "csv", "--to", "ansi", "--color", "never"],
             b'name\n"evil\x1b[31m\nnext"\n')
assert result.returncode == 0 and b"\x1b" not in result.stdout
assert "�".encode() in result.stdout
