# beep — passo a passo para os primeiros indicadores (eleições, DF)

Stack: `tsebr` (coleta TSE) + `censoagg` (Censo 2022) → `beep::run_app()` / `run_panel()` → DW PostgreSQL (séries longas `local, periodo, valor`).

## 0. Pré-requisitos (uma vez)

```r
install.packages("remotes")
remotes::install_github(c("DistintiveLab/tsebr",
                          "DistintiveLab/censoagg",
                          "DistintiveLab/beep"))
```

PostgreSQL no ar com database criada (neste projeto: `painel_eleicoes`; apps legados usam `aedidb`) e `.Renviron` na raiz do projeto (NÃO versionado):

```
user=distintive
password=***
host=127.0.0.1
dbname=painel_eleicoes
```

Schema do DW: use os recursos do próprio beep (`admin_app()` / `deploy_admin()`; dump de referência `ddlx.sql` no repo do beep).

## 1. Primeiros dados eleitorais (via `run_app()`)

```r
beep::run_app()
```

1. Aba **upload** → fonte **TSE (tsebr)**.
2. Escolha a família e preencha os parâmetros; o módulo mostra a call gerada, ex.:

```r
tse_resultados_municipio(2022, uf = "DF", cargo = "PRESIDENTE", nr_votavel = 13)
tse_detalhe_municipio(2022, uf = "DF", metrica = "abstencoes")   # também: comparecimento, votos_nulos, votos_brancos, aptos
```

3. Confirmar: o módulo registra a fonte (idempotente) e grava a série longa no DW.

> Quando `resultados-2026` sair no CKAN, as mesmas funções funcionam com `ano = 2026` (o tsebr descobre recursos pelo portal, sem caminhos fixos).

## 2. Primeiros dados do Censo (município)

No mesmo app, fonte **Censo (censoagg)**, ou direto:

```r
censoagg::censo_variaveis(2022, dataset = "tracts")   # escolha os V... no dicionário
censoagg::agregar_setores(dataset = "Basico", variaveis = c("V0001", "V0002"),
                          ano = 2022, nivel = "municipio")   # pop, domicílios
```

**Suficiente para indicadores municipais?** Sim para o universo do Censo: população, idade, cor/raça, alfabetização, domicílios e rendimento do responsável (dataset `DomicilioRenda`) agregados a município (percentuais = razão entre contagens, feita depois no DW). Limitações conhecidas: escolaridade detalhada/ocupação dependem de microdados (2010 ponderado OK; 2022 com restrições — ver nota do censoagg) e o nível **RA/bairro do DF não existe no censoagg** (vai até município/setor) — esse gap já está coberto por `R/prep_perfil_ra_df.R` (subdistritos IBGE).

## 3. Indicador novo → catálogo

1. Grave a série com a convenção de `orig_name` (ex.: `elei_prespref` para o gap presidente×governador — ver ROADMAP §Piloto, D1–D5).
2. Rode `beep::atualizar_indicadores()` e `beep::atualizar_grupos_indicadores()` para reconciliar o catálogo/grupos (idempotente).

## 4. Ver o resultado

```r
beep::run_panel()   # ou o app local em painel/ deste repo
```

Conferência rápida do DF: 7.050 seções (2026), 2.253.132 eleitores — os totais gravados precisam bater com `data/locais_votacao_ra_df.csv`.
