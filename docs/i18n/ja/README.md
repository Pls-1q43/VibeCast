# VibeCast

スマホを macOS のリモート音声テキスト入力パネルに。Vibe Coding のために設計されています。

[中文](../../../README.md) · [English](../en/README.md) · [日本語](README.md) · [한국어](../ko/README.md) · [Español](../es/README.md) · [हिन्दी](../hi/README.md) · [العربية](../ar/README.md)

VibeCast はスマホの入力法で生成したテキストを、Codex、WorkBuddy、Notion、CodeBuddy、または任意の Mac アプリへリアルタイムに反映します。音声認識はスマホのキーボード側で行われ、VibeCast はテキストをローカルに、速く、確実に運びます。

## 主な特徴

- スマホのブラウザだけで使える入力パネル。
- Mac 対象アプリへのリアルタイムテキストミラーリング。
- 対象ごとの独立下書き。
- 最終同期を確認してから送信する 2 段階送信。
- Bundle ID、フォーカス、書き込み、送信方式を設定可能。
- マイク権限なし、音声処理なし、診断ログは脱敏。
- Product, design, code, marketing: All by Codex. Thanks to OpenAI.

## 連係マイクとの違い

iPhone/Mac の連係マイクと比べて、VibeCast は次の問題を解決します。

1. 連係マイクは接続が不安定になることがあります。
2. 連係マイク使用中は iPhone で他の操作ができません。
3. Mac 側の対象アプリを素早く切り替えられません。
4. 実質的に Mac 側の音声入力を先に起動する必要があり、手をキーボードから離しきれません。
5. 連係マイクは Android 端末に対応していません。

## クイックスタートガイド

1. Mac で VibeCast を起動すると、メニューバーに VibeCast アイコンが表示されます。
2. アクセス URL をコピーします。
3. 同じ Wi-Fi のスマホブラウザでその URL を開きます。
4. スマホページで Codex、Notion、または設定済みの任意の対象を選びます。
5. スマホのキーボードまたは音声入力を使うと、対応する Mac アプリにテキストがリアルタイムで表示されます。
6. 「送信」をタップすると、VibeCast が最終テキストの同期を確認してから対象アプリで送信します。

## ドキュメント

[インストール](INSTALL.md) · [設定](CONFIGURATION.md) · [アーキテクチャ](ARCHITECTURE.md) · [セキュリティ](SECURITY.md) · [トラブルシューティング](TROUBLESHOOTING.md) · [ベストプラクティス](KNOWN_LIMITS.md) · [アンインストール](UNINSTALL.md)

## License

MIT License で公開されています。
