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

## Waveform touch behaviour

The waveform follows the supplied Poweramp recording: time is fixed at the centre and bars
translate continuously underneath, with a vertical centre line visible only during scrubbing. Each bar represents a stable slice of the audio rather than
a screen column whose height is replaced on each tick. Playback renders at up to 30 fps, stopping
the animation clock while paused, scrubbing or moving the player.

Tap the visible waveform to seek to that time. Drag left to advance or right to rewind; the
position is anchored once per gesture, so playback does not move the target under the finger.
Elapsed time previews immediately, the transport controls fade out during a drag and return
on release/cancellation. A release commits one seek; cancellation leaves playback untouched.
Both ends clamp to the real track duration. Normal transport-button taps keep their existing
actions. The display retains a 60-second window (or the track duration for shorter songs).

Each queue entry has a separate waveform interaction identity. Changing tracks cancels the old
preview, contracts/fades its waveform and reveals the incoming one. Late waveform decoding and
old gesture callbacks cannot apply to a replacement entry. Reduced Motion uses a fade without
the contraction. File decoding remains cached; animation does not decode audio every frame.

The fast export runs standalone Swift checks against the production geometry. The manual
simulator suite additionally drags the real waveform in both directions and checks the next
track starts with its own time and responsive transport controls.

## Audio output

The output badge reads AVAudioSession.currentRoute and sampleRate. When available its bit count
comes from the AVAudioEngine output node's PCM format. Thus `32/48K` describes the PCM supplied
to the session, **not** the Bluetooth codec, DAC resolution or original file bit depth. iOS does
not reliably expose the hardware output bit depth. Audio details remain available by tapping
the badge; file sample rate/bitrate/container remain on the separate technical line.

## Opening the player

`amp://player` opens the player. The optional `action` query accepts `toggle`, `previous` and
`next`; these wait for queue restoration on cold launch. Other schemes/hosts are ignored.
Returning from inactive/background with a loaded track also reveals the player, as does a cold
launch after queue restoration. Pending widget commands wait for restoration and run once.
Now Playing metadata includes a per-track content identifier and audio media type. Native iOS media-panel launching
is controlled by the OS and the installed application's signing/registration; verify this on a
physical device after installation. Tapping the status bar itself is an OS action, not a custom
app notification handler.

## Widget installation

The IPA embeds `ErhuPlayerWidget.appex`, a WidgetKit extension for small and medium Home Screen
widgets. It shows the current title, artist, artwork and play/pause state. The app publishes
snapshots only when these values change, rather than reloading the widget on every clock tick.
The medium widget uses a dark card with a large cover on the left, current/recently played metadata
on the right and a single Play/Pause pill. A paused snapshot shows the recently played album when
available; a playing snapshot shows the current track. Play and Pause are explicit commands, so
a stale Play label cannot accidentally pause playback. These links **open the app** to control its
actual player. The small widget opens the player with a single tap.

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

## Signed installations and widget diagnostics

Both targets inspect their own embedded provisioning profile for a concrete amp App Group,
including names suffixed/prefixed by a signing tool such as FlareStore. `AmpWidgetAppGroup` in
each Info.plist also supports an explicitly configured group. No private container or arbitrary
unrelated App Group is used as a fallback. A signer must retain the extension and authorize the
same group for the app and widget; app code cannot grant a missing signing entitlement.

**Settings → About amp → Home Screen widget** shows the resolved group, last shared title and
write errors, with a refresh action. The widget shows a permissions diagnostic instead of a fake
empty player when it cannot access shared storage. Current metadata is republished on activation;
artwork is written under a unique filename before its metadata is committed to avoid mismatched
covers. Snapshot files remain accessible after first unlock when the app runs in the background.
WidgetKit controls the refresh schedule; reload requests do not guarantee an immediate OS redraw.

The native Control Center media panel is separate from the Home Screen widget. amp registers
remote control events and handles inactive → active and user-activity restoration. The OS still
controls whether a tap on its media panel launches the signed installation; verify that behaviour
on device with the installed signature. The external content identifier is a track ID, not an
invented launch-URL API.

## Control Center and scrub feedback

On iOS 18+, the widget extension also offers **Open amp** in the Control Center control gallery.
Add that control explicitly; it is separate from iOS's native Now Playing media panel. Its
foreground App Intent is included in both the app and extension, signals the player to open,
and waits for queue restoration. Opening this control does not require the widget App Group.
The native panel's own app-launch behaviour is still controlled by iOS and has not been verified
on the user's signed installation; adding this control does not claim to override that panel.

The transport buttons fade out over 0.30 s during scrubbing and return over 0.42 s. The thin
centre line fades in after the buttons have disappeared and fades out on release or
cancellation. It is hidden during ordinary playback. Reduced Motion skips these animations.

## Cover changes

The reference's track change slides the departing still cover sideways as the next cover enters
from the opposite edge, with a small scale/opacity adjustment and a coordinated colour fade.
The animation lasts 0.42 s; Previous reverses Next even when wrapping the queue. The cover keeps
its existing full-bleed crop, 10% zoom and lower-edge mask. It does not turn into a bordered card
or require downloaded animated artwork. Reduced Motion uses a short dissolve without travel.

The old image remains visible until the new image and its palette have loaded. A cancelled
request cannot display a late result for a skipped track. Rapid selections preserve the current
visual pair and replace one pending destination, so images do not snap halfway through a slide
or accumulate in an unbounded animation queue. Closing the player releases departing layers.
The fast export checks the production queue/geometry, including reversal and rapid skipping.

## Blended, interactive covers and amp navigation

Cover transitions now last 0.62 s with a true dissolve of both cover images and both artwork-colour
gradients. Drag the upper cover left/right to preview the adjacent track and its colour. Release
a deliberate swipe to change tracks; a short drag returns to the current cover. Gesture velocity
allows an intentional flick, queue boundaries resist dragging, and vertical pulls still close
the player. Neighbour covers are decoded asynchronously and the release continues from the
finger's progress rather than restarting the animation.

Smart Playlists, their Home banner, navigation page, hide/show actions and automatic rebuilds
have been removed. User-created playlists remain. The legacy playback-source case is retained
only so existing saved queues can still be restored; it opens Home instead of a removed page.
Radio generation remains on demand, using the shared track-analysis engine.

About amp uses the amp icon, installed release/build, current repository/Releases/issue links and
amp's feature information, while retaining original attribution. The unrelated Erhu donation
section is removed.

## Functional cover verification

The cover input now uses one SwiftUI drag recognizer with a locked horizontal/vertical intent.
The former UIKit pan overlay and competing full-screen dismissal recognizer are removed.
A cancelled gesture restores the cover; a committed horizontal gesture retains its progress
until the next artwork is ready. Cover and background layers expose an animatable blend phase
so their actual visible samples stay synchronized.

Release compilation and focused simulator verification run in parallel. Publishing depends on
both succeeding. Verification swipes two distinct audio files with embedded red/blue covers,
checks reverse navigation and vertical dismissal, renders the actual cover overlap, and samples
the production backdrop before, during and after a timed change. Screenshots and xcresults are
retained as workflow artifacts. Other tests remain in the full-validation workflow.
