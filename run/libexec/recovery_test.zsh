#!/bin/zsh
set -e

script=${1:-${0:A:h}/appiumd.zsh}
# Load functions without executing the launcher's live service operations.
load_function() {
  local line definition='' collecting=false
  while IFS= read -r line; do
    [[ ${line} != "${1}() {" ]] || collecting=true
    if ${collecting}; then
      definition+="${line}"$'\n'
      [[ ${line} != '}' ]] || {
        eval "${definition}"
        return 0
      }
    fi
  done <"${script}"
  return 1
}
for name in watchdriver provision; do load_function "${name}"; done

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
session=Appium
driver_session='FMPS Test Driver'
self=${script}
driverstate=${tmp}/driver.json
appium_config_env=${tmp}/config.env
provisionlock=${tmp}/provision.lock
provisionpid=${provisionlock}/pid
logdrvr=${tmp}/driver.log
ERR_EXELOCK=125
ERR_PROJECT=127
ERR_COMPILE=123
ERR_UNKNOWN=100
print -- 'service_url=http://localhost:8100' >"${appium_config_env}"

truth() { [[ ${1:-false} == true ]]; }
pout() { :; }
perr() { print -r -- "$*" >>"${tmp}/errors"; }
exists() {
  if [[ ${1} == ${session} ]]; then
    ((tick <= last_tick)) && [[ ${appium_present} == true ]]
  else
    [[ ${driver_present} == true ]]
  fi
}
sleep() {
  SECONDS=$((SECONDS + $1))
  if (($1 == 2)); then tick=$((tick + 1)); fi
  if ((tick == lock_start)); then
    mkdir -p "${provisionlock}"
    print -- $$ >"${provisionpid}"
  fi
  if ((tick == lock_end)); then rm -rf "${provisionlock}"; fi
}
wda_ready() {
  case ${mode} in
  ready) return 0 ;;
  transient) ((tick != 2)) ;;
  recovered) ((recoveries > 0)) ;;
  rearm) ((recoveries >= 3 && SECONDS - heal_at < 150)) ;;
  *) return 1 ;;
  esac
}
zsh() {
  recoveries=$((recoveries + 1))
  driver_present=true
  if ((recoveries == 3)); then heal_at=$((SECONDS + 10)); fi
  if [[ ${mode} == rearm ]] && ((recoveries == 4)); then appium_present=false; fi
  return ${recovery_result}
}
reset() {
  tick=0 last_tick=10 SECONDS=0 recoveries=0 heal_at=0 recovery_result=0
  lock_start=-1 lock_end=-1
  appium_present=true driver_present=true lldb_managed=false driver_recovery=false
  mode=down
  rm -rf "${provisionlock}"
  touch "${driverstate}"
  : >"${logdrvr}"
  : >"${tmp}/errors"
}
crash() { print -- 'libc++abi: terminating due to uncaught exception' >"${logdrvr}"; }

reset
mode=ready
watchdriver
[[ ${recoveries} -eq 0 ]]
reset
mode=transient
watchdriver
[[ ${recoveries} -eq 0 ]]
reset
last_tick=100
watchdriver
[[ ${recoveries} -eq 0 ]]
reset
last_tick=151
watchdriver
[[ ${recoveries} -eq 1 ]]
reset
crash
mode=recovered
watchdriver
[[ ${recoveries} -eq 1 ]]
reset
mode=ready
driver_present=false
watchdriver
[[ ${recoveries} -eq 1 ]]

# A provisioning operation interrupts, rather than merely postpones, a failure streak.
reset
crash
lock_start=3
lock_end=4
last_tick=5
watchdriver
[[ ${recoveries} -eq 0 ]]
reset
crash
recovery_result=${ERR_EXELOCK}
watchdriver
[[ ${recoveries} -gt 3 ]]
reset
crash
last_tick=30
watchdriver
[[ ${recoveries} -eq 3 && $(grep -c 'recovery exhausted' "${tmp}/errors") -eq 1 ]]
reset
crash
mode=rearm
last_tick=200
watchdriver
[[ ${recoveries} -eq 4 ]]
reset
appium_present=false
watchdriver
[[ ${recoveries} -eq 0 ]]
reset
lldb_managed=true
watchdriver
[[ ${recoveries} -eq 0 ]]
reset
rm "${driverstate}"
watchdriver
[[ ${recoveries} -eq 0 ]]

# Real lock directories enforce exclusion and stale-owner reclamation. Healthy
# recovery contenders must not restart services or enter build/install paths.
launches=0
launchdriver() {
  launches=$((launches + 1))
  return ${ERR_COMPILE}
}
stopdriver() { return 91; }
builddriver() { return 92; }
installapp() { return 93; }
create() { return 94; }
tmux() { print -r -- "$*" >>"${tmp}/tmux"; }
reset
driver_recovery=true
appium_mode=relaunch-test-driver
mode=ready
: >"${tmp}/tmux"
provision
[[ ${launches} -eq 0 && ! -s ${tmp}/tmux && $(<"${provisionpid}") == $$ ]]
provision_locked=''
if provision; then exit 1; else result=$?; fi
[[ ${result} -eq ${ERR_EXELOCK} && $(<"${provisionpid}") == $$ ]]
print -- 99999999 >"${provisionpid}"
provision
[[ $(<"${provisionpid}") == $$ && ${launches} -eq 0 ]]
rm -rf "${provisionlock}"
mode=down
if provision; then exit 1; else result=$?; fi
[[ ${result} -eq ${ERR_COMPILE} && ${launches} -eq 1 && ! -s ${tmp}/tmux ]]
rm -rf "${provisionlock}"
appium_present=false
if provision; then exit 1; else result=$?; fi
[[ ${result} -eq ${ERR_EXELOCK} && ${launches} -eq 1 ]]
rm -rf "${provisionlock}"
appium_present=true
lldb_managed=true
if provision; then exit 1; else result=$?; fi
[[ ${result} -eq ${ERR_EXELOCK} && ${launches} -eq 1 ]]

# Shutdown during a successful Driver relaunch must not recreate Appium.
reset
driver_recovery=true
appium_mode=relaunch-test-driver
: >"${tmp}/tmux"
launchdriver() {
  appium_present=false
  return 0
}
create() { print -- unexpected-create >>"${tmp}/tmux"; }
if provision; then exit 1; else result=$?; fi
[[ ${result} -eq ${ERR_EXELOCK} && ! -s ${tmp}/tmux ]]
print -- 'PASS: recovery thresholds, busy-command grace, retry exhaustion/rearm, shutdown/debug exclusion, provisioning serialization and health recheck.'
