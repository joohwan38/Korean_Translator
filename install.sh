#!/bin/bash

# 클릭으로 실행 가능한 한국어 다국어 번역기 DMG 생성 스크립트
# macOS 환경에서 실행 가능한 앱 번들을 생성합니다

echo "===== 클릭으로 실행 가능한 한국어 다국어 번역기 DMG 패키징 스크립트 ====="

# 작업 디렉토리 확인
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"
echo "현재 작업 디렉토리: $(pwd)"

# 필요한 도구가 설치되어 있는지 확인
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "$1이(가) 설치되어 있지 않습니다."
        return 1
    fi
    return 0
}

# 필수 명령어 확인
if ! check_command python3; then
    echo "Python 3가 필요합니다. https://www.python.org/downloads/ 에서 설치해주세요."
    echo "주의: python.org에서 공식 배포판을 사용하세요. Homebrew 등으로 설치한 Python은 Tkinter 문제가 발생할 수 있습니다."
    exit 1
fi

# Python 설치 확인
PYTHON_PATH=$(which python3)
echo "사용 중인 Python 경로: $PYTHON_PATH"
echo "Python 버전:"
python3 -V

# 필요한 Python 패키지 설치
echo "필요한 Python 패키지 설치 중..."
python3 -m pip install --user pandas openpyxl requests aiohttp pyinstaller pillow

# 메인 Python 파일 확인
MAIN_PY="test.py"
if [ ! -f "$MAIN_PY" ]; then
    echo "오류: $MAIN_PY 파일이 없습니다. 앱 소스코드가 들어있는 $MAIN_PY 파일이 현재 디렉토리에 있어야 합니다."
    exit 1
fi
echo "소스 파일 발견: $MAIN_PY"

# 경로 관련 패치를 적용할 것인지 확인
echo "경로 관련 문제를 해결하기 위한 소스 코드 패치를 적용하시겠습니까? (y/n)"
read -p "선택 (기본값: y): " PATCH_CHOICE
PATCH_CHOICE=${PATCH_CHOICE:-y}

if [[ $PATCH_CHOICE == "y" || $PATCH_CHOICE == "Y" ]]; then
    # 백업 생성
    cp "$MAIN_PY" "${MAIN_PY}.bak"
    echo "원본 파일 백업: ${MAIN_PY}.bak"
    
    # 소스 코드 첫 부분에 경로 관련 코드 추가
    PATCH_CODE="
# 이 코드는 PyInstaller로 패키징 시 경로 문제를 해결하기 위해 install.sh에 의해 추가되었습니다
import os
import sys

# 앱이 패키지된 경우 sys._MEIPASS 사용, 그렇지 않으면 현재 디렉토리 사용
if getattr(sys, 'frozen', False):
    # PyInstaller에 의해 패키징된 경우
    bundle_dir = sys._MEIPASS
    print(f'앱 번들 경로: {bundle_dir}')
else:
    # 일반 Python 스크립트로 실행된 경우
    bundle_dir = os.path.dirname(os.path.abspath(__file__))
    print(f'스크립트 경로: {bundle_dir}')

# 아래 코드는 원본 소스 코드입니다
"

    # 소스 코드 패치 적용
    TMP_FILE="${MAIN_PY}.tmp"
    echo "$PATCH_CODE" > "$TMP_FILE"
    cat "$MAIN_PY" >> "$TMP_FILE"
    mv "$TMP_FILE" "$MAIN_PY"
    echo "소스 코드에 경로 관련 패치가 적용되었습니다."
else
    echo "패치 적용을 건너뜁니다."
fi

# 시작 시 기존 빌드 정리
echo "기존 빌드 정리 중..."
rm -rf build dist *.spec

# 기존 앱 삭제 (테스트용으로 /Applications에 설치했다면)
sudo rm -rf /Applications/한국어다국어번역기.app

# 임시 파일 제거
rm -f *.tmp *.bak runtime_hook.py entitlements.plist


# 기존 PNG 아이콘을 ICNS로 변환
PNG_ICON="app_icon.png"
ICON_FILE="AppIcon.icns"

if [ ! -f "$PNG_ICON" ]; then
    echo "오류: app_icon.png 파일을 찾을 수 없습니다."
    exit 1
fi

echo "기존 PNG 아이콘을 ICNS로 변환 중..."
# 임시 디렉토리 생성
ICONSET_DIR="AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# 다양한 크기로 아이콘 생성
for size in 16 32 64 128 256 512; do
    # 일반 해상도
    sips -z $size $size "$PNG_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" &>/dev/null
    
    # 레티나 해상도 (@2x)
    if [ $size -le 512 ]; then
        sips -z $((size*2)) $((size*2)) "$PNG_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" &>/dev/null
    fi
done

# iconutil로 .icns 파일 생성
if command -v iconutil &> /dev/null; then
    iconutil -c icns "$ICONSET_DIR"
    echo "아이콘 파일 생성 완료: $ICON_FILE"
else
    echo "경고: iconutil 명령어를 찾을 수 없습니다. macOS에서 실행해주세요."
    exit 1
fi

# 임시 디렉토리 정리
rm -rf "$ICONSET_DIR"

# 런타임 훅 스크립트 생성 (macOS 앱 번들 경로 처리용)
cat > "runtime_hook.py" << EOL
# -*- coding: utf-8 -*-
import os
import sys
import tkinter as tk

# macOS 앱 번들 실행 시 필요한 설정
def _setup_macos_app_environment():
    # 앱 번들 모드에서 올바른 경로 설정
    if getattr(sys, 'frozen', False):
        bundle_dir = sys._MEIPASS
        os.environ['PATH'] = os.path.join(bundle_dir, 'bin') + ':' + os.environ['PATH']
        
        # Tkinter 초기화 전에 메인 윈도우 설정
        # 이 설정은 macOS에서 Tkinter 앱이 클릭으로 실행될 때 필요함
        try:
            tk.Tk.report_callback_exception = lambda self, exc, val, tb: print(f"Error: {val}")
        except:
            pass

# 환경 설정 실행
_setup_macos_app_environment()
EOL

# PyInstaller .spec 파일 생성
echo "PyInstaller .spec 파일 생성 중..."
cat > "한국어다국어번역기.spec" << EOL
# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

# macOS 앱 번들용 추가 파일 목록
added_files = [
    ('${ICON_FILE}', '.'),
    ('${PNG_ICON}', '.'),
]

# 주요 분석 설정
a = Analysis(
    ['${MAIN_PY}'],
    pathex=[],
    binaries=[],
    datas=added_files,
    hiddenimports=[
        'pandas', 'numpy', 'openpyxl', 'xlrd', 'requests', 'aiohttp', 'asyncio', 
        'tkinter', 'tkinter.filedialog', 'tkinter.messagebox', 'tkinter.ttk',
        'sqlite3', 'threading', 'json', 're', 'subprocess', 'time', 'sys', 'os'
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=['runtime_hook.py'],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

# 유효하지 않은 모듈 제거
def remove_invalid_modules(modules):
    valid_modules = []
    for module in modules:
        if isinstance(module, tuple) and len(module) >= 2:
            valid_modules.append(module)
    return valid_modules

# 중복 모듈 제거
a.binaries = remove_invalid_modules(a.binaries)
a.datas = remove_invalid_modules(a.datas)

# PYZ 아카이브 생성
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

# 실행 파일 설정
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='한국어다국어번역기',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,  # GUI 모드로 설정 (클릭으로 실행 시 콘솔 창 숨김)
    disable_windowed_traceback=False,
    argv_emulation=True,  # macOS에서 중요한 옵션
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='${ICON_FILE}',
)

# 파일 수집 설정
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='한국어다국어번역기',
)

# macOS 앱 번들 설정
app = BUNDLE(
    coll,
    name='한국어다국어번역기.app',
    icon='${ICON_FILE}',
    bundle_identifier='com.translator.koreantranslator',
    info_plist={
        'CFBundleShortVersionString': '1.0.0',
        'CFBundleName': '한국어다국어번역기',
        'NSPrincipalClass': 'NSApplication',
        'NSHighResolutionCapable': 'True',
        'NSRequiresAquaSystemAppearance': 'False',
        'CFBundleDisplayName': '한국어다국어번역기',
        'CFBundleGetInfoString': '한국어 다국어 번역기',
        'LSMinimumSystemVersion': '10.13.0',
        'CFBundleDocumentTypes': [
            {
                'CFBundleTypeName': 'Excel 문서',
                'CFBundleTypeExtensions': ['xlsx', 'xls'],
                'CFBundleTypeRole': 'Editor',
            }
        ],
        'NSAppleEventsUsageDescription': '이 앱은 외부 프로그램과 통신하기 위해 Apple 이벤트를 사용합니다.',
        'NSHumanReadableCopyright': 'Copyright © 2024 All rights reserved.',
    },
)
EOL

# PyInstaller로 앱 빌드
echo "PyInstaller로 애플리케이션 빌드 중..."
python3 -m PyInstaller --clean --noconfirm 한국어다국어번역기.spec

BUILD_RESULT=$?
if [ $BUILD_RESULT -ne 0 ]; then
    echo "애플리케이션 빌드에 실패했습니다."
    exit 1
fi

# 앱번들 확인
APP_NAME="한국어다국어번역기.app"
APP_PATH="dist/$APP_NAME"

if [ ! -d "$APP_PATH" ]; then
    echo "앱 빌드에 실패했습니다."
    exit 1
fi

# 앱 권한 및 속성 설정
echo "앱 실행 권한 및 속성 설정 중..."
chmod -R +x "$APP_PATH/Contents/MacOS/"

# 앱 확장 속성 제거 (quarantine 등)
xattr -cr "$APP_PATH"

# macOS .app 번들 특수 권한 설정 
if [ -d "$APP_PATH/Contents/MacOS" ]; then
    chmod +x "$APP_PATH/Contents/MacOS/"*
fi

# Info.plist 확인
echo "Info.plist 확인 중..."
cat "$APP_PATH/Contents/Info.plist"

# 코드 서명 적용 (개선된 버전)
echo "애플리케이션에 개선된 코드 서명 적용 중..."

# 실행 파일 확인 및 수정
EXEC_PATH="$APP_PATH/Contents/MacOS/한국어다국어번역기"
if [ ! -f "$EXEC_PATH" ]; then
    echo "경고: 실행 파일이 없습니다. 찾는 중..."
    
    # MacOS 디렉토리의 모든 실행 파일 찾기
    EXEC_FILES=$(find "$APP_PATH/Contents/MacOS/" -type f)
    if [ -n "$EXEC_FILES" ]; then
        FIRST_EXEC=$(echo "$EXEC_FILES" | head -1)
        cp "$FIRST_EXEC" "$EXEC_PATH"
        chmod +x "$EXEC_PATH"
        echo "실행 파일을 복사했습니다: $FIRST_EXEC -> 한국어다국어번역기"
    else
        echo "오류: MacOS 디렉토리에 실행 파일이 없습니다."
        exit 1
    fi
fi

# 코드 서명하기 전에 Info.plist 확인 및 수정
/usr/libexec/PlistBuddy -c "Delete :CFBundleExecutable" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string 한국어다국어번역기" "$APP_PATH/Contents/Info.plist"

# 리소스 확인
if [ ! -d "$APP_PATH/Contents/Resources" ]; then
    mkdir -p "$APP_PATH/Contents/Resources"
fi

# 아이콘 파일 확인
if [ -f "${ICON_FILE}" ] && [ ! -f "$APP_PATH/Contents/Resources/${ICON_FILE}" ]; then
    cp "${ICON_FILE}" "$APP_PATH/Contents/Resources/"
fi

# 먼저 모든 코드 서명 제거
echo "기존 코드 서명 제거 중..."
codesign --remove-signature "$APP_PATH" 2>/dev/null || true

# 확장 속성 제거
echo "확장 속성 제거 중..."
xattr -cr "$APP_PATH"

# 모든 바이너리 파일에 개별적으로 서명
echo "개별 바이너리 파일에 서명 중..."
find "$APP_PATH/Contents/Frameworks" -type f -name "*.so" -exec codesign --force --sign - {} \; 2>/dev/null || true
find "$APP_PATH/Contents/Frameworks" -type f -name "*.dylib" -exec codesign --force --sign - {} \; 2>/dev/null || true

# Python 라이브러리에 특별히 서명
if [ -f "$APP_PATH/Contents/Frameworks/libpython3.12.dylib" ]; then
    echo "Python 라이브러리에 서명 중..."
    codesign --force --sign - "$APP_PATH/Contents/Frameworks/libpython3.12.dylib"
fi

# 실행 파일에 서명
echo "실행 파일에 서명 중..."
chmod +x "$APP_PATH/Contents/MacOS/한국어다국어번역기"
codesign --force --sign - "$APP_PATH/Contents/MacOS/한국어다국어번역기"

# entitlements.plist 파일 생성
cat > "entitlements.plist" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOL

# 마지막으로 앱 전체에 서명 (entitlements 포함)
echo "앱 번들 전체에 서명 중..."
codesign --force --deep --options runtime --entitlements entitlements.plist --sign - "$APP_PATH"

# 코드 서명 검증
echo "코드 서명 검증 중..."
codesign -vvv "$APP_PATH"

# 서명 검증 결과 확인
if [ $? -ne 0 ]; then
    echo "경고: 코드 서명 검증에 실패했습니다."
    echo "앱이 정상적으로 실행되지 않을 수 있습니다."
    
    # 추가 디버깅 정보
    echo "실행 파일 확인:"
    ls -la "$APP_PATH/Contents/MacOS/"
    
    echo "Python 라이브러리 확인:"
    ls -la "$APP_PATH/Contents/Frameworks/libpython3.12.dylib" 2>/dev/null || echo "Python 라이브러리가 없습니다."
else
    echo "코드 서명이 성공적으로 적용되었습니다."
fi

# DMG 생성
echo "DMG 파일 생성 중..."
DMG_NAME="한국어다국어번역기_설치파일.dmg"

# 기존 DMG 파일 삭제
if [ -f "$DMG_NAME" ]; then
    rm "$DMG_NAME"
fi

# hdiutil로 DMG 생성
hdiutil create -volname "한국어 다국어 번역기" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_NAME"

if [ $? -ne 0 ]; then
    echo "DMG 파일 생성에 실패했습니다."
    echo "애플리케이션은 'dist/한국어다국어번역기.app'에 생성되었습니다."
else
    echo "DMG 파일 생성 완료: $DMG_NAME"
    echo "생성된 DMG 파일 정보:"
    ls -lh "$DMG_NAME"
fi

# 디버그 실행 스크립트 생성
cat > debug_app.sh << 'EOL'
#!/bin/bash

# 앱 디버깅 스크립트
APP_PATH="dist/한국어다국어번역기.app"
if [ ! -d "$APP_PATH" ]; then
    echo "오류: $APP_PATH를 찾을 수 없습니다."
    exit 1
fi

EXEC_PATH="$APP_PATH/Contents/MacOS/한국어다국어번역기"
if [ ! -f "$EXEC_PATH" ]; then
    echo "오류: 실행 파일을 찾을 수 없습니다."
    find "$APP_PATH" -type f -name "한국어*" -o -name "Korean*"
    exit 1
fi

echo "앱을 터미널에서 실행하여 오류 메시지를 확인합니다..."
"$EXEC_PATH"
EOL

chmod +x debug_app.sh

# 앱 확인 스크립트 생성
cat > check_app.sh << 'EOL'
#!/bin/bash

# 앱 확인 스크립트
APP_PATH="dist/한국어다국어번역기.app"
if [ ! -d "$APP_PATH" ]; then
    echo "오류: $APP_PATH를 찾을 수 없습니다."
    exit 1
fi

echo "=== 앱 번들 구조 확인 ==="
find "$APP_PATH" -type f -not -path "*/\.*" | sort

echo -e "\n=== 앱 실행 파일 권한 확인 ==="
ls -la "$APP_PATH/Contents/MacOS/"

echo -e "\n=== Info.plist 확인 ==="
cat "$APP_PATH/Contents/Info.plist"

echo -e "\n=== 앱 코드 서명 확인 ==="
codesign -vvv "$APP_PATH" 2>&1

echo -e "\n=== 앱 서명 문제 해결 ==="
echo "앱에 서명 문제가 있을 경우 다음 명령으로 해결할 수 있습니다:"
echo "codesign --force --deep --sign - \"$APP_PATH\""

echo -e "\n=== 앱 확장 속성 제거 ==="
echo "quarantine 등의 확장 속성이 있을 경우 다음 명령으로 제거할 수 있습니다:"
echo "xattr -cr \"$APP_PATH\""
EOL

chmod +x check_app.sh

# 간단한 앱 실행 테스트
echo "간단한 앱 실행 테스트 중..."
if [ -f "$APP_PATH/Contents/MacOS/한국어다국어번역기" ]; then
    "$APP_PATH/Contents/MacOS/한국어다국어번역기" &
    APP_PID=$!
    sleep 2
    if kill -0 $APP_PID 2>/dev/null; then
        echo "앱이 성공적으로 실행되었습니다. 종료합니다."
        kill $APP_PID
    else
        echo "앱 실행 중 문제가 발생했습니다."
    fi
else
    echo "실행 파일을 찾을 수 없습니다."
fi


echo "===== 패키징 완료 ====="
echo "생성된 DMG 파일: $DMG_NAME"
echo "애플리케이션 경로: $APP_PATH"
echo ""
echo "앱이 클릭으로 실행되지 않는 경우, 다음 스크립트를 실행하여 문제를 진단하세요:"
echo "  ./check_app.sh   # 앱 번들 구조와 권한 확인"
echo "  ./debug_app.sh   # 터미널에서 앱 실행하여 오류 메시지 확인"
echo ""
echo "참고사항:"
echo "1. 이 애플리케이션을 실행하려면 Ollama가 설치되어 있어야 합니다."
echo "2. 첫 실행 시 모델을 설치할 수 있으며, gemma3:12b 모델이 권장됩니다."
echo "3. macOS의 '확인되지 않은 개발자' 경고가 표시될 경우:"
echo "   시스템 환경설정 > 보안 및 개인 정보 보호에서 '확인 없이 열기' 클릭하거나"
echo "   Control 키를 누른 상태로 앱을 클릭한 후 '열기' 선택"
echo ""
echo "설치 위치: 생성된 DMG 파일을 열고 애플리케이션을 Applications 폴더로 드래그하세요."