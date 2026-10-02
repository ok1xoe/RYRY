#!/bin/zsh
# Zkopíruje příručku z docs/html do site/manual a napojí ji na design webu (css/manual-bridge.css, nová ikona,
# odkaz zpět na web). Spusť po každé změně příručky.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf manual && cp -R ../docs/html manual
cp css/manual-bridge.css manual/bridge.css
cp img/icon-512.png manual/img/icon.png
for f in manual/index.html manual/en/index.html manual/cs/index.html; do
    [[ -f $f ]] || continue
    # styl webu hned po stylu příručky; v hlavičce odkaz zpět na úvodní stránku webu
    case $f in manual/index.html) css="bridge.css"; home="../index.html";; manual/cs/*) css="../bridge.css"; home="../../cs/index.html";; *) css="../bridge.css"; home="../../index.html";; esac
    perl -0pi -e "s#(<link rel=\"stylesheet\" href=\"[^\"]*style\\.css\">)#\$1\n<link rel=\"stylesheet\" href=\"$css\">#" $f
    perl -0pi -e "s#(<span class=\"lang\">)#<a class=\"home\" href=\"$home\">← RYRY</a>\n  \$1#" $f
done
echo "manual: $(du -sh manual | cut -f1)"
