# Uninstall

1. Menu bar से VibeCast quit करें।
2. App delete करें।

```bash
rm -rf dist/VibeCast.app
```

3. Configuration और pairing state हटाएं।

```bash
rm -rf "$HOME/Library/Application Support/VibeCast"
defaults delete VibeCast 2>/dev/null || true
```

4. System Settings से Accessibility permission हटाएं।
5. Login item remove करें।
6. Android Chrome site data या home-screen shortcut हटाएं।
