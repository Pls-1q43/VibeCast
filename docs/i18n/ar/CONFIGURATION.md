# إعداد التطبيقات الهدف

يستخدم VibeCast ملفات هدف للتحكم في التنشيط والتركيز والكتابة والإرسال.

```text
~/Library/Application Support/VibeCast/targets.json
```

فعّل التطبيقات في صفحة الإعداد، اختر Bundle ID من تطبيق عامل أو أدخله يدويًا، احفظ واختبر كل هدف.

الحقول المهمة: `displayName` و`bundleId` و`focusMode` و`writeMode` و`allowSelectAllReplace` و`sendMode` و`maxTextLength`.

لصفحات المستندات أبقِ `allowSelectAllReplace=false`. عند ضبط هدف جديد اختر `sendMode=none` أولًا لتأكيد نطاق الكتابة.
