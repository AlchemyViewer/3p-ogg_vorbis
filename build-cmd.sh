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

echo "${OGG_VERSION}" > "${stage}/VERSION.txt"

case "$AUTOBUILD_PLATFORM" in
    windows*)
        function copy_result {
            # $1 is the build directory in which to find the result
            # $2 is the basename of the .lib file we expect to find there
            cp "$1/$2".{lib,dll,exp,pdb} "$stage/lib/$3/"
        }

        if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
        then bitdir="Win32"
        else bitdir="x64"
        fi

        pushd "$OGG_SOURCE_DIR"
            pushd "win32/VS2019"
                build_sln "libogg.sln" "DebugDLL" "$AUTOBUILD_WIN_VSPLATFORM" "libogg"

                mkdir -p "$stage/lib/debug"
                copy_result "$bitdir/DebugDLL" libogg debug

                build_sln "libogg.sln" "ReleaseDLL" "$AUTOBUILD_WIN_VSPLATFORM" "libogg"

                mkdir -p "$stage/lib/release"
                copy_result "$bitdir/ReleaseDLL" libogg release
            popd

        mkdir -p "$stage/include"
        cp -a "include/ogg/" "$stage/include/"

        popd
        pushd "$VORBIS_SOURCE_DIR"
            pushd "win32/VS2019"
                build_sln "vorbis_dynamic.sln" "DebugDLL" "$AUTOBUILD_WIN_VSPLATFORM"

                copy_result "$bitdir/DebugDLL"  libvorbis       debug
                copy_result "$bitdir/DebugDLL"  libvorbisfile   debug

                build_sln "vorbis_dynamic.sln" "ReleaseDLL" "$AUTOBUILD_WIN_VSPLATFORM"

                copy_result "$bitdir/ReleaseDLL"  libvorbis       release
                copy_result "$bitdir/ReleaseDLL"  libvorbisfile   release
            popd
            cp -a "include/vorbis/" "$stage/include/"
        popd
    ;;
    darwin*)
        # Setup osx sdk platform
        SDKNAME="macosx"
        export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)
        export MACOSX_DEPLOYMENT_TARGET=10.13

        # Setup build flags
        ARCH_FLAGS="-arch x86_64"
        SDK_FLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"
        DEBUG_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -O0 -g -msse4.2 -fPIC -DPIC"
        RELEASE_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -O3 -ffast-math -g -msse4.2 -fPIC -DPIC -fstack-protector-strong"
        DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
        RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
        DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
        RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
        DEBUG_CPPFLAGS="-DPIC"
        RELEASE_CPPFLAGS="-DPIC"
        DEBUG_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names"
        RELEASE_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names"

        pushd "$OGG_SOURCE_DIR"
            # force regenerate autoconf
            autoreconf -fvi

            # debug configure and build
            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$DEBUG_CFLAGS" CXXFLAGS="$DEBUG_CXXFLAGS" \
                CPPFLAGS="$DEBUG_CPPFLAGS" LDFLAGS="$DEBUG_LDFLAGS" \
                ../configure --with-pic --enable-shared=no --prefix="\${AUTOBUILD_PACKAGES_DIR}" \
                    --includedir="\${prefix}/include" --libdir="\${prefix}/lib/debug"
                make -j$AUTOBUILD_CPU_COUNT
                make install DESTDIR="$stage"

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make check
                fi
            popd

            # Release configure and build
            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS" CXXFLAGS="$RELEASE_CXXFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" LDFLAGS="$RELEASE_LDFLAGS" \
                ../configure --with-pic --enable-shared=no --prefix="\${AUTOBUILD_PACKAGES_DIR}" \
                    --includedir="\${prefix}/include" --libdir="\${prefix}/lib/release"
                make -j$AUTOBUILD_CPU_COUNT
                make install DESTDIR="$stage"

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make check
                fi
            popd
        popd

        pushd "$VORBIS_SOURCE_DIR"
             # force regenerate autoconf
            autoreconf -fvi

            # debug configure and build
            mkdir -p "build_debug"
            pushd "build_debug"
                CFLAGS="$DEBUG_CFLAGS" CXXFLAGS="$DEBUG_CXXFLAGS" \
                CPPFLAGS="$DEBUG_CPPFLAGS" LDFLAGS="$DEBUG_LDFLAGS" \
                    ../configure --with-pic  --enable-shared=no --with-ogg-includes="$stage/include/" --with-ogg-libraries="$stage/lib/debug" \
                    --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/debug"
                make -j$AUTOBUILD_CPU_COUNT
                make install DESTDIR="$stage"

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make check
                fi
            popd

            # Release configure and build
            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS" CXXFLAGS="$RELEASE_CXXFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" LDFLAGS="$RELEASE_LDFLAGS" \
                ../configure --with-pic  --enable-shared=no --with-ogg-includes="$stage/include/" --with-ogg-libraries="$stage/lib/release" \
                    --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/release"
                make -j$AUTOBUILD_CPU_COUNT
                make install DESTDIR="$stage"

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make check
                fi
            popd
        popd
     ;;
    linux*)
        # Default target per --address-size
        opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"

        # Setup build flags
        DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC -I$stage/include"
        RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -DPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -I$stage/include"
        DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS "
        RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
        DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
        RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
        DEBUG_CPPFLAGS="-DPIC"
        RELEASE_CPPFLAGS="-DPIC"
        DEBUG_LDFLAGS="-L$stage/lib/debug"
        RELEASE_LDFLAGS="-L$stage/lib/release"

        # Handle any deliberate platform targeting
        if [ -z "${TARGET_CPPFLAGS:-}" ]; then
            # Remove sysroot contamination from build environment
            unset CPPFLAGS
        else
            # Incorporate special pre-processing flags
            export CPPFLAGS="$TARGET_CPPFLAGS"
        fi

        # Fix up path for pkgconfig
        if [ -d "$stage/packages/lib/release/pkgconfig" ]; then
            fix_pkgconfig_prefix "$stage/packages"
        fi

        OLD_PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"

        pushd "$OGG_SOURCE_DIR"
            # force regenerate autoconf
            autoreconf -fvi

            # debug configure and build
            export PKG_CONFIG_PATH="$stage/packages/lib/debug/pkgconfig:${OLD_PKG_CONFIG_PATH}"

            CFLAGS="$DEBUG_CFLAGS" CXXFLAGS="$DEBUG_CXXFLAGS" ./configure --enable-static \
                --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/debug"
            make -j$AUTOBUILD_CPU_COUNT
            make check
            make install DESTDIR="$stage"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make check
            fi

            make distclean

            # Release configure and build
            export PKG_CONFIG_PATH="$stage/packages/lib/release/pkgconfig:${OLD_PKG_CONFIG_PATH}"

            CFLAGS="$RELEASE_CFLAGS" CXXFLAGS="$RELEASE_CXXFLAGS" ./configure --enable-static \
                --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/release"
            make -j$AUTOBUILD_CPU_COUNT
            make check
            make install DESTDIR="$stage"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make check
            fi

            make distclean
        popd
        
        pushd "$VORBIS_SOURCE_DIR"
             # force regenerate autoconf
            autoreconf -fvi

            # debug configure and build
            export PKG_CONFIG_PATH="$stage/packages/lib/debug/pkgconfig:${OLD_PKG_CONFIG_PATH}"

            CFLAGS="$DEBUG_CFLAGS" CXXFLAGS="$DEBUG_CXXFLAGS" LDFLAGS="$DEBUG_LDFLAGS" \
                ./configure --with-pic --enable-static \
                --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/debug"
            make -j$AUTOBUILD_CPU_COUNT
            make install DESTDIR="$stage"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make check
            fi

            make distclean

            # Release configure and build
            export PKG_CONFIG_PATH="$stage/packages/lib/release/pkgconfig:${OLD_PKG_CONFIG_PATH}"

            CFLAGS="$RELEASE_CFLAGS" CXXFLAGS="$RELEASE_CXXFLAGS" LDFLAGS="$RELEASE_LDFLAGS" \
                ./configure --with-pic --enable-static \
                --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include" --libdir="\${prefix}/lib/release"
            make -j$AUTOBUILD_CPU_COUNT
            make install DESTDIR="$stage"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make check
            fi

            make distclean
        popd
    ;;
esac
mkdir -p "$stage/LICENSES"
pushd "$OGG_SOURCE_DIR"
    cp COPYING "$stage/LICENSES/ogg-vorbis.txt"
popd
