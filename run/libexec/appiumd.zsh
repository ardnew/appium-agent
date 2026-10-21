#!/bin/zsh
# ==============================================================================
#  appiumd.zsh: Attach console to new or existing Appium server
# ------------------------------------------------------------------------------
#
#  This script is used to launch Appium via the appium-agent utility created
#  specifically for FSDS EFB automated testing. Refer to the help output from
#  appium-agent (-h) for details on configuring Appium including how to specify
#  the target Calculator version to test, which device/OS to test on, and how
#  to save/load default parameters:
#
#   • appium-agent --help
#
#  This script locates its dependencies relative to its own location. Public
#  configuration uses environment variables; arguments are reserved for internal
#  watchdog operations. A list of configurable environment variables and their
#  current default values is defined in:
#
#   • ${FSDS_PREFIX}/etc/appium/config.env
#
#  Typically, you shouldn't modify that file directly. Instead, prefer command-
#  line flags given to appium-agent so that their values are sanitized and
#  validated. Using flag --overwrite-config (-w) will save these normalized
#  parameters to this file for reuse the next time appium-agent is invoked.
#
#   | TIP: Before writing the configuration to disk, you can review what would
#   |      be written with all things considered using flag --dry-run (-y).
#   |      This can also be used to print a new configuration file to stdout
#   |      without running it (redirect this to a file to save it for later).
#
#   | TIP: If the configuration ever gets too wonky, you can re-initialize it
#   |      to a known working state with flag --zero (-z). Combined with other
#   |      flags, this can be useful a few different ways:
#   |        • --dry-run (-y)          – view all default settings
#   |        • --overwrite-config (-w) – reset configuration file on disk
#
#  If no Appium instance is currently running, a new instance is created inside
#  a new tmux session, and that session is attached to a new terminal instance.
#  Otherwise, Appium is already running and its session (with all history) is
#  re-attached to the current TTY/PTY.
#
#  For debugging this script, pass the flag `-G` to appium-agent to see every
#  shell command as it is executed. This lets you monitor the control flow as
#  well as the expanded value of all referenced variables.
#
#  Debug output will be printed to stdout if run manually from a command-line.
#  Otherwise, if run by launchctl, the debug output will be printed to the
#  stdout/stderr log file paths defined in the service configuration, e.g.:
#
#   • ~/Library/LaunchAgents/appium.plist
#
#   | TIP: Debugging the actual WebDriverAgent (WDA) service running on the
#   |      target is a complicated effort. Most of the complications are now
#   |      detected and handled by appium-agent if given the right flags.
#   |      If you need to trudge this deep, dark path, start by performing
#   |      the following steps:
#   |
#   |        1. Open the project in Xcode and select a target device/simulator
#   |           (the simulator has not been tested as thoroughly).
#   |
#   |        2. Change the run action from "Build" to "Test" by long-pressing
#   |           the "Run" button in the Xcode toolbar and selecting "Test"
#   |           (or via menubar Product > Test, or with keyboard shortcut ⌘U).
#   |
#   |        3. Open the console in Xcode (View > Debug Area > Activate Console)
#   |           and select the "All Output" tab.
#   |
#   |        4. Wait for the test to output the HTTP URL of the WDA server,
#   |           which should resemble:
#   |
#   |             "ServerURLHere->http://192.168.3.7:8100<-ServerURLHere"
#   |
#   |        5. Ensure the iOS USB proxy service is running and forwarding
#   |           a local TCP port to the WDA server with, e.g., command:
#   |
#   |             launchctl list net.dev_okc.ios_tunnel
#   |
#   |           It is running if the output of that command includes key "PID".
#   |
#   |        6. If it is not running, then reload the launchd service by
#   |           running the command "reload-ios-tunnel", and then rerun step 5
#   |           to verify the service started successfully.
#   |
#   |             script: "${FSDS_PREFIX}/bin/reload-ios-tunnel"
#   |
#   |        7. Export the service URL to an env variable named "service_url":
#   |
#   |             export service_url='http://localhost:8100'
#   |
#   |        8. Call appium-agent with the following flags at minimum, e.g.:
#   |
#   |             appium-agent -vfrg
#   |
#   |           These flags mean:
#   |
#   |             -v: verbose output
#   |             -f: kill all other instances of Appium currently running
#   |             -r: restart Appium without building the app or WDA
#   |             -g: use "Debug" build configurations and bundle identifiers
#   |
#   |           You may optionally add the following flags:
#   |
#   |             -G: enable shell command tracing (for debugging this script)
#   |             -d "id=<UDID>": specify the target device by its UDID
#   |             -o "<Major.Minor>": specify the deployment target iOS version
#   |             -k "<Major.Minor>": specify the iOS SDK version to use
#   |
#   |           The -g flag is neccessary even though we are not re-building
#   |           so that Appium can interact with the correct app, which it
#   |           locates by bundle identifier. If you are running a release
#   |           build of the app, and just want to quickly restart Appium,
#   |           then use the same flags as above sans "-g" (e.g., "-vfr").
#   |
#   |        9. Verify the script successfully forked a new Appium session.
#   |           It should print the following as the last line of its output:
#   |
#   |             INFO appiumd: tmux session created: "Appium"
#   |
#   |        ** [NOTE] You can attach to the Appium session to monitor its
#   |           output with the following command:
#   |
#   |             tmux -u2 attach-session -t Appium
#   |
#   |           To detach from the session (without killing the server),
#   |           press [Ctrl-a] then [d] (for detach).
#   |
#   |      Now you should be able to set breakpoints in the WDA source code in
#   |      Xcode and run test cases (via Test Complete or Appium Inspector) to
#   |      trace how the requests are handled, capture crash stack traces, etc.
#
# ==============================================================================

# Capture the current time for global use
declare -r now=$( date +%s )

# Return whether argument was truthy (true = 0) or not (false = 1).
#
# These values are consistent with how the shell defines success (exit = 0)
# and failure (exit > 0) but are perhaps opposite convention/intuition.
#
# This allows us to use the shell's native eval constructs to test if variables
# have a true/false value, supporting a number of different concrete values:
#
#   false(1): "FaLsE", "0", " 'no '", "", "000", "N\r\n", " \tF^J", etc.
#    true(0): not false
#
truth() {
  [ ${#} -gt 0 ] || return 1
  perl -ne'exit m,^\s*(['\''"]?)\s*(|0+|f+(a+(l+(s+e*)?)?)?|n+o*)\s*\1?\s*$,i' <<< "${1}"
}

bool() { if truth "$@"; then echo 'true'; else echo 'false'; fi; }

self=$( realpath -q "$0" )
root=$( dirname "${self%/*}" )
date=$( date +'%Y%m%d-%H%M%S' )

pout() { echo "INFO: $*" >&2; }
perr() { echo "ERROR: $*" >&2; }

[[ -n ${UNBUFFERED} ]] || {
  if command -v stdbuf > /dev/null 2>&1; then
    export UNBUFFERED=1
    exec stdbuf -o0 -e0 "${self}" "${@}"
  fi
}

# ------------------------------------------------------------------------------
#  configuration
# ------------------------------------------------------------------------------

# Error codes
ERR_PROJECT=127
ERR_BUILDER=126
ERR_EXELOCK=125
ERR_USBPROX=124
ERR_COMPILE=123
ERR_CFGFILT=122
ERR_UNKNOWN=100

session='Appium'
driver_session='FMPS Test Driver'
watch_session='WDA Watchdog'
startin=$root
logsapp="${root}/var/log/appium"
logserv="${root}/var/log/appium/session.log"
logappd="${root}/var/log/appium/server.log"
logdrvr="${root}/var/log/appium/driver.log"
logprox="${root}/var/log/appium/proxy.log"
recoverylog="${logsapp}/recovery.log"
cfglock="${root}/var/run/appium/session.lock"
cfgjson="${root}/etc/appium/config.json"
wdalock="${root}/var/run/appium/build.lock"
genprop="${root}/libexec/genprops.zsh"
expodir="${root}/var/ipa"
expoipa="${root}/var/ipa/app.ipa"
driverstate="${root}/var/run/appium/test-driver.json"
driverderived="${root}/var/run/appium/DerivedData/TestDriver"
provisionlock="${root}/var/run/appium/provision.lock"
provisionpid="${provisionlock}/pid"
tundata="${root}/var/run/ios-tunnel"
tunctrl="${root}/var/run/ios-tunnel/enable/true"
webserv="${root}/bin/emt-proxy"

numjobs=$( nproc )

if [[ ${1:-} == --watch-driver || ${1:-} == --recover-driver ]]; then
  export appium_config_env=${2:?missing watchdog configuration path}
fi

# Source the dynamic settings from a sh-formatted file
if [[ -r "${appium_config_env}" ]]; then
  . "${appium_config_env}"
else
  [[ ! -r "${cfgjson%.json}.env" ]] ||
    . "${cfgjson%.json}.env"
fi

unset -v FSDS_APP_ID FSDS_DEV_ID
if [[ -r "${genprop}" ]]; then
  . "${genprop}"
  [[ -z ${app_id} ]] || export FSDS_APP_ID=${app_id}
  [[ -z ${dev_id} ]] || export FSDS_DEV_ID=${dev_id}
fi

truth ${trace_agent} && set -x

# ------------------------------------------------------------------------------
#  utility routines
# ------------------------------------------------------------------------------

count() {
  local -a opts
  while getopts ':abcdefghLkprsStuwxOGN' op; do
    [[ ${op} != [:?] ]] || return 1
    opts+=( "${op}" )
  done
  shift $(( OPTIND - 1 ))
  [[ $# -gt 0 ]] || return 0

  for op in "${opts[@]}"; do
    for arg; do
      test -${op} "${arg}" || shift
    done
  done
  echo $#
}

prune() {
  local inpath=${1}
  local rmglob=${2:-'*'} # match everything by default
  local maxage=${3:-'7'} # maximum age of files to keep (in days)

  [[ -d "${inpath}" ]] || return 0 # nothing to do (not an error)

  local findargs=(
    -maxdepth 1
    -name "${rmglob}"
    -mtime +${maxage}
    -execdir rm -r -- '{}' +
  )

  find "${inpath}" "${findargs[@]}"
}

rotatelogs() {
  local -r maxage=7 # prune logs created more than this many days ago
  local lf dir base
  for lf in "${@}"; do
    dir=${lf%/*}
    base=${lf##*/}
    mkdir -p "${dir}/backup" || return
    [[ ! -f "${lf}" ]] ||
      mv "${lf}" "${dir}/backup/${base%.log}.${date}.log" || return
    touch "${lf}" || return
    # remove all log files older than ${maxage} days
    find "${dir}/backup" \
      -type f \
      -name "${base%.log}.*.log" \
      -mtime +${maxage} \
      -delete || return
  done
}


srcroot() {
  # Check for the existence of some relative path to determine if we are in the
  # correct directory. Runs in a subshell to avoid polluting caller's CWD.
  (
    local curr=${1:-${proj_source}}
    local check=${2:-'Source/Xcode'} # Only valid from root directory

    [ -d "${curr}" ] || curr=$( dirname "${curr}" )

    cd "${curr}" || return 1
    while [ "${PWD}" != "/" ]; do
      [ ! -e "${check}" ] || { pwd ; return 0 }
      cd ..
    done
    return 1
  )
}

prepsdk() {
  # Run in a subshell to avoid clobbering the script's EXIT trap
  # and leaking set -ex into the caller's environment.
  (
    set -ex
    # Keep other xcodebuild owners, including the active test driver, alive.
    security unlock-keychain -p "${sec_kc_pass}" "${sec_kc_name}.keychain"
  )
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

  prepsdk &> /dev/null

  if [[ -n ${auto_provision} ]]; then

    set -x
    local rootdir=$( srcroot "${2:-${proj_source}}" "Provisioning" ) ||
      return ${ERR_PROJECT}
    #${rootdir}/Extra/Scripts/efbctrl.pl

    local -a findprov=( provprof.sh -d "${rootdir}" -f $'%k\t%u\t%t\t%a' )

    local uuid kind team bund
    unset -v found global

    while [[ -z ${found} ]]; do
      while read -r prof; do
        kind=$( echo "${prof}" | cut -f1 )
        [[ "${kind}" == ${xcprov_type} ]] || continue
        uuid=$( echo "${prof}" | cut -f2 )
        team=$( echo "${prof}" | cut -f3 )
        bund=$( echo "${prof}" | cut -f4 )
        # Check if the bundle ID matches the app ID
        ( setopt -o globsubst; [[ "${bundled_app}" != ${bund#*.} ]] ) || break
        perr "warning: provisioning profile does not contain AppID: ${bundled_app} (${uuid})" |& tee -a "${logserv}"
        unset -v uuid kind team bund
      done < <( "${findprov[@]}" )

      if [[ -z ${uuid} || -z ${team} || -z ${kind} ]]; then
        if [[ -n ${global} ]]; then
          perr "error: no valid provisioning profile found for ${xcprov_type}" |& tee -a "${logserv}"
          return ${ERR_UNKNOWN}
        fi
        perr "warning: searching for ${xcprov_type} provisioning profile in global scope" |& tee -a "${logserv}"
        findprov=( provprof.sh -f $'%k\t%u\t%t\t%a' )
        global=true
        continue
      fi
      found=true
    done

  fi

  xcargs+=( -sdk "'iphoneos${1:-${sdk_version}}'" )
  xcargs+=( -project "'${2:-${proj_source}}'" )
  xcargs+=( -scheme "'${3:-${proj_scheme}}'" )
  xcargs+=( -configuration "'${4:-${test_config}}'" )
  xcargs+=( -destination "'${5:-${target_dest}}'" )
  xcargs+=( -jobs "'${numjobs}'" )
  # The following is required when auto-provisioning is enabled to allow
  # automatic renewal of expired profiles (and certificates).
  xcargs+=( -allowProvisioningUpdates -allowProvisioningDeviceRegistration )
  xcargs+=(
#    "'IPHONEOS_DEPLOYMENT_TARGET=${6:-${ios_version}}'"
#    "'CODE_SIGN_STYLE=MANUAL'"
#    "'CODE_SIGN_IDENTITY=Apple ${kind}'"
#    "'DEVELOPMENT_TEAM=${team}'"
#    "'PROVISIONING_PROFILE=${uuid}'"
  )

  echo xcodebuild ${xcargs} ${action}
}

installapp() {
  setopt localoptions pipefail
  local ipa=${1:?missing IPA path}
  local bundle
  bundle=$(ipa-bundle-identifier "${ipa}") || {
    perr "cannot determine Calculator bundle ID from IPA: ${ipa}"
    return ${ERR_PROJECT}
  }
  [[ -n ${bundle} ]] || {
    perr "Calculator IPA has an empty bundle ID: ${ipa}"
    return ${ERR_PROJECT}
  }
  local app_bundle=${bundle}
  local manifested_driver=''
  if [[ -r ${driverstate} ]]; then
    manifested_driver=$(jq -r '.runner_bundle // empty' "${driverstate}" 2>/dev/null) || manifested_driver=''
  fi
  if [[ ${bundle} == "${bundled_drv}" || ${bundle} == "${bundled_drv}.xctrunner" ||
      ( -n ${manifested_driver} && ${bundle} == "${manifested_driver}" ) ]]; then
    perr "refusing Calculator IPA that would replace the selected FMPS Test Driver: ${bundle}"
    return ${ERR_PROJECT}
  fi
  local removals
  removals=$(installed-conflict-apps "${target_dest#id=}" "${bundle}" "${ipa}") || return
  local -a rmipa=( ${=removals} )

  pout "terminating target app: ${bundle}"
  ios kill "${bundle}" --udid "${target_dest#id=}" |& tee -a "${logserv}" || true
  if [[ ${#rmipa[@]} -gt 0 ]]; then
    pout "removing conflicting target apps: ${rmipa[*]}"
    for conflict in "${rmipa[@]}"; do
      [[ "${conflict}" == "${app_bundle}" ]] || continue
      ios uninstall "${conflict}" --udid "${target_dest#id=}" |& tee -a "${logserv}" || return
    done
  fi
  ios install --path "${ipa}" --udid "${target_dest#id=}" |& tee -a "${logserv}" || return
  bundled_app=${app_bundle}
  app_id=${bundled_app}
  export FSDS_APP_ID=${bundled_app}
  persist-appium-config-value bundled_app "${bundled_app}"
}

persist-appium-config-value() {
  local key=${1:?missing Appium config key}
  local value=${2:?missing Appium config value}
  [[ ${key} == bundled_app || ${key} == bundled_drv ]] || return 1
  local env=${appium_config_env:-${cfgjson%.json}.env}
  [[ -r ${env} ]] || {
    perr "cannot persist ${key}; Appium config is unreadable: ${env}"
    return 1
  }
  local assignment tmp mode
  printf -v assignment 'export %s=%q' "${key}" "${value}"
  tmp=$(mktemp "${env}.XXXXXX") || return
  mode=$(/usr/bin/stat -f '%Lp' "${env}") || { rm -f "${tmp}"; return 1; }
  awk -v key="${key}" -v assignment="${assignment}" '
    BEGIN { found = 0; pattern = "^[[:space:]]*(export[[:space:]]+)?"; pattern = pattern key "=" }
    $0 ~ pattern { print assignment; found = 1; next }
    { print }
    END { if (!found) print assignment }
  ' "${env}" >"${tmp}" &&
    chmod "${mode}" "${tmp}" &&
    mv "${tmp}" "${env}" || {
      rm -f "${tmp}"
      perr "cannot persist ${key} to Appium config: ${env}"
      return 1
    }
}

sync-driver-bundle() {
  [[ -r ${driverstate} ]] || return 0
  local runner
  runner=$(jq -r '.runner_bundle // empty' "${driverstate}" 2>/dev/null) || return 0
  [[ -n ${runner} ]] || return 0
  export bundled_drv=${runner%.xctrunner}
}

driverinstalled() {
  local bundle=${1:?missing driver bundle ID}
  ios apps --udid "${target_dest#id=}" |
    jq -e --arg bundle "${bundle}" '.. | objects | (.bundleIdentifier? // .CFBundleIdentifier? // .bundleID?) | select(. == $bundle)' >/dev/null
}

preparedriver() {
  setopt localoptions pipefail
  [[ -r "${driverstate}" ]] || {
    perr "test driver manifest missing; use t to rebuild the driver"
    return ${ERR_PROJECT}
  }
  local source runner udid xctestrun runner_path
  source=$(jq -r '.source // empty' "${driverstate}") || return
  runner=$(jq -r '.runner_bundle // empty' "${driverstate}") || return
  udid=$(jq -r '.udid // empty' "${driverstate}") || return
  xctestrun=$(jq -r '.xctestrun // empty' "${driverstate}") || return
  runner_path=$(jq -r '.runner_path // empty' "${driverstate}") || return
  [[ -n ${runner} && ${udid} == "${target_dest#id=}" &&
      -r ${xctestrun} && -d ${runner_path} ]] || {
    perr "test driver artifacts missing or device mismatch; use t to rebuild the driver"
    return ${ERR_PROJECT}
  }
  local -a bundles=("${runner_path}"/PlugIns/*.xctest(N))
  [[ ${#bundles} -eq 1 ]] || {
    perr "test driver bundle missing; use t to rebuild the driver"
    return ${ERR_PROJECT}
  }
  if [[ ${appium_mode} == relaunch-test-driver && ${source} != "${test_driver_source}" ]]; then
    perr "selected test driver source does not match installed artifacts: ${source}"
    return ${ERR_PROJECT}
  fi
  driverinstalled "${runner}" || {
    perr "test driver is not installed on device: ${runner}"
    return ${ERR_PROJECT}
  }
  # Destination artifacts prevent Xcode from reinstalling the driver or Calculator.
  driverrun="${xctestrun%.xctestrun}.destination.xctestrun"
  plutil -convert json -o - "${xctestrun}" |
    jq -e --arg runner "${runner}" --arg app "${bundled_app}" '
      if .__xctestrun_metadata__.FormatVersion != 2 then error("unsupported xctestrun format") else . end |
      .TestConfigurations |= map(.TestTargets |= map(
        select(.TestHostBundleIdentifier == $runner) |
        if (.TestBundlePath | type) != "string" then error("test bundle path missing") else . end |
        .UseDestinationArtifacts = true |
        .TestBundleDestinationRelativePath = .TestBundlePath |
        .UITargetAppBundleIdentifier = $app |
        del(.TestHostPath, .TestBundlePath, .UITargetAppPath, .DependentProductPaths)
      )) |
      if ([.TestConfigurations[].TestTargets[]] | length) == 0
        then error("driver target missing from xctestrun") else . end' |
    plutil -convert xml1 -o "${driverrun}.new" - || return
  mv "${driverrun}.new" "${driverrun}" || return
  export bundled_drv=${runner%.xctrunner}
}

stopdriver() {
  local bundle
  bundle=$( jq -r '.runner_bundle // empty' "${driverstate}" 2>/dev/null )
  tmux kill-session -t "${driver_session}" 2>/dev/null || true
  [[ -z ${bundle} ]] || ios kill "${bundle}" --udid "${target_dest#id=}" |& tee -a "${logserv}" || true
}

wda_ready() {
  setopt localoptions pipefail
  curl -fsS --max-time 2 "${service_url}/status" 2>/dev/null |
    jq -e '.value.ready == true' >/dev/null 2>&1
}

waitforwda() {
  local timeout=$1 elapsed=0
  while (( elapsed <= timeout )); do
    wda_ready && return 0
    sleep 2
    elapsed=$(( elapsed + 2 ))
  done
  return 1
}

startdriverwatch() {
  if [[ ${driver_recovery:-false} != true ]] || truth "${lldb_managed:-false}"; then
    tmux kill-session -t "${watch_session}" 2>/dev/null || true
  fi
  [[ -r ${driverstate} ]] || return 0
  truth "${lldb_managed:-false}" && return 0
  exists "${watch_session}" && return 0
  tmux new-session -d -s "${watch_session}" -- \
    zsh -c 'exec zsh "$1" --watch-driver "$2" >>"$3" 2>&1' \
      watchdog "${self}" "${appium_config_env:-${cfgjson%.json}.env}" "${recoverylog}" \; \
    set-option -w -t "${watch_session}" remain-on-exit off
}

watchdriver() {
  local misses=0 attempts=0 healthy_since=-1 failed_since=-1 exhausted=false owner result
  pout "WDA watchdog started"
  while true; do
    sleep 2
    if [[ -d ${provisionlock} ]]; then
      owner=''
      [[ ! -r ${provisionpid} ]] || owner=$(<"${provisionpid}")
      if [[ ${owner} != <-> ]] || kill -0 "${owner}" 2>/dev/null; then
        misses=0
        healthy_since=-1
        failed_since=-1
        continue
      fi
    fi
    exists "${session}" || return 0
    [[ -r ${driverstate} ]] || return 0
    [[ ! -r ${appium_config_env} ]] || . "${appium_config_env}"
    truth "${lldb_managed:-false}" && return 0
    [[ -n ${service_url} ]] || service_url="http://localhost:${driver_port:-8100}"
    if wda_ready && exists "${driver_session}"; then
      misses=0
      failed_since=-1
      (( healthy_since >= 0 )) || healthy_since=${SECONDS}
      if (( SECONDS - healthy_since >= 120 )); then
        attempts=0
        exhausted=false
      fi
      continue
    fi
    healthy_since=-1
    (( failed_since >= 0 )) || failed_since=${SECONDS}
    misses=$((misses + 1))
    if exists "${driver_session}"; then
      (( misses >= 3 )) || continue
      # shortcut: /status blocks with commands; raise the 300s grace if supported commands exceed it.
      if (( SECONDS - failed_since < 300 )) &&
          ! grep -Eq 'libc\+\+abi: terminating|Restarting after unexpected exit|Test crashed with signal|TEST EXECUTE FAILED' "${logdrvr}" 2>/dev/null; then
        continue
      fi
    fi
    if (( attempts >= 3 )); then
      if ! ${exhausted}; then
        perr "WDA automatic recovery exhausted (3 attempts); use T after correcting the failure"
        exhausted=true
      fi
      continue
    fi
    pout "WDA unavailable; automatic relaunch attempt $((attempts + 1))/3"
    result=0
    zsh "${self}" --recover-driver "${appium_config_env}" || result=$?
    # Lock contention is not a failed recovery attempt.
    (( result != ERR_EXELOCK )) || continue
    attempts=$((attempts + 1))
    misses=0
    failed_since=-1
    if (( result == 0 )); then
      pout "WDA recovery completed; clients must create new Appium sessions"
    else
      perr "WDA recovery failed with status ${result}"
    fi
    sleep 10
  done
}

launchdriver() {
  preparedriver || return

  pout "launching FMPS Test Driver with Xcode: ${bundled_drv}"
  stopdriver
  rotatelogs "${logdrvr}" || return
  tmux new-session -d -s "${driver_session}" -- \
    zsh -c 'exec xcodebuild test-without-building -xctestrun "$1" -destination "$2" >> "$3" 2>&1' \
      driver "${driverrun}" "${target_dest}" "${logdrvr}" || return

  local elapsed=0 timeout=120 url
  while (( elapsed < timeout )); do
    url=$( grep -oE 'ServerURLHere->https?://[^<]+<-ServerURLHere' "${logdrvr}" 2>/dev/null | head -1 )
    if [[ -n ${url} ]]; then
      url=${url#ServerURLHere->}
      url=${url%<-ServerURLHere}
      export service_url=$( sed -E 's#^([^/]+//)[^:]+(:[0-9]+)$#\1localhost\2#' <<< "${url}" )
      if waitforwda 10; then
        return 0
      fi
      pout "WDA is not ready at ${service_url}; reloading iOS tunnel and USB proxy"
      reload-ios-tunnel || return ${ERR_USBPROX}
      waitforwda 30 && return 0
      perr "WDA did not become ready at ${service_url} after reloading the iOS tunnel and USB proxy"
      return ${ERR_USBPROX}
    fi
    exists "${driver_session}" || {
      perr "FMPS Test Driver exited before publishing its service URL"
      return ${ERR_COMPILE}
    }
    sleep 2
    elapsed=$(( elapsed + 2 ))
  done
  perr "timed out waiting for FMPS Test Driver service URL"
  tmux kill-session -t "${driver_session}" 2>/dev/null || true
  return ${ERR_COMPILE}
}

builddriver() {
  setopt localoptions pipefail

  [[ -n ${test_driver_source} ]] || {
    perr "test driver source is not selected; use t to select a driver source"
    return ${ERR_PROJECT}
  }
  pout "building FMPS Test Driver from: ${test_driver_source}"
  local retained_run='' builddir=${driverderived}
  if [[ -r ${driverstate} ]]; then
    retained_run=$(jq -r '.xctestrun // empty' "${driverstate}") || return
  fi
  # Alternate build slots so a failed replacement cannot erase retained artifacts.
  [[ ${retained_run:A} != "${driverderived:A}/"* ]] || builddir="${driverderived}.next"
  local driverderived=${builddir}
  mkdir -p "${driverderived}" "${driverstate%/*}" || return
  rm -rf "${driverderived}" || return
  mkdir -p "${driverderived}" || return
  local driver_scheme=${test_driver_scheme:-'FMPS Calculator'}
  # Preserve Calculator's linker settings while enabling exception unwinding in WDA.
  # Select the setting name first: :default=$(inherited) concatenates list-valued flags.
  local driver_ldflags="'FSDS_DRIVER_LDFLAGS_WebDriverAgent=FSDS_WDA_LINKER_FLAGS' 'FSDS_DRIVER_LDFLAGS_FMPS_Test_Driver=FSDS_WDA_LINKER_FLAGS' 'FSDS_WDA_LINKER_FLAGS=-all_load' 'OTHER_LDFLAGS=\$(\$(FSDS_DRIVER_LDFLAGS_\$(TARGET_NAME:c99extidentifier):default=inherited))'"
  eval "$( build '' "${test_driver_source}" "${driver_scheme}" "${test_config}" '' '' build-for-testing ) ${driver_ldflags} -derivedDataPath '${driverderived}'" |& tee -a "${logdrvr}" || return
  local -a runs=("${driverderived}"/Build/Products/*.xctestrun(N))
  [[ ${#runs} -eq 1 ]] || {
    perr "expected one generated xctestrun, found ${#runs}"
    return ${ERR_COMPILE}
  }

  local products="${driverderived}/Build/Products/${test_config}-iphoneos"
  local -a runners=( "${products}"/**/*Runner.app(N) )
  [[ ${#runners[@]} -eq 1 ]] || {
    perr "expected one generated test Runner app, found ${#runners[@]}"
    return ${ERR_COMPILE}
  }
  local runner=${runners[1]}
  local -a tests=( "${runner}/PlugIns"/*.xctest(N) )
  [[ ${#tests[@]} -eq 1 ]] || {
    perr "expected one generated XCTest bundle, found ${#tests[@]}"
    return ${ERR_COMPILE}
  }
  local bundle
  bundle=$(plutil -extract CFBundleIdentifier raw -o - "${runner}/Info.plist") || return
  local xctestrun=${runs[1]}
  pout "installing FMPS Test Driver: ${bundle}"
  ios install --path "${runner}" --udid "${target_dest#id=}" |& tee -a "${logserv}" || return

  local state="${driverstate}.new"
  jq -n --arg source "${test_driver_source}" --arg runner "${bundle}" \
    --arg xctestrun "${xctestrun}" --arg runner_path "${runner}" --arg config "${test_config}" --arg udid "${target_dest#id=}" \
    '{source:$source,runner_bundle:$runner,xctestrun:$xctestrun,runner_path:$runner_path,configuration:$config,udid:$udid}' > "${state}" || return
  mv "${state}" "${driverstate}" || return
  export bundled_drv=${bundle%.xctrunner}
  persist-appium-config-value bundled_drv "${bundled_drv}" || return
  launchdriver
}

makeipa() {
  local proj=${proj_source##*/}
  local base=${self##*/}
  local ipapath="${expoipa%/*}/${base%.*sh}-${date}"
  local builder=$( srcroot ) || return ${ERR_PROJECT}

  prepsdk &> /dev/null

  builder="${builder}/Extra/Scripts/build-release.sh"
  [ -x "${builder}" ] || return ${ERR_BUILDER}

  local -a verbose
  ! truth ${trace_agent} || verbose=( -V 2 )

  # build and symlink to the common path expected by Appium / test scripts
  "${builder}" -Z -c release -x "${proj_scheme}, ${proj_config}" -k "iphoneos${sdk_version}" -i "${ios_version}" "${verbose[@]}" "${ipapath}" &&
    ipa=$( find "${ipapath}" -type f -name '*.ipa' ) &&
      ln -sf "${ipa}" "${expoipa}" &&
        installapp "${ipa}"
}

exists() {
  tmux has-session -t "$1" 2>/dev/null
}

contain() {
  local args="tmux -u2 attach-session -t ${1:-}"
  case ${TERM:-} in
    alacritty*)
      local -a opts=(
        #--hold
        -o 'env.FSDS_OMZ_UPDATE_SKIP="true"'
      )
      "${TERM}" msg create-window "${opts[@]}" -e zsh -ic "${args}"
    ;;
    tmux*)
      ${args}
    ;;
    #xterm*) # Requires X11 (possible on macOS, but not likely)
    #  "${TERM}" -maximized -u8 \
    #    -e zsh -ic "${args}"
    *) # Default to macOS built-in Terminal.app,
       # which apparently can only be launched via AppleScript:
      osascript -e "tell app \"Terminal\" to do script \"zsh -ic '${args}'\""
    ;;
  esac
}

attach() {

  # set remain-on-exit
  tmux set-option -t "${1}" remain-on-exit on

	if [[ "x${TMUX:-}" == x ]]; then
    contain "$1"
  else
    tmux -u2 switch-client -t "$1"
  fi
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
  # Atomic lock acquisition using noclobber — avoids TOCTOU race if two
  # instances run concurrently (> with noclobber fails if file exists).
  if ! ( set -o noclobber; : > "${cfglock}" ) 2>/dev/null; then
    perr 'config: appium config already locked' |& tee -a "${logserv}"
    return ${ERR_EXELOCK}
  fi
  config_locked=true

  # Always define the following options
  local opts=(
    # Required capabilities
    'automationName: "XCUITest"'
    'platformVersion: env.sdk_version'

    #'useNewWDA: true'
    #'useSimpleBuildTest: true'

    # Appium/WebDriverAgent optimizations
    #'shouldUseSingletonTestManager: true'
    #'waitForIdleTimeout: 100'
    #'waitForQuiescence: true'
    #'useNativeCachingStrategy: true'
    'screenshotQuality: 2' # [0=highest .. 2=lowest]

    # The following is required when auto-provisioning is enabled to allow
    # automatic renewal of expired profiles (and certificates).
    'allowProvisioningUpdates: true'
    'allowProvisioningDeviceRegistration: true'

    'showXcodeLog: false'

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
    [showIOSLog]=trace_agent
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
    if [ x${dev_id} != x ]; then
      export target_udid=${dev_id}
      opts+=( 'udid: env.dev_id' )
    else
      opts+=( 'deviceName: env.target_dest' )
    fi
  fi

  [ x${app_id} = x ] || export bundled_app=${app_id}
  opts+=(
    'bundleId: env.bundled_app'
    'noReset: true'
    'autoLaunch: true' # launch app under test (not test driver)
    'shouldTerminateApp: true'
    'forceAppLaunch: true'
    #'printPageSourceOnFindFailure: true'
    'localizableStringsDir: "Base.lproj"'
    'useNativeCachingStrategy: false'
    'mjpegServerPort: 9100'
  )
  local query=$(
    jqfilter "{ ${(j:,:)opts} }" server default-capabilities appium:options
  )
  if ! jq "del(.server.\"default-capabilities\".app, .server.\"default-capabilities\".\"appium:app\", .server.\"default-capabilities\".\"appium:options\".app, .server.\"default-capabilities\".\"appium:options\".\"appium:app\") | ${query}" "${cfgjson}" > "${cfglock}"; then
    perr "config: failed to apply JSON filter: ${query}" |& tee -a "${logserv}"
    return 1
  fi
  mv "${cfglock}" "${cfgjson}" || return
  config_locked=false
}

# debugwatch arms an LLDB watcher, in a dedicated tmux window, that attaches
# to the app-under-test on the physical device and breaks on all uncaught
# ObjC/C++ exceptions. Enabled via ${lldb_managed} (see --lldb-managed).
#
debugwatch() {

  # Kill any stale Debugger window left over from a previous run.
  tmux kill-window -t "${session}:Debugger" 2>/dev/null || true

  # LLDB cannot connect to a device by UDID.  Start Apple's debugserver over
  # usbmux, then connect LLDB to the local TCP endpoint it provides.  The
  # forwarder must remain alive for the duration of the LLDB session.
  local debugserver_python=${pymobiledevice3_python:-/opt/fsds/lib/python/venv/bin/python}
  local debugserver_port=${lldb_debugserver_port:-12345}
  local debugserver_cmd="${debugserver_python} -m pymobiledevice3 --udid '${target_udid}' developer debugserver start-server ${debugserver_port}"
  local lldbcmd="lldb -o \"platform select remote-ios\" -o \"process connect connect://127.0.0.1:${debugserver_port}\" -o \"process attach --waitfor --name '${proj_scheme}'\" -o \"breakpoint set -E all\" -o \"continue\""
  local watchcmd="${debugserver_cmd} & debugserver_pid=\$!; trap 'kill \${debugserver_pid} 2>/dev/null || true' EXIT INT TERM; ready=; for attempt in {1..20}; do kill -0 \${debugserver_pid} 2>/dev/null || break; nc -z 127.0.0.1 ${debugserver_port} 2>/dev/null && { ready=true; break; }; sleep 0.5; done; [[ \${ready} == true ]] || { echo 'debugserver did not open its local port'; wait \${debugserver_pid}; exit 1; }; ${lldbcmd}"

  # -a: insert after the target window instead of at its own index, which is
  # already in use by the "${session}" window created by create()'s new-session.
  tmux new-window -a -t "${session}" -n Debugger -- zsh -ic "${watchcmd}" |& tee -a "${logserv}"
}

create() {
  # exit immediately if any command results in error status
  # (the always block restores +e so callers aren't affected)
  {
  set -e

  # Only rotate logs whose writers are restarted here.
  rotatelogs "${logserv}" "${logappd}" || return
  prune "${logsapp}/backup"

  prune "${expodir}" 'appiumd-*'

  if [[ x${target_dest} != x ]]; then
    #reload-ios-tunnel
    #sleep 3
    #if tun=$( ios tunnel ls --udid "${target_dest#id=}" | jq -r '.[] | select( .udid == "'"${target_dest#id=}"'" ) | .udid' ); then
    if tun=$( ios tunnel ls --udid "${target_dest#id=}" | jq -r '.[]|.udid' ); then
      if [[ -z ${tun} ]]; then
        echo
        perr "create: no iOS tunnel found for device: ${target_dest}" #| tee -a "${logdrvr}"
        echo
        echo "  verify the test iPad device is connected and powered on,"
        echo "  which will require someone physically on-site to check."
        echo
        return ${ERR_USBPROX}
      fi
      if [[ "${tun}" != "${target_dest#id=}" ]]; then
        echo
        perr "create: invalid iOS tunnel: (${tun} != ${target_dest})" #| tee -a "${logdrvr}"
        echo
        echo "  verify the launchd service is loaded and enabled (ios-tunnel.plist)"
        echo "  you can restart it from within emt as follows:"
        echo
        echo "  Press [Ctrl-A] then [:] to enter command mode, then type:"
        echo "    ${FSDS_PREFIX}/bin/reload-ios-tunnel"
        echo
        return ${ERR_USBPROX}
      fi
    fi
  fi

  # A restart skips the Calculator build/install; Driver lifecycle is explicit.
  if [[ x${appium_restart} == x ]]; then
    # build and install the Calc App .ipa for installation on target device
    makeipa || return ${ERR_COMPILE}
  fi
  export xcprov_type='Development'

  [[ -n ${service_url} ]] || export service_url="http://localhost:${driver_port:-8100}"
  if ! wda_ready; then
    perr "WebDriverAgent is not available at ${service_url}; Calculator installation is preserved. Use t to select and start the FMPS Test Driver."
  fi
  sync-driver-bundle || return ${ERR_CFGFILT}
  config || return ${ERR_CFGFILT}
  local args=(
    --address "$( ifaddr "${listen_name}" )"
    --port "${listen_port}"
  )

  # fire off Appium in its own tmux session
  tmux \
    new-session \
      -ADX -d -c "${2}" -s "${1}" -n "${1}" -- \
        zsh -ic "appium server ${args} --config '${cfgjson}' |&
          tee -a '${logserv}'"

  # Arm the LLDB watcher now that the "${1}" tmux session exists and
  # ${target_udid} has been set (both required by debugwatch).
  truth ${lldb_managed} && debugwatch
  startdriverwatch || return
  return 0

  } always {
    set +e
  }
}

show-network-arch() {
  local -a deps=(
    listen_name
    listen_port
    service_url
    target_dest
  )
  for dep in "${deps[@]}"; do
    if [[ x${${dep}:-} == x ]]; then
      perr "show-network-arch: required variable uninitialized: ${dep}" |& tee -a "${logserv}"
      return 1
    fi
  done
}

provision() {
  mkdir -p "${provisionlock%/*}"
  if ! mkdir "${provisionlock}" 2>/dev/null; then
    local owner
    [[ ! -r ${provisionpid} ]] || owner=$( < "${provisionpid}" )
    if [[ ${owner} == <-> ]] && ! kill -0 "${owner}" 2>/dev/null; then
      rm -f "${provisionpid}"
      rmdir "${provisionlock}" 2>/dev/null || true
      mkdir "${provisionlock}" 2>/dev/null || {
        perr "another Appium provisioning operation is already active"
        return ${ERR_EXELOCK}
      }
    else
      perr "another Appium provisioning operation is already active"
      return ${ERR_EXELOCK}
    fi
  fi
  print -r -- $$ > "${provisionpid}"
  provision_locked=true
  if [[ ${driver_recovery:-false} == true ]]; then
    exists "${session}" || return ${ERR_EXELOCK}
    truth "${lldb_managed:-false}" && return ${ERR_EXELOCK}
    if wda_ready && exists "${driver_session}"; then
      return 0
    fi
  fi

  case ${appium_mode:-full} in
    full) unset -v appium_restart ;;
    restart|test-driver-only|relaunch-test-driver|activate-ipa)
      export appium_restart=true
      ;;
  esac
  case ${appium_mode:-full} in
    full|restart)
      ;;
    test-driver-only)
      stopdriver
      builddriver || return
      ;;
    relaunch-test-driver)
      launchdriver || return
      ;;
    activate-ipa)
      [[ -r ${target_app_ipa} ]] || {
        perr "target IPA not found: ${target_app_ipa}"
        return ${ERR_PROJECT}
      }
      installapp "${target_app_ipa}" || return
      ;;
    *)
      perr "unsupported Appium mode: ${appium_mode}"
      return ${ERR_UNKNOWN}
      ;;
  esac
  if [[ ${driver_recovery:-false} == true ]]; then
    exists "${session}" || return ${ERR_EXELOCK}
  fi
  tmux kill-session -t "${session}" 2>/dev/null || true
  create "${session}" "${startin}"
}

# ------------------------------------------------------------------------------
#  main
# ------------------------------------------------------------------------------

if [[ ${1:-} == --watch-driver ]]; then
  watchdriver
  exit $?
fi
if [[ ${1:-} == --recover-driver ]]; then
  export appium_mode=relaunch-test-driver
  driver_recovery=true
fi

trap "
appiumd_exit_status=\${?}
if [[ \${config_locked:-false} == true ]]; then rm -f '${cfglock}'; fi
if [[ -n \${provision_locked:-} ]]; then
  rm -f '${provisionpid}'
  rmdir '${provisionlock}' 2>/dev/null || true
fi
if [[ \${appiumd_exit_status} -eq 0 ]] && exists '${session}'; then
  [[ ${-} != *i* ]] || attach '${session}'
fi
" EXIT

case ${appium_mode:-} in
  test-driver-only|relaunch-test-driver|activate-ipa|full|restart)
    provision
    exit $?
    ;;
  '')
    if [[ ${FSDS_APPIUM_LAUNCHER:-} != launchctl ]]; then
      provision
      exit $?
    fi
    ;;
esac

#create "${session}" "${startin}"
case ${FSDS_APPIUM_LAUNCHER} in
  launchctl)
    export appium_restart=true
    if exists "${session}"; then
      pout "appiumd: existing session detected; LaunchAgent will wait until it ends before starting" |& tee -a "${logserv}"
      while exists "${session}"; do
        sleep 1
      done
      pout "appiumd: existing session ended; LaunchAgent resuming startup" |& tee -a "${logserv}"
    fi
    ;;
  *)
    if exists "${session}"; then
      pout "appiumd: existing session detected; re-attaching" |& tee -a "${logserv}"
      [[ ${-} != *i* ]] || attach "${session}"
      exit 0
    fi
    ;;
esac

exists "${session}" || create "${session}" "${startin}"


set +x
