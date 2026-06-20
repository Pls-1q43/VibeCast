# 설치와 사용

VibeCast는 macOS 메뉴 막대 앱과 Mac이 호스팅하는 폰 웹 페이지로 구성됩니다.

## 요구 사항

macOS 13+, Xcode Command Line Tools와 Swift 5.9+, Node.js 18+, Android Chrome, Mac과 폰이 서로 접근 가능한 로컬 네트워크, macOS 손쉬운 사용 권한이 필요합니다.

## 빌드

```bash
cd web && npm install && cd ..
bash scripts/build_app.sh
open dist/VibeCast.app
```

npm preload 문제가 있으면 `NODE_OPTIONS=""`를 사용하세요.

## 첫 실행

VibeCast를 실행하고 손쉬운 사용 권한을 허용합니다. 메뉴 막대에서 설정 페이지를 열어 대상 앱을 활성화하고 Bundle ID를 연결한 뒤 테스트합니다. 토큰이 포함된 접속 주소를 복사해 Android Chrome에서 엽니다.

## 일상 사용

폰에서 대상 카드를 누르고 Android 키보드의 음성 입력을 사용합니다. 초안을 확인한 뒤 보내기를 누르면 최종 revision이 Mac에 반영된 후 전송됩니다.
