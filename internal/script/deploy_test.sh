#!/bin/sh
set -eu

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
prefix="$tmp/install prefix"
mkdir -p "$prefix/bin" "$prefix/libexec" "$prefix/etc/appium"
printf 'old binary\n' >"$prefix/bin/appium-agent"
printf 'old helper\n' >"$prefix/libexec/genprops.zsh"
printf 'old launcher\n' >"$prefix/libexec/appiumd.zsh"
printf 'live settings\n' >"$prefix/etc/appium/config.env"
printf '{"live":true}\n' >"$prefix/etc/appium/config.json"
cp "$prefix/etc/appium/config.env" "$tmp/config.env"
cp "$prefix/etc/appium/config.json" "$tmp/config.json"
for file in appium-agent genprops.zsh appiumd.zsh; do
  case "$file" in appium-agent) dir=bin ;; *) dir=libexec ;; esac
  cp "$prefix/$dir/$file" "$tmp/$file.old"
done
cat >"$tmp/binary" <<'EOF'
#!/bin/sh
printf 'deployment fixture\n'
EOF

# An existing reader must retain its old inode after publication.
exec 3<"$prefix/libexec/appiumd.zsh"
sh internal/script/deploy.sh "$prefix" 1.2.3 "$tmp/binary" >"$tmp/output"
IFS= read -r old_launcher <&3
exec 3<&-
[ "$old_launcher" = 'old launcher' ]
[ "$(readlink "$prefix/bin/appium-agent")" = appium-agent1.2.3 ]
for file in bin/appium-agent1.2.3 libexec/genprops.zsh libexec/appiumd.zsh; do
  [ -x "$prefix/$file" ]
done
set -- "$prefix"/var/backups/appium-agent/*
[ "$#" -eq 1 ]
backup=$1
for file in appium-agent genprops.zsh appiumd.zsh; do
  cmp "$backup/$file" "$tmp/$file.old"
done
for file in config.env config.json; do
  cmp "$prefix/etc/appium/$file" "$tmp/$file"
done
for test in run/libexec/*_test.zsh; do
  [ ! -e "$prefix/libexec/${test##*/}" ]
done

# A failed stage or reused version cannot replace the active release.
if sh internal/script/deploy.sh "$prefix" 1.2.4 "$tmp/missing" >"$tmp/output" 2>&1; then
  echo 'Deployment accepted a missing binary' >&2
  exit 1
fi
[ ! -e "$prefix/bin/appium-agent1.2.4" ]
[ ! -d "$prefix/var/run/appium-agent-deploy.lock" ]
if sh internal/script/deploy.sh "$prefix" 1.2.3 "$tmp/binary" >"$tmp/output" 2>&1; then
  echo 'Deployment overwrote an installed version' >&2
  exit 1
fi
[ "$(readlink "$prefix/bin/appium-agent")" = appium-agent1.2.3 ]

# A contender must not remove another deployment's lock.
lock="$prefix/var/run/appium-agent-deploy.lock"
mkdir "$lock"
printf 'owner\n' >"$lock/owner"
if sh internal/script/deploy.sh "$prefix" 1.2.4 "$tmp/binary" >"$tmp/output" 2>&1; then
  echo 'Concurrent deployment acquired an existing lock' >&2
  exit 1
fi
[ "$(cat "$lock/owner")" = owner ]
[ ! -e "$prefix/bin/appium-agent1.2.4" ]
cmp "$prefix/bin/appium-agent" "$tmp/binary"
printf 'PASS: rollback snapshots, atomic script readers, live config preservation, failure boundaries, and deployment exclusion.\n'
