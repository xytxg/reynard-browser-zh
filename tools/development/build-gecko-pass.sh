#!/bin/bash

# Runs one CI pass of a Gecko build that may need several jobs to finish.
#
# A cold Gecko build (new Firefox release, new toolchain) does not fit in one
# GitHub-hosted macOS job: gkrust alone is a multi-hour Rust LTO step that
# sccache cannot cache, and the final XUL link comes after it. Each pass
# therefore keeps the real object directory, so the next pass continues the
# same make/cargo build instead of starting over:
#
#   normalize-sources  give every Gecko source file one fixed timestamp, so
#                      objects from an earlier job are never older than a
#                      freshly checked out source file
#   run DEADLINE ARGS  run build-gecko.sh ARGS; at the DEADLINE (Unix time)
#                      stop it cleanly and drop half-written outputs
#   save DIR           archive the object directory and sccache into DIR
#   restore DIR FP     unpack an archive from DIR if it was made with FP
#
# `run` exits 0 when Gecko is built, 75 when it stopped at the deadline and can
# resume, and with the build's own status for a real build failure.

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"
OBJDIR_NAME="obj-aarch64-apple-ios"
OBJDIR="$FIREFOX_DIR/$OBJDIR_NAME"
SOURCE_MTIME="${GECKO_SOURCE_MTIME:-202001010000}"
RESUMABLE=75

log() {
	echo "[gecko-pass] $*"
}

normalize_sources() {
	if [ ! -d "$FIREFOX_DIR" ]; then
		echo "Missing Gecko source at $FIREFOX_DIR" >&2
		exit 1
	fi
	log "setting Gecko source timestamps to $SOURCE_MTIME"
	find "$FIREFOX_DIR" \( -path "$FIREFOX_DIR/$OBJDIR_NAME" -o -path "$FIREFOX_DIR/.git" \) -prune \
		-o -exec touch -h -t "$SOURCE_MTIME" {} +
}

# Processes whose command line names the Gecko tree: compilers, linkers,
# build scripts. This script and the shell that started it are never included.
build_pids() {
	pgrep -f "$FIREFOX_DIR" 2>/dev/null | grep -vx -e "$$" -e "$PPID" || true
}

stop_build() {
	local group="$1" waited

	# Anything written from a minute before the stop on may be incomplete.
	local marker="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/gecko-pass-stop-marker"
	touch "$marker"
	python3 - "$marker" <<'PY'
import os, sys, time
stamp = time.time() - 60
os.utime(sys.argv[1], (stamp, stamp))
PY

	# SIGTERM, not SIGINT: a background job of a non-interactive shell starts
	# with SIGINT ignored. make deletes the targets it was building, and
	# clang/rustc remove their partial outputs, on SIGTERM as well.
	log "time budget reached; stopping the build"
	kill -TERM -- "-$group" 2>/dev/null || true
	waited=0
	while kill -0 "$group" 2>/dev/null && [ "$waited" -lt 120 ]; do
		sleep 5
		waited=$((waited + 5))
	done
	kill -KILL -- "-$group" 2>/dev/null || true

	# sccache runs compilers from its own server process, outside the build's
	# process group. Stop it and every remaining compiler/linker that still
	# writes into the Gecko tree before anything is archived.
	"${SCCACHE_PATH:-sccache}" --show-stats 2>/dev/null || true
	"${SCCACHE_PATH:-sccache}" --stop-server >/dev/null 2>&1 || true
	waited=0
	local pids
	pids="$(build_pids)"
	while [ -n "$pids" ] && [ "$waited" -lt 120 ]; do
		# shellcheck disable=SC2086 # one pid per word
		kill -KILL $pids 2>/dev/null || true
		sleep 5
		waited=$((waited + 5))
		pids="$(build_pids)"
	done
	if [ -n "$pids" ]; then
		echo "Gecko build processes are still running after the stop:" >&2
		# shellcheck disable=SC2086
		ps -o pid,args -p "$(echo $pids | tr ' ' ',')" >&2 || true
		exit 1
	fi

	if [ -d "$OBJDIR" ]; then
		local removed
		removed="$(find "$OBJDIR" -type f -newer "$marker" ! -path "$OBJDIR/.mozbuild/*" -print -delete | wc -l | tr -d ' ')"
		log "removed $removed possibly incomplete build outputs"
	fi
	rm -f "$marker"
}

run_pass() {
	local deadline="$1" pid rc
	shift
	case "$deadline" in
		'' | *[!0-9]*)
			echo "run needs a Unix time deadline" >&2
			exit 2
			;;
	esac

	# Job control puts the build into its own process group, so the whole
	# mach/make/cargo tree can be signalled at once.
	set -m
	GECKO_SOURCE_MTIME="$SOURCE_MTIME" "$SCRIPT_DIR/build-gecko.sh" "$@" &
	pid=$!
	set +m
	log "build started (pid $pid), deadline $(date -r "$deadline" 2>/dev/null || date -d "@$deadline")"

	while kill -0 "$pid" 2>/dev/null; do
		if [ "$(date +%s)" -ge "$deadline" ]; then
			stop_build "$pid"
			wait "$pid" 2>/dev/null || true
			exit "$RESUMABLE"
		fi
		sleep 15
	done

	set +e
	wait "$pid"
	rc=$?
	set -e
	exit "$rc"
}

compressor() {
	if command -v zstd >/dev/null 2>&1; then
		echo zstd
	else
		echo "zstd is required to archive the Gecko build" >&2
		exit 1
	fi
}

save_state() {
	local out="$1" fingerprint="$2"
	local zstd_bin
	zstd_bin="$(compressor)"
	mkdir -p "$out"
	test -d "$OBJDIR"
	printf '%s\n' "$fingerprint" > "$out/fingerprint"
	# pax keeps sub-second timestamps, which make and cargo compare.
	tar --format pax -C "$FIREFOX_DIR" -cf - "$OBJDIR_NAME" | "$zstd_bin" -T0 -3 -q -o "$out/objdir.tar.zst"
	if [ -n "${SCCACHE_DIR:-}" ] && [ -d "$SCCACHE_DIR" ]; then
		tar --format pax -C "$(dirname "$SCCACHE_DIR")" -cf - "$(basename "$SCCACHE_DIR")" |
			"$zstd_bin" -T0 -1 -q -o "$out/sccache.tar.zst"
	fi
	ls -l "$out"
}

restore_state() {
	local in="$1" fingerprint="$2"
	local zstd_bin
	zstd_bin="$(compressor)"
	if [ -f "$in/sccache.tar.zst" ] && [ -n "${SCCACHE_DIR:-}" ]; then
		mkdir -p "$(dirname "$SCCACHE_DIR")"
		rm -rf "$SCCACHE_DIR"
		"$zstd_bin" -dc "$in/sccache.tar.zst" | tar -xpf - -C "$(dirname "$SCCACHE_DIR")"
		rm -f "$in/sccache.tar.zst"
	fi
	if [ ! -f "$in/objdir.tar.zst" ]; then
		echo "No saved Gecko object directory in $in" >&2
		exit 1
	fi
	if [ "$(cat "$in/fingerprint" 2>/dev/null || true)" != "$fingerprint" ]; then
		# A different compiler, SDK or source set would mix incompatible objects.
		log "saved object directory was built with a different toolchain or source; starting clean"
		log "saved:   $(cat "$in/fingerprint" 2>/dev/null || echo none)"
		log "current: $fingerprint"
		rm -f "$in/objdir.tar.zst"
		return 0
	fi
	rm -rf "$OBJDIR"
	"$zstd_bin" -dc "$in/objdir.tar.zst" | tar -xpf - -C "$FIREFOX_DIR"
	rm -f "$in/objdir.tar.zst"
	log "restored $(du -sh "$OBJDIR" | cut -f1) object directory"
}

command="${1:-}"
[ "$#" -gt 0 ] && shift
case "$command" in
	normalize-sources)
		normalize_sources
		;;
	run)
		run_pass "$@"
		;;
	save)
		save_state "${1:?save needs an output directory}" "${2:?save needs a fingerprint}"
		;;
	restore)
		restore_state "${1:?restore needs an input directory}" "${2:?restore needs a fingerprint}"
		;;
	*)
		echo "Usage: $0 normalize-sources | run DEADLINE [build args] | save DIR FINGERPRINT | restore DIR FINGERPRINT" >&2
		exit 2
		;;
esac
