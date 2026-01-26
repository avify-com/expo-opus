#!/bin/bash

# Debug: Show that script started
echo "=== Script starting ===" >&2

set -e

# =============================================================================
# Build script for libopus and libogg from official Xiph.org sources
# Creates xcframeworks for iOS (device + simulator)
#
# Sources:
#   - libopus: https://downloads.xiph.org/releases/opus/
#   - libogg: https://downloads.xiph.org/releases/ogg/
#
# This script downloads, verifies, and compiles the official sources.
# =============================================================================

echo "=== Detecting directories ===" >&2
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$MODULE_DIR/build"
FRAMEWORKS_DIR="$MODULE_DIR/ios/Frameworks"
echo "SCRIPT_DIR: $SCRIPT_DIR" >&2
echo "MODULE_DIR: $MODULE_DIR" >&2
echo "BUILD_DIR: $BUILD_DIR" >&2
echo "FRAMEWORKS_DIR: $FRAMEWORKS_DIR" >&2

# Official Xiph.org sources (checksums verified from xiph.org/downloads)
OPUS_VERSION="1.5.2"
OPUS_URL="https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz"
OPUS_SHA256="65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"

OGG_VERSION="1.3.6"
OGG_URL="https://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.gz"
OGG_SHA256="83e6704730683d004d20e21b8f7f55dcb3383cdf84c0daedf30bde175f774638"

# iOS deployment target
IOS_MIN_VERSION="15.0"

# Simple logging without colors for better compatibility
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1"
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
    log_info "Checksum verified for $(basename $file)"
}

# Download and extract source
download_source() {
    local name="$1"
    local url="$2"
    local sha256="$3"
    local archive="$BUILD_DIR/$(basename $url)"

    if [ -f "$archive" ]; then
        log_info "$name archive already exists, verifying..."
        verify_checksum "$archive" "$sha256"
    else
        log_info "Downloading $name from Xiph.org..."
        curl -L --progress-bar -o "$archive" "$url"
        verify_checksum "$archive" "$sha256"
    fi

    log_info "Extracting $name..."
    tar -xzf "$archive" -C "$BUILD_DIR"
}

# Build library for a specific platform/architecture
build_for_arch() {
    local lib_name="$1"
    local src_dir="$2"
    local arch="$3"
    local platform="$4"

    local sdk
    local host
    local min_version_flag

    case "$platform" in
        "iphoneos")
            sdk=$(xcrun --sdk iphoneos --show-sdk-path)
            host="arm-apple-darwin"
            min_version_flag="-miphoneos-version-min=${IOS_MIN_VERSION}"
            ;;
        "iphonesimulator")
            sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
            if [ "$arch" = "arm64" ]; then
                host="aarch64-apple-darwin"
            else
                host="x86_64-apple-darwin"
            fi
            min_version_flag="-mios-simulator-version-min=${IOS_MIN_VERSION}"
            ;;
    esac

    local build_subdir="$BUILD_DIR/${lib_name}-${platform}-${arch}"
    mkdir -p "$build_subdir"

    log_info "Building $lib_name for $platform ($arch)..."

    cd "$src_dir"

    # Clean previous build
    make clean 2>/dev/null || true
    make distclean 2>/dev/null || true

    # Library-specific configure options
    local extra_opts=""
    if [ "$lib_name" = "libopus" ]; then
        # Disable ARM assembly (uses GNU syntax incompatible with Apple clang)
        # NEON intrinsics still work and provide good optimization
        extra_opts="--disable-asm"
    fi

    # Configure
    ./configure \
        CC="clang" \
        CXX="clang++" \
        CFLAGS="-arch $arch -O3 -fPIC $min_version_flag -isysroot $sdk" \
        CXXFLAGS="-arch $arch -O3 -fPIC $min_version_flag -isysroot $sdk" \
        LDFLAGS="-arch $arch $min_version_flag -isysroot $sdk" \
        --host="$host" \
        --prefix="$build_subdir" \
        --enable-static \
        --disable-shared \
        --disable-doc \
        --disable-extra-programs \
        --with-pic \
        $extra_opts \
        > "$build_subdir/configure.log" 2>&1

    # Build
    make -j$(sysctl -n hw.ncpu) > "$build_subdir/make.log" 2>&1
    make install > "$build_subdir/install.log" 2>&1

    cd "$SCRIPT_DIR"
}

# Create xcframework from static libraries
create_xcframework() {
    local lib_name="$1"
    local static_lib_name="$2"
    local header_dir="$3"

    local xcframework_path="$FRAMEWORKS_DIR/${lib_name}.xcframework"

    log_info "Creating $lib_name.xcframework..."

    # Remove existing xcframework
    rm -rf "$xcframework_path"

    # Create fat library for simulator (arm64 + x86_64)
    local sim_fat_dir="$BUILD_DIR/${lib_name}-sim-fat"
    mkdir -p "$sim_fat_dir"

    lipo -create \
        "$BUILD_DIR/${lib_name}-iphonesimulator-arm64/lib/${static_lib_name}" \
        "$BUILD_DIR/${lib_name}-iphonesimulator-x86_64/lib/${static_lib_name}" \
        -output "$sim_fat_dir/${static_lib_name}"

    # Create xcframework
    xcodebuild -create-xcframework \
        -library "$BUILD_DIR/${lib_name}-iphoneos-arm64/lib/${static_lib_name}" \
        -headers "$header_dir" \
        -library "$sim_fat_dir/${static_lib_name}" \
        -headers "$header_dir" \
        -output "$xcframework_path"

    log_info "Created $xcframework_path"
}

# Copy headers for Swift interop
copy_swift_shims() {
    local shims_dir="$MODULE_DIR/ios/Shims"

    # Use headers from build output (more reliable after distclean)
    local ogg_headers="$BUILD_DIR/libogg-iphoneos-arm64/include/ogg"
    local opus_headers="$BUILD_DIR/libopus-iphoneos-arm64/include/opus"

    log_info "Creating Swift shims for libogg..."
    local ogg_shim_dir="$shims_dir/ogg"
    mkdir -p "$ogg_shim_dir/ogg"

    # Copy ogg headers from build output
    cp "$ogg_headers/ogg.h" "$ogg_shim_dir/ogg/"
    cp "$ogg_headers/os_types.h" "$ogg_shim_dir/ogg/"
    cp "$ogg_headers/config_types.h" "$ogg_shim_dir/ogg/"

    # Create ogg umbrella header
    cat > "$ogg_shim_dir/ogg-umbrella.h" << 'EOF'
#import <Foundation/Foundation.h>

#import "ogg/ogg.h"
#import "ogg/os_types.h"
#import "ogg/config_types.h"
EOF

    # Create ogg module map
    cat > "$ogg_shim_dir/module.modulemap" << 'EOF'
module ogg {
    umbrella header "ogg-umbrella.h"
    export *
}
EOF

    log_info "Creating Swift shims for libopus..."
    local opus_shim_dir="$shims_dir/opus"
    mkdir -p "$opus_shim_dir/opus"

    # Copy opus headers from build output
    cp "$opus_headers/opus.h" "$opus_shim_dir/opus/"
    cp "$opus_headers/opus_defines.h" "$opus_shim_dir/opus/"
    cp "$opus_headers/opus_types.h" "$opus_shim_dir/opus/"
    cp "$opus_headers/opus_multistream.h" "$opus_shim_dir/opus/"
    cp "$opus_headers/opus_projection.h" "$opus_shim_dir/opus/"

    # Create opus umbrella header
    cat > "$opus_shim_dir/opus-umbrella.h" << 'EOF'
#import <Foundation/Foundation.h>

#import "opus/opus.h"
#import "opus/opus_defines.h"
#import "opus/opus_types.h"
#import "opus/opus_multistream.h"
#import "opus/opus_projection.h"
#import "opus_swift_helpers.h"
EOF

    # Create opus Swift helpers with wrapper functions for Swift interop
    cat > "$opus_shim_dir/opus_swift_helpers.h" << 'EOF'
#ifndef OPUS_SWIFT_HELPERS_H
#define OPUS_SWIFT_HELPERS_H

#import "opus/opus.h"
#import "opus/opus_defines.h"

// Swift-compatible wrapper functions for opus encoder CTL operations
// These wrap the C macros which Swift cannot call directly

static inline int opus_encoder_set_bitrate(OpusEncoder *st, opus_int32 bitrate) {
    return opus_encoder_ctl(st, OPUS_SET_BITRATE(bitrate));
}

static inline int opus_encoder_set_complexity(OpusEncoder *st, opus_int32 complexity) {
    return opus_encoder_ctl(st, OPUS_SET_COMPLEXITY(complexity));
}

static inline int opus_encoder_set_vbr(OpusEncoder *st, opus_int32 vbr) {
    return opus_encoder_ctl(st, OPUS_SET_VBR(vbr));
}

static inline int opus_encoder_set_vbr_constraint(OpusEncoder *st, opus_int32 cvbr) {
    return opus_encoder_ctl(st, OPUS_SET_VBR_CONSTRAINT(cvbr));
}

static inline int opus_encoder_set_signal(OpusEncoder *st, opus_int32 signal) {
    return opus_encoder_ctl(st, OPUS_SET_SIGNAL(signal));
}

static inline int opus_encoder_set_application(OpusEncoder *st, opus_int32 application) {
    return opus_encoder_ctl(st, OPUS_SET_APPLICATION(application));
}

static inline int opus_encoder_get_bitrate(OpusEncoder *st, opus_int32 *bitrate) {
    return opus_encoder_ctl(st, OPUS_GET_BITRATE(bitrate));
}

static inline int opus_encoder_get_complexity(OpusEncoder *st, opus_int32 *complexity) {
    return opus_encoder_ctl(st, OPUS_GET_COMPLEXITY(complexity));
}

// Decoder helper functions
static inline int opus_decoder_set_gain(OpusDecoder *st, opus_int32 gain) {
    return opus_decoder_ctl(st, OPUS_SET_GAIN(gain));
}

static inline int opus_decoder_get_gain(OpusDecoder *st, opus_int32 *gain) {
    return opus_decoder_ctl(st, OPUS_GET_GAIN(gain));
}

#endif /* OPUS_SWIFT_HELPERS_H */
EOF

    # Create opus module map
    cat > "$opus_shim_dir/module.modulemap" << 'EOF'
module opus {
    umbrella header "opus-umbrella.h"
    export *
}
EOF

    log_info "Swift shims created in $shims_dir"
}

# Main build process
main() {
    log_info "=== Building libopus and libogg from official Xiph.org sources ==="
    log_info "Opus version: $OPUS_VERSION"
    log_info "Ogg version: $OGG_VERSION"
    log_info ""

    # Create directories
    mkdir -p "$BUILD_DIR"
    mkdir -p "$FRAMEWORKS_DIR"

    # Download sources
    download_source "libopus" "$OPUS_URL" "$OPUS_SHA256"
    download_source "libogg" "$OGG_URL" "$OGG_SHA256"

    local opus_src="$BUILD_DIR/opus-${OPUS_VERSION}"
    local ogg_src="$BUILD_DIR/libogg-${OGG_VERSION}"

    # Build libogg first (opus may depend on it)
    log_info ""
    log_info "=== Building libogg ==="

    build_for_arch "libogg" "$ogg_src" "arm64" "iphoneos"
    build_for_arch "libogg" "$ogg_src" "arm64" "iphonesimulator"
    build_for_arch "libogg" "$ogg_src" "x86_64" "iphonesimulator"

    create_xcframework "libogg" "libogg.a" "$BUILD_DIR/libogg-iphoneos-arm64/include"

    # Build libopus
    log_info ""
    log_info "=== Building libopus ==="

    build_for_arch "libopus" "$opus_src" "arm64" "iphoneos"
    build_for_arch "libopus" "$opus_src" "arm64" "iphonesimulator"
    build_for_arch "libopus" "$opus_src" "x86_64" "iphonesimulator"

    create_xcframework "libopus" "libopus.a" "$BUILD_DIR/libopus-iphoneos-arm64/include"

    # Copy Swift shims for interop
    log_info ""
    log_info "=== Creating Swift shims ==="
    copy_swift_shims

    log_info ""
    log_info "=== Build complete! ==="
    log_info "Frameworks created in: $FRAMEWORKS_DIR"
    ls -la "$FRAMEWORKS_DIR"

    # Cleanup build directory (optional, comment out to keep for debugging)
    # rm -rf "$BUILD_DIR"
}

main "$@"
