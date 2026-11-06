import Intermediate

main! = |_args| {
	echo!("table intermediate tests")
	Ok({})
}

expect Intermediate.encode(NoHeader, []) == Ok([28, 84, 49, 28])
