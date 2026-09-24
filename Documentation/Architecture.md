# Architecture

## Process Model

```text
MyMacSwissArmyknife
  |
  +-- ModuleStateStore
  |     +-- persistent enabled/login-startup state
  |     +-- boot-session transition policy
  |     `-- aggregate SMAppService registration
  |
  +-- ModuleSupervisor
  |     +-- in-process module lifecycle
  |     +-- helper process health polling
  |     `-- launch/terminate/restart
  |
  +-- module settings adapters
  |     +-- ScrollReverser preference domain
  |     +-- ResourceMonitor preference domain
  |     `-- RightClickMenu shared JSON configuration
  |
  +-- in-process modules
  |     `-- ScrollReverser event tap
  |
  `-- embedded helper processes
        +-- ResourceMonitor.app
        `-- RightClickNewFilesHost.app

MyMacSwissArmyknife.app
  `-- Contents/Helpers/RightClickNewFilesHost.app
        `-- Contents/PlugIns/RightClickNewFilesExtension.appex
```

ScrollReverser runs inside the host because macOS grants Accessibility and
Input Monitoring permissions to the executable that creates the event tap.
This lets the host own permission prompts and prevents ScrollReverser from
creating a separate window or menu-bar icon.

ResourceMonitor remains a helper process because it owns a distinct live
metrics menu-bar presentation. Its process boundary also lets the supervisor
recover it independently after a crash.

RightClickMenu uses one Finder Sync extension embedded in a lightweight helper.
The extension returns a native `RightClickMenu` parent item with an `NSMenu`
submenu. Finder opens that submenu on hover, with Open With applications, New
File templates, and Open Terminal Here flattened into one level and separated
by command family. Leaf actions execute in the extension using the Finder
selection available when Finder dispatches the action.

The lightweight helper remains the containing application for the Finder Sync
extension, but stays inside the main application's `Contents/Helpers`
directory. The module registers that embedded extension and launches the
embedded helper when needed, leaving only `MyMacSwissArmyknife.app` at the top
level of `/Applications`.

The host and extension share one JSON configuration in the extension container.
The extension reloads it whenever Finder requests a menu, so settings changes
do not require restarting Finder.

## RightClickMenu Providers

Finder menu behavior is split into `RightClickMenuCommandProvider`
implementations:

- `OpenWithCommandProvider`
- `NewFilesCommandProvider`
- `OpenTerminalCommandProvider`

The extension initializes `RightClickMenuCommandRegistry` with all registered
providers and converts each provider group to native submenu items. Each leaf
uses a stable integer tag and an Objective-C-visible dynamic selector. The
native submenu preserves each leaf's explicit enabled state instead of asking
Finder's responder chain to auto-enable it. The selector rebuilds the command
from the action snapshot stored when Finder requested that menu. This avoids
querying Finder's transient selection after the context menu has closed.
Adding another Finder command only requires another provider in the registry.

The helper installer removes the former standalone
`/Applications/RightClickNewFilesHost.app`, unregisters other development
copies of the same Finder extension, and then registers the helper embedded in
the installed main app. This prevents Finder from alternating between stale
copies with the same extension identifier.

## Adding a Module

1. Add a `ModuleDefinition` with `.inProcess` or `.bundledApplication`.
2. For an in-process module, implement `InProcessModule` and inject it into
   `ModuleSupervisor`.
3. For a helper application, add its build to `Scripts/build-modules.sh`.
4. Add a settings adapter and a tab to `CollectionSettingsView`.
5. Add lifecycle and settings tests.

No change to `ModuleStateStore` or `ModuleSupervisor` should be necessary.

## Login Startup

The host is the only registered login item. Per-module settings are stored by
the host. At login, the host compares `kern.boottime` with the previous boot
session and derives each module's enabled state from its `startsAtLogin` flag.
This gives independent module startup behavior without registering multiple
nested applications with ServiceManagement.

## Health

`ModuleSupervisor` checks each enabled module every three seconds. In-process
drivers report their operational state directly. Helper applications are
checked by bundle identifier and launched from `Contents/Helpers` when missing.
Disabled modules are stopped, and launch or permission errors are surfaced in
the module tab.
