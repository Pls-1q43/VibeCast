# Desinstalación

1. Sal de VibeCast desde la barra de menús.
2. Elimina la app.

```bash
rm -rf dist/VibeCast.app
```

3. Elimina configuración y emparejamiento.

```bash
rm -rf "$HOME/Library/Application Support/VibeCast"
defaults delete VibeCast 2>/dev/null || true
```

4. Quita el permiso de Accesibilidad.
5. Quita el elemento de inicio de sesión.
6. Borra los datos del sitio en Android Chrome o el acceso de pantalla de inicio.
