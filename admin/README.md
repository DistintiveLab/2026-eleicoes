# Painel admin do lote

Monitoramento somente leitura do orquestrador do projeto **2026-eleicoes**: status de cada script de coleta (com o motivo dos
pulos, inclusive dependencias), grafo de dependencias declarado, frescor
das series no banco e historico das execucoes. Gerada por
`beep::deploy_admin()` como launcher sobre o pacote beep.

Tema visual: paleta `govbr` (alternavel pelo botao da barra superior).

## Rodar localmente

```r
shiny::runApp("admin")
```

Requisitos: pacote beep instalado e banco beepdb alcancavel com as
mesmas credenciais do orquestrador (variaveis de ambiente `user`,
`password`, `host`, `dbname`).

## Seguranca

NAO publicar esta app em host acessivel externamente sem autenticacao
na frente (shinymanager, shinyproxy ou VPN): ela expoe internals do
controle e exige acesso direto ao banco de dados.

