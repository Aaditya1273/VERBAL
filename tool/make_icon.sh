#!/usr/bin/env sh
# Generate VERBAL's launcher icon at every size Android and Devpost need.
#
# The mark is the mascot at rest, leaning out of the bottom-left of a dark
# rounded tile, large enough to bleed past its edge. One source, every size,
# so the icon can never drift from the character.
#
#     sh tool/make_icon.sh
set -e
cd "$(dirname "$0")/.."
src=assets/mascot/neutre.png
bg='#09090B'

render() { # size out
  s=$1
  r=$(( s * 23 / 100 ))            # corner radius
  m=$(( s * 112 / 100 ))           # the mascot, larger than the tile
  magick -size "${s}x${s}" gradient:'#3B3B40-#0B0B0D' \
    \( "$src" -resize "${m}x${m}" \) -geometry "-$(( s * 14 / 100 ))+$(( s * 22 / 100 ))" -composite \
    \( -size "${s}x${s}" xc:none -draw "roundrectangle 0,0,$(( s - 1 )),$(( s - 1 )),$r,$r" \) \
    -compose DstIn -composite -background none "$2"
  echo "  $2"
}

echo "Android launcher icons:"
render 48  android/app/src/main/res/mipmap-mdpi/ic_launcher.png
render 72  android/app/src/main/res/mipmap-hdpi/ic_launcher.png
render 96  android/app/src/main/res/mipmap-xhdpi/ic_launcher.png
render 144 android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png
render 192 android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
echo "Store / Devpost assets:"
render 1024 assets/icon/verbal_icon_1024.png
render 512  assets/icon/verbal_icon_512.png
