cmake_minimum_required(VERSION 3.18.1)

project("audio_encoder")

# Pre-built library directory
set(LIBS_DIR ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI})

# Include directories for headers
include_directories(${CMAKE_SOURCE_DIR}/include)

# ============================================================================
# Opus Encoder Library
# Built by scripts/build-opus-android.sh from official Xiph.org sources
# ============================================================================

if(EXISTS "${LIBS_DIR}/libopus.a")
    message(STATUS "Found libopus.a for ${ANDROID_ABI}")

    # Import pre-built libopus
    add_library(opus STATIC IMPORTED)
    set_target_properties(opus PROPERTIES
        IMPORTED_LOCATION ${LIBS_DIR}/libopus.a
    )

    # Create Opus JNI shared library
    add_library(opus_encoder SHARED
        opus_encoder_jni.cpp
    )

    target_link_libraries(opus_encoder
        opus
        log
    )

    # 16KB page size support for Google Play compatibility
    target_link_options(opus_encoder PRIVATE
        "-Wl,-z,max-page-size=16384"
    )
else()
    message(WARNING "libopus.a not found for ${ANDROID_ABI}")
    message(WARNING "Run scripts/build-opus-android.sh to build native libraries")

    # Create stub library
    add_library(opus_encoder SHARED
        opus_encoder_stub.cpp
    )

    target_link_libraries(opus_encoder
        log
    )
endif()

# ============================================================================
# LAME MP3 Encoder Library
# Built by scripts/build-lame-android.sh from official SourceForge sources
# ============================================================================

if(EXISTS "${LIBS_DIR}/libmp3lame.a")
    message(STATUS "Found libmp3lame.a for ${ANDROID_ABI}")

    # Import pre-built libmp3lame
    add_library(mp3lame STATIC IMPORTED)
    set_target_properties(mp3lame PROPERTIES
        IMPORTED_LOCATION ${LIBS_DIR}/libmp3lame.a
    )

    # Create LAME JNI shared library
    add_library(lame_encoder SHARED
        lame_jni.cpp
    )

    target_link_libraries(lame_encoder
        mp3lame
        log
    )

    # 16KB page size support for Google Play compatibility
    target_link_options(lame_encoder PRIVATE
        "-Wl,-z,max-page-size=16384"
    )
else()
    message(WARNING "libmp3lame.a not found for ${ANDROID_ABI}")
    message(WARNING "Run scripts/build-lame-android.sh to build native libraries")

    # Create stub library for LAME
    add_library(lame_encoder SHARED
        lame_stub.cpp
    )

    target_link_libraries(lame_encoder
        log
    )
endif()
