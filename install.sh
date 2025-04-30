#!/bin/bash

# Mac용 한국어 다국어 번역기 설치 스크립트
# 이 스크립트는 필요한 라이브러리를 설치하고 애플리케이션을 빌드합니다.
# 같은 폴더의 test.py를 소스 코드로 사용하며, 없으면 내장 코드를 생성합니다.

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 색상 초기화

echo -e "${GREEN}=======================================${NC}"
echo -e "${GREEN}  Mac용 한국어 다국어 번역기 설치     ${NC}"
echo -e "${GREEN}=======================================${NC}"

# Python이 설치되어 있는지 확인
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}오류: Python 3가 설치되어 있지 않습니다.${NC}"
    echo "Python을 먼저 설치해주세요: https://www.python.org/downloads/"
    exit 1
fi

# 필요한 패키지 설치
echo -e "\n${YELLOW}필요한 패키지를 설치합니다...${NC}"
python3 -m pip install --upgrade pip
python3 -m pip install pandas requests aiohttp sqlite3 pyinstaller

# 앱 아이콘 준비
echo -e "\n${YELLOW}앱 아이콘을 준비합니다...${NC}"

# 임시 아이콘 생성 (실제 배포 시에는 제대로 된 아이콘 파일 사용)
if [ ! -f "app_icon.png" ]; then
    echo "기본 아이콘을 생성합니다..."
    python3 -c "
import numpy as np
from PIL import Image, ImageDraw

# 1024x1024 크기의 이미지 생성
img = Image.new('RGB', (1024, 1024), color=(255, 255, 255))
draw = ImageDraw.Draw(img)

# 배경 색상
draw.rectangle([(0, 0), (1024, 1024)], fill=(66, 133, 244))

# 'K' 글자 그리기 (간단한 디자인)
draw.rectangle([(200, 200), (350, 800)], fill=(255, 255, 255))
draw.polygon([(350, 500), (800, 200), (850, 300), (450, 550)], fill=(255, 255, 255))
draw.polygon([(450, 550), (850, 800), (750, 850), (350, 500)], fill=(255, 255, 255))

img.save('app_icon.png')
"
fi

# 아이콘 디렉토리 생성
mkdir -p AppIcon.iconset

# 다양한 크기의 아이콘 생성
echo "아이콘 변환 중..."
sips -z 16 16     app_icon.png --out AppIcon.iconset/icon_16x16.png
sips -z 32 32     app_icon.png --out AppIcon.iconset/icon_16x16@2x.png
sips -z 32 32     app_icon.png --out AppIcon.iconset/icon_32x32.png
sips -z 64 64     app_icon.png --out AppIcon.iconset/icon_32x32@2x.png
sips -z 128 128   app_icon.png --out AppIcon.iconset/icon_128x128.png
sips -z 256 256   app_icon.png --out AppIcon.iconset/icon_128x128@2x.png
sips -z 256 256   app_icon.png --out AppIcon.iconset/icon_256x256.png
sips -z 512 512   app_icon.png --out AppIcon.iconset/icon_256x256@2x.png
sips -z 512 512   app_icon.png --out AppIcon.iconset/icon_512x512.png
sips -z 1024 1024 app_icon.png --out AppIcon.iconset/icon_512x512@2x.png

# .icns 파일 생성
iconutil -c icns AppIcon.iconset
echo "AppIcon.icns 아이콘 생성 완료"

# 소스 코드 파일 준비
echo -e "\n${YELLOW}소스 코드 파일을 준비합니다...${NC}"
if [ -f "test.py" ]; then
    echo "test.py 파일을 발견했습니다. 이를 소스 코드로 사용합니다."
    cp test.py translator_app.py
    # test.py가 올바른 형식인지 간단히 확인 (TranslationApp 클래스 포함 여부)
    if ! grep -q "class TranslationApp" test.py; then
        echo -e "${RED}경고: test.py에 TranslationApp 클래스가 포함되어 있지 않습니다.${NC}"
        echo "기본 소스 코드를 생성합니다."
        rm -f translator_app.py
        USE_TEST_PY=false
    else
        USE_TEST_PY=true
    fi
else
    echo "test.py 파일이 없습니다. 기본 소스 코드를 생성합니다."
    USE_TEST_PY=false
fi

# test.py가 없거나 유효하지 않은 경우 기본 소스 코드 생성
if [ "$USE_TEST_PY" != "true" ]; then
    cat > translator_app.py << 'EOF'
import pandas as pd
import requests
import json
import re
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
import threading
import os
import sys
import subprocess
import time
import sqlite3
import aiohttp
import asyncio
from multiprocessing import Pool, cpu_count
from concurrent.futures import ProcessPoolExecutor

class TranslationApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Korean to Multi-Language Translator")
        self.root.geometry("700x450")
        self.root.minsize(650, 400)

        # macOS에서 앱 아이콘 설정
        if hasattr(sys, "_MEIPASS"):
            app_path = os.path.join(sys._MEIPASS, "AppIcon.icns")
            if os.path.exists(app_path):
                self.root.iconbitmap(app_path)

        # 전체 프레임
        main_frame = tk.Frame(root)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=20)

        # Variables
        self.file_path = tk.StringVar()
        self.is_running = False
        self.stop_requested = False
        self.ollama_status = tk.StringVar(value="확인 중...")
        self.selected_model = tk.StringVar(value="llama3.2")  # 기본 모델: llama3.2
        self.available_models = []
        self.translation_cache = {}  # 메모리 내 캐시
        self.languages = ["EN", "JA", "ZH_HANT", "TH", "ES"]
        self.language_names = {
            "EN": "영어 (English)",
            "JA": "일본어 (Japanese)",
            "ZH_HANT": "중국어 번체 (Chinese Traditional)",
            "TH": "태국어 (Thai)",
            "ES": "스페인어 (Spanish)"
        }

        # 영구 캐시 초기화 (SQLite)
        self.init_cache_db()

        # GUI Elements
        header_frame = tk.Frame(main_frame)
        header_frame.pack(fill=tk.X, pady=10)
        tk.Label(header_frame, text="한국어 다국어 번역기", font=("Arial", 18, "bold")).pack(side=tk.LEFT)
        self.status_indicator = tk.Canvas(header_frame, width=15, height=15, bg="yellow")
        self.status_indicator.pack(side=tk.RIGHT, padx=5)
        tk.Label(header_frame, textvariable=self.ollama_status).pack(side=tk.RIGHT)

        # File selection
        file_frame = tk.Frame(main_frame)
        file_frame.pack(fill=tk.X, pady=10)
        tk.Label(file_frame, text="Excel 파일:").pack(side=tk.LEFT)
        tk.Entry(file_frame, textvariable=self.file_path, width=40).pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
        browse_button = tk.Button(file_frame, text="찾아보기", command=self.browse_file, width=8)
        browse_button.pack(side=tk.RIGHT)

        # 모델 선택 드롭다운
        model_frame = tk.Frame(main_frame)
        model_frame.pack(fill=tk.X, pady=10)
        tk.Label(model_frame, text="번역 모델:").pack(side=tk.LEFT)
        self.model_dropdown = ttk.Combobox(model_frame, textvariable=self.selected_model, state="readonly")
        self.model_dropdown.pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
        refresh_button = tk.Button(model_frame, text="새로고침", command=self.refresh_models, width=8)
        refresh_button.pack(side=tk.RIGHT)

        # Progress frame
        progress_frame = tk.Frame(main_frame)
        progress_frame.pack(fill=tk.X, pady=10)
        self.progress = ttk.Progressbar(progress_frame, length=500, mode='determinate')
        self.progress.pack(fill=tk.X, pady=5)
        self.progress_text = tk.StringVar(value="0%")
        tk.Label(progress_frame, textvariable=self.progress_text).pack()

        # Status label
        self.status_label = tk.Label(main_frame, text="준비 완료", wraplength=500, height=3, anchor="w", justify=tk.LEFT)
        self.status_label.pack(fill=tk.X, pady=10)

        # Buttons frame
        button_frame = tk.Frame(main_frame)
        button_frame.pack(fill=tk.X, pady=10)
        self.start_button = tk.Button(button_frame, text="번역 시작", command=self.start_translation, 
                                      bg="#4CAF50", fg="white", font=("Arial", 12, "bold"), 
                                      width=12, height=2)
        self.start_button.pack(side=tk.LEFT, padx=5)
        self.stop_button = tk.Button(button_frame, text="번역 중지", command=self.stop_translation, 
                                     bg="#f44336", fg="white", font=("Arial", 12, "bold"), 
                                     width=12, height=2, state=tk.DISABLED)
        self.stop_button.pack(side=tk.LEFT, padx=5)
        help_button = tk.Button(button_frame, text="도움말", command=self.show_help,
                              font=("Arial", 12), width=10, height=2)
        help_button.pack(side=tk.RIGHT, padx=5)
        check_button = tk.Button(button_frame, text="Ollama 확인", command=self.check_ollama_status,
                              font=("Arial", 12), width=12, height=2)
        check_button.pack(side=tk.RIGHT, padx=5)

        # Ollama API endpoint
        self.ollama_url = "http://localhost:11434/api/generate"

        # Check Ollama status and get models
        self.check_ollama_status()

    def init_cache_db(self):
        """SQLite 영구 캐시 초기화"""
        self.conn = sqlite3.connect("translation_cache.db")
        self.conn.execute("""
            CREATE TABLE IF NOT EXISTS translations (
                text TEXT,
                lang TEXT,
                translation TEXT,
                PRIMARY KEY (text, lang)
            )
        """)
        self.conn.commit()

    def get_cached_translation(self, text, target_lang):
        """캐시에서 번역 조회 (메모리 → SQLite)"""
        cache_key = f"{text}:{target_lang}"
        if cache_key in self.translation_cache:
            return self.translation_cache[cache_key]
        cursor = self.conn.execute("SELECT translation FROM translations WHERE text = ? AND lang = ?",
                                  (text, target_lang))
        result = cursor.fetchone()
        if result:
            self.translation_cache[cache_key] = result[0]
            return result[0]
        return None

    def cache_translation(self, text, target_lang, translation):
        """번역 결과를 캐시에 저장 (메모리 + SQLite)"""
        cache_key = f"{text}:{target_lang}"
        self.translation_cache[cache_key] = translation
        self.conn.execute("INSERT OR REPLACE INTO translations (text, lang, translation) VALUES (?, ?, ?)",
                         (text, target_lang, translation))
        self.conn.commit()

    def update_progress(self, value, total, message):
        """프로그레스 바와 상태 메시지 업데이트 (주기적 호출 최적화)"""
        if not hasattr(self, '_last_update') or time.time() - self._last_update > 0.5:
            self._last_update = time.time()
            percentage = int((value / total) * 100) if total > 0 else 0
            self.root.after(0, lambda: self.progress.configure(value=value))
            self.root.after(0, lambda: self.progress_text.set(f"{percentage}%"))
            self.root.after(0, lambda: self.status_label.configure(text=message))

    def refresh_models(self):
        """사용 가능한 Ollama 모델 목록 새로고침"""
        self.status_label.config(text="모델 목록 새로고침 중...")
        self.available_models = []
        self.get_available_models()

    def get_available_models(self):
        """사용 가능한 Ollama 모델 목록 가져오기 (경량 모델 우선)"""
        try:
            response = requests.get("http://localhost:11434/api/tags", timeout=5)
            if response.status_code == 200:
                data = response.json()
                models = data.get("models", []) or data.get("Tags", []) or data
                self.available_models = [model.get('name', model.get('Name', '')) for model in models if model.get('name') or model.get('Name')]
                
                if not self.available_models:
                    self.status_label.config(text="사용 가능한 모델 없음. 'ollama pull'로 모델 설치 필요.")
                    self.available_models = ["모델 없음"]
                
                # 모델 우선순위: llama3.2 → 경량 모델(grok, mistral) → 기타
                preferred_models = ['llama3.2', 'grok', 'mistral']
                sorted_models = sorted(self.available_models, 
                                    key=lambda x: (preferred_models.index(x) if x in preferred_models else len(preferred_models), x))
                self.available_models = sorted_models

                self.model_dropdown['values'] = self.available_models
                if 'llama3.2' in self.available_models:
                    self.selected_model.set('llama3.2')
                elif self.available_models:
                    self.selected_model.set(self.available_models[0])
                
                self.status_label.config(text=f"{len(self.available_models)}개의 모델 발견")
            else:
                self.status_label.config(text="Ollama API 응답 오류")
                self.available_models = ["API 오류"]
                self.model_dropdown['values'] = self.available_models
        except requests.exceptions.ConnectionError:
            self.status_label.config(text="Ollama 서버 연결 실패")
            self.available_models = ["연결 오류"]
            self.model_dropdown['values'] = self.available_models
        except requests.exceptions.Timeout:
            self.status_label.config(text="Ollama 서버 응답 시간 초과")
            self.available_models = ["타임아웃"]
            self.model_dropdown['values'] = self.available_models
        except Exception as e:
            self.status_label.config(text=f"모델 목록 가져오기 오류: {str(e)}")
            self.available_models = ["오류 발생"]
            self.model_dropdown['values'] = self.available_models

    def check_ollama_status(self):
        """Ollama 서버 상태 확인"""
        try:
            response = requests.get("http://localhost:11434/api/tags", timeout=5)
            if response.status_code == 200:
                self.ollama_status.set("Ollama 실행 중")
                self.status_indicator.config(bg="green")
                self.get_available_models()
            else:
                self.ollama_status.set("Ollama 응답 오류")
                self.status_indicator.config(bg="red")
        except requests.exceptions.ConnectionError:
            self.ollama_status.set("Ollama 실행 필요")
            self.status_indicator.config(bg="red")
            self.start_ollama()
        except requests.exceptions.Timeout:
            self.ollama_status.set("Ollama 응답 시간 초과")
            self.status_indicator.config(bg="red")
        except Exception as e:
            self.ollama_status.set(f"오류: {str(e)[:15]}...")
            self.status_indicator.config(bg="red")

    def start_ollama(self):
        """Ollama 시작 시도"""
        try:
            result = messagebox.askyesno("Ollama 실행", "Ollama가 실행되고 있지 않습니다. 실행하시겠습니까?")
            if result:
                subprocess.Popen(["open", "-a", "Ollama"])
                self.status_label.config(text="Ollama 실행 중... 잠시 후 확인")
        except Exception as e:
            messagebox.showerror("오류", f"Ollama 실행 실패: {str(e)}")

    def show_help(self):
        """도움말 창 표시"""
        help_text = """
        [사용 방법]
        1. Ollama가 설치 및 실행 중인지 확인.
        2. 드롭다운에서 모델 선택 (권장: llama3.2 또는 grok/mistral).
        3. '찾아보기'로 Excel 파일 선택.
        4. '번역 시작' 클릭.
        5. 중지하려면 '번역 중지' 클릭.

        [엑셀 파일 형식]
        - "MessageSet" 시트 필요.
        - 열: KO, EN, JA, ZH_HANT, TH, ES
        - KO 열에 한국어 입력, 나머지 비어 있으면 번역.

        [모델 추가]
        - 터미널에서 'ollama pull llama3.2' 등 실행.
        - 추가 후 '새로고침' 클릭.

        [문제 해결]
        - '확인 중...' 지속 시 Ollama 설치 확인.
        - 모델 목록 없으면 '새로고침' 클릭.
        - 오류 시 '번역 중지' 후 재시도.
        """
        help_window = tk.Toplevel(self.root)
        help_window.title("도움말")
        help_window.geometry("500x450")
        tk.Label(help_window, text="Korean Translator 도움말", font=("Arial", 16, "bold")).pack(pady=10)
        text_widget = tk.Text(help_window, wrap=tk.WORD, width=60, height=20)
        text_widget.pack(padx=20, pady=10, fill=tk.BOTH, expand=True)
        text_widget.insert(tk.END, help_text)
        text_widget.config(state=tk.DISABLED)
        tk.Button(help_window, text="닫기", command=help_window.destroy).pack(pady=10)

    def browse_file(self):
        file = filedialog.askopenfilename(filetypes=[("Excel 파일", "*.xlsx")])
        if file:
            self.file_path.set(file)
            self.status_label.config(text=f"선택된 파일: {os.path.basename(file)}")

    def create_prompt(self, korean_text, target_lang):
        """최적화된 프롬프트 생성"""
        return f"Translate from Korean to {target_lang}: '{korean_text}'"

    def clean_translation(self, text):
        """LLM 응답 정제"""
        text = re.sub(r'^[\s\'\""`]*', '', text)
        text = re.sub(r'[\s\'\""`]*$', '', text)
        prefixes = [
            r'번역\s*:', r'번역은\s*:', r'translation\s*:', r'translated text\s*:',
            r'is\s*:', r'in \w+\s*:', r'the translation is\s*:',
            r'translation of the text\s*:', r'here is the \w+ translation\s*:'
        ]
        pattern = '|'.join(prefixes)
        text = re.sub(fr'(?i)^(.*?({pattern}))', '', text)
        text = re.sub(r'[\*\`\#]', '', text)
        return text.strip()

    async def translate_async(self, text, target_lang, session, max_retries=3):
        """비동기 번역 요청"""
        if self.stop_requested:
            return text
        cached = self.get_cached_translation(text, target_lang)
        if cached:
            return cached
        model = self.selected_model.get()
        if not model or model in ["모델 없음", "API 오류", "연결 오류", "오류 발생", "타임아웃"]:
            self.root.after(0, lambda: messagebox.showerror("오류", "유효한 모델 선택 필요"))
            return text
        prompt = self.create_prompt(text, target_lang)
        payload = {"model": model, "prompt": prompt, "stream": False, "temperature": 0.0}
        for attempt in range(max_retries):
            if self.stop_requested:
                return text
            try:
                async with session.post(self.ollama_url, json=payload, timeout=30) as response:
                    response.raise_for_status()
                    result = await response.json()
                    translated = self.clean_translation(result["response"])
                    self.cache_translation(text, target_lang, translated)
                    return translated
            except Exception as e:
                if attempt < max_retries - 1:
                    continue
                self.update_progress(self.progress['value'], self.progress['maximum'], 
                                   f"{target_lang} 번역 오류: {str(e)}")
                return text
        return text

    async def translate_batch_async(self, texts, target_lang, batch_size=10):
        """비동기 배치 번역"""
        results = []
        async with aiohttp.ClientSession() as session:
            for i in range(0, len(texts), batch_size):
                if self.stop_requested:
                    break
                batch = texts[i:i + batch_size]
                tasks = [self.translate_async(text, target_lang, session) for text in batch]
                batch_results = await asyncio.gather(*tasks)
                results.extend(batch_results)
        return results

    def translate_worker(self, args):
        """멀티프로세싱 작업자 함수"""
        text, lang, model, ollama_url = args
        if text in self.translation_cache:
            return self.translation_cache[text]
        prompt = f"Translate from Korean to {lang}: '{text}'"
        payload = {"model": model, "prompt": prompt, "stream": False, "temperature": 0.0}
        try:
            response = requests.post(ollama_url, json=payload, timeout=30)
            response.raise_for_status()
            translated = self.clean_translation(response.json()["response"])
            self.cache_translation(text, lang, translated)
            return translated
        except:
            return text

    def stop_translation(self):
        """번역 작업 중지"""
        if self.is_running:
            self.stop_requested = True
            self.update_progress(self.progress['value'], self.progress['maximum'], 
                               "번역 중지 요청됨...")

    def validate_prerequisites(self):
        """필수 조건 검증"""
        if not self.file_path.get():
            messagebox.showerror("오류", "Excel 파일 선택 필요")
            return False
        model = self.selected_model.get()
        if not model or model in ["모델 없음", "API 오류", "연결 오류", "오류 발생", "타임아웃"]:
            messagebox.showerror("오류", "유효한 모델 선택 필요")
            return False
        try:
            response = requests.get("http://localhost:11434/api/tags", timeout=5)
            if response.status_code != 200:
                messagebox.showerror("오류", "Ollama 서버 응답 없음")
                return False
        except requests.exceptions.ConnectionError:
            messagebox.showerror("오류", "Ollama 서버 연결 실패")
            return False
        except requests.exceptions.Timeout:
            messagebox.showerror("오류", "Ollama 서버 응답 시간 초과")
            return False
        return True

    def translate_excel(self):
        """엑셀 파일 번역"""
        file_path = self.file_path.get()
        try:
            df = pd.read_excel(file_path, sheet_name="MessageSet")
            required_columns = ["KO"] + self.languages
            missing_columns = [col for col in required_columns if col not in df.columns]
            if missing_columns:
                messagebox.showerror("오류", f"누락된 열: {', '.join(missing_columns)}")
                self.is_running = False
                self.start_button.config(state="normal")
                self.stop_button.config(state="disabled")
                self.stop_requested = False
                return
            for lang in self.languages:
                df[lang] = df[lang].astype(str).replace("nan", "")
            korean_texts = df["KO"].dropna()
            total_texts = len(korean_texts)
            total_translations = total_texts * len(self.languages)
            self.progress['maximum'] = total_translations
            self.update_progress(0, total_translations, 
                               f"번역할 텍스트: {total_texts}, 총 번역: {total_translations}")

            translation_queue = []
            for idx, row in df.iterrows():
                korean_text = row["KO"]
                if pd.notna(korean_text) and str(korean_text).strip():
                    for lang in self.languages:
                        if not row[lang] or str(row[lang]).lower() == "nan" or not str(row[lang]).strip():
                            translation_queue.append((idx, korean_text, lang))

            progress_count = 0
            # 멀티프로세싱 풀 설정
            num_processes = min(cpu_count(), 4)  # CPU 코어 수 또는 최대 4
            with ProcessPoolExecutor(max_workers=num_processes) as executor:
                for idx, korean_text, lang in translation_queue:
                    if self.stop_requested:
                        self.update_progress(progress_count, total_translations, "번역 중지됨")
                        messagebox.showinfo("알림", "번역 중단. 처리된 내용 저장")
                        break
                    lang_name = self.language_names.get(lang, lang)
                    self.update_progress(progress_count, total_translations, 
                                       f"텍스트 {progress_count+1}/{len(translation_queue)} 번역 중... 언어: {lang_name}")
                    
                    # 비동기 배치 번역 호출
                    loop = asyncio.new_event_loop()
                    asyncio.set_event_loop(loop)
                    translated_texts = loop.run_until_complete(
                        self.translate_batch_async([korean_text], lang)
                    )
                    loop.close()
                    df.at[idx, lang] = translated_texts[0]
                    progress_count += 1

            base_name = os.path.splitext(file_path)[0]
            output_file = f"{base_name}_Translated.xlsx"
            counter = 1
            while os.path.exists(output_file):
                output_file = f"{base_name}_Translated_{counter}.xlsx"
                counter += 1
            df.to_excel(output_file, sheet_name="MessageSet", index=False)
            final_message = f"번역 {'중지' if self.stop_requested else '완료'}: {os.path.basename(output_file)}"
            self.update_progress(progress_count, total_translations, final_message)
            if messagebox.askyesno("성공", f"{final_message}\n폴더 열기?"):
                self.open_file_location(output_file)
            else:
                messagebox.showinfo("성공", final_message)
        except Exception as e:
            self.update_progress(self.progress['value'], self.progress['maximum'], f"오류: {str(e)}")
            messagebox.showerror("오류", f"오류 발생: {str(e)}")
        self.is_running = False
        self.stop_requested = False
        self.start_button.config(state="normal")
        self.stop_button.config(state="disabled")

    def open_file_location(self, file_path):
        """파일 폴더 열기"""
        try:
            folder_path = os.path.dirname(os.path.abspath(file_path))
            if sys.platform == "darwin":
                subprocess.Popen(["open", folder_path])
            elif sys.platform == "win32":
                os.startfile(folder_path)
            else:
                subprocess.Popen(["xdg-open", folder_path])
        except Exception as e:
            messagebox.showerror("오류", f"폴더 열기 실패: {str(e)}")

    def start_translation(self):
        """번역 시작"""
        if self.is_running:
            return
        if not self.validate_prerequisites():
            return
        self.is_running = True
        self.stop_requested = False
        self.start_button.config(state="disabled")
        self.stop_button.config(state="normal")
        self.progress['value'] = 0
        self.progress_text.set("0%")
        self.update_progress(0, 100, f"번역 시작... 모델: {self.selected_model.get()}")
        threading.Thread(target=self.translate_excel, daemon=True).start()

if __name__ == "__main__":
    root = tk.Tk()
    app = TranslationApp(root)
    root.mainloop()
EOF
fi

# PyInstaller로 앱 빌드
echo -e "\n${YELLOW}애플리케이션을 빌드합니다...${NC}"
python3 -m PyInstaller --name "Korean Translator" --windowed --onefile --icon=AppIcon.icns translator_app.py --add-data "AppIcon.icns:."

# 템플릿 생성 스크립트 추가
cat > create_template.py << 'EOF'
import pandas as pd
import os

def create_translation_template():
    """한국어 다국어 번역을 위한 엑셀 템플릿을 생성합니다."""
    
    # 샘플 데이터 생성
    data = {
        'Key': ['MSG_001', 'MSG_002', 'MSG_003', 'MSG_004', 'MSG_005'],
        'KO': ['환영합니다', '로그인하세요', '비밀번호를 잊으셨나요?', '회원가입', '저장'],
        'EN': ['', '', '', '', ''],
        'JA': ['', '', '', '', ''],
        'ZH_HANT': ['', '', '', '', ''],
        'TH': ['', '', '', '', ''],
        'ES': ['', '', '', '', '']
    }
    
    # DataFrame 생성
    df = pd.DataFrame(data)
    
    # 현재 사용자의 바탕화면 경로 가져오기
    desktop = os.path.join(os.path.expanduser('~'), 'Desktop')
    
    # 파일 저장
    template_path = os.path.join(desktop, 'Translation_Template.xlsx')
    df.to_excel(template_path, sheet_name='MessageSet', index=False)
    
    print(f"번역 템플릿이 생성되었습니다: {template_path}")
    return template_path

if __name__ == "__main__":
    create_translation_template()
EOF

# 빌드 결과 확인
if [ -f "dist/Korean Translator.app/Contents/MacOS/Korean Translator" ]; then
    echo -e "\n${GREEN}빌드 성공!${NC}"
    echo "애플리케이션이 dist 폴더에 생성되었습니다."
    
    # DMG 생성 (create-dmg가 설치된 경우)
    if command -v create-dmg &> /dev/null; then
        echo -e "\n${YELLOW}DMG 파일을 생성합니다...${NC}"
        create-dmg \
            --volname "Korean Translator" \
            --window-pos 200 120 \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "Korean Translator.app" 200 190 \
            --app-drop-link 400 190 \
            "Korean Translator.dmg" \
            "dist/Korean Translator.app"
        echo -e "${GREEN}DMG 파일 생성 완료!${NC}"
    else
        echo -e "\n${YELLOW}DMG 생성을 건너뜁니다 (create-dmg가 설치되어 있지 않음)${NC}"
        echo "DMG 생성을 원하시면 'brew install create-dmg'를 실행한 후 다시 시도하세요."
    fi
    
    # 템플릿 생성
    echo -e "\n${YELLOW}번역 템플릿을 생성합니다...${NC}"
    python3 create_template.py
    
    echo -e "\n${GREEN}설치가 완료되었습니다!${NC}"
    echo -e "애플리케이션을 실행하기 전에 Ollama가 설치되어 있어야 합니다."
    echo -e "Ollama 다운로드: https://ollama.ai/download"
else
    echo -e "\n${RED}빌드 실패!${NC}"
    echo "오류 로그를 확인하세요."
fi

# 정리
echo -e "\n${YELLOW}임시 파일을 정리합니다...${NC}"
rm -rf build
rm -rf AppIcon.iconset
rm -f *.spec
rm -f translator_app.py  # 생성된 소스 코드 정리 (test.py 유지)

echo -e "\n${GREEN}완료되었습니다.${NC}"