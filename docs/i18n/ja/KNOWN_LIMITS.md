# 能力範囲とベストプラクティス

VibeCast はスマホ入力法が生成したテキストを選択した Mac App にミラーリングします。

- 音声ボタンは Android キーボードが提供します。
- IME composition は入力法や Android バージョンで差があります。
- スマホを前面で使うと WebSocket が最も安定します。
- Accessibility 権限は起動、フォーカス、書き込み、送信の基盤です。
- Electron、WebView、リッチエディタはテストボタンで確認してください。

Notion AI 入力欄では `clipboard_replace` が有効なことがあります。通常の文書ブロックでは preserve-last-focus、カーソル挿入、同期のみを推奨します。
