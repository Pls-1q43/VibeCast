# インストールと使い方

VibeCast は macOS メニューバー App と、Mac が配信するスマホ用 Web ページで構成されます。

## 要件

- macOS 13 Ventura 以降
- Xcode Command Line Tools、Swift 5.9+
- Node.js 18+
- Android Chrome
- Mac とスマホが到達できるローカルネットワーク
- macOS アクセシビリティ権限

## ビルド

```bash
cd web && npm install && cd ..
bash scripts/build_app.sh
open dist/VibeCast.app
```

npm が preload 環境の影響を受ける場合は `NODE_OPTIONS=""` を付けて実行してください。

## 初回設定

1. `dist/VibeCast.app` を起動します。
2. システム設定でアクセシビリティ権限を付与します。
3. メニューバーから設定ページを開きます。
4. 対象 App を有効化し、Bundle ID を設定してテストします。
5. トークン付きアクセス URL をコピーし、Android Chrome で開きます。

## 日常利用

スマホで対象カードをタップし、Android キーボードの音声入力を使います。テキストを確認・編集して送信すると、VibeCast は最終 revision の同期後に対象 App へ送信します。
