# 対象 App 設定

VibeCast は対象プロファイルで App の起動、フォーカス、書き込み、送信を制御します。

設定ファイル:

```text
~/Library/Application Support/VibeCast/targets.json
```

## 手順

1. 設定ページを開く。
2. スマホに表示する App を有効化する。
3. 起動中 App から Bundle ID を選ぶか手入力する。
4. 必要ならカスタム App を追加する。
5. 保存して各対象をテストする。
6. 送信挙動が不明な場合は先に `sendMode=none` を選ぶ。

## 重要項目

`displayName` は表示名、`bundleId` は macOS App ID、`focusMode` はフォーカス方式、`writeMode` は書き込み方式、`allowSelectAllReplace` は全選択置換の許可、`sendMode` は送信方式です。

通常の文書ページでは `allowSelectAllReplace=false` を推奨します。
