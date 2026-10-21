#!/bin/zsh

quotemeta() { perl -pe'chomp;$_=quotemeta'; }

# use the overridden appium config if set by appium-agent
appium_config=${appium_config_env:-"${FSDS_PREFIX}/etc/appium/config.env"}
! [ -r "${appium_config}" ] || . "${appium_config}"

export app_id=${bundled_app:-${FSDS_CALC_BUNDLE}}
export drv_id=${FSDS_CALC_DRIVER:-${bundled_drv}}
export dev_id=${FSDS_CALC_DEVICE:-${target_dest#id=}}
installed-team-apps() {
  [ ${#} -gt 0 ] || set -- "${dev_id}"
  mobiledevice list_apps -u "${1}" | grep -iE '^com\.NorthropGrumman\.[^\.]+\.[^\.]+(.xctrunner)?$'
}

ipa-app-identifier() {
  (
    setopt localoptions pipefail nullglob
    local tmp
    tmp=$(mktemp -d) || return
    trap 'rm -rf "${tmp}"' EXIT
    unzip -q "${1}" 'Payload/*.app/*' -d "${tmp}" || return
    local -a apps=("${tmp}"/Payload/*.app)
    ((${#apps[@]} == 1)) || return 1
    codesign -d --entitlements - --xml "${apps[1]}" |
      plutil -extract application-identifier raw -o - -
  )
}

ipa-bundle-identifier() {
  (
    setopt localoptions nullglob
    local tmp
    tmp=$(mktemp -d) || return
    trap 'rm -rf "${tmp}"' EXIT
    unzip -q "${1}" 'Payload/*.app/*' -d "${tmp}" || return
    local -a apps=("${tmp}"/Payload/*.app)
    ((${#apps[@]} == 1)) || return 1
    plutil -extract CFBundleIdentifier raw -o - "${apps[1]}/Info.plist"
  )
}

installed-conflict-apps() {
  setopt localoptions pipefail
  local device=${1} target=${2} ipa=${3}
  local installed bundle incoming existing
  local -a conflicts
  installed=$(mobiledevice list_apps -u "${device}") || return
  while IFS= read -r bundle; do
    [[ "${bundle}" == "${target%.*}"* ]] || continue
    if [[ "${bundle}" == "${target}" ]]; then
      incoming=$(ipa-app-identifier "${ipa}") &&
        existing=$(mobiledevice get_app_prop -u "${device}" "${target}" Entitlements |
          plutil -extract application-identifier raw -o - -) || {
        printf '%s\n' "Cannot read signing identifiers for ${target}; refusing to uninstall." >&2
        return 1
      }
      if [[ "${incoming#*.}" != "${target}" || "${existing#*.}" != "${target}" ||
        "${incoming}" != *.* || "${existing}" != *.* ||
        -z "${incoming%%.*}" || -z "${existing%%.*}" ]]; then
        printf '%s\n' "Invalid signing identifiers for ${target}; refusing to uninstall." >&2
        return 1
      fi
      [[ "${incoming%%.*}" != "${existing%%.*}" ]] || continue
    fi
    conflicts+=("${bundle}")
  done <<<"${installed}"
  ((${#conflicts[@]} == 0)) || printf '%s\n' "${conflicts[@]}"
  return 0
}
