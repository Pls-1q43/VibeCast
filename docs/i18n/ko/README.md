# VibeCast

폰을 macOS 원격 음성 텍스트 입력 패널로 바꾸세요. Vibe Coding을 위해 설계되었습니다.

[中文](../../../README.md) · [English](../en/README.md) · [日本語](../ja/README.md) · [한국어](README.md) · [Español](../es/README.md) · [हिन्दी](../hi/README.md) · [العربية](../ar/README.md)

VibeCast는 폰 키보드가 만든 텍스트를 Codex, WorkBuddy, Notion, CodeBuddy 또는 사용자 지정 Mac 앱에 실시간으로 미러링합니다. 음성 인식은 폰 키보드에서 처리되고, VibeCast는 텍스트를 빠르고 로컬 중심으로 전달합니다.

## 핵심

- 폰 브라우저 기반 입력 패널.
- Mac 대상 앱으로 실시간 텍스트 미러링.
- 대상별 독립 초안.
- 최종 동기화 확인 후 보내는 2단계 전송.
- Bundle ID, 포커스, 쓰기, 전송 방식 설정.
- 마이크 권한 없음, 오디오 처리 없음, 민감정보 제거 로그.
- Product, design, code, marketing: All by Codex. Thanks to OpenAI.

## 연속성 마이크와 비교

iPhone/Mac 연속성 마이크와 비교해 VibeCast는 다음 문제를 해결합니다.

1. 연속성 마이크 연결은 불안정할 수 있습니다.
2. 연속성 마이크가 활성화된 동안 iPhone에서 다른 작업을 하기 어렵습니다.
3. Mac의 대상 앱을 빠르게 전환할 수 없습니다.
4. 먼저 Mac 쪽 음성 입력을 켜야 하므로 손을 키보드에서 완전히 떼기 어렵습니다.
5. 연속성 마이크는 Android 폰을 지원하지 않습니다.

## 빠른 시작 가이드

1. Mac에서 VibeCast를 시작하면 메뉴 막대에 VibeCast 아이콘이 나타납니다.
2. 접속 주소 복사를 선택합니다.
3. 같은 Wi-Fi의 폰 브라우저에서 해당 주소를 엽니다.
4. 폰 페이지에서 Codex, Notion 또는 설정된 대상을 선택합니다.
5. 폰 키보드나 음성 입력을 사용하면 텍스트가 해당 Mac 앱에 실시간으로 표시됩니다.
6. 보내기를 누르면 VibeCast가 최종 텍스트 동기화를 확인한 뒤 대상 앱에서 전송합니다.

## 문서

[설치](INSTALL.md) · [설정](CONFIGURATION.md) · [아키텍처](ARCHITECTURE.md) · [보안](SECURITY.md) · [문제 해결](TROUBLESHOOTING.md) · [모범 사례](KNOWN_LIMITS.md) · [삭제](UNINSTALL.md)

## License

MIT License로 배포됩니다.
