use table::visual_input::parse;

#[test]
fn parses_standard_borders_and_header() {
    let t = parse("+------+---+\n| name | n |\n+------+---+\n| A    | 2 |\n+------+---+\n", false, None).unwrap();
    assert_eq!(t.header.unwrap(), vec!["name", "n"]);
    assert_eq!(t.rows, vec![vec!["A", "2"]]);
    let u = parse("┌─────┐\n│ abc │\n└─────┘\n", true, None).unwrap();
    assert!(u.header.is_none());
    assert_eq!(u.rows, vec![vec!["abc"]]);
}

#[test]
fn custom_ascii_glyphs_are_explicit() {
    let t = parse("*~~~*\n! x !\n*~~~*\n", false, Some("*,*,*,*,*,*,*,*,*,~,!" )).unwrap();
    assert_eq!(t.rows, vec![vec!["x"]]);
}

#[test]
fn rejects_ambiguous_or_dangerous_tables() {
    for bad in ["+---+\n| | |\n+---+\n", "+---+\n| x |\n+----+\n", "+---+\n| 界 |\n+---+\n", "+---+\n| x |\n+---+\n| y |\n+---+\n| z |\n+---+\n"] { assert!(parse(bad, false, None).is_err(), "accepted {bad:?}"); }
    assert!(parse("\x1b]0;evil\x07+---+\n| x |\n+---+\n", true, None).is_err());
    assert!(parse("\x1b[2J+---+\n| x |\n+---+\n", true, None).is_err());
    assert!(parse("\x1b[31m+---+\x1b[0m\n| x |\n+---+\n", false, None).is_err());
    assert!(parse("\x1b[31m+---+\x1b[0m\n| x |\n+---+\n", true, None).is_ok());
}

#[test]
fn rejects_wrong_unicode_junctions_and_escapes_instead_of_executing_them() {
    assert!(parse("┌───┐───┐\n│ a │ b │\n└───┴───┘\n", true, None).is_err());
    assert!(parse("+---+\n| x |\n+---+\n\x1b[1A", true, None).is_err());
}

#[test]
fn validates_wide_and_combining_graphemes_by_display_width() {
    let text = "┌──────┐\n│ 界 e\u{301} │\n└──────┘\n";
    let table = parse(text, true, None).unwrap();
    assert_eq!(table.rows, vec![vec!["界 e\u{301}"]]);
    let unsafe_text = "┌───┐\n│ \u{202e}x │\n└───┘\n";
    assert!(parse(unsafe_text, true, None).is_err());
}

#[test]
fn custom_unicode_and_letter_glyphs_are_checked_by_display_width() {
    let rounded = "╭───╮\n│ x │\n╰───╯\n";
    let glyphs = "╭,┬,╮,├,┼,┤,╰,┴,╯,─,│";
    assert_eq!(parse(rounded, true, Some(glyphs)).unwrap().rows, vec![vec!["x"]]);
    let letters = "A---C\n! x !\nG---I\n";
    let glyphs = "A,B,C,D,E,F,G,H,I,-,!";
    assert_eq!(parse(letters, true, Some(glyphs)).unwrap().rows, vec![vec!["x"]]);
    assert!(parse(rounded, true, Some("界,┬,╮,├,┼,┤,╰,┴,╯,─,│")).is_err());
}
