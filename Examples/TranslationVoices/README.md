# Translation voice sample

This iOS 15+ sample links the Apple Swift package and its KMP runtime. The hosted
room and native voice sheet use the same retained `MediaSFUIosHostBridge`. It
never creates a room automatically. Join an owned test room using a room-scoped
handoff from your backend; keep account and provider credentials on the server.

## Build

First build a fresh distribution using [KMP Binary Sync](../../KMP_BINARY_SYNC.md).
Set `MEDIA_SFU_APPLE_ARTIFACTS_DIR` to that directory when resolving the package
and building the sample. Configure `MEDIA_SFU_MEDIASOUP_PACKAGE_PATH` and enable
the real native binding as described in that guide. The package's `MediaSFUSDKBinary` target then links that
local XCFramework rather than the last published runtime.

Open `TranslationVoices.xcodeproj`, select the `TranslationVoices` scheme and an
Apple Silicon iOS simulator. Pass the same `MEDIA_SFU_APPLE_ARTIFACTS_DIR` as an
Xcode build setting for the resource-copy phase. Command-line example:

```sh
xcodebuild -project Examples/TranslationVoices/TranslationVoices.xcodeproj \
  -scheme TranslationVoices -destination 'generic/platform=iOS Simulator' \
  MEDIA_SFU_APPLE_ARTIFACTS_DIR="$MEDIA_SFU_APPLE_ARTIFACTS_DIR" \
  CODE_SIGNING_ALLOWED=NO build
```

The initial form displays whether the KMP runtime is linked. Enter the display
name and backend-provided room name, room token and media link, then join. Enable
spoken translation in the hosted translation settings before opening
**Translation voice**. Set an allowed output language, wait for the catalogue,
select a voice and apply it. The server still validates the settings. **Configured
voice** leaves basic preference and clone configuration in the hosted settings.

Use the room's exit control to leave and release its media. Simulator builds and
unit tests do not establish physical-device translated audio acceptance.

## Tests

Run the sample's UI tests on an installed simulator after configuring the two
package overrides above. The startup test verifies that the runtime loads and
that the native-media binding is active.

The optional `testLiveCatalogueInOwnedRoom` test requires these test-runner
environment values from an already authorized, owned room:

- `MEDIASFU_TEST_DISPLAY_NAME`
- `MEDIASFU_TEST_ROOM_NAME`
- `MEDIASFU_TEST_ROOM_TOKEN`
- `MEDIASFU_TEST_ROOM_LINK`

Configure them in your local Xcode test environment; do not commit their values.
The test enters the normal handoff form, loads the French stock catalogue,
selects a returned entry and checks output-language invalidation. It requests the
room's normal exit flow and terminates the app during cleanup. Follow your
fixture's server-side room cleanup rules too. This test skips when no handoff is
provided and does not claim translated audio playback or physical-device support.
