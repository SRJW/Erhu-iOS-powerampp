# Building Erhu

The [iOS workflow](../.github/workflows/ios.yml) exports an **unsigned static-artwork IPA**
from `without-animated-art`. Download **Erhu-ipa** from a successful run; its ZIP contains
`Erhu.ipa`. This is a development build, not a release certified by the full test suite.

Each relevant app change runs one macOS job: resolve the pinned codecs, compile the iPhone
Release app, package it and upload the IPA immediately. It does not build a simulator app,
boot simulators or transfer an intermediate app to another runner. Test-only and documentation
changes do not rebuild the IPA. Manual runs must select `without-animated-art`; other branches
do not export. The build explicitly defines only `ERHU_STATIC_ART`, so the animated-artwork
condition `ERHU_ANIMATED_ART` is not enabled. No app functionality or artwork assets are removed.

Full validation remains available in **Actions → iOS full validation → Run workflow**.
It runs all `ErhuInteractionTests` and `ErhuTests`, including artwork, audio, library and transfer
regressions, and uploads **Erhu-test-results** with actual pass/fail/skip counts. These checks
remain necessary before claiming a fully tested release; their result does not block a
requested development IPA export. The separate beta publisher is unchanged.

Both workflows default to `macos-15-intel` because the Apple Silicon pool reported capacity
failures. Manual runs can choose `macos-15` when ARM capacity is available. Package and compiler
caches are separated by architecture, Xcode version, project and sources. Changes to test code
no longer invalidate the device build's exact cache key. Builds still run after cache restore;
results from a prior compilation are never treated as test results.

Measured before this split: roughly 15 minutes compiling simulator tests, 9 minutes executing
UI tests, 19 minutes executing unit tests, plus simulator startup and upload time. The device
build itself completed in about 6–8 minutes in observed runs. Export now depends only on that
device build and packaging; this is not a guaranteed duration because GitHub queue, cache and
runner performance vary. The bundled VYBE/Core ML model and the three pinned codec packages
remain part of the app and still need compilation/resolution when caches are cold.

For local development, use a Mac with a compatible Xcode and install XcodeGen:

```sh
git clone https://github.com/MeezaUni/Erhu-iOS.git
cd Erhu-iOS
git switch without-animated-art
brew install xcodegen
xcodegen generate
open Erhu.xcodeproj
```

Switch to `with-animated-art` before generating the project if you want motion-cover support.
For device builds, select your development team under **Signing & Capabilities**. Run the test
target from Xcode on an available iPhone simulator. The generated `.xcodeproj` is ignored;
project configuration lives in [project.yml](../project.yml).

Useful technical notes:

- [Android → iOS feature status](ANDROID_PORT.md)
- [Playback and transitions](ALBUM_ORDER_AND_TRANSITIONS.md)
- [Lyrics](LYRICS.md)
- [VYBE and model validation](VYBE.md)
- [Adding README screenshots](screenshots/README.md)

[Back to the main README](../README.md)
