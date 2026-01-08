#!/bin/bash

set -e

# =============================================================================
# Build script for LAME MP3 encoder from official SourceForge sources for Android
# Creates static libraries for all Android ABIs
#
# Sources:
#   - LAME: https://lame.sourceforge.io/
#
# Requirements:
#   - Android NDK (set ANDROID_NDK_HOME or NDK will be auto-detected)
#
# This script downloads, verifies, and compiles the official sources.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$MODULE_DIR/build-android-lame"
JNILIBS_DIR="$MODULE_DIR/android/src/main/jniLibs"
INCLUDE_DIR="$MODULE_DIR/android/src/main/cpp/include/lame"

# Official LAME source
LAME_VERSION="3.100"
LAME_URL="https://sourceforge.net/projects/lame/files/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz/download"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"

# Android API level (matches minSdk in build.gradle)
ANDROID_API=29

# ABIs to build
ABIS="arm64-v8a armeabi-v7a x86 x86_64"

log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# Find Android NDK
find_ndk() {
    if [ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ]; then
        echo "$ANDROID_NDK_HOME"
        return
    fi

    # Try common locations
    local ndk_paths=(
        "$HOME/Library/Android/sdk/ndk"
        "$HOME/Android/Sdk/ndk"
        "/usr/local/share/android-ndk"
    )

    for ndk_base in "${ndk_paths[@]}"; do
        if [ -d "$ndk_base" ]; then
            local latest=$(ls -1 "$ndk_base" 2>/dev/null | sort -V | tail -n1)
            if [ -n "$latest" ] && [ -d "$ndk_base/$latest" ]; then
                echo "$ndk_base/$latest"
                return
            fi
        fi
    done

    log_error "Android NDK not found. Set ANDROID_NDK_HOME environment variable."
    exit 1
}

# Verify SHA256 checksum
verify_checksum() {
    local file="$1"
    local expected="$2"
    local actual=$(shasum -a 256 "$file" | awk '{print $1}')

    if [ "$actual" != "$expected" ]; then
        log_error "Checksum verification failed for $file"
        log_error "Expected: $expected"
        log_error "Actual:   $actual"
        exit 1
    fi
    log_info "Checksum verified for $(basename "$file")"
}

# Download and extract source
download_source() {
    local archive="$BUILD_DIR/lame-${LAME_VERSION}.tar.gz"

    if [ -f "$archive" ]; then
        log_info "LAME archive already exists, verifying..."
        verify_checksum "$archive" "$LAME_SHA256"
    else
        log_info "Downloading LAME from SourceForge..."
        curl -L --progress-bar -o "$archive" "$LAME_URL"
        verify_checksum "$archive" "$LAME_SHA256"
    fi

    log_info "Extracting LAME..."
    tar -xzf "$archive" -C "$BUILD_DIR"
}

# Get NDK toolchain info for ABI
get_toolchain_info() {
    local abi="$1"

    case "$abi" in
        "arm64-v8a")
            echo "aarch64-linux-android"
            ;;
        "armeabi-v7a")
            echo "armv7a-linux-androideabi"
            ;;
        "x86")
            echo "i686-linux-android"
            ;;
        "x86_64")
            echo "x86_64-linux-android"
            ;;
    esac
}

# Build LAME for a specific ABI
build_for_abi() {
    local abi="$1"
    local ndk="$2"
    local src_dir="$BUILD_DIR/lame-${LAME_VERSION}"

    local toolchain="$ndk/toolchains/llvm/prebuilt/darwin-x86_64"
    if [ ! -d "$toolchain" ]; then
        toolchain="$ndk/toolchains/llvm/prebuilt/linux-x86_64"
    fi

    local target=$(get_toolchain_info "$abi")
    local build_subdir="$BUILD_DIR/lame-$abi"
    mkdir -p "$build_subdir"

    log_info "Building LAME for $abi..."

    cd "$src_dir"

    # Clean previous build
    make clean 2>/dev/null || true
    make distclean 2>/dev/null || true

    # Set up cross-compilation environment
    export CC="$toolchain/bin/${target}${ANDROID_API}-clang"
    export CXX="$toolchain/bin/${target}${ANDROID_API}-clang++"
    export AR="$toolchain/bin/llvm-ar"
    export RANLIB="$toolchain/bin/llvm-ranlib"
    export STRIP="$toolchain/bin/llvm-strip"

    # Configure - disable frontend (we only need libmp3lame)
    ./configure \
        --host="$target" \
        --prefix="$build_subdir" \
        --enable-static \
        --disable-shared \
        --disable-frontend \
        --disable-decoder \
        --disable-analyzer-hooks \
        --disable-gtktest \
        --with-pic \
        CFLAGS="-O3 -fPIC" \
        > "$build_subdir/configure.log" 2>&1

    # Build only libmp3lame
    make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu) > "$build_subdir/make.log" 2>&1
    make install > "$build_subdir/install.log" 2>&1

    # Copy to jniLibs
    local jni_abi_dir="$JNILIBS_DIR/$abi"
    mkdir -p "$jni_abi_dir"
    cp "$build_subdir/lib/libmp3lame.a" "$jni_abi_dir/"

    cd "$SCRIPT_DIR"
    log_info "Built LAME for $abi"
}

# Copy headers for JNI compilation
copy_headers() {
    local src_dir="$BUILD_DIR/lame-${LAME_VERSION}"

    log_info "Copying LAME headers..."
    mkdir -p "$INCLUDE_DIR"
    cp "$src_dir/include/lame.h" "$INCLUDE_DIR/"

    log_info "Headers copied to $INCLUDE_DIR"
}

# Main build process
main() {
    log_info "=== Building LAME MP3 encoder for Android ==="
    log_info "LAME version: $LAME_VERSION"
    log_info "Target API: $ANDROID_API"
    log_info "ABIs: $ABIS"
    log_info ""

    # Find NDK
    local ndk=$(find_ndk)
    log_info "Using NDK: $ndk"

    # Create directories
    mkdir -p "$BUILD_DIR"
    mkdir -p "$JNILIBS_DIR"

    # Download source
    download_source

    # Copy headers immediately after extraction (before distclean removes them)
    copy_headers

    # Build for each ABI
    for abi in $ABIS; do
        build_for_abi "$abi" "$ndk"
    done

    log_info ""
    log_info "=== Build complete! ==="
    log_info "Static libraries created in: $JNILIBS_DIR"
    for abi in $ABIS; do
        ls -la "$JNILIBS_DIR/$abi/libmp3lame.a" 2>/dev/null || true
    done
}

main "$@"
