# Uninstall

1. Quit VibeCast from the menu bar.
2. Delete the app bundle, for example:

   ```bash
   rm -rf dist/VibeCast.app
   ```

3. Remove local configuration and pairing state:

   ```bash
   rm -rf "$HOME/Library/Application Support/VibeCast"
   defaults delete VibeCast 2>/dev/null || true
   ```

4. Remove Accessibility permission in System Settings.
5. Remove the login item if enabled.
6. Clear the VibeCast site data in Android Chrome or remove the home-screen shortcut.
