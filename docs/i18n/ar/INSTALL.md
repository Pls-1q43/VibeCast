# التثبيت والاستخدام

يتكون VibeCast من تطبيق شريط قوائم على macOS وصفحة ويب للهاتف يستضيفها Mac.

## المتطلبات

macOS 13+، وXcode Command Line Tools مع Swift 5.9+، وNode.js 18+، وAndroid Chrome، وشبكة محلية يمكن للهاتف وMac الوصول عبرها، وإذن تسهيلات استخدام macOS.

## البناء

```bash
cd web && npm install && cd ..
bash scripts/build_app.sh
open dist/VibeCast.app
```

إذا تأثر npm ببيئة preload محلية فاستخدم `NODE_OPTIONS=""`.

## أول تشغيل

شغّل VibeCast، امنح إذن تسهيلات الاستخدام، افتح صفحة الإعداد من شريط القوائم، فعّل الأهداف، اربط Bundle IDs واختبر الكتابة. انسخ عنوان الوصول مع الرمز وافتحه في Android Chrome.

## الاستخدام اليومي

اضغط بطاقة الهدف على الهاتف، استخدم زر الإملاء في لوحة مفاتيح Android، راجع المسودة واضغط إرسال. يرسل VibeCast بعد عكس آخر revision إلى Mac.
