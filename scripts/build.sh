#!/usr/bin/env bash
# Build patched Electron for macOS arm64 and produce release assets.
# Usage: build.sh <version, e.g. 43.1.1> <output dir>
#
# Produces in <output dir>:
#   electron-v<version>-darwin-arm64.zip   (official asset naming)
#   SHASUMS256.txt
#
# Environment:
#   ELECTRON_BUILD_DIR  work dir for depot_tools + checkout (default ~/.pixel-electron-build)
#   GN_BUILD_TYPE       release (default) or testing
set -euo pipefail

VERSION="${1:?usage: build.sh <electron version> <output dir>}"
OUT_DIR="${2:?usage: build.sh <electron version> <output dir>}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ELECTRON_BUILD_DIR:-$HOME/.pixel-electron-build}"
GN_BUILD_TYPE="${GN_BUILD_TYPE:-release}"
mkdir -p "$WORK" "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

echo "== disk before =="
df -h "$WORK" | tail -1

if [ ! -d "$WORK/depot_tools" ]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$WORK/depot_tools"
fi
export PATH="$WORK/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0

mkdir -p "$WORK/electron"
cd "$WORK/electron"
if [ ! -f .gclient ]; then
  gclient config --name "src/electron" --unmanaged https://github.com/electron/electron
fi

echo "== gclient sync v$VERSION =="
gclient sync -f --with_branch_heads --with_tags --no-history -j8 \
  --revision "src/electron@v$VERSION"

echo "== apply patches =="
cd "$WORK/electron/src/electron"
git checkout -- .
for patch in "$REPO_DIR"/patches/*.patch; do
  echo "applying $(basename "$patch")"
  git apply "$patch"
done

echo "== gn gen =="
cd "$WORK/electron/src"
# //electron/BUILD.gn lists .git/packed-refs as a gn input; a no-history
# checkout has no packed refs until we pack them
git -C electron pack-refs --all || true
[ -f electron/.git/packed-refs ] || touch electron/.git/packed-refs
export CHROMIUM_BUILDTOOLS_PATH="$PWD/buildtools"
# the checkout's own pinned binaries: the depot_tools gn/ninja wrappers
# require a bootstrapped depot_tools python that we deliberately skip
GN="$PWD/buildtools/mac/gn"
NINJA="$PWD/third_party/ninja/ninja"
"$GN" gen out/Build --args="import(\"//electron/build/args/$GN_BUILD_TYPE.gn\") use_remoteexec=false"

echo "== ninja (this is the long part) =="
"$NINJA" -C out/Build electron
"$NINJA" -C out/Build electron:electron_dist_zip

ASSET="electron-v$VERSION-darwin-arm64.zip"
cp out/Build/dist.zip "$OUT_DIR/$ASSET"
cd "$OUT_DIR"
shasum -a 256 "$ASSET" | awk '{print $1 " *" $2}' > SHASUMS256.txt

echo "== artifacts =="
ls -la "$OUT_DIR"
cat SHASUMS256.txt
