#!/usr/bin/env bash
# Runtime validation of the selectable toolchain, inside the built image.
#
# The behaviour tests in selector.test.sh run on the host with fixtures. This
# file checks the real artifact: the versions actually installed, the legacy
# defaults, the venv, the pnpm settings and the failure modes. It is meant to
# run in the image with no network and as the image's own user:
#
#   docker run --rm --network none --platform linux/amd64 -e HOME=/home/jenkins \
#     -v "$PWD/tests/runtime.test.sh:/runtime.test.sh:ro" \
#     iskra/jenkins-slave:<tag> bash /runtime.test.sh
#
# Nothing here installs, downloads or writes outside /tmp.
set -uo pipefail

checks=0
failures=0
ok() { checks=$((checks + 1)); printf 'ok   - %s\n' "$1"; }
no() { checks=$((checks + 1)); failures=$((failures + 1)); printf 'FAIL - %s\n' "$1"; }
note() { printf 'note - %s\n' "$1"; }
expect() {
  if [ "$2" = "$3" ]; then ok "$1 ($3)"; else no "$1 (expected $2, got $3)"; fi
}
expect_fail() {
  if [ "$2" -ne 0 ]; then ok "$1 (exit $2)"; else no "$1 (exit 0)"; fi
}
fake() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$2" >"$1"
  chmod 0755 "$1"
}

work=$(mktemp -d /tmp/runtime.XXXXXX)
trap 'rm -rf "$work"' EXIT

echo '# identity'
expect 'the image user is jenkins' 'jenkins' "$(id -un)"
expect 'the image is linux/amd64' 'x86_64' "$(uname -m)"

echo '# the selector inventory'
iskra-toolchain list >"$work/list"
cat "$work/list"
for version in 20.20.2 24.20.0 3.13.18 10.34.9; do
  grep -q "$version" "$work/list" && ok "$version is listed" || no "$version is missing from the inventory"
done

echo '# the legacy defaults are untouched'
expect 'default python3 is 3.8.13' 'Python 3.8.13' "$(python3 -V 2>&1)"
expect 'default python is 3.8.13' 'Python 3.8.13' "$(python -V 2>&1)"
case "$(pip3.8 -V 2>&1)" in
  *'python 3.8'*) ok 'pip3.8 still belongs to python 3.8' ;;
  *) no "pip3.8 points elsewhere: $(pip3.8 -V 2>&1)" ;;
esac
if command -v guillotina >/dev/null 2>&1; then
  ok 'the legacy guillotina CLI is installed'
else
  no 'the legacy guillotina CLI is missing'
fi
if command -v node >/dev/null 2>&1; then
  no "node is on the default PATH: $(command -v node)"
else
  ok 'no node on the default PATH'
fi
if yarn --version >/dev/null 2>&1; then
  note 'bare yarn runs: this image has a node on PATH, update README'
else
  ok 'bare yarn still needs a node, as before the change'
fi
expect 'yarn 1.22.5 works with a selected node' '1.22.5' "$(iskra-toolchain exec --node 24.20.0 -- yarn --version 2>&1)"
helm version --short >/dev/null 2>&1 && ok 'helm runs' || no 'helm does not run'
kubectl version --client >/dev/null 2>&1 && ok 'kubectl runs' || no 'kubectl does not run'
for tool in aws google-chrome firefox; do
  if command -v "$tool" >/dev/null 2>&1 && "$tool" --version >/dev/null 2>&1; then
    ok "$tool runs"
  else
    no "$tool does not run"
  fi
done
if command -v java >/dev/null 2>&1; then
  note "java is present at $(command -v java); README says it is not"
else
  ok 'java is absent from this container, as before the change (the jnlp container has the JDK)'
fi

echo '# two node versions, separate processes'
for version in 20.20.2 24.20.0; do
  expect "node $version in its own shell" "v$version" "$(bash -c "iskra-toolchain exec --node $version -- node -v" 2>&1)"
done
expect 'two node versions in the same container' 'v20.20.2 v24.20.0 ' \
  "$(printf '%s\n%s\n' "$(iskra-toolchain exec --node 20.20.2 -- node -v)" "$(iskra-toolchain exec --node 24.20.0 -- node -v)" | tr '\n' ' ')"

echo '# python 3.13.18 next to 3.8.13'
expect 'python3 under selection' 'Python 3.13.18' "$(iskra-toolchain exec --python 3.13.18 -- python3 -V 2>&1)"
expect 'bare python under selection' 'Python 3.13.18' "$(iskra-toolchain exec --python 3.13.18 -- python -V 2>&1)"
expect 'python3.13 under selection' 'Python 3.13.18' "$(iskra-toolchain exec --python 3.13.18 -- python3.13 -V 2>&1)"
expect 'sys.prefix is the versioned prefix' '/opt/python/3.13.18' "$(iskra-toolchain exec --python 3.13.18 -- python3 -c 'import sys; print(sys.prefix)' 2>&1)"
expect 'sys.base_prefix is the versioned prefix' '/opt/python/3.13.18' "$(iskra-toolchain exec --python 3.13.18 -- python3 -c 'import sys; print(sys.base_prefix)' 2>&1)"
expect 'bz2, lzma, sqlite3 and ssl import' 'modules-ok' "$(iskra-toolchain exec --python 3.13.18 -- python3 -c 'import bz2, lzma, sqlite3, ssl; print("modules-ok")' 2>&1)"
iskra-toolchain exec --python 3.13.18 -- python3 -m venv "$work/venv" >/dev/null 2>&1
[ -x "$work/venv/bin/python" ] && ok 'venv is created' || no 'venv creation failed'
expect 'the venv runs 3.13.18' 'Python 3.13.18' "$("$work/venv/bin/python" -V 2>&1)"
expect 'the venv prefix is the venv' "$work/venv" "$("$work/venv/bin/python" -c 'import sys; print(sys.prefix)' 2>&1)"
"$work/venv/bin/pip" -V >/dev/null 2>&1 && ok 'the venv has pip' || no 'the venv has no pip'
case "$(iskra-toolchain exec --python 3.13.18 -- pip -V 2>&1 | awk '{print $2}')" in
  26.3*) ok 'pip is pinned to 26.3' ;;
  *) no "pip is not the pinned 26.3: $(iskra-toolchain exec --python 3.13.18 -- pip -V 2>&1)" ;;
esac
# A venv is what the Plone Makefile creates; it must work with an empty PATH.
expect 'venv works from a bare PATH' "$work/venv" "$(env -i "$work/venv/bin/python" -c 'import sys; print(sys.prefix)')"

echo '# pnpm 10.34.9 with a selected node'
expect 'pnpm version' '10.34.9' "$(iskra-toolchain exec --node 24.20.0 --pnpm 10.34.9 -- pnpm -v 2>&1)"
expect 'pnpm disables the switch and enforces the version' 'false|true' \
  "$(iskra-toolchain exec --node 24.20.0 --pnpm 10.34.9 -- sh -c 'printf "%s|%s" "${npm_config_manage_package_manager_versions-}" "${npm_config_package_manager_strict_version-}"' 2>&1)"
mkdir -p "$work/match"
printf '{"name":"match","version":"1.0.0","packageManager":"pnpm@10.34.9"}\n' >"$work/match/package.json"
status=0
(cd "$work/match" && iskra-toolchain exec --node 24.20.0 --pnpm 10.34.9 -- pnpm install --offline --ignore-scripts >"$work/match.log" 2>&1) || status=$?
[ "$status" -eq 0 ] && ok 'a matching packageManager installs offline' || no "the matching install failed ($status)"
mkdir -p "$work/mismatch"
printf '{"name":"mismatch","version":"1.0.0","packageManager":"pnpm@9.1.1"}\n' >"$work/mismatch/package.json"
status=0
(cd "$work/mismatch" && iskra-toolchain exec --node 24.20.0 --pnpm 10.34.9 -- pnpm install --offline --ignore-scripts >"$work/mismatch.log" 2>&1) || status=$?
expect_fail 'a different packageManager fails instead of downloading' "$status"
if grep -qi 'configured to use v9.1.1' "$work/mismatch.log"; then
  ok 'the mismatch names both versions'
else
  no "the mismatch is not explained: $(tail -2 "$work/mismatch.log")"
fi

echo '# an explicit pnpm wins over a global one in a node bin'
# The test hooks point the selector at a fixture root; this is the same code
# path a legacy agent with `npm i -g pnpm` would hit.
fake "$work/fx/node/v24.20.0/bin/node" 'v24.20.0'
fake "$work/fx/node/v24.20.0/bin/pnpm" '9.9.9-global'
fake "$work/fx/pnpm/10.34.9/bin/pnpm" '10.34.9'
expect 'the selected pnpm wins' '10.34.9' \
  "$(ISKRA_TOOLCHAIN_NODE_ROOT="$work/fx/node" ISKRA_TOOLCHAIN_PNPM_ROOT="$work/fx/pnpm" iskra-toolchain exec --node 24.20.0 --pnpm 10.34.9 -- pnpm -v 2>&1)"

echo '# no selector means no change'
base_path=$(bash -c 'printf "%s" "$PATH"')
expect 'the PATH without a selector is untouched' "$base_path" "$(iskra-toolchain exec -- bash -c 'printf "%s" "$PATH"')"
expect 'no node without a selector' 'none' "$(iskra-toolchain exec -- sh -c 'command -v node || echo none' 2>&1)"
expect 'no pnpm settings without a selector' 'unset' \
  "$(env -u npm_config_manage_package_manager_versions iskra-toolchain exec -- sh -c 'printf "%s" "${npm_config_manage_package_manager_versions:-unset}"' 2>&1)"

echo '# missing versions fail and write nothing'
touch "$work/marker"
sleep 1
for spec in '--node 99.0.0' '--python 3.12.0' '--pnpm 9.9.9'; do
  status=0
  # shellcheck disable=SC2086
  iskra-toolchain exec $spec -- true >/dev/null 2>"$work/missing.log" || status=$?
  expect_fail "$spec is refused" "$status"
  grep -q 'available:' "$work/missing.log" && ok "$spec lists the available versions" || no "$spec does not list versions"
done
status=0
iskra-toolchain exec --node 3.13.18/../../etc -- true >/dev/null 2>&1 || status=$?
expect_fail 'a traversal attempt is refused' "$status"
written=$(find /opt/python /opt/pnpm /usr/local/nvm /usr/local/bin -newer "$work/marker" 2>/dev/null | head -5)
[ -z "$written" ] && ok 'no version directory was written' || no "the selector wrote $written"
expect 'the nvm tree still has eight node versions' '8' "$(ls -1 /usr/local/nvm/versions/node | wc -l | tr -d ' ')"
expect 'the nvm tree is readable' '/usr/local/nvm/versions/node/v24.20.0/bin/node' \
  "$(iskra-toolchain exec --node 24.20.0 -- sh -c 'readlink -f /usr/local/nvm/versions/node/v24.20.0/bin/node')"

echo
printf '%s checks, %s failed\n' "$checks" "$failures"
[ "$failures" -eq 0 ]
