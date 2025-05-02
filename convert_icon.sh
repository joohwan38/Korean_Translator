#!/bin/bash
# app_icon.png를 app_icon.icns로 변환

# 출력 디렉토리 생성
mkdir -p icon.iconset

# 다양한 크기로 PNG 리사이징
sips -z 16 16     app_icon.png --out icon.iconset/icon_16x16.png
sips -z 32 32     app_icon.png --out icon.iconset/icon_16x16@2x.png
sips -z 32 32     app_icon.png --out icon.iconset/icon_32x32.png
sips -z 64 64     app_icon.png --out icon.iconset/icon_32x32@2x.png
sips -z 128 128   app_icon.png --out icon.iconset/icon_128x128.png
sips -z 256 256   app_icon.png --out icon.iconset/icon_128x128@2x.png
sips -z 256 256   app_icon.png --out icon.iconset/icon_256x256.png
sips -z 512 512   app_icon.png --out icon.iconset/icon_256x256@2x.png
sips -z 512 512   app_icon.png --out icon.iconset/icon_512x512.png
sips -z 1024 1024 app_icon.png --out icon.iconset/icon_512x512@2x.png

# iconset을 icns로 변환
iconutil -c icns icon.iconset -o app_icon.icns

# 정리
rm -rf icon.iconset
echo "app_icon.icns 생성 완료!"