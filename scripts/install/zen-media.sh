#!/usr/bin/env bash
# Reproduce the laptop's FFmpeg 8 ABI for Zen without downgrading system packages.
set -euo pipefail
[[ ${CONFIG_ZEN_MEDIA:-1} != 0 ]] || exit 0
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
    echo 'Zen media compatibility bundle is supported only on Arch x86_64.'
    exit 0
}
target=${ZEN_MEDIA_LIB_DIR:-$HOME/.local/lib/ffmpeg-firefox}

check_bundle() {
    LD_LIBRARY_PATH="$1${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" python3 - <<'PY'
import ctypes
codec = ctypes.CDLL('libavcodec.so.62')
codec.avcodec_find_decoder_by_name.restype = ctypes.c_void_p
assert codec.avcodec_version() >> 16 == 62
assert codec.avcodec_find_decoder_by_name(b'h264'), 'H.264 decoder missing'
for lib in ['libavutil.so.60', 'libswresample.so.6']:
    ctypes.CDLL(lib)
PY
}
if [[ -f $target/libavcodec.so.62 ]] && check_bundle "$target" 2>/dev/null; then
    echo 'Zen media compatibility libraries already load successfully.'
    exit 0
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/extract"
for spec in 'ffmpeg:ffmpeg-2%3A8.1.2-11-x86_64.pkg.tar.zst' 'x265:x265-4.2-2-x86_64.pkg.tar.zst'; do
    name=${spec%%:*} archive=${spec#*:}
    url="https://archive.archlinux.org/packages/${name:0:1}/$name/$archive"
    package="$scratch/$name.pkg.tar.zst"
    if [[ -n ${ZEN_MEDIA_PACKAGE_CACHE:-} ]]; then
        cp "$ZEN_MEDIA_PACKAGE_CACHE/$name.pkg.tar.zst" "$package"
        cp "$ZEN_MEDIA_PACKAGE_CACHE/$name.pkg.tar.zst.sig" "$package.sig"
    else
        curl -fsSL --retry 2 -o "$package" "$url"
        curl -fsSL --retry 2 -o "$package.sig" "$url.sig"
    fi
    pacman-key --verify "$package.sig" "$package"
    # Extract libraries only, never package install scripts or system files.
    if [[ $name == ffmpeg ]]; then
        bsdtar -xf "$package" -C "$scratch/extract" \
            --include 'usr/lib/libavcodec.so.62*' \
            --include 'usr/lib/libavutil.so.60*' --include 'usr/lib/libswresample.so.6*'
    else
        bsdtar -xf "$package" -C "$scratch/extract" --include 'usr/lib/libx265.so.216*'
    fi
done
check_bundle "$scratch/extract/usr/lib"
mkdir -p "${target%/*}"
staging=$(mktemp -d "${target}.new.XXXXXX")
cp -a "$scratch/extract/usr/lib/." "$staging/"
if [[ -e $target ]]; then
    mv "$target" "${target}.previous.$(date +%s)"
fi
mv "$staging" "$target"
echo "Zen media compatibility libraries installed: $target"
