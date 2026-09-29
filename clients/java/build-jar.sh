#!/bin/zsh
# Sestaví clients/java/mmtty4mac-client.jar (JDK 21, bez závislostí).
set -euo pipefail
cd "$(dirname "$0")"
rm -rf out && mkdir out
javac --release 21 -d out $(find src -name '*.java')
jar --create --file mmtty4mac-client.jar -C out .
echo "Hotovo: $(pwd)/mmtty4mac-client.jar"
