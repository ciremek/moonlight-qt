#!/bin/bash
# Build Moonlight (release) into build/app/Moonvibe.app
set -euo pipefail
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p build && cd build
qmake6 -r ../moonlight-qt.pro CONFIG+=release
make -j"$(sysctl -n hw.ncpu)"
echo "Built: $(pwd)/app/Moonvibe.app"
