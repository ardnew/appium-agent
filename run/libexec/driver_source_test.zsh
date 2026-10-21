#!/bin/zsh
set -e

script=${1:-${0:A:h}/appiumd.zsh}
# Load only functions; never execute the launcher's live service operations.
load_function() {
 local line definition='' collecting=false
 while IFS= read -r line; do
  if [[ ${line} == "${1}() {" ]]; then collecting=true; fi
  if ${collecting}; then
   definition+="${line}"$'\n'
   [[ ${line} != '}' ]] || break
  fi
 done <"${script}"
 [[ -n ${definition} ]]
 eval "${definition}"
}
for name in build builddriver preparedriver; do load_function "${name}"; done

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
proj_source="${tmp}/ASES (3.6) Runway Release.xcodeproj"
test_driver_source="${tmp}/test-xctest-proxy.xcodeproj"
proj_scheme='Calculator Scheme'
test_driver_scheme='Driver Scheme'
test_config=Release
sdk_version=26.2
numjobs=1
xcbuild_act=build
bundled_app=calculator
bundled_drv=driver
target_dest=id=device
appium_mode=test-driver-only
driverderived="${tmp}/Retained Products"
driverstate="${tmp}/driver.json"
logdrvr="${tmp}/driver.log"
logserv="${tmp}/session.log"
ERR_PROJECT=127
ERR_COMPILE=123
auto_provision=''
install_failure=false
build_failure=false
mkdir -p "${proj_source}" "${test_driver_source}"
print -- ASES >"${proj_source}/${proj_scheme}.payload"
print -- test-xctest-proxy >"${test_driver_source}/${test_driver_scheme}.payload"
prepsdk() { :; }
pout() { print -r -- "$*"; }
perr() { print -ru2 -- "$*"; }
persist-appium-config-value() { :; }

# The compiler fixture builds the payload belonging to the selected project/scheme.
xcodebuild() {
 local project='' scheme='' configuration=''
 while (($#)); do
  case ${1} in
  -project)
   project=${2}
   shift 2
   ;;
  -scheme)
   scheme=${2}
   shift 2
   ;;
  -configuration)
   configuration=${2}
   shift 2
   ;;
  *) shift ;;
  esac
 done
 [[ -r "${project}/${scheme}.payload" ]] || return 41
 [[ ${build_failure} == false ]] || return 43
 local products="${driverderived}/Build/Products"
 local runner="${products}/${configuration}-iphoneos/Driver-Runner.app"
 mkdir -p "${runner}/PlugIns/driver.xctest"
 cp "${project}/${scheme}.payload" "${runner}/branch"
 print -- '{"CFBundleIdentifier":"driver.xctrunner"}' >"${runner}/Info.plist"
 print -- '{"__xctestrun_metadata__":{"FormatVersion":2},"TestConfigurations":[{"TestTargets":[{"TestHostBundleIdentifier":"driver.xctrunner","TestBundlePath":"__TESTHOST__/PlugIns/driver.xctest"}]}]}' >"${products}/Driver.xctestrun"
}
ios() {
 [[ ${1} == install && ${2} == --path ]] || return 40
 ${install_failure} && return 42
 cp "${3}/branch" "${tmp}/installed-driver"
}
driverinstalled() { [[ -r ${tmp}/installed-driver ]]; }
launchdriver() { preparedriver; }

builddriver || exit 1
[[ $(<"${tmp}/installed-driver") == test-xctest-proxy ]]
[[ $(jq -r .source "${driverstate}") == "${test_driver_source}" ]]
[[ ${proj_source} == "${tmp}/ASES (3.6) Runway Release.xcodeproj" ]]

# Relaunch accepts the installed Driver source, not the independent Calculator.
appium_mode=relaunch-test-driver
preparedriver || exit 1
saved_manifest=$(<"${driverstate}")
ln -s "${tmp}" "${tmp}/alias"
driverderived="${tmp}/alias/Retained Products"
test_driver_source="${tmp}/another-driver.xcodeproj"
if preparedriver 2>/dev/null; then exit 1; fi

# A failed replacement cannot claim that the new branch is installed.
mkdir -p "${test_driver_source}"
print -- replacement >"${test_driver_source}/${test_driver_scheme}.payload"
install_failure=true
if builddriver; then exit 1; fi
[[ $(<"${tmp}/installed-driver") == test-xctest-proxy ]]
[[ $(<"${driverstate}") == "${saved_manifest}" ]]
test_driver_source=$(jq -r .source "${driverstate}")
old_runner=$(jq -r .runner_path "${driverstate}")
[[ $(<"${old_runner}/branch") == test-xctest-proxy ]]
preparedriver || exit 1

# A failed compiler must leave the previously installed Driver relaunchable.
install_failure=false
build_failure=true
if builddriver; then exit 1; fi
[[ $(<"${driverstate}") == "${saved_manifest}" ]]
[[ $(<"${old_runner}/branch") == test-xctest-proxy ]]
preparedriver || exit 1
build_failure=false

# A successful replacement becomes relaunchable and survives the next failed build.
test_driver_source="${tmp}/another-driver.xcodeproj"
builddriver || exit 1
[[ $(<"${tmp}/installed-driver") == replacement ]]
preparedriver || exit 1
saved_manifest=$(<"${driverstate}")
old_runner=$(jq -r .runner_path "${driverstate}")
build_failure=true
if builddriver; then exit 1; fi
[[ $(<"${driverstate}") == "${saved_manifest}" ]]
[[ $(<"${old_runner}/branch") == replacement ]]
preparedriver || exit 1
build_failure=false

# An absent Driver source cannot fall back to Calculator or erase retained artifacts.
test_driver_source=''
if builddriver 2>/dev/null; then exit 1; fi
test_driver_source=$(jq -r .source "${driverstate}")
preparedriver || exit 1
[[ $(<"${driverstate}") == "${saved_manifest}" ]]
print -- 'PASS: selected Driver branch built/installed independently, relaunch matched its source, failed replacements preserved attribution.'
