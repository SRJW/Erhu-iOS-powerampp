# Building Erhu

Builds run on GitHub's macOS runners, so you can get an IPA without owning a Mac. The
[iOS workflow](../.github/workflows/ios.yml) generates the Xcode project, builds an unsigned IPA,
runs the simulator tests, and uploads **Erhu-ipa** and **Erhu-test-results**. Documentation-only
commits may skip CI.

CI defaults to Intel runners because GitHub's Apple Silicon pool currently reports capacity
failures. In **Actions → iOS → Run workflow**, choose `macos-15` to use Apple Silicon when
capacity is available; `macos-15-intel` selects Intel. Binary codec packages support both
simulator architectures. The device Release build and simulator tests run in parallel;
the simulator app and both test bundles are compiled once with `build-for-testing`. The full
`ErhuInteractionTests` suite and full `ErhuTests` suite then run with `test-without-building`,
on separate clean simulators. `ErhuTests` includes all artwork, transfer/library, audio and
transition regressions; they are not rerun as duplicate selections. Both suites must execute
at least one test and pass before the final job packages and uploads **Erhu-ipa**. Any skips
requested by an existing test are reported explicitly in the result counts.

Pinned Swift packages and compiler products are cached separately by runner architecture,
Xcode version, project configuration and source contents. Source changes still trigger a
build and every test run. Failed test runs retain logs, xcresult bundles and test counts in
**Erhu-test-results**; device compiler diagnostics are in **Erhu-build-logs**.

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
