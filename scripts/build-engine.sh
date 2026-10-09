#!/bin/bash
# Build the bundled engine (libzen + libmediainfo) from MediaArea's source releases.
#
# Why not Homebrew's dylibs: bottles target the build machine's macOS (minos 26.0+),
# so a bundled copy refuses to load on anything older than that — regardless of the
# app's own deployment target. Building here pins minos to MACOSX_DEPLOYMENT_TARGET.
#
# Output: Vendor/engine/{include,lib}  (git-ignored; project.yml links + bundles it)
#
# To update the engine: bump the versions + checksums below (Homebrew's formula
# lists the same tarballs: `brew info --json=v2 libmediainfo`), re-run this script,
# then rebuild the app.
set -euo pipefail
cd "$(dirname "$0")/.."

ZEN_VERSION="0.4.41"
ZEN_SHA256="eb237d7d3dca6dc6ba068719420a27de0934a783ccaeb2867562b35af3901e2d"
MI_VERSION="26.10"
MI_SHA256="a806fd36592549a03e810486f415a6858d4d8f14066bfbe97b32a447cd5eb590"

DEPLOYMENT_TARGET="$(awk -F'"' '/MACOSX_DEPLOYMENT_TARGET/{print $2; exit}' project.yml)"
ARCHS="${ARCHS:-arm64}"            # ARCHS="arm64;x86_64" for a universal engine
PREFIX="$PWD/Vendor/engine"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Download, verify, unpack into $WORK/<name>.
fetch() {
  local name="$1" url="$2" sha="$3"
  curl -fsSL --retry 3 -o "$WORK/$name.tar" "$url"
  echo "$sha  $WORK/$name.tar" | shasum -a 256 -c -
  mkdir -p "$WORK/$name"
  tar -xf "$WORK/$name.tar" -C "$WORK/$name" --strip-components 1
}

# Configure + build + install one CMake project into $PREFIX.
# Homebrew prefixes are ignored so zlib/curl come from the SDK and tinyxml2 is the
# bundled copy — nothing in the result may depend on /opt/homebrew.
build() {
  local src="$WORK/$1"
  PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
  cmake -S "$src/Project/CMake" -B "$src/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" \
    -DCMAKE_FIND_FRAMEWORK=LAST \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
    -DCMAKE_INSTALL_NAME_DIR="@rpath" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
  cmake --build "$src/build"
  cmake --install "$src/build" --strip
}

rm -rf "$PREFIX"
fetch zen "https://mediaarea.net/download/source/libzen/$ZEN_VERSION/libzen_$ZEN_VERSION.tar.bz2" "$ZEN_SHA256"
fetch mi  "https://mediaarea.net/download/source/libmediainfo/$MI_VERSION/libmediainfo_$MI_VERSION.tar.xz" "$MI_SHA256"
build zen
build mi

# Sanity: right minos, no Homebrew references.
for lib in "$PREFIX/lib/libzen.0.dylib" "$PREFIX/lib/libmediainfo.0.dylib"; do
  minos="$(vtool -show-build "$lib" | awk '/minos/{print $2; exit}')"
  [ "$minos" = "$DEPLOYMENT_TARGET" ] || { echo "error: $lib minos $minos != $DEPLOYMENT_TARGET" >&2; exit 1; }
  if otool -L "$lib" | grep -q /opt/homebrew; then
    echo "error: $lib links Homebrew:" >&2; otool -L "$lib" >&2; exit 1
  fi
done
echo "Built libzen $ZEN_VERSION + libmediainfo $MI_VERSION (macOS $DEPLOYMENT_TARGET, $ARCHS) → $PREFIX"
