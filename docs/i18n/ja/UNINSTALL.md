# アンインストール

1. メニューバーから VibeCast を終了します。
2. App を削除します。

```bash
rm -rf dist/VibeCast.app
```

3. 設定とペアリング状態を削除します。

```bash
rm -rf "$HOME/Library/Application Support/VibeCast"
defaults delete VibeCast 2>/dev/null || true
```

4. システム設定でアクセシビリティ権限を削除します。
5. ログイン項目を削除します。
6. Android Chrome のサイトデータまたはホーム画面ショートカットを削除します。
