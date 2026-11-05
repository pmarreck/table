use table::{parse_delimited, write_delimited, Table};

#[test]
fn csv_quoting_multiline_crlf_and_empty_cells() {
    let t = parse_delimited("name,value,empty\r\n\"a, b\",\"x\"\"y\nline\",\r\n", true, true).unwrap();
    assert_eq!(t, Table { header: Some(vec!["name".into(), "value".into(), "empty".into()]), rows: vec![vec!["a, b".into(), "x\"y\nline".into(), "".into()]] });
    assert_eq!(parse_delimited(&write_delimited(&t, true).unwrap(), true, true).unwrap(), t);
    assert!(write_delimited(&t, false).is_err());
}

#[test]
fn rejects_invalid_and_ragged_input() {
    for bad in ["\"unterminated", "\"x\"tail", "abc\"def", "a,b\nc", "a\rb"] { assert!(parse_delimited(bad, true, false).is_err(), "accepted {bad:?}"); }
}

#[test]
fn tsv_preserves_trailing_empty_fields_and_empty_rows() {
    let t = parse_delimited("a\t\r\n\t\r\n", false, false).unwrap();
    assert_eq!(t.rows, vec![vec!["a", ""], vec!["", ""]]);
    assert_eq!(parse_delimited(&write_delimited(&t, false).unwrap(), false, false).unwrap(), t);
}
