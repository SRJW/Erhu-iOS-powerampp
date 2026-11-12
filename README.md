<h1><img src="Erhu/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="amp" width="64"> amp</h1>

Tu música, en tu iPhone. **amp** es un reproductor de audio local para iOS 17 o posterior, con una biblioteca propia, un reproductor a pantalla completa y carátulas estáticas.

[Descargar amp · Releases](https://github.com/SRJW/Erhu-iOS-powerampp/releases) · [Compilaciones](https://github.com/SRJW/Erhu-iOS-powerampp/actions/workflows/ios.yml) · [Reportar un problema](https://github.com/SRJW/Erhu-iOS-powerampp/issues)

## Descargar e instalar

1. Abre **[Releases](https://github.com/SRJW/Erhu-iOS-powerampp/releases)** y elige la publicación más reciente de amp. Las compilaciones de desarrollo se identifican como *Pre-release*.
2. En **Assets**, descarga **`amp.ipa`** directamente. No necesitas abrir la página de artefactos de GitHub Actions.
3. Firma e instala la IPA con [SideStore](https://sidestore.io/) o [AltStore Classic](https://altstore.io/), usando tu cuenta de Apple.
4. Añade música con **+**, desde **Archivos → En mi iPhone → amp**, o mediante la transferencia por Wi-Fi.

Las IPAs publicadas son compilaciones de desarrollo **sin firma**; no se instalan directamente desde Safari. Con una cuenta gratuita de Apple normalmente debes renovar la firma cada siete días. Para conservar tu biblioteca al actualizar, instala la nueva versión sobre la anterior con la misma identidad de firma e identificador de aplicación.

Esta rama, **`without-animated-art`**, publica la versión con carátulas estáticas. Cada compilación correcta crea una publicación propia en Releases con su IPA y revisión de origen. La versión anterior recuperada también está disponible allí.

## Funciones

- Biblioteca de canciones, álbumes, artistas, favoritos y playlists, con pestañas reordenables.
- Reproductor con portada de borde a borde, mezcla de colores entre canciones, cambios de pista deslizando la portada, waveform y controles de reproducción.
- Cola, reproducción aleatoria, repetición, búsqueda dentro de la pista, marcadores y bucles A–B.
- Letras sincronizadas, archivos LRC y búsqueda de letras en línea.
- Ecualizador, visualizador y Transition Studio para configurar transiciones entre canciones.
- Edición y reparación de etiquetas, gestión de carátulas y transferencia de archivos por Wi-Fi.
- Temas claros y oscuros, minirreproductor de cristal e iconos de amp para ambas apariencias.
- Widget **amp Player** para la pantalla de inicio.
- Comprobación de actualizaciones desde las publicaciones de este repositorio.

MP3, AAC, ALAC, FLAC, WAV, AIFF, CAF y Ogg Vorbis/Opus, con contenedores compatibles como M4A, M4B y MP4. No reproduce archivos protegidos mediante DRM.

Smart Playlists se ha retirado. Las playlists creadas por el usuario se conservan.

## Eliminar canciones del teléfono

En el menú **…** de una canción o mediante una pulsación prolongada, elige **Delete from device** y confirma.

Esto borra permanentemente el archivo de la carpeta de amp visible en **Archivos**, elimina la canción de la biblioteca y las playlists y retira sus apariciones en la cola. **No se puede deshacer.** Si la canción tiene otra copia en una carpeta distinta, esa copia permanece. Quitar una canción de una playlist sigue siendo una acción independiente y conserva el archivo.

amp solo elimina archivos propios de su carpeta de música. Si iOS impide borrar un archivo, muestra el error y conserva su entrada en la biblioteca.

## Widget y controles de iOS

Añade **amp Player** desde la galería de widgets de iOS. El widget muestra la canción actual y permite abrir el reproductor; los enlaces de control abren amp para ejecutar la acción.

La instalación debe conservar la extensión y un App Group compartido correctamente provisionado. La aparición del widget y su acceso a los datos dependen de la firma utilizada. Más detalles: [reproductor y widget](docs/PLAYER_AND_WIDGET.md).

El indicador de salida del reproductor usa la ruta y frecuencia de la sesión de audio. La línea técnica del archivo muestra sus propios datos; no son la misma medición.

## Compilar y validar

El proyecto usa Swift, SwiftUI, AVFoundation y Core Audio. Se necesita un Mac con Xcode y [XcodeGen](https://github.com/yonaskolb/XcodeGen) para compilar iOS:

```sh
xcodegen generate
open Erhu.xcodeproj
```

El proyecto y los identificadores internos conservan el nombre `Erhu` para mantener la compatibilidad de datos. El nombre de la aplicación instalada es **amp**.

- **[iOS](.github/workflows/ios.yml)** comprueba el borrado real de archivos con casos de aislamiento, compila Release, verifica que la IPA incluya la extensión y publica `amp.ipa` en Releases. Reutiliza dependencias y productos compilados cuando la caché lo permite.
- **[iOS full validation](.github/workflows/ios-tests.yml)** ejecuta las pruebas completas unitarias, de regresión y de interacción en un simulador. Se inicia manualmente desde Actions; su resultado es independiente de la exportación de desarrollo.

Una exportación correcta no implica que se haya ejecutado la suite completa de simulador. Las notas de cada publicación indican las comprobaciones realizadas.

## Problemas y sugerencias

Abre un [issue](https://github.com/SRJW/Erhu-iOS-powerampp/issues) con el modelo de iPhone, versión de iOS, etiqueta de la publicación de amp y pasos para reproducir el problema. Para problemas de instalación, indica también la herramienta de firma.

## Créditos y licencia

amp continúa el proyecto de [Erhu para iOS de Mohammed Azeemulla Khan / Azeem](https://github.com/MeezaUni/Erhu-iOS), con antecedentes en [erhu para Android](https://github.com/lochanpthakke/erhu) de Lochan Thakke y Kshitij Kekunnaya.

El cambio de nombre no modifica las condiciones ni los avisos de los autores originales. Consulta [LICENSE](LICENSE), [licencias y permisos](docs/LICENSING-PERMISSIONS.md) y las licencias de componentes en [ThirdParty](ThirdParty/). Las versiones históricas cubiertas por GPL conservan sus condiciones correspondientes en [LICENSES](LICENSES/).
