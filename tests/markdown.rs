use table::{markdown, Table};

#[test]
fn escapes_punctuation_and_round_trips() {
    let table = Table { header: Some(vec!["A | B".into(), "path\\name".into()]), rows: vec![vec!["[link](https://x) & *markup*".into(), "世界".into()]] };
    let text = markdown::write(&table).unwrap();
    assert!(text.contains("A \\| B"));
    assert!(text.contains("path\\\\name"));
    assert_eq!(markdown::parse(&text).unwrap(), table);
}

#[test]
fn accepts_common_table_dialects() {
    let table = markdown::parse("name | value\r\n:--- | ---:\r\na\\|b | c\\\\d\r\n").unwrap();
    assert_eq!(table.header.unwrap(), vec!["name", "value"]);
    assert_eq!(table.rows, vec![vec!["a|b", "c\\d"]]);
}

#[test]
fn unsupported_or_ambiguous_inputs_fail() {
    for bad in ["", "a\n", "a\n--\n", "a | b\n---\n", "a\n---\nx | y\n", "a\n---\n\0\n"] { assert!(markdown::parse(bad).is_err(), "accepted {bad:?}"); }
    for value in [" leading", "trailing ", "line\nbreak", "tab\there"] {
        let t = Table { header: Some(vec![value.into()]), rows: vec![] };
        assert!(markdown::write(&t).is_err());
    }
    assert!(markdown::write(&Table { header: None, rows: vec![vec!["x".into()]] }).is_err());
}
