# Navegación de amp

Plan confirmado: una barra compartida. La tira de canción aparece en las secciones y herramientas; en el reproductor completo aparecen únicamente los mismos cuatro botones. Se conserva la estética de amp.

## Cambios por etapas

| Etapa | Archivos principales | Prueba manual |
| --- | --- | --- |
| 0. Accesibilidad pendiente | `UI/SeekInteraction.swift` | Arrastrar el waveform en ambos modos y después usar play/pausa, siguiente y anterior. No cambian dibujo, gestos ni medidas. |
| 1. Formato y versión | `UI/LibraryItems.swift`, `Core/Settings/ReleaseChecker.swift`, `Features/Settings/SettingsView.swift`, `Support/Info.plist` | About muestra el tag de la compilación. Compararlo con el IPA instalado a través de FlareStore. ALAC y AAC conservan extensión y duración en la fila. |
| 2. Apariencia opcional | `Core/Settings/PlayerBackgroundSettings.swift`, `AppSettings.swift`, `SettingsView.swift`, `PlayerReferenceComponents.swift`, `ReferencePlayerBackdrop.swift` | Settings → Themes & Appearance → Player artwork & background. Cambiar fundido, detalles, desenfoque, intensidad y saturación. Restablecer devuelve el aspecto predeterminado; los ajustes sobreviven al reinicio. El desenfoque afecta a los detalles añadidos al fondo. |
| 3. Sesión y retirada de VYBE | `AppRouter.swift`, `AppServices.swift`, `ErhuApp.swift`, `AppSettings.swift`, `MixStore.swift`, `IntroductionView.swift`, `WidgetShared/PlayerLaunchRequest.swift`, `project.yml` | Minimizar desde álbum, búsqueda, Settings y reproductor y regresar: conservar la pantalla. Terminar la app y abrirla: raíz Library. Widget y enlaces explícitos al reproductor siguen funcionando. VYBE no tiene pantalla, opción, arranque ni modelo empaquetado. Radio conserva su motor por metadatos e historial. |
| 4. Barra y menú | `App/AppBottomBar.swift`, `RootView.swift`, `AppRouter.swift`, `MiniPlayer.swift`, alojamiento inferior de `NowPlayingView.swift` | Cambiar Library/EQ/Search sin pausar; Library siempre vuelve a raíz. La tira abre el reproductor y se oculta dentro. Menú abre encima de los botones; tocar fuera lo cierra. Abrir una herramienta y pulsar × recupera el contexto anterior. |
| 5. Categorías e índice | `LibraryPages.swift`, `LibraryCategory.swift`, `EntityCategoryView.swift`, `AllSongsView.swift`, `SongAlphabetNavigation.swift`, `PlayerSongReveal.swift`, `LibraryStore.swift`, `LibraryDatabase.swift` | Abrir todas las categorías; probar vacíos, subir a Library, ordenar y buscar. En Songs, arrastrar A–Z/# con orden alfabético, también con resultados filtrados. Seleccionar canciones, añadir a playlist y cancelar/confirmar borrado. |
| 6. Búsqueda | `SearchView.swift`, `LibrarySearch.swift`, `LibraryPages.swift` | Probar cada chip, limpiar texto, volver a una búsqueda reciente y abrir resultados. Reproducir/aleatorio usan las canciones del filtro; Select permite añadir o eliminar. Cambiar de sección conserva consulta y pila de resultados durante la sesión. |
| 7. Limpieza y regresiones | Retirada de `HomeView.swift` y controles de `LibraryBottomChrome.swift`; pruebas nativas; `LibraryScanner.swift` | Revisar ausencia de barras duplicadas, acceso a la última fila, reproducción continua, compartir archivo y tres puntos del reproductor. El escáner lee AAC/ALAC reales y repara el antiguo valor ambiguo durante el siguiente escaneo. |

## Dónde quedaron las funciones

- Home se integra en Library. Sus tracks están en All Songs; Featured Albums en Albums; los álbumes y playlists recientes en Recently Played; las emisoras en Radio. El aviso de actualización aparece en Library y permanece en About/Updates.
- Importar música: Library → ⋮ → Import music. Wi-Fi Transfer sigue en ese menú y en el menú inferior. Crear playlist: Playlists → ⋮ → New playlist.
- Ordenar y mostrar/ocultar categorías: Library → ⋮ → Customize Library. Arrastrar los controles de orden y usar los interruptores; Reset recupera el orden original y muestra todos los apartados. Se conservan los datos y la posición de los apartados ocultos. Si se ocultan todos, queda un acceso a Customize Library para recuperarlos. Ordenar canciones, filtros de fecha/género/mood e importar: ⋮ de la categoría.
- Tocar el título en el reproductor siempre abre All Songs sin filtros, desplaza la lista hasta la canción y la resalta brevemente. No cambia la reproducción. La línea de artista/álbum sigue abriendo su álbum, con la carpeta como respaldo si faltan metadatos.
- Sound Capsule, Equalizer, Auto Fix Tags, Artwork Fetcher, Wi-Fi Transfer y Settings permanecen en el menú inferior, una vez cada uno. Equalizer también es el segundo destino principal.
- Anterior y siguiente permanecen en el reproductor completo. La tira lleva play/pausa. Las funciones de compartir, revelar canción/álbum, cola, letras, marcas, visualizador, reparación de etiquetas y Transition Studio se conservan.
- No se guarda una ruta para restaurarla tras cerrar el proceso. Los enlaces `amp://player`, el widget y las userActivity explícitas conservan su destino. Un regreso normal desde segundo plano no se considera un toque de la tarjeta del Centro de control.
- Al vaciar Queue, el reproductor sin canción conserva sus cuatro botones. Para probarlo, elimina las entradas de Queue, pulsa Done y vuelve a Library: la tira debe mostrar su estado vacío.

## Validación

GitHub Actions compila y empaqueta el IPA en macOS. La comprobación nativa cubre los gestos del reproductor, compartir y navegación a canción/álbum, formatos reales AAC/ALAC, migración de ajustes, categorías, búsqueda y selección/borrado. La nueva prueba de interfaz recorre menú → Settings → ×, vuelve desde segundo plano y abre/cierra Sound Capsule sobre el reproductor.

En el iPhone aún hay que comprobar el comportamiento de la tarjeta del Centro de control y bloqueo con los logs `Documents/Diagnostics/lifecycle.log`; el simulador no reproduce el re-firmado de FlareStore. Que no haya logs de primer plano indicaría que iOS no está abriendo el proceso; no se fuerza navegación en todos los regresos para ocultar esa diferencia.

Entrega: `v0.1.0-amp.90`. IPA descargado y verificado: versión y build propios, modo de audio en segundo plano y ausencia del modelo de VYBE. Las tres pruebas nativas de cierre del reproductor, historial/selección/borrado y navegación/segundo plano pasaron en la revisión final. Durante la implementación también pasaron 30 pruebas de rutas, formatos y audio, y 26 de renderizado y animación; los dos modos de waveform y los controles de reproducción conservaron sus comprobaciones.
