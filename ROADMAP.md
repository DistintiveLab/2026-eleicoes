# Roadmap — Painel Eleições 2026

Projeto: painel analítico das Eleições 2026 centrado em R, com banco de dados **`eleicoes`**, cobrindo votos por candidato/partido, votos nulos e brancos, abstenção acima de 25% por seção eleitoral, gastos de campanha e cruzamento com perfis sociodemográficos do **Censo 2022 IBGE** (microdados e agregados por bairro/setor censitário).

**Contexto temporal (verificado em 05/10/2026):** o 1º turno ocorreu em 04/10/2026; o 2º turno (onde houver) é em 25/10/2026. Já há **10 séries 2026** no portal de dados abertos do TSE (tag "Ano 2026", ver §3.1), incluindo eleitorado por seção, candidaturas, prestação de contas e pesquisas eleitorais. Falta apenas a série de **resultados por seção** (`resultados-2026`, padrão de 2022/2024), esperada nos dias seguintes à apuração.

**Piloto definido (05/10/2026) — Distrito Federal, 2º turno em 25/10:**

- **Objetivo analítico:** mapear dissonâncias de orientação de voto entre esferas para priorizar esforços de virada de votos a favor de **Lula (presidente, PT 13)** e **Leandro Grass (governo do DF, PT 13)**.
- **Oponentes principais:** Flávio Bolsonaro (PL 22, chapa pura — 47,03% × 45,16% de Lula no 1ºT) e Celina Leão (PP 11 — 49,93% × 34,47% de Grass no 1ºT).
- **Coligações:** Grass = "DF do Povo" (PDT + Fe Brasil PT/PCdoB/PV + PSOL-REDE; vice Dora Gomes, PV). Celina = "Propósito e Ação" (PP/União, Republicanos, MDB, PODE, PL, DC, Mobiliza, Democrata, PRD/Solidariedade). Lula = "Brasil Pronto pra Mais" (PT, PCdoB, PV, PSOL, REDE, PDT, PSB) — única coligação formal da presidencial.
- **Indicadores de dissonância (por seção/bairro, ver §6):**
  - **D0 — teto de virada ("até")**: brancos + nulos + abstenções + votos em terceiros por local de votação (métrica `ate` do `ondedapraconversar`, §3.6c); flag "virável" quando o líder vence por menos que o bloco aberto. Computar para presidência **e** governo do DF.
  - **D1 — transferência presidência → governo:** gap = % válidos arco-Lula − % Grass. Onde Lula > Grass: eleitor lulista que não votou Grass → prioridade de virada no DF.
  - **D2 — defesa (inverso):** gap = % Grass − % arco-Lula. Onde Grass > Lula: esforço de transferência para Lula.
  - **D3 — coattails federais:** desempenho do arco aliado em dep. federal (PT/PSOL/PV) vs. presidência por local de votação.
  - **D4 — mobilização:** abstenção > 25% e nulos/brancos cruzados com perfil Censo 2022 (idade, renda, cor/raça) — eleitorado potencial não capturado.
  - **D5 — swing 1ºT → 2ºT** (pós-25/10): variação por local de votação entre turnos.
- **Dissonâncias estruturais a modelar:** PSB aliado formal de Lula (vice Alckmin) mas com candidatura própria ao governo do DF (Cappelli, 2,23%); PDT aliado nas duas esferas; PL elegeu as 2 senadoras (Michelle Bolsonaro, Bia Kicis) e 3 dos 8 dep. federais do DF.

---

## 1. Escopo analítico (indicadores do produto)

| Bloco | Indicadores |
|---|---|
| Votação | votos nominais por candidato/cargo, votação por partido, eleito/não eleito |
| Qualidade do voto | votos nulos, votos brancos, % por seção/município |
| Comparecimento | aptos, comparecimento, **abstenção por seção com alerta > 25%** |
| Gastos de campanha | receitas, despesas contratadas e pagas, gasto/voto, por tipo de recurso/fornecedor |
| Perfil sociodemográfico (Censo 2022) | estrutura etária, cor/raça, alfabetização, rendimento do responsável, características de domicílio — por bairro e (quando viável) setor censitário |
| Território | níveis: município, bairro, setor censitário; localização dos locais de votação |
| Pesquisas eleitorais (opcional) | pesquisas registradas (`pesquisas-eleitorais-2026`) x resultado apurado |
| Dissonâncias (piloto DF) | gap do arco aliado entre esferas (presidente × governador) por seção/bairro; coattails federais; abstenção/nulos; swing 1ºT→2ºT |

---

## 2. Decisões de arquitetura (proposta a validar na Fase 0)

- **Núcleo em R**, pipeline reprodutível com `{targets}` + `{renv}` (conforme diretriz do README: "R centrado").
- **Banco de dados `eleicoes`**:
  - Fase A (MVP): **DuckDB** (`eleicoes.duckdb`) — zero infraestrutura, ótimo para leitura analítica e para os volumes envolvidos (detalhe por seção BR completo tem vários GB).
  - Fase B (se multiusuário/web): **PostgreSQL + PostGIS**, database nomeada `eleicoes`. Os scripts devem ser agnósticos via `{DBI}` para facilitar a migração.
- **Painel**: Shiny (`{bslib}` + `{leaflet}` + `{plotly}`/`{ggplot2}`) ou Quarto dashboard para relatórios estáticos + Shiny para o painel vivo.
- **Alertas sonoros ("beep")**: interpretado como alertas no painel quando gatilhos disparam (ex.: abstenção > 25%). Ver gotcha sobre `{beepr}` na seção 7.
- **Camada geoespacial**: shapefiles/gpkg do IBGE lidos com `{sf}`; `{geobr}` como conveniência (verificar cobertura do Censo 2022, senão baixar direto do geoftp).

---

## 3. Fontes de dados (todas verificadas em 05/10/2026)

### 3.1 TSE — Portal de Dados Abertos (CKAN)

- **Portal**: `https://dadosabertos.tse.jus.br/` — a API CKAN é aberta a clientes automatizados (testado com requisições diretas). Arquivos servidos por CDN (padrão 2026: `cdn.tse.jus.br/estatistica/sead/eleicoes/eleicoes2026/<assunto>/...`). Cada zip tem um par `.sha512` para verificação de integridade.
- **Descoberta de datasets**: `package_search?fq=tags:%22Ano+2026%22` ou `package_show?id=<nome>`. **Não confiar em `package_list`** — constatado cache desatualizado em 05/10/2026 (omitia datasets criados em 03–04/10).
- **A página principal do TSE (tse.jus.br) bloqueia clientes automatizados (HTTP 403)** — trabalhar sempre com o portal CKAN.
- **No R, usar `{ckanr}` como cliente primário da API** — manutenção retomada no repo ropensci/ckanr (commits ativos em set/2026: tratamento de erros, compat. CKAN 2.11); `{httr2}`/`{httr}` + `{jsonlite}` apenas como fallback para ações/parâmetros não cobertos pelo pacote (decisão de projeto).

Os 10 datasets com tag "Ano 2026" (verificados em 05/10/2026 via `package_search`):

| Dataset (`id` CKAN) | Arquivos-chave | Uso |
|---|---|---|
| `candidatos-2026` | `consulta_cand_2026.zip` (+ complementar e redes sociais; 92 recursos com fatias por UF) | cadastro de candidaturas |
| `eleitorado-2026` | `perfil_eleitor_secao_2026_{UF...ZZ}.zip` (27 UFs + ZZ), `eleitorado_local_votacao_2026.zip`, `perfil_eleitorado_2026.zip`, `perfil_eleitor_deficiencia_2026.zip`, `transf_temporaria_secao_2026.zip` | perfil do eleitorado por seção (idade, escolaridade, sexo) + eleitorado por local de votação |
| `prestacao-de-contas-eleitorais-2026` | `prestacao_de_contas_eleitorais_candidatos_2026.zip`, `..._orgaos_partidarios_2026.zip`, `CNPJ_campanha_2026.zip`, `receita_documento_2026.zip`, `despesa_documento_2026.zip`, `extrato_bancario_{candidato,partido}_2026.zip` | gastos de campanha |
| `prestacao-de-contas-partidarias-2026` | `prestacao_contas_anual_partidaria_2026.zip` (+ nota fiscal) | contas partidárias (contexto) |
| `pesquisas-eleitorais-2026` | `pesquisa_eleitoral_2026.zip`, `pesquisa_{contratante,pagante}_2026.zip`, `questionario_pesquisa_2026.zip`, `bairro_municipio_2026.zip` | pesquisas registradas; **`bairro_municipio` é a tabela de referência de bairros do próprio TSE** — insumo direto para o matching seção↔bairro (§6) |
| `resultados-2026-logs-...-gedai-1-turno` | `log_gedai_1t_{UF}_{ts}.zip` (112 recursos) | logs das urnas (auditoria) |
| `resultados-2026-correspondencias-...-1-turno` | `CESP_1t_{UF}_{ts}.zip` (112 recursos) | correspondências esperadas/efetivadas urna↔totalização |
| `processual-2026` | `processo_eleitoral_2026.zip`, `recursos_eleitorais_2026.zip` etc. | judicialização (opcional) |
| `mesarias-mesarios-e-funcoes-especiais-2026` | mesárias/mesários por seção | operação logística (opcional) |
| `denuncias-eleitorais` | denúncias eleitorais 2026 | fiscalização (opcional) |

**Ainda não publicado:** `resultados-2026` (votação por seção) — `package_show?id=resultados-2026` retorna 404 e ele não aparece na tag "Ano 2026". Pelo padrão 2022/2024, trará `detalhe_votacao_secao_2026.zip` (zip nacional) e/ou `votacao_secao_2026_{UF}.zip` (por UF) — em 2022 existem ambos — mais o dataset irmão `resultados-2026-boletim-de-urna`. É essa a série que alimenta votos, nulos/brancos e abstenções por seção.

> Enquanto `resultados-2026` não sai, desenvolver todo o pipeline com **`detalhe_votacao_secao_2022.zip`** + **`votacao_secao_2022_{UF}.zip`** (e 2024 municipais, se útil) — o schema é homogêneo entre anos (com renomeações pontuais de colunas).

### 3.2 IBGE — Censo 2022

Base FTP: `https://ftp.ibge.gov.br/Censos/Censo_Demografico_2022/`

| Caminho | Conteúdo |
|---|---|
| `Agregados_por_Setores_Censitarios/Agregados_por_Setor_csv/` | zips nacionais por tema: `Agregados_por_setores_{basico, demografia, cor_ou_raca, alfabetizacao, caracteristicas_domicilio1-3, parentesco, obitos, domicilios_indigenas, domicilios_quilombolas, pessoas_indigenas, pessoas_quilombolas}_BR.zip` |
| `Agregados_por_Setores_Censitarios/Agregados_por_Bairro_csv/` (e `_xlsx`) | **mesmos temas agregados por bairro** — chave do cruzamento territorial |
| também `Agregados_por_{Distrito, Municipio, SubDistrito}_csv/` | níveis territoriais superiores |
| `Agregados_por_Setores_Censitarios/malha_com_atributos/` | malha já com indicadores joinados |
| `Agregados_por_Setores_Censitarios/dicionario_de_dados_agregados_por_setores_censitarios_20260520.xlsx` | dicionário de variáveis (atualizado em 20/05/2026) |
| `Agregados_por_Setores_Censitarios_Rendimento_do_Responsavel/` | **rendimento do responsável por domicílio por setor** (base do perfil de renda territorial) |
| `Microdados_e_Areas_de_Ponderacao/Microdados_de_acesso_Publico/` (`csv/`, `txt/`) | **microdados da amostra** (pessoas/domicílios) para perfis detalhados: escolaridade, ocupação, renda individual etc. |
| `Microdados_e_Areas_de_Ponderacao/Documentacao/` | layouts e dicionários dos microdados |
| `Microdados_e_Areas_de_Ponderacao/Areas_de_Ponderacao/` | malhas/identificação das áreas de ponderação |
| `Favelas_e_comunidades_urbanas_Resultados_do_universo/` | enriquecimento opcional por setor |
| `Populacao_por_cor_ou_raca_Resultados_do_universo/` | apoio temático |

### 3.3 IBGE — Malhas territoriais (geofeed)

`https://geoftp.ibge.gov.br/organizacao_do_territorio/malhas_territoriais/malhas_de_setores_censitarios__divisoes_intramunicipais/censo_2022/`

- `bairros/` → subpastas `shp/` e `gpkg/` — **malha de bairros 2022 existe** (preferir gpkg)
- `setores/`, `distritos/`, `subdistritos/`, `tabelas_complementares/`
- `Historico_formacao_Setores_Censitarios_2010_2022.{ods,xlsx}` — correspondência de setores 2010↔2022 (necessário para séries históricas)
- `Descricoes_limites_Setores_Censitarios_20251010.zip`, `Dicionario_de_dados_malha_agregados.xlsx`

### 3.4 IBGE — APIs (nível municipal e comparativos)

- API de Agregados: `https://servicodados.ibge.gov.br/api/docs/` (SIDRA) — útil para comparar municípios sem baixar microdados.

### 3.5 Dados estáticos curados (nossos, versionados no repositório)

- **`data-raw/partidos_arco_2026.csv`** — classificação de cada partido em **dois planos** (`arco_presidencial` × `arco_governo_df`: `aliado_formal`/`proximo`/`variavel`/`oponente`/`oponente_principal`/`outros`), com número eleitoral e notas de contexto.
- **`data-raw/candidaturas_piloto_2026.csv`** — candidaturas do recorte do piloto (presidente + governador/senado/dep. federal do DF), campo (`nossa`/`aliada`/`oponente`/`oponente_principal`/`outros`), coligações, vices e resultado do 1º turno.
- **Fonte dos números do 1ºT:** levantamento de 05/10/2026 (TSE via G1, Agência Senado, HubPolítico, Wikipédia) — **conferir e substituir quando `resultados-2026` sair**.
- **Pendências:** números eleitorais de PRD e Democrata (marcados `NA`); confirmar se o PCB lançou candidato próprio à presidência.
- **Uso no pipeline:** juntar com `votacao_secao` por `NR_PARTIDO`/`NR_VOTAVEL` para computar "arco Lula" e "arco Grass" por seção (e comparar com 2022/2018 para tendência).
- **Perfil sociodemográfico por RA (gerado em 05/10/2026 por `R/prep_perfil_ra_df.R`)**:
  - `data/pop_ra_df.csv` — Censo 2022 por RA: população, área/densidade, estrutura etária (0-14/15-29/30-59/60+), % feminina, % preta+parda, renda média e mediana do responsável, domicílios;
  - `data/locais_votacao_ra_df.csv` — as 7.050 seções do DF com local, endereço, bairro TSE, lat/lon, RA (metodo geo/alias) e eleitores da seção;
  - `data/eleitorado_ra_df.csv` — perfil do eleitorado por RA (2.253.132 eleitores): faixas etárias (16-24/25-44/45-59/60+), sexo, escolaridade, cor/raça;
  - `data/perfil_ra_df.csv` — consolidado população × eleitorado (razão eleitores/habitante).
  - Zips brutos e dicionários em `data-raw/raw/{ibge,tse}/`.

### 3.6 Referência externa: `ondedapraconversar` (fork de `mateuspestana/ondedapraconversar`)

Projeto-irmão: mapa público para voluntários "onde dá pra conversar e virar voto para o Lula no 2º turno de 2026" (React/Leaflet + Vercel; pipeline em Python). Analisado em 05/10/2026 — o que reaproveitar:

- **(a) Boletins de urna do 1ºT já estão acessíveis** via `resultados.tse.jus.br`, sem esperar o dataset `resultados-2026`: config `oficial/comum/config/ele-c.json` (verificado ao vivo) → pleito **3220** (ele2026, 04/10) com eleições **6257** (Presidente), **6259** (Governador/Senador/Dep. Federal/Dep. Distrital — cobre todas as disputas do DF) e **6261** (Conselheiro Distrital); 2ºT mapeado como 6258/6260. Download por urna em `arquivo-urna/{pleito}/dados/{uf}/{mun}/{zona}/{secao}/` — script `baixar_boletins.py` (32 threads, **rate limit ≤85 req/s — o TSE bloqueia ~10 min acima de ~100 req/s**).
- **(b) Parser `.bu.dat` (ASN.1/DER) puro** — `boletim.py`, com validação embutida (Σ votos = comparecimento; aptos ≥ comparecimento; "campo errado é recusa, não palpite"). Sem equivalente em R conhecido: rodar como utilitário Python chamado do pipeline R (`system2()`), ou portar a lógica.
- **(c) Métricas de virada**: `ate` = brancos + nulos + abstenções + votos em terceiros (teto de virada do local), flag `viraveis` (líder na frente, mas diferença < abertos), agregação `porBairro()` — complementa nossas D1–D5; no DF, computar também para Grass × Celina.
- **(d) Unidade "região"**: urnas no mesmo ponto (coordenada arredondada a 4 casas ≈ 11 m) somadas entre zonas; seção principal + agregadas (agregada não tem BU próprio) — adotar como granularidade de campo.
- **(e) Geocodificação CNEFE em cascata** (`geocodificar_locais.py` + `baixar_cnefe.py`): estabelecimento → endereço → rua → localidade → CEP → escola_localidade → núcleo, com validação (≤2 km do CEP, ≤4 km do centróide do bairro) e flag `aprox` — fallback para locais sem lat/lon do TSE (no DF 2026 a cobertura TSE foi total; reter para outras UFs).
- **(f) Empacotamento de dados estáticos**: grade `celulas/{lat}_{lon}.json` (0,25°), `pontos.json` delta-encoded, índice de busca por prefixo sem serviço externo, escrita atômica `.parcial` — referência para servir o painel barato em CDN.
- **(g) Fichas de conversa com citações conferidas contra os PDFs dos programas** (`conferir_citacoes.py`) — padrão de qualidade para material de campo.
- **Ressalvas**: repositório **sem LICENSE** (usar internamente / consultar os autores); caminhos hardcoded no pipeline; o front é outra stack (não R) — nosso núcleo analítico em R pode exportar os JSONs que aquele formato de front consome.

---

## 4. Fases

### Fase 0 — Fundação (semana 1)
- `git init`, estrutura `{targets}` (`_targets.R`, `R/`, `data-raw/`, `data/`), `{renv}`.
- Decisões: UFs prioritárias (BR completo ou recorte?), motor do banco (DuckDB → PostGIS), ferramenta do painel.
- Funções utilitárias: download+unzip em memória, leitura de CSV TSE (encoding Latin-1, separador `;`), normalização de nomes de municípios.
- **Pronto quando**: `targets::tar_make()` roda end-to-end com um dataset-exemplo.

### Fase 1 — Ingestão eleitoral básica (semanas 1–2) — fontes já disponíveis
- Baixar e conformar: `consulta_cand_2026`, `perfil_eleitor_secao_2026_{UF}`, `eleitorado_local_votacao_2026`.
- Tabela de correspondência **código de município TSE ↔ código IBGE** (chaves distintas! ver seção 7), com testes de unicidade por UF.
- **Pronto quando**: tabelas conformadas no banco com validação `{pointblank}` (sem NA em chaves, valores ≥ 0).

### Fase 2 — Resultados por seção (semanas 2–4)
- **Caminho imediato (não bloquear pelo dataset):** baixar boletins de urna do 1ºT 2026 direto de `resultados.tse.jus.br` (padrão `ondedapraconversar`, §3.6a) — resultado por urna já disponível, inclusive para Grass × Celina e senado no DF.
- Desenvolver com `detalhe_votacao_secao_2022.zip` + `votacao_secao_2022_{UF}.zip` (mesmo schema esperado em 2026) para a via bulk.
- Métricas por seção: aptos, comparecimento, abstenções, brancos, nulos, votos por candidato (formato longo).
- Monitorar a chegada de `resultados-2026` e `resultados-2026-boletim-de-urna` com job diário consultando `package_search?fq=tags:%22Ano 2026%22` (não usar `package_list` — cache desatualizado) e plugar os zips 2026 assim que publicados.
- **Pronto quando**: % abstenção por seção calculada e flag > 25% testada contra 2022.

### Fase 3 — Censo 2022: agregados territoriais (semanas 3–5)
- Ingestão dos agregados por **setor** e por **bairro** (basico, demografia, cor_ou_raca, alfabetizacao, domicilio1-3) + **rendimento do responsável** por setor.
- Construção de `agg_bairro_socioeconomico`: % jovens/adultos/idosos, % preta+parda, % alfabetizados, renda média do responsável, densidade domiciliar.
- **Pronto quando**: indicadores por bairro para todos os municípios-alvo, cruzáveis por código IBGE.

### Fase 4 — Microdados do Censo 2022 (semanas 4–6) — perfis sociodemográficos detalhados
- Ler microdados da amostra (`Microdados_de_acesso_Publico/`, layouts em `Documentacao/`) com R; identificar na documentação o **menor nível geográfico disponível** (tipicamente município e, conforme documentação, área de ponderação).
- Perfis: escolaridade detalhada, ocupação, renda individual, idade/sexo/cor cruzados.
- **Usar sempre os pesos de amostragem** (`{survey}` ou weighted means); não somar linhas cruas.
- Microdados servem para perfis de **município/área de ponderação**; para bairro/setor, usar os agregados (Fase 3). Não estimar domínios pequenos direto da amostra (CV alto).
- **Pronto quando**: perfil sociodemográfico ponderado por município validado contra tabelas oficiais SIDRA (tolerância ~1%).

### Fase 5 — Camada geoespacial e correspondência seção ↔ território (semanas 5–7)
- Malhas: bairros 2022 (gpkg) + setores; municípios.
- Enlaçamento seção eleitoral → território (o ponto metodológico mais delicado; ver seção 6).
- **Pronto quando**: cada local de votação do recorte tem um bairro atribuído com taxa de match reportada (meta > 95% por município).

### Fase 6 — Banco `eleicoes` conformado (semanas 6–8, em paralelo)
- Modelo estrela (esboço na seção 5), cargas idempotentes via `targets`, validações `{pointblank}`, testes `{testthat}` nas transformações-chave (abstenção, totais por seção batendo com totais de zona/município).
- **Pronto quando**: consultas do painel rodam só do banco, sem recomputar Raw.

### Fase 7 — Painel + alertas (semanas 7–9)
- Páginas: (1) panorama município/bairro; (2) abstenção e nulos/brancos com **alerta sonoro/visual para seções > 25% de abstenção**; (3) perfil sociodemográfico do território; (4) gastos de campanha (gasto/voto); (5) mapa interativo.
- **Pronto quando**: usuário navega do município ao bairro e dispara o alerta de abstenção.

### Fase 8 — Gastos de campanha (semanas 5–9, trilha paralela)
- `prestacao_de_contas_eleitorais_candidatos_2026` + `receita_documento`/`despesa_documento` + `CNPJ_campanha` (liga CNPJ de campanha ↔ candidatura).
- Indicadores: total arrecadado/gasto por candidato e partido, gasto/voto, origem de recursos, snapshot semanal durante a campanha (prestação é atualizada; versão final só após o pleito).
- **Pronto quando**: ranking de gasto/voto por cargo no recorte.

### Fase 9 — Pós-2º turno (após 25/10/2026)
- Recarga final de resultados e prestação final de contas; comparativos 2018/2022/2026 (usar `Historico_formacao_Setores_Censitarios_2010_2022` quando quiser voltar a setores de 2010).
- Relatório executivo automatizado (Quarto).

**MVP (mínimo viável)** = Fases 0–3 + versão simples da 7: painel município/bairro com abstenção, nulos/brancos e perfil censitário básico. Gastos e microdados entram na sequência.

---

## 5. Modelo de dados (esboço)

```
dim_municipio      (cod_tse, cod_ibge7, uf, nome)
dim_bairro         (cod_bairro_ibge, cod_municipio, nome)
dim_setor          (cod_setor, cod_bairro, cod_municipio)
dim_zona / dim_local_votacao  (uf, nr_zona, local, endereco, bairro_norm)
dim_candidato      (sq_candidato, nome, partido, cargo, situacao)
dim_partido        (numero, sigla, federacao)
fct_votacao_secao  (ano, uf, cod_tse_mun, zona, secao, candidato, votos)
fct_secao_totais   (ano, ..., aptos, comparecimento, abstencoes, brancos, nulos)
fct_perfil_secao   (ano, ..., faixas de idade/escolaridade/sexo do eleitorado)
fct_receita / fct_despesa  (ano, sq_candidato|cnpj, valor, data, fonte/fornecedor)
agg_bairro_censo   (indicadores da Fase 3)
agg_setor_censo    (indicadores por setor + rendimento responsável)
```

---

## 6. Metodologia: cruzamento seção eleitoral ↔ território (core do projeto)

1. **Seção eleitoral é unidade de votação, não de residência.** O cruzamento com perfil sociodemográfico é aproximado: assume-se que o eleitor vota perto de onde mora. Documentar essa limitação no painel.
2. **Coordenadas oficiais existem**: `eleitorado_local_votacao_{ANO}.zip` traz `NR_LATITUDE`/`NR_LONGITUDE` por seção (validado em 2026). Estratégia validada no piloto DF (100% de match seção→RA):
   - **a. Spatial join** do ponto (lat/lon, CRS 4674) com a malha IBGE via `sf::st_join` — caminho preferencial e determinístico;
   - **b. Bairro do local** como validação/fallback (alias de nomes: TSE usa subdivisões tipo "CEILÂNDIA NORTE"; concordância alias×spatial no DF: 88,5%);
   - **c. Último fallback**: nível zona ou município.
3. Recomendação: **nível de análise bairro/RA** e município; setor censitário quando houver necessidade de granularidade fina (a malha de setores + agregados por setor cobrem, mas os zips são nacionais e pesados).
4. Série histórica territorial: setores 2022 ≠ 2010; para comparar, usar `Historico_formacao_Setores_Censitarios_2010_2022`.

---

## 7. Gotchas técnicos (economizam dias de tentativa e erro)

- **Encoding**: CSVs do TSE (e os `txt` do IBGE) usam **Latin-1/Windows-1252**, separador `;`, decimal `,` — usar `readr::read_csv2(..., locale = locale(encoding = "Latin1"))` ou equivalente.
- **DF não tem "bairros" no IBGE**: a hierarquia é 1 município (Brasília) → 1 distrito → **33 subdistritos = RAs**; os agregados por bairro não cobrem o DF — usar o nível **subdistrito** (`Agregados_por_subdistritos_*`) e a malha `DF_subdistritos_CD2022.gpkg`.
- **Bairros do TSE no DF são mais finos que RA** ("CEILÂNDIA NORTE", "ASA SUL", "SETOR SUL" de Taguatinga...): mapa de aliases + spatial join em `R/prep_perfil_ra_df.R` resolve (100% de match; concordância alias×geo 88,5%).
- **Valor `"."` nos agregados IBGE significa zero** (força coluna para character) — converter com `x[x=="."] <- 0`.
- **Perfil do eleitorado TSE**: categoria de faixa etária "Inválida" existe (irrelevante em volume); escolaridade tem 9 níveis — bucketizar conforme script.
- **Códigos de município TSE ≠ IBGE**: o join territorial exige tabela de correspondência (por nome normalizado + UF, com revisão dos empates). Nunca cruzar pelo nome cru.
- **Nomes de colunas mudam entre anos** nos arquivos TSE — conformar por posição semântica + dicionário próprio, não por nome.
- **`resultados-2026` (votação por seção) não publicado ainda** (05/10/2026): monitorar via `package_search?fq=tags:%22Ano+2026%22` — o `package_list` está com cache desatualizado (omitia datasets criados em 03–04/10/2026), e a página HTML do TSE dá 403 para bots. Enquanto isso, boletins de urna via §3.6a.
- **Endpoint de boletins (`resultados.tse.jus.br`)**: manter ≤85 req/s (bloqueio de ~10 min acima de ~100); validar por urna: Σ votos = comparecimento e aptos ≥ comparecimento.
- **`{ckanr}` em manutenção ativa** (retomada 2026, último commit set/2026): usar como cliente primário; se algum endpoint/parâmetro falhar no pacote, cair para chamada direta `{httr2}` + `{jsonlite}`.
- **`{beepr}` toca na sessão R (servidor), não no navegador** — para alerta sonoro em painel web, embutir `<audio>` e disparar via JS/custom message em Shiny.
- **Microdados da amostra têm pesos** — toda estatística precisa ser ponderada; não usar para bairro/setor (domínios pequenos).
- **Rendimento por setor** vem da pasta separada `Agregados_por_Setores_Censitarios_Rendimento_do_Responsavel/`, não dos zips principais.
- **Preferir gpkg a shp** nas malhas (mais leve e sem limite de nome de coluna).
- `malha_com_atributos/` já traz malha + indicadores joinados — pode eliminar um passo de ingestão.
- Prestação de contas muda ao longo da campanha (snapshots semanais; versão final pós-pleito) — guardar data do snapshot em toda carga.

---

## 8. Stack R sugerida

`{targets}`, `{renv}`, `{ckanr}` (API TSE; fallback `{httr2}` + `{jsonlite}`), `{DBI}`, `{duckdb}` (→ `{RPostgres}`/PostGIS), `{arrow}` (parquet intermediário), `{readr}`, `{readxl}`, `{dplyr}`, `{tidyr}`, `{stringr}`, `{janitor}`, `{fuzzyjoin}`, `{sf}`, `{geobr}`, `{survey}`, `{pointblank}`, `{testthat}`, `{shiny}`, `{bslib}`, `{leaflet}`, `{plotly}`, `{ggplot2}`, `{gt}`, `{beepr}`.

---

## 9. Cronograma e marcos

| Marco | Quando | Conteúdo |
|---|---|---|
| M1 — Pipeline verde | semana 1 | Fase 0 concluída |
| M2 — Eleitorado+candidaturas no banco | semana 2 | Fases 1 |
| M3 — Motor de resultados pronto (com 2022) | semana 4 | Fase 2 |
| M4 — Censo por bairro/setor + microdados | semana 6 | Fases 3–4 |
| M5 — Match seção↔bairro > 95% | semana 7 | Fase 5 |
| M6 — MVP no ar | semana 8–9 | Fases 6–7 (parcial) |
| M7 — Gastos de campanha | semana 9 | Fase 8 |
| M8 — Recarga 2º turno + relatório final | pós-25/10/2026 | Fase 9 |

---

## 10. Riscos e questões em aberto

1. **Recorte territorial**: BR inteiro x UFs prioritárias? (impacta volume de `detalhe_votacao_secao` e tempo de carga).
2. **"Beep" no README**: interpretado aqui como alertas sonoros do painel; confirmar com o requisitante (alternativa: era referência a alguma ferramenta de shapefiles — nesse caso, `{sf}`/`{geobr}` cobrem).
3. **Motor do banco definitivo** (DuckDB x PostgreSQL/PostGIS) — decidir na Fase 0.
4. **Qualidade do campo bairro nos dados TSE** varia por UF/município — medir taxa de match no início da Fase 5 para calibrar expectativa.
5. ~~Geocodificação depende de cota/API externa~~ **Resolvido**: `eleitorado_local_votacao_2026` já traz lat/lon por seção — spatial join direto com malhas IBGE.
6. Pendência: taxa de alfabetização por RA exige o arquivo por **setor** (nos agregados por bairro/subdistrito, o bloco por idade é o total 15+, não os alfabetizados).
