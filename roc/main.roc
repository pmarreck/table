app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst",
	unicode: "https://github.com/roc-lang/unicode/releases/download/4.2.0/4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w.tar.zst",
}
import Model
import BuildInfo
import pf.Console
import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.Stdin
import pf.Stdout
import pf.Stderr
import unicode.Scalar

main! = |native_args| {
	var $args = []
	for arg in native_args {
		match OsStr.to_str_try(arg) {
			Ok(s) => {
				$args = $args.append(s)
			}
			Err(_) => {
				Stderr.line!("table: arguments must be UTF-8") ?? {}
				return Err(Exit(1))
			}
		}
	}
	match run!($args) {
		Ok({}) => Ok({})
		Err(Invalid(message)) => {
			Stderr.line!("table: ${message}") ?? {}
			Err(Exit(1))
		}
		Err(_) => {
			Stderr.line!("table: input/output failed") ?? {}
			Err(Exit(1))
		}
	}
}

help = "Usage: table [--from auto|csv|tsv|markdown|ir|ascii|ansi] --to csv|tsv|markdown|ir|ascii|ansi [--header|--no-header]\nInput format is detected when --from is omitted. Ambiguous input requires --from.\nAutodetection buffers stdin; explicit --from tsv retains fixed-width visual streaming.\nVisual output: --widths, --align, --overflow, --terminal-width, --color, --plain, --decimal-separator.\n"

formats = ["csv", "tsv", "markdown", "ir", "ascii", "ansi"]

auto_color! = || Console.width!() > 0 and Env.var_str!("NO_COLOR").is_err() and (Env.var_str!("TERM") ?? "") != "dumb"

run! = |args| {
	var $from = "auto"
	var $to = ""
	var $to_set = False
	var $header = True
	var $header_explicit = False
	var $allow = False
	var $glyphs = []
	var $color = False
	var $opts = []
	var $i = 0
	while $i < args.len() {
		raw = args.get($i) ?? ""
		$i = $i + 1
		parts = raw.split_on("=")
		key = parts.first() ?? ""
		inline = parts.len() > 1
		match key {
			"--from" | "--to" | "--visual-glyphs" | "--widths" | "--align" | "--overflow" | "--terminal-width" | "--color" | "--decimal-separator" => {
				value = if inline Str.join_with(parts.drop_first(1), "=") else {
					v = args.get($i).map_err(|_| Invalid("${key} requires a value"))?
					$i = $i + 1
					v
				}
				match key {
					"--from" => {
						$from = value
					}
					"--to" => {
						$to = value
						$to_set = True
					}
					"--visual-glyphs" => {
						$glyphs = [value]
					}
					_ => {
						v = if key == "--color" and value == "auto" (if auto_color!() "always" else "never") else value
						if key == "--color" {
							$color = True
						}
						$opts = $opts.append(key).append(v)
					}
				}
			}
			"--allow-lossy" if !inline => {
				$allow = True
			}
			"--header" if !inline => {
				$header = True
				$header_explicit = True
			}
			"--no-header" if !inline => {
				$header = False
				$header_explicit = True
			}
			"--plain" if !inline => {
				$opts = $opts.append(key)
			}
			"--about" if !inline => return Stdout.line!(BuildInfo.about)
			"--help" | "-h" if !inline => return Stdout.write!(help)
			_ => return Err(Invalid("unknown option: ${raw}"))
		}
	}
	if !$to_set {
		return Err(Invalid("--to is required"))
	}
	if !formats.contains($to) {
		return Err(Invalid("output formats: csv, tsv, markdown, ir, ascii, ansi"))
	}
	auto = $from == "auto"
	var $input = []
	if auto {
		$input = Stdin.read_to_end!()?
		$from = Model.detect($input, $glyphs)?
	}
	if !formats.contains($from) {
		return Err(Invalid("input formats: auto, csv, tsv, markdown, ir, ascii, ansi"))
	}
	if $header_explicit and $from != "csv" and $from != "tsv" {
		return Err(Invalid("--header and --no-header apply only to CSV or TSV input"))
	}
	vis = $to == "ascii" or $to == "ansi"
	vin = $from == "ascii" or $from == "ansi"
	if vin and !$allow {
		return Err(Invalid("visual input is lossy; pass --allow-lossy to accept padding removal and possible prior clipping"))
	}
	if !vin and ($allow or $glyphs.len() > 0) {
		return Err(Invalid("--allow-lossy and --visual-glyphs require visual input"))
	}
	if !vis and $opts.len() > 0 {
		return Err(Invalid("display options require ASCII or ANSI output"))
	}
	if vis and !$color {
		$opts = $opts.append("--color").append(if auto_color!() "always" else "never")
	}
	if vis and $from != "tsv" and !$opts.contains("--terminal-width") {
		columns = env_columns(Env.var_str!("COLUMNS") ?? "")
		width = if columns > 0 and columns <= 10000 columns else Console.width!()
		if width > 0 {
			$opts = $opts.append("--terminal-width").append(width.to_str())
		}
	}
	if $from == "tsv" and vis and !auto {
		Stderr.line!("table: visual output may clip, pad, or sanitize cell contents")?
		_ = render!([], True, $to == "ascii", $header, $opts)?
		return Ok({})
	}
	if !auto {
		$input = Stdin.read_to_end!()?
	}
	table = Model.parse($from, $input, $header, $glyphs)?
	output = if vis {
		Stderr.line!("table: visual output may clip, pad, or sanitize cell contents")?
		render!(Model.render_input(table)?.to_utf8(), False, $to == "ascii", Model.has_header(table), $opts)?
	} else Model.write(table, $to)?
	Stdout.write_bytes!(output)
}

env_columns = |text| {
	var $started = False
	var $value = ""
	for item in Scalar.iter(text) {
		cp = Scalar.to_u32(item.scalar)
		white = (cp >= 9 and cp <= 13) or cp == 32 or cp == 0x85 or cp == 0xa0 or cp == 0x1680 or (cp >= 0x2000 and cp <= 0x200a) or cp == 0x2028 or cp == 0x2029 or cp == 0x202f or cp == 0x205f or cp == 0x3000
		if $started or !white {
			$started = True
			$value = $value.concat(Scalar.to_str(item.scalar) ?? "")
		}
	}
	bytes = $value.to_utf8()
	digits = if bytes.first() == Ok(43) bytes.drop_first(1) else bytes
	if digits.len() == 0 or !digits.all(|b| b >= 48 and b <= 57) {
		return 0
	}
	U64.from_str(Str.from_utf8_lossy(digits)) ?? 0
}

renderer! = || {
	executable = Env.exe_path!().map_err(|_| Invalid("cannot locate table executable"))?
	path = Path.to_str(executable).map_err(|_| Invalid("cannot locate table executable"))?
	parts = path.split_on("/")
	directory = Str.join_with(parts.drop_last(1), "/")
	root = Str.join_with(parts.drop_last(2), "/")
	for candidate in ["${directory}/libexec/tsv-to-ansi-table", "${root}/libexec/tsv-to-ansi-table"] {
		if Path.exists!(Path.utf8(candidate)) ?? False {
			return Ok(candidate)
		}
	}
	Ok(BuildInfo.renderer)
}

render! = |bytes, inherit, ascii, header, options| {
	program = renderer!()?
	var $args = []
	if !header {
		$args = $args.append("--no-header")
	}
	if ascii {
		$args = $args.append("--ascii")
	}
	cmd = Cmd.new(OsStr.utf8(program)).args($args.concat(options).map(OsStr.utf8))
	if inherit {
		status = cmd.exec_exit_code!().map_err(|_| Invalid("cannot start renderer"))?
		if status != 0 {
			return Err(Invalid("renderer exited with exit status: ${status.to_str()}"))
		}
		return Ok([])
	}
	result = cmd.stdin(Bytes(bytes)).output_limit(18_446_744_073_709_551_615).exec_output_bytes!()
	match result {
		Ok(value) => Ok(value.stdout_bytes)
		Err(NonZeroExitCodeB(value)) => Err(Invalid("renderer: ${Str.from_utf8_lossy(value.stderr_bytes).trim()}"))
		Err(_) => Err(Invalid("cannot start renderer"))
	}
}
