# Reference player and Home Screen widget

The static-artwork build retains static covers; presentation and colour fades are UI animations.
The full player uses a full-screen viewport, a cropped 55%-height cover with 10% zoom, a
25% lower-edge dissolve, and a 40% upper dark gradient. There is no card border, corner mask,
horizontal inset or circular close button. Close with a downward gesture or **More → Close player**.

Title, artist/album, secondary controls, waveform, time badges, technical metadata and navigation
use approximate screen-height anchors of 60%, 63%, 67.5%, 79%, 86%, 89.5% and 94%. Text uses
bundled Avenir Next fonts and displays the stored metadata unchanged. The background derives a
muted hue from the cover; it is not hardcoded to the example's brown for unrelated albums.
Transport circle diameters are 11%, 15%, 18%, 15%, 11% of screen width, with minimum 44-point
hit targets. The outer triple-triangle controls still seek 10 seconds; the inner controls change
tracks. The reference waveform shows a real 60-second window, centred on the playhead, with
played/unplayed bars at 25%/70% opacity and 75% maximum amplitude height. Other seek-bar styles
retain their full-track timeline. No file bitrate, timestamp or battery values are fabricated.

## Audio output

The output badge reads AVAudioSession.currentRoute and sampleRate. When available its bit count
comes from the AVAudioEngine output node's PCM format. Thus `32/48K` describes the PCM supplied
to the session, **not** the Bluetooth codec, DAC resolution or original file bit depth. iOS does
not reliably expose the hardware output bit depth. Audio details remain available by tapping
the badge; file sample rate/bitrate/container remain on the separate technical line.

## Opening the player

`amp://player` opens the player. The optional `action` query accepts `toggle`, `previous` and
`next`; these wait for queue restoration on cold launch. Other schemes/hosts are ignored.
Returning from background with a loaded track also reveals the player. Now Playing metadata
includes the external content identifier and audio media type. Native iOS media-panel launching
is controlled by the OS and the installed application's signing/registration; verify this on a
physical device after installation. Tapping the status bar itself is an OS action, not a custom
app notification handler.

## Widget installation

The IPA embeds `ErhuPlayerWidget.appex`, a WidgetKit extension for small and medium Home Screen
widgets. It shows the current title, artist, artwork and play/pause state. The app publishes
snapshots only when these values change, rather than reloading the widget on every clock tick.
The medium widget's previous/play/next links **open the app** to control its actual player. They do not
pretend to control AVAudioEngine inside the widget extension. The small widget opens the player with a single tap.

Both targets declare the App Group `group.com.erhu.player`. A signing/provisioning setup must
allow that group for both the app and the widget extension. If your signing tool rewrites bundle
IDs or strips entitlements, it must preserve a matching App Group (or configure an owned group
consistently in `WidgetShared/PlayerWidgetSnapshot.swift` and both Support entitlement files).
A build without signing cannot validate those installation capabilities. Without shared-container
access the widget displays its empty state and its links still open the app; current-track data
requires a correctly provisioned group. After installation, add **amp Player** through the iOS
Home Screen widget gallery. Visibility and signed-extension installation require a device check.

Full simulator tests remain in the manual **iOS full validation** workflow. Its player lifecycle
check now uses the menu's close action, since the circular close button was intentionally removed.

## amp branding

The installed app is named **amp**. The Xcode product, bundle IDs, storage directories and App
Group identifiers retain their existing internal names so updating the app preserves its data.
Both `amp://player` and legacy `erhu://player` links work. The icon assets are opaque 1024px
light/dark images with the glass tile reframed to the canvas edges; iOS supplies the launcher
mask. This removes the old flat outside padding, rather than claiming unsupported transparent
wallpaper-visible regions in a legacy PNG app icon.
