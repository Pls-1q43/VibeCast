# Configuración de apps destino

VibeCast usa perfiles de destino para controlar activación, foco, escritura y envío.

```text
~/Library/Application Support/VibeCast/targets.json
```

Activa las apps que quieres ver en el teléfono, elige una app abierta para rellenar el Bundle ID o escríbelo manualmente, guarda y prueba cada destino.

Campos clave: `displayName`, `bundleId`, `focusMode`, `writeMode`, `allowSelectAllReplace`, `sendMode`, `maxTextLength`.

Para páginas de documentos, mantén `allowSelectAllReplace=false`. Para destinos nuevos, usa primero `sendMode=none` y confirma el alcance de escritura.
