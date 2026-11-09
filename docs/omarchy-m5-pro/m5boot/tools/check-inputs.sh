#!/bin/sh
# Verify each payload input against the SHA-256 listed in spec/inputs.md. Fails on any mismatch/unlisted file.
for f in "$@"; do
	[ -n "$f" ] || continue
	h=$(sha256sum "$f" | cut -d' ' -f1)
	# path and hash on the same line, each as a whole token (with or without backticks: the task-17 slim table has none)
	# task 15: the task-24 DTB line is prose ("path, size, sha256 hash."), so "," and "." also end a token
	grep -F "$f" spec/inputs.md | grep -qE "(^|[\` |])$f([\` |,.]|\$).*(^|[\` |])$h([\` |,.]|\$)" || { echo "check-inputs: $f ($h) not listed in spec/inputs.md" >&2; exit 1; }
	echo "check-inputs: ok $f"
done
