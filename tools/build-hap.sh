#!/usr/bin/env bash
# Builds the debug HAP from the command line using DevEco Studio's bundled JDK and node.
set -e
cd "$(dirname "$0")/.."
DE="/c/Program Files/Huawei/DevEco Studio"
export DEVECO_SDK_HOME="C:/Program Files/Huawei/DevEco Studio/sdk"
export JAVA_HOME="C:/Program Files/Huawei/DevEco Studio/jbr"
export PATH="$DE/jbr/bin:$DE/tools/node:$PATH"
"$DE/tools/hvigor/bin/hvigorw.bat" --mode module -p module=entry@default -p product=default -p buildMode=debug assembleHap --no-daemon
