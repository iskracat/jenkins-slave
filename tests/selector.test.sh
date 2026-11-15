#!/usr/bin/env bash
# Behaviour tests for iskra-toolchain.
#
# The selector is a path resolver: these tests use fixture directories with
# fake executables and prove the resolution, the validation and the failure
# modes. They do not prove that a given Node or Python is installed in the
# image; that is checked inside the built image.
#
# Run: bash tests/selector.test.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
selector="$root/iskra-toolchain"

failures=0
checks=0
pass() {
  checks=$((checks + 1))
  printf 'ok   - %s\n' "$1"
}
fail() {
  checks=$((checks + 1))
  failures=$((failures + 1))
  printf 'FAIL - %s\n' "$1"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/iskra-toolchain.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

node_root="$tmp/node"
python_root="$tmp/python"
pnpm_root="$tmp/pnpm"

fake() {
  # fake <path> <output>
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$2" >"$1"
  chmod 0755 "$1"
}

fake "$node_root/v20.20.2/bin/node" 'v20.20.2'
fake "$node_root/v24.20.0/bin/node" 'v24.20.0'
fake "$python_root/3.13.18/bin/python3" '3.13.18'
cp "$python_root/3.13.18/bin/python3" "$python_root/3.13.18/bin/python"
fake "$python_root/3.8.13/bin/python3" '3.8.13'
fake "$pnpm_root/10.34.9/bin/pnpm" '10.34.9'

export ISKRA_TOOLCHAIN_NODE_ROOT="$node_root"
export ISKRA_TOOLCHAIN_PYTHON_ROOT="$python_root"
export ISKRA_TOOLCHAIN_PNPM_ROOT="$pnpm_root"

marker="$tmp/.marker"
: >"$marker"
sleep 1

run() {
  # run <expected-status> <description> -- <selector args...>
  local expected=$1 description=$2
  shift 3
  local status=0
  "$selector" "$@" >"$tmp/out" 2>"$tmp/err" || status=$?
  if [ "$status" -eq "$expected" ]; then
    pass "$description (exit $status)"
  else
    fail "$description (expected $expected, got $status: $(cat "$tmp/err"))"
  fi
}

echo '# listing and defaults'

run 0 'list succeeds' -- list
if grep -q '20.20.2' "$tmp/out" && grep -q '24.20.0' "$tmp/out" &&
  grep -q '3.13.18' "$tmp/out" && grep -q '10.34.9' "$tmp/out"; then
  pass 'list shows the fixture versions'
else
  fail "list does not show the fixture versions: $(cat "$tmp/out")"
fi

# The host may have its own node; what matters is that the selector adds none of
# the fixture directories and sets none of the pnpm variables.
clean_env=(env -u PNPM_HOME -u npm_config_manage_package_manager_versions -u PNPM_CONFIG_MANAGE_PACKAGE_MANAGER_VERSIONS)
"${clean_env[@]}" "$selector" exec -- sh -c 'printf "%s\n" "$PATH"' >"$tmp/out"
case $(cat "$tmp/out") in
  *"$node_root"* | *"$python_root"* | *"$pnpm_root"*)
    fail 'without a selector a toolchain directory appears in PATH'
    ;;
  *)
    pass 'without a selector no toolchain directory is added to PATH'
    ;;
esac

"${clean_env[@]}" "$selector" exec -- sh -c 'printf "%s" "${PNPM_HOME:-unset}"' >"$tmp/out"
if [ "$(cat "$tmp/out")" = 'unset' ]; then
  pass 'without a selector PNPM_HOME is untouched'
else
  fail "without a selector PNPM_HOME is $(cat "$tmp/out")"
fi

echo '# node selection'

run 0 'node 24.20.0 runs' -- exec --node 24.20.0 -- node -v
[ "$(cat "$tmp/out")" = 'v24.20.0' ] &&
  pass 'node 24.20.0 is the selected one' ||
  fail "node 24.20.0 resolved to $(cat "$tmp/out")"

run 0 'a leading v is accepted' -- exec --node v20.20.2 -- node -v
[ "$(cat "$tmp/out")" = 'v20.20.2' ] &&
  pass 'v20.20.2 is the selected one' ||
  fail "v20.20.2 resolved to $(cat "$tmp/out")"

"$selector" exec --node 24.20.0 -- sh -c 'command -v node' >"$tmp/out"
[ "$(cat "$tmp/out")" = "$node_root/v24.20.0/bin/node" ] &&
  pass 'the selected node is first in PATH' ||
  fail "node came from $(cat "$tmp/out")"

# A Node version can carry a global pnpm from an older image or a legacy agent.
# The explicit --pnpm must win over it.
fake "$node_root/v24.20.0/bin/pnpm" '9.9.9-legacy-global'
"$selector" exec --node 24.20.0 --pnpm 10.34.9 -- pnpm -v >"$tmp/out"
[ "$(cat "$tmp/out")" = '10.34.9' ] &&
  pass 'the selected pnpm wins over a global pnpm in the node bin' ||
  fail "a legacy global pnpm won: $(cat "$tmp/out")"
"$selector" exec --node 24.20.0 --pnpm 10.34.9 -- sh -c 'command -v pnpm' >"$tmp/out"
[ "$(cat "$tmp/out")" = "$pnpm_root/10.34.9/bin/pnpm" ] &&
  pass 'the pnpm prefix is first in PATH' ||
  fail "pnpm came from $(cat "$tmp/out")"
rm -f "$node_root/v24.20.0/bin/pnpm"

echo '# python and pnpm selection'

run 0 'python 3.13.18 runs' -- exec --python 3.13.18 -- python3 -V
[ "$(cat "$tmp/out")" = '3.13.18' ] &&
  pass 'python 3.13.18 is the selected one' ||
  fail "python 3.13.18 resolved to $(cat "$tmp/out")"

run 0 'the selected python is also the bare python' -- exec --python 3.13.18 -- python -V
[ "$(cat "$tmp/out")" = '3.13.18' ] &&
  pass 'bare python follows the selection' ||
  fail "bare python resolved to $(cat "$tmp/out")"

run 0 'two python versions in the same container' -- exec --python 3.8.13 -- python3 -V
[ "$(cat "$tmp/out")" = '3.8.13' ] &&
  pass 'python 3.8.13 is selectable next to 3.13.18' ||
  fail "python 3.8.13 resolved to $(cat "$tmp/out")"

run 0 'pnpm 10.34.9 runs' -- exec --pnpm 10.34.9 -- pnpm -v
[ "$(cat "$tmp/out")" = '10.34.9' ] &&
  pass 'pnpm 10.34.9 is the selected one' ||
  fail "pnpm 10.34.9 resolved to $(cat "$tmp/out")"

"$selector" exec --pnpm 10.34.9 -- sh -c 'printf "%s|%s" "${npm_config_manage_package_manager_versions-}" "${npm_config_package_manager_strict_version-}"' >"$tmp/out"
if [ "$(cat "$tmp/out")" = 'false|true' ]; then
  pass 'selecting pnpm disables the switch and enforces the version'
else
  fail "pnpm environment is $(cat "$tmp/out")"
fi

echo '# separate processes keep the choice'

for _ in 1 2; do
  "$selector" exec --node 24.20.0 -- sh -c 'node -v' >>"$tmp/out2"
done
if [ "$(cat "$tmp/out2")" = "$(printf 'v24.20.0\nv24.20.0')" ]; then
  pass 'two independent non-interactive shells resolve the same version'
else
  fail "independent shells resolved $(cat "$tmp/out2")"
fi

echo '# arguments, exit codes and signals'

run 0 'arguments with spaces and globs survive' -- exec --node 24.20.0 -- printf '%s|' 'a b' 'c*d' ''
[ "$(cat "$tmp/out")" = 'a b|c*d||' ] &&
  pass 'arguments are passed unchanged' ||
  fail "arguments became $(cat "$tmp/out")"

run 42 'the exit code of the command is propagated' -- exec -- sh -c 'exit 42'
run 0 'the exit code 0 path is untouched' -- exec -- true

"$selector" exec -- sleep 30 &
pid=$!
sleep 1
kill -TERM "$pid" 2>/dev/null
status=0
wait "$pid" 2>/dev/null || status=$?
if [ "$status" -eq 143 ]; then
  pass 'the selector is replaced by the command (signals reach it)'
else
  fail "the selector did not exec (wait status $status)"
fi

echo '# validation and failure modes'

run 3 'an unknown node version fails' -- exec --node 99.0.0 -- node -v
grep -q 'available: 20.20.2 24.20.0' "$tmp/err" &&
  pass 'the failure lists the installed versions' ||
  fail "the failure does not list versions: $(cat "$tmp/err")"
grep -qi 'nothing is downloaded' "$tmp/err" &&
  pass 'the failure states that nothing is downloaded' ||
  fail 'the failure does not forbid a download'

run 3 'an unknown python version fails' -- exec --python 3.12.0 -- python3 -V
run 3 'an unknown pnpm version fails' -- exec --pnpm 9.0.0 -- pnpm -v

for bad in '24.20' 'latest' '../3.13.18' '3.13.18/../../etc' '1.2.3 -x' ''; do
  run 3 "the node version '$bad' is refused" -- exec --node "$bad" -- node -v
done
# The "v" prefix is a Node convention, not a general one.
run 3 'a v-prefixed python version is refused' -- exec --python v3.13.18 -- python3 -V
run 3 'a v-prefixed pnpm version is refused' -- exec --pnpm v10.34.9 -- pnpm -v

# pnpm needs a Node that can run it; without one it must say so instead of
# letting the shebang fail.
status=0
env -i PATH=/usr/bin:/bin ISKRA_TOOLCHAIN_NODE_ROOT="$node_root" \
  ISKRA_TOOLCHAIN_PYTHON_ROOT="$python_root" ISKRA_TOOLCHAIN_PNPM_ROOT="$pnpm_root" \
  "$selector" exec --pnpm 10.34.9 -- pnpm -v >"$tmp/out" 2>"$tmp/err" || status=$?
[ "$status" -eq 3 ] &&
  pass 'pnpm without a node fails with the selector message' ||
  fail "pnpm without a node returned $status"
grep -q 'needs a node on PATH' "$tmp/err" &&
  pass 'the missing node is explained' ||
  fail "the missing node is not explained: $(cat "$tmp/err")"

run 3 'a command without -- is refused' -- exec --node 24.20.0 node -v
run 3 'an unknown option is refused' -- exec --nodejs 24.20.0 -- node -v
run 3 'a missing --node value is refused' -- exec --node
run 2 'no subcommand shows the usage' --
run 3 'an unknown subcommand is refused' -- install
run 3 'a missing command after -- is refused' -- exec --node 24.20.0 --

echo '# the selector never writes'

if [ -z "$(find "$tmp" -type f -newer "$marker" -not -path "$tmp" -not -name '.marker' -not -name 'out*' -not -name 'err' 2>/dev/null)" ]; then
  pass 'no file was created in the toolchain roots'
else
  fail 'the selector created files'
fi

original=$(cd "$root" && git status --porcelain 2>/dev/null | grep -c 'iskra-toolchain' || true)
[ "$original" = '0' ] &&
  pass 'the selector file is tracked without local modifications' ||
  printf 'note - iskra-toolchain is modified locally (expected during development)\n'

echo
if [ "$failures" -ne 0 ]; then
  printf '%s of %s checks failed\n' "$failures" "$checks"
  exit 1
fi
printf '%s checks passed\n' "$checks"
