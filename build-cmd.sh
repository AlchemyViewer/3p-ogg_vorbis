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

build=${AUTOBUILD_BUILD_ID:=0}
echo "${OGG_VERSION}-${VORBIS_VERSION}.${build}" > "${stage}/VERSION.txt"

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
        pushd "$OGG_SOURCE_DIR"
        opts="-m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE"
        CFLAGS="$opts" CXXFLAGS="$opts" ./configure --prefix="$stage"
        make
        make install
        popd
        
        pushd "$VORBIS_SOURCE_DIR"
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:"$stage/lib"
        CFLAGS="$opts" CXXFLAGS="$opts" ./configure --prefix="$stage"
        make
        make install
        popd
        
        mv "$stage/lib" "$stage/release"
        mkdir -p "$stage/lib"
        mv "$stage/release" "$stage/lib"
    ;;
esac
mkdir -p "$stage/LICENSES"
pushd "$OGG_SOURCE_DIR"
    cp COPYING "$stage/LICENSES/ogg-vorbis.txt"
popd
