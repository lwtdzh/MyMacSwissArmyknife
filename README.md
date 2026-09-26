# MyMacSwissArmyknife

MyMacSwissArmyknife is a native macOS host that collects several small system
utilities behind one menu-bar icon and one settings window.

## Modules

- **ScrollReverser**, adapted from
  [pilotmoon/scroll-reverser](https://github.com/pilotmoon/scroll-reverser).
  It reverses mouse and trackpad scrolling independently.
- **ResourceMonitor**, adapted from
  [lwtdzh/NetSpeedMonitor](https://github.com/lwtdzh/NetSpeedMonitor).
  It displays network, disk, CPU, and memory activity in the menu bar or a
  floating panel.
- **RightClickMenu**, a configurable Finder extension with Open With, New
  Files, and Open Terminal Here commands.
- **ClipyEnhanced**, integrated from
  [lwtdzh/clipy-enhanced](https://github.com/lwtdzh/clipy-enhanced). It provides
  clipboard history, snippets, format-specific paste choices, previews, and
  global keyboard shortcuts.
- **AppBlocker**, which immediately terminates applications selected in its
  block list.

The host owns module enablement, login startup, settings, health reporting, and
the main status menu. Enabling a module adds a checkmark to its menu item.

ClipyEnhanced keeps its clipboard database, monitoring, paste behavior,
snippets, and hotkeys in a bundled helper. When it is enabled, moving the
pointer over its checked first-level item opens its clipboard menu as a native
submenu. Disabling it stops the helper and removes that submenu. The
standalone ClipyEnhanced status icon, Preferences item, login setting, and Quit
item are omitted because the host now owns those functions.

## Settings

The settings window has one tab per module:

- ScrollReverser: direction, device selection, scroll step size, and permission
  setup.
- ResourceMonitor: presentation mode, visible metrics, units, and refresh
  interval.
- RightClickMenu: Open With applications, New Files templates, Finder
  extension management, and Open Terminal Here.
- ClipyEnhanced: clipboard limits and behavior, stored data types, menu
  presentation, excluded applications, modifier actions, screenshots, and
  keyboard shortcuts.
- AppBlocker: blocked applications and module startup behavior.

ClipyEnhanced retains its Main Menu, History, Snippets, Clear History, and
per-snippet-folder shortcuts. The host settings tab edits the four global
shortcuts. The existing snippet editor remains available for folder contents,
import/export, enablement, ordering, and folder-specific shortcuts.

## Build

Requirements:

- macOS 13.5 or later
- Xcode
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
xcodegen generate --spec Upstream/ResourceMonitor/project.yml \
  --project Upstream/ResourceMonitor
xcodegen generate
xcodebuild \
  -project MyMacSwissArmyknife.xcodeproj \
  -scheme MyMacSwissArmyknife \
  -destination "platform=macOS" \
  test
```

The host build phase compiles and embeds ResourceMonitor and ClipyEnhanced in
`MyMacSwissArmyknife.app/Contents/Helpers`. Both helpers are built as universal
`arm64`/`x86_64` applications. ScrollReverser's event-tap logic is compiled
directly into the host.

RightClickMenu is embedded as a Finder Sync extension. Its Open With
applications and New Files templates can be added or removed from the host
settings. The built-in templates create extensionless, TXT, DOCX, XLSX, PPTX,
and Markdown files.

Run the complete Debug/Release validation and publish a ready-to-run app:

```bash
./Scripts/test-all.sh
open Build/Release/MyMacSwissArmyknife.app
```

The validation script:

- runs the ClipyEnhanced bridge tests;
- builds ResourceMonitor in Debug and Release and runs its tests;
- runs the host unit and integration tests;
- builds the universal Release application;
- verifies all embedded executables, bundle identifiers, architectures, Finder
  extension metadata, and signatures; and
- publishes the checked application at
  `Build/Release/MyMacSwissArmyknife.app`.

## Permissions

When ScrollReverser is enabled, the host requests Accessibility and Input
Monitoring access. ClipyEnhanced automatic paste also uses the host's
Accessibility permission. macOS requires the user to approve these permissions
in System Settings.

For login startup to work outside Xcode, move the built app to `/Applications`.
A Developer ID signing identity is required before distributing the app.
Keeping the same bundle identifiers and installing at
`/Applications/MyMacSwissArmyknife.app` minimizes permission churn during local
updates. A stable certificate is still required for macOS to treat rebuilt
versions as the same signed code identity.

## Startup Semantics

- Enabling a module starts it and keeps it running.
- Disabling a module stops it and clears its login-startup setting.
- Selecting **Start at login** enables the module and registers the host as a
  macOS login item.
- On a new system boot, only modules marked **Start at login** remain enabled.
- During the same boot session, relaunching the host preserves enabled state.

## Licensing

ScrollReverser is Apache-2.0 licensed; its license and notice remain in its
upstream directory. ResourceMonitor is integrated with authorization from its
owner and original author, lwtdzh. ClipyEnhanced is MIT licensed; its license
and the ClipMenu license remain in `Upstream/ClipyEnhanced`.
