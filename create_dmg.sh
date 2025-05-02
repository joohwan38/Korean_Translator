#!/bin/bash
# DMG 생성 스크립트 (create-dmg 사용, 앱 크기 최적화 포함, pip3 사용, PyInstaller 오류 수정)

# 변수 정의
APP_NAME="KoreanTranslator"
DMG_NAME="${APP_NAME}.dmg"
CONTENTS_DIR="dmg_contents"
SOURCE_APP="dist/${APP_NAME}.app"
README_FILE="README.txt"
REQUIRED_SPACE_GB=2  # 필요한 최소 공간 (GB)
PYTHON_SCRIPT="KoreanTranslator.py"  # PyInstaller로 빌드할 Python 스크립트
SPEC_FILE="${APP_NAME}.spec"  # PyInstaller 스펙 파일

# 오류 처리 함수
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# 디스크 공간 확인
check_disk_space() {
    AVAILABLE_SPACE=$(df -g / | tail -1 | awk '{print $4}')
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE_GB" ]; then
        error_exit "Insufficient disk space. At least ${REQUIRED_SPACE_GB}GB required, but only ${AVAILABLE_SPACE}GB available."
    fi
}

# create-dmg 설치 확인
check_create_dmg() {
    if ! command -v create-dmg &> /dev/null; then
        error_exit "create-dmg is not installed. Install it with 'brew install create-dmg'."
    fi
}

# PyInstaller 설치 확인
check_pyinstaller() {
    if ! command -v pyinstaller &> /dev/null; then
        error_exit "PyInstaller is not installed. Install it with 'pip3 install pyinstaller'."
    fi
}

# Python 및 pip3 설치 확인
check_python_pip() {
    if ! command -v python3 &> /dev/null; then
        error_exit "Python3 is not installed. Install it with 'brew install python' or from python.org."
    fi
    if ! command -v pip3 &> /dev/null; then
        echo "pip3 is not installed. Attempting to install..."
        python3 -m ensurepip --upgrade || error_exit "Failed to install pip3 with ensurepip"
        python3 -m pip install --upgrade pip || error_exit "Failed to upgrade pip3"
    fi
}

# .spec 파일 수정 (numpy 제외, strip 적용)
modify_spec_file() {
    echo "Modifying ${SPEC_FILE} for optimization..."
    # 백업 생성
    cp "${SPEC_FILE}" "${SPEC_FILE}.bak" || error_exit "Failed to backup ${SPEC_FILE}"

    # Analysis 섹션에 excluded_imports 추가
    sed -i '' "/^a = Analysis(/,/)$/ s/excluded_imports=\[[^]]*\]/excluded_imports=['numpy']/" "${SPEC_FILE}" || error_exit "Failed to modify excluded_imports in ${SPEC_FILE}"
    # strip=True 추가 (EXE 또는 BUNDLE 섹션)
    sed -i '' "/^exe = EXE(/,/)$/ s/strip=False/strip=True/" "${SPEC_FILE}" || error_exit "Failed to modify strip in ${SPEC_FILE}"
}

# 앱 크기 최적화 (pandas 및 PyInstaller 빌드)
optimize_app() {
    echo "Optimizing ${APP_NAME}.app..."

    # Python 및 pip3 확인
    check_python_pip

    # pandas 최적화: 소스에서 빌드
    echo "Installing optimized pandas..."
    pip3 install pandas --no-binary pandas || error_exit "Failed to install pandas with --no-binary"

    # PyInstaller로 최적화된 빌드
    echo "Building ${APP_NAME}.app with PyInstaller..."
    check_pyinstaller
    if [ -f "${SPEC_FILE}" ]; then
        # .spec 파일 수정
        modify_spec_file
        pyinstaller "${SPEC_FILE}" || error_exit "PyInstaller build failed with ${SPEC_FILE}"
    else
        [ -f "${PYTHON_SCRIPT}" ] || error_exit "${PYTHON_SCRIPT} not found!"
        pyinstaller --strip --exclude-module numpy --name "${APP_NAME}" "${PYTHON_SCRIPT}" || error_exit "PyInstaller build failed"
    fi

    # 빌드된 앱 크기 확인
    echo "Checking size of ${SOURCE_APP}..."
    du -sh "${SOURCE_APP}" || error_exit "Failed to check app size"
}

# 파일 존재 여부 확인
echo "Checking file existence..."
[ -f "${README_FILE}" ] || error_exit "${README_FILE} not found!"

# 앱 최적화 실행
optimize_app
[ -d "${SOURCE_APP}" ] || error_exit "${SOURCE_APP} not found after optimization!"

# 디스크 공간 확인
echo "Checking available disk space..."
check_disk_space

# create-dmg 설치 확인
echo "Checking create-dmg installation..."
check_create_dmg

# 기존 디렉토리 정리 및 생성
echo "Creating ${CONTENTS_DIR} directory..."
rm -rf "${CONTENTS_DIR}"
mkdir -p "${CONTENTS_DIR}" || error_exit "Failed to create ${CONTENTS_DIR}"

# 파일 복사
echo "Copying files..."
cp -R "${SOURCE_APP}" "${CONTENTS_DIR}/" || error_exit "Failed to copy ${SOURCE_APP}"
cp "${README_FILE}" "${CONTENTS_DIR}/" || error_exit "Failed to copy ${README_FILE}"

# DMG 생성
echo "Creating DMG with create-dmg..."
create-dmg \
  --volname "${APP_NAME}" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 200 190 \
  --icon "${README_FILE}" 400 190 \
  --app-drop-link 600 190 \
  "${DMG_NAME}" \
  "${CONTENTS_DIR}/" || error_exit "Failed to create DMG"

# 정리
echo "Cleaning up..."
rm -rf "${CONTENTS_DIR}" || error_exit "Failed to clean up"

echo "${DMG_NAME} created successfully!"