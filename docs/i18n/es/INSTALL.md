# Instalación y uso

VibeCast se compone de una app de barra de menús para macOS y una página web para el teléfono servida por el Mac.

## Requisitos

macOS 13+, Xcode Command Line Tools con Swift 5.9+, Node.js 18+, Android Chrome, una red local alcanzable entre Mac y teléfono, y permiso de Accesibilidad en macOS.

## Compilar

```bash
cd web && npm install && cd ..
bash scripts/build_app.sh
open dist/VibeCast.app
```

Si npm se ve afectado por un preload local, usa `NODE_OPTIONS=""`.

## Primer uso

Inicia VibeCast, concede Accesibilidad, abre la página de configuración desde la barra de menús, activa destinos, vincula Bundle IDs y prueba la escritura. Copia la dirección con token y ábrela en Android Chrome.

## Uso diario

Toca una tarjeta de destino en el teléfono, usa el botón de voz del teclado Android, revisa el borrador y pulsa Enviar. VibeCast envía cuando la revisión final ya está reflejada en el Mac.
