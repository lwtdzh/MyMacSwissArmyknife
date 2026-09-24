# ClipyEnhanced

ClipyEnhanced is an unofficial continuation of [Clipy](https://github.com/Clipy/Clipy).

The original Clipy project has not been updated for a long time, so this inherited project keeps the same lightweight macOS clipboard-manager style while adding support for newer pasteboard use cases.

This is not an official Clipy release.

## Added Features

- Renamed the app to `ClipyEnhanced`.
- Captures more macOS pasteboard data types instead of only the original text-oriented clipboard content.
- Supports image clipboard items, including common formats such as PNG, JPG/JPEG, GIF, TIFF, BMP, HEIC, and WebP when macOS can read them.
- Shows image history entries with readable titles such as `JPG Image on 15:04:03`.
- Shows a thumbnail preview when hovering an image item in the recent paste menu.
- Stores unrecognized non-text pasteboard payloads as generic binary clipboard items.
- Shows unknown binary history entries with titles such as `Binary Data on 15:04:03`.
- Adds a per-folder `Show contents in menu` option for Snippets folders, so selected folders can display their snippets directly in the Snippets menu.
- Removes official-update checking because this is an unofficial build.
- Removes crash/error-reporting hooks and related preferences.

## Build

Requirements:

- macOS
- Xcode
- Ruby/Bundler
- CocoaPods

Build steps:

```sh
bundle install
bundle exec pod install
open Clipy.xcworkspace
```

Then build the `Clipy` scheme in Xcode.

The local command-line build used during development is:

```sh
xcodebuild -workspace Clipy.xcworkspace -scheme Clipy -configuration Debug -derivedDataPath build/DerivedData build
```

## License

This project inherits the original Clipy licensing. See [LICENSE](LICENSE) and [LICENSE_CLIPMENU](LICENSE_CLIPMENU).
