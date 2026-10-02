#!/bin/zsh
# Builds clients/java/ryry-client.jar (JDK 21, no dependencies).
set -euo pipefail
cd "$(dirname "$0")"
rm -rf out && mkdir out
javac --release 21 -d out $(find src -name '*.java')
jar --create --file ryry-client.jar -C out .
echo "Done: $(pwd)/ryry-client.jar"
