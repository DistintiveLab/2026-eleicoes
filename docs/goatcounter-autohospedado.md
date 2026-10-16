# GoatCounter auto-hospedado para o painel (viravoto.coletivo.net.br)

Tutorial para instalar e ligar o [GoatCounter](https://www.goatcounter.com/)
(analytics open source, sem cookies de rastreio) **no nosso próprio servidor**,
medindo o painel Shiny servido em `viravoto.coletivo.net.br` (nginx →
proxy_pass → shiny-server).

Por que auto-hospedar: os dados ficam no nosso servidor, `count.js` é servido
de um **subdomínio nosso** (first-party, bem menos bloqueado por adblockers
do que `gc.zgo.at`), e o custo é zero.

Resultado final:

```
navegador ── painel ──► https://viravoto.coletivo.net.br
                          └─ nginx :443 ──► shiny-server 127.0.0.1:3846
                                            (site_dir /srv/shiny-server/2026-eleicoes)

navegador ── beacons ──► https://gc.viravoto.coletivo.net.br
                          └─ nginx :443 ──► goatcounter 127.0.0.1:8081
                                            └─ SQLite /var/lib/goatcounter/db.sqlite3
```

Decisões adotadas (ajuste se preferir outro esquema):

| Item | Valor | Motivo |
|---|---|---|
| Domínio do GoatCounter | `gc.viravoto.coletivo.net.br` | separa analytics do app; count.js first-party |
| Porta local | `127.0.0.1:8081` | o default do goatcounter é `:8080`; 8081 evita conflito |
| Binário | `/usr/local/bin/goatcounter` (v2.7.0) | release oficial linux-amd64 |
| Dados | `/var/lib/goatcounter/db.sqlite3` | SQLite basta para esse volume |
| Serviço | systemd `goatcounter.service`, usuário dedicado | padrão da casa (cf. `shiny-server.service`) |

Verificado na v2.7.0 (README + `goatcounter help db`): o **`-vhost` é o domínio
onde o próprio GoatCounter responde** (dashboard e `/count`), *não* o domínio
contado — o site "só fica disponível nesse domínio". O domínio do painel
entraria depois em *Settings → Site settings*, como metadado.

## 0. Pré-requisitos

- Acesso root/sudo **no servidor** (é a própria máquina do viravoto).
- Registro DNS: criar `gc.viravoto.coletivo.net.br` como **A → 92.112.176.154**
  (mesmo IP do viravoto), no mesmo painel onde o `viravoto` foi criado.
  Confirmar propagação (pode levar minutos):

  ```sh
  dig +short gc.viravoto.coletivo.net.br   # ou: getent hosts gc.viravoto.coletivo.net.br
  # deve responder 92.112.176.154
  ```

- Um e-mail para o login do dashboard (ex.: o e-mail do coletivo).

## 1. Instalar o binário

```sh
sudo curl -fsSLo /tmp/goatcounter.gz \
  https://github.com/arp242/goatcounter/releases/download/v2.7.0/goatcounter-v2.7.0-linux-amd64.gz

echo "98d221cb9c8ef2bf76d8daa9cca647839f8d8b0bb5bc7400ff9337c5da834511  /tmp/goatcounter.gz" \
  | sha256sum -c

gunzip -f /tmp/goatcounter.gz
sudo install -m 0755 /tmp/goatcounter /usr/local/bin/goatcounter
goatcounter version   # goatcounter v2.7.0
```

Usuário e diretório de dados dedicados:

```sh
sudo adduser --system --group --home /var/lib/goatcounter \
  --shell /usr/sbin/nologin goatcounter
sudo mkdir -p /var/lib/goatcounter
sudo chown goatcounter:goatcounter /var/lib/goatcounter
```

## 2. Criar o site no banco

```sh
sudo -u goatcounter goatcounter db create site \
  -db 'sqlite+file:/var/lib/goatcounter/db.sqlite3' \
  -createdb \
  -vhost=gc.viravoto.coletivo.net.br \
  -user.email=SEU-EMAIL@exemplo.com
```

- Pede a **senha interativamente** (evite `-password`, que vai para o history).
  Rodar com `sudo -u goatcounter` já deixa o `db.sqlite3` com o dono certo
  (rodando como root depois seria preciso `chown goatcounter:goatcounter`).
- `-createdb` cria o arquivo SQLite se não existir.
- O `-vhost` **tem que ser** `gc.viravoto.coletivo.net.br` (onde o GoatCounter
  é acessado). Se um dia precisar conferir o que existe no banco:

  ```sh
  sudo -u goatcounter goatcounter db show site \
    -find gc.viravoto.coletivo.net.br -db 'sqlite+file:/var/lib/goatcounter/db.sqlite3'
  ```

## 3. systemd

`/etc/systemd/system/goatcounter.service`:

```ini
[Unit]
Description=GoatCounter (web analytics, self-hosted)
After=network.target

[Service]
User=goatcounter
Group=goatcounter
ExecStart=/usr/local/bin/goatcounter serve \
  -db 'sqlite+file:/var/lib/goatcounter/db.sqlite3' \
  -listen 127.0.0.1:8081 \
  -automigrate
Restart=always
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/goatcounter

[Install]
WantedBy=multi-user.target
```

`-automigrate` roda migrações pendentes a cada boot (útil em upgrades).
Flags também aceitam env vars (`GOATCOUNTER_DB`, `GOATCOUNTER_LISTEN`, ...).

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now goatcounter
systemctl status goatcounter --no-pager
ss -tlnp | grep 8081          # goatcounter em 127.0.0.1:8081
curl -s http://127.0.0.1:8081/status   # endpoint de healthcheck
```

## 4. nginx + TLS

Criar `/etc/nginx/sites-enabled/gc.viravoto.coletivo.net.br.conf` seguindo o
padrão do conf do viravoto. **Atenção:** o `map $http_upgrade
$connection_upgrade` já existe no conf do viravoto (mesmo nível `http`, pois
sites-enabled é incluído lá) — **não redeclare** no novo arquivo (`nginx -t`
falharia com "duplicate variable").

```nginx
server {
    server_name gc.viravoto.coletivo.net.br;
    listen 80;

    location /.well-known/acme-challenge/ {
        root /home/distintive/domains/gc.viravoto.coletivo.net.br/public_html/;
    }
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    server_name gc.viravoto.coletivo.net.br;
    listen 443 ssl;

    ssl_certificate     /home/distintive/domains/gc.viravoto.coletivo.net.br/ssl.combined;
    ssl_certificate_key /home/distintive/domains/gc.viravoto.coletivo.net.br/ssl.key;

    access_log /var/log/virtualmin/gc.viravoto.coletivo.net.br_access_log;
    error_log  /var/log/virtualmin/gc.viravoto.coletivo.net.br_error_log;

    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 60s;
    }
}
```

TLS — dois caminhos (o de cima já assume os caminhos do Virtualmin):

- **Virtualmin (padrão da casa):** criar o sub-servidor
  `gc.viravoto.coletivo.net.br` no Virtualmin (ele emite o cert Let's Encrypt
  em `/home/distintive/domains/gc.../ssl.combined` + `ssl.key` e cuida da
  renovação). Depois basta substituir o `location /` gerado pelo bloco
  `proxy_pass` acima e remover o `root`/PHP do template.
- **certbot direto:** `sudo certbot --nginx -d gc.viravoto.coletivo.net.br`
  ajusta o conf e a renovação sozinho (requer certbot instalado).

O `X-Forwarded-Proto` é importante: a v2.7.0 detecta dele se o cookie de
login deve ser `Secure` (sem ele, atrás de HTTPS, o login "não gruda").

```sh
sudo nginx -t && sudo systemctl reload nginx
```

## 5. Ligar o app (snippet no Shiny)

Recomendado: **JS no `painel/www/painel.js`**, com guarda de hostname — assim
o tracker só carrega na produção e nunca em `localhost`/testes (a UI é
avaliada uma vez por processo e servida para todos). O `painel.js` já tem o
handler de clique nas abas; é só pendurar o `count()` nele.

(a) No início da IIFE, depois do `'use strict';`:

```js
  /* Analytics GoatCounter: só carrega na produção, nunca em localhost/testes. */
  if (location.hostname === 'viravoto.coletivo.net.br') {
    var gc = document.createElement('script');
    gc.async = true;
    gc.dataset.goatcounter = 'https://gc.viravoto.coletivo.net.br/count';
    gc.src = 'https://gc.viravoto.coletivo.net.br/count.js';
    document.head.appendChild(gc);
  }
```

(b) No handler de clique existente, contar a aba como pageview virtual:

```diff
   document.addEventListener('click', function (evento) {
     var aba = evento.target.closest('#painel_nav a[data-value]');
     if (aba) {
       try { localStorage.setItem('painel_aba', aba.dataset.value); } catch (e) { /* ok */ }
   +   if (window.goatcounter && typeof window.goatcounter.count === 'function') {
   +     window.goatcounter.count({ path: '/aba-' + aba.dataset.value });
   +   }
     }
   });
```

Como fica a leitura: cada visita conta `/` automaticamente (o `count.js`
padrão conta no onload), e cada troca/restauração de aba conta
`/aba-virada`, `/aba-mapa`, ... — a restauração da última aba
(`inicializar()`) dispara clique sintético, que o handler acima captura.
Clicar de novo na aba já ativa conta de novo; se incomodar, guarde a última
aba contada numa variável e ignore repetições.

Alternativa (não recomendada): injetar direto no `painel_recursos()`
(`painel/R/painel_ui.R`) com
`shiny::tags$script(`data-goatcounter` = "https://gc...", src = "https://gc.../count.js", async = NA)`
— carregaria também fora da produção, poluindo as estatísticas com acessos
  de dev.

**Aplicar e reiniciar** (o `includeScript` embute o JS na UI, avaliada no
startup do processo R — reload de página não basta):

```sh
sudo systemctl restart shiny-server
```

Isso reinicia **todas** as instâncias (3838, 3845 e a 3846 do viravoto);
contar com alguns segundos de indisponibilidade.

## 6. Validar

1. `https://gc.viravoto.coletivo.net.br` abre a tela de login → entrar com o
   e-mail/senha do passo 2 → dashboard.
2. Abrir o painel em `viravoto.coletivo.net.br`, navegar entre abas.
3. Pageviews levam **~10 s** para aparecer; dar F5 no dashboard.
   "Pages" deve mostrar `/` e `/aba-virada`, `/aba-mapa`, ...
4. DevTools → Network → filtrar `count`: deve haver requisição para
   `gc.viravoto.coletivo.net.br/count` (beacon, status 200).
5. Testar em janela privativa sem extensões: adblockers podem bloquear
   (subdomínio próprio costuma passar; `gc.zgo.at` é o que costuma cair).
6. *Settings → Server management* no dashboard ajuda a debugar o servidor.

## 7. Operação

**Backup** (seguro com o serviço rodando; requer `sqlite3`, `sudo apt install
sqlite3`). Ex.: `/etc/cron.d/goatcounter-backup`:

```
0 4 * * * root mkdir -p /var/lib/goatcounter/backup && sqlite3 /var/lib/goatcounter/db.sqlite3 ".backup '/var/lib/goatcounter/backup/db-$(date +\%F).sqlite3'" && find /var/lib/goatcounter/backup -name 'db-*.sqlite3' -mtime +30 -delete
```

**Upgrade**: baixar o binário da nova release (mesma URL trocando a versão,
conferir o sha256 da página de release), `install` por cima e
`systemctl restart goatcounter` — o `-automigrate` roda as migrações.
Ler o CHANGELOG antes de saltar versões maiores.

**Privacidade/LGPD**: GoatCounter não usa cookies de rastreio nem
identificadores únicos (sessões via hash diário não identificável), respeita
`DNT` por padrão e os dados ficam no nosso servidor — sem necessidade de
banner de consentimento segundo a política do projeto
(https://www.goatcounter.com/privacy). Os bots vão para tabela própria.

**Não contar os próprios acessos** (opcional): bloquear seu IP só no
endpoint de coleta, dentro do server 443 do gc:

```nginx
    location = /count {
        deny 203.0.113.7;      # seu IP (403; o beacon falha em silêncio)
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
```

## 8. Troubleshooting

| Sintoma | Causa provável | Correção |
|---|---|---|
| 502 no `gc.…` | serviço parado / porta errada | `systemctl status goatcounter`; conferir `-listen 127.0.0.1:8081` vs `proxy_pass` |
| Login volta à tela de login | faltou `X-Forwarded-Proto` | conferir o `proxy_set_header` no server 443 |
| "site not found" no `gc.…` | Host ≠ `-vhost` criado | `goatcounter db show site -find ...` e recriar com o vhost certo |
| Pageviews não aparecem | atraso ~10 s; adblock; `data-goatcounter` errado; app aberto fora de `viravoto...` (guarda de hostname) | DevTools → Network/Console no painel |
| Erro de permissão no db | banco criado como root | `sudo chown goatcounter:goatcounter /var/lib/goatcounter/db.sqlite3` |
| `nginx -t`: "duplicate variable" | `map $http_upgrade` redeclarado | remover o `map` do novo conf (já existe no do viravoto) |
| Snippet não aparece no app | UI avaliada no startup | `sudo systemctl restart shiny-server` |

Se um dia o app passar a enviar `Content-Security-Policy`, liberar
`gc.viravoto.coletivo.net.br` em `script-src` e `connect-src`/`img-src`
(beacon).
