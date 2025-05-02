#!/bin/bash
# PyInstaller로 KoreanTranslator.app 생성

# 의존성 설치
pip install pyinstaller pandas requests aiohttp ttkbootstrap pyobjc-framework-Cocoa
pip3 install pyinstaller pandas requests aiohttp ttkbootstrap pyobjc-framework-Cocoa

# 기존 빌드 캐시 제거
rm -rf build dist *.spec

# 먼저 spec 파일 생성
pyi-makespec --windowed \
  --icon=app_icon.icns \
  --add-data "app_icon.icns:." \
  --osx-bundle-identifier=com.example.KoreanTranslator \
  --name KoreanTranslator \
  test.py

# spec 파일 수정하여 Info.plist 설정 추가
cat > Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>app_icon.icns</string>
    <key>CFBundleDisplayName</key>
    <string>KoreanTranslator</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# spec 파일 수정
sed -i '' 's/info_plist=None/info_plist={"CFBundleIconFile": "app_icon.icns", "CFBundleDisplayName": "KoreanTranslator", "NSHighResolutionCapable": True}/' KoreanTranslator.spec

# PyInstaller 실행 (수정된 spec 파일 사용)
pyinstaller --clean KoreanTranslator.spec

# 앱 번들 내 Contents/Resources에 아이콘 복사
cp app_icon.icns dist/KoreanTranslator.app/Contents/Resources/

# macOS 아이콘 캐시 갱신
touch dist/KoreanTranslator.app
killall Dock

echo "KoreanTranslator.app 생성 완료!"