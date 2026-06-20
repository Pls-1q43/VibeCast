# 대상 앱 설정

VibeCast는 대상 프로필로 앱 활성화, 포커스, 쓰기, 전송을 제어합니다.

```text
~/Library/Application Support/VibeCast/targets.json
```

설정 페이지에서 앱을 활성화하고 Bundle ID를 연결합니다. 실행 중인 앱에서 선택하거나 직접 입력할 수 있습니다. 새 대상은 저장 후 반드시 테스트하세요.

중요 필드: `displayName`, `bundleId`, `focusMode`, `writeMode`, `allowSelectAllReplace`, `sendMode`, `maxTextLength`.

문서 페이지에서는 `allowSelectAllReplace=false`를 유지하고, 새 대상은 먼저 `sendMode=none`으로 쓰기 범위를 확인하는 것이 좋습니다.
