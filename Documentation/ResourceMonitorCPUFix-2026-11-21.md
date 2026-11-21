# Resource Monitor nettop CPU fix

The fix keeps nettop's input pipe open and cleans up its process when the application closes the helper's output. During the follow-up build 44 installation, collector PID **69105** averaged **0.33% CPU over 15 seconds**. A scan of all nettop processes confirmed it was the only remaining collector. The sections below preserve the investigation and initial installation evidence.

**Build 45 was fully rebuilt, tested, and installed on November 22.** The installed collector averaged **0.95% CPU over 20.01 seconds**, all **81 XCTest cases** passed, and every supported refresh interval passed additional runtime checks. See the build 45 results at the end of this report.

## Correction after the user's follow-up screenshot

The initial verification missed an orphaned nettop from the XCTest run. The user's screenshot showed **PID 77976 at 135.8% CPU**. Live inspection confirmed its parent was PID 1, its stdin pipe had no writer, and its start time was **13:16:51 on November 21**, matching the earlier XCTest run. It was separate from the installed app's collector, PID 78247, which was still at about **0.3% CPU nearly ten hours later**. The earlier completion statement was incomplete because it checked the replaced application collector but missed this test process.

PID 77976 has been terminated. Investigation reproduced the missing cleanup path: closing the helper's output reader caused the helper to exit with **-13 (SIGPIPE)**. Its nettop child survived, lost the input pipe's writer, and encountered the same EOF loop.

The additional fix ignores SIGPIPE in the helper and uses the throwing **FileHandle.write(contentsOf:)** API. When its output reader closes, the helper catches the write failure, terminates and reaps nettop, then exits. Normal sampling and the existing SIGTERM cleanup remain unchanged.

The new **output-closed** regression test failed with -13 before this change and now passes, explicitly checking that nettop is gone. Existing parser, CPU/cadence, collector-exit, and helper-exit tests pass. All seven Resource Monitor XCTest cases were rerun successfully; a subsequent process scan found only the installed application's collector, with no test collector left behind.

The universal release was rebuilt and installed. Helper **69100** and nettop **69105** replaced the previous installed sampling processes. The main app, Resource Monitor, and ClipyEnhanced retained PIDs **1789, 1853, and 1910**. Preferences are identical before and after installation, and the helper still runs with **--interval 2**.

## Cause and code change

The call chain is **TrafficMonitor.launchHelper → net-speed-all → ExternalNetworkSampler.init → /usr/bin/nettop**.

The helper connected nettop’s standard input to **/dev/null**. On this Mac, nettop continues watching input in CSV logging mode. The immediately ready/end-of-file input makes its event handling spin. A three-second stack sample showed repeated dispatch event processing. Changing only stdin to an open, idle pipe eliminated the high CPU while preserving sample delivery.

In **Upstream/ResourceMonitor/Sources/NetSpeedHelper/main.swift**, lines 53–55 retain the pipe for the sampler’s lifetime; line 82 passes it to nettop. The follow-up adds output-error cleanup in **emit** and ignores SIGPIPE during helper startup.

The collector still uses the same arguments:

```text
nettop -P -d -t external -L 0 -s 1 -n -x -J bytes_in,bytes_out
```

Continuous delta counting, external-interface filtering, startup-baseline exclusion, PTY output flushing, all refresh options, CPU/memory/disk sampling, and shutdown behavior remain unchanged. In particular, this preserves the November 11 fix for missing traffic when upload connections close.

## Evidence

CPU measurements below use the increase in process CPU time divided by elapsed wall time. A value above 100% means more than one core’s worth of CPU.

| Experiment | nettop CPU | Result |
|---|---:|---|
| Fresh original helper, 10.04 seconds | 146.75% | Reproduces immediately |
| Direct nettop, stdin /dev/null, 10.01 seconds | 146.77% | 11 CSV frames |
| Same nettop arguments and PTY output, idle input pipe, 10.01 seconds | 0.60% | 11 CSV frames |
| Patched helper with temporary instrumentation, 10.04 seconds | 0.80% | JSON samples continue |
| Clean helper regression test, 5.01 seconds | 0.20% | Five valid samples |
| Installed release helper’s collector, 15.01 seconds | 0.67% | stdin verified as PIPE |

The measurements in this table describe the initial fix. The old collector was PID 1922, parent helper 1921. The initial installation replaced them with helper 78240 and collector 78247. Both original sampling processes were confirmed gone, but the separate XCTest collector was missed at that stage. The follow-up correction above records its removal and the replacement process IDs.

**progress_status: verified**

| Hypothesis | Conclusion | Evidence |
|---|---|---|
| Input/EOF event handling causes a busy loop | CONFIRMED | Changing stdin alone reduced CPU from 146.77% to 0.60%, with equal frame counts |
| Days of accumulated collector state cause the observed behavior | REJECTED as a necessary cause | A freshly launched original helper reproduced 146.75% CPU immediately |
| Regular collection under the current socket load requires this much CPU | REJECTED as the explanation | The same collection options and host workload ran at 0.60% with an idle pipe |
| The screenshot shows the installed collector still spinning | REJECTED | Screenshot PID 77976 was orphaned; installed collector PID 78247 remained near 0.3% |
| Output-reader shutdown bypasses nettop cleanup | CONFIRMED | Closing the reader reproduced helper exit -13; the follow-up handles that error and verifies child termination |

Evidence came from process CPU-time measurements, a live stack sample, lsof descriptor inspection, temporary sampler lifecycle/delta events, and controlled curl transfers. This identifies the reproduced issue on this Mac; it does not claim to exclude every possible future cause of nettop CPU usage.

## Validation

- The new CPU regression test fails against the original source: **7.41 CPU-seconds in 5.03 wall seconds**. It passes against the fixed source.
- Existing delta-parser tests pass, including disappearing connections, newly observed processes, fragmented CSV, UTF-8 names, and exclusion of initial historical totals.
- The helper delivers all six numeric metrics at one-second cadence. Collector failure and helper shutdown tests both pass; neither leaves a collector behind.
- All **seven ResourceMonitorTests** pass.
- The release build succeeds for **arm64 and x86_64**, and strict signing verification passes for the module, installed full app, and packaged full app. Runtime tests ran on Apple Silicon.
- Resource Monitor preferences exported before and after installation are identical. The running helper retains the user’s two-second refresh setting.
- Production source contains no temporary instrumentation.

Controlled transfers used synthetic data and did not alter existing user transfers:

| Direction | curl-confirmed payload | Approximate integrated helper total during the window |
|---|---:|---:|
| Download, sixteen 1 MiB responses | 16,777,216 bytes | 18,185,912 bytes |
| Upload, one synthetic 8 MiB body | 8,388,608 bytes | 9,079,240 bytes |

The helper totals include all external background traffic, protocol overhead, and sampling-window differences. These tests demonstrate continued traffic counting, not a precise percentage accuracy estimate. A first attempt at a single 16 MiB download received HTTP 403 and was excluded; the repeated 1 MiB requests and 8 MiB upload completed successfully.

The initial repair did not rerun the host and Clipy test suites. No multi-day soak or Intel runtime test was performed. The follow-up reused the earlier controlled-transfer evidence because it changes only output-failure cleanup; it reran parser, sampler CPU/cadence, lifecycle, and Resource Monitor unit tests.

## Initial build 44 packages and backups

The follow-up package is **Build/Release/MyMacSwissArmyknife-v1.0-build44-nettop-cpu-fix-r2.zip**. This superseded the earlier package without the **-r2** suffix. Both ZIP archives are retained; their extracted app bundles were subsequently removed to prevent duplicate launcher icons.

That package was build 44 with the rebuilt universal helper substituted into a copy of the installed app, followed by signing the enclosing Resource Monitor and host bundles. Other module binaries were preserved. Only the sampling helper restarted; the host’s existing supervision launched its replacement. No source commit or remote publication occurred during that initial repair.

- Archive SHA-256: **33f545b8474aeab69338c4cad6ff7dbe6e39b5bc9be55685f1803e4dfe62e798**
- Helper SHA-256: **33a618ad522faffeb4e16b0bc901b733578822cb4927a4ff6409a1bd6ffda7f6**
- Backup before the follow-up: **~/Library/Application Support/MyMacSwissArmyknife/Backups/MyMacSwissArmyknife-build44-before-nettop-cleanup-20261121.zip**
- Original app backup: **~/Library/Application Support/MyMacSwissArmyknife/Backups/MyMacSwissArmyknife-build44-before-nettop-cpu-fix-20261121.zip**

For a manual follow-up, view nettop in Activity Monitor with Resource Monitor enabled and allow several refreshes. It should remain low during idle periods, while upload/download and other metrics continue updating. Changing the refresh interval should replace the sampling helper and leave only one collector; disabling Resource Monitor should remove its helper and collector. Restore the backed-up app only if rollback is needed.

Temporary instrumentation, the debugging server, session record, raw evidence, test builds, and the exchanged old app copy were removed after verification. The backup, release package, source change, regression test, and this report are retained.

## Build 45 verification — November 22

The complete release was built using **Scripts/package-release.sh v1.0-build45**, which runs **Scripts/test-all.sh** with release privacy checks enabled. Both the main app and Finder extension report build **45**.

| Check | Observed result |
|---|---|
| Host tests | 71 passed, zero failures: App Blocker, Keep Awake, Scroll Reverser, Finder menus, Clipy integration, preferences, module supervision and status menus |
| Resource Monitor tests | 7 passed, zero failures |
| Clipy bridge tests | 3 passed, zero failures |
| Network helper regressions | Parser, CPU/cadence, collector exit, helper exit and closed output reader all passed |
| CPU during the helper regression | 0.80% over 4.98 seconds, with five valid samples |
| Resource Monitor builds | Debug and Release passed |
| Full release | Universal arm64/x86_64 build passed; strict signatures, bundle contents, extension version, privacy scan and ZIP integrity passed |
| Packaged helper refresh choices | 1, 2, 3, 5 and 10 seconds all produced six valid metrics, matching external-interface totals and the expected cadence |
| Output reader closure | Each refresh choice terminated the helper and its nettop child within the next refresh plus the allowed shutdown time |
| Installed app | All 309 bundle entries matched the packaged app, including file hashes and symlink targets |
| App restart | The previous host, both modules, helper and nettop exited; the new host relaunched Resource Monitor and ClipyEnhanced |
| Installed collector | One nettop, PID 20487, parent helper 20485; 0.95% average CPU over 20.01 seconds; saved two-second interval retained |
| Preferences | Host, Scroll Reverser, Clipy and Finder configuration unchanged; Resource Monitor values and panel positions unchanged after decoding its reserialized JSON |
| Finder extension | Exactly one registered extension, enabled, inside the installed build 45 app |

The release helper also ran during synthetic external transfers. curl confirmed a **1,048,576-byte download** and an **8,388,608-byte upload**. The corresponding integrated helper totals were **65,120,409 download bytes** and **10,429,483 upload bytes**. Background traffic was substantial, especially during the download; these observations verify continued sample delivery and traffic counting but cannot establish transfer-specific accuracy. The earlier 16 MiB download / 8 MiB upload experiment above provides the less noisy measurement.

The host's designated signing requirement remains **identifier "com.mymacswissarmyknife.host"**, preserving the identity used by its macOS permissions. Clipboard paste events are dispatched through the host's existing bridge. No permission reset was performed.

The two extracted build 44 repair apps, the extracted build 45 packaging copy, old launcher registrations, and temporary build app bundles were removed. Spotlight now returns only **/Applications/MyMacSwissArmyknife.app** for the host bundle identifier. Its Resource Monitor and Clipy apps remain embedded in **Contents/Helpers**, and Finder's extension remains in **Contents/PlugIns**. ZIP backups are retained, including **~/Library/Application Support/MyMacSwissArmyknife/Backups/MyMacSwissArmyknife-build44-before-build45-20261122.zip**.

Release archive: **Build/Release/MyMacSwissArmyknife-v1.0-build45.zip**

SHA-256: **65f28915e71dc6dbc9f2e1358d66e5f1df06d276d4aeea411f6a90fa5664820d**

Runtime verification was on this Apple Silicon Mac. Intel binaries were built but not run; no multi-day soak was performed. Automated GUI inspection returned **AXErrorAPIDisabled**, so launcher cleanup was verified through bundle inventory, Spotlight and LaunchServices rather than a visual icon count. Live permission-dependent interactions such as scrolling and pasting into another application were not exercised in this release pass.
