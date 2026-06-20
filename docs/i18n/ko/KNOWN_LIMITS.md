# 능력 범위와 모범 사례

VibeCast는 폰 키보드가 만든 텍스트를 선택한 Mac 앱에 미러링합니다.

- 음성 버튼은 Android 키보드가 제공합니다.
- IME composition 동작은 키보드와 Android 버전에 따라 다를 수 있습니다.
- 폰을 전면에서 사용할 때 WebSocket이 가장 안정적입니다.
- 손쉬운 사용 권한은 활성화, 포커스, 쓰기, 전송의 기반입니다.
- Electron, WebView, 리치 에디터는 테스트 버튼으로 확인하세요.

Notion AI 입력창은 `clipboard_replace`가 잘 맞을 수 있습니다. 일반 문서 블록은 마지막 포커스 유지, 커서 삽입 또는 동기화만을 권장합니다.
