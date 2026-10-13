# Roadmap de indicadores e visualização — Virada de votos no 2º turno (Lula × Flávio; Grass × Celina)

**Data:** 12/10/2026 · **2º turno:** 25/10/2026 · **MVP no ar:** quinta 15/10 · **Escopo piloto:** DF (33 RAs, 7.050 seções no cadastro, 6.969 com voto, 2.253.132 eleitores)
**Janela de decisão:** tudo o que não estiver no painel até 15/10 (MVP) não muda a campanha — priorizar o que é computável com os dados já disponíveis.

Este documento ordena o pedido da sessão de 12/10: (a) passar dos indicadores de inventário (brancos/nulos/abstenção, em absoluto ou proporção) para **indicadores de alvo acionável** — onde ir, com quem falar, o que pedir; (b) aproveitar cruzamentos sociodemográficos do Censo (e em breve da PDAD-A 2024) para priorizar; (c) inspirar a camada visual em iniciativas equivalentes.

---

## 1. Mudança crítica de dados (12/10): `resultados-2026` foi publicado

Verificado hoje no CKAN do TSE (`package_show?id=resultados-2026`, dataset criado 06–08/10). Acabou a dependência de boletins de urna via `resultados.tse.jus.br`:

| Arquivo | Conteúdo | Uso |
|---|---|---|
| `cdn.tse.jus.br/estatistica/sead/odsele/votacao_secao/votacao_secao_2026_DF.zip` | votação nominal por seção, 1º turno | base de todos os indicadores V1–V5 |
| `.../detalhe_votacao_secao/detalhe_votacao_secao_2026.zip` | aptos/comparecimento/abstenções/brancos/nulos por seção | teto de virada, excesso de abstenção |
| `.../detalhe_votacao_munzona/detalhe_votacao_munzona_2026.zip` | agregados município/zona | validação de totais |
| `.../relatorio_resultado_totalizacao/Relatorio_Resultado_Totalizacao_2026_DF.zip` | relatório oficial DF | conferência (ver §5a: números reais validados contra munzona) |

Combinar com o que já temos no projeto: `perfil_eleitor_secao_2026_DF` (sexo/idade/escolaridade **por seção** — ouro para cruzamento sociodemográfico), `eleitorado_local_votacao_2026` (lat/lon por seção), `data/locais_votacao_ra_df.csv` (match 100% seção→RA), `data-raw/partidos_arco_2026.csv` (arcos), Censo por RA (`data/perfil_ra_df.csv`) e por setor.

---

## 2. Diagnóstico: o que o painel tem hoje vs. o que falta

| Já no painel (`painel_eleicoes`) | Natureza |
|---|---|
| abstenções e taxa por seção/RA/município, aptos, abstenção 2022×2026 | inventário |
| censo por setor/RA: nº homens, nº mulheres, demografia básica | inventário |
| perfil por RA (pop, idade, cor/raça, renda do responsável, eleitorado) | insumo pronto, ainda sem cruzamento com voto |

**Lacunas:** nenhuma métrica de votação nominal por candidato; nenhum cruzamento comportamento eleitoral × sociodemografia; nenhum índice composto de priorização; visualização ainda sem modo "oportunidade de virada".

---

## 3. Referências externas — o que adotar de cada uma (inspeção 12/10/2026)

| Iniciativa | O que vale adotar |
|---|---|
| **vira_voto / eleicao_2026_1turno** (tatipara, MIT) | Fórmulas prontas: `DEFICIT_2T = (Flávio−Lula) − (2p−1)·OUTROS` (cenário de transferência p=0,5/0,6); `VOTOS_PARA_VENCER = max(0, déficit+1)`; `COTA_META` rateada pela abstenção de cada local; **`SALDO_POR_ABSTENCIONISTA = 2s−1`** com s=Lula/(Lula+Flávio) do local — negativo onde o oponente lidera ⇒ **mobilizar ali ajuda o adversário**; `GANHO_LIQUIDO_ESPERADO = taxa_mobilização × abstenção × saldo`; ranking com **ganho acumulado e % da meta coberta**; pareamento de locais 2022↔2026 em 4 etapas (chave → nome → coordenada ≤150 m → fuzzy). |
| **mapa-duplas.vercel.app** | "Tendem ao 13/22" (estimativa de como os faltosos votariam, pela vizinhança da urna) ⇒ "votos a ganhar"; listas separadas **Conversar** (mudou de voto/votou em outro) × **Mobilizar** (faltosos em locais já nossos); ficha de local com **roteiro de conversa e círculo de 500 m**; botão "perto de mim"; **copiar mensagem pronta para WhatsApp**; "ganho por ponto de comparecimento". |
| **fortalezanasurnas.netlify.app** | Padrão de transparência (`#metodo`); coroplético por bairro com **modos de cor** (mais votado / um candidato / disputa apertada / abstenção / brancos+nulos) e **base de % selecionável** (válidos / comparecimento / aptos); **excesso vs. esperado** (observado − esperado se a área tivesse a taxa da cidade) com significância ~2 DP; ranking clicável; Shift+clique compara áreas. |
| **rafadaguia/analise-de-esforco-por-bairros-lula-2026** | Índice composto de **postos percentuais** (potencial 0–1, segurança, certeza, escala=log(aptos)) com 3 esquemas de pesos (P2 potencial 0,55) e **7 níveis por qcut**; "**terreno perdido**" = queda de Lula acima da queda nacional (desloc − nacional)×válidos; ganho de mobilização = +2 pp de comparecimento × fração nossa dos não-votantes; **temas com portões territoriais** (ex.: saneamento só onde ≥50% sem esgoto); ressalva ética: lê cor/raça mas não usa para priorização. |
| **mapadavirada26.com** | Número-âncora ("diferença a virar: 2.224.965 votos"); camadas = não votaram / votaram em outro / perda desde 2022; perfil "quem tem por perto" ao clicar; materiais persuasivos por 3 perfis de eleitor (não votou/terceiro, pensando no adversário, rejeita o PT). |
| **ondedapraconversar** (já em ROADMAP §3.6) | métrica `ate` (teto de virada = brancos+nulos+abstenções+terceiros), flag `viraveis`, unidade "região" = urnas no mesmo ponto (coordenada 4 casas ≈ 11 m). |
| **tropaviravoto.com, voto-vizinho.momoi-labs.dev, mapa-vira-voto.eleitoral.org.br, ovotodecisivo.com, seuimposto.com, vamoscomlula.eita.coop.br** | **Pendência:** inspeção automatizada falhou (timeout). Rever manualmente até 15/10 e completar esta tabela. |
| **claude.ai/artifact/Fm6yV6cYYBEmk4AsSWpbh** | Não verificável (exige login). Se o autor exportar (HTML/prints), anexar aqui. |

---

## 4. PDAD-A 2024 (IPEDF) — pontos aproveitáveis (questionário inspecionado)

Fonte: `pdad.ipe.df.gov.br` — microdados (moradores + domicílios, chave `A01nficha`, pesos `peso_dom`/`peso_mor`, 99999=NA/88888=não sabe), dicionário XLSX e API (`api.ipe.df.gov.br`). Nível de divulgação: **RA** (35 RAs + 12 municípios da PMB/GO + 16 localidades; sem bairro). Não substitui o Censo para setor (amostral) — usar para **temas por RA**.

Blocos com maior potencial para mensagem/camada temática (numeração do questionário público):

| Tema de campanha | Quesitos PDAD-A 2024 |
|---|---|
| Transferência de renda / programas sociais | **Bloco D Benefícios Sociais:** D15 (recebeu benefício DF/GO), D16_1 transferência de renda, D16_3 alimentação, D16_4 educação; I22 renda de "Auxílio Brasil/Bolsa Família, DF sem Miséria, BPC/LOAS, Auxílio gás" |
| Fome / segurança alimentar | Bloco D SAN (aplicado ao responsável — conferir numeração no PDF; referência na pág. 28) |
| Emprego / informalidade | I03–I22 (procura, regime, carteira I18, esfera, renda do trabalho principal e outros) |
| Moradia / aluguel | B05 valor do aluguel, B06 escritura definitiva, B18_2 esgoto a céu aberto |
| Mobilidade / custo do transporte | I09 meios de transporte ao trabalho, I10 tempo casa→trabalho, H05 transporte escolar |
| Conectividade | C05 acesso à internet no domicílio (banda larga × móvel) |
| Perfil sociocultural | E05 cor/raça, E06 religião, bloco de migração, G06 fecundidade, H01 alfabetização, G05 plano de saúde |

Uso metodológico: **portões territoriais** (só sugerir o tema na RA onde o gatilho dispara, ex.: "custo do ônibus" onde % alta de usuários × renda baixa). Os municípios da PMB/GO servem para contexto de mancha urbana, não para voto no DF.

**Ingestão pelo pacote `DistintiveLab/pdadr`** (12/10): pacote inicial de importação dos dados da PDAD já existe no GitHub da org — usá-lo para baixar/conformar microdados e agregar as variáveis-chave por RA; a integração à interface do `beep` (catálogo/DW) fica como débito técnico pós-2ºT.

---

## 5. Os indicadores (V1–V5 prioritários + futuros)

Convenções: unidade-base = **local de votação** (urnas somadas no mesmo ponto, coordenada arredondada a 4 casas — §3.6d); síntese por **RA**; todas as métricas em % **e** em votos; base de % selecionável (válidos/comparecimento/aptos); suprimir unidades < 200 aptos (ruído + privacidade).

### V1 — Votos para vencer e teto de virada (por local, por disputa)
- **Pergunta:** onde a margem do oponente cabe no eleitorado não alinhado a ele?
- **Fórmulas** (tatipara + ondedapraconversar):
  - `margem = votos_oponente − votos_nosso` (disputa presidencial: Flávio−Lula; governamental: Celina−Grass)
  - `teto_virada = brancos + nulos + abstenções + terceiros`
  - `déficit_2T = margem − (2p−1)·terceiros`, cenários **p=0,5 e p=0,6** (transferência de terceiros)
  - `votos_para_vencer = max(0, déficit+1)`; classes: `à frente` / `virável com a abstenção` (≤ abstenção) / `abstenção insuficiente`
- **Dados:** votacao_secao_2026_DF + detalhe_votacao_secao_2026 (ambos já publicados).
- **Priorização:** ranking por votos_para_vencer; cobertura acumulada da meta DF (`% meta acumulada`).

### V2 — Transferência entre esferas: lulismo não transferido (gap Lula × Grass)
- **Pergunta:** onde há eleitor que votou Lula e não votou Grass (e vice-versa)?
- **Fórmulas:** `gap = pct_Lula − pct_Grass` (válidos, por local); `votos_a_transferir = max(0, votos_Lula − votos_Grass)` — é o volume máximo de eleitor lulista a converter no mesmo território (parcela não votou Grass: terceiros/brancos/nulos/abstenção); inverso onde Grass > Lula = esforço pró-Lula. Onde houver candidato do PSB/PDT forte, marcar dissonância estrutural (§ ROADMAP: Cappelli 2,23%).
- **Visual:** dispersão pct_Lula × pct_Grass por local (bolha = eleitores), diagonal 45° e quadrantes; a distância à diagonal é a oportunidade.

### V3 — Alvo sociodemográfico: eleitoras (e eleitoras jovens) em território virável
- **Pergunta:** onde o público com maior aderência progressista (mulheres; mulheres 16–29) está subaproveitado?
- **Fórmulas:** por seção (perfil_eleitor_secao: sexo × faixa etária), agregado ao local:
  - `alvo_fem = n_eleitoras_local × 1[votos_para_vencer > 0]` (eleitoras em locais viráveis)
  - `alvo_fem_jovem = n_eleitoras_16a29` idem
  - na RA: cruzar com `% fem` e `% 15–29` do Censo (`perfil_ra_df.csv`) para composição e mensagem; **validar a premissa** regredindo `pct_Lula ~ pct_eleitoras` entre locais/RA (a tatipara obteve R²=0,836 com renda+cor+alfabetização a nível municipal — reproduzir a nível local como sanidade).
- **Futuro PDAD:** fecundidade (G06), religião (E06), chefia feminina — refinar a mensagem, nunca microsegmentar indivíduos.
- **Nota ética:** caracterização territorial para orientar conversa e conteúdo; cor/raça entra em diagnóstico de território, não em ranking individual (seguir escolha do rafadaguia).

### V4 — Abstenção excedente "nossa" (excesso × sinal político)
- **Pergunta:** onde deixar de votar mais dói no adversário — ou em nós?
- **Fórmulas:**
  - `esperado = taxa_abstenção_DF × aptos_local`; `excesso = abstenções − esperado`, flag significante > 2 DP (fortalezanasurnas)
  - `saldo_abstencionista = 2s−1`, s = Lula/(Lula+Flávio) do local — **sinal negativo ⇒ não mobilizar** (tatipara)
  - `ganho_esperado = 0,10 × abstenção × saldo` (taxa de mobilização 10%;敏感性 5–15%)
- **Cruzamento Censo:** excesso × % jovem 16–29 × renda do responsável × % preta+parda (RA/setor) ⇒ "abstenção progressista" = prioridade de mobilização; abstenção em território opositor = defesa, não alvo.
- **Saída:** lista "Mobilizar" (mapa-duplas), com cota por local (`abstenção × taxa_cota`).

### V5 — Terreno perdido 2022→2026 (swing territorial)
- **Pergunta:** onde Lula/Grass caiu além da queda estrutural (queda nacional) — e onde subiu?
- **Fórmulas** (rafadaguia + tatipara):
  - parear locais 2022↔2026 (4 etapas; reportar taxa de match — tatipara atingiu 96% dos votos pareados)
  - `desloc = pct_Lula_26_1T − pct_Lula_22_2T` (idem Grass × Ibaneis 22 se útil)
  - `terreno_perdido = max(0, −(desloc − queda_nacional)) × válidos` ; `votos_a_recuperar = max(0, Lula_22 − Lula_26)`
  - locais com desloc > 0 = mensagem "está funcionando" (manter); desloc muito negativo = reconquista.
- **Dados:** votacao_secao_2022_DF + eleitorado_local_votacao_2022 (já referenciados no ROADMAP).

### Futuros (não bloqueiam o 2ºT)
- **V6 — Camadas temáticas com portões** (após ingestão PDAD): tema sugerido por RA (benefício social, SAN, ônibus/tempo, aluguel, internet) conforme gatilho dispare — alimenta roteiro da ficha.
- **V7 — Coattails federais/distritais** (D3 do ROADMAP): arco PT/PSOL/PV em dep. federal × presidência por local.
- **V8 — Swing 1ºT→2ºT** (D5, pós-25/10): recarga e comparativo.

### Índice composto: **IPV — Índice de Potencial de Virada**
Componentes em **posto percentual (0–1)** entre unidades ≥ 200 aptos (rafadaguia, sem MCMC):
1. `potencial` = posto de votos_para_vencer + ganho_esperado (V1/V4/V5 normalizados juntos)
2. `aderência` = posto do alvo sociodemográfico (V3 + perfil Censo da RA)
3. `segurança` = posto do saldo_abstencionista e da estabilidade 22→26 (evitar unidades onde o pêndulo oscila contra)
4. `escala` = posto de log(aptos)

Pesos: **P2 foco potencial 0,55/0,15/0,15/0,15** (padrão da entrega) e P1 equilibrado 0,25×4. Níveis 1–7 por qcut (7 = prioridade máxima). Saída `data/virada_prioridade.csv` com ranking, nível e `% meta acumulada`.

---

## 6. Visualização no painel (nova aba "Virada 2ºT")

Componente novo `painel/R/mod_panel_virada.R` + JS no padrão `painel-map.js`:

1. **Mapa com dois modos** (toggle):
   - **RA (coroplético)**: modos de cor = mais votado / margem / abstenção / brancos+nulos / IPV (padrão fortalezanasurnas + nosso);
   - **Locais (pontos)**: bolha por local de votação — tamanho = eleitores abertos (teto_virada) ou abstenção; cor = situação (`à frente`, `virável`, `abstenção insuficiente`); cluster em zoom afastado (padrão mapa-duplas).
2. **Ranking lateral clicável**: ordenável por IPV / votos_para_vencer / ganho_esperado; coluna de `% meta acumulada`; clique destaca no mapa (padrão tatipara/fortaleza).
3. **Ficha de localidade** (clique): card com número grande "votos para vencer" (presidência e governo), KPIs 2022×2026, composição do eleitorado (eleitoras, jovens), composição Censo/PDAD da RA, bloco "**quem procurar**" (faltosos / terceiros / lulista-sem-Grass) e roteiro curto (padrão mapa-duplas).
4. **Controles**: disputa (presidente/governo), cenário p (0,5/0,6), base de %, mínimo de eleitores, mostrar/ocultar classes de situação.
5. **Aba Baixar**: xlsx com local × indicadores V1–V5 + IPV; botão "copiar mensagem" (template WhatsApp por local).
6. **Seção #metodo** (transparência): fórmulas, cenários, limitações (voto é no local, não na residência; falácia ecológica; supressão de unidades pequenas).
7. Catálogo beep: registrar cada V* como indicador (convenção `orig_name`, ex. `virada_votos_para_vencer`, `virada_gap_esferas`, `virada_alvo_mulheres`, `virada_abst_excedente`, `virada_terreno_perdido`, `virada_ipv`) no nível local (RA via `ra_geo` já mapeada) + `atualizar_indicadores()`.

---

## 7. Sequência de tarefas (MVP: quinta 15/10)

| # | Tarefa | Entradas | Saída | Prazo |
|---|---|---|---|---|
| T0 | Ingestão `votacao_secao_2026_DF` + `perfil_eleitor_secao_2026_DF`; validar totais contra `detalhe_votacao_munzona_2026` (✅ concluído 12/10: comparecimento/brancos/nulos batem exato; válidos nominais +10.299 = anulados sub judice; números reais do 1ºT DF: **Flávio 51,31% × Lula 38,11%** (presidência) e **Celina 49,68% × Grass 34,30%** (governo, base nominal); aptos oficiais 2.243.988, abstenção 19,0%; presidente exige o arquivo nacional `votacao_secao_2026_BR.zip` filtrado por SG_UF=DF — o per-UF só traz a eleição estadual); aptos/abstenção por seção via `locais_votacao_ra_df.csv` + Σ votos | CDN TSE | tabelas conformadas | seg 12/10 |
| T1 | Unidade "local de votação" (urnas por ponto, §3.6d) + pareamento 2022↔2026 de locais (4 etapas tatipara) com taxa de match reportada | T0 + `votacao_secao_2022_DF` + `eleitorado_local_votacao_2022.zip` (cache) | `virada_locais.csv` | seg–ter 12–13/10 |
| T2 | **V1 + V2** por local e por RA (presidência e governo), cenários p | T1 | `virada_local.csv` | ter 13/10 |
| T3 | **V4 + V5**: excesso de abstenção, saldo, terreno perdido, votos a recuperar | T2 + Censo RA | idem | ter 13/10 |
| T4 | **V3**: eleitoras/jovens por local × situação de virável; regressão de sanidade pct_Lula ~ perfil | T2 + perfil_eleitor_secao | idem | qua 14/10 |
| T5 | **IPV** composto (postos, pesos P2/P1, 7 níveis) + `virada_prioridade.csv` + calibragem com militância | T2–T4 | ranking validado | qua 14/10 |
| T6 | Painel MVP: aba "Virada 2ºT" (mapa 2 modos, ranking, ficha, #metodo, xlsx) — lê CSVs autocontidos em `painel/data_virada/`; catálogo beep fica pós-MVP | T5 | **MVP no ar** | **qui 15/10** |
| T7 | PDAD-A 2024 via **`DistintiveLab/pdadr`**: microdados + variáveis-chave por RA (D15/D16, SAN, informalidade, transporte, aluguel) → camadas temáticas na ficha | pdadr/IPEDF | enriquecimento (paralelo, não bloqueia MVP; resto pós-2ºT) | qui 15/10+ |
| T8 | Pós-25/10: recarga 2ºT, V8 swing por local, relatório Quarto comparativo 2018/2022/2026 | resultados 2ºT | relatório | pós |

Débito técnico pós-MVP: indicadores V1–V5/IPV no catálogo beep (`orig_name` `virada_*` + `atualizar_indicadores()`) com série por RA; integração pdadr↔beep.

Critério de pronto por tarefa: totais batem com o oficial ±0,1%; unidades pequenas suprimidas e contadas; documento #metodo atualizado.

## 8. Salvaguardas metodológicas

1. **Voto é no local, não na residência** — dizer no painel; locais de serviço (Plano Piloto) atraem eleitores de outras RAs.
2. **Falácia ecológica**: perfis descrevem áreas, não pessoas; regressões servem de sanidade, não de imputação individual (a inferência ecológica do rafadaguia é possível, mas não cabe na janela de 13 dias).
3. **Cenários explícitos** (p, taxa de mobilização) com sensibilidade — nunca um número único sem intervalo.
4. **Privacidade/ruído**: suprimir < 200 aptos; agregação por local como granularidade pública.
5. **Uso ético de cor/raça e gênero**: caracterização territorial para orientar conversa; sem microsegmentação individual.
6. **Sinal antes de volume**: saldo negativo ⇒ não mobilizar (evitar levar pauta a território que retribui ao adversário).
