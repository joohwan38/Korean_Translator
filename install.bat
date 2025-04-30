@echo off
setlocal enabledelayedexpansion

:: 윈도우즈용 한국어 다국어 번역기 설치 스크립트
:: 이 스크립트는 필요한 라이브러리를 설치하고 애플리케이션을 빌드합니다.
:: 같은 폴더의 test.py 파일이 필요합니다.

:: 색상 정의
set GREEN=[92m
set YELLOW=[93m
set RED=[91m
set NC=[0m

echo %GREEN%=======================================%NC%
echo %GREEN%  Windows용 한국어 다국어 번역기 설치  %NC%
echo %GREEN%=======================================%NC%

:: Python이 설치되어 있는지 확인
python --version > nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo %RED%오류: Python이 설치되어 있지 않습니다.%NC%
    echo Python을 먼저 설치해주세요: https://www.python.org/downloads/
    pause
    exit /b 1
)

:: test.py 파일 확인
if not exist "test.py" (
    echo %RED%오류: test.py 파일이 필요합니다.%NC%
    pause
    exit /b 1
)

:: 필요한 패키지 설치
echo.
echo %YELLOW%필요한 패키지를 설치합니다...%NC%
python -m pip install --upgrade pip
python -m pip install pandas requests aiohttp pyinstaller pillow

:: 앱 아이콘 준비
echo.
echo %YELLOW%앱 아이콘을 준비합니다...%NC%

:: 임시 아이콘 생성 (실제 배포 시에는 제대로 된 아이콘 파일 사용)
if not exist "app_icon.png" (
    echo 기본 아이콘을 생성합니다...
    python -c "import numpy as np; from PIL import Image, ImageDraw; img = Image.new('RGB', (256, 256), color=(255, 255, 255)); draw = ImageDraw.Draw(img); draw.rectangle([(0, 0), (256, 256)], fill=(66, 133, 244)); draw.rectangle([(50, 50), (90, 200)], fill=(255, 255, 255)); draw.polygon([(90, 125), (200, 50), (210, 75), (110, 140)], fill=(255, 255, 255)); draw.polygon([(110, 140), (210, 200), (190, 210), (90, 125)], fill=(255, 255, 255)); img.save('app_icon.png')"
)

:: ICO 파일로 변환
echo 아이콘 변환 중...
python -c "from PIL import Image; img = Image.open('app_icon.png'); img.save('app_icon.ico')"

:: test.py 파일을 translator_app.py로 복사
echo.
echo %YELLOW%소스 코드 파일을 준비합니다...%NC%
copy test.py translator_app.py

:: PyInstaller로 앱 빌드
echo.
echo %YELLOW%애플리케이션을 빌드합니다...%NC%
python -m PyInstaller --name "Korean Translator" --windowed --onefile --icon=app_icon.ico translator_app.py

:: 템플릿 생성 스크립트 추가
echo.
echo %YELLOW%번역 템플릿 생성 스크립트를 생성합니다...%NC%

echo import pandas as pd > create_template.py
echo import os >> create_template.py
echo. >> create_template.py
echo def create_translation_template(): >> create_template.py
echo     """한국어 다국어 번역을 위한 엑셀 템플릿을 생성합니다.""" >> create_template.py
echo. >> create_template.py
echo     # 샘플 데이터 생성 >> create_template.py
echo     data = { >> create_template.py
echo         'Key': ['MSG_001', 'MSG_002', 'MSG_003', 'MSG_004', 'MSG_005'], >> create_template.py
echo         'KO': ['환영합니다', '로그인하세요', '비밀번호를 잊으셨나요?', '회원가입', '저장'], >> create_template.py
echo         'EN': ['', '', '', '', ''], >> create_template.py
echo         'JA': ['', '', '', '', ''], >> create_template.py
echo         'ZH_HANT': ['', '', '', '', ''], >> create_template.py
echo         'TH': ['', '', '', '', ''], >> create_template.py
echo         'ES': ['', '', '', '', ''] >> create_template.py
echo     } >> create_template.py
echo. >> create_template.py
echo     # DataFrame 생성 >> create_template.py
echo     df = pd.DataFrame(data) >> create_template.py
echo. >> create_template.py
echo     # 현재 사용자의 바탕화면 경로 가져오기 >> create_template.py
echo     desktop = os.path.join(os.path.expanduser('~'), 'Desktop') >> create_template.py
echo. >> create_template.py
echo     # 파일 저장 >> create_template.py
echo     template_path = os.path.join(desktop, 'Translation_Template.xlsx') >> create_template.py
echo     df.to_excel(template_path, sheet_name='MessageSet', index=False) >> create_template.py
echo. >> create_template.py
echo     print(f"번역 템플릿이 생성되었습니다: {template_path}") >> create_template.py
echo     return template_path >> create_template.py
echo. >> create_template.py
echo if __name__ == "__main__": >> create_template.py
echo     create_translation_template() >> create_template.py

:: 빌드 결과 확인
if exist "dist\Korean Translator.exe" (
    echo.
    echo %GREEN%빌드 성공!%NC%
    echo 애플리케이션이 dist 폴더에 생성되었습니다.
    
    :: 템플릿 생성
    echo.
    echo %YELLOW%번역 템플릿을 생성합니다...%NC%
    python create_template.py
    
    echo.
    echo %GREEN%설치가 완료되었습니다!%NC%
    echo 애플리케이션을 실행하기 전에 Ollama가 설치되어 있어야 합니다.
    echo Ollama 다운로드: https://ollama.ai/download
) else (
    echo.
    echo %RED%빌드 실패!%NC%
    echo 오류 로그를 확인하세요.
)

:: 정리
echo.
echo %YELLOW%임시 파일을 정리합니다...%NC%
rmdir /s /q build
del *.spec
del translator_app.py  :: 생성된 소스 코드 정리 (test.py 유지)

echo.
echo %GREEN%완료되었습니다.%NC%
pause