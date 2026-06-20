# Límites de capacidad y buenas prácticas

VibeCast refleja texto producido por el teclado del teléfono hacia apps Mac seleccionadas.

- El botón de voz lo proporciona el teclado Android.
- La composición IME puede variar por teclado y versión de Android.
- El uso en primer plano del teléfono ofrece la conexión WebSocket más estable.
- Accesibilidad permite activar, enfocar, escribir y enviar.
- Electron, WebView y editores ricos deben validarse con el botón Test.

En Notion AI, `clipboard_replace` puede funcionar bien tras confirmar foco. En bloques de documento, usa conservar foco, insertar en cursor o solo sincronizar.
