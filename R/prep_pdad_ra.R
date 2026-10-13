# Pipeline PDAD-A 2024 (T7) ------------------------------------------------------
# Microdados da PDAD-A 2024 (IPEDF) via pacote pdadr (DistintiveLab/pdadr).
# Agrega indicadores temáticos por RA do DF — pesos peso_dom/peso_mor, códigos
# reservados 77777/88888/99999 tratados como NA — e grava:
#   painel/data_virada/pdad_ra.csv
# Chave `ra` = nome uppercase sem acento (mesma de virada_ra.csv/geojson).
# Linha ra == "DF" guarda as referências do Distrito Federal para comparação.
# Uso: Rscript R/prep_pdad_ra.R

library(pdadr)
library(dplyr)

SAIDA <- "painel/data_virada/pdad_ra.csv"

normalizar_ra <- function(x) {
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- toupper(trimws(gsub("\\s+", " ", x)))
  x
}

# proporção ponderada de `flag` (logical; NA = fora do denominador) por RA, wide
prop_wide <- function(dados, flag, peso, nome) {
  dados$.flag <- flag
  out <- pdadr::estimar(dados, ".flag", tipo = "proporcao", por = "ra", peso = peso)
  names(out)[names(out) == "estimativa"] <- nome
  dplyr::select(out, "ra", dplyr::all_of(nome))
}

# valor de referência do DF inteiro (proporção ponderada)
prop_df <- function(dados, flag, peso) {
  dados$.flag <- flag
  unlist(pdadr::estimar(dados, ".flag", tipo = "proporcao", por = NULL, peso = peso)["estimativa"])
}

rodar <- function() {
  loc <- pdad_localidades |>
    dplyr::filter(.data$uf == "DF", !is.na(.data$cod_ibge_subdistrito)) |>
    dplyr::mutate(ra = normalizar_ra(.data$nome_ibge),
      valor_join = as.numeric(.data$valor))

  ras_painel <- readr::read_csv("painel/data_virada/virada_ra.csv", progress = FALSE,
    col_types = readr::cols(ra = readr::col_character()))$ra
  stopifnot(setequal(ras_painel, loc$ra))

  dom <- get_pdad("domicilios") |>
    pdadr::limpar_reservados() |>
    dplyr::filter(.data$localidade %in% loc$valor_join) |>
    dplyr::left_join(dplyr::select(loc, valor_join, ra), by = c("localidade" = "valor_join"))
  mor <- get_pdad("moradores") |>
    pdadr::limpar_reservados() |>
    dplyr::filter(.data$localidade %in% loc$valor_join) |>
    dplyr::left_join(dplyr::select(loc, valor_join, ra), by = c("localidade" = "valor_join"))

  # domicílios -----------------------------------------------------------------
  ind_dom <- dplyr::tibble(ra = loc$ra, n_dom = as.integer(table(factor(dom$ra, levels = loc$ra)))) |>
    dplyr::full_join(prop_wide(dom, dom$D15 == 1, "peso_dom", "pct_beneficio"), by = "ra") |>
    dplyr::full_join(prop_wide(dom, !is.na(dom$D15) & dom$D15 == 1 & dom$D16_1 == 1,
      "peso_dom", "pct_trans_renda"), by = "ra") |>
    dplyr::full_join(prop_wide(dom, dom$B06 == 2, "peso_dom", "pct_sem_escritura"), by = "ra") |>
    dplyr::full_join(prop_wide(dom, dom$B18_2 == 1, "peso_dom", "pct_esgoto_ceu"), by = "ra") |>
    dplyr::full_join(prop_wide(dom, dom$C05 == 3, "peso_dom", "pct_sem_internet"), by = "ra") |>
    dplyr::full_join(prop_wide(dom, !is.na(dom$B05), "peso_dom", "pct_alugado"), by = "ra")

  renda <- dom |>
    dplyr::filter(!is.na(.data$renda_domiciliar_pc_r)) |>
    pdadr::estimar("renda_domiciliar_pc_r", tipo = "media", por = "ra", peso = "peso_dom") |>
    dplyr::rename(renda_pc = estimativa) |> dplyr::select(-n)
  aluguel <- dom |>
    dplyr::filter(!is.na(.data$B05), .data$B05 > 0) |>
    pdadr::estimar("B05", tipo = "media", por = "ra", peso = "peso_dom") |>
    dplyr::rename(aluguel_medio = estimativa) |> dplyr::select(-n)

  # moradores ocupados -----------------------------------------------------------
  ocup <- mor |> dplyr::filter(.data$I04 == 1)
  empregados <- ocup |> dplyr::filter(.data$I13 %in% c(3, 4, 5, 6))

  ind_mor <- dplyr::tibble(ra = loc$ra, n_mor = as.integer(table(factor(ocup$ra, levels = loc$ra)))) |>
    dplyr::full_join(prop_wide(ocup, ocup$I09_1 == 1, "peso_mor", "pct_onibus"), by = "ra") |>
    dplyr::full_join(prop_wide(ocup, ocup$I10 %in% 4:9, "peso_mor", "pct_45min"), by = "ra") |>
    dplyr::full_join(prop_wide(ocup, ocup$I13 == 7, "peso_mor", "pct_conta_propria"), by = "ra") |>
    dplyr::full_join(prop_wide(empregados, empregados$I18 == 2, "peso_mor", "pct_sem_carteira"), by = "ra")

  pdad <- ind_dom |>
    dplyr::full_join(renda, by = "ra") |>
    dplyr::full_join(aluguel, by = "ra") |>
    dplyr::full_join(ind_mor, by = "ra") |>
    dplyr::left_join(dplyr::select(loc, ra, cd_subdist = cod_ibge_subdistrito), by = "ra")

  # referência DF + portões territoriais (tema sugerido na ficha) -----------------
  df_ref <- dplyr::tibble(
    pct_onibus = prop_df(ocup, ocup$I09_1 == 1, "peso_mor"),
    pct_trans_renda = prop_df(dom, !is.na(dom$D15) & dom$D15 == 1 & dom$D16_1 == 1, "peso_dom"),
    pct_sem_escritura = prop_df(dom, dom$B06 == 2, "peso_dom"),
    pct_esgoto_ceu = prop_df(dom, dom$B18_2 == 1, "peso_dom"),
    pct_sem_internet = prop_df(dom, dom$C05 == 3, "peso_dom"),
    pct_sem_carteira = prop_df(empregados, empregados$I18 == 2, "peso_mor"),
    renda_pc = {
      ocup_dom <- dom |> dplyr::filter(!is.na(.data$renda_domiciliar_pc_r))
      unlist(pdadr::estimar(ocup_dom, "renda_domiciliar_pc_r", tipo = "media", por = NULL, peso = "peso_dom")["estimativa"])
    }
  )

  gatilhos <- function(linha) {
    d <- 0.04
    fired <- character()
    if (!is.na(linha$pct_onibus) && !is.na(linha$renda_pc) &&
        linha$pct_onibus - df_ref$pct_onibus >= d && linha$renda_pc <= 0.9 * df_ref$renda_pc)
      fired <- c(fired, "custo do ônibus")
    if (!is.na(linha$pct_trans_renda) && linha$pct_trans_renda - df_ref$pct_trans_renda >= d)
      fired <- c(fired, "transferência de renda")
    if ((!is.na(linha$pct_sem_escritura) && linha$pct_sem_escritura - df_ref$pct_sem_escritura >= d) ||
        (!is.na(linha$pct_esgoto_ceu) && linha$pct_esgoto_ceu - df_ref$pct_esgoto_ceu >= d))
      fired <- c(fired, "moradia e regularização")
    if (!is.na(linha$pct_sem_internet) && linha$pct_sem_internet - df_ref$pct_sem_internet >= d)
      fired <- c(fired, "internet e conectividade")
    if ((!is.na(linha$pct_sem_carteira) && linha$pct_sem_carteira - df_ref$pct_sem_carteira >= d &&
        !is.na(linha$renda_pc) && linha$renda_pc <= df_ref$renda_pc) ||
        (!is.na(linha$pct_conta_propria) && linha$pct_conta_propria - mean(pdad$pct_conta_propria, na.rm = TRUE) >= 0.05 &&
          !is.na(linha$renda_pc) && linha$renda_pc <= df_ref$renda_pc))
      fired <- c(fired, "trabalho e carteira")
    if (!length(fired)) fired <- "sem gatilho dominante (perfil próximo à média do DF)"
    fired
  }

  temas <- lapply(seq_len(nrow(pdad)), function(i) gatilhos(pdad[i, ]))
  pdad$tema_sugerido <- vapply(temas, `[`, character(1), 1)
  pdad$tema_todos <- vapply(temas, function(x) paste(x, collapse = " | "), character(1))

  linha_df <- dplyr::bind_cols(dplyr::tibble(
    ra = "DF", cd_subdist = NA_character_,
    pct_beneficio = prop_df(dom, dom$D15 == 1, "peso_dom"),
    n_dom = nrow(dom),
    pct_alugado = prop_df(dom, !is.na(dom$B05), "peso_dom"),
    n_mor = nrow(ocup)
  ), df_ref, dplyr::tibble(tema_sugerido = NA_character_, tema_todos = NA_character_))

  saida <- dplyr::bind_rows(
    dplyr::select(pdad, ra, cd_subdist, n_dom, n_mor, renda_pc, aluguel_medio,
      pct_beneficio, pct_trans_renda, pct_alugado, pct_sem_escritura, pct_esgoto_ceu,
      pct_sem_internet, pct_onibus, pct_45min, pct_conta_propria, pct_sem_carteira,
      tema_sugerido, tema_todos),
    dplyr::select(linha_df, dplyr::any_of(names(pdad)))
  )
  readr::write_csv(saida, SAIDA)
  cat("OK:", nrow(saida), "linhas ->", SAIDA, "\n")
  print(saida |> dplyr::select(ra, renda_pc, pct_trans_renda, pct_onibus, tema_sugerido), n = 40)
}

rodar()
