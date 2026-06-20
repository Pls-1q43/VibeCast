# Security और Privacy

VibeCast local text flow पर केंद्रित है। Speech recognition Android keyboard के अंदर होता है; VibeCast को page में लिखा हुआ text मिलता है।

- Web page standard `<textarea>` इस्तेमाल करता है।
- Microphone permission नहीं मांगता।
- Audio receive, transmit या store नहीं करता।
- Mac user text external services को नहीं भेजता।
- Diagnostics full text, tokens या clipboard content record नहीं करते।

Pairing token Mac generate करता है और URL में शामिल होता है। Token regenerate करने पर पुराने URLs invalid हो जाते हैं। Writing से पहले target, Bundle ID, process, session, revision, rate और size validate होते हैं।
