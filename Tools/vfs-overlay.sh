#!/bin/bash
# Shared by build.sh and Tools/make-icon.sh. Sourced, not executed.
#
# Some Command Line Tools installs carry a stale /usr/include/swift/module.modulemap
# left over from an older release (it belongs to no installed package). It defines
# module SwiftBridging, which the shipped bridging.modulemap also defines, so every
# clang module build fails with "redefinition of module 'SwiftBridging'" — which in
# turn makes Swift fall back to rebuilding the SDK's .swiftinterface files and report
# a bogus "SDK is not supported by the compiler" mismatch.
#
# A VFS overlay hides the stale file without touching the system, so this works on a
# machine you do not want to sudo on. If you do want the real fix:
#
#     sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
#
# after which this file becomes a no-op and can stay where it is.
#
# Sets VFS_ARGS as an array; empty on a healthy toolchain.

STALE_MODULEMAP=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
VFS_ARGS=()

if [ -f "$STALE_MODULEMAP" ]; then
  mkdir -p .build
  : > .build/empty.modulemap
  cat > .build/overlay.yaml <<EOF
{
  "version": 0,
  "case-sensitive": false,
  "roots": [
    { "type": "file",
      "name": "$STALE_MODULEMAP",
      "external-contents": "$(pwd)/.build/empty.modulemap" }
  ]
}
EOF
  OV="$(pwd)/.build/overlay.yaml"
  VFS_ARGS=(-vfsoverlay "$OV" -Xcc -ivfsoverlay -Xcc "$OV" \
            -Xfrontend -vfsoverlay -Xfrontend "$OV")
fi
