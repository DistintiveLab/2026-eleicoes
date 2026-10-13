# Conexao e leituras do DW de indicadores (beepdb) para o Painel.
#
# NAO usa tdbname/userdb/passwddbdev/hostdbdev de proposito: o .Renviron do
# pndr_dashboard aponta essas vars para o DW remoto e elas SOBRESCREVEM as
# variaveis de ambiente da sessao (verificado 2026-09-17, ver
# roadmap_gastos_tributarios.md secao D3). O painel usa o padrao do beep
# (user/password/host/dbname) com defaults locais, mudando de alvo via env
# quando necessario.

#' Conexao com o DW de indicadores
#' @keywords internal
painel_con <- function() {
  DBI::dbConnect(RPostgres::Postgres(),
                 user     = Sys.getenv("user", "beep"),
                 password = Sys.getenv("password", "aEd1#man@gR"),
                 host     = Sys.getenv("host", "127.0.0.1"),
                 dbname   = Sys.getenv("dbname", "beepdb"))
}

#' Executa uma consulta abrindo e fechando conexao propria — usado so na
#' falha de cache, o que poupa os ~4s de handshake nas leituras comuns
#' @keywords internal
painel_com_con <- function(consulta) {
  con <- painel_con()
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  consulta(con)
}

#' Metadados dos indicadores (mdata) com rotulo para selectize
#' @keywords internal
painel_mdata <- function(con) {
  md <- DBI::dbGetQuery(con, paste(
    "SELECT mdata_id, orig_name, data_name, data_desc FROM mdata",
    "ORDER BY orig_name"))
  nome <- ifelse(is.na(md$data_name), md$orig_name, md$data_name)
  md$rotulo <- paste0(nome, " (", md$orig_name, ")")
  painel_mdata_extras(con, md)
}

#' Acrescenta ao catalogo as colunas opcionais do painel: periodicidade
#' (freq_name, de mdata_exts/data_freq), classe do indicador
#' (data_class_id, de mdata_exts), tipo do grafico em destaque
#' (tipo_grafico, de mdata_grafico) e visibilidade nos seletores
#' (visivel, de mdata_visivel). Fail-open: DW sem as tabelas auxiliares
#' segue com defaults (freq/classe ausentes, "linha", visivel)
#' @keywords internal
painel_mdata_extras <- function(con, md) {
  md$freq_name <- rep(NA_character_, NROW(md))
  md$data_class_id <- rep(NA_integer_, NROW(md))
  md$tipo_grafico <- rep(NA_character_, NROW(md))
  md$visivel <- rep(TRUE, NROW(md))
  md$unidade <- rep(NA_character_, NROW(md))
  freq <- tryCatch(DBI::dbGetQuery(con, paste(
    "SELECT e.mdata_id, f.freq_name, e.data_class_id, e.dataunit_num",
    "FROM mdata_exts e",
    "LEFT JOIN data_freq f ON f.data_freq_id = e.data_freq_id")),
    error = function(e) NULL)
  if (NROW(freq)) {
    md$freq_name <- freq$freq_name[match(md$mdata_id, freq$mdata_id)]
    md$data_class_id <- as.integer(
      freq$data_class_id[match(md$mdata_id, freq$mdata_id)])
    md$unidade <- painel_unidade_normaliza(
      freq$dataunit_num[match(md$mdata_id, freq$mdata_id)])
  }
  graf <- tryCatch(DBI::dbGetQuery(con,
    "SELECT mdata_id, tipo_grafico FROM mdata_grafico"),
    error = function(e) NULL)
  if (NROW(graf))
    md$tipo_grafico <- graf$tipo_grafico[match(md$mdata_id, graf$mdata_id)]
  ocultos <- tryCatch(DBI::dbGetQuery(con,
    "SELECT mdata_id FROM mdata_visivel WHERE NOT visivel"),
    error = function(e) NULL)
  if (NROW(ocultos))
    md$visivel[md$mdata_id %in% ocultos$mdata_id] <- FALSE
  md
}

#' Resolve o tipo do grafico em destaque do indicador: o override por
#' indicador (tipo_grafico de mdata_grafico) vence; sem override, o
#' composto (data_class_id 4) ganha "banda" e os demais "linha"
#' (inclui as series replicadas/degeneradas, sem contexto seccional)
#' @keywords internal
painel_tipo_grafico <- function(tipo_grafico, data_class_id) {
  if (length(tipo_grafico) == 1L && !is.na(tipo_grafico))
    return(tipo_grafico)
  if (length(data_class_id) == 1L && !is.na(data_class_id) &&
      identical(as.integer(data_class_id), 4L))
    return("banda")
  "linha"
}

#' Rotulo amigavel do eixo temporal conforme a periodicidade do indicador
#' (anual -> "Ano", mensal -> "Mês"...) — prepara o painel para series
#' nao anuais sem trocar as legendas caso a caso
#' @keywords internal
painel_rotulo_tempo <- function(freq_name) {
  f <- tolower(trimws(as.character(freq_name)[1]))
  rotulos <- c(diaria = "Data", "diària" = "Data", semanal = "Semana",
               quinzenal = "Quinzena", mensal = "Mês", bimestral = "Bimestre",
               trimestral = "Trimestre", quadrimestral = "Quadrimestre",
               semestral = "Semestre", anual = "Ano", bienal = "Ano",
               irregular = "Data")
  if (is.na(f) || !f %in% names(rotulos)) return("Ano")
  unname(rotulos[[f]])
}

#' Geometrias municipais do DW (bloco local_id < 5572 mais os
#' municipios incorporados apos o bloco PNAD, local_id > 7087)
#' @keywords internal
painel_geo_mun <- function(con) {
  painel_pnad_bloco_fim_resolver(con)
  sf::st_read(con, query = paste(
    "SELECT l.local_id, l.local_name, g.geometry",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE", painel_municipio_filtro()), quiet = TRUE)
}

#' Localidades do DW rotuladas por nome + id (ha nomes repetidos entre
#' granularidades: municipio, UF, aglomeracao, regiao, "exceto")
#' @keywords internal
painel_locais <- function(con) {
  painel_pnad_bloco_fim_resolver(con)
  loc <- DBI::dbGetQuery(con,
    "SELECT local_id, local_name FROM local ORDER BY local_name, local_id")
  setNames(loc$local_id,
           paste0(loc$local_name, " (id ", loc$local_id, ")"))
}

#' Codigo IBGE das localidades com codigo externo, indexado pelo local_id —
#' traduz a coluna "Codigo" das planilhas da aba Baixar: municipios
#' (geoloc_id de 7 digitos) e niveis submunicipais (setor, bairro, area de
#' ponderacao; larguras acima de 10, cujos geoloc_id sao os codigos
#' divulgados pelo IBGE). Os demais niveis (UF, regioes, PNAD) nao tem
#' codigo externo e continuam mostrando o local_id.
#' @keywords internal
painel_codigo_mun <- function(con) {
  painel_pnad_bloco_fim_resolver(con)
  cod <- DBI::dbGetQuery(con, paste(
    "SELECT l.local_id, g.geoloc_id::text AS codigo",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE", painel_municipio_filtro(),
    "OR length(g.geoloc_id::text) > 10",
    "ORDER BY l.local_id"))
  setNames(cod$codigo, as.character(cod$local_id))
}

#' Valores de um indicador (todas as localidades e refdates)
#' @keywords internal
painel_valores <- function(con, mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0)))
  }
  DBI::dbGetQuery(con, sprintf(
    "SELECT local_id, refdate, value FROM data_values WHERE mdata_id = %d",
    mdata_id))
}

#' Serie de um indicador em UMA localidade — usa o prefixo da chave
#' primaria (mdata_id, local_id) em vez de puxar todas as localidades
#' @keywords internal
painel_valores_local <- function(con, mdata_id, local_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(mdata_id) || is.na(local_id)) {
    return(data.frame(refdate = as.Date(character(0)), value = numeric(0)))
  }
  DBI::dbGetQuery(con, sprintf(paste(
    "SELECT refdate, value FROM data_values",
    "WHERE mdata_id = %d AND local_id = %d ORDER BY refdate"),
    mdata_id, local_id))
}

#' Anos com observacoes de um indicador (para os limites do slider do mapa)
#' @keywords internal
painel_anos <- function(con, mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) return(data.frame(ano = integer(0)))
  DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT date_part('year', refdate)::int AS ano FROM data_values WHERE mdata_id = %d ORDER BY 1",
    mdata_id))
}

#' Valor do ultimo refdate de cada localidade dentro de um ano: replica no
#' SQL (DISTINCT ON + faixa make_date, indices amigaveis; NULL e NaN caem no
#' <> 'NaN'::float8) o que antes puxava o indicador inteiro e agregava em R
#' @keywords internal
painel_valores_ano <- function(con, mdata_id, ano) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  ano <- suppressWarnings(as.integer(ano))[1]
  if (is.na(mdata_id) || is.na(ano)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0)))
  }
  DBI::dbGetQuery(con, sprintf(paste(
    "SELECT DISTINCT ON (local_id) local_id, refdate, value",
    "FROM data_values",
    "WHERE mdata_id = %d AND refdate >= make_date(%d, 1, 1)",
    "AND refdate < make_date(%d, 1, 1)",
    "AND value <> 'NaN'::float8",
    "ORDER BY local_id, refdate DESC"),
    mdata_id, ano, ano + 1L))
}

#' Refdates distintos de um indicador (limites do slider por data do mapa)
#' @keywords internal
painel_refdates <- function(con, mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) {
    return(data.frame(refdate = as.Date(character(0))))
  }
  DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT refdate FROM data_values WHERE mdata_id = %d ORDER BY 1",
    mdata_id))
}

#' Valores das localidades num refdate exato (slider por data do mapa)
#' @keywords internal
painel_valores_refdate <- function(con, mdata_id, refdate) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  refdate <- as.Date(refdate)[1]
  if (is.na(mdata_id) || is.na(refdate)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0)))
  }
  DBI::dbGetQuery(con, sprintf(paste(
    "SELECT local_id, refdate, value FROM data_values",
    "WHERE mdata_id = %d AND refdate = date '%s'",
    "AND value <> 'NaN'::float8"),
    mdata_id, format(refdate, "%Y-%m-%d")))
}

#' Rotulo curto de cada refdate para o slider: so o ano quando ele e o
#' unico ponto daquele ano na serie (series anuais seguem \"2022\"), ou
#' d/m/AAAA quando o ano tem mais de um ponto (turnos de eleicao)
#' @keywords internal
painel_rotulo_data <- function(datas) {
  datas <- as.Date(datas)
  anos <- format(datas, "%Y")
  contagens <- table(anos)
  as.character(ifelse(anos %in% names(contagens)[contagens > 1],
                      format(datas, "%d/%m/%Y"), anos))
}

#' Rotulo de aba das planilhas do painel: mesmo criterio de
#' [painel_rotulo_data()] (ano sozinho quando ele e o unico ponto do ano
#' na serie), mas com data completa ISO AAAA-MM-DD nos anos de varios
#' pontos: "/" e proibido em nome de aba de planilha e o ISO ordena
#' lexicograficamente correto mesmo misturado com "2022"
#' @keywords internal
painel_rotulo_aba <- function(datas) {
  datas <- as.Date(datas)
  anos <- format(datas, "%Y")
  contagens <- table(anos)
  as.character(ifelse(anos %in% names(contagens)[contagens > 1],
                      format(datas, "%Y-%m-%d"), anos))
}

#' Serie completa do indicador ja reduzida a 1 observacao por localidade x
#' ano (ultimo refdate finito do ano): UMA query por indicador em vez de uma
#' por (indicador, ano), que o mapa animado e a aba Baixar pagariam a cada
#' ano do slider. Base do cache achatado [painel_valores_por_ano_cache()] e
#' da banda transversal [painel_plot_banda()]
#' @keywords internal
painel_valores_por_ano <- function(con, mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0), ano = integer(0)))
  }
  DBI::dbGetQuery(con, sprintf(paste(
    "SELECT DISTINCT ON (local_id, ano) local_id, refdate, value,",
    "date_part('year', refdate)::int AS ano",
    "FROM data_values",
    "WHERE mdata_id = %d AND value <> 'NaN'::float8",
    "ORDER BY local_id, ano, refdate DESC"),
    mdata_id))
}

#' Serie completa do indicador com TODAS as observacoes (uma linha por
#' localidade x refdate, sem reducao ao ultimo ponto do ano): base do
#' explorar e do recorte por data da aba Baixar, consistente com o slider
#' por data do mapa (eleicoes com 2 turnos aparecem nos dois refdates)
#' @keywords internal
painel_valores_por_data <- function(con, mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0), ano = integer(0)))
  }
  DBI::dbGetQuery(con, sprintf(paste(
    "SELECT local_id, refdate, value,",
    "date_part('year', refdate)::int AS ano",
    "FROM data_values",
    "WHERE mdata_id = %d AND value <> 'NaN'::float8",
    "ORDER BY local_id, refdate"),
    mdata_id))
}

#' Fatiador puro do cache achatado: devolve as linhas do ano com as colunas
#' do contrato historico (sem a coluna ano), vazio tipado quando nao ha match
#' @keywords internal
painel_filtrar_ano <- function(d, ano) {
  vazio <- data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0))
  ano <- suppressWarnings(as.integer(ano)[1])
  if (is.null(d) || !NROW(d) || is.na(ano) || !"ano" %in% names(d)) return(vazio)
  res <- d[d$ano == ano, c("local_id", "refdate", "value"), drop = FALSE]
  rownames(res) <- NULL
  res
}

#' Ranking vazio (localidade nao municipal, sem dado no ano ou sem par)
#' @keywords internal
painel_ranking_vazio <- function() {
  data.frame(rank_uf = NA_integer_, n_uf = NA_integer_,
             rank_br = NA_integer_, n_br = NA_integer_)
}

#' Posicao de uma localidade num indicador e data: quantos municipios do
#' pais e da propria UF tem valor MAIOR naquela data
#'
#' Os dois universos sao municipais (largura 7 do geoloc_id): o pais inteiro
#' e a UF de origem, pelo prefixo de 2 digitos do geoloc_id. A posicao conta
#' os valores estritamente maiores, entao empates dividem a mesma posicao; o
#' total (`n_uf`, `n_br`) e quantos municipios tem dado na data para o
#' indicador. Com `refdate` valido a comparacao e no dia exato (slider por
#' data do mapa); sem `refdate`, vale a regra de ano de [painel_valores_ano()]
#' (ultimo refdate de cada localidade dentro do ano, `DISTINCT ON` + faixa
#' `make_date`), e o valor da propria localidade e do mesmo ano.
#'
#' Contar de cima para baixo assume "maior e melhor", o sentido dos
#' indicadores compostos do catalogo do painel: o resumo nao guarda direcao
#' do indicador (a tabela mdata nao tem essa coluna).
#' @keywords internal
painel_ranking_local <- function(con, mdata_id, local_id, ano,
                                 refdate = NULL) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  local_id <- suppressWarnings(as.integer(local_id))[1]
  ano <- suppressWarnings(as.integer(ano))[1]
  refdate <- as.Date(refdate)[1]
  if (is.na(mdata_id) || is.na(local_id) || is.na(ano)) {
    return(painel_ranking_vazio())
  }
  corte <- if (!is.na(refdate)) {
    sprintf("AND v.refdate = date '%s'", format(refdate, "%Y-%m-%d"))
  } else {
    sprintf(paste("AND v.refdate >= make_date(%d, 1, 1)",
                  "AND v.refdate < make_date(%d, 1, 1)"),
            ano, ano + 1L)
  }
  q <- DBI::dbGetQuery(con, sprintf(paste(
    "WITH alvo AS (",
    "  SELECT left(g.geoloc_id::text, 2) AS uf, v.value",
    "  FROM local l",
    "  JOIN geoloc g USING (geoloc_id)",
    "  JOIN data_values v ON v.local_id = l.local_id",
    "  WHERE l.local_id = %d AND length(g.geoloc_id::text) = 7",
    "  AND v.mdata_id = %d",
    "  %s",
    "  AND v.value <> 'NaN'::float8",
    "  ORDER BY v.refdate DESC LIMIT 1",
    "), vals AS (",
    "  SELECT DISTINCT ON (v.local_id) left(g.geoloc_id::text, 2) AS uf, v.value",
    "  FROM data_values v",
    "  JOIN local l USING (local_id)",
    "  JOIN geoloc g USING (geoloc_id)",
    "  WHERE v.mdata_id = %d",
    "  %s",
    "  AND v.value <> 'NaN'::float8",
    "  AND length(g.geoloc_id::text) = 7",
    "  ORDER BY v.local_id, v.refdate DESC",
    ")",
    "SELECT",
    "  (count(*) FILTER (WHERE v.value > a.value) + 1)::int AS rank_uf,",
    "  count(*)::int AS n_uf,",
    "  (SELECT count(*) + 1 FROM vals, alvo WHERE vals.value > alvo.value)::int",
    "  AS rank_br,",
    "  (SELECT count(*) FROM vals, alvo)::int AS n_br",
    "FROM vals v, alvo a WHERE v.uf = a.uf"),
    local_id, mdata_id, corte,
    mdata_id, corte))
  if (!NROW(q)) return(painel_ranking_vazio())
  r <- vapply(q, function(x) suppressWarnings(as.numeric(x))[1], numeric(1))
  # alvo vazio (localidade nao municipal ou sem dado no ano) devolve a
  # agregacao degenerada 1 / 0 / 1 / 0: sem universo, sem posicao
  if (!is.finite(r[["n_br"]]) || r[["n_br"]] < 1) return(painel_ranking_vazio())
  data.frame(rank_uf = r[["rank_uf"]], n_uf = r[["n_uf"]],
             rank_br = r[["rank_br"]], n_br = r[["n_br"]])
}

#' Anotacao de ranking de um cartao do resumo: "5o melhor na UF e 590o BR"
#'
#' `NULL` quando nao ha posicao a mostrar (universo de um so municipio,
#' localidade sem dado no ano ou UF sem par). `n` e o tamanho do universo.
#' @keywords internal
painel_ranking_texto <- function(rank_uf, n_uf, rank_br, n_br) {
  vale <- function(rank, n) {
    isTRUE(is.finite(rank) && is.finite(n) && rank >= 1 && n > 1)
  }
  partes <- character(0)
  if (vale(rank_uf, n_uf)) {
    partes <- c(partes, sprintf("%s\u00ba melhor na UF", painel_num(rank_uf)))
  }
  if (vale(rank_br, n_br)) {
    partes <- c(partes, sprintf("%s\u00ba BR", painel_num(rank_br)))
  }
  if (!length(partes)) return(NULL)
  paste(partes, collapse = " e ")
}

# Rotulos dos niveis territoriais do DW, pela largura do geoloc_id (IBGE):
# 1 grande regiao, 2 UF, 4 regiao geografica intermediaria (2017),
# 5 microrregiao (1990), 6 regiao geografica imediata (2017),
# 7 municipio e 8 mesorregiao (1990; sem dados no DW). A chave "7p" separa
# as regioes de interesse em PNAD Contínua, que usam codigos de 7 digitos
# (mesma largura do codigo IBGE de municipio) e vivem na faixa alta dos
# local_id (6941..7086) — publicadas so pelos indicadores pnadc*/comp_pnadc*
# (verificado 2026-09-22: nenhum indicador municipal publica nelas, e nenhum
# pnadc publica em municipio).
# Niveis submunicipais (roadmap-niveis-submunicipais) usam CHAVE POR TIPO
# (o proprio `nivel_tipo` gravado em `local`): bairro, subdistrito, setor,
# area de ponderacao. A largura deixa de ser identificadora porque bairro
# e subdistrito dividem os 11 digitos — quem decide e o nivel_tipo. As
# chaves numericas de largura ("10"/"11"/"12"/"15"/"16") seguem listadas
# como legado para linhas gravadas antes do nivel_tipo. Manter sincrono
# com R/niveis_territoriais.R (o esqueleto do painel e autocontido de
# proposito).
painel_niveis_rotulo <- c(
  "1" = "Região",
  "2" = "Unidade da Federação",
  "4" = "Região geográfica intermediária",
  "5" = "Microrregião",
  "6" = "Região geográfica imediata",
  "7" = "Município",
  "7p" = "Região de interesse PNAD",
  "8" = "Mesorregião",
  "11" = "Bairro",
  "12" = "Bairro",
  "10" = "Área de ponderação",
  "15" = "Setor censitário",
  "16" = "Setor censitário",
  "bairro" = "Bairro",
  "subdistrito" = "Subdistrito (RA)",
  "setor" = "Setor censitário",
  "area_ponderacao" = "Área de ponderação")

# Largura representativa de cada nivel submunicipal (para os consumers que
# so olham p$nivel: rotulo com sigla de UF em 7, simplificacao de geometria
# abaixo de 3...). Chave = nivel_tipo; copia local de
# R/niveis_territoriais.R — o esqueleto do painel e autocontido.
painel_nivel_tipo_largura <- c(
  bairro = 11L, subdistrito = 11L, area_ponderacao = 10L, setor = 15L)

# Fronteira entre os municipios e as regioes de interesse em PNAD Contínua
# dentro da largura 7 do geoloc_id — mesma convencao adotada pelo
# populate_initialdb (malha 2024). Municipios: local_id 1..5571 (5571
# municipios da malha 2024, Boa Esperanca do Norte incluida); estratos
# PNAD a partir de 5572. O limite superior 7087 tem duas funcoes:
# (a) excluir da zona PNAD os municipios incorporados com append
# (local_id 7088+; ver incorporar_municipio_ibge()); no DW de
# producao com a numeracao antiga, 7087 era o proprio Brasil
# (estratos 6941..7086, Brasil = 7087) — o gate de largura 7 o
# mantinha fora da zona PNAD de qualquer forma. No numeracao nova o
# Brasil/imediatas/intermediarias caem depois dos estratos e seguem
# fora pelo mesmo gate ou pelo limite.
# Niveis submunicipais ganham blocos proprios a partir de 100000 (setores,
# bairros 1000000+, areas de ponderacao 2000000+) e ficam FORA deste
# filtro — copia local de niveis_submunicipal_inicio
# (R/niveis_territoriais.R): o esqueleto do painel e autocontido.
painel_municipio_limite_id <- 5572L
painel_pnad_bloco_fim <- 7087L
.painel_bloco_env <- new.env(parent = emptyenv())

#' Fim do bloco PNAD: local_id da linha "Brasil" (dinamico; cai no
#' fallback estatico sem a linha). Cache de sessao em environment
#' proprio (namespace e travado apos o load).
painel_pnad_bloco_fim_resolver <- function(con) {
  if (is.null(.painel_bloco_env$fim)) {
    v <- tryCatch(as.integer(DBI::dbGetQuery(con, paste(
      "SELECT local_id FROM local WHERE local_name = 'Brasil'",
      "ORDER BY local_id LIMIT 1"))$local_id[1]),
      error = function(e) NA_integer_)
    .painel_bloco_env$fim <- if (is.na(v)) painel_pnad_bloco_fim else v
  }
  .painel_bloco_env$fim
}
painel_submunicipal_inicio <- 100000L

#' Fragmento SQL que seleciona apenas municipios (alias `l` no chamador)
painel_municipio_filtro <- function(alias = "l") {
  bloco_fim <- if (!is.null(.painel_bloco_env$fim)) .painel_bloco_env$fim else
    painel_pnad_bloco_fim
  sprintf("(%s.local_id < %d OR (%s.local_id > %d AND %s.local_id < %d))",
          alias, painel_municipio_limite_id, alias, bloco_fim,
          alias, painel_submunicipal_inicio)
}

#' Decodifica a chave de nivel territorial do painel
#'
#' A chave e a largura do geoloc_id como texto ("1".."8") ou "7p" para as
#' regioes de interesse em PNAD Contínua, que dividem a largura 7 com os
#' municipios. Niveis submunicipais usam o proprio `nivel_tipo` como chave
#' ("bairro", "subdistrito", "setor", "area_ponderacao") — bairro e
#' subdistrito dividem a largura 11, entao a largura nao distingue niveis.
#' Devolve o nivel numerico (largura representativa nos submunicipais), o
#' tipo quando ha, se e o subnivel PNAD e o fragmento SQL que seleciona os
#' locais do nivel (pressupoe aliases `l` e `g` no chamador).
#' @keywords internal
painel_nivel_parse <- function(nivel_id) {
  chave <- suppressWarnings(trimws(as.character(nivel_id)[1]))
  if (is.na(chave)) chave <- ""
  chave <- tolower(chave)
  pnad <- nzchar(chave) && chave == "7p"
  tipo <- if (!pnad && grepl("^[a-z_]+$", tolower(chave))) tolower(chave) else
    NA_character_
  nivel <- if (pnad) {
    7L
  } else if (!is.na(tipo) && tipo %in% names(painel_nivel_tipo_largura)) {
    unname(painel_nivel_tipo_largura[tipo])
  } else {
    suppressWarnings(as.integer(chave))[1]
  }
  if (!is.na(nivel) && nivel < 1L) nivel <- NA_integer_
  bloco_fim <- if (!is.null(.painel_bloco_env$fim)) .painel_bloco_env$fim else
    painel_pnad_bloco_fim
  filtro <- if (is.na(nivel)) {
    "1 = 0"
  } else if (!is.na(tipo)) {
    sprintf("l.nivel_tipo = '%s'", tipo)
  } else if (pnad) {
    sprintf("length(g.geoloc_id::text) = 7 AND l.local_id >= %d AND l.local_id <= %d",
            painel_municipio_limite_id, bloco_fim)
  } else if (identical(nivel, 7L)) {
    bloco_fim7 <- if (!is.null(.painel_bloco_env$fim)) .painel_bloco_env$fim else
      painel_pnad_bloco_fim
    sprintf("length(g.geoloc_id::text) = 7 AND %s", painel_municipio_filtro())
  } else {
    sprintf("length(g.geoloc_id::text) = %d", nivel)
  }
  list(nivel = nivel, pnad = pnad,
       chave = if (is.na(nivel)) NA_character_ else chave,
       tipo = tipo,
       filtro = filtro)
}

# Siglas por codigo de UF (para desambiguar nomes de municipios repetidos)
painel_uf_sigla <- c(
  "11" = "RO", "12" = "AC", "13" = "AM", "14" = "RR", "15" = "PA", "16" = "AP",
  "17" = "TO", "21" = "MA", "22" = "PI", "23" = "CE", "24" = "RN", "25" = "PB",
  "26" = "PE", "27" = "AL", "28" = "SE", "29" = "BA", "31" = "MG", "32" = "ES",
  "33" = "RJ", "35" = "SP", "41" = "PR", "42" = "SC", "43" = "RS", "50" = "MS",
  "51" = "MT", "52" = "GO", "53" = "DF")

#' Niveis territoriais disponiveis no DW: apenas os que possuem dados,
#' com quantidade de localidades distintas. Niveis submunicipais sao
#' chaveados pelo `nivel_tipo` ("bairro", "subdistrito", "setor",
#' "area_ponderacao") — a largura nao distingue bairro de subdistrito;
#' linhas submunicipais gravadas antes do nivel_tipo caem na chave de
#' largura legada. A largura 7 aparece em duas linhas — municipios ("7")
#' e regioes de interesse em PNAD Contínua ("7p") — para nao somar
#' 5.570 + 146 numa unica entrada. O EXISTS varre
#' o catalogo de locais (milissegundos com o indice
#' data_values(local_id), ver [garantir_indice_valores()]) em vez de
#' agregar os ~10 milhoes de pontos do data_values
#' @keywords internal
painel_niveis <- function(con) {
  painel_pnad_bloco_fim_resolver(con)
  q <- DBI::dbGetQuery(con, paste(
    "SELECT CASE WHEN l.local_id >=", painel_submunicipal_inicio,
    "THEN coalesce(l.nivel_tipo, length(g.geoloc_id::text)::text)",
    sprintf("WHEN length(g.geoloc_id::text) = 7 AND l.local_id >= %d AND l.local_id <= %d THEN '7p'",
            painel_municipio_limite_id,
            painel_pnad_bloco_fim_resolver(con)),
    "ELSE length(g.geoloc_id::text)::text END AS nivel_id,",
    "count(*)::int AS n_locais",
    "FROM local l",
    "JOIN geoloc g USING (geoloc_id)",
    "WHERE EXISTS (SELECT 1 FROM data_values v WHERE v.local_id = l.local_id)",
    "GROUP BY 1 ORDER BY 1"))
  q$rotulo <- unname(painel_niveis_rotulo[q$nivel_id])
  # largura fora do registro nao some: rótulo generico mantem o nivel
  # visivel no painel ate o registro ser atualizado
  falta <- is.na(q$rotulo) & grepl("^[0-9]+$", q$nivel_id)
  q$rotulo[falta] <- paste0("Nível de ", q$nivel_id[falta], " dígitos")
  q[!is.na(q$rotulo), ]
}

#' Nivel territorial de abertura default da aba Regiao: a variavel de
#' ambiente `painel_nivel` (chave do nivel, ex.: `subdistrito` ou `2`)
#' decide quando o nivel existe no catalogo; sem a variavel ou com nivel
#' indisponivel, municipal quando disponivel, senao UF
#' @keywords internal
painel_nivel_default <- function(niveis, padrao = Sys.getenv("painel_nivel", "")) {
  alvo <- trimws(as.character(padrao)[1])
  if (!is.na(alvo) && nzchar(alvo) && !is.null(niveis) && NROW(niveis) &&
      alvo %in% as.character(niveis$nivel_id)) {
    return(alvo)
  }
  if (is.null(niveis) || !nrow(niveis)) return("2")
  alvo <- which(grepl("Munic", niveis$rotulo, fixed = TRUE))
  if (length(alvo)) as.character(niveis$nivel_id[alvo[1]]) else "2"
}

#' Indicador de abertura do painel, escolhido pelo orig_name
#'
#' A variavel de ambiente `beep_indicador` (ex.: `desprod1`) decide qual
#' indicador das abas Regiao, Mapa e Baixar nasce selecionado; vazia ou
#' desconhecida cai no primeiro do catalogo (`md`, de [painel_mdata()]).
#' Lida a cada chamada, ou seja, a sessao R precisa ser reiniciada para
#' enxergar uma mudanca (o server roda o `updateSelectizeInput` na abertura).
#' @keywords internal
painel_indicador_default <- function(md, padrao = Sys.getenv("beep_indicador", "")) {
  if (is.null(md) || !NROW(md) || !"mdata_id" %in% names(md)) return(NA_integer_)
  if ("visivel" %in% names(md))
    md <- md[is.na(md$visivel) | md$visivel, , drop = FALSE]
  alvo <- trimws(as.character(padrao)[1])
  if (length(alvo) && !is.na(alvo) && nzchar(alvo) && "orig_name" %in% names(md)) {
    i <- match(alvo, trimws(as.character(md$orig_name)))
    if (!is.na(i)) return(as.integer(md$mdata_id[i]))
  }
  as.integer(md$mdata_id[1])
}

#' Localidades de um nivel territorial (pela chave de [painel_nivel_parse()] )
#' que possuem dados, rotuladas por nome (municipios ganham sigla da UF;
#' regioes PNAD ja trazem o contexto no proprio nome). O EXISTS replace o
#' DISTINCT sobre data_values e fica milissegundos com o indice
#' data_values(local_id) (ver [garantir_indice_valores()])
#' @keywords internal
painel_locais_nivel <- function(con, nivel_id) {
  p <- painel_nivel_parse(nivel_id)
  if (is.na(p$nivel)) return(integer(0))
  q <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT l.local_id, l.local_name,",
    "substring(g.geoloc_id::text, 1, 2) AS uf",
    "FROM local l",
    "JOIN geoloc g USING (geoloc_id)",
    "WHERE %s",
    "AND EXISTS (SELECT 1 FROM data_values v WHERE v.local_id = l.local_id)",
    "ORDER BY l.local_name, l.local_id"),
    p$filtro))
  rotulo <- if (identical(p$nivel, 7L) && !p$pnad) {
    sigla <- unname(painel_uf_sigla[q$uf])
    ifelse(is.na(sigla), q$local_name, paste0(q$local_name, " (", sigla, ")"))
  } else if (p$pnad) {
    # estratos PNAD dividem nomes com municipios (ex.: "Brasilia" e
    # tambem a RM PNAD): rotulo explicito evita escolher o estrato
    # esperando o municipio
    paste0(q$local_name, " (PNAD)")
  } else {
    q$local_name
  }
  setNames(as.integer(q$local_id), rotulo)
}

#' Localidade de um nivel com maior cobertura (pontos) de um indicador —
#' selecao default do seletor de localidade
#' @keywords internal
painel_local_top <- function(con, mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  if (is.na(mdata_id) || is.na(p$nivel)) return(NULL)
  q <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT v.local_id FROM data_values v",
    "JOIN local l USING (local_id) JOIN geoloc g USING (geoloc_id)",
    "WHERE v.mdata_id = %d AND %s",
    "GROUP BY v.local_id ORDER BY count(*) DESC, v.local_id LIMIT 1"),
    mdata_id, p$filtro))
  if (nrow(q)) as.integer(q$local_id[1]) else NULL
}

#' sf vazio tipado (colunas code/label/geometry) para as leituras de
#' geometria do globo
#' @keywords internal
painel_geo_vazio <- function() {
  sf::st_sf(code = character(0), label = character(0),
            geometry = sf::st_sfc(crs = 4326))
}

#' Geometrias das Unidades da Federacao do DW (largura 2 do geoloc_id:
#' 26 UFs + DF), com code/label para o globo
#' @keywords internal
painel_geo_uf <- function(con) {
  geo <- sf::st_read(con, query = paste(
    "SELECT l.local_id, l.local_name, g.geometry",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE length(g.geoloc_id::text) = 2",
    "ORDER BY l.local_id"), quiet = TRUE)
  geo$code <- as.character(geo$local_id)
  geo$label <- geo$local_name
  geo[, c("code", "label", "geometry")]
}

#' Geometrias de um nivel territorial do DW para o globo, simplificadas
#' no SQL (0.01 grau ~ 1 km) para o geojson ficar leve; niveis acima do
#' limite de feicoes (municipio: 5.6 mil poligonos) voltam vazio e o
#' chamador cai nas UFs como base do desenho — as regioes PNAD (146
#' feicoes) sao desenhadas normalmente
#' @keywords internal
painel_geo_nivel <- function(con, nivel_id, max_feicoes = 700L) {
  p <- painel_nivel_parse(nivel_id)
  if (is.na(p$nivel)) return(painel_geo_vazio())
  n_geo <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT count(*)::int AS n FROM local l",
    "JOIN geoloc g USING (geoloc_id) WHERE %s"),
    p$filtro))$n
  if (!length(n_geo) || is.na(n_geo) || n_geo > max_feicoes) {
    return(painel_geo_vazio())
  }
  geometria <- if (p$nivel <= 2L) "g.geometry" else
    "ST_SimplifyPreserveTopology(g.geometry, 0.01) AS geometry"
  geo <- sf::st_read(con, query = sprintf(paste(
    "SELECT l.local_id, l.local_name,", geometria,
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE %s",
    "ORDER BY l.local_id"),
    p$filtro), quiet = TRUE)
  geo$code <- as.character(geo$local_id)
  geo$label <- geo$local_name
  geo[, c("code", "label", "geometry")]
}

#' Botao "usar minha localizacao" da aba Regiao esta ativo? A variavel de
#' ambiente `painel_geolocalizacao=1` habilita o pedido de posicao ao
#' navegador (Geolocation API, exige HTTPS ou localhost) para selecionar a
#' localidade mais proxima do nivel corrente; qualquer outro valor (ou
#' variavel ausente) mantem o painel sem o botao
#' @keywords internal
painel_geolocalizacao_ativa <- function() {
  identical(Sys.getenv("painel_geolocalizacao"), "1")
}

#' Localidade mais proxima de um ponto (lat/lon WGS84) entre as feicoes de
#' um nivel: a que contem o ponto quando ha, senao a de representacao
#' interna mais proxima. Opera sem o s2 (GEOS plano, suficiente em escala
#' de cidade) porque malhas do Censo chegam com aneis invalidos (vertice
#' duplicado) que derrubam a construcao da geografia s2 antes de qualquer
#' predicado; NA quando nao ha feicoes ou coordenadas
#' @keywords internal
painel_geo_mais_proxima <- function(geo, lat, lon) {
  if (is.null(geo) || !nrow(geo)) return(NA_character_)
  lat <- suppressWarnings(as.numeric(lat)[1])
  lon <- suppressWarnings(as.numeric(lon)[1])
  if (is.na(lat) || is.na(lon)) return(NA_character_)
  s2_antigo <- sf::sf_use_s2()
  on.exit(sf::sf_use_s2(s2_antigo), add = TRUE)
  sf::sf_use_s2(FALSE)
  ponto <- sf::st_sfc(sf::st_point(c(lon, lat)), crs = 4326)
  dentro <- unlist(sf::st_intersects(ponto, sf::st_geometry(geo),
                                      sparse = TRUE))
  if (length(dentro)) return(as.character(geo$code[dentro[1]]))
  centros <- suppressWarnings(
    sf::st_point_on_surface(sf::st_geometry(geo)))
  d <- as.numeric(sf::st_distance(centros, ponto))
  if (!length(d) || all(is.na(d))) return(NA_character_)
  as.character(geo$code[which.min(d)])
}

#' Geometria de uma localidade (destaque do globo quando a base e a das
#' UFs e a selecao nao esta entre as feicoes)
#' @keywords internal
painel_geo_local <- function(con, local_id) {
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(local_id)) return(painel_geo_vazio())
  geo <- sf::st_read(con, query = sprintf(paste(
    "SELECT l.local_id, l.local_name, g.geometry",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE l.local_id = %d"),
    local_id), quiet = TRUE)
  geo$code <- as.character(geo$local_id)
  geo$label <- geo$local_name
  geo[, c("code", "label", "geometry")]
}

#' Geometria da UF que contem uma localidade (contexto do globo: o
#' estado aparece inteiro com a localidade em destaque)
#' @keywords internal
painel_geo_pai_uf <- function(con, local_id) {
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(local_id)) return(painel_geo_vazio())
  geo <- sf::st_read(con, query = sprintf(paste(
    "SELECT luf.local_id, luf.local_name, guf.geometry",
    "FROM local lf",
    "JOIN geoloc gf ON gf.geoloc_id = lf.geoloc_id",
    "JOIN geoloc guf ON length(guf.geoloc_id::text) = 2",
    "AND left(guf.geoloc_id::text, 2) = left(gf.geoloc_id::text, 2)",
    "JOIN local luf ON luf.geoloc_id = guf.geoloc_id",
    "WHERE lf.local_id = %d"),
    local_id), quiet = TRUE)
  geo$code <- as.character(geo$local_id)
  geo$label <- geo$local_name
  geo[, c("code", "label", "geometry")]
}

#' Malha municipal de uma UF (prefixo de 2 digitos do geoloc_id),
#' simplificada no SQL (0.01 grau ~ 1 km) — so as bordas dos vizinhos
#' desenhadas no globo ao redor do municipio em destaque
#' @keywords internal
painel_geo_mun_uf <- function(con, uf) {
  painel_pnad_bloco_fim_resolver(con)
  uf <- as.character(uf)[1]
  if (is.na(uf) || !grepl("^[0-9]{2}$", uf)) return(painel_geo_vazio())
  geo <- sf::st_read(con, query = sprintf(paste(
    "SELECT l.local_id, l.local_name,",
    "ST_SimplifyPreserveTopology(g.geometry, 0.01) AS geometry",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    sprintf("WHERE %s AND left(g.geoloc_id::text, 2) = '%%s'",
            painel_municipio_filtro()),
    "ORDER BY l.local_id"),
    uf), quiet = TRUE)
  geo$code <- as.character(geo$local_id)
  geo$label <- geo$local_name
  geo[, c("code", "label", "geometry")]
}

#' Feicoes submunicipais do mesmo nivel dentro de um municipio (prefixo de
#' 7 digitos do geoloc_id — setor, bairro, subdistrito e area de ponderacao
#' codificam o municipio nos primeiros digitos), simplificadas no SQL —
#' malha do globo quando o destaque e submunicipal: as feicoes do nivel
#' tesselam o municipio em foco. O nivel e selecionado pelo `nivel_tipo`
#' (largura nao distingue bairro de subdistrito); sem tipo (legado), pela
#' largura. Acima do teto de feicoes volta vazio e o globo fica apenas
#' com o destaque sobre a UF (degradacao). Malhas grandes (acima de 2 mil
#' feicoes, como os setores censitarios de uma capital inteira) ganham
#' simplificacao mais forte no SQL para caberem no mapa, que usa teto
#' proprio em [painel_geo_irmaos_nivel_cache()].
#' @keywords internal
painel_geo_irmaos_mun <- function(con, mun, tipo = NULL, larg = NULL,
                                  max_feicoes = 2000L) {
  mun <- trimws(as.character(mun)[1])
  if (is.na(mun) || !grepl("^[0-9]{7}$", mun)) return(painel_geo_vazio())
  escopo <- sprintf("left(g.geoloc_id::text, 7) = '%s'", mun)
  tipo <- if (length(tipo) == 1 && !is.na(tipo) && nzchar(tipo)) tipo else NULL
  escopo <- if (!is.null(tipo))
    paste(escopo, sprintf("AND l.nivel_tipo = '%s'", tipo))
  else if (!is.null(larg))
    paste(escopo, sprintf("AND length(g.geoloc_id::text) = %d",
                          as.integer(larg)))
  else paste(escopo, "AND length(g.geoloc_id::text) > 10")
  n_geo <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT count(*)::int AS n FROM local l",
    "JOIN geoloc g USING (geoloc_id) WHERE %s"), escopo))$n
  if (!length(n_geo) || is.na(n_geo) || n_geo < 1L || n_geo > max_feicoes) {
    return(painel_geo_vazio())
  }
  # tolerancia adaptativa: malhas grandes (capital inteira de setores)
  # simplificam mais forte para o geojson caber no navegador
  tol <- if (n_geo > 2000L) 0.001 else 0.0005
  geo <- sf::st_read(con, query = sprintf(paste(
    "SELECT l.local_id, l.local_name,",
    "ST_SimplifyPreserveTopology(g.geometry, %s) AS geometry",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE %s",
    "ORDER BY l.local_id"),
    tol, escopo), quiet = TRUE)
  geo$code <- as.character(geo$local_id)
  geo$label <- geo$local_name
  geo[, c("code", "label", "geometry")]
}

#' Contorno simplificado do municipio dono de um codigo submunicipal
#' (geoloc de 7 digitos): degradacao do mapa quando a malha do nivel
#' excede o limite de feicoes dentro do municipio
#' @keywords internal
painel_geo_municipio_codigo <- function(con, codigo) {
  codigo <- trimws(as.character(codigo)[1])
  if (is.na(codigo) || !grepl("^[0-9]{7}$", codigo)) return(painel_geo_vazio())
  geo <- sf::st_read(con, query = sprintf(paste(
    "SELECT l.local_id, l.local_name,",
    "ST_SimplifyPreserveTopology(g.geometry, 0.005) AS geometry",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE g.geoloc_id::text = '%s'",
    "AND length(g.geoloc_id::text) = 7"),
    codigo), quiet = TRUE)
  geo$code <- as.character(geo$local_id)
  geo$label <- geo$local_name
  geo[, c("code", "label", "geometry")]
}

#' UFs que contem localidades de um nivel com dados de um indicador —
#' pintura do globo quando a base e a das UFs (nivel municipal)
#' @keywords internal
painel_ufs_com_dados <- function(con, mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  if (is.na(mdata_id) || is.na(p$nivel)) return(character(0))
  q <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT DISTINCT luf.local_id",
    "FROM data_values v",
    "JOIN local l ON l.local_id = v.local_id",
    "JOIN geoloc g ON g.geoloc_id = l.geoloc_id",
    "JOIN geoloc guf ON length(guf.geoloc_id::text) = 2",
    "AND left(guf.geoloc_id::text, 2) = left(g.geoloc_id::text, 2)",
    "JOIN local luf ON luf.geoloc_id = guf.geoloc_id",
    "WHERE v.mdata_id = %d AND %s"),
    mdata_id, p$filtro))
  as.character(q$local_id)
}

#' Localidade de um nivel com maior cobertura de um indicador DENTRO de
#' uma UF — destino do clique na UF quando o globo usa base estadual
#' @keywords internal
painel_local_top_uf <- function(con, mdata_id, nivel_id, uf_local_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  uf_local_id <- suppressWarnings(as.integer(uf_local_id))[1]
  if (is.na(mdata_id) || is.na(p$nivel) || is.na(uf_local_id)) return(NULL)
  q <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT v.local_id FROM data_values v",
    "JOIN local l ON l.local_id = v.local_id",
    "JOIN geoloc g ON g.geoloc_id = l.geoloc_id",
    "JOIN geoloc guf ON length(guf.geoloc_id::text) = 2",
    "AND left(guf.geoloc_id::text, 2) = left(g.geoloc_id::text, 2)",
    "JOIN local luf ON luf.geoloc_id = guf.geoloc_id",
    "WHERE v.mdata_id = %d AND %s",
    "AND luf.local_id = %d",
    "GROUP BY v.local_id ORDER BY count(*) DESC, v.local_id LIMIT 1"),
    mdata_id, p$filtro, uf_local_id))
  if (nrow(q)) as.integer(q$local_id[1]) else NULL
}

#' Localidades de um nivel territorial (largura do geoloc_id) com dados
#' para um indicador — disponibilidade para o globo de UFs
#' @keywords internal
painel_locais_com_dados <- function(con, mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  if (is.na(mdata_id) || is.na(p$nivel)) return(character(0))
  q <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT DISTINCT v.local_id",
    "FROM data_values v",
    "JOIN local l USING (local_id) JOIN geoloc g USING (geoloc_id)",
    "WHERE v.mdata_id = %d AND %s"),
    mdata_id, p$filtro))
  as.character(q$local_id)
}

#' Nivel territorial onde um indicador vive: a chave de nivel (mesma
#' convencao de [painel_niveis()]) com mais localidades com dados dele —
#' municipais dao "7", submunicipais dao o proprio nivel_tipo. Indicador
#' sem dados devolve NA
#' @keywords internal
painel_ind_nivel <- function(con, mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) return(NA_character_)
  painel_pnad_bloco_fim_resolver(con)
  q <- DBI::dbGetQuery(con, sprintf(paste(
    "SELECT CASE WHEN l.local_id >=", painel_submunicipal_inicio,
    "THEN coalesce(l.nivel_tipo, length(g.geoloc_id::text)::text)",
    sprintf("WHEN length(g.geoloc_id::text) = 7 AND l.local_id >= %d AND l.local_id <= %d THEN '7p'",
            painel_municipio_limite_id, painel_pnad_bloco_fim_resolver(con)),
    "ELSE length(g.geoloc_id::text)::text END AS nivel_id,",
    "count(DISTINCT v.local_id)::int AS n_locais",
    "FROM data_values v",
    "JOIN local l USING (local_id)",
    "JOIN geoloc g USING (geoloc_id)",
    "WHERE v.mdata_id = %d",
    "GROUP BY 1",
    "ORDER BY n_locais DESC, nivel_id"),
    mdata_id))
  if (nrow(q)) as.character(q$nivel_id[1]) else NA_character_
}

#' Municipios (geoloc de 7 digitos) que contem feicoes de um nivel
#' submunicipal com dados de um indicador, com a contagem de feicoes —
#' decide quais malhas locais o mapa carrega quando a do nivel inteiro e
#' pesada demais (acima do limite de feicoes)
#' @keywords internal
painel_muns_nivel_dados <- function(con, mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  vazio <- data.frame(municipio = character(0), n_locais = integer(0))
  if (is.na(mdata_id) || is.na(p$nivel)) return(vazio)
  if (is.na(p$tipo) && p$nivel <= 10L) return(vazio)
  DBI::dbGetQuery(con, sprintf(paste(
    "SELECT left(g.geoloc_id::text, 7) AS municipio,",
    "count(DISTINCT v.local_id)::int AS n_locais",
    "FROM data_values v",
    "JOIN local l USING (local_id)",
    "JOIN geoloc g USING (geoloc_id)",
    "WHERE v.mdata_id = %d AND %s",
    "AND length(g.geoloc_id::text) > 10",
    "GROUP BY 1 ORDER BY n_locais DESC, municipio"),
    mdata_id, p$filtro))
}

# Familia de indicadores de cada eixo do catalogo: o prefixo de orig_name
# (convencao do pacote: orig_name == nome do script de coleta) identifica a
# familia do indicador, e o "comp_" na frente identifica o composto do eixo.
painel_familias_eixo <- c(
  educ = "Eixo 1", citec = "Eixo 2", desprod = "Eixo 3", infra = "Eixo 4",
  dessoc = "Eixo 5", sust = "Eixo 6", governativas = "Eixo 7")

#' Grupo de um indicador do catalogo (Eixo N, Objetivo N ou Estratos PNAD)
#' pela convencao de orig_name; NA para os indicadores de apoio
#'
#' O catalogo do DW e montado por convencao de nome (educ1..4 + comp_educ no
#' Eixo 1, objetivo2_1..3 + comp_objetivo2 no Objetivo 2, pnadc1..7 +
#' comp_pnadc8..14 nos Estratos PNAD): a tabela mdata_group existe, mas esta
#' populada so parcialmente (verificado 2026-09-22: 7 dos 35 indicadores dos
#' eixos), entao nao serve de fonte da hierarquia. Variacoes de trabalho
#' (`_via_beep`, `_v0`) ficam fora do catalogo, que e o que o painel publica.
#' @keywords internal
painel_grupo_indicador <- function(orig_name) {
  x <- trimws(as.character(orig_name))
  x <- sub("^comp_", "", x)
  x[grepl("_v[0-9]+$", x)] <- NA_character_
  grupo <- rep(NA_character_, length(x))
  for (familia in names(painel_familias_eixo)) {
    alvo <- grepl(sprintf("^%s[0-9]*$", familia), x)
    grupo[alvo] <- unname(painel_familias_eixo[[familia]])
  }
  alvo <- grepl("^objetivo[0-9]+(_[0-9]+)?$", x)
  grupo[alvo] <- paste0("Objetivo ", sub("^objetivo([0-9]+).*$", "\\1", x[alvo]))
  grupo[grepl("^pnadc[0-9]+$", x)] <- "Estratos PNAD"
  grupo
}

#' Raiz de um grupo do catalogo (Eixos, Objetivos ou o proprio grupo)
#' @keywords internal
painel_grupo_raiz <- function(grupo) {
  ifelse(grepl("^Eixo", grupo), "Eixos",
         ifelse(grepl("^Objetivo", grupo), "Objetivos", grupo))
}

#' Ordem canonica dos grupos no seletor de indicadores do painel
#' @keywords internal
painel_grupos_selecao <- c(paste("Eixo", 1:7), paste("Objetivo", 1:4),
                           "Estratos PNAD")

#' Opcoes do seletor de indicadores do painel, agrupadas por eixo/objetivo
#'
#' Monta a lista aninhada que o `updateSelectizeInput(server = TRUE)`
#' transforma em optgroups, os titulos de grupo nao clicaveis do selectize:
#' "Eixo 1".."Eixo 7", "Objetivo 1".."Objetivo 4", "Estratos PNAD" e, por
#' fim, "Demais indicadores" (series de apoio e variantes de trabalho).
#' Dentro de cada eixo/objetivo o composto abre o grupo e os componentes
#' vem numerados ("Indicador N - Nome (orig_name)"); os Estratos PNAD
#' seguem o numero do estrato (pnadc1..7 e comp_pnadc8..14); os demais
#' mantem a ordem alfabetica do `orig_name` de [painel_mdata()].
#' Indicadores marcados como invisiveis (tabela auxiliar `mdata_visivel`,
#' coluna `visivel` do catalogo) ficam de fora das opcoes.
#' @keywords internal
painel_opcoes_indicador <- function(md) {
  if (is.null(md) || !NROW(md)) return(list())
  if ("visivel" %in% names(md))
    md <- md[is.na(md$visivel) | md$visivel, , drop = FALSE]
  x <- trimws(as.character(md$orig_name))
  grupo <- painel_grupo_indicador(x)
  grupo[is.na(grupo)] <- "Demais indicadores"
  numero <- rep(NA_integer_, length(x))
  numerado <- grepl("[0-9]+$", x)
  numero[numerado] <- as.integer(sub("^.*?([0-9]+)$", "\\1", x[numerado]))
  composto <- grepl("^comp_", x)
  nome <- if ("data_name" %in% names(md)) trimws(as.character(md$data_name)) else
    rep(NA_character_, length(x))
  rotulo <- paste0(ifelse(is.na(nome), x, nome), " (", x, ")")
  rotulo <- ifelse(is.na(numero) | composto, rotulo,
                   paste0("Indicador ", numero, " - ", rotulo))
  ordem <- intersect(painel_grupos_selecao, unique(grupo))
  ordem <- c(ordem,
             setdiff(unique(grupo), c(painel_grupos_selecao,
                                      "Demais indicadores")))
  if ("Demais indicadores" %in% grupo) ordem <- c(ordem, "Demais indicadores")
  respostas <- lapply(ordem, function(g) {
    i <- which(grupo == g)
    if (g == "Demais indicadores") {
      i <- i[order(x[i])]
    } else if (g == "Estratos PNAD") {
      i <- i[order(numero[i], x[i], na.last = TRUE)]
    } else {
      i <- i[order(as.integer(!composto[i]), numero[i], x[i],
                   na.last = TRUE)]
    }
    opcoes <- setNames(as.character(md$mdata_id[i]), rotulo[i])
    if (length(opcoes) == 1L) opcoes <- as.list(opcoes)
    opcoes
  })
  names(respostas) <- ordem
  respostas
}

#' Hierarquia do catalogo de indicadores: raiz (Eixos, Objetivos, Estratos
#' PNAD) > grupo (Eixo 1..7, Objetivo 1..4) > indicador, com a classe do
#' dado (data_class_id) — estrutura do resumo e do accordeon da aba Regiao
#'
#' Os ids e nomes de grupo vem da tabela datagroup do DW; o vinculo de cada
#' indicador ao grupo vem da convencao de orig_name (ver
#' [painel_grupo_indicador()]). Indicador sem grupo conhecido fica de fora.
#' @keywords internal
painel_hierarquia <- function(con) {
  md <- DBI::dbGetQuery(con, paste(
    "SELECT m.mdata_id, m.orig_name, m.data_name, e.data_class_id,",
    "e.dataunit_num AS unidade",
    "FROM mdata m LEFT JOIN mdata_exts e USING (mdata_id)",
    "ORDER BY m.mdata_id"))
  md$unidade <- painel_unidade_normaliza(md$unidade)
  md$datagroup_name <- painel_grupo_indicador(md$orig_name)
  md <- md[!is.na(md$datagroup_name), ]
  grupos <- DBI::dbGetQuery(con,
    "SELECT datagroup_id, datagroup_name FROM datagroup")
  md$raiz_nome <- painel_grupo_raiz(md$datagroup_name)
  md$datagroup_id <- grupos$datagroup_id[match(md$datagroup_name,
                                               grupos$datagroup_name)]
  md$raiz_id <- grupos$datagroup_id[match(md$raiz_nome, grupos$datagroup_name)]
  md <- md[order(md$raiz_nome, md$datagroup_id, md$mdata_id),
           c("raiz_id", "raiz_nome", "datagroup_id", "datagroup_name",
             "mdata_id", "data_class_id", "orig_name", "data_name",
             "unidade")]
  rownames(md) <- NULL
  md
}

#' Indicadores compostos do catalogo (data_class_id = 4 no mdata_exts)
#' @keywords internal
painel_compostos <- function(con) {
  DBI::dbGetQuery(con, paste(
    "SELECT m.mdata_id, m.orig_name, m.data_name",
    "FROM mdata m",
    "JOIN mdata_exts e ON e.mdata_id = m.mdata_id AND e.data_class_id = 4",
    "ORDER BY m.orig_name"))
}

#' Nome do grupo curado do resumo no catalogo (tabela datagroup): os
#' indicadores ligados a ele em mdata_group sao os cartoes do "Resumo da
#' regiao", escolhidos no app do beep (aba Variaveis e Indicadores). Deve
#' bater com [beep_grupo_resumo_nome] do pacote (guardado por teste)
#' @keywords internal
painel_grupo_resumo_nome <- "Resumo"

#' Separador do rotulo dos cartoes do resumo (travessao, em UTF-8)
#' @keywords internal
painel_resumo_sep <- " \u2014 "

#' Fonte de cada indicador do catalogo — base do agrupamento "por fonte"
#' do resumo quando o DW nao tem eixos/objetivos nem grupo Resumo
#' @keywords internal
painel_fontes <- function(con) {
  DBI::dbGetQuery(con, paste(
    "SELECT m.mdata_id, m.orig_name, m.data_name, e.data_class_id,",
    "nullif(trim(coalesce(e.dataunit_num, '')), '') AS unidade,",
    "coalesce(d.datasource_name, 'Sem fonte cadastrada') AS fonte",
    "FROM mdata m",
    "LEFT JOIN mdata_exts e ON e.mdata_id = m.mdata_id",
    "LEFT JOIN datasource d ON d.datasource_id = e.datasource_id",
    "ORDER BY m.mdata_id"))
}

#' Membros do grupo Resumo do catalogo (datagroup "Resumo" via mdata_group),
#' com a fonte de cada um — vazio quando o grupo nao existe ou nao tem
#' vinculos; o painel le fail-open e cai nos compostos ou nas fontes
#' @keywords internal
painel_grupo_resumo <- function(con) {
  DBI::dbGetQuery(con, paste(
    "SELECT m.mdata_id, m.orig_name, m.data_name, e.data_class_id,",
    "nullif(trim(coalesce(e.dataunit_num, '')), '') AS unidade,",
    "coalesce(d2.datasource_name, 'Sem fonte cadastrada') AS fonte",
    "FROM mdata m",
    "JOIN mdata_group g ON g.mdata_id = m.mdata_id",
    "JOIN datagroup d ON d.datagroup_id = g.datagroup_id",
    "LEFT JOIN mdata_exts e ON e.mdata_id = m.mdata_id",
    "LEFT JOIN datasource d2 ON d2.datasource_id = e.datasource_id",
    "WHERE d.datagroup_name = 'Resumo'",
    "ORDER BY m.mdata_id"))
}

#' Nucleo do resumo: valor mais recente (e o anterior) de cada indicador
#' pedido na localidade, ate a data de corte
#'
#' @param indicadores data.frame com `mdata_id`, `rotulo`, `grupo` e `raiz`
#'   (uma linha por cartao do resumo, na ordem desejada); a coluna opcional
#'   `unidade` (ex.: "%") acompanha cada linha — frames sem ela (caches
#'   antigos em disco, fixtures) seguem com unidade NA
#' @param valores tabela de [painel_valores_local_todos()]
#' @param refdate data de corte: sem ela, a observacao mais recente; com ela,
#'   a ultima observacao em ou antes da data (slider por data do resumo)
#' @keywords internal
painel_resumo_linhas <- function(indicadores, valores, refdate = NULL) {
  vazio <- data.frame(grupo = character(0), raiz = character(0),
                      mdata_id = integer(0), rotulo = character(0),
                      valor = numeric(0), refdate = as.Date(character(0)),
                      valor_ant = numeric(0),
                      refdate_ant = as.Date(character(0)),
                      unidade = character(0))
  if (!NROW(indicadores) || !NROW(valores)) return(vazio)
  unid <- if (is.data.frame(indicadores) &&
              "unidade" %in% names(indicadores))
    indicadores$unidade else rep(NA_character_, nrow(indicadores))
  refdate <- as.Date(refdate)[1]
  linhas <- lapply(seq_len(nrow(indicadores)), function(i) {
    v <- valores[valores$mdata_id == indicadores$mdata_id[i] &
                   is.finite(valores$value), ]
    if (!nrow(v)) return(NULL)
    if (!is.na(refdate))
      v <- v[v$refdate <= refdate, , drop = FALSE]
    if (!nrow(v)) return(NULL)
    v <- v[order(v$refdate), , drop = FALSE]
    ultimo <- nrow(v)
    anterior <- ultimo - 1L
    data.frame(grupo = indicadores$grupo[i], raiz = indicadores$raiz[i],
               mdata_id = indicadores$mdata_id[i],
               rotulo = indicadores$rotulo[i],
               valor = v$value[ultimo], refdate = v$refdate[ultimo],
               valor_ant = if (anterior) v$value[anterior] else NA_real_,
               refdate_ant = if (anterior) v$refdate[anterior]
                            else as.Date(NA),
               unidade = unid[i])
  })
  linhas <- linhas[!vapply(linhas, is.null, logical(1))]
  if (!length(linhas)) return(vazio)
  resumo <- do.call(rbind, linhas)
  rownames(resumo) <- NULL
  resumo
}

#' Rotulo de exibicao de um indicador do catalogo (data_name ou orig_name)
#' @keywords internal
painel_resumo_nome <- function(orig_name, data_name) {
  nome <- trimws(as.character(data_name))
  sem_nome <- is.na(nome) | !nzchar(nome)
  nome[sem_nome] <- trimws(as.character(orig_name))[sem_nome]
  nome
}

#' Resumo por grupo do catalogo: um cartao por indicador composto com o
#' valor mais recente na localidade ate a data de corte (rotulo, valor e
#' data) — conteudo do "Resumo da regiao" na aba Regiao
#'
#' @param hierarquia tabela de [painel_hierarquia()]
#' @param compostos tabela de [painel_compostos()]
#' @param valores tabela de [painel_valores_local_todos()]
#' @param refdate data de corte: sem ela, a observacao mais recente; com ela,
#'   a ultima observacao em ou antes da data (slider por data do resumo)
#' @keywords internal
painel_resumo_grupos <- function(hierarquia, compostos, valores,
                               refdate = NULL) {
  h <- NULL
  if (NROW(hierarquia) && NROW(compostos))
    h <- hierarquia[hierarquia$mdata_id %in% compostos$mdata_id, , drop = FALSE]
  if (!NROW(h)) return(painel_resumo_linhas(NULL, valores, refdate))
  ind <- data.frame(
    mdata_id = h$mdata_id,
    rotulo = paste0(painel_resumo_nome(h$orig_name, h$data_name),
                    painel_resumo_sep, h$datagroup_name),
    grupo = h$datagroup_name, raiz = h$raiz_nome,
    unidade = if ("unidade" %in% names(h)) h$unidade
              else rep(NA_character_, nrow(h)))
  painel_resumo_linhas(ind, valores, refdate)
}

#' Resumo por fonte (fallback geral): um cartao por indicador do catalogo
#' com valor na localidade, rotulado com a fonte e ordenado por fonte —
#' alimenta o "Resumo da regiao" quando nao ha grupo Resumo curado nem
#' compostos por eixo/objetivo
#' @keywords internal
painel_resumo_fontes <- function(fontes, valores, refdate = NULL) {
  if (!NROW(fontes)) return(painel_resumo_linhas(NULL, valores, refdate))
  fonte <- as.character(fontes$fonte)
  if (!length(fonte) || all(is.na(fonte)))
    fonte <- rep("Sem fonte cadastrada", NROW(fontes))
  fonte[is.na(fonte)] <- "Sem fonte cadastrada"
  ordem <- order(fonte, fontes$mdata_id)
  ind <- data.frame(
    mdata_id = fontes$mdata_id[ordem],
    rotulo = paste0(painel_resumo_nome(fontes$orig_name, fontes$data_name)[ordem],
                    painel_resumo_sep, fonte[ordem]),
    grupo = fonte[ordem],
    raiz = rep("Por fonte", length(ordem)),
    unidade = if ("unidade" %in% names(fontes)) fontes$unidade[ordem]
              else rep(NA_character_, length(ordem)))
  painel_resumo_linhas(ind, valores, refdate)
}

#' Resumo com os membros do grupo Resumo (curados no app do beep): um
#' cartao por membro, rotulado com a fonte quando ela existe
#' @keywords internal
painel_resumo_membros <- function(membros, valores, refdate = NULL) {
  if (!NROW(membros)) return(painel_resumo_linhas(NULL, valores, refdate))
  fonte <- as.character(membros$fonte)
  fonte[is.na(fonte)] <- "Sem fonte cadastrada"
  rotulo <- painel_resumo_nome(membros$orig_name, membros$data_name)
  tem_fonte <- !is.na(fonte) & fonte != "Sem fonte cadastrada"
  rotulo[tem_fonte] <- paste0(rotulo[tem_fonte], painel_resumo_sep,
                              fonte[tem_fonte])
  ind <- data.frame(
    mdata_id = membros$mdata_id, rotulo = rotulo,
    grupo = rep(painel_grupo_resumo_nome, nrow(membros)),
    raiz = rep(painel_grupo_resumo_nome, nrow(membros)),
    unidade = if ("unidade" %in% names(membros)) membros$unidade
              else rep(NA_character_, nrow(membros)))
  painel_resumo_linhas(ind, valores, refdate)
}

#' Valores de TODOS os indicadores em uma localidade — alimenta o resumo
#' e os mini-graficos da aba Regiao em uma unica leitura
#' @keywords internal
painel_valores_local_todos <- function(con, local_id) {
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(local_id)) {
    return(data.frame(mdata_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0)))
  }
  DBI::dbGetQuery(con, sprintf(paste(
    "SELECT mdata_id, refdate, value FROM data_values",
    "WHERE local_id = %d ORDER BY mdata_id, refdate"),
    local_id))
}

#' Reorienta os aneis de um GeoJSON para o cliente do globo (d3-geo)
#'
#' O d3-geo decide o interior de um poligono esferico pela orientacao dos
#' aneis, na convencao oposta ao RFC 7946: exterior no sentido horario
#' (area com sinal negativa em graus) e furos no anti-horario. As malhas
#' do IBGE (UFs, municipios) ja vem assim, mas as geometrias derivadas do
#' Censo 2022 (bairros, subdistritos, setores, areas de ponderacao,
#' gravadas pelos incorporar_*) chegam invertidas; sem normalizacao o
#' globo desenha o complemento de cada feicao (o disco inteiro pintado) e
#' a tela fica em branco com o azulado translucido da selecao por cima.
#' O ajuste e local ao GeoJSON enviado ao navegador (globo: nivel,
#' destaque, contexto e malha); as geometrias do banco nao mudam e o
#' driver GeoJSON do GDAL nao tem opcao equivalente (RFC7946=YES nao e
#' suportado na escrita).
#' @keywords internal
painel_geojson_orientar <- function(texto) {
  area_anel <- function(anel) {
    m <- matrix(unlist(anel), ncol = 2, byrow = TRUE)
    n <- nrow(m)
    if (n < 4) return(0)
    sum(m[seq_len(n - 1), 1] * m[2:n, 2] -
          m[2:n, 1] * m[seq_len(n - 1), 2]) / 2
  }
  orientar_anel <- function(anel, exterior) {
    area <- area_anel(anel)
    if (is.na(area) || area == 0) return(anel)
    # exterior quer sentido horario (area negativa); furo, anti-horario
    if (identical(area < 0, exterior)) anel else rev(anel)
  }
  orientar_poligono <- function(pol) {
    lapply(seq_along(pol), function(i) orientar_anel(pol[[i]], i == 1))
  }
  gj <- jsonlite::fromJSON(texto, simplifyVector = FALSE)
  if (!is.list(gj) || !is.list(gj$features)) return(texto)
  gj$features <- lapply(gj$features, function(f) {
    geom <- f$geometry
    if (is.list(geom) && !is.null(geom$type) &&
        !is.null(geom$coordinates)) {
      if (identical(geom$type, "Polygon")) {
        geom$coordinates <- orientar_poligono(geom$coordinates)
      } else if (identical(geom$type, "MultiPolygon")) {
        geom$coordinates <- lapply(geom$coordinates, orientar_poligono)
      }
      f$geometry <- geom
    }
    f
  })
  jsonlite::toJSON(gj, auto_unbox = TRUE, digits = 7)
}

#' GeoJSON (string) de um objeto sf para mensagens Shiny ao cliente,
#' com aneis reorientados para o d3-geo do globo (ver
#' [painel_geojson_orientar()])
#' @keywords internal
painel_geojson <- function(x) {
  arquivo <- tempfile(fileext = ".geojson")
  on.exit(unlink(arquivo), add = TRUE)
  sf::st_write(x, arquivo, quiet = TRUE)
  texto <- paste(readLines(arquivo, warn = FALSE, encoding = "UTF-8"),
                 collapse = "")
  painel_geojson_orientar(texto)
}

#' Paleta de cores do mapa (port fiel do mypallet do labourvaluesdatapanel):
#' divergente centrada em 0 quando ha negativos, com rampas invertidas
#' conforme o argumento (checkbox "Inverter cores da escala"; a inversao
#' tambem vale para dados so positivos). O argumento escala controla o
#' dominio das cores (seletor "Escala" da toolbar do mapa): "zero" ancora
#' em 0 (historico, comparavel entre datas), "minmax" usa a faixa observada
#' no refdate (contraste maximo em faixas estreitas, como taxas de 16 a
#' 23%) e "quantil" classifica por posicao no ranking (colorQuantile).
#' @keywords internal
painel_paleta <- function(values, invertida = FALSE,
                          escala = c("zero", "minmax", "quantil")) {
  escala <- match.arg(escala)
  values[!is.finite(values)] <- NA_real_
  if (!any(is.finite(values))) {
    return(function(value) rep("transparent", length(value)))
  }
  finitos <- values[is.finite(values)]
  qtt <- length(values)
  if (isTRUE(invertida)) {
    rampa_neg <- grDevices::colorRampPalette(c("#0000FF", "#C8C8FF"))
    rampa_pos <- grDevices::colorRampPalette(c("#FFC8C8", "#FF0000"))
    rampa_so_positivos <- grDevices::colorRampPalette(c("#FF0000", "#FFC8C8"))
  } else {
    rampa_neg <- grDevices::colorRampPalette(c("#FF0000", "#C8C8FF"))
    rampa_pos <- grDevices::colorRampPalette(c("#C8C8FF", "#0000FF"))
    rampa_so_positivos <- grDevices::colorRampPalette(c("#FFC8C8", "#FF0000"))
  }

  # quantil: classes por posicao no ranking; sem valores distintos nao ha
  # quebras, entao cai no modo "zero"
  if (escala == "quantil" && length(unique(finitos)) > 1) {
    return(leaflet::colorQuantile(rampa_so_positivos(5), domain = finitos,
                                  n = 5, na.color = "transparent"))
  }

  if (escala == "minmax") {
    dominio <- range(finitos)
    if (dominio[1] == dominio[2]) {
      margem <- max(abs(dominio[1]) * 1e-8, 1e-12)
      dominio <- dominio + c(-margem, margem)
    }
    if (dominio[1] >= 0) {
      cores <- rampa_so_positivos(2 * qtt)
    } else if (dominio[2] <= 0) {
      cores <- rampa_neg(2 * qtt)
    } else {
      # rampa divergente partida no valor 0, nao no meio mecanico do
      # dominio: a fatia negativa recebe cores na proporcao da distancia
      # do minimo ate o zero
      frac0 <- (0 - dominio[1]) / (dominio[2] - dominio[1])
      n_neg <- max(1, min(2 * qtt - 1, round(2 * qtt * frac0)))
      cores <- c(rampa_neg(n_neg), rampa_pos(2 * qtt - n_neg))
    }
    return(leaflet::colorNumeric(cores, domain = dominio,
                                 na.color = "transparent"))
  }

  negative <- rampa_neg(qtt)
  positive <- rampa_pos(qtt)
  onlypositive <- rampa_so_positivos(qtt)
  suppressWarnings({
    maximum <- max(values, na.rm = TRUE) * 1.1
    minimum <- min(values, na.rm = TRUE) * 1.1
  })
  if (is.finite(minimum) && is.finite(maximum) &&
      minimum == 0 && maximum == 0) {
    minimum <- -1e-12
    maximum <- 1e-12
  }

  if (is.infinite(maximum) || is.infinite(minimum)) {
    return(function(value) rep("transparent", length(value)))
  }

  if (minimum < 0 && maximum > 0) {
    if (maximum > abs(minimum)) {
      dominio <- c(-maximum, maximum)
    } else {
      dominio <- c(minimum, -minimum)
    }
    cores <- c(negative, positive)
  } else if (maximum < 0) {
    dominio <- c(minimum, 0)
    cores <- negative
  } else {
    dominio <- c(0, maximum)
    cores <- onlypositive
  }

  leaflet::colorNumeric(cores, domain = dominio, na.color = "transparent")
}

#' Normaliza a unidade do numerador vinda do mdata_exts (dataunit_num):
#' trim, vazio/NA vira NA (colunas texte do DW costumam nascer TBD)
#' @keywords internal
painel_unidade_normaliza <- function(x) {
  x <- trimws(as.character(x))
  x[is.na(x) | !nzchar(x)] <- NA_character_
  x
}

#' Unidade e percentual: so dataunit_num = "%" liga a exibicao x100 (Gini
#' e indices entre 0 e 1 NAO sao percentual; a decisao vem do metadado,
#' nunca da faixa de valores)
#' @keywords internal
painel_eh_percent <- function(unidade) {
  if (length(unidade)) isTRUE(unname(painel_unidade_normaliza(
    unidade[1])) == "%") else FALSE
}

#' Numeros no padrao pt-BR para rotulos de mapa e legenda. Com unidade
#' percentual ("%" em dataunit_num) o valor 0..1 e exibido x100 com
#' sufixo " %" e menos casas significativas
#' @keywords internal
painel_num <- function(x, unidade = NULL) {
  if (painel_eh_percent(unidade)) {
    txt <- format(x * 100, big.mark = ".", decimal.mark = ",",
                  scientific = FALSE, trim = TRUE, digits = 4L)
    paste0(txt, " %")
  } else {
    format(x, big.mark = ".", decimal.mark = ",", scientific = FALSE,
           trim = TRUE, digits = 6)
  }
}

#' Remove camadas sem dados antes da conversao plotly: o ggplotly crasha
#' em to_basic (order/list) com camadas de zero linhas — caso real da
#' localidade escolhida ausente da serie por ano do ramo banda
#' @keywords internal
painel_sem_camadas_vazias <- function(p) {
  base <- p$data
  mantem <- vapply(p$layers, function(camada) {
    d <- camada$data
    if (is.null(d) || inherits(d, "waiver")) d <- base
    NROW(d) > 0
  }, logical(1))
  p$layers <- p$layers[mantem]
  p
}

#' Grafico em destaque da serie da aba Regiao, despachando o tipo por
#' indicador ("linha" default, "barras" ou "lollipop") e renomeando as
#' colunas para legendas amigaveis no hover do plotly ("Ano"/"valor"
#' em vez de "as.Date(refdate)"/"value"). Series anuais/bienais usam o
#' ano inteiro no eixo x; as demais mantem a data
#' @keywords internal
painel_plot_indicador <- function(v, titulo = NULL, cor = "#1351B4",
                                  tipo = "linha", rotulo_x = "Ano") {
  tipo <- tolower(trimws(as.character(tipo)[1]))
  if (is.na(tipo) || !tipo %in% c("barras", "lollipop")) tipo <- "linha"
  rotulo_x <- trimws(as.character(rotulo_x)[1])
  if (is.na(rotulo_x) || !nzchar(rotulo_x)) rotulo_x <- "Ano"
  d <- data.frame(
    x = if (identical(rotulo_x, "Ano"))
      as.integer(format(as.Date(v$refdate), "%Y")) else as.Date(v$refdate),
    valor = v$value)
  names(d)[1] <- rotulo_x
  p <- ggplot2::ggplot(d, ggplot2::aes(x = .data[[rotulo_x]],
                                      y = .data[["valor"]]))
  if (identical(tipo, "barras")) {
    p <- p + ggplot2::geom_col(fill = cor, width = 0.62)
  } else if (identical(tipo, "lollipop")) {
    p <- p + ggplot2::geom_segment(
      ggplot2::aes(xend = .data[[rotulo_x]], y = 0, yend = .data[["valor"]]),
      color = "#B5B5B5", linewidth = 0.8, show.legend = FALSE) +
      ggplot2::geom_point(color = cor, size = 2.6)
  } else {
    p <- p + ggplot2::geom_line(color = cor, linewidth = 0.9) +
      ggplot2::geom_point(color = cor, size = 1.8)
  }
  p + ggplot2::labs(title = titulo, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 12)
}

#' Banda de contexto min/mediana/max do indicador no nivel territorial
#' aberto, com a serie da localidade selecionada em destaque — porte da
#' plotabanda_destaque do painel_DAHU, sobre o corte transversal do cache
#' achatado [painel_valores_por_ano_cache()]. Series anuais/bienais
#' agregam por ano inteiro no eixo x; as demais mantem a data. Contexto
#' todo-NA (nenhum valor finito no periodo) devolve banda vazia sem erro.
#' As camadas de contexto (banda e mediana) saem sem marcadores — e assim
#' que o mod_panel_regiao identifica, no plotly, quais traces silenciar
#' @keywords internal
painel_plot_banda <- function(d, local_id, titulo = NULL, cor = "#1351B4",
                              rotulo_x = "Ano") {
  rotulo_x <- trimws(as.character(rotulo_x)[1])
  if (is.na(rotulo_x) || !nzchar(rotulo_x)) rotulo_x <- "Ano"
  por_ano <- identical(rotulo_x, "Ano")
  base <- if (!is.null(d) && NROW(d)) d else
    data.frame(local_id = integer(0), refdate = as.Date(character(0)),
               value = numeric(0), ano = integer(0))
  x <- if (por_ano) as.integer(base$ano) else as.Date(base$refdate)
  ok <- is.finite(base$value) & !is.na(x)
  xi <- x[ok]
  v <- base$value[ok]
  ux <- sort(unique(xi))
  ctx <- data.frame(
    x = ux,
    `Mínimo` = vapply(as.list(ux), function(k) min(v[xi == k]), numeric(1)),
    Mediana = vapply(as.list(ux), function(k) stats::median(v[xi == k]), numeric(1)),
    `Máximo` = vapply(as.list(ux), function(k) max(v[xi == k]), numeric(1)),
    check.names = FALSE)
  local_id <- suppressWarnings(as.integer(local_id)[1])
  sel <- !is.na(local_id) & base$local_id == local_id
  serie <- data.frame(x = x[sel], valor = base$value[sel], check.names = FALSE)
  names(ctx)[1] <- rotulo_x
  names(serie)[1] <- rotulo_x
  ggplot2::ggplot() +
    ggplot2::geom_ribbon(
      data = ctx,
      ggplot2::aes(x = .data[[rotulo_x]], ymin = .data[["Mínimo"]],
                   ymax = .data[["Máximo"]]),
      fill = cor, alpha = 0.10, na.rm = TRUE) +
    ggplot2::geom_line(
      data = ctx,
      ggplot2::aes(x = .data[[rotulo_x]], y = .data[["Mediana"]]),
      linetype = "dashed", color = "#4A4A4A", linewidth = 0.7,
      na.rm = TRUE, show.legend = FALSE) +
    ggplot2::geom_line(
      data = serie,
      ggplot2::aes(x = .data[[rotulo_x]], y = .data[["valor"]]),
      color = cor, linewidth = 0.9, na.rm = TRUE) +
    ggplot2::geom_point(
      data = serie,
      ggplot2::aes(x = .data[[rotulo_x]], y = .data[["valor"]]),
      color = cor, size = 1.8, na.rm = TRUE) +
    ggplot2::labs(title = titulo, x = NULL, y = NULL) +
    ggplot2::theme_minimal(base_size = 12)
}

#' Delta de camadas do mapa (port do wlv_map_layer_delta): mantem o par
#' completo cor/tooltip de cada camada alterada, para o cliente fundir por id
#' @keywords internal
painel_delta_camadas <- function(anteriores, camadas) {
  mudou <- vapply(camadas, function(camada)
    !identical(anteriores[[camada$id]], camada), logical(1L))
  camadas[mudou]
}

# Acessores cacheados das leituras do DW (ver painel_cache.R): geometrias
# quase nao mudam (30 dias); catalogo vale 7 dias e valores 30 — o
# aquecedor pos-ETL ([aquecer_painel()]) regenera o cache a cada carga,
# entao o TTL longo so segura o usuario entre ETLs. IDs invalidos
# retornam vazio sem tocar no cache (a chave nunca leva NA).
painel_cache_ttl <- c(geo = 24 * 30, catalogo = 24 * 7, valores = 24 * 30)

#' mdata com rotulos, cacheado
#' @keywords internal
painel_mdata_cache <- function() {
  painel_cache_get(painel_cache_chave("mdata"), painel_cache_ttl[["catalogo"]],
                   function() painel_com_con(painel_mdata))
}

#' Niveis territoriais disponiveis, cacheado
#' @keywords internal
painel_niveis_cache <- function() {
  painel_cache_get(painel_cache_chave("niveis"), painel_cache_ttl[["catalogo"]],
                   function() painel_com_con(painel_niveis))
}

#' Hierarquia de agrupamentos (Eixos/Objetivos), cacheado
#' @keywords internal
painel_hierarquia_cache <- function() {
  painel_cache_get(painel_cache_chave("hierarquia"), painel_cache_ttl[["catalogo"]],
                   function() painel_com_con(painel_hierarquia))
}

#' Indicadores compostos do catalogo, cacheado
#' @keywords internal
painel_compostos_cache <- function() {
  painel_cache_get(painel_cache_chave("compostos"), painel_cache_ttl[["catalogo"]],
                   function() painel_com_con(painel_compostos))
}

#' Fonte de cada indicador, cacheado
#' @keywords internal
painel_fontes_cache <- function() {
  painel_cache_get(painel_cache_chave("fontes"), painel_cache_ttl[["catalogo"]],
                   function() painel_com_con(painel_fontes))
}

#' Membros do grupo Resumo, cacheado
#' @keywords internal
painel_grupo_resumo_cache <- function() {
  painel_cache_get(painel_cache_chave("grupo_resumo"),
                   painel_cache_ttl[["catalogo"]],
                   function() painel_com_con(painel_grupo_resumo))
}

#' Geometrias municipais, cacheado
#' @keywords internal
painel_geo_mun_cache <- function() {
  painel_cache_get(painel_cache_chave("geo_mun"), painel_cache_ttl[["geo"]],
                   function() painel_com_con(painel_geo_mun))
}

#' Codigo IBGE dos municipios, cacheado
#' @keywords internal
painel_codigo_mun_cache <- function() {
  painel_cache_get(painel_cache_chave("codigo_mun"),
                   painel_cache_ttl[["catalogo"]],
                   function() painel_com_con(painel_codigo_mun))
}

#' Geometrias das UFs, cacheado
#' @keywords internal
painel_geo_uf_cache <- function() {
  painel_cache_get(painel_cache_chave("geo_uf"), painel_cache_ttl[["geo"]],
                   function() painel_com_con(painel_geo_uf))
}

#' Geometrias de um nivel territorial, cacheado
#' @keywords internal
painel_geo_nivel_cache <- function(nivel_id) {
  p <- painel_nivel_parse(nivel_id)
  if (is.na(p$nivel)) return(painel_geo_vazio())
  painel_cache_get(
    painel_cache_chave(sprintf("geo_nivel_%s", p$chave)),
    painel_cache_ttl[["geo"]],
    function() painel_com_con(function(con) painel_geo_nivel(con, nivel_id)))
}

#' Geometria de uma localidade, cacheada
#' @keywords internal
painel_geo_local_cache <- function(local_id) {
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(local_id)) return(painel_geo_vazio())
  painel_cache_get(
    painel_cache_chave(sprintf("geo_local_%d", local_id)),
    painel_cache_ttl[["geo"]],
    function() painel_com_con(function(con) painel_geo_local(con, local_id)))
}

#' Geometria da UF de uma localidade, cacheada
#' @keywords internal
painel_geo_pai_uf_cache <- function(local_id) {
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(local_id)) return(painel_geo_vazio())
  painel_cache_get(
    painel_cache_chave(sprintf("geo_pai_uf_%d", local_id)),
    painel_cache_ttl[["geo"]],
    function() painel_com_con(function(con) painel_geo_pai_uf(con, local_id)))
}

#' Malha municipal da UF de uma localidade, cacheada POR UF (a malha
#' inteira entra no cache; o municipio em destaque sai dela fora do cache,
#' senao a entrada serviria outra selecao do mesmo estado)
#' @keywords internal
painel_geo_mun_uf_cache <- function(local_id) {
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(local_id)) return(painel_geo_vazio())
  uf <- painel_com_con(function(con) DBI::dbGetQuery(con, sprintf(paste(
    "SELECT left(g.geoloc_id::text, 2) AS uf",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE l.local_id = %d"),
    local_id))$uf)
  uf <- as.character(uf)[1]
  if (is.na(uf) || !grepl("^[0-9]{2}$", uf)) return(painel_geo_vazio())
  malha <- painel_cache_get(
    painel_cache_chave(sprintf("geo_mun_uf_%s", uf)),
    painel_cache_ttl[["geo"]],
    function() painel_com_con(function(con) painel_geo_mun_uf(con, uf)))
  malha[malha$code != as.character(local_id), , drop = FALSE]
}

#' Malha decorativa do globo em torno da localidade em foco: selecao
#' municipal desenha as bordas dos demais municipios do estado
#' ([painel_geo_mun_uf_cache()]); selecao submunicipal (setor, bairro,
#' subdistrito, area de ponderacao — geoloc_id com mais de 10 digitos)
#' troca as bordas pelas proprias feicoes do nivel (pelo `nivel_tipo` da
#' localidade) dentro do municipio em foco
#' ([painel_geo_irmaos_mun()]), que tesselam o municipio inteiro. A feicao
#' do destaque sai fora do cache (cada selecao exclui a si mesma), como em
#' [painel_geo_mun_uf_cache()].
#' @keywords internal
painel_geo_malha_foco_cache <- function(local_id) {
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(local_id)) return(painel_geo_vazio())
  info <- painel_com_con(function(con) DBI::dbGetQuery(con, sprintf(paste(
    "SELECT g.geoloc_id::text AS codigo, l.nivel_tipo AS nivel_tipo",
    "FROM local l JOIN geoloc g USING (geoloc_id)",
    "WHERE l.local_id = %d"),
    local_id)))
  codigo <- as.character(info$codigo)[1]
  nivel_tipo <- as.character(info$nivel_tipo)[1]
  if (is.na(codigo) || !nzchar(codigo)) return(painel_geo_vazio())
  if (nchar(codigo) > 10L) {
    mun <- substr(codigo, 1, 7)
    tipo <- if (!is.na(nivel_tipo) && nzchar(nivel_tipo)) nivel_tipo else NULL
    chave_nivel <- if (!is.null(tipo)) tipo else as.character(nchar(codigo))
    malha <- painel_cache_get(
      painel_cache_chave(sprintf("geo_irmaos_%s_%s", chave_nivel, mun)),
      painel_cache_ttl[["geo"]],
      function() painel_com_con(function(con)
        painel_geo_irmaos_mun(con, mun = mun, tipo = tipo,
                              larg = nchar(codigo))))
    return(malha[malha$code != as.character(local_id), , drop = FALSE])
  }
  painel_geo_mun_uf_cache(local_id)
}

#' Malha completa de um nivel submunicipal dentro de um municipio
#' (geoloc de 7 digitos), cacheada por municipio — chave derivada da de
#' [painel_geo_malha_foco_cache()], com o teto no final para nao
#' conflitar com a malha do globo. O teto e maior que o do globo: o mapa
#' aguenta malhas de capital inteira (~5 mil setores) com a simplificacao
#' adaptativa de [painel_geo_irmaos_mun()]
#' @keywords internal
painel_geo_irmaos_nivel_cache <- function(mun, tipo = NULL, larg = NULL,
                                          max_feicoes = 6000L) {
  mun <- trimws(as.character(mun)[1])
  if (is.na(mun) || !grepl("^[0-9]{7}$", mun)) return(painel_geo_vazio())
  tipo <- if (length(tipo) == 1 && !is.na(tipo) && nzchar(tipo)) tipo else NULL
  chave_nivel <- if (!is.null(tipo)) tipo else
    suppressWarnings(as.character(as.integer(larg)[1]))
  if (is.na(chave_nivel)) return(painel_geo_vazio())
  painel_cache_get(
    painel_cache_chave(sprintf("geo_irmaos_%s_%s_%d",
                               chave_nivel, mun, as.integer(max_feicoes))),
    painel_cache_ttl[["geo"]],
    function() painel_com_con(function(con)
      painel_geo_irmaos_mun(con, mun = mun, tipo = tipo, larg = larg,
                            max_feicoes = max_feicoes)))
}

#' Contorno do municipio dono de um codigo submunicipal, cacheado
#' @keywords internal
painel_geo_municipio_codigo_cache <- function(codigo) {
  codigo <- trimws(as.character(codigo))[1]
  if (is.na(codigo) || !grepl("^[0-9]{7}$", codigo)) return(painel_geo_vazio())
  painel_cache_get(
    painel_cache_chave(sprintf("geo_municipio_%s", codigo)),
    painel_cache_ttl[["geo"]],
    function() painel_com_con(function(con)
      painel_geo_municipio_codigo(con, codigo)))
}

#' UFs com dados num nivel, cacheado
#' @keywords internal
painel_ufs_com_dados_cache <- function(mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  if (is.na(mdata_id) || is.na(p$nivel)) return(character(0))
  painel_cache_get(
    painel_cache_chave(sprintf("ufs_com_dados_%d_%s", mdata_id, p$chave)),
    painel_cache_ttl[["catalogo"]],
    function() painel_com_con(function(con)
      painel_ufs_com_dados(con, mdata_id, nivel_id)))
}

#' Localidade com maior cobertura numa UF, cacheada
#' @keywords internal
painel_local_top_uf_cache <- function(mdata_id, nivel_id, uf_local_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  uf_local_id <- suppressWarnings(as.integer(uf_local_id))[1]
  if (is.na(mdata_id) || is.na(p$nivel) || is.na(uf_local_id)) return(NULL)
  painel_cache_get(
    painel_cache_chave(sprintf("local_top_uf_%d_%s_%d",
                               mdata_id, p$chave, uf_local_id)),
    painel_cache_ttl[["catalogo"]],
    function() painel_com_con(function(con)
      painel_local_top_uf(con, mdata_id, nivel_id, uf_local_id)))
}

#' Localidades de um nivel territorial, cacheado
#' @keywords internal
painel_locais_nivel_cache <- function(nivel_id) {
  p <- painel_nivel_parse(nivel_id)
  if (is.na(p$nivel)) return(integer(0))
  painel_cache_get(
    painel_cache_chave(sprintf("locais_nivel_%s", p$chave)),
    painel_cache_ttl[["catalogo"]],
    function() painel_com_con(function(con) painel_locais_nivel(con, nivel_id)))
}

#' Localidade com maior cobertura de um indicador num nivel, cacheado
#' @keywords internal
painel_local_top_cache <- function(mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  if (is.na(mdata_id) || is.na(p$nivel)) return(NULL)
  painel_cache_get(
    painel_cache_chave(sprintf("local_top_%d_%s", mdata_id, p$chave)),
    painel_cache_ttl[["catalogo"]],
    function() painel_com_con(function(con)
      painel_local_top(con, mdata_id, nivel_id)))
}

#' Localidades de um nivel com dados para um indicador, cacheado
#' @keywords internal
painel_locais_com_dados_cache <- function(mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  if (is.na(mdata_id) || is.na(p$nivel)) return(character(0))
  painel_cache_get(
    painel_cache_chave(sprintf("locais_com_dados_%d_%s", mdata_id, p$chave)),
    painel_cache_ttl[["catalogo"]],
    function() painel_com_con(function(con)
      painel_locais_com_dados(con, mdata_id, nivel_id)))
}

#' Nivel territorial de um indicador, cacheado
#' @keywords internal
painel_ind_nivel_cache <- function(mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) return(NA_character_)
  painel_cache_get(
    painel_cache_chave(sprintf("ind_nivel_%d", mdata_id)),
    painel_cache_ttl[["catalogo"]],
    function() painel_com_con(function(con) painel_ind_nivel(con, mdata_id)))
}

#' Municipios com feicoes de um nivel submunicipal de um indicador,
#' cacheado
#' @keywords internal
painel_muns_nivel_dados_cache <- function(mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  p <- painel_nivel_parse(nivel_id)
  if (is.na(mdata_id) || is.na(p$nivel))
    return(data.frame(municipio = character(0), n_locais = integer(0)))
  painel_cache_get(
    painel_cache_chave(sprintf("muns_nivel_dados_%d_%s", mdata_id, p$chave)),
    painel_cache_ttl[["catalogo"]],
    function() painel_com_con(function(con)
      painel_muns_nivel_dados(con, mdata_id, nivel_id)))
}

#' Indicador tem dados no nivel territorial? Niveis pesados (malha acima
#' do limite do globo) consultam por UF; leves, por localidade — mesma
#' regra de disponibilidade do globo de localidades
#' @keywords internal
painel_ind_tem_dados <- function(mdata_id, nivel_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) return(FALSE)
  if (nrow(painel_geo_nivel_cache(nivel_id))) {
    length(painel_locais_com_dados_cache(mdata_id, nivel_id)) > 0
  } else {
    length(painel_ufs_com_dados_cache(mdata_id, nivel_id)) > 0
  }
}

#' Primeiro indicador visivel do catalogo com dados no nivel territorial:
#' destino da troca automatica quando o indicador corrente fica sem dados
#' ao mudar de nivel
#' @keywords internal
painel_indicador_com_dados <- function(md, nivel_id) {
  if (is.null(md) || !NROW(md) || !"mdata_id" %in% names(md)) return(NA_integer_)
  cand <- md$mdata_id
  if ("visivel" %in% names(md))
    cand <- cand[is.na(md$visivel) | md$visivel]
  for (id in cand) if (painel_ind_tem_dados(id, nivel_id))
    return(as.integer(id))
  NA_integer_
}

#' Serie de um indicador em uma localidade, cacheado
#' @keywords internal
painel_valores_local_cache <- function(mdata_id, local_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(mdata_id) || is.na(local_id)) {
    return(data.frame(refdate = as.Date(character(0)), value = numeric(0)))
  }
  painel_cache_get(
    painel_cache_chave(sprintf("valores_local_%d_%d", mdata_id, local_id)),
    painel_cache_ttl[["valores"]],
    function() painel_com_con(function(con)
      painel_valores_local(con, mdata_id, local_id)))
}

#' Valores de todos os indicadores em uma localidade, cacheado
#' @keywords internal
painel_valores_local_todos_cache <- function(local_id) {
  local_id <- suppressWarnings(as.integer(local_id))[1]
  if (is.na(local_id)) {
    return(data.frame(mdata_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0)))
  }
  painel_cache_get(
    painel_cache_chave(sprintf("valores_local_todos_%d", local_id)),
    painel_cache_ttl[["valores"]],
    function() painel_com_con(function(con)
      painel_valores_local_todos(con, local_id)))
}

#' Anos com observacoes de um indicador, cacheado
#' @keywords internal
painel_anos_cache <- function(mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) return(data.frame(ano = integer(0)))
  painel_cache_get(
    painel_cache_chave(sprintf("anos_%d", mdata_id)),
    painel_cache_ttl[["valores"]],
    function() painel_com_con(function(con) painel_anos(con, mdata_id)))
}

#' Refdates distintos de um indicador, cacheados
#' @keywords internal
painel_refdates_cache <- function(mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) {
    return(data.frame(refdate = as.Date(character(0))))
  }
  painel_cache_get(
    painel_cache_chave(sprintf("refdates_%d", mdata_id)),
    painel_cache_ttl[["valores"]],
    function() painel_com_con(function(con) painel_refdates(con, mdata_id)))
}

#' Valores por refdate exato, cacheados (slider por data do mapa)
#' @keywords internal
painel_valores_refdate_cache <- function(mdata_id, refdate) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  refdate <- as.Date(refdate)[1]
  if (is.na(mdata_id) || is.na(refdate)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0)))
  }
  painel_cache_get(
    painel_cache_chave(sprintf("valores_refdate_%d_%s", mdata_id,
                               format(refdate, "%Y%m%d"))),
    painel_cache_ttl[["valores"]],
    function() painel_com_con(function(con)
      painel_valores_refdate(con, mdata_id, refdate)))
}

#' Serie completa reduzida a 1 observacao por localidade x ano, cacheada
#' (cache achatado: uma chave por indicador em vez de uma por ano — o mapa
#' animado e a aba Baixar pagariam a regeneracao a cada ano do slider)
#' @keywords internal
painel_valores_por_ano_cache <- function(mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0), ano = integer(0)))
  }
  painel_cache_get(
    painel_cache_chave(sprintf("valores_por_ano_%d", mdata_id)),
    painel_cache_ttl[["valores"]],
    function() painel_com_con(function(con)
      painel_valores_por_ano(con, mdata_id)))
}

#' Serie completa com todas as observacoes (localidade x refdate),
#' cacheada: uma chave por indicador, base do explorar e do recorte por
#' data da aba Baixar
#' @keywords internal
painel_valores_por_data_cache <- function(mdata_id) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  if (is.na(mdata_id)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0), ano = integer(0)))
  }
  painel_cache_get(
    painel_cache_chave(sprintf("valores_por_data_%d", mdata_id)),
    painel_cache_ttl[["valores"]],
    function() painel_com_con(function(con)
      painel_valores_por_data(con, mdata_id)))
}

#' Valores do ultimo refdate por localidade num ano: fatia do cache
#' achatado [painel_valores_por_ano_cache()] com a assinatura historica
#' (mapa, baixar e ranking seguem sem mudanca de chamada)
#' @keywords internal
painel_valores_ano_cache <- function(mdata_id, ano) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  ano <- suppressWarnings(as.integer(ano))[1]
  if (is.na(mdata_id) || is.na(ano)) {
    return(data.frame(local_id = integer(0), refdate = as.Date(character(0)),
                      value = numeric(0)))
  }
  painel_filtrar_ano(painel_valores_por_ano_cache(mdata_id), ano)
}

#' Ranking de uma localidade num indicador e data, cacheado: com `refdate`
#' valido, ranking no dia exato; sem `refdate`, no ultimo refdate do ano
#' (contrato historico)
#' @keywords internal
painel_ranking_local_cache <- function(mdata_id, local_id, ano,
                                       refdate = NULL) {
  mdata_id <- suppressWarnings(as.integer(mdata_id))[1]
  local_id <- suppressWarnings(as.integer(local_id))[1]
  ano <- suppressWarnings(as.integer(ano))[1]
  refdate <- as.Date(refdate)[1]
  if (is.na(mdata_id) || is.na(local_id) || is.na(ano)) {
    return(painel_ranking_vazio())
  }
  painel_cache_get(
    painel_cache_chave(sprintf("ranking_%d_%d_%d_%s", mdata_id, local_id,
                               ano, if (!is.na(refdate))
                                 format(refdate, "%Y%m%d") else "ano")),
    painel_cache_ttl[["valores"]],
    function() painel_com_con(function(con)
      painel_ranking_local(con, mdata_id, local_id, ano, refdate)))
}
