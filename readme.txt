KoreanTranslator 사용 방법
============================

1. 설치
- KoreanTranslator.dmg 파일을 더블클릭해 엽니다.
- KoreanTranslator.app을 /Applications 폴더로 드래그합니다.

2. 앱 실행
- /Applications/KoreanTranslator.app을 더블클릭합니다.
- "출처를 알 수 없음" 경고가 나타나면:
  - 시스템 환경설정 > 보안 및 개인 정보 > 일반으로 이동.
  - "KoreanTranslator.app" 옆의 "그래도 열기" 버튼을 클릭.
  - 또는, 터미널에서 다음 명령어를 실행:
    ```
    xattr -cr /Applications/KoreanTranslator.app
    open /Applications/KoreanTranslator.app
    ```
- 앱이 처음 실행되면 Ollama와 gemma3:12b 모델을 자동 설치합니다. 인터넷 연결이 필요하며, 설치에 시간이 걸릴 수 있습니다 (약 7GB).

3. 사용 방법
- 앱을 실행하면 한국어 다국어 번역기가 열립니다.
- "찾아보기" 버튼으로 Excel 파일을 선택합니다.
- Excel 파일은 "MessageSet" 시트와 KO, EN, JA, ZH_HANT, TH, ES 열이 있어야 합니다.
- "번역 시작" 버튼을 클릭해 번역을 시작합니다.
- 번역된 파일은 원본 파일 이름에 "_Translated"가 추가된 이름으로 저장됩니다.

4. 문제 해결
- Ollama 설치가 실패하면 앱을 종료하고 다시 실행하세요.
- 앱이 실행되지 않으면 Gatekeeper 우회 과정을 다시 확인하세요.
- 추가 도움이 필요하면 [당신의 연락처]로 문의하세요.

============================