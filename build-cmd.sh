#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then 
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

OGG_SOURCE_DIR="libogg"
OGG_VERSION="$(sed -n "s/^ VERSION='\(.*\)'/\1/p" "$OGG_SOURCE_DIR/configure")"

VORBIS_SOURCE_DIR="libvorbis"
VORBIS_VERSION="$(sed -n "s/^PACKAGE_VERSION='\(.*\)'/\1/p" "$VORBIS_SOURCE_DIR/configure")"

top="$(pwd)"
stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

echo "${OGG_VERSION}-${VORBIS_VERSION}" > "${stage}/VERSION.txt"

# setup staging dirs
mkdir -p "$stage/include/"
mkdir -p "$stage/lib/debug"
mkdir -p "$stage/lib/release"

case "$AUTOBUILD_PLATFORM" in
    windows*)
        pushd "$OGG_SOURCE_DIR"
            mkdir -p "build"
            pushd "build"
                cmake .. -G "Ninja Multi-Config" -DBUILD_SHARED_LIBS=OFF \
                    -DBUILD_TESTING=ON \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/ogg_release"

                cmake --build . --config Debug
                cmake --install . --config Debug

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd
        popd

        # copy ogg libs
        cp ${stage}/ogg_debug/lib/ogg.lib ${stage}/lib/debug/libogg.lib
        cp ${stage}/ogg_release/lib/ogg.lib ${stage}/lib/release/libogg.lib

        # copy ogg headers
        cp -a $stage/ogg_release/include/* $stage/include/

        pushd "$VORBIS_SOURCE_DIR"
            mkdir -p "build_debug"
            pushd "build_debug"
                cmake .. -G "Ninja Multi-Config" \
                    -DOGG_LIBRARIES="$(cygpath -m $stage)/lib/debug/libogg.lib" \
                    -DOGG_INCLUDE_DIRS="$(cygpath -m $stage)/include" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DBUILD_TESTING=ON \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/vorbis_debug"

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release"
            pushd "build_release"
                cmake .. -G "Ninja Multi-Config" \
                    -DOGG_LIBRARIES="$(cygpath -m $stage)/lib/release/libogg.lib" \
                    -DOGG_INCLUDE_DIRS="$(cygpath -m $stage)/include" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DBUILD_TESTING=ON \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/vorbis_release"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd
        popd

        # copy vorbis libs
        cp ${stage}/vorbis_debug/lib/vorbis.lib ${stage}/lib/debug/libvorbis.lib
        cp ${stage}/vorbis_debug/lib/vorbisenc.lib ${stage}/lib/debug/libvorbisenc.lib
        cp ${stage}/vorbis_debug/lib/vorbisfile.lib ${stage}/lib/debug/libvorbisfile.lib
        cp ${stage}/vorbis_release/lib/vorbis.lib ${stage}/lib/release/libvorbis.lib
        cp ${stage}/vorbis_release/lib/vorbisenc.lib ${stage}/lib/release/libvorbisenc.lib
        cp ${stage}/vorbis_release/lib/vorbisfile.lib ${stage}/lib/release/libvorbisfile.lib

        # copy vorbis headers
        cp -a $stage/vorbis_release/include/* $stage/include/
    ;;
    darwin*)
        # Setup build flags
        C_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CFLAGS"
        C_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CFLAGS"
        LINK_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_LINKER"
        LINK_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_LINKER"

        # deploy target
        export MACOSX_DEPLOYMENT_TARGET=${LL_BUILD_DARWIN_BASE_DEPLOY_TARGET}

        pushd "$OGG_SOURCE_DIR"
            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$C_OPTS_X86" \
                LDFLAGS="$LINK_OPTS_X86" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
                    -DCMAKE_C_FLAGS="$C_OPTS_X86" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/ogg_release_x86"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            mkdir -p "build_release_arm64"
            pushd "build_release_arm64"
                CFLAGS="$C_OPTS_ARM64" \
                LDFLAGS="$LINK_OPTS_ARM64" \
                cmake .. -GXcode -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
                    -DCMAKE_C_FLAGS="$C_OPTS_ARM64" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/ogg_release_arm64"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # create fat libraries
            lipo -create ${stage}/ogg_release_x86/lib/libogg.a ${stage}/ogg_release_arm64/lib/libogg.a -output ${stage}/lib/release/libogg.a

            # copy headers
            cp -a $stage/ogg_release_x86/include/* $stage/include/
        popd

        pushd "$VORBIS_SOURCE_DIR"
            mkdir -p "build_release_x86"
            pushd "build_release_x86"
                CFLAGS="$C_OPTS_X86" \
                LDFLAGS="$LINK_OPTS_X86" \
                cmake .. -G Ninja -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
                    -DOGG_LIBRARIES="${stage}/lib/release/libogg.a" -DOGG_INCLUDE_DIRS="$stage/include" \
                    -DCMAKE_C_FLAGS="$C_OPTS_X86" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/vorbis_release_x86"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            mkdir -p "build_release_arm64"
            pushd "build_release_arm64"
                CFLAGS="$C_OPTS_ARM64" \
                LDFLAGS="$LINK_OPTS_ARM64" \
                cmake .. -G Ninja -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=ON \
                    -DOGG_LIBRARIES="${stage}/lib/release/libogg.a" -DOGG_INCLUDE_DIRS="$stage/include" \
                    -DCMAKE_C_FLAGS="$C_OPTS_ARM64" \
                    -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                    -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                    -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                    -DCMAKE_MACOSX_RPATH=YES \
                    -DCMAKE_INSTALL_PREFIX="$stage/vorbis_release_arm64"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                   ctest -C Release
                fi
            popd

            # create fat libraries
            lipo -create ${stage}/vorbis_release_x86/lib/libvorbis.a ${stage}/vorbis_release_arm64/lib/libvorbis.a -output ${stage}/lib/release/libvorbis.a
            lipo -create ${stage}/vorbis_release_x86/lib/libvorbisenc.a ${stage}/vorbis_release_arm64/lib/libvorbisenc.a -output ${stage}/lib/release/libvorbisenc.a
            lipo -create ${stage}/vorbis_release_x86/lib/libvorbisfile.a ${stage}/vorbis_release_arm64/lib/libvorbisfile.a -output ${stage}/lib/release/libvorbisfile.a

            # copy headers
            cp -a $stage/vorbis_release_x86/include/* $stage/include/
        popd
     ;;
    linux*)
        # Default target per autobuild build --address-size
        opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE_CFLAGS}"

        # Handle any deliberate platform targeting
        if [ -z "${TARGET_CPPFLAGS:-}" ]; then
            # Remove sysroot contamination from build environment
            unset CPPFLAGS
        else
            # Incorporate special pre-processing flags
            export CPPFLAGS="$TARGET_CPPFLAGS"
        fi

        pushd "$OGG_SOURCE_DIR"
            mkdir -p "build"
            pushd "build"
                CFLAGS="$opts" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DBUILD_TESTING=ON \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage/ogg_release"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                   ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/ogg_release/lib/*.a ${stage}/lib/release/

            # copy headers
            cp -a ${stage}/ogg_release/include/* ${stage}/include/
        popd
        
        pushd "$VORBIS_SOURCE_DIR"
            mkdir -p "build"
            pushd "build"
                CFLAGS="$opts" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DBUILD_TESTING=ON \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage/vorbis_release" \
                    -DOGG_LIBRARIES="$stage/lib/release/libogg.a" \
                    -DOGG_INCLUDE_DIRS="$stage/include"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                   ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/vorbis_release/lib/*.a ${stage}/lib/release/

            # copy headers
            cp -a ${stage}/vorbis_release/include/* ${stage}/include/
        popd
    ;;
esac

mkdir -p "$stage/LICENSES"
cp $OGG_SOURCE_DIR/COPYING "$stage/LICENSES/ogg-vorbis.txt"
