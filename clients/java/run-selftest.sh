#!/bin/zsh
# Přeloží klienta a spustí SelfTest (volitelně proti běžícímu mmtty4mac: ./run-selftest.sh ws://127.0.0.1:7363/v1).
set -euo pipefail
cd "$(dirname "$0")"
rm -rf out && mkdir out
javac --release 21 -d out $(find src -name '*.java')
java -cp out cz.ok1xoe.mmtty4mac.SelfTest "$@"
