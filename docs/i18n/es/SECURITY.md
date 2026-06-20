# Seguridad y privacidad

VibeCast trabaja con flujo local de texto. El reconocimiento de voz ocurre dentro del teclado Android; VibeCast recibe solo el texto escrito en la página.

- La web usa un `<textarea>` estándar.
- No pide permiso de micrófono.
- No recibe, transmite ni guarda audio.
- El Mac no envía texto del usuario a servicios externos.
- Los diagnósticos no guardan texto completo, tokens ni contenido del portapapeles.

El token de emparejamiento lo genera el Mac y va incluido en la URL. Al regenerarlo, las URLs antiguas dejan de funcionar. Antes de escribir, VibeCast valida destino, Bundle ID, proceso, sesión, revisión, frecuencia y tamaño.
