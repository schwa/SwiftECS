default:
	just --list

preview-docs:
	swift package --disable-sandbox preview-documentation --target SwiftECS

check-docs:
	swift package --allow-writing-to-directory /tmp/SwiftECS-docs generate-documentation --target SwiftECS --warnings-as-errors --output-path /tmp/SwiftECS-docs

benchmark entities="100000" workers="4 6 12 18" work="0 10 50 200":
	#!/usr/bin/env bash
	set -euo pipefail
	xcb build Benchmark -c release >/dev/null
	binary=$(xcb executable-path Benchmark -c release | tail -1)
	header="| Work per entity | Serial |"
	divider="|---|---:|"
	for workers in {{workers}}; do
		header+=" $workers workers |"
		divider+="---:|"
	done
	echo "$header"
	echo "$divider"
	for work in {{work}}; do
		frames=$(( work >= 50 ? 10 : 50 ))
		row="| $work iterations |"
		for parallelism in 0 {{workers}}; do
			ms=$(ECS_ENTITIES={{entities}} ECS_FRAMES=$frames ECS_ROUNDS=3 ECS_WORK=$work ECS_PARALLELISM=$parallelism "$binary" 2>/dev/null | awk -F= '/ms_per_frame/ {print $2}')
			row+=" $(printf '%.1f' "$ms") |"
		done
		echo "$row"
	done
