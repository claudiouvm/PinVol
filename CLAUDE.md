# PinVol — convenciones del proyecto

- **Descripciones en GitHub: primero en inglés y después en español.** Vale para PRs, releases e issues
  (secciones `## English` y `## Español`). El código, los comentarios y los mensajes de commit van en español.
- **Portada del repo**: `README.md` (inglés) y `README.es.md` (español) son cortos y van en espejo, con un selector de idioma
  arriba. Los detalles técnicos están en `docs/DEVELOPMENT.md` y `docs/DESARROLLO.md`, también en espejo.
  Si cambias uno, cambia el otro.
- **Merge directo a `main`** cuando el CI esté en verde; no hace falta pedir confirmación.
- **Versión**: se define en `Info.plist` (`CFBundleShortVersionString`). Al subirla, actualiza también
  `RELEASE_NOTES.md` (inglés y después español; el CI exige que su primera línea nombre la versión). El workflow
  `Release` publica `v<versión>` con esas notas y deja `dist/PinVol.dmg` al día.
- **Solo Apple Silicon (arm64)** y **macOS 26 (Tahoe) o posterior**. No se genera binario x86_64; `build.sh` y `tools/make-dmg.sh` lo exigen.
- **Licencia**: MIT (`LICENSE`, © Claudiouvm); el botón «license» de los README la nombra.
- La app no se notariza (decisión del dueño): va firmada ad-hoc.
- No se puede compilar Swift/AppKit en Linux; el CI de macOS (`.github/workflows/release.yml`) es la compilación real.
  Sus capturas (artefacto `capturas`, a 2x) sirven para revisar el diseño. Las de la portada (`docs/apps-*.png`) salen del
  workflow `Screenshots`, que instala Spotify, IINA y TIDAL para que aparezcan con su ícono real.
