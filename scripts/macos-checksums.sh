#!/bin/zsh
# Record the installer and every input so CI can detect edits, additions and deletions.
set -euo pipefail
cd "${0:a:h}/.."
export LC_ALL=C
shasum -a 256 Package.swift Package.resolved(N) Resources/**/*(.D) Sources/**/*(.D) \
    scripts/{build-app,macos-checksums}.sh build/LangCursor-macOS.dmg
