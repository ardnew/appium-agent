#!/bin/sh
set -eu

prefix=${1:?missing install prefix}
version=${2:?missing release version}
binary=${3:?missing built executable}
case "$version" in
*[!0-9A-Za-z.+-]* | '')
  echo 'Invalid release version' >&2
  exit 1
  ;;
esac

mkdir -p "$prefix/bin" "$prefix/libexec" "$prefix/var/run"
lock="$prefix/var/run/appium-agent-deploy.lock"
mkdir "$lock" 2>/dev/null || {
  echo "Deployment already locked, or lock directory unwritable: $lock" >&2
  exit 1
}
stage_bin='' stage_lib=''
trap 'rm -rf "$stage_bin" "$stage_lib"; rmdir "$lock"' EXIT
trap 'exit 1' HUP INT TERM

target="$prefix/bin/appium-agent$version"
if [ -e "$target" ] || [ -L "$target" ]; then
  echo "Release already installed: $target; choose a new version" >&2
  exit 1
fi

backup_root="$prefix/var/backups/appium-agent"
mkdir -p "$backup_root"
backup=$(mktemp -d "$backup_root/$(date +%Y%m%d-%H%M%S).XXXXXX")
for file in bin/appium-agent libexec/genprops.zsh libexec/appiumd.zsh; do
  if [ -e "$prefix/$file" ] || [ -L "$prefix/$file" ]; then
    cp -pL "$prefix/$file" "$backup/${file##*/}"
  fi
done
printf 'Rollback files: %s\n' "$backup"

stage_bin=$(mktemp -d "$prefix/bin/.appium-agent.XXXXXX")
stage_lib=$(mktemp -d "$prefix/libexec/.appium-agent.XXXXXX")
install -m 0755 "$binary" "$stage_bin/appium-agent$version"
for script in genprops.zsh appiumd.zsh; do
  install -m 0755 "run/libexec/$script" "$stage_lib/$script"
  zsh -n "$stage_lib/$script"
done
ln -s "appium-agent$version" "$stage_bin/appium-agent"

# Publish the helper before its caller; each rename stays on its destination filesystem.
for script in genprops.zsh appiumd.zsh; do
  mv -f "$stage_lib/$script" "$prefix/libexec/$script"
done
mv -f "$stage_bin/appium-agent$version" "$target"
mv -f "$stage_bin/appium-agent" "$prefix/bin/appium-agent"

FSDS_PREFIX="$prefix" SHELL=/bin/zsh "$prefix/bin/appium-agent" --help >"$stage_bin/help"
IFS= read -r version_line <"$stage_bin/help"
printf '%s\n' "$version_line"
printf 'Deployment complete; services and live configuration were not modified.\n'
