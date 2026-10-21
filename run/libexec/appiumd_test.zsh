#!/bin/zsh
set -e

script=${1:-${0:A:h}/appiumd.zsh}
# Load functions without executing top-level service operations.
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
for name in rotatelogs jqfilter config create preparedriver wda_ready waitforwda launchdriver builddriver provision installapp persist-appium-config-value sync-driver-bundle; do load_function "${name}"; done

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
tmux_actions=${tmp}/tmux-actions
logsapp=${tmp}/appium
mkdir -p "${logsapp}"
logserv=${logsapp}/session.log
logappd=${logsapp}/server.log
logdrvr=${logsapp}/driver.log
cfgjson=${tmp}/config.json
cfglock=${tmp}/session.lock
appium_config_env=${tmp}/config.env
startin=${tmp}
listen_name=lo0
listen_port=4723
session=Appium
driver_session=Driver
target_dest=''
appium_restart=true
service_url=http://localhost:8100
driver_port=8100
sdk_version=18.0
dev_id=device
app_id=uploaded.calculator
bundled_app=uploaded.calculator
bundled_drv=driver
trace_agent=false
lldb_managed=false
expodir=${tmp}/ipa
date=restart
ERR_PROJECT=127
ERR_USBPROX=124
reload_calls=0
wda_response='{"value":{"ready":true}}'
reload_response='{"value":{"ready":true}}'
ERR_COMPILE=123
prune() { :; }
startdriverwatch() { :; }
truth() { return 1; }
ifaddr() { print -- 127.0.0.1; }
pout() { :; }
curl() {
 [[ $* == *"${service_url}/status" ]] || return 1
 print -r -- "${wda_response}"
}
sleep() { :; }
reload-ios-tunnel() {
 reload_calls=$((reload_calls + 1))
 print -- reload-tunnel >>"${tmp}/actions"
 wda_response=${reload_response}
}
perr() { print -u2 -- "$*"; }
tmux() {
 if [[ $* == *kill-session* ]]; then print -r -- "$*" >>"${tmux_actions}"; fi
 if [[ $* == *test-without-building* ]]; then
  exec 4>>"${logdrvr}"
  print -- 'ServerURLHere->http://127.0.0.1:8100<-ServerURLHere' >&4
 fi
}
stopdriver() { print -- stop >>"${tmp}/actions"; }
driverinstalled() { return 0; }
print -r -- '{"server":{"default-capabilities":{"app":"legacy.ipa","appium:app":"namespaced.ipa","appium:options":{"app":"nested.ipa","appium:app":"nested-namespaced.ipa"}}}}' >"${cfgjson}"
print -r -- "export bundled_app='uploaded.calculator'" >"${appium_config_env}"

print -- old-session >"${logserv}"
print -- old-server >"${logappd}"
print -- launch-agent-output >"${logsapp}/stdout.log"
print -- old-driver >"${logdrvr}"
exec 3>>"${logdrvr}"
create "${session}" "${startin}" || exit 1
[[ ! -s ${tmp}/actions ]]
jq -e '(.server."default-capabilities".app | not) and (.server."default-capabilities"."appium:app" | not) and (.server."default-capabilities"."appium:options".app | not) and (.server."default-capabilities"."appium:options"."appium:app" | not) and .server."default-capabilities"."appium:options".bundleId == "uploaded.calculator"' "${cfgjson}" >/dev/null
set -e
print -- live-driver-output >&3
exec 3>&-
[[ $(<"${logdrvr}") == $'old-driver\nlive-driver-output' ]]
[[ ! -f ${logsapp}/backup/driver.restart.log ]]
[[ $(<"${logsapp}/stdout.log") == launch-agent-output ]]
[[ $(<"${logsapp}/backup/session.restart.log") == old-session ]]
[[ $(<"${logsapp}/backup/server.restart.log") == old-server ]]

# A generated run may include other test targets and a Calculator dependency.
print -- '{"__xctestrun_metadata__":{"FormatVersion":2},"TestConfigurations":[{"TestTargets":[{"TestHostBundleIdentifier":"driver.xctrunner","TestBundlePath":"__TESTHOST__/PlugIns/driver.xctest","TestHostPath":"__TESTROOT__/Runner.app","UITargetAppPath":"__TESTROOT__/Calculator.app","DependentProductPaths":["Calculator.app"],"PreferredScreenCaptureFormat":"screenRecording"},{"TestHostBundleIdentifier":"unrelated.xctrunner"}]}]}' >"${tmp}/seed.json"
driverderived="${tmp}/Retained Products"
driverstate=${tmp}/driver.json
proj_source=project
test_driver_source=driver-project
proj_scheme='Calculator Scheme'
test_driver_scheme='Driver Scheme'
test_config=Release
bundled_app=uploaded.calculator
bundled_drv=driver
appium_mode=test-driver-only
target_dest=id=device
# Simulate compiler output, not the lifecycle implementation under test.
fake_build() {
 local products="${driverderived}/Build/Products"
 local runner="${products}/Release-iphoneos/Driver-Runner.app"
 mkdir -p "${runner}/PlugIns/driver.xctest"
 print -- '{"CFBundleIdentifier":"driver.xctrunner"}' >"${runner}/Info.plist"
 plutil -convert xml1 -o "${products}/Driver.xctestrun" "${tmp}/seed.json"
}
build() { print -- fake_build; }
install_failure=false
uninstall_failure=false
ios() {
 if [[ ${1} == tunnel ]]; then
  print -- '[{"udid":"device"}]'
 else
  print -r -- "$*" >>"${tmp}/actions"
  if [[ ${1} == install && ${install_failure} == true ]]; then
   print -u2 -- 'installation denied: test sentinel'
   return 42
  fi
  if [[ ${1} == uninstall && ${uninstall_failure} == true ]]; then
   print -u2 -- 'uninstall denied: test sentinel'
   return 43
  fi
 fi
}
ipa-bundle-identifier() { print -- "${incoming_bundle}"; }
incoming_bundle=actual.calculator
install_conflicts=''
installed-conflict-apps() {
 [[ -z ${install_conflicts} ]] || print -- "${install_conflicts}"
 return 0
}
date=new-driver
builddriver || exit 1
[[ ${reload_calls} -eq 0 ]]
[[ $(jq -r .xctestrun "${driverstate}") == "${driverderived}/Build/Products/Driver.xctestrun" ]]
[[ $(jq -r .source "${driverstate}") == "${test_driver_source}" ]]
plutil -convert json -o - "${driverrun}" | jq -e '
 [.TestConfigurations[].TestTargets[]] as $targets |
 ($targets | length) == 1 and
 $targets[0].UseDestinationArtifacts == true and
 $targets[0].UITargetAppBundleIdentifier == "uploaded.calculator" and
 $targets[0].TestBundleDestinationRelativePath == "__TESTHOST__/PlugIns/driver.xctest" and
 ($targets[0] | has("UITargetAppPath") or has("TestHostPath") or has("DependentProductPaths") | not) and
 $targets[0].PreferredScreenCaptureFormat == "screenRecording"' >/dev/null
[[ ${bundled_app} == uploaded.calculator && ${proj_source} == project ]]
[[ $(<"${appium_config_env}") == *"bundled_drv=driver"* ]]
[[ $(<"${tmp}/actions") == *'install --path '*Driver-Runner.app* ]]
[[ $(<"${tmp}/actions") != *Calculator* ]]
[[ $(<"${logsapp}/backup/driver.new-driver.log") == *live-driver-output* ]]
target_dest=''
create "${session}" "${startin}" || exit 1
set -e
print -- managed-runtime-output >&4
exec 4>&-
[[ $(<"${logdrvr}") == *managed-runtime-output ]]

# A source Calc install uses the app-only installer without touching live Driver artifacts.
target_dest=id=device
source_ipa=${tmp}/source.ipa
target_app_ipa=${tmp}/stale-upload.ipa
touch "${source_ipa}" "${target_app_ipa}"
incoming_bundle=uploaded.calculator
appium_restart=''
appium_mode=full
saved_manifest=$(<"${driverstate}")
cp "${driverderived}/Build/Products/Driver.xctestrun" "${tmp}/before-source.xctestrun"
saved_driver_log=$(<"${logdrvr}")
provisionlock=${tmp}/provision.lock
provisionpid=${provisionlock}/pid
bundled_drv=stale.driver
makeipa() { installapp "${source_ipa}" && print -- source-calc-build >>"${tmp}/actions"; }
: >"${tmp}/actions"
: >"${tmux_actions}"
provision || exit 1
[[ $(<"${tmux_actions}") == *'kill-session -t Appium'* && $(<"${tmux_actions}") != *Driver* ]]
[[ $(<"${tmp}/actions") == *"install --path ${source_ipa}"* ]]
[[ $(<"${tmp}/actions") != *"${target_app_ipa}"* && $(<"${tmp}/actions") != *stop* && $(<"${tmp}/actions") != *driver* && $(<"${tmp}/actions") != *uninstall* ]]
[[ $(<"${driverstate}") == "${saved_manifest}" ]]
cmp -s "${tmp}/before-source.xctestrun" "${driverderived}/Build/Products/Driver.xctestrun"
[[ $(<"${logdrvr}") == "${saved_driver_log}" ]]
[[ ${bundled_drv} == driver && $(<"${appium_config_env}") == *"bundled_drv=driver"* ]]
jq -e '.server."default-capabilities"."appium:options"."updatedWDABundleId" == "driver"' "${cfgjson}" >/dev/null
rm -rf "${provisionlock}"

# Restart is serialized but must not rebuild or reinstall Calculator.
appium_mode=restart
appium_restart=''
: >"${tmp}/actions"
: >"${tmux_actions}"
provision || exit 1
[[ ! -s ${tmp}/actions && ${bundled_app} == uploaded.calculator ]]
[[ $(<"${tmux_actions}") == *'kill-session -t Appium'* && $(<"${tmux_actions}") != *Driver* ]]
rm -rf "${provisionlock}"
incoming_bundle=driver.xctrunner
saved_config=$(<"${appium_config_env}")
: >"${tmp}/actions"
if installapp "${source_ipa}" 2>/dev/null; then exit 1; fi
[[ ! -s ${tmp}/actions && $(<"${appium_config_env}") == "${saved_config}" ]]
incoming_bundle=driver
if installapp "${source_ipa}" 2>/dev/null; then exit 1; fi
[[ ! -s ${tmp}/actions && $(<"${appium_config_env}") == "${saved_config}" ]]
incoming_bundle=actual.calculator
appium_restart=true

# Relaunch rejects missing artifacts before stopping; IPA activation does not depend on them.
target_dest=id=device
appium_mode=relaunch-test-driver
mv "${driverderived}/Build/Products/Driver.xctestrun" "${tmp}/saved.xctestrun"
: >"${tmp}/actions"
if launchdriver 2>/dev/null; then exit 1; fi
[[ ! -s ${tmp}/actions ]]
appium_mode=activate-ipa
target_app_ipa=${tmp}/upload.ipa
touch "${target_app_ipa}"
provisionlock=${tmp}/provision.lock
provisionpid=${provisionlock}/pid
saved_manifest=$(<"${driverstate}")
saved_driver_log=$(<"${logdrvr}")
mv "${tmp}/saved.xctestrun" "${driverderived}/Build/Products/Driver.xctestrun"
mv "${driverstate}" "${tmp}/saved-driver.json"
mv "${driverderived}" "${tmp}/saved-products"
service_url=http://localhost:${driver_port}
wda_response='{"value":{"ready":false}}'
if ! provision >"${tmp}/activation-console.log" 2>&1; then exit 1; fi
grep -q 'Calculator installation is preserved. Use t' "${tmp}/activation-console.log"
[[ $(<"${tmp}/actions") == *'kill actual.calculator'* ]]
[[ $(<"${tmp}/actions") == *"install --path ${target_app_ipa}"* ]]
[[ $(<"${tmp}/actions") != *stop* && $(<"${tmp}/actions") != *driver* && $(<"${tmp}/actions") != *uninstall* ]]
[[ ! -e ${driverstate} && ! -e ${driverderived} ]]
[[ $(<"${logdrvr}") == "${saved_driver_log}" ]]
[[ $(<"${appium_config_env}") == *"bundled_app=actual.calculator"* ]]
rm -rf "${provisionlock}"
mv "${tmp}/saved-driver.json" "${driverstate}"
mv "${tmp}/saved-products" "${driverderived}"

# With Driver artifacts present, Calc IPA installation leaves them byte-for-byte unchanged.
saved_manifest=$(<"${driverstate}")
saved_driver_log=$(<"${logdrvr}")
cp "${driverderived}/Build/Products/Driver.xctestrun" "${tmp}/before-ipa.xctestrun"
: >"${tmp}/actions"
provision || exit 1
[[ $(<"${tmp}/actions") == *'kill actual.calculator'* ]]
[[ $(<"${tmp}/actions") == *"install --path ${target_app_ipa}"* ]]
[[ $(<"${tmp}/actions") != *stop* && $(<"${tmp}/actions") != *driver* && $(<"${tmp}/actions") != *uninstall* ]]
[[ $(<"${driverstate}") == "${saved_manifest}" ]]
cmp -s "${tmp}/before-ipa.xctestrun" "${driverderived}/Build/Products/Driver.xctestrun"
[[ $(<"${logdrvr}") == "${saved_driver_log}" ]]
rm -rf "${provisionlock}"

saved_config=$(<"${appium_config_env}")
uninstall_failure=true
install_conflicts=actual.calculator
: >"${tmp}/actions"
: >"${logserv}"
if installapp "${target_app_ipa}" >"${tmp}/uninstall-console.log" 2>&1; then exit 1; fi
grep -q 'uninstall denied: test sentinel' "${tmp}/uninstall-console.log"
grep -q 'uninstall denied: test sentinel' "${logserv}"
[[ $(<"${tmp}/actions") == *'uninstall actual.calculator'* && $(<"${tmp}/actions") != *'install --path '* ]]
[[ $(<"${appium_config_env}") == "${saved_config}" ]]
uninstall_failure=false
install_conflicts=''

# Installer failures remain visible and cannot update the selected Calc metadata.

install_failure=true
: >"${tmp}/actions"
: >"${logserv}"
if installapp "${target_app_ipa}" >"${tmp}/install-console.log" 2>&1; then exit 1; fi
grep -q 'installation denied: test sentinel' "${tmp}/install-console.log"
grep -q 'installation denied: test sentinel' "${logserv}"
[[ $(<"${appium_config_env}") == "${saved_config}" ]]
install_failure=false
# A broken WDA forward gets one recovery, then readiness is required.
wda_response='{"value":{"ready":false}}'
reload_response='{"value":{"ready":true}}'
launchdriver || exit 1
[[ ${reload_calls} -eq 1 ]]
wda_response='{"value":{"ready":false}}'
reload_response='{"value":{"ready":false}}'
if launchdriver; then exit 1; fi
[[ ${reload_calls} -eq 2 ]]
appium_mode=relaunch-test-driver
test_driver_source=other-project
: >"${tmp}/actions"
if launchdriver 2>/dev/null; then exit 1; fi
[[ ! -s ${tmp}/actions ]]

# A compiler failure must not install anything or replace the last manifest.
saved_manifest=$(<"${driverstate}")
fake_build() { return 42; }
if builddriver; then exit 1; fi
[[ ! -s ${tmp}/actions ]]
[[ $(<"${driverstate}") == "${saved_manifest}" ]]
appium_mode=full
appium_restart=''
service_url=http://localhost:8100
wda_response='{"value":{"ready":true}}'
app_id=actual.calculator
bundled_app=actual.calculator
makeipa() { print -- calculator-build >>"${tmp}/actions"; }
builddriver() {
 print -- unexpected-driver-build >>"${tmp}/actions"
 return 99
}
: >"${tmp}/actions"
create "${session}" "${startin}" || exit 1
[[ $(<"${tmp}/actions") == calculator-build ]]

# Missing WDA never triggers a Driver build and leaves the installed Calc identity intact.
appium_restart=true
service_url=''
wda_response='{"value":{"ready":false}}'
: >"${tmp}/actions"
create "${session}" "${startin}" >"${tmp}/missing-wda.log" 2>&1 || exit 1
grep -q 'Calculator installation is preserved. Use t' "${tmp}/missing-wda.log"
[[ ! -s ${tmp}/actions ]]
[[ ${bundled_app} == actual.calculator ]]

print -- 'PASS: Calc-only build/restart, IPA activation and install error boundaries, independent Driver artifacts, stale-app removal, live-log preservation.'
