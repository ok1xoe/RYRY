# ryry.ok1xoe.dev – web produktu RYRY

Statický web bez sestavování a bez externích požadavků (písma jsou přibalená) v designu „instrument“
z `ok1xoe.dev` (repo `xoe-web`). Tmavé i světlé téma sdílí volbu s `ok1xoe.dev` (stejný klíč v localStorage).

```
index.html, support.html, privacy.html   angličtina (výchozí)
cs/…                                      čeština
manual/                                   příručka (kopie docs/html napojená na design, vytváří build-manual.sh)
css/site.css, assets/fonts/               design systém OK1XOE.dev – NEUPRAVOVAT, jen kopírovat z xoe-web
css/ryry.css                              doplňky pro RYRY (ikona v hero, tlačítko App Store, snímky, FAQ)
css/manual-bridge.css                     přemapování barev a písma příručky na design webu
js/site.js                                hlavička, patička, téma, osciloskop se signálem FSK
img/                                      ikona (z docs/appstore/icon-1024.png)
deploy/nginx-ryry.conf.example            hostový Nginx + certbot
```

## Lokálně

    ./build-manual.sh                     # po změně příručky v docs/html
    python3 -m http.server 8090 -d .      # pak http://localhost:8090

## Nasazení (stejně jako xoe-web, jen statika)

    rsync -av --delete site/ server:/var/www/ryry/

Pak Nginx a certifikát podle `deploy/nginx-ryry.conf.example`. App Store Connect vyžaduje, aby
`https://ryry.ok1xoe.dev/support.html` a `/privacy.html` fungovaly už při odeslání ke schválení.

## Po schválení v App Store

V `index.html` a `cs/index.html` nahraď `href="#appstore"` adresou aplikace
`https://apps.apple.com/app/id<číslo>` (App Store Connect → App Information → Apple ID).

## Aktualizace designu

Když se změní design systém v `xoe-web`, zkopíruj `css/site.css` a `assets/fonts/` znovu. Doplňky RYRY jsou
jen v `css/ryry.css` a `css/manual-bridge.css`.
