use table::{decode, encode, Table};

#[test]
fn prescribed_wire_vectors() {
    let cases: &[(Table, &[u8])] = &[
        (Table { header: None, rows: vec![] }, b"\x1cT1\x1c"),
        (Table { header: Some(vec!["".into()]), rows: vec![] }, b"\x1cT1\x1d\x1e\x1c"),
        (Table { header: None, rows: vec![vec!["".into(), "".into()]] }, b"\x1cT1\x1f\x1e\x1c"),
        (Table { header: None, rows: vec![vec!["\x1b\x1c\x1d\x1e\x1f".into()]] }, b"\x1cT1\x1be\x1bf\x1bg\x1br\x1bu\x1e\x1c"),
    ];
    for (table, wire) in cases { assert_eq!(&encode(table).unwrap(), wire); assert_eq!(&decode(wire).unwrap(), table); }
}

#[test]
fn every_ascii_scalar_and_unicode_round_trip() {
    for code in 0..=127 {
        let cell = format!("before{}é界\n\0after", char::from(code));
        let table = Table { header: Some(vec![cell.clone(), String::new()]), rows: vec![vec![String::new(), cell]] };
        assert_eq!(decode(&encode(&table).unwrap()).unwrap(), table);
    }
}

#[test]
fn malformed_documents_are_rejected() {
    for wire in [b"".as_slice(), b"\x1cT1", b"\x1cT1\x1d\x1c", b"\x1cT1x\x1c", b"\x1cT1\x1fx\x1c", b"\x1cT1\x1bq\x1e\x1c", b"\x1cT1\xff\x1e\x1c", b"\x1cT1\x1e\x1c!", b"\x1cT1\x1e\x1f\x1e\x1c"] { assert!(decode(wire).is_err(), "accepted {wire:?}"); }
    assert!(encode(&Table { header: None, rows: vec![vec![]] }).is_err());
}
