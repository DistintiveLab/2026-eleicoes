# Pipeline Virada 2ºT 2026 — DF -------------------------------------------------
# Estágios (rodar em ordem; cada um salva RDS em coleta/cache/virada/):
#   t0  : parse votacao_secao 2026 (presidente via BR + governador via DF)
#         -> secao_2026.rds + validação contra detalhe_votacao_munzona
#   t0p : parse perfil_eleitor_secao_2026_DF -> perfil_2026_raw.rds
#   t1  : unidade local de votação + pareamento 2022<->2026
#   t2..t5: indicadores V1-V5 + IPV -> data/virada_*.csv + painel/data_virada/
# Uso: Rscript R/prep_virada_2t.R t0 [t0p t1 ...]
#
# Base de dados de referência: votacao_secao (nominal por seção). Divergência
# conhecida vs totalização oficial: 10.299 votos nominais de governador
# anulados apurados em separado (sub judice) aparecem como nominais aqui;
# comparecimento/brancos/nulos batem exatamente com o munzona.

library(readr)
library(dplyr)
library(tidyr)

CACHE <- "coleta/cache"
VIRADA <- file.path(CACHE, "virada")
dir.create(VIRADA, showWarnings = FALSE, recursive = TRUE)

CAND_PRES <- c(lula = "13", flavio = "22")
CAND_GOV <- c(grass = "13", celina = "11")
BRANCO <- "95"; NULO <- "96"

ler_votacao_secao <- function(caminho, turno = NULL) {
  x <- read_csv2(caminho, locale = locale(encoding = "Latin1"), progress = FALSE,
    col_types = cols(.default = col_character(),
      NR_TURNO = col_integer(), NR_ZONA = col_integer(),
      NR_SECAO = col_integer(), CD_CARGO = col_integer(),
      QT_VOTOS = col_integer()),
    col_select = any_of(c("NR_TURNO", "NR_ZONA", "NR_SECAO", "CD_CARGO",
      "DS_CARGO", "NR_VOTAVEL", "NM_VOTAVEL", "QT_VOTOS",
      "NR_LOCAL_VOTACAO", "NM_LOCAL_VOTACAO", "DS_LOCAL_VOTACAO_ENDERECO")))
  if (!is.null(turno)) x <- x %>% filter(NR_TURNO == turno)
  x
}

pivot_cargo <- function(x, mapa, prefixo) {
  x %>%
    mutate(col = ifelse(NR_VOTAVEL %in% mapa,
      names(mapa)[match(NR_VOTAVEL, mapa)],
      ifelse(NR_VOTAVEL == BRANCO, "brancos",
      ifelse(NR_VOTAVEL == NULO, "nulos", "terceiros")))) %>%
    count(NR_ZONA, NR_SECAO, col, wt = QT_VOTOS, name = "v") %>%
    pivot_wider(names_from = col, values_from = v, values_fill = 0) %>%
    rename_with(~ paste0(prefixo, .x), .cols = -c(NR_ZONA, NR_SECAO))
}

# T0: seções 2026 (presidente do BR + governador do DF) -------------------------

t0 <- function() {
  pres <- ler_votacao_secao(file.path(CACHE, "vs2026br", "votacao_secao_2026_DF_pres.csv"))
  gov <- ler_votacao_secao(file.path(CACHE, "vs2026", "votacao_secao_2026_DF.csv"))
  stopifnot(all(pres$NR_TURNO == 1L), all(gov$NR_TURNO == 1L))
  pres <- pres %>% filter(CD_CARGO == 1)
  gov <- gov %>% filter(CD_CARGO == 3)

  valida <- function(x, mapa, rotulo) {
    validos <- x %>% filter(!NR_VOTAVEL %in% c(BRANCO, NULO)) %>%
      summarise(v = sum(QT_VOTOS)) %>% pull(v)
    tot <- sum(x$QT_VOTOS)
    resumo <- x %>% filter(NR_VOTAVEL %in% mapa) %>%
      group_by(NR_VOTAVEL) %>% summarise(v = sum(QT_VOTOS), .groups = "drop")
    rot <- sprintf("%s %d (%.2f%%)", names(mapa)[match(resumo$NR_VOTAVEL, mapa)],
      resumo$v, resumo$v / validos * 100)
    cat(sprintf("%s: válidos=%d brancos=%d nulos=%d | %s\n", rotulo, validos,
      sum(x$QT_VOTOS[x$NR_VOTAVEL == BRANCO]),
      sum(x$QT_VOTOS[x$NR_VOTAVEL == NULO]), paste(rot, collapse = " ")))
  }
  cat("== 1ºT DF (base nominal votacao_secao) ==\n")
  valida(pres, CAND_PRES, "presidente")
  valida(gov, CAND_GOV, "governador")

  sp <- pivot_cargo(pres, CAND_PRES, "p_")
  sg <- pivot_cargo(gov, CAND_GOV, "g_")
  loc <- bind_rows(
      pres %>% distinct(NR_ZONA, NR_SECAO, NR_LOCAL_VOTACAO, NM_LOCAL_VOTACAO, DS_LOCAL_VOTACAO_ENDERECO),
      gov %>% distinct(NR_ZONA, NR_SECAO, NR_LOCAL_VOTACAO, NM_LOCAL_VOTACAO, DS_LOCAL_VOTACAO_ENDERECO)) %>%
    distinct()

  secao <- sp %>%
    full_join(sg, by = c("NR_ZONA", "NR_SECAO")) %>%
    left_join(loc, by = c("NR_ZONA", "NR_SECAO")) %>%
    mutate(across(where(is.numeric), ~ replace_na(.x, 0)))

  cat(sprintf("seções: presidente=%d governador=%d união=%d\n",
    nrow(sp), nrow(sg), nrow(secao)))
  saveRDS(secao, file.path(VIRADA, "secao_2026.rds"))
  invisible(secao)
}

# T0 validação: soma por seção vs detalhe_votacao_munzona (oficial 11/10) -------

t0v <- function() {
  m <- read_csv2(file.path(CACHE, "vs2026", "detalhe_votacao_munzona_2026_DF.csv"),
    locale = locale(encoding = "Latin1"), progress = FALSE,
    col_types = cols(.default = col_character(), QT_APTOS = col_integer(),
      QT_COMPARECIMENTO = col_integer(), QT_ABSTENCOES = col_integer(),
      QT_VOTOS = col_integer(), QT_VOTOS_NOMINAIS_VALIDOS = col_integer(),
      QT_VOTOS_BRANCOS = col_integer(), QT_VOTOS_NULOS = col_integer()))
  of <- m %>% filter(DS_CARGO == "Governador") %>%
    summarise(aptos = sum(QT_APTOS), comp = sum(QT_COMPARECIMENTO),
      abst = sum(QT_ABSTENCOES), brancos = sum(QT_VOTOS_BRANCOS),
      nulos = sum(QT_VOTOS_NULOS), validos = sum(QT_VOTOS_NOMINAIS_VALIDOS))
  secao <- readRDS(file.path(VIRADA, "secao_2026.rds"))
  nosso <- secao %>%
    summarise(votos = sum(g_grass + g_celina + g_terceiros +
      g_brancos + g_nulos),
      brancos = sum(g_brancos), nulos = sum(g_nulos),
      validos = sum(g_grass + g_celina + g_terceiros))
  cat("== validação governador vs munzona oficial ==\n")
  cat(sprintf("comparecimento: nosso=%d oficial=%d %s\n", nosso$votos, of$comp,
    ifelse(nosso$votos == of$comp, "OK", "DIVERGE")))
  cat(sprintf("brancos: nosso=%d oficial=%d %s | nulos: nosso=%d oficial=%d %s\n",
    nosso$brancos, of$brancos, ifelse(nosso$brancos == of$brancos, "OK", "DIVERGE"),
    nosso$nulos, of$nulos, ifelse(nosso$nulos == of$nulos, "OK", "DIVERGE")))
  cat(sprintf("válidos nominais: nosso=%d oficial=%d (dif=%d = anulados sub judice)\n",
    nosso$validos, of$validos, nosso$validos - of$validos))
  cat(sprintf("aptos oficiais DF=%d abstenções=%d (%.1f%%)\n",
    of$aptos, of$abst, of$abst / of$aptos * 100))
}

# T0 perfil: eleitoras por seção (total e 16-29) --------------------------------

t0p <- function() {
  arq <- file.path(CACHE, "perfil2026", "perfil_eleitor_secao_2026_DF.csv")
  pf <- read_csv2(arq, locale = locale(encoding = "Latin1"), progress = FALSE,
    col_types = cols(.default = col_character(),
      NR_ZONA = col_integer(), NR_SECAO = col_integer(),
      QT_ELEITORES = col_integer()),
    col_select = any_of(c("NR_ZONA", "NR_SECAO", "CD_GENERO", "DS_GENERO",
      "CD_FAIXA_ETARIA", "DS_FAIXA_ETARIA", "QT_ELEITORES")))
  tot <- pf %>% summarise(across(QT_ELEITORES, sum)) %>% pull()
  fem <- pf %>% filter(DS_GENERO == "FEMININO") %>%
    summarise(across(QT_ELEITORES, sum)) %>% pull()
  faixas_jovens <- c("16 anos", "17 anos", "18 anos", "19 anos", "20 anos",
    "21 a 24 anos", "25 a 29 anos")
  fem_jov <- pf %>% filter(DS_GENERO == "FEMININO",
      DS_FAIXA_ETARIA %in% faixas_jovens) %>%
    summarise(across(QT_ELEITORES, sum)) %>% pull()
  cat(sprintf("perfil 2026: eleitores=%d eleitoras=%d (%.1f%%) eleitoras 16-29=%d\n",
    tot, fem, fem / tot * 100, fem_jov))
  cat(sprintf("seções no perfil: %d\n", nrow(pf %>% distinct(NR_ZONA, NR_SECAO))))
  saveRDS(pf, file.path(VIRADA, "perfil_2026_raw.rds"))
  invisible(pf)
}

# T1: unidades locais de votação (2026 e 2022) + pareamento --------------------

# locais_votacao_ra_df.csv tem encoding misto (UTF-8 e Latin-1):
# lê como Latin-1 e repara mojibake das partes originalmente UTF-8
consertar_utf8 <- function(x) {
  idx <- !is.na(x) & grepl("[ÂÃâã]", x)
  y <- x
  if (any(idx)) {
    z <- iconv(x[idx], "UTF-8", "ISO8859-1")
    ok <- !is.na(z) & validUTF8(z)
    y[idx][ok] <- z[ok]
  }
  y
}

normalizar_nome <- function(x) {
  x <- toupper(trimws(x))
  x <- gsub("[^A-Z0-9À-Ý ]", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

dist_m <- function(lat1, lon1, lat2, lon2) {
  dy <- (lat2 - lat1) * 110540
  dx <- (lon2 - lon1) * 111320 * cos((lat1 + lat2) / 2 * pi / 180)
  sqrt(dx^2 + dy^2)
}

t1 <- function() {
  loc <- read_csv("data/locais_votacao_ra_df.csv", progress = FALSE,
    show_col_types = FALSE, locale = locale(encoding = "Latin1"))
  loc <- loc %>% mutate(across(where(is.character), consertar_utf8))
  secao <- readRDS(file.path(VIRADA, "secao_2026.rds"))

  secao26 <- loc %>%
    inner_join(secao, by = c("zona" = "NR_ZONA", "secao" = "NR_SECAO")) %>%
    mutate(local_key = paste0(sprintf("%.4f", round(lat, 4)), "|",
      sprintf("%.4f", round(lon, 4)), "|", normalizar_nome(local)))

  # seções do cadastro sem voto também contam aptos no local
  sem_voto <- loc %>%
    anti_join(secao, by = c("zona" = "NR_ZONA", "secao" = "NR_SECAO")) %>%
    mutate(local_key = paste0(sprintf("%.4f", round(lat, 4)), "|",
      sprintf("%.4f", round(lon, 4)), "|", normalizar_nome(local)))

  votos_cols <- c("p_lula", "p_flavio", "p_terceiros", "p_brancos", "p_nulos",
    "g_grass", "g_celina", "g_terceiros", "g_brancos", "g_nulos")

  attrs_cols <- c("local_key", "zona", "secao", "local", "lat", "lon",
    "eleitores_secao", "ra_geo", "ra_nome")
  attrs_local <- bind_rows(
      secao26 %>% select(all_of(attrs_cols), all_of(votos_cols)),
      sem_voto %>% select(all_of(attrs_cols)) %>%
        mutate(!!!setNames(rep(0, length(votos_cols)), votos_cols))) %>%
    group_by(local_key) %>%
    summarise(n_secoes = n(), aptos = sum(eleitores_secao),
      nome = first(normalizar_nome(local)), lat = first(lat), lon = first(lon),
      ra = first(ra_geo), ra_nome = first(ra_nome),
      zonas = paste(sort(unique(zona)), collapse = ","),
      .groups = "drop")
  votos_local <- secao26 %>%
    group_by(local_key) %>%
    summarise(n_secoes_votantes = n(),
      across(all_of(votos_cols), ~ sum(.x, na.rm = TRUE)), .groups = "drop")
  local26 <- attrs_local %>%
    left_join(votos_local, by = "local_key") %>%
    tidyr::replace_na(list(n_secoes_votantes = 0)) %>%
    mutate(across(all_of(votos_cols), ~ tidyr::replace_na(.x, 0)),
      local_id = row_number())

  codigos26 <- NULL

  # ---- 2022: eleitorado/local + votos presidente 2º turno por seção ----------
  elv <- read_delim(file.path(CACHE, "elv2022", "eleitorado_local_votacao_2022_DF.csv"),
    delim = ";", locale = locale(encoding = "Latin1", decimal_mark = "."),
    progress = FALSE,
    col_types = cols(.default = col_character(),
      NR_ZONA = col_integer(), NR_SECAO = col_integer(),
      NR_LOCAL_VOTACAO = col_integer(), NR_LATITUDE = col_double(),
      NR_LONGITUDE = col_double(), QT_ELEITOR_SECAO = col_integer()),
    col_select = c(NR_TURNO, NR_ZONA, NR_SECAO, NR_LOCAL_VOTACAO,
      NM_LOCAL_VOTACAO, NR_LATITUDE, NR_LONGITUDE, QT_ELEITOR_SECAO)) %>%
    distinct(NR_ZONA, NR_SECAO, NR_LOCAL_VOTACAO, NM_LOCAL_VOTACAO,
      NR_LATITUDE, NR_LONGITUDE, QT_ELEITOR_SECAO)

  p22 <- ler_votacao_secao(
    file.path(CACHE, "vs2022br", "votacao_secao_2022_DF_pres.csv"), turno = 2)
  stopifnot(all(p22$CD_CARGO == 1))
  pres22 <- p22 %>%
    filter(NR_VOTAVEL %in% c("13", "22", "95", "96")) %>%
    mutate(col = c("13" = "lula22", "22" = "bolo22", "95" = "brancos22",
      "96" = "nulos22")[NR_VOTAVEL]) %>%
    count(NR_ZONA, NR_SECAO, col, wt = QT_VOTOS, name = "v") %>%
    pivot_wider(names_from = col, values_from = v, values_fill = 0) %>%
    mutate(validos22 = lula22 + bolo22)

  cat(sprintf("2022 2ºT DF: Lula %d (%.2f%%) Bolsonaro %d (%.2f%%) | seções %d\n",
    sum(pres22$lula22), sum(pres22$lula22) / sum(pres22$validos22) * 100,
    sum(pres22$bolo22), sum(pres22$bolo22) / sum(pres22$validos22) * 100,
    nrow(pres22)))

  local22 <- elv %>%
    inner_join(pres22, by = c("NR_ZONA", "NR_SECAO")) %>%
    mutate(local_key22 = paste0(sprintf("%.4f", round(NR_LATITUDE, 4)), "|",
      sprintf("%.4f", round(NR_LONGITUDE, 4)), "|", normalizar_nome(NM_LOCAL_VOTACAO))) %>%
    group_by(local_key22) %>%
    summarise(nome22 = normalizar_nome(NM_LOCAL_VOTACAO[1]),
      lat22 = mean(NR_LATITUDE, na.rm = TRUE),
      lon22 = mean(NR_LONGITUDE, na.rm = TRUE),
      aptos22 = sum(QT_ELEITOR_SECAO), n_secoes22 = n(),
      across(c(lula22, bolo22, brancos22, nulos22, validos22), sum),
      .groups = "drop") %>%
    mutate(id22 = row_number()) %>%
    filter(is.finite(lat22), is.finite(lon22))

  # ---- pareamento 2022 -> 2026 (código NR_LOCAL_VOTACAO não é único por
  # local físico: 107 códigos vs 559 locais; usa nome + coordenada) ----------
  cruz <- expand_grid(i22 = local22$id22, local_id = local26$local_id) %>%
    mutate(d = dist_m(local22$lat22[i22], local22$lon22[i22],
      local26$lat[local_id], local26$lon[local_id])) %>%
    filter(is.finite(d))

  usados22 <- integer(0); usados26 <- integer(0)

  passo1 <- cruz %>%
    filter(!(local22$id22[i22] %in% usados22),
      !(local26$local_id[local_id] %in% usados26)) %>%
    mutate(nome22 = local22$nome22[i22], nome26 = local26$nome[local_id]) %>%
    filter(d <= 150, nome22 == nome26)
  usados22 <- local22$id22[passo1$i22]
  usados26 <- local26$local_id[passo1$local_id]

  passo2 <- cruz %>%
    filter(!(local22$id22[i22] %in% usados22),
      !(local26$local_id[local_id] %in% usados26)) %>%
    filter(d <= 150) %>%
    group_by(i22) %>% slice_min(d, n = 1) %>% ungroup() %>%
    group_by(local_id) %>% slice_min(d, n = 1) %>% ungroup()
  usados22 <- c(usados22, local22$id22[passo2$i22])
  usados26 <- c(usados26, local26$local_id[passo2$local_id])

  resto <- setdiff(local22$id22, usados22)
  passo3 <- bind_rows(lapply(resto, function(cd) {
    i <- match(cd, local22$id22)
    cand <- local26 %>%
      filter(!(local_id %in% usados26)) %>%
      mutate(d = dist_m(local22$lat22[i], local22$lon22[i], lat, lon),
        adist = adist(local22$nome22[i], nome)) %>%
      filter(d <= 2000) %>% arrange(adist, d) %>% head(1)
    if (nrow(cand)) {
      usados26 <<- c(usados26, cand$local_id)
      tibble(i22 = cd, local_id = cand$local_id)
    }
  }))

  pares <- bind_rows(
    passo1 %>% transmute(i22 = local22$id22[i22],
      local_id = local26$local_id[local_id], etapa = 1),
    passo2 %>% transmute(i22 = local22$id22[i22],
      local_id = local26$local_id[local_id], etapa = 2),
    passo3 %>% transmute(etapa = 3)) %>%
    distinct(i22, local_id, .keep_all = TRUE)

  cat(sprintf("pareamento: %d/%d locais 2022 (%.1f%%) | por etapa 1/2/3: %s\n",
    nrow(pares), nrow(local22), nrow(pares) / nrow(local22) * 100,
    paste(as.integer(table(factor(pares$etapa, levels = 1:3))),
      collapse = "/")))

  local26_pareado <- local26 %>%
    left_join(pares %>% select(local_id, i22, etapa), by = "local_id") %>%
    left_join(local22 %>% select(id22, lula22, bolo22, brancos22, nulos22,
      validos22, aptos22, n_secoes22), by = c("i22" = "id22"))

  saveRDS(local26_pareado, file.path(VIRADA, "local_2026.rds"))
  cat(sprintf("locais 2026: %d | com par 2022: %d | aptos DF=%d\n",
    nrow(local26_pareado), sum(!is.na(local26_pareado$i22)),
    sum(local26_pareado$aptos)))
  invisible(local26_pareado)
}

stages <- list(t0 = t0, t0v = t0v, t0p = t0p, t1 = t1)
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) args <- names(stages)
for (s in args) {
  cat("\n== estágio", s, "==\n")
  stages[[s]]()
}
