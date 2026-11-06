import unicode.Grapheme
import unicode.Scalar
import unicode.EastAsianWidth
import unicode.GeneralCategory
import unicode.Emoji

Text :: [].{
	repeat = |text, count| {
		var $out = ""
		for _ in 0..<count { $out = Str.concat($out, text) }
		$out
	}
	pad = |text, size, alignment| {
		w = width(text)
		gap = if size > w size - w else 0
		left = if alignment == "right" gap else if alignment == "center" gap // 2 else 0
		"${repeat(" ", left)}${text}${repeat(" ", gap - left)}"
	}
	clip = |text, size, policy, ascii| {
		clip_with(text, size, policy, if ascii "..." else "…")
	}
	clip_with = |text, size, policy, glyph| {
		if width(text) <= size { return text }
		mode = if policy == "auto" {
			if text.contains("/") or text.contains("\\") "prefix-ellipsis" else "suffix-ellipsis"
		} else policy
		ellipsis = mode == "prefix-ellipsis" or mode == "suffix-ellipsis"
		marker = if !ellipsis "" else clusters(glyph).take_first(size) |> Str.join_with("")
		budget = size - width(marker)
		parts = clusters(text)
		from_end = mode == "prefix-ellipsis" or mode == "truncate-left"
		var $result = ""
		var $used = 0
		var $i = 0
		var $done = False
		while $i < parts.len() and !$done {
			index = if from_end parts.len() - $i - 1 else $i
			part = parts.get(index) ?? ""
			w = width(part)
			if $used + w > budget { $done = True } else {
				$result = if from_end Str.concat(part, $result) else Str.concat($result, part)
				$used = $used + w
			}
			$i = $i + 1
		}
		if from_end Str.concat(marker, $result) else Str.concat($result, marker)
	}
	width = |text| clusters(text).fold(0, |sum, cluster| sum + cluster_width(cluster))
	clusters = |text| Grapheme.slices(text)
	safe = |text| {
		clean = Scalar.iter(text).fold("", |out, item| {
		cp = Scalar.to_u32(item.scalar)
		category = GeneralCategory.short(GeneralCategory.of_scalar(item.scalar))
		bad = category == "Cc" or category == "Zl" or category == "Zp" or (category == "Cf" and cp != 0x200D and cp != 0x200C and !(cp >= 0xE0020 and cp <= 0xE007F))
		Str.concat(out, if bad "�" else Scalar.to_str(item.scalar) ?? "�")
		})
		clusters(clean).map(|cluster| if cluster_width(cluster) == 0 "◌${cluster}" else cluster) |> Str.join_with("")
	}
}

cluster_width : Str -> U64
cluster_width = |cluster| {
	var $width = 0
	var $emoji = False
	for item in Scalar.iter(cluster) {
		cp = Scalar.to_u32(item.scalar)
		category = GeneralCategory.short(GeneralCategory.of_scalar(item.scalar))
		if Emoji.has_default_emoji_presentation(item.scalar) or cp == 0xFE0F or cp == 0x20E3 { $emoji = True }
		if category != "Mn" and category != "Me" and category != "Cf" {
			w = match EastAsianWidth.of_scalar(item.scalar) {
				Wide | Fullwidth => 2
				_ => 1
			}
			$width = if w > $width w else $width
		}
	}
	if $emoji 2 else $width
}
expect Text.width("hello") == 5
expect Text.width("界") == 2
expect Text.width("e\u(301)") == 1
expect Text.width("👩‍💻") == 2
expect Text.width("🇺🇸") == 2
expect Text.width("1️⃣") == 2
expect Text.clusters("ae\u(301)界") == ["a", "e\u(301)", "界"]
expect Text.safe("x\u(1b)[31m\u(7)\u(202e)y") == "x�[31m��y"

expect Text.clip("abcdef", 4, "truncate-right", False) == "abcd"
expect Text.clip("abcdef", 4, "truncate-left", False) == "cdef"
expect Text.clip("abcdef", 4, "suffix-ellipsis", False) == "abc…"
expect Text.clip("abcdef", 4, "prefix-ellipsis", False) == "…def"
expect Text.clip("/abc/file.txt", 6, "auto", False) == "…e.txt"
expect Text.clip("abcdef", 2, "suffix-ellipsis", True) == ".."
expect Text.clip("e\u(301)界xx", 3, "truncate", False) == "e\u(301)界"
expect Text.clip("a👩‍💻z", 2, "prefix-ellipsis", False) == "…z"
expect Text.clip("界", 1, "truncate", False) == ""
expect Text.pad("12", 5, "right") == "   12"
expect Text.pad("a", 4, "center") == " a  "
expect Text.pad("界", 3, "left") == "界 "

expect Text.width(Text.clip("/home/example/very-long-report.tsv", 25, "auto", False)) == 25
expect Text.width("…") == 1
expect Text.width(".") == 1

expect Text.safe("\u(301)") == "◌\u(301)"
expect Text.safe("\u(200d)") == "◌\u(200d)"
