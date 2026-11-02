# Build and release workflow

**English** | [简体中文](CI.zh-CN.md)

CI uses Ubuntu 24.04 and three independent matrix jobs for rootful, rootless and roothide. `ci/install_linux_deps.sh` installs Clang 22 from LLVM's signed apt repository. `ci/bootstrap.py` prepares pinned roothide/Theos, SDK 16.5, SHA256-verified Linux linker tools and the Gum devkit. Gum extraction accepts the official archives' `./` filename prefix. See [package variants](PACKAGING.md) for schemes and install paths.

Install `libplist-utils` as well: its runtime library is needed by the toolchain's `plistutil`. An earlier CI package step failed because `libplist-2.0.so.4` was missing; a preinstalled local copy had hidden the omission. Before compiling, `build.sh` runs `ci/check_packaging_tools.py` using the actual build PATH. It checks that XML and OpenStep string tables can be converted in place to binary plists while preserving Chinese values. Missing libraries produce a cause and installation hint. This check runs even when the toolchain cache is restored.

Every push builds packages and uploads artifacts. Only a push to the default branch compares that push's `before` commit with the current `VERSION`, including version changes in earlier commits of a multi-commit push. An initial push that introduces the first version releases it. An unchanged version, build-number-only change, tag, another branch or manual run does not release. An unavailable old commit prevents publishing while allowing builds.

Each scheme uploads its own artifact; one failed job does not cancel the others. The separate release job requires all three builds to pass, merges artifacts from the same workflow run, verifies every package's SHA256 and creates `vVERSION` with all three debs, combined checksums and per-scheme build information. An existing release is preserved. Artifacts contain packages, checksums and public build provenance, excluding source workspaces, generated pairing headers, downloaded dependencies and private captures. Available diagnostics are uploaded on failure.

`VERSION` is the release version and `BUILD_NUMBER` is the app build number; both feed generated package metadata. Only a change to `VERSION` triggers a release. For example, pushing a change from 1.3.7 to 1.3.8 to the default branch publishes v1.3.8; pushing UI changes alone produces artifacts.

Third-party actions are pinned to commits and public binary dependencies to checksums. Caches contain public tools only, excluding pairing material. Device passwords and activation codes do not belong in workflow environment values, repository variables or source files; the build does not require them.
