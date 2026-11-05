# Table intermediate representation, version 1

This is a byte format for exactly one table, not terminal output. Its fields are
valid UTF-8 strings and may contain any Unicode scalar value, including NUL,
newlines, ESC and FS/GS/RS/US. Offsets below are byte values in hexadecimal.

```
document = FS "T1" [ GS row ] *row FS
row      = field *( US field ) RS
field    = *( ordinary / escape )
escape   = ESC ( "e" / "f" / "g" / "r" / "u" )
FS = 1c; GS = 1d; RS = 1e; US = 1f; ESC = 1b
```

`e`, `f`, `g`, `r`, and `u` encode literal ESC, FS, GS, RS, and US,
respectively. `ordinary` is any byte except those five, provided the decoded
field is valid UTF-8. No other escape is legal. GS marks the sole header row,
which must come first; it is absent when there is no header. Every row has at
least one field, and all rows in a table have the same field count. A row with
one empty field is `RS`; two empty fields are `US RS`. A table with no rows is
`FS T1 FS`, distinct from a table with an empty header. EOF before the closing
FS, data after it, a bare structural marker in a field, invalid UTF-8, invalid
escapes, and ragged rows are errors. These constraints give one representation
per valid model and make concatenation or recovery from truncation explicit
errors rather than guesses.

The intermediate form preserves cell contents, header presence, row order, and
column count. It does not encode source dialect, alignment, formatting, color or
styling. Rendered tables may be clipped, padded or sanitized, and are not
assumed reversible. Input formats unable to represent a given cell must reject
it or document an explicit lossy mode; they must not silently drop bytes.
