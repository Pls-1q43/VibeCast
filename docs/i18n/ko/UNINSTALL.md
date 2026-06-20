# 삭제

1. 메뉴 막대에서 VibeCast를 종료합니다.
2. 앱을 삭제합니다.

```bash
rm -rf dist/VibeCast.app
```

3. 설정과 페어링 상태를 삭제합니다.

```bash
rm -rf "$HOME/Library/Application Support/VibeCast"
defaults delete VibeCast 2>/dev/null || true
```

4. 시스템 설정에서 손쉬운 사용 권한을 제거합니다.
5. 로그인 항목을 제거합니다.
6. Android Chrome 사이트 데이터 또는 홈 화면 바로가기를 삭제합니다.
