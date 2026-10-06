# Prep do perfil sociodemografico (populacao + eleitorado) por RA do DF
# Fontes:
#   IBGE Censo 2022 - agregados por SUBDISTRITO (no DF, subdistritos = Regioes Administrativas)
#   IBGE Censo 2022 - malha de subdistritos DF (gpkg) para spatial join
#   TSE 2026 - eleitorado_local_votacao_2026_DF.csv (secao -> local -> bairro -> lat/lon)
#   TSE 2026 - perfil_eleitor_secao_2026_DF.csv (perfil do eleitorado por secao)
# Saidas em data/:
#   pop_ra_df.csv            - indicadores do Censo 2022 por RA
#   locais_votacao_ra_df.csv - secoes com local, bairro TSE, RA e coordenadas
#   eleitorado_ra_df.csv     - perfil do eleitorado por RA

suppressMessages({
  library(data.table)
  library(sf)
})

RAW <- "data-raw/raw/x"
OUT <- "data"
dir.create(OUT, showWarnings = FALSE)

msg <- function(...) cat(sprintf(...), "\n")

num <- function(x) {
  x <- as.character(x)
  x[is.na(x) | x == "." | x == ""] <- "0"
  as.numeric(x)
}

norm_txt <- function(x) {
  x <- tolower(as.character(x))
  acc <- c("\u00e1","\u00e0","\u00e2","\u00e3","\u00e4",
           "\u00e9","\u00e8","\u00ea","\u00eb",
           "\u00ed","\u00ec","\u00ee","\u00ef",
           "\u00f3","\u00f2","\u00f4","\u00f5","\u00f6",
           "\u00fa","\u00f9","\u00fb","\u00fc","\u00e7")
  sem <- c("a","a","a","a","a","e","e","e","e","i","i","i","i",
           "o","o","o","o","o","u","u","u","u","c")
  for (i in seq_along(acc)) x <- gsub(acc[i], sem[i], x, fixed = TRUE)
  x <- gsub("['`^~\u00b4]", "", x)
  toupper(trimws(gsub("\\s+", " ", x)))
}

rd <- function(f, ...) fread(file.path(RAW, f), encoding = "Latin-1", dec = ",", showProgress = FALSE, ...)

# 1. Populacao por RA (subdistritos do DF) --------------------------------

bas <- rd("Agregados_por_subdistritos_basico_BR.csv")[NM_UF == "Distrito Federal"]
dem <- rd("Agregados_por_subdistritos_demografia_BR.csv")[CD_SUBDIST %in% bas$CD_SUBDIST]
cr  <- rd("Agregados_por_subdistritos_cor_ou_raca_BR.csv")[CD_SUBDIST %in% bas$CD_SUBDIST]
alf <- rd("Agregados_por_subdistritos_alfabetizacao_BR.csv")[CD_SUBDIST %in% bas$CD_SUBDIST]
rr  <- rd("Agregados_por_subdistritos_renda_responsavel_BR.csv")[CD_SUBDIST %in% bas$CD_SUBDIST]
msg("IBGE subdistritos DF: %d", nrow(bas))

to_num <- function(dt, cols) dt[, (cols) := lapply(.SD, num), .SDcols = cols]
dem_cols <- paste0("V010", sprintf("%02d", 6:41)); to_num(dem, dem_cols)
cr_cols  <- paste0("V013", 17:21);                 to_num(cr, cr_cols)
alf_cols <- grep("^V0", names(alf), value = TRUE); to_num(alf, alf_cols)
rr_cols  <- paste0("V0600", 1:6);                  to_num(rr, rr_cols)

pop <- data.table(
  cd_subdist    = bas$CD_SUBDIST,
  ra_ibge       = norm_txt(bas$NM_SUBDIST),
  ra_nome       = bas$NM_SUBDIST,
  area_km2      = num(bas$AREA_KM2),
  populacao     = num(bas$v0001),
  domicilios    = num(bas$v0002),
  dpp_ocupados  = num(bas$v0007),
  moradores_por_domicilio = num(bas$v0005)
)
stopifnot(!anyDuplicated(pop$ra_ibge))

pop[, pop_0_14    := dem$V01031 + dem$V01032 + dem$V01033]
pop[, pop_15_29   := dem$V01034 + dem$V01035 + dem$V01036]
pop[, pop_30_59   := dem$V01037 + dem$V01038 + dem$V01039]
pop[, pop_60_mais := dem$V01040 + dem$V01041]
pop[, pct_0_14    := round(100 * pop_0_14 / populacao, 1)]
pop[, pct_15_29   := round(100 * pop_15_29 / populacao, 1)]
pop[, pct_30_59   := round(100 * pop_30_59 / populacao, 1)]
pop[, pct_60_mais := round(100 * pop_60_mais / populacao, 1)]
pop[, pct_fem     := round(100 * dem$V01008 / dem$V01006, 1)]
tot_cor <- cr$V01317 + cr$V01318 + cr$V01319 + cr$V01320 + cr$V01321
pop[, pct_preta_parda := round(100 * (cr$V01318 + cr$V01320) / tot_cor, 1)]

bloco_idade <- c(paste0("V0064", 4:9), paste0("V006", 50:56))
pop[, pop_15_mais := rowSums(as.matrix(alf[, ..bloco_idade]))]
pop[, renda_media_resp   := round(rr$V06004, 0)]
pop[, renda_mediana_resp := round(rr$V06006, 0)]
pop[, densidade_hab_km2  := round(populacao / area_km2, 0)]

pop_keep <- c("cd_subdist","ra_ibge","ra_nome","area_km2","populacao","pop_15_mais","domicilios",
              "dpp_ocupados","moradores_por_domicilio","densidade_hab_km2",
              "pct_0_14","pct_15_29","pct_30_59","pct_60_mais","pct_fem",
              "pct_preta_parda",
              "renda_media_resp","renda_mediana_resp")
pop <- pop[, ..pop_keep]
setorder(pop, -populacao)
fwrite(pop, file.path(OUT, "pop_ra_df.csv"))
msg("pop_ra_df.csv: %d RAs | pop DF = %s", nrow(pop), format(sum(pop$populacao), big.mark = ","))

# 2. Locais de votacao: secao -> bairro TSE -> RA IBGE --------------------

lv <- rd("eleitorado_local_votacao_2026_DF.csv")
msg("locais: %d linhas | %d secoes", nrow(lv), uniqueN(lv[, .(NR_ZONA, NR_SECAO)]))
lv2 <- lv[, .(
  zona = NR_ZONA, secao = NR_SECAO, local = NM_LOCAL_VOTACAO,
  endereco = DS_ENDERECO, bairro_tse = NM_BAIRRO,
  lat = suppressWarnings(as.numeric(NR_LATITUDE)),
  lon = suppressWarnings(as.numeric(NR_LONGITUDE)),
  eleitores_secao = QT_ELEITOR_SECAO
)]
lv2[, bairro_norm := norm_txt(bairro_tse)]

alias <- c(
  "AGUAS CLARAS - TAGUATINGA SUL" = "AGUAS CLARAS",
  "NORTE (AGUAS CLARAS)"  = "AGUAS CLARAS",
  "SUL (AGUAS CLARAS)"    = "AGUAS CLARAS",
  "AREA OCTOGONAL SUL"    = "SUDOESTE/OCTOGONAL",
  "SETOR SUDOESTE"        = "SUDOESTE/OCTOGONAL",
  "ASA NORTE"             = "PLANO PILOTO",
  "ASA SUL"               = "PLANO PILOTO",
  "SETOR MILITAR URBANO"  = "PLANO PILOTO",
  "SETOR MILITAR COMPLEMENTAR" = "PLANO PILOTO",
  "GRANJA DO TORTO"       = "PLANO PILOTO",
  "CRUZEIRO NOVO"         = "CRUZEIRO",
  "CRUZEIRO VELHO"        = "CRUZEIRO",
  "GUARA I"               = "GUARA",
  "GUARA II"              = "GUARA",
  "CEILANDIA NORTE"       = "CEILANDIA",
  "CEILANDIA SUL"         = "CEILANDIA",
  "TAGUATINGA CENTRO"     = "TAGUATINGA",
  "TAGUATINGA NORTE"      = "TAGUATINGA",
  "TAGUATINGA SUL"        = "TAGUATINGA",
  "SETOR LESTE"           = "TAGUATINGA",
  "SETOR SUL"             = "TAGUATINGA",
  "SETOR NORTE"           = "TAGUATINGA",
  "SETOR OESTE"           = "TAGUATINGA",
  "SETOR TRADICIONAL"     = "TAGUATINGA",
  "SETOR RESIDENCIAL LESTE"  = "TAGUATINGA",
  "SETOR RESIDENCIAL NORTE"  = "TAGUATINGA",
  "ZONA INDUSTRIAL"       = "TAGUATINGA",
  "SAMAMBAIA NORTE"       = "SAMAMBAIA",
  "SAMAMBAIA SUL"         = "SAMAMBAIA",
  "CIDADE ESTRUTURAL"     = "SCIA",
  "SETOR DE MANSOES PARK WAY" = "PARK WAY",
  "SETOR HABITACIONAL JARDIM BOTANICO" = "JARDIM BOTANICO",
  "ENGENHO DAS LAJES"     = "BRAZLANDIA",
  "VALE DO AMANHECER"     = "PLANALTINA",
  "ESTANCIA MESTRE D'ARMAS" = "PLANALTINA",
  "ARAPOANGA"             = "SANTA MARIA",
  "PONTE ALTA NORTE"      = "SANTA MARIA",
  "RESIDENCIAL SANTOS DUMONT" = "SANTA MARIA"
)
lv2[, ra_alias := fifelse(bairro_norm %in% names(alias), unname(alias[bairro_norm]), bairro_norm)]

# spatial join com a malha de subdistritos (resolve ambiguos e valida aliases)
malha <- st_read("data-raw/raw/ibge/DF_subdistritos_CD2022.gpkg", quiet = TRUE)
sub_col <- grep("NM_SUBDIST", names(malha), value = TRUE)
malha_tab <- st_set_geometry(malha, NULL)
malha_dt <- data.table(cd = malha_tab[[grep("CD_SUBDIST", names(malha_tab), value = TRUE)]],
                       ra_geo = norm_txt(malha_tab[[sub_col]]))
msg("malha subdistritos: %d poligonos", nrow(malha_dt))

pts <- lv2[!is.na(lat) & !is.na(lon)]
pts[, secao_idx := .I]
pts_sf <- st_as_sf(pts, coords = c("lon", "lat"), crs = 4674) |> st_transform(st_crs(malha))
ji <- st_join(pts_sf["secao_idx"], malha)
ji_dt <- data.table(secao_idx = ji$secao_idx, ra_geo = norm_txt(ji[[sub_col]]))
pts[, ra_geo := ji_dt[match(secao_idx, secao_idx)]$ra_geo]
lv2[, ra_geo := NA_character_]
lv2[pts$secao_idx, ra_geo := pts$ra_geo]

lv2[, ra_ibge := fifelse(!is.na(ra_geo) & ra_geo %in% pop$ra_ibge, ra_geo, ra_alias)]
lv2[, ra_metodo := fifelse(!is.na(ra_geo) & ra_geo %in% pop$ra_ibge, "geo", fifelse(ra_alias %in% pop$ra_ibge, "alias", NA_character_))]
ok <- lv2$ra_ibge %in% pop$ra_ibge
msg("match secao -> RA: %d/%d (%.1f%%)", sum(ok), nrow(lv2), 100 * mean(ok))
ambos <- lv2[!is.na(ra_geo) & ra_alias %in% pop$ra_ibge]
msg("concordancia alias x spatial: %.1f%% (%d secoes)",
    100 * mean(ambos$ra_alias == ambos$ra_geo, na.rm = TRUE), nrow(ambos))
sem <- lv2[!ok, .(n = .N, eleitores = sum(eleitores_secao)), by = bairro_norm][order(-n)]
if (nrow(sem)) { msg("sem RA (%d bairros):", nrow(sem)); print(utils::head(sem, 10)) }

lv2 <- merge(lv2, pop[, .(cd_subdist, ra_ibge, ra_nome)], by = "ra_ibge", all.x = TRUE)
setorder(lv2, zona, secao)
fwrite(lv2, file.path(OUT, "locais_votacao_ra_df.csv"))
msg("locais_votacao_ra_df.csv: %d secoes | eleitores: %s",
    nrow(lv2), format(sum(lv2$eleitores_secao, na.rm = TRUE), big.mark = ","))

# 3. Perfil do eleitorado por secao -> RA --------------------------------

sel <- c("NR_ZONA", "NR_SECAO", "DS_GENERO", "DS_FAIXA_ETARIA",
         "DS_GRAU_ESCOLARIDADE", "DS_RACA_COR", "QT_ELEITORES")
pe <- rd("perfil_eleitor_secao_2026_DF.csv", select = sel)
msg("perfil_eleitor_secao: %d linhas | eleitores: %s",
    nrow(pe), format(sum(pe$QT_ELEITORES), big.mark = ","))

pe[, fx := fcase(
  DS_FAIXA_ETARIA %in% c("16 anos","17 anos","18 anos","19 anos","20 anos","21 a 24 anos"), "16-24",
  grepl("^(25 a 29|30 a 34|35 a 39|40 a 44)", DS_FAIXA_ETARIA), "25-44",
  grepl("^(45 a 49|50 a 54|55 a 59)", DS_FAIXA_ETARIA), "45-59",
  grepl("^(60 a 64|65 a 69)", DS_FAIXA_ETARIA), "60-69",
  grepl("^(70|75|80|85|90|95|100)", DS_FAIXA_ETARIA), "70+",
  default = NA)]
if (anyNA(pe$fx)) msg("ATENCAO: faixas nao mapeadas: %s",
                      paste(unique(pe[is.na(fx)]$DS_FAIXA_ETARIA), collapse = ", "))

pe[, esc := fcase(
  DS_GRAU_ESCOLARIDADE == "SUPERIOR COMPLETO", "superior",
  DS_GRAU_ESCOLARIDADE %in% c("SUPERIOR INCOMPLETO","ENSINO MEDIO COMPLETO","ENSINO MEDIO INCOMPLETO"), "medio",
  grepl("FUNDAMENTAL", DS_GRAU_ESCOLARIDADE), "fundamental",
  DS_GRAU_ESCOLARIDADE %in% c("ANALFABETO","LE E ESCREVE"), "analf_ou_le",
  default = "nao_informado")]

agg_secao <- function(.dt, col, prefixo) {
  d <- dcast(.dt[, .(n = sum(QT_ELEITORES)),
                 by = .(zona = NR_ZONA, secao = NR_SECAO, cat = get(col))],
             zona + secao ~ paste0(prefixo, cat), value.var = "n", fill = 0)
  d
}
sec <- pe[, .(eleitores = sum(QT_ELEITORES)), by = .(zona = NR_ZONA, secao = NR_SECAO)]
sec <- merge(sec, agg_secao(pe, "DS_GENERO", "gen_"), by = c("zona","secao"), all.x = TRUE)
sec <- merge(sec, agg_secao(pe, "fx", "fx_"),        by = c("zona","secao"), all.x = TRUE)
sec <- merge(sec, agg_secao(pe, "esc", "esc_"),      by = c("zona","secao"), all.x = TRUE)
rc <- agg_secao(pe, "DS_RACA_COR", "cor_")
rcp <- grep("cor_(PRETA|PARDA)", names(rc), value = TRUE)
if (length(rcp)) sec <- merge(sec, rc[, c("zona","secao", rcp, rcp), with = FALSE], by = c("zona","secao"), all.x = TRUE)

sec_ra <- merge(sec, lv2[, .(zona, secao, ra_ibge, ra_nome)], by = c("zona","secao"), all.x = TRUE)
msg("secoes perfil: %d | sem RA: %d", nrow(sec_ra), sum(is.na(sec_ra$ra_ibge)))
numcols <- setdiff(names(sec_ra), c("ra_ibge","ra_nome"))
sec_ra[, (numcols) := lapply(.SD, function(x) { x[is.na(x)] <- 0; x }), .SDcols = numcols]

elei <- sec_ra[, lapply(.SD, sum), by = .(ra_ibge, ra_nome), .SDcols = numcols]
preta_parda <- rowSums(as.matrix(elei[, ..rcp]))
elei[, pct_fem := round(100 * gen_FEMININO / eleitores, 1)]
elei[, pct_16_24 := round(100 * `fx_16-24` / eleitores, 1)]
elei[, pct_25_44 := round(100 * `fx_25-44` / eleitores, 1)]
elei[, pct_45_59 := round(100 * `fx_45-59` / eleitores, 1)]
elei[, pct_60_mais := round(100 * (`fx_60-69` + `fx_70+`) / eleitores, 1)]
elei[, pct_superior := round(100 * esc_superior / eleitores, 1)]
elei[, pct_medio := round(100 * esc_medio / eleitores, 1)]
elei[, pct_fundamental := round(100 * esc_fundamental / eleitores, 1)]
elei[, pct_analf_ou_le := round(100 * esc_analf_ou_le / eleitores, 1)]
elei[, pct_preta_parda_eleit := round(100 * preta_parda / eleitores, 1)]
keep <- c("ra_ibge","ra_nome","eleitores","pct_fem","pct_16_24","pct_25_44","pct_45_59",
          "pct_60_mais","pct_superior","pct_medio","pct_fundamental","pct_analf_ou_le",
          "pct_preta_parda_eleit")
elei <- elei[, ..keep]
setorder(elei, -eleitores)
fwrite(elei, file.path(OUT, "eleitorado_ra_df.csv"))
msg("eleitorado_ra_df.csv: %d RAs | eleitores: %s",
    nrow(elei), format(sum(elei$eleitores), big.mark = ","))

# 4. Consolidado: populacao x eleitorado por RA ---------------------------

con <- merge(pop, elei[, .(ra_ibge, eleitores, pct_fem_eleit = pct_fem,
                           pct_16_24_e = pct_16_24, pct_superior_e = pct_superior,
                           pct_preta_parda_e = pct_preta_parda_eleit)],
             by = "ra_ibge", all = TRUE)
con[, eleitores_por_hab := round(eleitores / populacao, 3)]
fwrite(con, file.path(OUT, "perfil_ra_df.csv"))
msg("perfil_ra_df.csv: %d RAs", nrow(con))
msg("FIM OK")
