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
