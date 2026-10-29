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
#   check-toolchain    verify that every tool the object directory's
#                      configuration points at (bootstrapped clang, cbindgen,
#                      node, SDKs, sccache, rustc, Python) still exists; if
#                      not, drop config.status so mach configures (and
#                      bootstraps into the same paths) again
#   save DIR           archive the object directory, ~/.mozbuild and sccache
#                      into DIR
#   restore DIR FP     unpack an archive from DIR if it was made with FP
#                      in the same checkout and home directory
#
# `run` exits 0 when Gecko is built, 75 when it stopped at the deadline and can
# resume, 70 when the build printed nothing within GECKO_STARTUP_MINUTES (a
# hang before any work, which a later pass would only repeat), and with the
# build's own status for a real build failure.

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"
OBJDIR_NAME="obj-aarch64-apple-ios"
OBJDIR="$FIREFOX_DIR/$OBJDIR_NAME"
# configure records absolute paths (topsrcdir, topobjdir, the bootstrapped
# toolchains under the mach state directory, sccache, rustc), so a pass can
# only continue another one at exactly the same locations.
MOZBUILD_DIR="${MOZBUILD_STATE_PATH:-$HOME/.mozbuild}"
SOURCE_MTIME="${GECKO_SOURCE_MTIME:-202001010000}"
RESUMABLE=75
STALLED=70
# mach prints its first line within seconds. A build that has printed nothing
# after this long is stuck before compiling anything (in v0.18.0-zh.4 mach
# waited on terminal-notifier for a whole 320-minute pass).
STARTUP_MINUTES="${GECKO_STARTUP_MINUTES:-20}"

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

# Prints what the build's process group and anything else touching the Gecko
# tree is doing, so a stop or a hang leaves evidence in the job log.
dump_processes() {
	local group="$1"
	echo "[gecko-pass] processes of the build (process group $group):"
	ps -axo pid,ppid,pgid,etime,stat,command 2>/dev/null |
		awk -v g="$group" 'NR == 1 || $3 == g' | cut -c1-300 || true
	local notifier
	notifier="$(pgrep -fl terminal-notifier 2>/dev/null || true)"
	if [ -n "$notifier" ]; then
		echo "[gecko-pass] terminal-notifier is running (set MOZ_NOSPAM=1):"
		echo "$notifier"
	fi
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
	dump_processes "$group"
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

# Prints every absolute tool path recorded in config.status.json that is
# missing on this machine; exit status 3 means the object directory belongs
# to another checkout or objdir path and cannot be continued at all.
missing_tools() {
	python3 - "$OBJDIR/config.status.json" "$FIREFOX_DIR" "$OBJDIR" "$HOME" <<'PY'
import json, os, shlex, sys

status, srcdir, objdir, home = sys.argv[1:5]
with open(status, encoding="utf-8") as fh:
    config = json.load(fh)

def same(a, b):
    return os.path.normpath(a or "") == os.path.normpath(b)

if not same(config.get("topsrcdir"), srcdir) or not same(config.get("topobjdir"), objdir):
    print(f"recorded topsrcdir {config.get('topsrcdir')}, topobjdir {config.get('topobjdir')}", file=sys.stderr)
    sys.exit(3)

# Locations that hold tools, not build outputs: the mach state directory
# and rustup under $HOME, the runner tool cache (sccache), Xcode and
# Homebrew. Paths inside the source or object tree are build outputs.
roots = [home, os.environ.get("RUNNER_TOOL_CACHE", ""), "/Applications", "/opt/homebrew"]
roots = tuple(os.path.normpath(r) + os.sep for r in roots if r)
inside = (os.path.normpath(srcdir) + os.sep, os.path.normpath(objdir) + os.sep)
# Tools a resumed build runs directly. Their recorded path must exist
# wherever it is.
required = {"CC", "CXX", "HOST_CC", "HOST_CXX", "CCACHE", "RUSTC", "CARGO",
            "CBINDGEN", "PYTHON3", "NODEJS", "MOZ_LIBCLANG_PATH"}
# Recorded defaults that are data locations, not tools, and normally do not
# exist (the l10n checkout is only used for repacks). Missing ones must not
# force a reconfigure.
optional = {"L10NBASEDIR"}

def tokens(value):
    if isinstance(value, str):
        try:
            return shlex.split(value)
        except ValueError:
            return value.split()
    if isinstance(value, (list, tuple)):
        return [t for item in value for t in tokens(item)]
    return []

missing = set()
for key, value in config.get("substs", {}).items():
    for token in tokens(value):
        if not token.startswith("/"):
            continue
        path = os.path.normpath(token)
        if path.startswith(inside) or key in optional:
            continue
        if (key in required or path.startswith(roots)) and not os.path.exists(path):
            missing.add(f"{key}={path}")
for line in sorted(missing):
    print(line)
PY
}

check_toolchain() {
	if [ ! -f "$OBJDIR/config.status.json" ]; then
		log "no configured object directory; configure will bootstrap the toolchains"
		return 0
	fi
	local missing rc=0
	missing="$(missing_tools)" || rc=$?
	if [ "$rc" -eq 3 ]; then
		log "object directory was configured for another checkout path; starting clean"
		rm -rf "$OBJDIR"
		return 0
	elif [ "$rc" -ne 0 ]; then
		echo "Could not read $OBJDIR/config.status.json" >&2
		return "$rc"
	fi
	if [ -z "$missing" ]; then
		log "all toolchain paths recorded by configure exist"
		return 0
	fi
	log "toolchain paths recorded by configure are missing on this runner:"
	printf '%s\n' "$missing" | sed 's/^/  /'
	# Without config.status mach runs configure again, which bootstraps the
	# same toolchains into the same $MOZBUILD_DIR paths. configure writes its
	# outputs only when their content changes, so finished objects stay valid.
	log "removing config.status so mach reconfigures and bootstraps them again"
	rm -f "$OBJDIR/config.status"
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

	check_toolchain

	case "$STARTUP_MINUTES" in
		'' | *[!0-9]*)
			echo "GECKO_STARTUP_MINUTES must be a number of minutes" >&2
			exit 2
			;;
	esac
	local build_log="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/gecko-pass-build.log"
	local started
	started="$(date +%s)"
	: > "$build_log"

	# Job control puts the build into its own process group, so the whole
	# mach/make/cargo tree can be signalled at once. Its output reaches the
	# job log through tee, which ignores SIGTERM so make's cleanup messages
	# after a stop are still shown.
	set -m
	GECKO_SOURCE_MTIME="$SOURCE_MTIME" "$SCRIPT_DIR/build-gecko.sh" "$@" > >(trap '' TERM; exec tee -a "$build_log") 2>&1 &
	pid=$!
	set +m
	log "build started (pid $pid), deadline $(date -r "$deadline" 2>/dev/null || date -d "@$deadline")"

	while kill -0 "$pid" 2>/dev/null; do
		if [ "$(date +%s)" -ge "$deadline" ]; then
			stop_build "$pid"
			wait "$pid" 2>/dev/null || true
			exit "$RESUMABLE"
		fi
		if [ "$STARTUP_MINUTES" -gt 0 ] && [ ! -s "$build_log" ] &&
			[ $(( $(date +%s) - started )) -ge $(( STARTUP_MINUTES * 60 )) ]; then
			echo "Gecko build printed nothing in $STARTUP_MINUTES min; it is stuck before compiling." >&2
			dump_processes "$pid" >&2
			kill -TERM -- "-$pid" 2>/dev/null || true
			sleep 10
			kill -KILL -- "-$pid" 2>/dev/null || true
			wait "$pid" 2>/dev/null || true
			exit "$STALLED"
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

# Where this pass builds; a saved object directory is only usable here.
location_file() {
	printf 'srcdir=%s\nobjdir=%s\nmozbuild=%s\n' "$FIREFOX_DIR" "$OBJDIR" "$MOZBUILD_DIR"
}

save_state() {
	local out="$1" fingerprint="$2"
	local zstd_bin
	zstd_bin="$(compressor)"
	if [ ! -d "$OBJDIR" ]; then
		echo "No object directory at $OBJDIR: this pass never started compiling, so there is nothing to continue." >&2
		exit 1
	fi
	mkdir -p "$out"
	printf '%s\n' "$fingerprint" > "$out/fingerprint"
	location_file > "$out/location"
	# pax keeps sub-second timestamps, which make and cargo compare.
	tar --format pax -C "$FIREFOX_DIR" -cf - "$OBJDIR_NAME" | "$zstd_bin" -T0 -3 -q -o "$out/objdir.tar.zst"
	# The bootstrapped toolchains the objects were compiled with (clang and
	# its headers, SDKs, cbindgen, node) and mach's virtualenvs. A fresh
	# runner has none of them, and config.status points at these exact paths.
	# toolchains/ only holds the downloaded archives and is left out.
	if [ -d "$MOZBUILD_DIR" ]; then
		tar --format pax -C "$(dirname "$MOZBUILD_DIR")" --exclude "$(basename "$MOZBUILD_DIR")/toolchains" \
			-cf - "$(basename "$MOZBUILD_DIR")" | "$zstd_bin" -T0 -3 -q -o "$out/mozbuild.tar.zst"
	fi
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
	if [ "$(cat "$in/location" 2>/dev/null || true)" != "$(location_file)" ]; then
		log "saved object directory was built at another location; starting clean"
		log "saved:   $(tr '\n' ' ' < "$in/location" 2>/dev/null || echo none)"
		log "current: $(location_file | tr '\n' ' ')"
		rm -f "$in/objdir.tar.zst" "$in/mozbuild.tar.zst"
		return 0
	fi
	if [ "$(cat "$in/fingerprint" 2>/dev/null || true)" != "$fingerprint" ]; then
		# A different compiler, SDK or source set would mix incompatible objects.
		log "saved object directory was built with a different toolchain or source; starting clean"
		log "saved:   $(cat "$in/fingerprint" 2>/dev/null || echo none)"
		log "current: $fingerprint"
		rm -f "$in/objdir.tar.zst" "$in/mozbuild.tar.zst"
		return 0
	fi
	if [ -f "$in/mozbuild.tar.zst" ]; then
		# Exactly the toolchains (and file timestamps) the objects were built
		# with, at the paths config.status records.
		rm -rf "$MOZBUILD_DIR"
		mkdir -p "$(dirname "$MOZBUILD_DIR")"
		"$zstd_bin" -dc "$in/mozbuild.tar.zst" | tar -xpf - -C "$(dirname "$MOZBUILD_DIR")"
		rm -f "$in/mozbuild.tar.zst"
		log "restored $(du -sh "$MOZBUILD_DIR" | cut -f1) mach state directory $MOZBUILD_DIR"
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
	check-toolchain)
		check_toolchain
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
		echo "Usage: $0 normalize-sources | check-toolchain | run DEADLINE [build args] | save DIR FINGERPRINT | restore DIR FINGERPRINT" >&2
		exit 2
		;;
esac
