# jenkins-slave

One shared Jenkins agent image. It is not built per project: it carries several
toolchain versions and a project selects the ones it needs, per process.

## Defaults are unchanged

Without an explicit selection nothing changes:

- `python3`, `python`, `pip`, `pip3` and `pip3.8` are the 3.8.13 build in
  `/usr/local`, and the CLIs installed with it (`guillotina`, ...) keep working;
- the nvm versions stay where they are and the nvm `default` alias stays
  `v24.20.0`;
- no Node is added to `PATH` (the image has none by default);
- `gcloud`, `aws`, `helm`, `helmfile`, `kubectl`, `docker`, `yarn`, Chrome,
  Firefox, `xvfb` and the rest are untouched. `java` is not installed in this
  container at all (it never was; the pod's `jnlp` container provides the JDK),
  and this change does not add it.

There is no `BASH_ENV`, no profile and no `ENTRYPOINT` that changes a shell.

## Opt-in selection

`/usr/local/bin/iskra-toolchain` resolves exact versions and prepends their
`bin` directories to `PATH` for one process. It never downloads, installs or
edits anything, and it never touches the installation directories.

```sh
iskra-toolchain list
iskra-toolchain exec --node 24.20.0 --python 3.13.18 --pnpm 10.34.9 -- <command>
```

Any combination of the three selectors is valid (`--pnpm` needs a Node, selected or already on `PATH`), and `--` is required before the command:

```sh
iskra-toolchain exec --python 3.13.18 -- make -C backend test
iskra-toolchain exec --node 24.20.0 --pnpm 10.34.9 -- make -C frontend install-ci
```

Rules:

- versions are exact `MAJOR.MINOR.PATCH`; `24`, `24.20`, `latest` and paths are
  refused;
- a single leading `v` is accepted for Node (`v24.20.0` == `24.20.0`);
- an unknown version exits 3 and lists what the image has; there is no fallback
  and no download;
- the command replaces the selector (`exec`), so arguments, exit codes and
  signals are the command's.

A selection lives for one process only. A pipeline that has several `sh` steps
must ask for the versions in every step, usually through one small wrapper that
reads a single project file; nothing survives from a previous step.

The pnpm prefix is placed before the Node bin, so an explicit `--pnpm` wins over
a global pnpm that an older image or a mutable agent left inside a Node version.
`--pnpm` needs a Node that can run it: pass `--node` too.

Selecting `--pnpm` also disables pnpm's automatic package-manager switch and
enforces the selected version (`npm_config_manage_package_manager_versions=false`,
`npm_config_package_manager_strict_version=true`). A project whose
`packageManager` names another pnpm version fails with
`This project is configured to use vX of pnpm. Your current pnpm is vY` instead
of downloading it. `PNPM_HOME` is not set: the prefix is read-only for jobs and
no job needs a global pnpm install from a shared image.

## Versions in the image

| Tool | Location | Versions |
| --- | --- | --- |
| Node | `/usr/local/nvm/versions/node/v*` | 10.20.1, 12.16.0, 14.21.3, 16.20.1, 18.16.1, 20.20.2, 22.23.2, 24.20.0 |
| Python | `/opt/python/<version>` | 3.13.18 (plus the default 3.8.13 in `/usr/local`, not selectable by accident) |
| pnpm | `/opt/pnpm/<version>` | 10.34.9 |

The side-by-side Python 3.13.18 is built with its own shared libpython and an
`rpath` to its prefix, so nothing outside `/opt/python/3.13.18` is configured.
`ensurepip` stays enabled because the Plone Makefile creates its virtualenv with
`python -m venv`. PGO is not enabled for this second interpreter: it only
changes speed and multiplies build time. The checksum is the official one from
python.org and pip is pinned (`26.3`).

pnpm is installed once at build time from the npm package into a versioned
prefix. Its shebang is `#!/usr/bin/env node`, so it always runs with the Node
that the pipeline selected, and no Node version's npm global directory is
mutated.

## Build

```sh
make build            # local build of $(IMAGE):$(TAG), never pushes
make build TAG=21     # next tag, still local
make test             # behaviour tests of the selector with fixtures
```

`make image` is the legacy target and still builds **and pushes**. It is not a
local check. `PLATFORM` defaults to `linux/amd64`, which is what the cluster
runs; the Node tarballs, Chrome and the AWS CLI in the Dockerfile are amd64
only, so the image is not an arm64 artifact.

## Rollout (administrative, not in this repository)

The running agents use `iskra/jenkins-slave:20` (visible in the Jenkins build
log). Tag 20 predates the selector, so pipelines that call it fail with
`command not found` until:

1. the new image is built and published under an **immutable** tag, by an
   operator with registry permission;
2. the Kubernetes pod template of the Jenkins cloud is pointed at that tag;
3. the build is recorded with its digest (the log only shows the tag).

Tag 20 should not be overwritten. Until the template moves, `iskra-toolchain`
does not exist on the agents, whatever this repository contains.

## Tests

- `tests/selector.test.sh` (48 checks) runs on the host with fixture
  directories. It proves the resolution and the ordering (an explicit pnpm wins
  over a global one in a node bin), the normalisation (a leading `v` is Node
  only), the refusal of traversal/ranges, the missing-version failure, the pnpm
  without-node failure, argument quoting, exit code and signal propagation, and
  that no file is written. It does **not** prove that a real Node or Python is
  installed.
- `tests/runtime.test.sh` runs **inside the built image**, with no network and
  as the image user. It checks the real versions, the legacy defaults, the venv
  and its stdlib, the pnpm settings, the pnpm/node collision, the mismatch
  failure and that nothing is written:

```sh
docker run --rm --network none --platform linux/amd64 -e HOME=/home/jenkins \
  -v "$PWD/tests/runtime.test.sh:/runtime.test.sh:ro" \
  iskra/jenkins-slave:<tag> bash /runtime.test.sh
```

Both exit non-zero on a failure. Neither installs, downloads or touches the
host.

## Risks for other projects

What is verified: the defaults are unchanged in the built image (`python3`,
`python`, `pip`, `pip3`, `pip3.8` are 3.8.13, the legacy CLIs run, no Node is on
`PATH`, the nvm versions and the `default` alias are untouched), and the
selector changes nothing without an explicit selection.

What is **not** verified: that every other project keeps working. This image is
rebuilt from `apt` and from an unpinned `requirements.txt`, so a rebuild can
resolve newer package versions with the same 3.8.13 interpreter. Compatibility
with the other jobs needs a rebuild, a comparison with their previous agent and
a rollout check; this change does not prove it.

- `/usr/local` still holds Python 3.8.13; a project that needs 3.13 must ask.
- `/usr/local/nvm` is still owned by `jenkins` (unchanged), so a job on a
  long-lived Docker agent could still run `nvm install` and mutate that agent.
  In Kubernetes each pod has its own writable layer, and the selector never
  writes.
- Adding `libbz2-dev`, `liblzma-dev` and `libexpat1-dev` to the build
  dependencies only adds Python modules; no existing binary changes its
  resolution.
- `--pnpm` alone only works if a compatible `node` is already on `PATH`;
  otherwise it fails with a message that asks for `--node`. Do not assume every
  subset of selectors is useful.
- `java` is not in this container (the `jnlp` container of the pod provides the
  JDK); the selector does not add it.
