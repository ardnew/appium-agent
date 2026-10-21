#!/bin/zsh
set -e

appium_config_env=/dev/null
bundled_app=com.example.persisted
FSDS_CALC_BUNDLE=com.example.stale
source "${0:A:h}/genprops.zsh"
[[ ${app_id} == com.example.persisted ]]
unset bundled_app
source "${0:A:h}/genprops.zsh"
[[ ${app_id} == com.example.stale ]]

target=com.NorthropGrumman.FMPS-Calculator.App
variant=com.NorthropGrumman.FMPS-Calculator.Debug
test_incoming="NEW.${target}"
test_existing="NEW.${target}"
installed_apps=$(printf '%s\n' "${variant}" "${target}" com.NorthropGrumman.DAPA-Calculator.App)
list_failure=0
read_failure=0

ipa-app-identifier() { print -r -- "${test_incoming}"; }
mobiledevice() {
  if [[ ${1} == list_apps ]]; then
    ((list_failure == 0)) || return 1
    print -r -- "${installed_apps}"
  else
    ((read_failure == 0)) || return 1
    printf '{ "application-identifier" = "%s"; }\n' "${test_existing}"
  fi
}

result=$(installed-conflict-apps device "${target}" unused.ipa)
[[ ${result} == "${variant}" ]] # Same prefix preserves the target's data.

test_existing="OLD.${target}"
result=$(installed-conflict-apps device "${target}" unused.ipa)
[[ ${result} == "${variant}"$'\n'"${target}" ]]

for test_existing in '' 'OLD.other.app' "${target}" ".${target}"; do
  if result=$(installed-conflict-apps device "${target}" unused.ipa 2>/dev/null); then
    print -u2 -- 'Invalid signing identifiers must stop selection.'
    exit 1
  fi
  [[ -z ${result} ]] # Do not emit variants before discovering an unsafe target.
done

test_existing="NEW.${target}"
read_failure=1
if result=$(installed-conflict-apps device "${target}" unused.ipa 2>/dev/null); then
  exit 1
fi
[[ -z ${result} ]]
read_failure=0
list_failure=1
if result=$(installed-conflict-apps device "${target}" unused.ipa 2>/dev/null); then
  exit 1
fi
list_failure=0
installed_apps=com.NorthropGrumman.DAPA-Calculator.App
result=$(installed-conflict-apps device "${target}" unused.ipa)

[[ -z ${result} ]]
ipa_bundle=com.example.actual
extra_app=false
unzip() {
  local dest
  for dest; do :; done
  mkdir -p "${dest}/Payload/Calc.app"
  [[ ${extra_app} == false ]] || mkdir -p "${dest}/Payload/Other.app"
}
plutil() { print -r -- "${ipa_bundle}"; }
[[ $(ipa-bundle-identifier uploaded.ipa) == "${ipa_bundle}" ]]
extra_app=true
if ipa-bundle-identifier malformed.ipa >/dev/null 2>&1; then
  print -u2 -- 'An IPA with multiple app bundles must not select an arbitrary bundle.'
  exit 1
fi

print -- 'PASS: signing selection, IPA bundle identity, invalid metadata, read failures, absent target.'
