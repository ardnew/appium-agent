#!/bin/zsh
# ==============================================================================
#  appiumd.zsh: Attach console to new or existing Appium server
# ------------------------------------------------------------------------------
#  This script is used to launch Appium by either system services (launchctl)
#  or regular users. It is also used to re-attach a running Appium instance to
#  the user's current console window, if such an instance exists.
#
#  The script takes no arguments and locates its dependencies automatically by
#  file paths relative to the location of this script.
#
#  If no Appium instance is currently running, a new instance is created and
#  attached to the current console. Otherwise, Appium is already running, its
#  original session (with all history) is re-attached to the current console.
#
#  For debugging this script, export the environment variable `trace_agent` to
#  a truthy value either in the environment from which this script is invoked,
#  or in the environment configuration script located at:
#
#   • ${FSDS_ROOT}/run/etc/appium/config.env
#
#  Passing the flag `-v` to appium-agent will also enable "trace_agent".
#  You do not have to edit any files or modify your environment in that case.
#
#  Debug output will be printed to stdout if run manually from a command-line.
#  Otherwise, if run by launchctl, the debug output will be printed to the
#  stdout log file path defined in the service configuration, e.g.:
#
#   • ~/Library/LaunchAgents/appium.plist
#
# ==============================================================================

# Return whether argument was truthy (true = 0) or not (false = 1).
#
# These values are consistent with how the shell defines success (exit = 0)
# and failure (exit > 0) but are perhaps opposite conventional definition.
#
# This allows us to use the shell's native eval constructs to test if variables
# have a true/false value, supporting a number of different concrete values:
#
#   False(1): "FaLsE", "0", "no", "", "000", "N\r\n", " \tF^J", etc.
#   True(0): not False
truth() {
  [ ${#} -gt 0 ] || return 1
  perl -ne'exit m,^\s*(|0+|f(a(l(se?)?)?)?|no?)\s*$,i' <<< "${1}"
}

self=$( realpath -q "$0" )
root=$( dirname "${self%/*}" )
date=$( date +'%Y%m%d-%H%M%S' )

# ------------------------------------------------------------------------------
#  configuration
# ------------------------------------------------------------------------------

session='Appium'
startin=$root
logback="${root}/var/log/appium/backup"
logserv="${root}/var/log/appium/session.log"
logdrvr="${root}/var/log/appium/driver.log"
cfglock="${root}/var/run/appium/session.lock"
cfgjson="${root}/etc/appium/config.json"
wdalock="${root}/var/run/appium/build.lock"
genprop="${root}/libexec/genprops.zsh"
expoipa="${root}/var/ipa/app.ipa"
numjobs=$( nproc )

# Source the dynamic settings from a sh-formatted file
if [[ -r "${appium_config_env}" ]]; then
  . "${appium_config_env}"
else
  [[ ! -r "${cfgjson%.json}.env" ]] ||
    . "${cfgjson%.json}.env"
fi

[[ ! -x "${genprop}" ]] ||
  . "${genprop}"

truth ${trace_agent} && set -x

# ------------------------------------------------------------------------------
#  utility routines
# ------------------------------------------------------------------------------

rotate() {
  retain=10 # number of backup logs to keep
  mkdir -p "${logback}" # ensure backup dir exists

  for log in "${@}"; do
    base=${log##*/}
    # move the given file into the backup dir (if it exists)
    [[ ! -f "${log}" ]] ||
      mv "${log}" "${logback}/${base%.log}.${date}.log"
    # replace it with a new, empty log file
    touch "${log}"

    # sort all files with the same basename in the backup dir by modtime,
    # and remove all but the ${retain} most recently modified
    while read -re name; do
      [[ ! -f "${logback}/${name}" ]] ||
        rm -f "${logback}/${name}"
    done < <(
      command ls -1rt "${logback}/${base%.log}."*".log" | head -n -${retain}
    )
  done
}

srcroot() {
  # Check for the existence of some relative path to determine if we are in the
  # correct directory
  curr=${1:-${proj_source}}
  check=${2:-'Source/Xcode'} # Only valid from root directory

  [ -d "${curr}" ] || curr=$( dirname "${curr}" )

  cd "${curr}"
  while [ "${PWD}" != "/" ]; do
    [ ! -e "${check}" ] || { pwd ; return }
    cd ..
  done
  return 1
}

# Usage:
#
#   build [sdkversion] [xcodeproj] [scheme] [config] [destination] [iosversion] [action ...]
#
# All arguments are optional. Undef and empty arguments use globally-defined
# default values; most are sourced from "${root}/etc/appium/config.env".
#
# To specify an argument that appears after deferred/defaulted arguments, use
# an empty string as placeholder:
#
#   # Override argument $2 and $4, but use the default values everywhere else
#   build '' foo '' bar
#
build() {
  local xcargs action=${xcbuild_act}
  (( $# < 7 )) || action="${@:7}"

  xcargs+=( -sdk "'iphoneos${1:-${sdk_version}}'" )
  xcargs+=( -project "'${2:-${proj_source}}'" )
  xcargs+=( -scheme "'${3:-${test_scheme}}'" )
  xcargs+=( -configuration "'${4:-${test_config}}'" )
  xcargs+=( -destination "'${5:-${target_dest}}'" )
  xcargs+=( -jobs "'${numjobs}'" )
  # The following is required when auto-provisioning is enabled to allow
  # automatic renewal of expired profiles (and certificates).
  xcargs+=( -allowProvisioningUpdates -allowProvisioningDeviceRegistration )
  xcargs+=( "'IPHONEOS_DEPLOYMENT_TARGET=${6:-${ios_version}}'" )

  echo xcodebuild ${xcargs} ${action}
}

makeipa() {
  local proj=${proj_source##*/}
  local base=${self##*/}
  local ipapath="${expoipa%/*}/${base%.*sh}-${date}"
  local builder=$( srcroot ) || return 127

  builder="${builder}/Extra/Scripts/build-release.sh"
  [ -x "${builder}" ] || return 126

  # build and symlink to the common path expected by Appium / test scripts
  "${builder}" -c release -x "${proj_scheme}, ${proj_config}" -k "iphoneos${sdk_version}" -i "${ios_version}" "${ipapath}" &&
    ipa=$( find "${ipapath}" -type f -name "${proj%.xcodeproj}.ipa" ) &&
      ln -sf "${ipa}" "${expoipa}"
}

exists() {
	tmux has-session -t "$1" 2>/dev/null
}

contain() {
  local args="tmux -u2 attach-session -t \"${1:-}\""
  case ${TERM:-} in
    alacritty*)
      "${TERM}" msg create-window \
        -o 'window.startup_mode = "Maximized"' \
        -e zsh -i -l -c "${args}"
    ;;
    tmux*)
      ${args}
    ;;
    xterm*)
      "${TERM}" -maximized -u8 \
        -e zsh -i -l -c "${args}"
    ;;
  esac
}

attach() {
	[ -n "${TMUX:-}" ] && tmux -u2 switch-client -t "$1" || contain "$1"
}

jqfilter() {
  local path
  for dir in "${@:2}"; do path="${path}.\"${dir}\""; done
  echo "${path} = ${1}"
}

ifaddr() {
  # echo the IPv4 address of the given interface name, e.g., "en0".
  active=$(
    echo "${1}" |
    perl -anle'
      BEGIN { $u = `ifconfig -ul` }
      print if ( ($_) = grep { /\S/ && $u=~/\b\Q$_\E\b/ } @F )
    '
  )
  # Need to use BSD cut for -w flag (not GNU)
  cut='/usr/bin/cut'
  ifconfig ${active} |
    command grep -oE 'inet\s+[0-9.]+' |
    "${cut}" -sw -f2
}

config() {

  mkdir -p "${cfglock%/*}"
  if [[ -f "${cfglock}" ]]; then
    echo 'config: appium config already locked' |& tee -a "${logserv}"
    return 1
  fi

  # Always define the following options
  local opts=(
    # Required capabilities
    'automationName: "XCUITest"'
    'platformVersion: env.sdk_version'

    'useNewWDA: true'
    #'useSimpleBuildTest: true'

    # Appium/WebDriverAgent optimizations
    'shouldUseSingletonTestManager: false'
    'waitForQuiescence: false'
    'screenshotQuality: 2' # [0=highest .. 2=lowest]

    # The following is required when auto-provisioning is enabled to allow
    # automatic renewal of expired profiles (and certificates).
    'allowProvisioningUpdates: true'
    'allowProvisioningDeviceRegistration: true'

    'showXcodeLog: true'
    'showIOSLog: env.trace_agent'

    # Access to keychain is required for use with code signing assets
    'keychainPath: "/Users/fsds/Library/Keychains/login.keychain-db"'
    'keychainPassword: "fsdspass"'

    # TBD: Determine if this can be used to detect cached build artifacts and
    #      reduce compilation/install times.
    #
    #   | proj=${proj_source##*/}
    #   | export derived_dat="${proj_source%/${projo}}/DerivedData/${proj%.xcodeproj}"
    #
    #'derivedDataPath: env.derived_dat'

    # Facebook's modern device automation utility
    #'launchWithIDB: true'

    # These need to be predefined in the Xcode project.
    #'xcodeOrgId: "T3BRA85ATJ"'
    #'xcodeSigningId: "iPhone Developer"'
  )

  # Override service URL with local TCP port forwarding
  #[ x${service_url} != x ] ||
  #  export service_url="http://localhost:${driver_port}"

  # Add the following options iff the corresponding env var is defined
  declare -A append=(
    [webDriverAgentUrl]=service_url
    [updatedWDABundleId]=bundled_drv
    [wdaLocalPort]=driver_port
  )
  local prebuilt=false
  for key ref in "${(@kv)append}"; do
    [[ -n ${(P)ref++} ]] || continue
    opts+=( "${key}: env.${ref}" )
    prebuilt=true
  done
  ${prebuilt} && opts+=( 'usePrebuiltWDA: true' )

  # If target_dest begins with "id=", then interpret it as a hardware UDID.
  # Otherwise, the device is specified by the more user-friendly common name.
  if [[ "${target_dest}" == "id="* ]]; then
    export target_udid=${target_dest#id=}
    opts+=( 'udid: env.target_udid' )
  else
    opts+=( 'deviceName: env.target_dest' )
  fi

  [ x${app_id} = x ] || export bundled_app=${app_id}
  opts+=(
    'bundleId: env.bundled_app'
    'noReset: true'
    'autoLaunch: true' # launch app under test (not test driver)
    'shouldTerminateApp: true'
    'forceAppLaunch: true'
  )
  local query=$(
    jqfilter "{ ${(j:,:)opts} }" server default-capabilities appium:options
  )
  if ! jq "${query}" "${cfgjson}" > "${cfglock}"; then
    echo "config: failed to apply JSON filter: ${query}" |& tee -a "${logserv}"
    return 2
  fi
  mv "${cfglock}" "${cfgjson}"
}

create() {
  # exit immediately if any command results in error status
  set -e

  # rotate our log files
  rotate "${logdrvr}" "${logserv}" &>/dev/null

  # if ${appium_restart} is non-empty, then skip building the target app and
  # test driver, and proceed immediately to launch Appium
  if [[ x${appium_restart} == x ]]; then

    # build and install the Calc App .ipa for installation on target device
    makeipa || return

    # If there exists a named capture group "Keep", then trigger will export
    # the captured pattern as ${TRIGGER_PATTERN} for the triggered command.
    url=$( trigger -a ${logdrvr} \
      '/ServerURLHere->(?P<Keep>http://[0-9\.]+:[0-9]+)<-ServerURLHere/' \
      -- zsh -i -c "$( build ) &" \
      ++ zsh -c 'echo ${TRIGGER_PATTERN}' )

    # use local TCP port forwarding via USB (usbmuxd) instead of direct TCP/IP
    #url=$( sed -E 's/^([^\/]+\/\/)[^:]+(:[0-9]+)$/\1localhost\2/' <<< ${url} )

    export service_url=${url}
  fi

  # construct Appium configuration file "config.json" and exec arguments
  config || return
  local args=(
    --address "$( ifaddr "${listen_name}" )"
    --port "${listen_port}"
  )

  # fire off Appium in its own tmux session
  tmux new-session -d -c "${2}" -s "${1}" -n "${1}" \
    zsh -i -c "appium server ${args} --config '${cfgjson}' |& tee -p -a '${logserv}'"
}

# ------------------------------------------------------------------------------
#  main
# ------------------------------------------------------------------------------

exists "$session" || create "$session" "$startin"
[[ ${-} != *i* ]] || attach "$session"

# Always turn off execution trace, though this usually isn't necessary
# (unless the script is being sourced for some reason).
set +x
