"""Differential CSV round trips against Python's standard-library CSV parser."""
import csv
import io
import random
import subprocess
import sys

binary = sys.argv[1]
rng = random.Random(20261105)
alphabet = 'ab,"\r\n\\\t界é' + ''.join(map(chr, range(0, 32)))
rows = [["header", "value", "empty"]]
rows.extend([[f"ascii-{code}", chr(code), ""] for code in range(128)])
rows.extend([[f"random-{i}", ''.join(rng.choice(alphabet) for _ in range(rng.randrange(25))), ""] for i in range(128)])
source = io.StringIO(newline="")
csv.writer(source, lineterminator="\r\n").writerows(rows)


def convert(data, source_format, destination):
    result = subprocess.run([binary, "--from", source_format, "--to", destination], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode:
        raise AssertionError(f"{source_format} -> {destination}: {result.stderr!r}")
    return result.stdout


encoded = source.getvalue().encode("utf-8")
intermediate = convert(encoded, "csv", "ir")
converted = convert(intermediate, "ir", "csv")
actual = list(csv.reader(io.StringIO(converted.decode("utf-8"), newline=""), strict=True))
assert actual == rows, "Python CSV reader found changed, missing or extra fields"
assert list(csv.reader(io.StringIO(convert(encoded, "csv", "csv").decode("utf-8"), newline=""), strict=True)) == rows
