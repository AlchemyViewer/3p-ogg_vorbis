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
        pushd "$OGG_SOURCE_DIR"
        opts="-arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE"
        export CFLAGS="$opts" 
        export CPPFLAGS="$opts" 
        export LDFLAGS="$opts"
        ./configure --prefix="$stage"
        make
        make install
        popd
        
        pushd "$VORBIS_SOURCE_DIR"
        ./configure --prefix="$stage"
        make
        make install
        popd
        
        mv "$stage/lib" "$stage/release"
        mkdir -p "$stage/lib"
        mv "$stage/release" "$stage/lib"
     ;;
    linux*)
        # Linux build environment at Linden comes pre-polluted with stuff that can
        # seriously damage 3rd-party builds.  Environmental garbage you can expect
        # includes:
        #
        #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
        #    DISTCC_LOCATION            top            branch      CC
        #    DISTCC_HOSTS               build_name     suffix      CXX
        #    LSDISTCC_ARGS              repo           prefix      CFLAGS
        #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
        #
        # So, clear out bits that shouldn't affect our configure-directed build
        # but which do nonetheless.
        #
        # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

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

        JOBS=`cat /proc/cpuinfo | grep processor | wc -l`

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
            make -j$JOBS
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
            make -j$JOBS
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
            make -j$JOBS
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
            make -j$JOBS
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
