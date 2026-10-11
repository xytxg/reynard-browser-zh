#!/bin/sh

set -eu

CLANG_PATH="$(xcrun --sdk iphoneos --find clang)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist/Reynard.xcarchive"
APP_DIR="$ARCHIVE_DIR/Products/Applications"
WORK_DIR="$ROOT_DIR/dist/Reynard"

BUILD_TYPE="${1:-normal}"
case "$BUILD_TYPE" in
	--trollstore)
		OUTPUT_NAME="Reynard-TrollStore.tipa"
		PTRACE_JIT_NAME="ts_ptrace_jit"
		;;
	--jailbroken)
		OUTPUT_NAME="Reynard-Jailbroken.ipa"
		PTRACE_JIT_NAME="jb_ptrace_jit"
		;;
	*)
		BUILD_TYPE="normal"
		OUTPUT_NAME="Reynard.ipa"
		;;
esac

cd "$ROOT_DIR"

if [ ! -d "$APP_DIR" ]; then
	echo "Missing archive output at $APP_DIR"
	echo "Run tools/release/build-app.sh first."
	exit 1
fi

APP_PATH="$(find "$APP_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1)"
if [ -z "$APP_PATH" ]; then
	echo "No .app found in $APP_DIR"
	exit 1
fi

# I absolutely hate Apple for this
# Why is my bundle identifier just become unavailable for no reason?
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard" "$APP_PATH/Info.plist"
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.Helper" "$APP_PATH/PlugIns/Reynard Helper.appex/Info.plist"
plutil -replace CFBundleIdentifier -string "com.minh-ton.Reynard.OpenIn" "$APP_PATH/PlugIns/OpenIn.appex/Info.plist"

# The standard package must use the same XUL normalization, signature stripping,
# and structural validation as the dedicated source-built unsigned workflow.
if [ "$BUILD_TYPE" = "normal" ]; then
    exec "$SCRIPT_DIR/create-unsigned-ipa.sh" "$APP_PATH" "$ROOT_DIR/dist/$OUTPUT_NAME"
fi

rm -rf "$WORK_DIR" "$ROOT_DIR/dist/$OUTPUT_NAME"
mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

cd "$WORK_DIR"

if [ "$BUILD_TYPE" != "normal" ]; then
	PTRACE_JIT_SRC="$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.c"
	PTRACE_JIT_OUT="Payload/Reynard.app/$PTRACE_JIT_NAME"

	"$CLANG_PATH" \
		-arch arm64 \
		-isysroot "$SDK_PATH" \
		-miphoneos-version-min=13.0 \
		-Os \
		"$PTRACE_JIT_SRC" \
		-o "$PTRACE_JIT_OUT"

	chmod 0755 "$PTRACE_JIT_OUT"
	ldid -S"$ROOT_DIR/browser/Reynard/JIT/Unsandboxed/ptrace_jit.entitlements" "$PTRACE_JIT_OUT"
	ldid -S"$ROOT_DIR/browser/Reynard/Entitlements/Reynard.private.entitlements" "Payload/Reynard.app/Reynard"
	ldid -S"$ROOT_DIR/browser/Helper/Entitlements/Reynard-Helper.private.entitlements" "Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper"
fi

if [ "$BUILD_TYPE" = "--jailbroken" ]; then
	# Since releases are now built on GitHub Actions, and it does not have proper signing yet (i believe it
	# requires a paid Apple developer account because of using the free one we would have to replace the
	# provisioning profile once every 7 days?). So this is a workaround for the issue where libhooker-based
	# jailbreaks just refuse to load the adhoc signed dylib and cause the app to crash.
	#
	# The 0.10.0 package is the last properly signed upstream build. Pin both the downloaded IPA and the
	# extracted dylib so a replaced release asset or a truncated download fails the build instead of being
	# silently embedded in the jailbroken package.
	SIGNED_IPA_URL="https://github.com/minh-ton/reynard-browser/releases/download/0.10.0/Reynard.ipa"
	SIGNED_IPA_SHA256="567282427ffa56bf897aa786ff3e16beb6098c31b7880b309d94f6f2f58d5a8b"
	SIGNED_CONCURRENCY_SHA256="cab2c1c922f659d8d96fb2b4b0717e646dca432895443998beadda9a3532386e"
	SIGNED_IPA_PATH="$ROOT_DIR/dist/Reynard-0.10.0-signed-source.ipa"
	SIGNED_CONCURRENCY_TMP="$WORK_DIR/libswift_Concurrency.dylib.signed"
	CONCURRENCY_PATH="Payload/Reynard.app/Frameworks/libswift_Concurrency.dylib"

	rm -f "$SIGNED_IPA_PATH" "$SIGNED_CONCURRENCY_TMP"
	if ! curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
		--output "$SIGNED_IPA_PATH" "$SIGNED_IPA_URL"; then
		echo "Failed to download the signed libswift_Concurrency source package." >&2
		exit 1
	fi
	actual_ipa_sha256="$(shasum -a 256 "$SIGNED_IPA_PATH" | awk '{ print $1 }')"
	if [ "$actual_ipa_sha256" != "$SIGNED_IPA_SHA256" ]; then
		echo "Signed source package SHA-256 mismatch: expected $SIGNED_IPA_SHA256, got $actual_ipa_sha256" >&2
		rm -f "$SIGNED_IPA_PATH"
		exit 1
	fi
	if ! unzip -p "$SIGNED_IPA_PATH" "$CONCURRENCY_PATH" > "$SIGNED_CONCURRENCY_TMP"; then
		echo "Signed source package does not contain $CONCURRENCY_PATH." >&2
		rm -f "$SIGNED_IPA_PATH" "$SIGNED_CONCURRENCY_TMP"
		exit 1
	fi
	actual_dylib_sha256="$(shasum -a 256 "$SIGNED_CONCURRENCY_TMP" | awk '{ print $1 }')"
	if [ "$actual_dylib_sha256" != "$SIGNED_CONCURRENCY_SHA256" ]; then
		echo "Signed libswift_Concurrency.dylib SHA-256 mismatch: expected $SIGNED_CONCURRENCY_SHA256, got $actual_dylib_sha256" >&2
		rm -f "$SIGNED_IPA_PATH" "$SIGNED_CONCURRENCY_TMP"
		exit 1
	fi
	mkdir -p "Payload/Reynard.app/Frameworks"
	mv -f "$SIGNED_CONCURRENCY_TMP" "$CONCURRENCY_PATH"
	rm -f "$SIGNED_IPA_PATH"
fi

zip -r "../$OUTPUT_NAME" Payload -x "._*" -x ".DS_Store" -x "__MACOSX"
