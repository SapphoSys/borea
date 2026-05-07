# Borea
🌌 Swift app for macOS to control WH-1000XM4 headsets.

## Build
For development:
```sh
swift run Borea
```

To build an `.app` bundle:
```sh
./Scripts/build-app.sh
open .build/Borea.app
```

## Debugging
Run Borea with the `BOREA_DEBUG=1` flag to receive debug logs.

```sh
BOREA_DEBUG=1 .build/Borea.app/Contents/MacOS/Borea
```

## License
Borea is licensed under the zlib License.

## References
- https://github.com/Plutoberth/SonyHeadphonesClient
- https://helpguide.sony.net/mdr/wh1000xm4/v1/en/contents/TP0002752772.html
- https://www.sony.com/electronics/support/wireless-headphones-bluetooth-headphones/wh-1000xm4/specifications
