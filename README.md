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

