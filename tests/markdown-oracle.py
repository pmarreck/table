"""Check Markdown output's rendered cell text with GitHub's GFM parser."""
import csv
import io
import string
import subprocess
import sys
from html.parser import HTMLParser

binary = sys.argv[1]
values = list(string.punctuation) + [r"\|", r"\\|", "&amp;", "<b>x</b>", "[x](https://example.test)", "**strong**", "`code`", "界", "e\u0301", "👩\u200d💻"]
rows = [["value"]] + [[value] for value in values]
source = io.StringIO(newline="")
csv.writer(source, lineterminator="\n").writerows(rows)
converted = subprocess.run([binary, "--from", "csv", "--to", "markdown"], input=source.getvalue().encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
assert converted.returncode == 0, converted.stderr
rendered = subprocess.run(["cmark-gfm", "-e", "table"], input=converted.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
assert rendered.returncode == 0, rendered.stderr


class Cells(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.cells = []
        self.current = None

    def handle_starttag(self, tag, attrs):
        if tag in ("th", "td"):
            assert self.current is None
            self.current = ""

    def handle_data(self, data):
        if self.current is not None:
            self.current += data

    def handle_endtag(self, tag):
        if tag in ("th", "td"):
            assert self.current is not None
            self.cells.append(self.current)
            self.current = None


parser = Cells()
parser.feed(rendered.stdout.decode())
assert parser.cells == [row[0] for row in rows], f"rendered cells changed: {parser.cells!r}"
