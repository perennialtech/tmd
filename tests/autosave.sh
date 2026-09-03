#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

home_dir="$test_root/home"
data_dir="$test_root/data"
capture_file="$test_root/server-input"
expected_file="$test_root/expected"
invalid_output="$test_root/invalid-output"

mkdir -p \
	"$home_dir/server/LaunchUtils" \
	"$home_dir/server/tModLoader-Logs" \
	"$data_dir"

cat >"$home_dir/server/LaunchUtils/ScriptCaller.sh" <<'EOF'
#!/bin/sh

set -eu

: "${CAPTURE_FILE:?}"

while IFS= read -r server_command; do
	printf '%s\n' "$server_command" >>"$CAPTURE_FILE"

	if [ "$server_command" = save ]; then
		exit 0
	fi
done

exit 1
EOF
chmod 0755 "$home_dir/server/LaunchUtils/ScriptCaller.sh"

if env \
	HOME="$home_dir" \
	ISDOCKER=1 \
	TML_WORKSHOP_IDS="" \
	TML_AUTOSAVE_INTERVAL_SECONDS=0 \
	bash "$repo_root/manage-tModLoaderServer.sh" \
	start \
	--folder "$data_dir" \
	>"$invalid_output" 2>&1; then
	echo "An invalid autosave interval was accepted" >&2
	exit 1
fi

if ! grep -Fx \
	"TML_AUTOSAVE_INTERVAL_SECONDS must be a canonical positive decimal integer" \
	"$invalid_output" >/dev/null; then
	echo "The invalid autosave interval did not produce the expected error" >&2
	cat "$invalid_output" >&2
	exit 1
fi

if ! printf 'playing\n' |
	timeout 15s env \
		HOME="$home_dir" \
		ISDOCKER=1 \
		CAPTURE_FILE="$capture_file" \
		TML_WORKSHOP_IDS="" \
		TML_AUTOSAVE_INTERVAL_SECONDS=1 \
		bash "$repo_root/manage-tModLoaderServer.sh" \
		start \
		--folder "$data_dir"; then
	echo "The autosave integration server did not exit successfully" >&2
	exit 1
fi

printf 'playing\nsave\n' >"$expected_file"

if ! cmp -s "$expected_file" "$capture_file"; then
	echo "The server did not receive console input followed by an autosave command" >&2
	diff -u "$expected_file" "$capture_file" >&2 || :
	exit 1
fi
