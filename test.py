import os
import sys
import logging
import subprocess
import requests
import tkinter as tk
from tkinter import messagebox, filedialog
import time
import traceback
import sqlite3
import pandas as pd
import json
import aiohttp
import asyncio
import re
import threading
from threading import local, Lock
import ttkbootstrap as ttk
from ttkbootstrap.constants import *

# 로그 설정
log_file = os.path.expanduser("~/KoreanTranslator.log")
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(log_file)
    ]
)
logger = logging.getLogger('TranslationApp')

# 즉시 로그 기록
logger.debug("앱 시작 시도")
logger.debug(f"파이썬 버전: {sys.version}")
logger.debug(f"작업 디렉토리: {os.getcwd()}")
logger.debug(f"sys.path: {sys.path}")
logger.debug(f"sys._MEIPASS: {getattr(sys, '_MEIPASS', '패키징되지 않음')}")

# 앱 번들 경로 설정
if getattr(sys, 'frozen', False):
    bundle_dir = sys._MEIPASS
    logger.debug(f'앱 번들 경로: {bundle_dir}')
else:
    bundle_dir = os.path.dirname(os.path.abspath(__file__))
    logger.debug(f'스크립트 경로: {bundle_dir}')

os.environ['PYTHONHASHSEED'] = '1'


class TranslationApp:
    def __init__(self, root):
        logger.debug("TranslationApp 초기화 시작")
        try:
            self.root = root
            self.root.title("한국어 다국어 번역기")
            self.root.geometry("700x450")
            self.root.minsize(650, 400)

            # 전역 폰트 설정
            default_font = ("Segoe UI", 13)
            self.root.option_add("*Font", default_font)

            # 전체 프레임
            main_frame = ttk.Frame(root, padding=20)
            main_frame.pack(fill=tk.BOTH, expand=True)

            # Variables
            self.file_path = tk.StringVar()
            self.is_running = False
            self.stop_requested = False
            self.ollama_status = tk.StringVar(value="확인 중...")
            self.selected_model = tk.StringVar(value="gemma3:12b")
            self.available_models = []
            self.translation_cache = {}
            self.languages = ["EN", "JA", "ZH_HANT", "TH", "ES"]
            self.language_names = {
                "EN": "English",
                "JA": "Japanese",
                "ZH_HANT": "Chinese Traditional",
                "TH": "Thai",
                "ES": "Spanish"
            }

            # 스레드별 SQLite 연결
            self.thread_local = local()
            self.lock = Lock()

            # 영구 캐시 초기화
            self.init_cache_db()

            # GUI Elements
            header_frame = ttk.Frame(main_frame)
            header_frame.pack(fill=tk.X, pady=10)

            ttk.Label(header_frame, text="한국어 다국어 번역기", font=("Segoe UI", 18, "bold")).pack(side=tk.LEFT)

            self.status_indicator = tk.Canvas(header_frame, width=15, height=15, bg="yellow")
            self.status_indicator.pack(side=tk.RIGHT, padx=5)

            ttk.Label(header_frame, textvariable=self.ollama_status).pack(side=tk.RIGHT)

            # 파일 선택
            file_frame = ttk.Frame(main_frame)
            file_frame.pack(fill=tk.X, pady=10)

            ttk.Label(file_frame, text="Excel 파일:").pack(side=tk.LEFT)
            ttk.Entry(file_frame, textvariable=self.file_path, width=40).pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
            self.browse_button = ttk.Button(file_frame, text="찾아보기", command=self.browse_file, width=8)
            self.browse_button.pack(side=tk.RIGHT)

            # 모델 선택
            model_frame = ttk.Frame(main_frame)
            model_frame.pack(fill=tk.X, pady=10)

            ttk.Label(model_frame, text="번역 모델:").pack(side=tk.LEFT)
            self.model_dropdown = ttk.Combobox(model_frame, textvariable=self.selected_model, state="readonly")
            self.model_dropdown.pack(side=tk.LEFT, padx=5, fill=tk.X, expand=True)
            self.model_dropdown.bind("<<ComboboxSelected>>", self.on_model_change)

            self.refresh_button = ttk.Button(model_frame, text="새로고침", command=self.refresh_models, width=8)
            self.refresh_button.pack(side=tk.RIGHT)

            # 진행률
            progress_frame = ttk.Frame(main_frame)
            progress_frame.pack(fill=tk.X, pady=10)

            self.progress = ttk.Progressbar(progress_frame, length=500, mode='determinate')
            self.progress.pack(fill=tk.X, pady=5)

            self.progress_text = tk.StringVar(value="0%")
            ttk.Label(progress_frame, textvariable=self.progress_text).pack()

            self.status_label = ttk.Label(main_frame, text="준비 완료", wraplength=500, anchor="w", justify=tk.LEFT)
            self.status_label.pack(fill=tk.X, pady=10)

            # 버튼 그룹
            button_frame = ttk.Frame(main_frame)
            button_frame.pack(fill=tk.X, pady=10)

            self.start_button = ttk.Button(button_frame, text="번역 시작", command=self.start_translation, width=12)
            self.start_button.pack(side=tk.LEFT, padx=5)

            self.stop_button = ttk.Button(button_frame, text="번역 중지", command=self.stop_translation, width=12, state=tk.DISABLED)
            self.stop_button.pack(side=tk.LEFT, padx=5)

            help_button = ttk.Button(button_frame, text="도움말", command=self.show_help, width=10)
            help_button.pack(side=tk.RIGHT, padx=5)

            check_button = ttk.Button(button_frame, text="Ollama 확인", command=self.check_ollama_status, width=12)
            check_button.pack(side=tk.RIGHT, padx=5)

            self.ollama_url = "http://localhost:11434/api/generate"

            self.root.protocol("WM_DELETE_WINDOW", self.on_closing)
            logger.debug("GUI 초기화 완료")

            self.check_ollama_status()

        except Exception as e:
            logger.error(f"초기화 오류: {str(e)}\n{traceback.format_exc()}")
            messagebox.showerror("초기화 오류", f"앱 초기화 실패: {str(e)}")
            sys.exit(1)

    def get_db_connection(self):
        """스레드별 SQLite 연결 반환"""
        if not hasattr(self.thread_local, 'conn'):
            db_path = os.path.expanduser("~/KoreanTranslator.db")
            logger.debug(f"데이터베이스 연결 시도: {db_path}")
            try:
                self.thread_local.conn = sqlite3.connect(db_path, check_same_thread=False)
                self.thread_local.conn.execute("PRAGMA journal_mode=WAL")
            except sqlite3.Error as e:
                logger.error(f"데이터베이스 연결 오류: {str(e)}\n{traceback.format_exc()}")
                raise
        return self.thread_local.conn

    def init_cache_db(self):
        """SQLite 영구 캐시 초기화"""
        logger.debug("init_cache_db 시작")
        try:
            conn = self.get_db_connection()
            with self.lock:
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS translations (
                        text TEXT,
                        lang TEXT,
                        translation TEXT,
                        PRIMARY KEY (text, lang)
                    )
                """)
                conn.commit()
                logger.debug("캐시 테이블 생성 완료")
        except sqlite3.Error as e:
            logger.error(f"init_cache_db 오류: {str(e)}\n{traceback.format_exc()}")
            raise

    def clear_caches(self):
        """Clear both in-memory and SQLite translation caches."""
        self.translation_cache.clear()
        conn = self.get_db_connection()
        with self.lock:
            conn.execute("DELETE FROM translations")
            conn.commit()
        self.status_label.config(text="캐시 초기화 완료")

    def on_closing(self):
        """Handle app closing by cleaning up resources."""
        if hasattr(self.thread_local, 'conn'):
            self.thread_local.conn.close()
        self.root.destroy()

    def get_cached_translation(self, text, target_lang):
        """캐시에서 번역 조회 (메모리 → SQLite)"""
        cache_key = f"{text}:{target_lang}"
        if cache_key in self.translation_cache:
            return self.translation_cache[cache_key]
        conn = self.get_db_connection()
        with self.lock:
            cursor = conn.execute("SELECT translation FROM translations WHERE text = ? AND lang = ?",
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
        conn = self.get_db_connection()
        with self.lock:
            conn.execute("INSERT OR REPLACE INTO translations (text, lang, translation) VALUES (?, ?, ?)",
                         (text, target_lang, translation))
            conn.commit()

    def update_progress(self, value, total, message):
        if not hasattr(self, '_last_update') or time.time() - self._last_update > 0.5:
            self._last_update = time.time()
            percentage = int((value / total) * 100) if total > 0 else 0
            self.root.after(0, lambda: self.progress.configure(value=value))
            self.root.after(0, lambda: self.progress_text.set(f"{percentage}%"))
            self.root.after(0, lambda: self.status_label.configure(text=message))

    def open_url(self, url):
        """브라우저에서 URL 열기"""
        try:
            if sys.platform == "darwin":  # macOS
                subprocess.Popen(["open", url])
            elif sys.platform == "win32":  # Windows
                import webbrowser
                webbrowser.open(url)
            else:  # Linux
                subprocess.Popen(["xdg-open", url])
        except Exception as e:
            self.status_label.config(text=f"URL 열기 오류: {str(e)}")
            messagebox.showerror("오류", f"URL 열기 오류: {str(e)}")

    def install_ollama(self):
        """Ollama를 설치하는 메서드"""
        try:
            self.status_label.config(text="Ollama 설치 안내 준비 중...")
            self.root.update()
            
            # 플랫폼 확인
            platform = sys.platform
            
            # 설치 안내 창
            install_window = tk.Toplevel(self.root)
            install_window.title("Ollama 설치 안내")
            install_window.geometry("600x450")
            install_window.grab_set()  # 모달 창으로 설정
            
            instruction_text = tk.Text(install_window, wrap=tk.WORD, width=70, height=20, padx=15, pady=15)
            instruction_text.pack(padx=20, pady=10, fill=tk.BOTH, expand=True)
            
            # 하이퍼링크 설정을 위한 태그 생성
            instruction_text.tag_configure("hyperlink", foreground="blue", underline=1)
            instruction_text.tag_bind("hyperlink", "<Button-1>", lambda e: self.open_url("https://ollama.com/download"))
            instruction_text.tag_bind("hyperlink", "<Enter>", lambda e: instruction_text.config(cursor="hand2"))
            instruction_text.tag_bind("hyperlink", "<Leave>", lambda e: instruction_text.config(cursor=""))
            
            if platform == "darwin":  # macOS
                instructions = """
                Ollama 설치 방법 (macOS):
                
                1. 브라우저에서 """
                
                # 지침 텍스트 삽입 및 하이퍼링크 적용
                instruction_text.insert(tk.END, instructions)
                instruction_text.insert(tk.END, "https://ollama.com/download", "hyperlink")
                instruction_text.insert(tk.END, """ 페이지를 방문하세요.
                2. macOS용 Ollama를 다운로드하고 설치하세요.
                3. 설치 후 Ollama 앱을 실행하세요.
                4. Ollama가 시스템 트레이에 표시되는지 확인하세요.
                5. 설치가 완료되면 이 창을 닫고 '확인' 버튼을 클릭하세요.
                
                [중요] 설치 후에도 오류가 계속 발생하면:
                - Ollama 앱이 실행 중인지 확인하세요.
                - 시스템을 재시작한 후 Ollama 앱을 먼저 실행하고 번역기를 시작하세요.
                """)
                
            elif platform == "win32":  # Windows
                instructions = """
                Ollama 설치 방법 (Windows):
                
                1. 브라우저에서 """
                
                instruction_text.insert(tk.END, instructions)
                instruction_text.insert(tk.END, "https://ollama.com/download", "hyperlink")
                instruction_text.insert(tk.END, """ 페이지를 방문하세요.
                2. Windows용 Ollama 설치 파일(.exe)을 다운로드하세요.
                3. 다운로드한 설치 파일을 실행하고 설치를 완료하세요.
                4. 설치 후 Windows 시작 메뉴에서 Ollama를 찾아 실행하세요.
                5. Ollama가 시스템 트레이에 표시되는지 확인하세요.
                6. 설치가 완료되면 이 창을 닫고 '확인' 버튼을 클릭하세요.
                
                [중요] 설치 후에도 오류가 계속 발생하면:
                - 컴퓨터를 재시작하세요.
                - Ollama를 먼저 실행한 후 번역기를 시작하세요.
                - Ollama가 시스템 트레이에 표시되어 있는지 확인하세요.
                """)
                
            else:  # Linux
                instructions = """
                Ollama 설치 방법 (Linux):
                
                1. 터미널을 열고 다음 명령어를 실행하세요:
                curl -fsSL https://ollama.com/install.sh | sh
                
                2. 설치 후 터미널에서 다음 명령으로 Ollama 서버를 시작하세요:
                ollama serve
                
                3. 별도의 터미널 창을 열어 다음 명령으로 모델을 다운로드하세요:
                ollama pull gemma3:12b
                
                4. 또는 """
                
                instruction_text.insert(tk.END, instructions)
                instruction_text.insert(tk.END, "https://ollama.com/download", "hyperlink")
                instruction_text.insert(tk.END, """ 페이지에서 대체 설치 방법을 확인하세요.
                
                5. 설치가 완료되면 이 창을 닫고 '확인' 버튼을 클릭하세요.
                
                [중요] 설치 후에도 오류가 계속 발생하면:
                - 터미널에서 'which ollama' 명령으로 설치 경로를 확인하세요.
                - 'sudo ln -s /설치경로/ollama /usr/local/bin/ollama' 명령으로 심볼릭 링크를 생성해보세요.
                - 번역기를 시작하기 전에 반드시 'ollama serve' 명령으로 서버를 먼저 실행하세요.
                """)
            
            instruction_text.config(state=tk.DISABLED)
            
            button_frame = tk.Frame(install_window)
            button_frame.pack(fill=tk.X, pady=10)
            
            check_button = ttk.Button(button_frame, text="확인", 
                                    command=lambda: [install_window.destroy(), self.check_ollama_status()])
            check_button.pack(side=tk.RIGHT, padx=20)
            
            self.status_label.config(text="Ollama 설치 안내 표시 중")
            return True
        except Exception as e:
            self.status_label.config(text=f"Ollama 설치 안내 오류: {str(e)}")
            messagebox.showerror("오류", f"Ollama 설치 안내 오류: {str(e)}")
            return False

    def wait_for_ollama_server(self):
        """Ollama 서버가 시작될 때까지 대기"""
        self.status_label.config(text="Ollama 서버 시작 대기 중...")
        # 서버 시작 대기
        for i in range(20):  # 최대 20초 대기
            try:
                response = requests.get("http://localhost:11434/api/tags", timeout=2)
                if response.status_code == 200:
                    self.status_label.config(text="Ollama 실행 중")
                    self.status_indicator.config(bg="green")
                    self.get_available_models()
                    return True
            except requests.exceptions.RequestException:
                time.sleep(1)
                continue
        
        # 서버 시작 실패
        self.status_label.config(text="Ollama 서버 시작 실패")
        messagebox.showinfo("안내", "Ollama 서버 시작에 실패했습니다. 수동으로 Ollama를 실행해주세요.")
        return False
    
    def get_available_models(self):
        try:
            response = requests.get("http://localhost:11434/api/tags", timeout=5)
            if response.status_code == 200:
                data = response.json()
                self.available_models = []
                
                # 데이터 타입에 따른 처리
                if isinstance(data, dict):
                    # 딕셔너리인 경우 models 또는 Tags 키 확인
                    if "models" in data and isinstance(data["models"], list):
                        models_list = data["models"]
                    elif "Tags" in data and isinstance(data["Tags"], list):
                        models_list = data["Tags"]
                    else:
                        # 적절한 키가 없으면 빈 리스트로 설정
                        models_list = []
                elif isinstance(data, list):
                    # 데이터가 직접 리스트인 경우
                    models_list = data
                else:
                    # 다른 타입의 경우 빈 리스트로 설정
                    models_list = []
                
                # 모델 이름 추출 (안전하게)
                for model in models_list:
                    if isinstance(model, dict):
                        # name 또는 Name 키 확인
                        name = None
                        if "name" in model and model["name"]:
                            name = model["name"]
                        elif "Name" in model and model["Name"]:
                            name = model["Name"]
                        
                        if name:
                            self.available_models.append(name)
                
                # 모델이 없으면 gemma3:12b 설치 시도
                if not self.available_models:
                    self.status_label.config(text="모델 없음. gemma3:12b 설치를 시작합니다...")
                    self.available_models = ["설치 중...(약 5분 정도 소요 됨)"]
                    self.model_dropdown['values'] = self.available_models
                    self.selected_model.set("설치 중...(약 5분 정도 소요 됨)")
                    
                    # 즉시 UI 업데이트
                    self.root.update_idletasks()
                    
                    # 설치 시작 (약간의 지연 후)
                    self.root.after(200, lambda: self.install_model("gemma3:12b"))
                    return
                
                # 모델 목록 정렬
                preferred_models = ['gemma3:12b', 'grok', 'mistral']
                sorted_models = sorted(self.available_models, 
                                    key=lambda x: (preferred_models.index(x) if x in preferred_models else len(preferred_models), x))
                self.available_models = sorted_models

                self.model_dropdown['values'] = self.available_models
                if 'gemma3:12b' in self.available_models:
                    self.selected_model.set('gemma3:12b')
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
            error_msg = str(e)
            logger.error(f"모델 목록 가져오기 오류: {error_msg}")
            self.status_label.config(text=f"모델 목록 가져오기 오류: {error_msg[:50]}...")
            self.available_models = ["오류 발생"]
            self.model_dropdown['values'] = self.available_models

    def install_model(self, model_name):
        """API를 사용하여 모델 설치 및 진행률 표시 (상세 정보 포함)"""
        logger.debug(f"install_model 시작: {model_name}")
        
        # 프로그레스 바 초기화
        self.progress['value'] = 0
        self.progress_text.set("0%")
        self.status_label.config(text=f"{model_name} 설치 준비 중...")
        self.root.update_idletasks()
        
        # 설치 스레드 실행
        def run_installation():
            try:
                # 진행 표시 업데이트 함수
                def update_progress(percent, message):
                    self.root.after(0, lambda: self.progress.configure(value=percent))
                    self.root.after(0, lambda: self.progress_text.set(f"{percent}%"))
                    self.root.after(0, lambda: self.status_label.configure(text=message))
                
                update_progress(1, f"{model_name} 다운로드 시작...")
                
                # API를 통한 모델 다운로드
                url = "http://localhost:11434/api/pull"
                headers = {"Content-Type": "application/json"}
                data = {"name": model_name}
                
                try:
                    # 스트리밍 요청
                    with requests.post(url, headers=headers, json=data, stream=True) as response:
                        if response.status_code != 200:
                            error_msg = f"API 오류: {response.status_code} - {response.text}"
                            logger.error(error_msg)
                            update_progress(0, error_msg)
                            self.root.after(0, lambda e=error_msg: messagebox.showerror("API 오류", e))
                            return
                        
                        start_time = time.time()
                        last_update_time = start_time
                        last_completed = 0
                        download_speeds = []  # 다운로드 속도 이동 평균을 위한 리스트
                        
                        for line in response.iter_lines():
                            if not line:
                                continue
                            
                            try:
                                status = json.loads(line.decode("utf-8"))
                                
                                # 진행률 계산
                                if "total" in status and "completed" in status and status["total"] > 0:
                                    total = status["total"]
                                    completed = status["completed"]
                                    progress_percent = min(99, int((completed / total) * 100))
                                    
                                    # 전체 용량 (MB 단위로 변환)
                                    total_mb = total / (1024 * 1024)
                                    completed_mb = completed / (1024 * 1024)
                                    remaining_mb = total_mb - completed_mb
                                    
                                    # 다운로드 속도 계산 (MB/s)
                                    current_time = time.time()
                                    time_diff = current_time - last_update_time
                                    
                                    if time_diff > 0.5:  # 0.5초마다 속도 업데이트
                                        bytes_diff = completed - last_completed
                                        speed_mbps = (bytes_diff / time_diff) / (1024 * 1024)
                                        
                                        # 이동 평균을 위해 최근 5개 속도 유지
                                        download_speeds.append(speed_mbps)
                                        if len(download_speeds) > 5:
                                            download_speeds.pop(0)
                                        
                                        # 평균 다운로드 속도
                                        avg_speed = sum(download_speeds) / len(download_speeds)
                                        
                                        # 남은 시간 계산 (분 단위)
                                        if avg_speed > 0:
                                            est_remaining_sec = remaining_mb / avg_speed
                                            est_remaining_min = est_remaining_sec / 60
                                        else:
                                            est_remaining_min = 5.0  # 기본값
                                        
                                        # 업데이트
                                        last_update_time = current_time
                                        last_completed = completed
                                        
                                        # 상태 메시지 형식화
                                        status_msg = (
                                            f"{model_name} 다운로드 중... {progress_percent}% "
                                            f"({completed_mb:.1f}MB/{total_mb:.1f}MB) "
                                            f"[{avg_speed:.1f}MB/s] "
                                            f"(약 {est_remaining_min:.1f}분 남음)"
                                        )
                                        
                                        update_progress(progress_percent, status_msg)
                                    
                                # 상태 메시지 처리
                                elif "status" in status:
                                    current_status = status["status"]
                                    if current_status == "success":
                                        update_progress(100, f"{model_name} 설치 완료!")
                                    elif "downloading" in current_status:
                                        if "progress" not in status:
                                            elapsed_min = (time.time() - start_time) / 60
                                            update_progress(
                                                10, 
                                                f"{model_name} 다운로드 준비 중... (경과 시간: {elapsed_min:.1f}분)"
                                            )
                                    elif "writing" in current_status:
                                        update_progress(95, f"{model_name} 설치 마무리 중...")
                                    elif "verifying" in current_status:
                                        update_progress(97, f"{model_name} 설치 확인 중...")
                                        
                            except json.JSONDecodeError as e:
                                logger.error(f"JSON 파싱 오류: {str(e)}, 라인: {line}")
                            
                            # UI 응답성 유지를 위한 업데이트
                            self.root.update_idletasks()
                        
                        # 완료 처리
                        update_progress(100, f"{model_name} 설치 완료!")
                        self.root.after(1000, self.refresh_models)
                        
                except requests.RequestException as e:
                    error_msg = f"API 요청 오류: {str(e)}"
                    logger.error(error_msg)
                    update_progress(0, error_msg)
                    self.root.after(0, lambda e=error_msg: messagebox.showerror("API 오류", e))
                    return
                    
            except Exception as e:
                error_msg = f"{model_name} 설치 오류: {str(e)}"
                logger.error(f"{error_msg}\n{traceback.format_exc()}")
                self.root.after(0, lambda: self.status_label.config(text=error_msg))
                self.root.after(0, lambda e=error_msg: messagebox.showerror("오류", e))
        
        # 설치 스레드 시작
        threading.Thread(target=run_installation, daemon=True).start()

    def refresh_models(self):
        self.status_label.config(text="모델 목록 새로고침 중...")
        self.clear_caches()
        self.available_models = []
        self.get_available_models()

    def check_ollama_status(self):
        """Ollama 서버 상태 확인"""
        logger.debug("check_ollama_status 메서드 시작")
        try:
            response = requests.get("http://localhost:11434/api/tags", timeout=5)
            if response.status_code == 200:
                self.ollama_status.set("Ollama 실행 중")
                self.status_indicator.config(bg="green")
                self.get_available_models()
            else:
                self.ollama_status.set("Ollama 응답 오류")
                self.status_indicator.config(bg="red")
                result = messagebox.askyesno("Ollama 오류", "Ollama 서버 응답에 문제가 있습니다. Ollama 실행을 시도하시겠습니까?")
                if result:
                    self.start_ollama()
        except requests.exceptions.ConnectionError:
            self.ollama_status.set("Ollama 실행 필요")
            self.status_indicator.config(bg="red")
            result = messagebox.askyesno("Ollama 설치/실행", 
                                      "Ollama 서버에 연결할 수 없습니다.\n\nOllama가 설치되어 있고 실행 중인지 확인하시겠습니까?")
            if result:
                self.start_ollama()
        except requests.exceptions.Timeout:
            self.ollama_status.set("Ollama 응답 시간 초과")
            self.status_indicator.config(bg="red")
            result = messagebox.askyesno("Ollama 오류", "Ollama 서버 응답 시간이 초과되었습니다. Ollama 실행을 시도하시겠습니까?")
            if result:
                self.start_ollama()
        except Exception as e:
            self.ollama_status.set(f"오류: {str(e)[:15]}...")
            self.status_indicator.config(bg="red")
            result = messagebox.askyesno("Ollama 오류", f"Ollama 확인 중 오류: {str(e)}\n\nOllama 설치/실행 안내를 보시겠습니까?")
            if result:
                self.install_ollama()

    def start_ollama(self):
        """Ollama 서버를 시작"""
        logger.debug("start_ollama 메서드 시작")
        try:
            platform = sys.platform
            
            # 먼저 Ollama 서버 실행 상태 확인 (설치 여부와 무관하게)
            try:
                response = requests.get("http://localhost:11434/api/tags", timeout=2)
                if response.status_code == 200:
                    # 이미 실행 중이면 상태 업데이트하고 종료
                    self.ollama_status.set("Ollama 실행 중")
                    self.status_indicator.config(bg="green")
                    self.get_available_models()
                    return
            except requests.exceptions.RequestException:
                # 실행 중이지 않음, 계속 진행
                pass
                
            if platform == "darwin":  # macOS
                # macOS에서는 애플리케이션 폴더 확인
                if os.path.exists("/Applications/Ollama.app"):
                    subprocess.Popen(["open", "-a", "Ollama"])
                    self.status_label.config(text="Ollama 앱 실행 중...")
                    # 서버 시작 대기
                    self.wait_for_ollama_server()
                else:
                    # 설치되지 않았으면 설치 안내
                    result = messagebox.askyesno("Ollama 설치", "Ollama가 설치되어 있지 않습니다. 설치 안내를 보시겠습니까?")
                    if result:
                        self.install_ollama()
                    return
                    
            elif platform == "win32":  # Windows
                # Windows에서 Ollama 실행 시도
                try:
                    # 일반적인 설치 경로 확인
                    program_files = os.environ.get("ProgramFiles", "C:\\Program Files")
                    ollama_paths = [
                        os.path.join(program_files, "Ollama", "ollama.exe"),
                        os.path.join(program_files, "Ollama", "bin", "ollama.exe"),
                        os.path.join(os.environ.get("LOCALAPPDATA", ""), "Ollama", "ollama.exe"),
                        os.path.join(os.environ.get("APPDATA", ""), "Ollama", "ollama.exe")
                    ]
                    
                    ollama_found = False
                    for path in ollama_paths:
                        if os.path.exists(path):
                            # 이 경로가 존재하면 실행 시도
                            subprocess.Popen([path, "serve"], creationflags=subprocess.CREATE_NO_WINDOW)
                            self.status_label.config(text="Ollama 서버 실행 중...")
                            ollama_found = True
                            # 서버 시작 대기
                            self.wait_for_ollama_server()
                            break
                            
                    if not ollama_found:
                        # 설치되지 않았으면 설치 안내
                        result = messagebox.askyesno("Ollama 설치", "Ollama가 설치되어 있지 않거나 경로를 찾을 수 없습니다. 설치 안내를 보시겠습니까?")
                        if result:
                            self.install_ollama()
                        return
                except Exception as e:
                    self.status_label.config(text=f"Ollama 실행 오류: {str(e)}")
                    result = messagebox.askyesno("Ollama 오류", f"Ollama 실행 중 오류: {str(e)}\n\n설치 안내를 보시겠습니까?")
                    if result:
                        self.install_ollama()
                    return
                    
            else:  # Linux
                # Linux에서는 바로 설치 안내로 이동
                result = messagebox.askyesno("Ollama 설치/실행", "Ollama를 설치하거나 실행하는 방법을 확인하시겠습니까?")
                if result:
                    self.install_ollama()
                return
                
        except Exception as e:
            self.status_label.config(text=f"Ollama 시작 오류: {str(e)}")
            result = messagebox.askyesno("오류", f"Ollama 시작 오류: {str(e)}\n\n설치 안내를 확인하시겠습니까?")
            if result:
                self.install_ollama()

    def show_help(self):
        help_window = tk.Toplevel(self.root)
        help_window.title("도움말")
        help_window.geometry("600x700")
        tk.Label(help_window, text="Korean Translator 도움말", font=("Segoe UI", 16, "bold")).pack(pady=10)
        
        text_widget = tk.Text(help_window, wrap=tk.WORD, width=70, height=30, padx=15, pady=15)
        text_widget.pack(padx=20, pady=10, fill=tk.BOTH, expand=True)
        
        # 하이퍼링크 태그 설정
        text_widget.tag_configure("hyperlink", foreground="blue", underline=1)
        text_widget.tag_bind("hyperlink", "<Button-1>", lambda e: self.open_url("https://ollama.com/download"))
        text_widget.tag_bind("hyperlink", "<Enter>", lambda e: text_widget.config(cursor="hand2"))
        text_widget.tag_bind("hyperlink", "<Leave>", lambda e: text_widget.config(cursor=""))
        
        # 도움말 텍스트 삽입 (하이퍼링크 포함)
        text_widget.insert(tk.END, """
        [사용 방법]
        1. 먼저 Ollama를 설치해야 합니다:
        - 'Ollama 확인' 버튼을 클릭하여 설치 여부를 확인하세요.
        - 설치되어 있지 않다면 안내에 따라 설치하세요.
        2. Ollama가 실행 중인지 확인하세요 (상태 표시기가 녹색이면 실행 중).
        3. 드롭다운에서 모델 선택 (권장: gemma3:12b 또는 llama3.2/mistral).
        4. '찾아보기'로 Excel 파일 선택.
        5. '번역 시작' 클릭.
        6. 중지하려면 '번역 중지' 클릭.

        [Ollama 설치 방법]
        - macOS, Windows: """)
        
        text_widget.insert(tk.END, "https://ollama.com/download", "hyperlink")
        
        text_widget.insert(tk.END, """ 에서 설치 파일 다운로드
        - Linux: 터미널에서 'curl -fsSL https://ollama.com/install.sh | sh' 실행

        [엑셀 파일 형식]
        - "MessageSet" 시트 필요.
        - 열: KO, EN, JA, ZH_HANT, TH, ES
        - KO 열에 한국어 입력, 나머지 비어 있으면 번역.

        [모델 추가]
        - 터미널에서 'ollama pull gemma3:12b' 등 실행.
        - 모델이 하나도 없으면 gemma3:12b 자동 설치 시도.
        - 추가/변경 후 '새로고침' 클릭.
        - 모델 변경 시 이전 번역 캐시 자동 삭제.

        [문제 해결]
        - '확인 중...' 지속 시 Ollama 설치 확인.
        - 모델 목록 없으면 '새로고침' 클릭.
        - 오류 시 '번역 중지' 후 재시도.
        """)
        
        text_widget.config(state=tk.DISABLED)
        
        # 닫기 버튼
        close_button = ttk.Button(help_window, text="닫기", command=help_window.destroy)
        close_button.pack(pady=10)

    def browse_file(self):
        file = filedialog.askopenfilename(filetypes=[("Excel 파일", "*.xlsx")])
        if file:
            self.file_path.set(file)
            self.status_label.config(text=f"선택된 파일: {os.path.basename(file)}")

    def create_prompt(self, korean_text, target_lang):
        """번역 프롬프트 생성"""
        return f"""Translate this Korean text to {self.language_names.get(target_lang, target_lang)}: '{korean_text}'.
Give ONLY the direct translation without ANY explanations or notes. 
Do NOT include the original Korean text or pronunciation.
Do NOT say 'translation:', 'in English:', etc.
Just give the translated word or phrase and nothing else."""

    def clean_translation(self, text):
        """번역 결과 텍스트 정리"""
        text = re.sub(r'\n', ' ', text)
        text = re.sub(r'^[\s\'\""`]*', '', text)
        text = re.sub(r'[\s\'\""`]*$', '', text)
        prefixes = [
            r'번역\s*:', r'번역은\s*:', r'translation\s*:', r'translated text\s*:',
            r'is\s*:', r'in \w+\s*:', r'the translation is\s*:',
            r'translation of the text\s*:', r'here is the \w+ translation\s*:',
            r'in \w+, this would be\s*:', r'translated to \w+\s*:',
            r'the \w+ word for this is\s*:'
        ]
        pattern = '|'.join(prefixes)
        text = re.sub(fr'(?i)^(.*?({pattern}))', '', text)
        text = re.sub(r'\s*\([^)]*\)', '', text)
        text = re.sub(r'\s*\[[^\]]*\]', '', text)
        text = re.sub(r'\s*"[^"]*"', '', text)
        text = re.sub(r'(?i)^(here\'s|here is|this is|that is).*?:', '', text)
        text = re.sub(r'[\*\`\#\-]', '', text)
        if '/' in text:
            text = text.split('/')[0]
        text = re.sub(r'[.!?]$', '', text)
        if len(text.split(',')) > 1:
            text = text.split(',')[0]
        text = re.sub(r'\s+', ' ', text).strip()
        return text

    async def translate_async(self, text, target_lang, session, max_retries=3):
        if self.stop_requested:
            return text
        cached = self.get_cached_translation(text, target_lang)
        if cached:
            return cached
        model = self.selected_model.get()
        if not model or model in ["모델 없음", "API 오류", "연결 오류", "오류 발생", "타임아웃", "설치 중..."]:
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

    def stop_translation(self):
        if self.is_running:
            self.stop_requested = True
            self.update_progress(self.progress['value'], self.progress['maximum'], 
                               "번역 중지 요청됨...")

    def validate_prerequisites(self):
        if not self.file_path.get():
            messagebox.showerror("오류", "Excel 파일 선택 필요")
            return False
        model = self.selected_model.get()
        if not model or model in ["모델 없음", "API 오류", "연결 오류", "오류 발생", "타임아웃", "설치 중..."]:
            messagebox.showerror("오류", "유효한 모델 선택 필요 (설치 완료 대기)")
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
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                for idx, korean_text, lang in translation_queue:
                    if self.stop_requested:
                        self.update_progress(progress_count, total_translations, "번역 중지됨")
                        messagebox.showinfo("알림", "번역 중단. 처리된 내용 저장")
                        break
                    lang_name = self.language_names.get(lang, lang)
                    self.update_progress(progress_count, total_translations, 
                                       f"텍스트 {progress_count+1}/{len(translation_queue)} 번역 중... 언어: {lang_name}")
                    
                    translated_texts = loop.run_until_complete(
                        self.translate_batch_async([korean_text], lang)
                    )
                    df.at[idx, lang] = translated_texts[0]
                    progress_count += 1
            finally:
                loop.close()

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

    def on_model_change(self, event):
        self.clear_caches()
        self.status_label.config(text=f"모델 변경: {self.selected_model.get()}")

if __name__ == "__main__":
    logger.debug("메인 실행 시작")
    try:
        root = ttk.Window(themename="lumen")
        logger.debug("tkinter 루트 창 생성")
        
        # macOS에서 앱 아이콘 설정
        try:
            # macOS에서는 NSApplication 사용
            if sys.platform == "darwin":
                try:
                    # PyObjC 라이브러리 사용 시도
                    import objc
                    from AppKit import NSImage, NSApplication
                    
                    icon_path = os.path.join(bundle_dir, 'app_icon.icns')
                    if os.path.exists(icon_path):
                        image = NSImage.alloc().initWithContentsOfFile_(icon_path)
                        NSApplication.sharedApplication().setApplicationIconImage_(image)
                        logger.debug(f"NSApplication 아이콘 설정 시도: {icon_path}")
                except ImportError:
                    # PyObjC가 없으면 기본 방법 사용
                    icon_path = os.path.join(bundle_dir, 'app_icon.png')
                    if os.path.exists(icon_path):
                        img = tk.PhotoImage(file=icon_path)
                        root.iconphoto(True, img)
                        logger.debug(f"PNG 아이콘으로 대체: {icon_path}")
            # 다른 플랫폼에서는 PNG 사용
            else:
                icon_path = os.path.join(bundle_dir, 'app_icon.png')
                if os.path.exists(icon_path):
                    img = tk.PhotoImage(file=icon_path)
                    root.iconphoto(True, img)
                    logger.debug(f"아이콘 설정 시도: {icon_path}")
        except Exception as e:
            logger.error(f"아이콘 설정 오류: {str(e)}")
        
        app = TranslationApp(root)
        logger.debug("TranslationApp 인스턴스 생성")
        root.mainloop()
        logger.debug("메인 루프 종료")
    except Exception as e:
        logger.error(f"메인 실행 오류: {str(e)}\n{traceback.format_exc()}")
        try:
            messagebox.showerror("실행 오류", f"앱 실행 실패: {str(e)}")
        except:
            pass
        sys.exit(1)
