#' panel_virada UI Function
#'
#' @description Aba "Virada 2ºT": mapa dos locais de votação do DF (bolhas
#'   por local ou coroplético por região administrativa), ranking de
#'   prioridade pelo IPV e ficha por local com roteiro e mensagem pronta
#'   para WhatsApp. Lê CSVs autocontidos de data_virada/ (gerados por
#'   R/prep_virada_2t.R e R/prep_pdad_ra.R no repositório), sem depender do
#'   banco de dados do painel.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_panel_virada_ui <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(class = "painel-toolbar painel-virada-toolbar", role = "search",
      `aria-label` = "Seleção da virada",
      tags$div(class = "form-group",
        tags$label(`for` = ns("corrida"), "Corrida"),
        shiny::selectInput(ns("corrida"), NULL, width = "auto",
          choices = c("Governo do DF (Grass x Celina)" = "gov",
                      "Presidência (Lula x Flávio)" = "pres"),
          selected = "gov")),
      tags$div(class = "form-group",
        tags$label(`for` = ns("modo"), "Mapa"),
        shiny::selectInput(ns("modo"), NULL, width = "auto",
          choices = c("Locais de votação" = "locais",
                      "Regiões administrativas" = "ra"),
          selected = "locais")),
      tags$div(class = "form-group",
        tags$label(`for` = ns("metrica"), "Cor da RA"),
        shiny::selectInput(ns("metrica"), NULL, width = "auto",
          choices = c("IPV (potencial de virada)" = "ipv",
                      "Votos para vencer" = "vpc",
                      "Margem do 1ºT (% válidos)" = "margem",
                      "Abstenção (% aptos)" = "abstencao",
                      "Lulismo não transferido (pp)" = "gap",
                      "Mais votado" = "mais_votado"),
          selected = "ipv")),
      tags$div(class = "form-group",
        tags$label(`for` = ns("ordenar"), "Ordenar ranking por"),
        shiny::selectInput(ns("ordenar"), NULL, width = "auto",
          choices = c("IPV" = "ipv", "Votos para vencer" = "vpc",
                      "Teto de virada" = "teto", "Ganho esperado (abstenção)" = "ganho"),
          selected = "ipv")),
      tags$div(class = "form-group",
        tags$label(`for` = ns("cenario"), "Cenário 2ºT"),
        shiny::selectInput(ns("cenario"), NULL, width = "auto",
          choices = c("p = 0,5 (neutro)" = "p50",
                      "p = 0,6 (terceiros p/ nós)" = "p60"),
          selected = "p50")),
      tags$div(class = "form-group",
        tags$label(`for` = ns("min_aptos"), "Mín. aptos"),
        shiny::numericInput(ns("min_aptos"), NULL, value = 200,
          min = 0, max = 2000, step = 50, width = "110px")),
      tags$button(type = "button", class = "btn btn-default btn-sm painel-virada-tour-btn",
        title = "Percorrer os blocos desta aba com descrições curtas",
        `aria-label` = "Abrir o tutorial visual desta aba", "Tutorial")),
    shiny::uiOutput(ns("cabecalho")),
    tags$div(class = "painel-regiao-grade painel-virada-grade",
      tags$div(class = "painel-card painel-virada-card-mapa",
        tags$h3("Mapa da virada"),
        leaflet::leafletOutput(ns("mapa"), height = "calc(100vh - 460px)"),
        tags$p(class = "painel-nota", shiny::textOutput(ns("status_mapa")))),
      tags$div(class = "painel-card painel-virada-card-ranking",
        tags$h3("Ranking de prioridade"),
        DT::DTOutput(ns("ranking")),
        tags$div(class = "painel-resumo-acoes",
          shiny::downloadButton(ns("xlsx"), "Baixar planilha (xlsx)",
            class = "btn-sm")),
        tags$p(class = "painel-nota",
          "Clique numa linha para abrir a ficha do local e destacá-lo no",
          "mapa. IPV = índice de potencial de virada (0 a 1; nível 1 a 7)."))),
    shiny::uiOutput(ns("ficha"), class = "painel-virada-ficha-slot"),
    tags$div(class = "painel-card painel-virada-metodo",
      tags$h3("Como ler este painel (#metodo)"),
      tags$details(
        tags$summary("Fórmulas, cenários e limitações"),
        tags$div(class = "painel-nota",
          tags$p(tags$strong("Unidade: "), "local de votação (urnas somadas",
            " no mesmo ponto; coordenada a ~11 m). Síntese por região",
            " administrativa (RA). O voto é no local de votação, não na",
            " residência de quem vota."),
          tags$p(tags$strong("V1 votos para vencer: "),
            "margem = votos do oponente menos os nossos; teto de virada =",
            " brancos + nulos + abstenções + terceiros; déficit no 2º turno",
            " = margem - (2p-1) x terceiros, com p = fração de terceiros",
            " que nos apoia (cenários 0,5 e 0,6); votos para vencer =",
            " max(0, déficit + 1). Classes: à frente / virável com a",
            " abstenção (votos para vencer <= abstenção) / abstenção",
            " insuficiente."),
          tags$p(tags$strong("V2 lulismo não transferido: "),
            "gap = % Lula (presidência) - % Grass (governo) sobre válidos",
            " nominais; votos a transferir = max(0, Lula - Grass) no local.",
            " No 1ºT do DF, Lula superou Grass em todos os 622 locais."),
          tags$p(tags$strong("V4 abstenção: "),
            "excesso = abstenção do local - taxa DF x aptos (flag acima de",
            " 2 desvios); saldo = 2s - 1, com s = nossa fração do duelo;",
            " ganho esperado = 10% da abstenção x saldo (sinal negativo",
            " indica território em que mobilizar abstenção favorece o",
            " adversário)."),
          tags$p(tags$strong("V5 terreno perdido: "),
            "desloc = % Lula 2026 (1ºT) - % Lula 2022 (2ºT) nos locais",
            " pareados (94%); terreno perdido = queda além da queda estrutural",
            " do DF (-2,9 pp) x válidos de 2022."),
          tags$p(tags$strong("IPV: "),
            "posto percentual (0-1) com pesos 0,55 potencial (votos para",
            " vencer + ganho esperado + terreno perdido), 0,15 aderência",
            " (eleitoras jovens + perfil da RA), 0,15 segurança (saldo",
            " abstencionista + estabilidade 2022-2026) e 0,15 escala",
            " (log dos aptos); 7 níveis por quantil, restrito a locais com",
            " 200+ aptos."),
          tags$p(tags$strong("Limitações: "),
            "base nominal por seção (votacao_secao do TSE): 10.299 votos",
            " de governador anulados sub judice aparecem como nominais;",
            " aptos por seção vêm do cadastro e superam os oficiais em",
            "~9 mil (abstenção por local ligeiramente subestimada);",
            " pareamento 2022 cobre 93,6% dos votos; leituras ecológicas",
            " (perfil do local, não do eleitor); locais com menos de 200",
            " aptos ficam fora do ranking."),
          tags$p(tags$strong("PDAD-A 2024 (IPEDF): "),
            "o perfil sociodemográfico da RA na ficha vem da PDAD-A 2024",
            " (pesquisa amostral com pesos domiciliar e de moradores, via",
            " pacote pdadr). O tema de conversa é sugerido por gatilhos",
            " territoriais, ex.: custo do ônibus onde a % de usuários é",
            " alta e a renda per capita é baixa. Descreve a RA do local,",
            " não o eleitor do local."))))
  )
}

# rotulos e formatos -----------------------------------------------------------

virada_classe_rotulo <- c(
  "a frente" = "À frente",
  "viravel com a abstencao" = "Virável com a abstenção",
  "abstencao insuficiente" = "Abstenção insuficiente")

virada_classe_cor <- c(
  "a frente" = "#2e7d32",
  "viravel com a abstencao" = "#f9a825",
  "abstencao insuficiente" = "#78909c")

virada_int <- function(x) {
  x <- round(x)
  formatC(x, big.mark = ".", decimal.mark = ",", format = "d")
}

virada_pct <- function(x, digito = 1) {
  ifelse(is.na(x), "sem dado",
    sprintf(paste0("%.", digito, "f%%"), 100 * x))
}

virada_pp <- function(x, digito = 1) {
  ifelse(is.na(x), "sem dado",
    sprintf(paste0("%+.", digito, "f pp"), 100 * x))
}

virada_real <- function(x) {
  ifelse(is.na(x), "s/d",
    paste0("R$ ", formatC(round(x), big.mark = ".", decimal.mark = ",", format = "d")))
}

virada_chip <- function(rotulo, valor, nota = NULL) {
  tags$div(class = "painel-resumo-chip",
    tags$div(class = "painel-resumo-chip-rotulo", rotulo),
    tags$div(class = "painel-resumo-chip-valor", valor),
    if (!is.null(nota)) tags$div(class = "painel-resumo-chip-delta", nota))
}

#' panel_virada Server Functions
#'
#' @noRd
mod_panel_virada_server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    virada_dir <- local({
      for (d in c("data_virada", file.path("painel", "data_virada")))
        if (dir.exists(d)) break
      d
    })
    dados <- local({
      arq <- function(f) file.path(virada_dir, f)
      if (!file.exists(arq("virada_local.csv"))) return(NULL)
      lista <- list(
        local = readr::read_csv(arq("virada_local.csv"),
          show_col_types = FALSE, progress = FALSE),
        prioridade = readr::read_csv(arq("virada_prioridade.csv"),
          show_col_types = FALSE, progress = FALSE))
      if (file.exists(arq("virada_ra.geojson")))
        lista$geo <- sf::st_read(arq("virada_ra.geojson"), quiet = TRUE)
      if (file.exists(arq("pdad_ra.csv")))
        lista$pdad <- readr::read_csv(arq("pdad_ra.csv"),
          show_col_types = FALSE, progress = FALSE)
      lista
    })
    tem_dados <- shiny::reactive(!is.null(dados))

    pref <- shiny::reactive(if (identical(input$corrida, "pres")) "pres_" else "gov_")
    cen <- shiny::reactive(if (identical(input$cenario, "p60")) "p60" else "p50")
    col_vpc <- shiny::reactive(paste0(pref(), "votos_para_vencer_", cen()))
    col_teto <- shiny::reactive(paste0(pref(), "teto_virada"))
    col_ganho <- shiny::reactive(paste0(pref(), "ganho_esperado"))
    col_classe <- shiny::reactive(paste0(pref(), "classe"))
    col_ipv <- shiny::reactive(paste0("ipv_", sub("_$", "", pref())))
    col_nivel <- shiny::reactive(paste0("ipv_nivel_", sub("_$", "", pref())))

    loc_filtrados <- shiny::reactive({
      shiny::req(tem_dados())
      minimo <- suppressWarnings(as.numeric(input$min_aptos)[1])
      if (is.na(minimo)) minimo <- 0
      dados$local |> dplyr::filter(aptos >= minimo)
    })

    ra_tabela <- shiny::reactive({
      shiny::req(tem_dados())
      dados$local |>
        dplyr::group_by(ra, ra_nome) |>
        dplyr::summarise(
          n_locais = dplyr::n(),
          aptos = sum(aptos),
          lula = sum(p_lula), flavio = sum(p_flavio),
          grass = sum(g_grass), celina = sum(g_celina),
          pct_lula = sum(p_lula) / sum(validos_pres),
          pct_flavio = sum(p_flavio) / sum(validos_pres),
          pct_grass = sum(g_grass) / sum(validos_gov),
          pct_celina = sum(g_celina) / sum(validos_gov),
          pct_abstencao_pres = sum(pres_abstencao) / sum(aptos),
          pct_abstencao_gov = sum(gov_abstencao) / sum(aptos),
          vpc_pres = sum(pres_votos_para_vencer_p50),
          vpc_gov = sum(gov_votos_para_vencer_p50),
          gap_esferas = sum(p_lula) / sum(validos_pres) -
            sum(g_grass) / sum(validos_gov),
          ipv_pres = weighted.mean(ipv_pres, aptos * elegivel_200, na.rm = TRUE),
          ipv_gov = weighted.mean(ipv_gov, aptos * elegivel_200, na.rm = TRUE),
          .groups = "drop")
    })

    # cabeçalho DF -------------------------------------------------------------
    output$cabecalho <- shiny::renderUI({
      shiny::validate(shiny::need(tem_dados(),
        "Dados da virada não encontrados: rode Rscript R/prep_virada_2t.R t2 t3 t4 t5 no repositório para gerar data_virada/."))
      d <- loc_filtrados()
      pres <- identical(pref(), "pres_")
      margem_df <- if (pres) sum(dados$local$p_flavio) - sum(dados$local$p_lula) else
        sum(dados$local$g_celina) - sum(dados$local$g_grass)
      vpc_df <- sum(d[[col_vpc()]], na.rm = TRUE)
      viraveis <- sum(d[[col_classe()]] == "viravel com a abstencao")
      a_frente <- sum(d[[col_classe()]] == "a frente")
      tags$div(class = "painel-card",
        tags$h3(paste("Virada no 2º turno",
          if (pres) "presidência no DF" else "governo do DF")),
        tags$div(class = "painel-resumo-grade",
          virada_chip(paste("Margem do 1ºT (",
            if (pres) "Flávio - Lula" else "Celina - Grass", ")"),
            virada_int(margem_df), "votos"),
          virada_chip(paste("Votos para vencer",
            if (identical(cen(), "p60")) "(p = 0,6)" else "(p = 0,5)"),
            virada_int(vpc_df), "soma dos locais"),
          virada_chip("Locais viráveis", paste0(viraveis, " de ", nrow(d)),
            paste0(a_frente, " à frente")),
          virada_chip("Lulismo não transferido",
            virada_int(sum(dados$local$votos_a_transferir)),
            "votos Lula sem Grass"),
          virada_chip("Abstenção DF (1ºT)",
            virada_pct(sum(d[[paste0(pref(), "abstencao")]]) / sum(d$aptos)),
            "sobre aptos do cadastro")))
    })

    # ranking ------------------------------------------------------------------
    ranking_df <- shiny::reactive({
      d <- loc_filtrados()
      ord <- input$ordenar
      col <- switch(ord,
        ipv = col_ipv(), vpc = col_vpc(), teto = col_teto(), ganho = col_ganho(),
        col_ipv())
      d |>
        dplyr::mutate(ordenacao = ifelse(is.na(.data[[col]]), -Inf, .data[[col]])) |>
        dplyr::arrange(desc(ordenacao)) |>
        dplyr::transmute(
          local_id,
          nome = tools::toTitleCase(tolower(nome)),
          ra_nome,
          aptos = virada_int(aptos),
          votos_para_vencer = virada_int(.data[[col_vpc()]]),
          teto_virada = virada_int(.data[[col_teto()]]),
          classe = unname(virada_classe_rotulo[.data[[col_classe()]]]),
          ipv = ifelse(is.na(.data[[col_ipv()]]), "s/n",
            sprintf("%.2f", .data[[col_ipv()]])),
          nivel = ifelse(is.na(.data[[col_nivel()]]), "-",
            as.character(.data[[col_nivel()]])))
    })

    output$ranking <- DT::renderDT({
      shiny::req(tem_dados())
      DT::datatable(ranking_df(),
        selection = "single", rownames = FALSE, filter = "none",
        colnames = c("id", "Local", "RA", "Aptos", "Votos p/ vencer",
          "Teto de virada", "Situação", "IPV", "Nível"),
        options = list(pageLength = 10, lengthChange = FALSE,
          scrollX = TRUE, dom = "tp",
          language = list(url = "//cdn.datatables.net/plug-ins/1.13.7/i18n/pt-BR.json")),
        escape = TRUE)
    })

    # seleção ------------------------------------------------------------------
    sel_local <- shiny::reactiveVal(NA_integer_)

    shiny::observeEvent(input$ranking_rows_selected, {
      i <- input$ranking_rows_selected
      if (length(i) == 1 && !is.na(i)) {
        sel_local(ranking_df()$local_id[i])
      }
    })

    shiny::observeEvent(input$mapa_shape_click, {
      clique <- input$mapa_shape_click
      shiny::req(clique, clique$id)
      if (identical(input$modo, "ra")) {
        ra <- clique$id
        melhor <- loc_filtrados() |>
          dplyr::filter(ra == !!ra, !is.na(.data[[col_ipv()]])) |>
          dplyr::arrange(desc(.data[[col_ipv()]]))
        if (!nrow(melhor)) melhor <- loc_filtrados() |> dplyr::filter(ra == !!ra)
        if (nrow(melhor)) sel_local(melhor$local_id[1])
      } else {
        if (clique$id != "virada_sel")
          sel_local(suppressWarnings(as.numeric(clique$id)))
      }
    })

    local_sel <- shiny::reactive({
      shiny::req(tem_dados())
      if (is.na(sel_local())) return(NULL)
      dados$local |> dplyr::filter(local_id == sel_local())
    })

    # mapa ---------------------------------------------------------------------
    output$mapa <- leaflet::renderLeaflet({
      leaflet::leaflet() |>
        leaflet::setView(lng = -47.83, lat = -15.79, zoom = 10) |>
        leaflet::setMaxBounds(-48.35, -16.35, -47.25, -15.35) |>
        leaflet::addTiles(
          urlTemplate = if (!is.null(painel_carto_chave()))
            paste0("https://{s}.basemaps.cartocdn.com/rastertiles/voyager/",
                   "{z}/{x}/{y}.png?key=", painel_carto_chave()) else
            "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          attribution = if (!is.null(painel_carto_chave()))
            '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>, &copy; <a href="https://carto.com/attributions">CARTO</a>' else
            '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
          options = leaflet::providerTileOptions(subdomains = "abcd",
            maxZoom = 19))
    })

    shiny::observe({
      shiny::req(tem_dados(), input$modo)
      proxy <- leaflet::leafletProxy("mapa", session = session) |>
        leaflet::clearShapes() |> leaflet::clearControls()
      if (identical(input$modo, "ra")) {
        shiny::req(!is.null(dados$geo))
        rt <- ra_tabela()
        g <- dados$geo |> dplyr::inner_join(rt, by = "ra")
        metrica <- input$metrica
        if (identical(metrica, "mais_votado")) {
          g$vencedor <- ifelse(identical(pref(), "pres_"),
            ifelse(g$pct_lula >= g$pct_flavio, "Lula", "Flávio"),
            ifelse(g$pct_grass >= g$pct_celina, "Grass", "Celina"))
          pal <- leaflet::colorFactor(
            c(Lula = "#c8102e", Grass = "#c8102e",
              `Flávio` = "#12559c", Celina = "#12559c"),
            domain = g$vencedor, na.color = "transparent")
          rotulo <- "%s<br><b>%s</b> (%s)"
          textos <- sprintf(rotulo, g$ra_nome, g$vencedor,
            virada_pct(ifelse(g$vencedor %in% c("Lula", "Grass"),
              ifelse(g$vencedor == "Lula", g$pct_lula, g$pct_grass),
              ifelse(g$vencedor == "Flávio", g$pct_flavio, g$pct_celina))))
          proxy |> leaflet::addPolygons(data = g, layerId = ~ra,
            fillColor = ~pal(vencedor), fillOpacity = 0.65,
            weight = 1.2, color = "#444444", opacity = 0.8,
            highlight = leaflet::highlightOptions(weight = 2.5, color = "white",
              bringToFront = TRUE),
            popup = textos) |>
            leaflet::addLegend("bottomright",
              colors = c("#c8102e", "#12559c"),
              labels = c("Nosso (Lula / Grass)", "Oponente (Flávio / Celina)"),
              title = "Mais votado no 1ºT")
        } else {
          valores <- switch(metrica,
            ipv = g[[col_ipv()]],
            vpc = g[[paste0("vpc_", sub("_$", "", pref()))]],
            margem = -(if (identical(pref(), "pres_"))
              (g$pct_flavio - g$pct_lula) else (g$pct_celina - g$pct_grass)) * 100,
            abstencao = g[[paste0("pct_abstencao_", sub("_$", "", pref()))]] * 100,
            gap = g$gap_esferas * 100)
          titulo <- switch(metrica,
            ipv = "IPV (0 a 1)",
            vpc = "Votos para vencer (p = 0,5)",
            margem = "Nossa margem (% válidos)",
            abstencao = "Abstenção (% aptos)",
            gap = "Lulismo não transferido (pp)")
          fmt_val <- if (identical(metrica, "vpc")) virada_int(valores) else
            sprintf("%.1f", valores)
          textos <- sprintf("<b>%s</b><br>%s", g$ra_nome,
            ifelse(is.na(valores), "sem dado", fmt_val))
          pal <- painel_paleta(valores, escala = "minmax")
          proxy |> leaflet::addPolygons(data = g, layerId = ~ra,
            fillColor = ~pal(valores), fillOpacity = 0.7,
            weight = 1.2, color = "#444444", opacity = 0.8,
            highlight = leaflet::highlightOptions(weight = 2.5, color = "white",
              bringToFront = TRUE),
            popup = textos) |>
            leaflet::addLegend("bottomright",
              values = range(valores, na.rm = TRUE), pal = pal,
              opacity = 0.8, title = titulo,
              labFormat = function(type, cuts, ...) sprintf("%.1f", cuts))
        }
      } else {
        d <- loc_filtrados()
        teto <- d[[col_teto()]]
        raio <- 5 + 13 * sqrt(teto / max(teto, na.rm = TRUE))
        cores <- unname(virada_classe_cor[d[[col_classe()]]])
        textos <- sprintf(
          paste0("<b>%s</b> (%s)<br>Votos p/ vencer: <b>%s</b><br>",
            "Teto de virada: %s<br>Situação: %s<br>",
            "%% Lula %s | %% Grass %s<br>Aptos: %s"),
          tools::toTitleCase(tolower(d$nome)), d$ra_nome,
          virada_int(d[[col_vpc()]]), virada_int(teto),
          unname(virada_classe_rotulo[d[[col_classe()]]]),
          virada_pct(d$pct_lula), virada_pct(d$pct_grass),
          virada_int(d$aptos))
        proxy |>
          leaflet::addCircles(data = d, lng = ~lon, lat = ~lat,
            layerId = ~local_id, radius = raio, weight = 1,
            color = "#333333", fillColor = cores, fillOpacity = 0.6,
            popup = textos) |>
          leaflet::addLegend("bottomright",
            colors = unname(virada_classe_cor),
            labels = unname(virada_classe_rotulo),
            title = paste("Situação",
              if (identical(pref(), "pres_")) "presidência" else "governo",
              if (identical(cen(), "p60")) "(p = 0,6)" else "(p = 0,5)"))
      }
    })

    # destaque do local selecionado (anel, sem redesenhar as camadas) ----------
    shiny::observe({
      proxy <- leaflet::leafletProxy("mapa", session = session)
      proxy |> leaflet::removeShape("virada_sel")
      l <- local_sel()
      if (is.null(l) || nrow(l) == 0) return()
      proxy |> leaflet::addCircles(data = l, lng = ~lon, lat = ~lat,
        layerId = "virada_sel", radius = 120, weight = 3, color = "#111111",
        fill = FALSE)
    })

    output$status_mapa <- shiny::renderText({
      shiny::req(tem_dados())
      d <- loc_filtrados()
      if (identical(input$modo, "ra")) {
        sprintf("%d RAs | mapa coroplético; clique numa RA para abrir o melhor local dela.",
          nrow(ra_tabela()))
      } else {
        sprintf("%d locais com %s+ aptos (%d eleitores aptos); bolha = teto de virada, cor = situação no cenário %s.",
          nrow(d), format(input$min_aptos, big.mark = ".", decimal.mark = ","),
          sum(d$aptos), if (identical(cen(), "p60")) "p = 0,6" else "p = 0,5")
      }
    })

    # ficha do local -----------------------------------------------------------
    output$ficha <- shiny::renderUI({
      shiny::req(tem_dados())
      l <- local_sel()
      if (is.null(l) || nrow(l) == 0) {
        return(shiny::tags$p(class = "painel-nota",
          "Selecione um local no mapa ou no ranking para ver a ficha completa,",
          " com roteiro de campo e mensagem pronta para WhatsApp."))
      }
      l <- l[1, ]
      pdad <- if (!is.null(dados$pdad)) {
        p <- dados$pdad[dados$pdad$ra == l$ra & dados$pdad$ra != "DF", ,
          drop = FALSE]
        if (nrow(p)) p[1, ] else NULL
      }
      pdad_df <- if (!is.null(dados$pdad)) {
        p <- dados$pdad[dados$pdad$ra == "DF", , drop = FALSE]
        if (nrow(p)) p[1, ] else NULL
      }
      vpc_gov <- l[["gov_votos_para_vencer_p50"]]
      vpc_pres <- l[["pres_votos_para_vencer_p50"]]
      classe_gov <- unname(virada_classe_rotulo[l[["gov_classe"]]])
      classe_pres <- unname(virada_classe_rotulo[l[["pres_classe"]]])
      ganho_gov <- l[["gov_ganho_esperado"]]
      abst_gov <- l[["gov_abstencao"]]
      terceiros_gov <- l[["g_terceiros"]] + l[["g_brancos"]] + l[["g_nulos"]]
      transferir <- l[["votos_a_transferir"]]
      desloc <- l[["desloc_22_26"]]
      lula22 <- l[["pct_lula22_2t"]]
      nivel_gov <- l[["ipv_nivel_gov"]]
      ipv_gov <- l[["ipv_gov"]]
      nome <- tools::toTitleCase(tolower(l$nome))

      roteiro <- if (isTRUE(vpc_gov > 0) &&
        isTRUE(l[["gov_saldo_abstencionista"]] > 0)) {
        sprintf(paste("Local virável e com eleitorado favorável: prioridade",
          "alta. Mobilizar abstenção (%s aptos faltosos, ganho esperado de",
          "%s votos com 10%% de mobilização), converter lulistas-sem-Grass",
          "(%s) e priorizar eleitoras de 16 a 29 anos (%s no local)."),
          virada_int(abst_gov), virada_int(pmax(0, ganho_gov)),
          virada_int(transferir), virada_int(l[["eleitoras_16_29"]]))
      } else if (isTRUE(vpc_gov > 0)) {
        sprintf(paste("Local virável, mas com saldo abstencionista negativo:",
          "o eleitorado faltoso pende ao adversário. Começar pela conversa",
          "de persuasão (terceiros, brancos e nulos: %s) e pelo lulista",
          "que não votou Grass (%s) antes de mobilizar abstenção."),
          virada_int(terceiros_gov), virada_int(transferir))
      } else if (isTRUE(l[["gov_margem"]] < 0)) {
        "Local à frente no governo: proteger o comparecimento e monitorar a contagem; sem esforço de virada necessário."
      } else {
        sprintf(paste("Abstenção insuficiente para virar sozinha (%s faltosos",
          "contra %s votos necessários): combinar conversão de terceiros",
          "(%s) com a mobilização de faltosos."),
          virada_int(abst_gov), virada_int(vpc_gov),
          virada_int(terceiros_gov))
      }

      if (!is.null(pdad) && !is.na(pdad$tema_sugerido) &&
        !grepl("^sem gatilho", pdad$tema_sugerido)) {
        detalhe <- switch(pdad$tema_sugerido,
          "custo do ônibus" = sprintf(
            "%s dos ocupados vão de ônibus ao trabalho e a renda per capita média da RA é %s",
            virada_pct(pdad$pct_onibus), virada_real(pdad$renda_pc)),
          "transferência de renda" = sprintf(
            "%s dos domicílios da RA recebem transferência de renda",
            virada_pct(pdad$pct_trans_renda)),
          "moradia e regularização" = sprintf(
            "%s dos domicílios sem escritura definitiva",
            virada_pct(pdad$pct_sem_escritura)),
          "internet e conectividade" = sprintf(
            "%s dos domicílios sem internet em casa",
            virada_pct(pdad$pct_sem_internet)),
          "trabalho e carteira" = sprintf(
            "%s dos empregados sem carteira assinada",
            virada_pct(pdad$pct_sem_carteira)),
          "")
        roteiro <- paste0(roteiro, sprintf(
          " Ângulo PDAD da %s: %s - %s.",
          l$ra_nome, pdad$tema_sugerido, detalhe))
      }

      mensagem <- sprintf(paste0(
        "VIRADA 2º TURNO DF\n%s (%s)\n",
        "Votos para vencer no governo: %s (%s)\n",
        "Presidência: %s (%s)\n",
        "Lula 1ºT %s x Grass %s: %s pp de lulismo não transferido ",
        "(%s eleitores a converter)\n",
        "Abstenção no local: %s (saldo %s)\n",
        "%s\n",
        "IPV %s/7 - prioridade %s de 7"),
        nome, l$ra_nome,
        virada_int(vpc_gov), classe_gov,
        virada_int(vpc_pres), classe_pres,
        virada_pct(l$pct_lula), virada_pct(l$pct_grass),
        virada_pp(l$gap_esferas),
        virada_int(transferir),
        virada_int(abst_gov),
        ifelse(is.na(l[["gov_saldo_abstencionista"]]), "s/d",
          sprintf("%+.2f", l[["gov_saldo_abstencionista"]])),
        roteiro,
        ifelse(is.na(nivel_gov), "s/n", as.character(nivel_gov)),
        ifelse(is.na(nivel_gov), "s/n", as.character(nivel_gov)))

      tags$div(class = "painel-card painel-virada-ficha",
        tags$h3(paste("Ficha:", nome)),
        tags$p(class = "painel-nota", sprintf(
          "%s | %d seções (%d votantes) | %s aptos | zona(s) %s",
          l$ra_nome, l$n_secoes, l$n_secoes_votantes,
          virada_int(l$aptos), l$zonas)),
        tags$div(class = "painel-resumo-grade",
          virada_chip("Votos p/ vencer (governo)", virada_int(vpc_gov),
            classe_gov),
          virada_chip("Votos p/ vencer (presidência)", virada_int(vpc_pres),
            classe_pres),
          virada_chip("Lulismo não transferido",
            virada_pp(l$gap_esferas), sprintf("%s votos",
              virada_int(transferir))),
          virada_chip("Lula 2022 (2ºT) x 2026 (1ºT)",
            ifelse(is.na(lula22), "sem par 2022",
              paste0(virada_pct(lula22), " -> ", virada_pct(l$pct_lula))),
            ifelse(is.na(desloc), "local sem pareamento 2022",
              virada_pp(desloc))),
          virada_chip("Abstenção (governo)",
            virada_pct(l[["gov_taxa_abstencao"]]),
            sprintf("%s faltosos | ganho esperado %s",
              virada_int(abst_gov), virada_int(pmax(0, ganho_gov)))),
          virada_chip("IPV governo",
            ifelse(is.na(ipv_gov), "s/n",
              sprintf("%.2f (nível %s/7)", ipv_gov,
                ifelse(is.na(nivel_gov), "s/n", nivel_gov))))),
        tags$h4("Quem procurar neste local"),
        tags$div(class = "painel-resumo-grade",
          virada_chip("Faltosos (governo)", virada_int(abst_gov),
            "comparecimento do local"),
          virada_chip("Terceiros + brancos + nulos", virada_int(terceiros_gov),
            "governo"),
          virada_chip("Lulistas sem Grass", virada_int(transferir),
            "votaram Lula, não Grass"),
          virada_chip("Eleitoras", virada_int(l[["eleitoras"]]),
            sprintf("%s de 16 a 29 anos", virada_int(l[["eleitoras_16_29"]])))),
        if (!is.null(pdad))
          tags$div(class = "painel-virada-pdad",
            tags$h4("Perfil PDAD-A 2024 da RA"),
            tags$div(class = "painel-resumo-grade",
              virada_chip("Tema de conversa sugerido", pdad$tema_sugerido,
                if (is.null(pdad_df)) NULL else sprintf(
                  "renda per capita do DF: %s",
                  virada_real(pdad_df$renda_pc))),
              virada_chip("Renda domiciliar per capita",
                virada_real(pdad$renda_pc),
                if (is.null(pdad_df)) NULL else sprintf("DF: %s",
                  virada_real(pdad_df$renda_pc))),
              virada_chip("Domicílios com transferência de renda",
                virada_pct(pdad$pct_trans_renda),
                if (is.null(pdad_df)) NULL else sprintf("DF: %s",
                  virada_pct(pdad_df$pct_trans_renda))),
              virada_chip("Ocupados que vão de ônibus ao trabalho",
                virada_pct(pdad$pct_onibus),
                if (is.null(pdad_df)) NULL else sprintf("DF: %s",
                  virada_pct(pdad_df$pct_onibus))),
              virada_chip("Domicílios sem internet em casa",
                virada_pct(pdad$pct_sem_internet),
                if (is.null(pdad_df)) NULL else sprintf("DF: %s",
                  virada_pct(pdad_df$pct_sem_internet))),
              virada_chip("Domicílios sem escritura definitiva",
                virada_pct(pdad$pct_sem_escritura),
                if (is.null(pdad_df)) NULL else sprintf("DF: %s",
                  virada_pct(pdad_df$pct_sem_escritura))),
              virada_chip("Empregados sem carteira assinada",
                virada_pct(pdad$pct_sem_carteira),
                if (is.null(pdad_df)) NULL else sprintf("DF: %s",
                  virada_pct(pdad_df$pct_sem_carteira))))),
        tags$h4("Roteiro curto"),
        tags$p(class = "painel-nota", roteiro),
        tags$div(class = "painel-resumo-acoes",
          tags$textarea(id = ns("msg"), class = "form-control",
            rows = 6, style = "width: 100%; font-size: 13px;", mensagem),
          tags$button(id = ns("copiar"), type = "button",
            class = "btn btn-default btn-sm", style = "margin-top: 6px;",
            `aria-label` = "Copiar mensagem para a militância",
            onclick = sprintf(paste0(
              "navigator.clipboard.writeText(",
              "document.getElementById('%s').value)",
              ".then(function(){var b=document.getElementById('%s');",
              "b.textContent='Copiado!';",
              "setTimeout(function(){b.textContent='Copiar mensagem';},2000);})",
              ".catch(function(){alert('Não foi possível copiar.');});",
              ");"),
              ns("msg"), ns("copiar")),
            "Copiar mensagem")))
    })

    # planilha -----------------------------------------------------------------
    output$xlsx <- shiny::downloadHandler(
      filename = "virada_2t_df.xlsx",
      content = function(arquivo) {
        shiny::req(tem_dados())
        openxlsx::write.xlsx(list(
          locais = dados$local,
          prioridade = dados$prioridade,
          ra = readr::read_csv(file.path(virada_dir, "virada_ra.csv"),
            show_col_types = FALSE, progress = FALSE)),
          arquivo, firstActiveRow = 1)
      })
  })
}

## To be copied in the UI
# mod_panel_virada_ui("panel_virada_1")

## To be copied in the server
# mod_panel_virada_server("panel_virada_1")
