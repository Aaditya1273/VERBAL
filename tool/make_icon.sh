#!/usr/bin/env sh
# Generate VERBAL's launcher icon at every size Android and Devpost need.
#
# The mark is the mascot at rest, exactly as it appears in the app, centred
# on the app's black ground. One source, every size, so the icon can never
# drift from the character.
#
#     sh tool/make_icon.sh
set -e
cd "$(dirname "$0")/.."
src=assets/mascot/neutre.png
bg='#09090B'

render() { # size out
  magick -size "$1x$1" "xc:$bg" \( "$src" -resize "$(( $1 * 78 / 100 ))x$(( $1 * 78 / 100 ))" \) \
    -gravity center -composite "$2"
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
