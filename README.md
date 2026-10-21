> [!WARNING]
> This document describes the files and procedures designed and implemented
> specifically for the FSDS team's iPad test automation capability.
>
> It outlines the intended workflow in case something breaks and needs manual
> intervention, or as a reference for developers that wish to adjust or extend
> any component used by the test automation services.
>
> However, in the ideal scenario, you (test engineer or CM manager) should 
> never have to consult or be aware of this file.
>
> The only files most users should interact with are:
>
>   - `emt`: Allows users to select app/device for test (remote access via SSH)
>   - `appium-agent`: Controls Appium configuration (local access only)

# Build and install

Go 1.26.1 or newer and GNU Make are required. `semver.ascii` is the default
version, embedded into the executable with `go:embed` and shown by `--help`.
Edit that file to change the project version.

```sh
make                       # Build bin/appium-agent (also: make build)
make version               # Print the selected version
make check                 # Run Go tests/vet, shell checks, and deployment regressions
make install               # Install under ${FSDS_PREFIX:-/opt/fsds}/bin
make install version=0.10.3 # Override the version for this build/install only
make deploy                # Verify, back up, and deploy the executable + runtime scripts
make clean                 # Remove the local build, not installed versions
```

`make install` installs `appium-agentVERSION` and points the relative
`appium-agent` symlink at it, matching EMT's installation layout. For example,
the current default installs `appium-agent0.10.2`. Older versioned binaries
are retained. Reinstalling the **same version replaces that binary**, so use
a new version to preserve a rollback point.

To roll back to a retained version:

```sh
ln -sfn appium-agent0.10.0 "${FSDS_PREFIX:-/opt/fsds}/bin/appium-agent"
```

`make install` updates only the Go executable. For a complete release, run
`make deploy` as the service-owning user, optionally setting `FSDS_PREFIX` and
`version` just as with `make install`. It runs the checks and build, rejects an
already-installed version, and prevents concurrent deployments with a lock.
Update `semver.ascii` or supply a new version before deploying again.

Deployment snapshots the current executable and both runtime scripts under
`${FSDS_PREFIX:-/opt/fsds}/var/backups/appium-agent/`, then atomically replaces
`genprops.zsh`, `appiumd.zsh`, the versioned executable, and the executable symlink.
It verifies the installed program with `--help`; it never runs the launcher,
restarts services, or overwrites live configuration. Test harnesses and
`run/etc/appium` defaults are not deployed.

Replacements are atomic per file, not a multi-file transaction; use the printed
backup directory if a deployment fails after publication starts. Review any
local edits to deployed scripts before overwriting them.

# Appium service

The Appium server runs perpetually under launchd(8) as a LaunchAgent in the
"User" domain and is defined in the following file:

 - `${HOME}/Library/LaunchAgents/appium.plist`

  > The `${HOME}` variable refers to the home directory of the user that should
  > control the Appium (Node.js) processes. We are using a shared user account
  > named `fsds` for all FSDS-related services on macOS (`HOME="/Users/fsds"`).

The agent manages restarting the server on bootup, after crashing, etc., to
ensure it is *always* running and available on its defined interface.

To enable/load or disable/unload the agent, use the following commands:

```sh
# Install and activate the agent. You must specify the file argument using its
# absolute path. Every component in the path, including the file itself, must
# be a real physical file/dir; using symlinks anywhere in the path will produce
# an extremely vague error (such as "I/O error").
launchctl load /Users/fsds/Library/LaunchAgents/appium.plist
launchctl enable /Users/fsds/Library/LaunchAgents/appium.plist

# With similar conditions as above, deactivate and uninstall the agent.
launchctl disable /Users/fsds/Library/LaunchAgents/appium.plist
launchctl unload /Users/fsds/Library/LaunchAgents/appium.plist
```

# Configuration

The above launch agent invokes Appium using a shell script (zsh) located at:

 - `${FSDS_PREFIX}/libexec/appiumd.zsh`

This shell script provides a JSON configuration file to Appium that defines
"capabilities" of the device under test. This controls which devices and 
interfaces to expose through the Appium Web server. The JSON file definition is
specified by Appium using a JSON formatted schema. Both the configuration file
and associated schema are located in the same directory:

 - `${FSDS_PREFIX}/etc/appium/config.json`
 - `${FSDS_PREFIX}/etc/appium/schema.json`

Note the schema should be considered read-only and never modified. Refer to the
schema for a list of available configuration options, along with their default 
values, data types, enumerations, etc.

This configuration file contains data specific to the most recently requested
test event: hardware device UDID under test, target iOS version, path to app
under test (source code and executable), etc. These parameters will be used in 
all subsequent test events until a new configuration has been installed.

For every new test event configuration, these test-specific parameters must 
somehow be input to the JSON configuration file. But, manipulating the JSON 
content is error-prone and tedious. Instead, the test-specific parameters are 
also defined in a simple ini-style configuration file with newline-delimited, 
`key=value` syntax that is much easier to modify for both humans and automated
tools:

 - `${FSDS_PREFIX}/etc/appium/config.env`

> [!IMPORTANT]
> This file is the preferred source of Appium configuration because of its
> simple syntax and minimal content. 

When a new test event is requested, the `appiumd.zsh` launch agent reads this 
file — along with any command-line arguments defined in `appium.plist` — and 
overwrites the corresponding values in the JSON configuration file.

## Independent Calculator and test-driver workflows

The generated `config.env` keeps Calculator selection (`proj_source`,
`bundled_app`, `proj_config`, and `target_app_ipa`) independent from the Driver
selection (`test_driver_source`, `test_driver_scheme`, `bundled_drv`, and
`test_config`). EMT may select a validated, retained IPA through its canonical
`~/Library/Caches/emt/upload/app.ipa` symlink.

- The default invocation builds and installs only Calculator from
  `--target-app-source`; it derives and saves the built IPA's actual bundle ID,
  and never installs or launches the Driver.
- `--restart-appium` reconnects Appium without installing either application.
- `--activate-ipa PATH` validates and installs that uploaded Calculator IPA,
  derives its bundle identifier, updates the generated configuration, and
  restarts Appium. It does not select, stop, replace, or install the Driver.
- `--test-driver-only --test-driver-source PATH` builds, installs, and launches
  only the FMPS Test Driver Runner from that required, independent source; it
  never falls back to the Calculator source. `--test-driver-scheme` selects its
  Xcode scheme; `--test-driver-config` selects its build configuration.
  Calculator's source, bundle identifier, config, and IPA selection are retained.
- `--relaunch-test-driver` reuses the installed Runner and retained artifacts
  without building or installing either application.

Driver builds override `OTHER_LDFLAGS` to `-all_load` for `WebDriverAgent` and
`FMPS Test Driver`, enabling exception unwinding even in older source branches.
Other targets retain their project linker settings, including Calculator's Ada
libraries. These overrides require a rebuild/install; relaunch alone cannot apply them.
The override selects a setting name before expanding its value; placing
`$(inherited)` inside `:default=` concatenates list-valued linker flags.

Calculator installation succeeds even when WDA is unavailable; the console
directs the operator to provision the Driver with `t`. Calc operations do not
require the Driver manifest or retained build products. Explicit Driver operations
and the watchdog can restart the Runner; an Appium-only restart does not itself
terminate it.

Appium connects through `webDriverAgentUrl`; it does not launch a separate WDA.
The Driver manifest and provisioning lock are stored below
`${FSDS_PREFIX}/var/run/appium`. Operations reload the current generated
`config.env` while preserving explicitly supplied command-line values. `--orphan`
alone does not discard saved selections; `--zero` disables this reload and uses
only command-line flags and environment values.

An unchanged source launch keeps the canonical configuration so its built bundle
ID remains available to later restarts. A missing saved file can be created with
`--overwrite-config`. Reboot and USB-cycle operations retain device selection
without applying Calculator IPA normalization.

The driver manifest records the source, device, Runner path, and generated
`.xctestrun` path. Retain the managed DerivedData alongside it. Driver builds
alternate between two build directories, preserving the published artifacts if
compilation or installation fails. Missing artifacts or an older manifest require
one `t` provisioning run before Driver relaunch; they do not prevent Calculator
installation. There is no legacy launcher fallback.

Deploy the binary with the matching `run/libexec/appiumd.zsh` at
`${FSDS_PREFIX}/libexec/appiumd.zsh`. The launcher's build, relaunch check, and
manifest writer must use `test_driver_source`, not Calculator's `proj_source`.
After correcting an older launcher, provision once with EMT `t` to replace the
previously installed Driver; `T` only relaunches that existing installation.

Check independent branch selection and failed-install attribution against both
the source and deployed launcher without touching the device:

```sh
zsh run/libexec/driver_source_test.zsh
zsh run/libexec/driver_source_test.zsh /opt/fsds/libexec/appiumd.zsh
```

After an explicit Driver launch publishes its URL, startup verifies WDA readiness
through the configured localhost forwarding endpoint. A failed check reloads the
existing iOS tunnel and USB proxy once, then checks again before starting Appium.
If forwarding remains unavailable, startup fails instead of advertising a usable
driver. Healthy forwarding is left untouched; recovery briefly interrupts the
shared tunnel and proxy but does not reinstall either application.

Appium startup also starts a separate `WDA Watchdog` tmux session when a retained
Driver manifest exists. It probes WDA directly every two seconds, not Appium's
independent `/status`. A missing Runner tmux session triggers recovery immediately.
With a surviving host process, three failed probes require either a crash marker
in the current Driver log or five minutes of continuous failure: ordinary long
WDA commands can block its main-thread `/status` handler. Commands intentionally
blocking that handler for more than five minutes need a longer watchdog allowance.

Recovery reuses the `--relaunch-test-driver` lifecycle under the provisioning lock,
validates the selected source/device/artifacts, and waits for WDA readiness before
restarting Appium. It never builds, installs, or replays test commands. Old Appium
sessions and element IDs are invalid: clients must create a new session and resume
from a known checkpoint. Provisioning pauses monitoring; `--lldb-managed` disables
it, and stopping Appium stops the watchdog rather than resurrecting the service.

There are at most three automatic relaunches until WDA and its Runner remain
healthy for two minutes. Exhaustion is logged and requires operator correction
and EMT `T` (or restored stable health); repeated crashes cannot cause an unlimited
restart loop. Watchdog output is in `${FSDS_PREFIX}/var/log/appium/recovery.log`.
An Appium creation failure after WDA recovery is left for the host service/operator.

Run deterministic recovery checks without touching the device:

```sh
zsh run/libexec/recovery_test.zsh
zsh run/libexec/recovery_test.zsh /opt/fsds/libexec/appiumd.zsh
```

The custom WDA launch path returns XCTest manager launch errors as structured
WebDriver responses instead of throwing an exception that terminates the Runner.
Failed session creation returns `session not created`; launch/activate requests
return the underlying launch error while WDA remains available. This does not
bypass signing, provisioning, or device trust requirements: correct those
requirements before retrying. After changing WDA source, rebuild and install the
Runner; `--relaunch-test-driver` alone reuses the installed binary.

Device smoke coverage (iPadOS 27.0.1, Xcode SDK 26.2): forced Calculator launch,
missing-app launch and activation followed by successful WDA commands, failed WDA
session creation followed by a successful Appium session, and automatic recovery
after stopping the USB proxy. Rejected signing/trust and other SDK versions were
not exercised.

Project IPA installation progress shown in EMT includes the installer's detailed
`err` field alongside its status/message. Unfiltered installer JSON events are
also appended to `${FSDS_PREFIX}/var/log/appium/session.log` for diagnostics.

`run/libexec/genprops.zsh` is the source for the shared helper deployed at
`${FSDS_PREFIX}/libexec/genprops.zsh`. Both built and uploaded IPAs preserve an
installed target when its application-identifier prefix matches the incoming
IPA's signed entitlement. A different prefix requires uninstalling the target
and removes its local data. Unreadable or invalid signing metadata stops the
operation before any uninstall. Both installation paths uninstall only the exact
target Calculator bundle ID on a signing-prefix mismatch, never the FMPS Test
Driver or variants. A Calculator IPA that would replace the selected Driver is rejected.

Run the signing-selection regression checks with:
`zsh run/libexec/genprops_test.zsh`.

Appium startup rotates only `session.log` and `server.log`. The driver log rotates
immediately before starting a new Xcode driver, not when Appium restarts while
reusing a driver. Logs owned by
EMT, tunnel, USB proxy, and LaunchAgent stdout/stderr writers are left in place.
Run the log-lifetime regression checks with:
`zsh run/libexec/appiumd_test.zsh`.
