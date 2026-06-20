# إزالة التثبيت

1. أنهِ VibeCast من شريط القوائم.
2. احذف التطبيق.

```bash
rm -rf dist/VibeCast.app
```

3. احذف الإعداد وحالة الاقتران.

```bash
rm -rf "$HOME/Library/Application Support/VibeCast"
defaults delete VibeCast 2>/dev/null || true
```

4. أزل إذن Accessibility من System Settings.
5. أزل عنصر التشغيل عند الدخول.
6. احذف بيانات الموقع في Android Chrome أو اختصار الشاشة الرئيسية.
