#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"

TARGET="aarch64-apple-ios"
USE_SCCACHE=false
AUTO_CLOBBER=false
DISABLE_JEMALLOC=false

# Availability checks emitted by Clang call into compiler-rt. Gecko's iOS
# build uses ld64.lld directly, which does not always add this archive the way
# the Clang driver does. Add it explicitly so deployment-target guards keep
# working when the SDK is newer than the minimum supported iOS version.
CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
CLANG_RESOURCE_DIR="$("$CLANG_PATH" --print-resource-dir)"
COMPILER_RT_IOS="$CLANG_RESOURCE_DIR/lib/darwin/libclang_rt.ios.a"
if [ ! -f "$COMPILER_RT_IOS" ]; then
	echo "Missing iOS compiler runtime: $COMPILER_RT_IOS"
	exit 1
fi
export LDFLAGS="${LDFLAGS:+$LDFLAGS }$COMPILER_RT_IOS"

for arg in "$@"; do
	case "$arg" in
		--use-sccache)
			USE_SCCACHE=true
			;;
		--auto-clobber)
			AUTO_CLOBBER=true
			;;
		--disable-jemalloc)
			DISABLE_JEMALLOC=true
			;;
	esac
done

if [ "$USE_SCCACHE" = true ]; then
	SCCACHE_BIN="${SCCACHE_PATH:-$(command -v sccache)}"
fi

cd "$ROOT_DIR"

if [ ! -d "$FIREFOX_DIR" ]; then
	echo "Missing firefox source at $FIREFOX_DIR"
	echo "Add the submodule, then run tools/development/update-gecko.sh."
	exit 1
fi

MOZCONFIG="$FIREFOX_DIR/.mozconfig"
MOZCONFIG_BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/reynard-mozconfig.XXXXXX")"
MOZCONFIG_BACKUP="$MOZCONFIG_BACKUP_DIR/.mozconfig"
HAD_MOZCONFIG=0

if [ -e "$MOZCONFIG" ]; then
	mv "$MOZCONFIG" "$MOZCONFIG_BACKUP"
	HAD_MOZCONFIG=1
fi

restore_mozconfig() {
	rm -f "$MOZCONFIG"
	if [ "$HAD_MOZCONFIG" -eq 1 ]; then
		mv "$MOZCONFIG_BACKUP" "$MOZCONFIG"
	fi
	rmdir "$MOZCONFIG_BACKUP_DIR"
}

trap restore_mozconfig EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

{
	echo "ac_add_options --enable-application=mobile/ios"
	echo "ac_add_options --target=$TARGET"
	echo "ac_add_options --enable-ios-target=15.0"
	echo "ac_add_options --enable-webrtc"
	echo "ac_add_options --enable-optimize"
	echo "ac_add_options --enable-release"
	echo "ac_add_options --enable-rust-simd"
	echo "ac_add_options --enable-lto"
	echo "ac_add_options --disable-debug"
	echo "ac_add_options --disable-tests"
	echo "ac_add_options --enable-bootstrap"
	if [ "$USE_SCCACHE" = true ]; then
		echo "mk_add_options 'export RUSTC_WRAPPER=$SCCACHE_BIN'"
		echo "ac_add_options --with-ccache=$SCCACHE_BIN"
	fi
	if [ "$DISABLE_JEMALLOC" = true ]; then
		echo "ac_add_options --disable-jemalloc"
	fi
	if [ "$AUTO_CLOBBER" = true ]; then
		echo "mk_add_options AUTOCLOBBER=1"
	fi
} > "$MOZCONFIG"

if ! rustup target list | grep -q "^$TARGET (installed)"; then
	rustup target add "$TARGET"
fi

cd "$FIREFOX_DIR"
./mach build

trap - EXIT
restore_mozconfig
