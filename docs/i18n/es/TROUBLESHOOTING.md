# Solución de problemas

## El teléfono no abre la página

Comprueba que Mac y teléfono estén en una red alcanzable, que VibeCast esté activo y que uses una dirección reciente con token.

## La página no conecta

Verifica que la URL tenga `token=...`. Si regeneraste el token, abre la nueva dirección.

## Accesibilidad no autorizada

Activa VibeCast en Ajustes del Sistema → Privacidad y seguridad → Accesibilidad. Si ya aparece activo, apágalo y enciéndelo, y reinicia VibeCast.

## Falla foco o sincronización

Pulsa Reenfocar, vuelve a probar el destino en configuración y considera `clipboard_replace` para Electron/WebView. Mantén `allowSelectAllReplace=false` hasta confirmar el alcance.

## Falla el envío

Espera a que el estado sea Sincronizado y confirma que `sendShortcut` coincida con la app destino.
