#!/bin/sh
# Deny install-type build actions for the Screenshot capture configuration
# (screenshot-capture design section 1, tasks 2.1).
#
# `SUPPORTED_PLATFORMS=iphonesimulator` already rejects physical-device
# builds, but a simulator-destination `xcodebuild archive` (or `install`)
# would still succeed and could be mistaken for a distributable artifact.
# This pre-build phase fails those actions explicitly for the Screenshot
# configuration only. Normal `build`/`test` actions (simulator capture and
# the Screenshot test suite) and every Debug/Release action stay allowed —
# no production restriction is added.
#
# Xcode provides CONFIGURATION and ACTION to every build phase:
# `xcodebuild archive` runs phases with ACTION=install, `xcodebuild build`
# with ACTION=build, `xcodebuild test` with ACTION=build for its build part.
# Wired via `preBuildScripts` on the TimeOfLife app target in `project.yml`.
if [ "${CONFIGURATION:-}" = "Screenshot" ] && [ "${ACTION:-}" = "install" ]; then
    echo "error: Screenshot configuration forbids the '$ACTION' action (capture builds are simulator-run only; archives stay on the Debug/Release scheme)" >&2
    exit 1
fi
exit 0
