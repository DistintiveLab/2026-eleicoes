#' panel_map UI Function
#'
#' @description A shiny Module. Mapa coropletico do nivel territorial do
#'   indicador do DW (beepdb) no ano escolhido (ultimo refdate do ano):
#'   indicadores municipais mantem a malha historica; indicadores de outros
#'   niveis (UF, regiao, submunicipais) recebem a malha do nivel ou, quando
#'   ela excede o limite de feicoes, malhas por municipio (teto de 6 mil
#'   feicoes locais, com simplificacao adaptativa) e, acima disso, o
#'   contorno dos municipios com dados (degradacao honesta). Slider de ano animado, paleta com seletor de
#'   escala de cores (do zero, min-max ou quantil, invertivel) e
#'   atualizacao incremental (port do
#'   labourvaluesdatapanel): a geometria e enviada uma unica vez e apenas
#'   cores/tooltips atravessam a conexao; trocar de nivel troca a malha no
#'   proxy, sem reconstruir o widget.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_panel_map_ui <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(class = "painel-toolbar painel-mapa-toolbar", role = "search",
             `aria-label` = "Seleção de indicador e ano",
      tags$div(class = "form-group painel-mapa-indicador",
        tags$label(`for` = ns("indicador"), "Indicador"),
        tags$div(class = "painel-mapa-indicador-linha",
          shiny::selectizeInput(ns("indicador"), NULL, choices = NULL,
                                width = "100%", options = painel_opcoes_select(
                                  "Escolha um indicador")),
          shiny::actionButton(ns("info"), NULL,
            icon = shiny::icon("circle-info"),
            class = "painel-info-btn",
            `aria-label` = "Sobre o indicador"))),
      tags$div(class = "form-group painel-mapa-ano",
        tags$label(`for` = ns("data"), "Data"),
        shiny::sliderInput(ns("data"), NULL, min = 1, max = 1,
                           value = 1, step = 1, sep = "", ticks = FALSE,
                           animate = shiny::animationOptions(interval = 7000,
                                                             loop = FALSE),
                           width = "100%")),
      tags$div(class = "form-group painel-mapa-inverter",
        tags$label(`for` = ns("escala"), "Escala"),
        shiny::selectInput(ns("escala"), NULL,
          choices = c("Do zero" = "zero", "Mín-máx" = "minmax",
                      "Quantil" = "quantil"),
          selected = "zero", width = "140px"),
        shiny::checkboxInput(ns("inverter"), "Inverter cores"))),
    tags$p(class = "painel-mapa-status",
           shiny::textOutput(ns("status"), inline = TRUE)),
    tags$div(class = "painel-mapa",
             leaflet::leafletOutput(ns("mapa"), height = "calc(100vh - 370px)"))
  )
}

#' panel_map Server Functions
#'
#' @noRd
mod_panel_map_server <- function(id) {
  moduleServer(id, function(input, output, session) {

    md <- painel_mdata_cache()
    malha_municipal <- local({
      g <- painel_geo_mun_cache()
      g$layer_id <- as.character(g$local_id)
      g[, c("layer_id", "local_name", "geometry")]
    })
    normaliza_malha <- function(g) {
      if (!nrow(g)) return(g)
      g$layer_id <- as.character(if ("code" %in% names(g)) g$code else g$local_id)
      if (!"local_name" %in% names(g)) g$local_name <- g$label
      g[, c("layer_id", "local_name", "geometry")]
    }
    shiny::updateSelectizeInput(session, "indicador",
                                choices = painel_opcoes_indicador(md),
                                selected = if (nrow(md))
                                  painel_indicador_default(md) else NULL,
                                server = TRUE)

    # Datas disponiveis do indicador direto do DW (agregacao cacheada),
    # sem puxar a serie completa para descobri-las: o slider caminha por
    # refdates exatos (series com mais de um ponto no ano, como turnos
    # de eleicao, ganham uma posicao por data)
    datas_ind <- shiny::reactive({
      shiny::validate(shiny::need(nrow(md) > 0,
        "Banco de dados do painel sem indicadores (tabela mdata vazia): confira as variáveis user, password, host e dbname e reinicie a sessão R antes de relançar o app."))
      shiny::req(input$indicador)
      painel_refdates_cache(input$indicador)$refdate
    })

    # Rotulo curto de cada posicao do slider: so o ano quando ele e o
    # unico refdate daquele ano, d/m/AAAA quando o ano tem mais de um
    rotulos_ind <- shiny::reactive(painel_rotulo_data(datas_ind()))

    # Posicao do slider -> refdate exato (clamp nas bordas; sem selecao
    # ainda, cai na ultima data)
    refdate_sel <- shiny::reactive({
      datas <- datas_ind()
      shiny::req(length(datas) > 0)
      i <- suppressWarnings(as.integer(input$data)[1])
      if (is.na(i)) i <- length(datas)
      i <- max(1L, min(i, length(datas)))
      datas[i]
    })

    rotulo_sel <- shiny::reactive({
      r <- rotulos_ind()
      i <- match(refdate_sel(), datas_ind())
      if (is.na(i) || !length(r) || i > length(r)) "" else r[i]
    })

    # Unidade do indicador corrente (dataunit_num do mdata_exts; "%"
    # exibe x100): a guarda NULL cobre cache de catalogo antigo sem a
    # coluna unidade
    unidade_ind <- shiny::reactive({
      ind <- suppressWarnings(as.integer(input$indicador))[1]
      u <- if (is.null(md$unidade)) NA_character_ else
        md$unidade[match(ind, md$mdata_id)]
      if (length(u) && !is.na(u[1])) u[1] else NA_character_
    })

    # Malha do nivel territorial do indicador: municipal mantem o
    # comportamento historico; niveis leves (UF, regiao, 7p) carregam a
    # malha do nivel inteiro; niveis pesados (submunicipais) carregam malhas
    # por municipio com dados (teto de 6 mil feicoes locais, que cobre os
    # setores censitarios de uma capital) e degradam para o contorno do
    # municipio acima disso
    mapa_malha <- shiny::reactive({
      ind <- suppressWarnings(as.integer(input$indicador))[1]
      ch <- if (is.na(ind)) NA_character_ else painel_ind_nivel_cache(ind)
      if (is.na(ch) || identical(ch, "7")) {
        return(list(geo = malha_municipal, nivel = "7",
                    degradados = character(0), aviso = ""))
      }
      rotulo <- unname(painel_niveis_rotulo[ch])
      if (is.na(rotulo)) rotulo <- sprintf("Nível %s", ch)
      g <- normaliza_malha(painel_geo_nivel_cache(ch))
      if (nrow(g)) {
        return(list(geo = g, nivel = ch, degradados = character(0), aviso = ""))
      }
      p <- painel_nivel_parse(ch)
      muns <- painel_muns_nivel_dados_cache(ind, ch)
      pecas <- list()
      degradados <- character(0)
      for (i in seq_len(nrow(muns))) {
        peca <- normaliza_malha(painel_geo_irmaos_nivel_cache(
          muns$municipio[i], p$tipo, larg = p$nivel))
        if (nrow(peca)) {
          pecas <- c(pecas, list(peca))
          next
        }
        contorno <- normaliza_malha(
          painel_geo_municipio_codigo_cache(muns$municipio[i]))
        if (nrow(contorno)) {
          pecas <- c(pecas, list(contorno))
          degradados[contorno$layer_id[1]] <- sprintf(
            "malha do nível %s indisponível (%s feições com dados)",
            rotulo, painel_num(muns$n_locais[i]))
        }
      }
      if (!length(pecas)) {
        return(list(geo = malha_municipal, nivel = "7",
                    degradados = character(0),
                    aviso = sprintf(paste0("Nível %s sem malha disponível ",
                                           "para o mapa; exibindo a malha ",
                                           "municipal."), rotulo)))
      }
      geo <- if (length(pecas) == 1L) pecas[[1]] else do.call(rbind, pecas)
      aviso <- if (length(degradados)) sprintf(
        paste0("Nível %s: malha acima do limite de feições do mapa em %d ",
               "município(s); exibindo o contorno deles. Use a aba Região ",
               "para navegar o nível."),
        rotulo, length(degradados)) else ""
      list(geo = geo, nivel = ch, degradados = degradados, aviso = aviso)
    })

    # Envia apenas as posicoes (1..N) e os rotulos de data: o navegador
    # conserva a selecao mais recente e a ajusta a cobertura recebida
    # (snap direcional sobre lacunas).
    shiny::observe({
      datas <- datas_ind()
      session$sendCustomMessage("painel-map-years", list(
        sliderId = session$ns("data"),
        indicatorId = session$ns("indicador"),
        indicator = input$indicador,
        # I(): sem auto_unbox um array de 1 elemento vira escalar no JS
        years = I(as.integer(seq_along(datas))),
        labels = I(as.character(rotulos_ind()))))
    })

    # valores do refdate exato escolhido no slider, agregado no proprio
    # SQL e cacheado; NULL quando vazio e o contrato assumido por paleta,
    # status, camadas e legenda abaixo
    mapa_dados <- shiny::reactive({
      shiny::req(input$indicador, refdate_sel())
      v <- painel_valores_refdate_cache(input$indicador, refdate_sel())
      if (!nrow(v)) return(NULL)
      v
    })

    paleta <- shiny::reactive({
      d <- if (is.null(mapa_dados())) NA_real_ else mapa_dados()$value
      escala <- if (is.null(input$escala)) "zero" else input$escala
      painel_paleta(d, invertida = isTRUE(input$inverter),
                    escala = escala)
    })

    output$status <- shiny::renderText({
      aviso <- mapa_malha()$aviso
      if (nzchar(aviso)) return(aviso)
      if (!is.null(mapa_dados()) && nrow(mapa_dados())) return("")
      paste0("Data ", rotulo_sel(), ": sem observações. ",
             "Escolha outra data ou indicador.")
    })

    # Rotulos e cores de TODAS as feicoes da malha do nivel (NA onde sem
    # dados): o delta e computado sobre o conjunto integral, como no
    # labourvaluesdatapanel.
    camadas <- shiny::reactive({
      pal <- paleta()
      dados <- mapa_dados()
      malha <- mapa_malha()
      g <- malha$geo
      valor <- if (is.null(dados)) rep(NA_real_, nrow(g)) else
        dados$value[match(g$layer_id, as.character(dados$local_id))]
      cores <- pal(valor)
      texto <- ifelse(is.na(valor), "Sem dados",
                      painel_num(valor, unidade_ind()))
      if (length(malha$degradados)) {
        i <- match(g$layer_id, names(malha$degradados))
        hit <- !is.na(i)
        texto[hit] <- malha$degradados[i[hit]]
      }
      lapply(seq_len(nrow(g)), function(i) list(
        id = g$layer_id[i],
        color = cores[[i]],
        label = sprintf("<b>%s</b><br>%s", g$local_name[i], texto[i])))
    })

    output$mapa <- leaflet::renderLeaflet({
      # widget estatico na malha municipal: a troca de nivel acontece no
      # proxy do observe abaixo, sem rebuild nem corrida de proxies
      leaflet::leaflet(malha_municipal) |>
        leaflet::setView(lng = -53.633308, lat = -13.550520, zoom = 4) |>
        leaflet::setMaxBounds(-77, -38, -27, 10) |>
        # tiles Carto com CARTO_API_KEY ou fundo neutro vetorial sem tiles
        # (padrao do labourvaluesdatapanel + contorno de UFs do IBGE)
        painel_basemap_adicionar(contorno_uf = painel_geo_uf_cache) |>
        htmlwidgets::onRender("function(el, x) { window.PainelMap.attach(el, this); }")
    })

    # Geometria persistente e atualizacao incremental: cada widget novo (por
    # exemplo, apos reconexao) recebe a geometria; ao mudar indicador, ano ou
    # paleta, somente cores e textos atravessam a conexao. Trocar de nivel
    # troca a malha no proxy (removeShape + addPolygons + enquadramento)
    mapa_instancia <- NULL
    geo_chave <- NULL
    geometria_enviada <- FALSE
    geometria_ids <- character(0)
    entregues <- list()
    shiny::observe({
      pronto <- input$mapa_painel_map_ready
      shiny::req(pronto)
      malha <- mapa_malha()
      camadas <- camadas()
      ids <- malha$geo$layer_id
      chave <- paste(malha$nivel, length(ids),
                     if (length(ids)) paste(ids[1], ids[length(ids)]) else "")
      reset <- !identical(mapa_instancia, pronto)
      trocou <- !identical(geo_chave, chave)
      if (reset || trocou) {
        entregues <<- list()
        geometria_enviada <<- FALSE
      }
      if (reset) mapa_instancia <<- pronto
      if (trocou) geo_chave <<- chave
      proxy <- leaflet::leafletProxy("mapa", session = session, data = malha$geo)
      if (!isTRUE(geometria_enviada)) {
        if (length(geometria_ids))
          proxy <- proxy |> leaflet::removeShape(geometria_ids)
        proxy <- proxy |> leaflet::addPolygons(
          layerId = ~layer_id,
          fillColor = "transparent", fillOpacity = 0.85,
          weight = 0.4, color = "#666666", opacity = 0.6,
          highlight = leaflet::highlightOptions(weight = 2, color = "white",
                                                bringToFront = TRUE))
        geometria_ids <<- ids
        geometria_enviada <<- TRUE
      }
      # enquadra apenas quando a malha muda ou o widget e novo, para nao
      # roubar o pan/zoom do usuario a cada troca de ano
      if ((reset || trocou) && nrow(malha$geo) &&
          !identical(malha$nivel, "7")) {
        bb <- sf::st_bbox(sf::st_geometry(malha$geo))
        proxy <- proxy |> leaflet::fitBounds(
          bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]])
      } else if (trocou) {
        proxy <- proxy |>
          leaflet::setView(lng = -53.633308, lat = -13.550520, zoom = 4)
      }
      delta <- painel_delta_camadas(entregues, camadas)
      if (length(delta) || reset || trocou) {
        session$sendCustomMessage("painel-map-delta", list(
          id = session$ns("mapa"), instance = pronto,
          reset = reset || trocou,
          layers = delta))
        for (camada in delta) entregues[[camada$id]] <<- camada
      }
    })

    # Legenda colapsavel (o cliente a reempacota em details/summary)
    legenda_chave <- NULL
    shiny::observe({
      pronto <- input$mapa_painel_map_ready
      shiny::req(pronto, mapa_dados())
      dados <- mapa_dados()$value
      chave <- list(instance = pronto, indicador = input$indicador,
                    data = format(refdate_sel(), "%Y-%m-%d"),
                    inverter = isTRUE(input$inverter),
                    escala = input$escala,
                    faixa = range(dados, finite = TRUE))
      if (identical(chave, legenda_chave)) return()
      legenda_chave <<- chave
      proxy <- leaflet::leafletProxy("mapa", session = session)
      proxy |> leaflet::removeControl("painel-legenda")
      quantil_ativo <- identical(input$escala, "quantil") &&
        length(unique(dados[is.finite(dados)])) > 1
      if (any(is.finite(dados))) {
        titulo <- md$data_name[md$mdata_id == input$indicador]
        if (is.na(titulo)) titulo <- md$orig_name[md$mdata_id == input$indicador]
        if (quantil_ativo) {
          # legenda de classes por quebras de quantil calculadas sobre os
          # proprios valores do refdate (as duas bordas do intervalo nao
          # bastam para o colorQuantile)
          proxy |> leaflet::addLegend(
            "bottomright", layerId = "painel-legenda",
            values = dados[is.finite(dados)], pal = paleta(), opacity = 0.8,
            title = titulo,
            labFormat = function(type, cuts, ...)
              painel_num(cuts, unidade_ind()))
        } else {
          limite <- range(dados, finite = TRUE)
          if (limite[1] == limite[2]) {
            margem <- max(abs(limite[1]) * 1e-8, 1e-12)
            limite <- limite + c(-margem, margem)
          }
          proxy |> leaflet::addLegend(
            "bottomright", layerId = "painel-legenda",
            # valores como intervalo para contornar o bug do valor unico
            values = c(limite[1] * 0.99999999, limite[2] * 1.00000001),
            pal = paleta(), opacity = 0.8, title = titulo,
            labFormat = function(type, cuts, ...)
              painel_num(cuts, unidade_ind()))
        }
      }
    })

    # Ajuda do indicador: abre o modal sem alterar a selecao do mapa
    shiny::observeEvent(input$info, {
      shiny::req(input$indicador)
      linha <- md[md$mdata_id == input$indicador, ][1, ]
      titulo <- if (!is.na(linha$data_name)) linha$data_name else linha$orig_name
      descricao <- linha$data_desc
      if (is.na(descricao) || !nzchar(trimws(descricao))) {
        descricao <- "Descrição não disponível."
      }
      shiny::showModal(shiny::modalDialog(
        title = titulo,
        tags$p(tags$strong("Código no banco de dados do painel: "), linha$orig_name),
        tags$p(descricao),
        easyClose = TRUE,
        footer = shiny::modalButton("Fechar")))
    })
  })
}

## To be copied in the UI
# mod_panel_map_ui("panel_map_1")

## To be copied in the server
# mod_panel_map_server("panel_map_1")
