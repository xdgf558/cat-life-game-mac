#!/bin/sh
set -eu

: "${CATLIFE_BUILD_CACHE:?Set CATLIFE_BUILD_CACHE to an external build cache directory}"
case "$CATLIFE_BUILD_CACHE" in
    /Volumes/*/*) ;;
    *) printf '%s\n' 'CATLIFE_BUILD_CACHE must be on a mounted volume.' >&2; exit 1 ;;
esac
catlife_volume_name=${CATLIFE_BUILD_CACHE#/Volumes/}
catlife_volume="/Volumes/${catlife_volume_name%%/*}"
if ! /sbin/mount | /usr/bin/grep -Fq " on $catlife_volume ("; then
    printf '%s\n' "Build volume is not mounted: $catlife_volume" >&2
    exit 1
fi

mkdir -p "$CATLIFE_BUILD_CACHE/Tmp" "$CATLIFE_BUILD_CACHE/DerivedData" \
    "$CATLIFE_BUILD_CACHE/SourcePackages" "$CATLIFE_BUILD_CACHE/PackageCache" \
    "$CATLIFE_BUILD_CACHE/ModuleCache.noindex" "$CATLIFE_BUILD_CACHE/XcodeCache"
catlife_hash=$(printf '%s' "$CATLIFE_BUILD_CACHE" | /usr/bin/shasum -a 256 | /usr/bin/cut -c 1-16)
catlife_temp_link="/private/tmp/catlife-appstore-$(id -u)-$catlife_hash"
if [ -L "$catlife_temp_link" ]; then
    [ "$(readlink "$catlife_temp_link")" = "$CATLIFE_BUILD_CACHE/Tmp" ] || exit 1
elif [ -e "$catlife_temp_link" ]; then
    printf '%s\n' "Temporary path already exists: $catlife_temp_link" >&2
    exit 1
else
    ln -s "$CATLIFE_BUILD_CACHE/Tmp" "$catlife_temp_link"
fi

cd "$(dirname "$0")/.."
python3 -B scripts/check_runtime_assets.py
export TMPDIR="$catlife_temp_link/"
export CLANG_MODULE_CACHE_PATH="$CATLIFE_BUILD_CACHE/ModuleCache.noindex"
export SWIFT_MODULECACHE_PATH="$CATLIFE_BUILD_CACHE/ModuleCache.noindex"
export SWIFTPM_MODULECACHE_OVERRIDE="$CATLIFE_BUILD_CACHE/ModuleCache.noindex"
xcodebuild build -project CatLifeMac.xcodeproj -scheme CatLifeMac-AppStore \
    -configuration AppStore -destination 'generic/platform=macOS' \
    -derivedDataPath "$CATLIFE_BUILD_CACHE/DerivedData" \
    -clonedSourcePackagesDirPath "$CATLIFE_BUILD_CACHE/SourcePackages" \
    -packageCachePath "$CATLIFE_BUILD_CACHE/PackageCache" \
    -disablePackageRepositoryCache -skipPackageUpdates -jobs 4 \
    CODE_SIGNING_ALLOWED=NO CLANG_MODULE_CACHE_PATH="$CATLIFE_BUILD_CACHE/ModuleCache.noindex" \
    SWIFT_MODULE_CACHE_PATH="$CATLIFE_BUILD_CACHE/ModuleCache.noindex" \
    CACHE_ROOT="$CATLIFE_BUILD_CACHE/XcodeCache" CCHROOT="$CATLIFE_BUILD_CACHE/XcodeCache" -quiet
