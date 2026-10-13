#' panel_regiao UI Function
#'
#' @description Resumo da região: cartões com os valores recentes dos
#'   indicadores do grupo Resumo (curados no app do beep via aba Variáveis
#'   e Indicadores) ou, na falta dele, dos indicadores compostos dos 7
#'   eixos, dos 4 objetivos e dos estratos PNAD ou, ainda, de todos os
#'   indicadores agrupados por fonte — com botão "mostrar mais" expandindo
#'   um accordeon por raiz (Eixos, Objetivos, Estratos PNAD ou Por fonte),
#'   grupo e indicador com mini-gráficos, alem da serie temporal de um
#'   indicador do banco de dados do painel para a
#'   localidade escolhida dentro de um nivel territorial (regiao, UF,
#'   regiao intermediaria, microrregiao, regiao imediata, municipio).
#'   Opcionalmente (painel_geolocalizacao=1), um botao ao lado do seletor
#'   de localidade pede a posicao ao navegador e seleciona a localidade
#'   mais proxima do nivel corrente.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_panel_regiao_ui <- function(id) {
  ns <- NS(id)
  tagList(
    tags$div(class = "painel-toolbar", role = "search", `aria-label` = "Seleção de indicador e localidade",
      tags$div(class = "form-group",
        tags$label(`for` = ns("indicador"), "Indicador"),
        shiny::selectizeInput(ns("indicador"), NULL, choices = NULL,
                              width = "100%", options = painel_opcoes_select(
                                "Escolha um indicador"))),
      tags$div(class = "form-group",
        tags$label(`for` = ns("nivel"), "Nível territorial"),
        shiny::selectizeInput(ns("nivel"), NULL, choices = NULL,
                              width = "auto", options = painel_opcoes_select(
                                "Escolha o nível", max_options = 100L))),
      tags$div(class = "form-group",
        tags$label(`for` = ns("localidade"), "Localidade"),
        shiny::selectizeInput(ns("localidade"), NULL, choices = NULL,
                              width = "100%", options = painel_opcoes_select(
                                "Digite parte do nome")),
        # Botao "usar minha localizacao" (painel_geolocalizacao=1 no
        # .Renviron): pede a posicao ao navegador e o server seleciona a
        # localidade mais proxima do nivel corrente. Os erros chegam
        # mapeados por codigo: a mensagem crua do navegador (ex.: "Unknown
        # error acquiring position", do Firefox do Linux sem servico de
        # localizacao) nao orienta o usuario
        if (painel_geolocalizacao_ativa()) {
          tags$button(id = ns("geo"), type = "button",
            class = "painel-info-btn",
            title = "Usar minha localização",
            `aria-label` = "Usar minha localização",
            onclick = sprintf(paste0(
              "(function(){",
              "if(!('geolocation' in navigator)){",
              "alert('Este navegador não oferece localização ou a página não ",
              "está em HTTPS/localhost.');return;}",
              "navigator.geolocation.getCurrentPosition(",
              "function(p){Shiny.setInputValue('%s',",
              "{lat:p.coords.latitude,lon:p.coords.longitude},",
              "{priority:'event'})},",
              "function(e){var m={",
              "1:'permissão negada no navegador',",
              "2:'posição indisponível (comum no Firefox do Linux, que não tem ",
              "serviço de localização; tente outro navegador, como o Chrome)',",
              "3:'tempo esgotado'}[e.code]||(e.message||'erro desconhecido');",
              "alert('Não foi possível obter sua localização: '+m+' Escolha a ",
              "localidade manualmente ou tente outro navegador.');},",
              "{enableHighAccuracy:false,timeout:15000,maximumAge:300000});",
              "})()"),
              ns("geo_coords")),
            shiny::icon("location-arrow"))
        })),
    tags$div(class = "painel-card",
      tags$h3("Resumo da região"),
      tags$p(class = "painel-nota", shiny::textOutput(ns("resumo_local"))),
      # Slider estatico (nao renderUI): o JS do painel exige o no no DOM
      # na chegada da mensagem que preenche os rotulos; com uma unica data
      # fica 1..1 ate a cobertura chegar
      tags$div(class = "painel-resumo-periodo",
        shiny::sliderInput(ns("resumo_data"),
          "Data de referência do resumo", min = 1, max = 1, value = 1,
          step = 1, sep = "", ticks = FALSE, width = "100%")),
      shiny::uiOutput(ns("resumo")),
      shiny::uiOutput(ns("detalhes"))),
    tags$div(class = "painel-regiao-grade",
      tags$div(class = "painel-card",
        tags$h3(shiny::textOutput(ns("titulo")), class = "sr-only"),
        tags$div(class = "painel-serie-opcoes",
          tags$label(`for` = ns("tipo_grafico"), "Visualização"),
          shiny::selectInput(ns("tipo_grafico"), NULL,
            choices = c("Linha" = "linha", "Barras" = "barras",
                        "Lollipop" = "lollipop",
                        "Banda (mín, máx e mediana)" = "banda"),
            selected = "linha", width = "auto")),
        plotly::plotlyOutput(ns("serie"), height = "420px"),
        tags$p(class = "painel-nota",
          "Série do banco de dados do painel. Use o seletor de nível",
          "territorial para mudar de recorte (região, UF, divisões",
          "regionais do IBGE ou município), escolher a localidade desejada",
          "e o seletor de visualização para alternar entre linha, barras,",
          "lollipop e a banda de mínimo, máximo e mediana do nível.")),
      tags$div(class = "painel-card painel-globo-card",
        tags$h3("Globo de localidades"),
        mod_panel_globe_ui(ns("panel_globe_1")),
        tags$p(class = "painel-nota",
          "Arraste para girar, aproxime com a roda ou pelos botões e clique",
          "em uma área com dados para escolher a localidade do nível",
          "territorial corrente; no nível municipal o município escolhido",
          "aparece destacado sobre o estado inteiro.")))
  )
}

#' panel_regiao Server Functions
#'
#' @param paleta reactive com a paleta ativa ("govbr" ou "pb") — define a
#'   cor da serie
#'
#' @noRd
mod_panel_regiao_server <- function(id,
                                    paleta = shiny::reactive("govbr")) {
  moduleServer(id, function(input, output, session) {
    md <- painel_mdata_cache()
    niveis <- painel_niveis_cache()
    hierarquia <- painel_hierarquia_cache()
    compostos <- painel_compostos_cache()
    fontes <- painel_fontes_cache()
    grupo_resumo <- painel_grupo_resumo_cache()
    shiny::updateSelectizeInput(session, "indicador",
                                choices = painel_opcoes_indicador(md),
                                selected = if (nrow(md))
                                  painel_indicador_default(md) else NULL,
                                server = TRUE)
    shiny::updateSelectizeInput(session, "nivel",
      choices = setNames(niveis$nivel_id,
                         paste0(niveis$rotulo, " (", niveis$n_locais, ")")),
      selected = painel_nivel_default(niveis))

    locais <- shiny::reactive({
      shiny::req(input$nivel)
      painel_locais_nivel_cache(input$nivel)
    })

    # Globo de localidades: as delimitacoes do nivel corrente e o clique
    # contextualizado — numa feicao do nivel seleciona direto; numa UF da
    # base municipal escolhe a localidade com maior cobertura dentro dela
    uf_pendente <- shiny::reactiveVal(NULL)
    clique_globo <- mod_panel_globe_server("panel_globe_1",
      nivel = shiny::reactive(input$nivel),
      indicador = shiny::reactive({
        ind <- suppressWarnings(as.integer(input$indicador))[1]
        if (!is.na(ind)) ind else NULL
      }),
      localidade = shiny::reactive(
        if (length(input$localidade) && nzchar(input$localidade))
          suppressWarnings(as.integer(input$localidade))[1] else NULL))

    # Clique no globo: feicao do proprio nivel vai direto ao seletor;
    # UF (base do nivel municipal) leva a localidade com mais pontos do
    # indicador dentro dela — sem candidatos, cai no nivel UF com ela
    shiny::observeEvent(clique_globo(), {
      escolha <- clique_globo()
      shiny::req(is.list(escolha), length(escolha$code),
                 !is.na(escolha$code))
      if (identical(escolha$modo, "nivel")) {
        escolhas <- locais()
        if (escolha$code %in% unlist(escolhas)) {
          shiny::updateSelectizeInput(session, "localidade",
            choices = escolhas, selected = escolha$code, server = TRUE)
        }
      } else {
        indicador <- suppressWarnings(as.integer(input$indicador))[1]
        if (is.na(indicador)) indicador <- painel_indicador_default(md)
        destino <- if (!is.na(indicador))
          painel_local_top_uf_cache(indicador, input$nivel, escolha$code) else NULL
        if (is.null(destino)) {
          uf_pendente(escolha$code)
          shiny::updateSelectizeInput(session, "nivel", selected = "2")
        } else {
          shiny::updateSelectizeInput(session, "localidade",
            choices = locais(), selected = destino, server = TRUE)
        }
      }
    })

    # Botao "usar minha localizacao": com a posicao do navegador,
    # seleciona a localidade do nivel corrente cuja feicao contem o ponto
    # (ou a de representacao interna mais proxima). Niveis pesados, sem
    # malha leve no painel, avisam em vez de falharem em silencio
    shiny::observeEvent(input$geo_coords, {
      coords <- input$geo_coords
      shiny::req(is.list(coords), !is.null(coords$lat),
                 !is.null(coords$lon))
      lat <- suppressWarnings(as.numeric(coords$lat)[1])
      lon <- suppressWarnings(as.numeric(coords$lon)[1])
      escolhas <- locais()
      shiny::req(!is.na(lat), !is.na(lon), length(escolhas))
      geo <- painel_geo_nivel_cache(input$nivel)
      if (!nrow(geo)) {
        shiny::showNotification(
          paste0("Este nível não tem malha leve para localizar a ",
                 "localidade mais próxima."), type = "warning")
        return(NULL)
      }
      com_dados <- geo[geo$code %in% unlist(escolhas, use.names = FALSE), ]
      if (!nrow(com_dados)) com_dados <- geo
      alvo <- painel_geo_mais_proxima(com_dados, lat, lon)
      if (!is.na(alvo) && alvo %in% unlist(escolhas, use.names = FALSE)) {
        shiny::updateSelectizeInput(session, "localidade",
          choices = escolhas, selected = alvo, server = TRUE)
      }
    })

    # Ao trocar de nivel territorial: recarrega localidades e seleciona a
    # com maior cobertura do indicador corrente naquele nivel — ou a UF
    # clicada no globo, quando a troca de nivel veio de la. Indicador sem
    # dados no novo nivel troca para o primeiro com dados, mantendo a
    # tela util em vez de um globo "sem dados"
    shiny::observeEvent(input$nivel, {
      escolhas <- locais()
      shiny::req(length(escolhas))
      pendente <- uf_pendente()
      uf_pendente(NULL)
      indicador <- suppressWarnings(as.integer(input$indicador))[1]
      if (is.na(indicador)) indicador <- painel_indicador_default(md)
      if (!painel_ind_tem_dados(indicador, input$nivel)) {
        com_dados <- painel_indicador_com_dados(md, input$nivel)
        if (!is.na(com_dados)) {
          indicador <- com_dados
          # server=TRUE exige choices na atualizacao: sem elas o Shiny
          # registra um dataobj vazio e o cliente falha ao buscar o rotulo
          shiny::updateSelectizeInput(session, "indicador",
                                      choices = painel_opcoes_indicador(md),
                                      selected = indicador, server = TRUE)
        }
      }
      destino <- NULL
      if (length(pendente) && identical(input$nivel, "2") &&
          pendente %in% unlist(escolhas, use.names = FALSE)) {
        destino <- as.integer(pendente)
      } else {
        topo <- painel_local_top_cache(indicador, input$nivel)
        destino <- if (is.null(topo)) as.integer(escolhas[[1]]) else topo
      }
      shiny::updateSelectizeInput(session, "localidade",
                                  choices = escolhas, selected = destino,
                                  server = TRUE)
    })

    serie_loc <- shiny::reactive({
      shiny::validate(shiny::need(nrow(md) > 0,
        "Banco de dados do painel sem indicadores (tabela mdata vazia): confira as variáveis user, password, host e dbname e reinicie a sessão R antes de relançar o app."))
      shiny::req(input$indicador, input$localidade)
      painel_valores_local_cache(input$indicador, input$localidade)
    })

    # Rotulo da localidade corrente: sai dos proprios rotulos das escolhas
    # do selectize (nome + sigla da UF no nivel municipal)
    rotulo_local <- shiny::reactive({
      rotulos <- locais()
      i <- match(as.integer(input$localidade), rotulos)
      if (!length(i) || is.na(i)) NULL else names(rotulos)[i]
    })

    # Nome do nivel territorial corrente (Município, Região, UF...)
    rotulo_nivel <- shiny::reactive({
      rotulo <- niveis$rotulo[as.character(niveis$nivel_id) ==
                                as.character(input$nivel)]
      if (length(rotulo) && !is.na(rotulo[1])) rotulo[1] else "Localidade"
    })

    titulo <- shiny::reactive({
      shiny::validate(shiny::need(nrow(md) > 0,
        "Banco de dados do painel sem indicadores (tabela mdata vazia): confira as variáveis user, password, host e dbname e reinicie a sessão R antes de relançar o app."))
      shiny::req(input$indicador, rotulo_local())
      indice <- match(as.integer(input$indicador), md$mdata_id)
      nome <- md$data_name[indice]
      if (is.na(nome)) nome <- md$orig_name[indice]
      paste0(nome, " — ", rotulo_local())
    })

    output$resumo_local <- shiny::renderText({
      shiny::req(rotulo_local())
      paste0(rotulo_nivel(), ": ", rotulo_local())
    })

    cor <- shiny::reactive({
      if (identical(paleta(), "pb")) "#78529D" else "#1351B4"
    })

    # Tipo padrao do grafico em destaque segundo o DW: override por
    # indicador (mdata_grafico) ou default por classe (composto -> banda)
    tipo_grafico_dw <- shiny::reactive({
      indice <- match(as.integer(input$indicador), md$mdata_id)
      painel_tipo_grafico(
        if (!is.na(indice)) md$tipo_grafico[indice] else NA_character_,
        if (!is.na(indice)) md$data_class_id[indice] else NA_integer_)
    })

    # Troca de indicador realinha o seletor de visualizacao com o padrao
    # do DW; a escolha manual do usuario vale ate a proxima troca
    shiny::observeEvent(input$indicador, {
      shiny::req(nrow(md))
      shiny::updateSelectInput(session, "tipo_grafico",
                               selected = tipo_grafico_dw())
    })

    output$titulo <- shiny::renderText(titulo())

    output$serie <- plotly::renderPlotly({
      v <- serie_loc()
      shiny::validate(shiny::need(nrow(v),
        "Sem dados para esta combinação de indicador e localidade."))
      tipo <- input$tipo_grafico
      if (length(tipo) != 1L || is.na(tipo) ||
          !tipo %in% c("linha", "barras", "lollipop", "banda"))
        tipo <- tipo_grafico_dw()
      indice <- match(as.integer(input$indicador), md$mdata_id)
      rotulo_x <- painel_rotulo_tempo(
        if (!is.na(indice)) md$freq_name[indice] else NA_character_)
      p <- if (identical(tipo, "banda")) {
        painel_plot_banda(painel_valores_por_data_cache(input$indicador),
                          local_id = input$localidade, titulo = titulo(),
                          cor = cor(), rotulo_x = rotulo_x)
      } else {
        painel_plot_indicador(v, titulo = titulo(), cor = cor(),
                              tipo = tipo, rotulo_x = rotulo_x)
      }
      p <- painel_sem_camadas_vazias(p)
      p <- plotly::ggplotly(p, tooltip = c("x", "y"))
      if (identical(tipo, "banda")) {
        # silencia o hover da banda/mediana (contexto): o destaque e a
        # unica camada com marcadores no painel_plot_banda()
        modos <- vapply(p$x$data, function(t) paste0(t$mode), character(1))
        silenciar <- which(!grepl("markers", modos))
        if (length(silenciar))
          p <- plotly::style(p, hoverinfo = "skip", traces = silenciar)
      }
      plotly::config(p, displayModeBar = FALSE)
    })

    # Resumo da localidade (labourvaluesdatapanel-like): todos os valores
    # da localidade em uma leitura; cartões na data de referencia do
    # slider com os indicadores do grupo Resumo (curados no app do beep)
    # ou, na falta, os compostos por eixo/objetivo ou todos por fonte
    resumo_vals <- shiny::reactive({
      shiny::req(input$localidade)
      painel_valores_local_todos_cache(input$localidade)
    })

    expandido <- shiny::reactiveVal(FALSE)

    # Indicadores que puxam o resumo: grupo Resumo quando curado; sem
    # ele, os compostos da hierarquia (ancestral) ou todo o catalogo
    # (agrupamento por fonte)
    resumo_ids <- shiny::reactive({
      if (NROW(grupo_resumo)) return(grupo_resumo$mdata_id)
      if (NROW(hierarquia) && NROW(compostos))
        return(intersect(hierarquia$mdata_id, compostos$mdata_id))
      if (NROW(fontes)) return(fontes$mdata_id)
      integer(0)
    })

    # Slider de data do resumo: recorte temporal dos cartões
    # (valor e ranking na data escolhida; default = data mais recente com
    # dados). Os limites vem dos refdates disponiveis dos proprios
    # indicadores do resumo na localidade corrente
    datas_resumo <- shiny::reactive({
      v <- resumo_vals()
      ids <- resumo_ids()
      if (!NROW(v) || !length(ids)) return(as.Date(character(0)))
      datas <- sort(unique(v$refdate[v$mdata_id %in% ids]))
      datas <- datas[!is.na(datas)]
      ano_piso <- 1995L
      datas_filtradas <-
        datas[as.integer(format(datas, "%Y")) >= ano_piso]
      if (length(datas_filtradas)) datas <- datas_filtradas
      datas
    })

    rotulos_resumo <- shiny::reactive({
      d <- datas_resumo()
      if (!length(d)) return(character(0))
      painel_rotulo_data(d)
    })

    # Envia apenas as posicoes (1..N) e os rotulos de data: mesmo contrato
    # do slider por data do mapa; o navegador ajusta a selecao a cobertura
    # recebida. indicatorId = localidade descarta mensagens obsoletas da
    # mesma forma que o indicador faz no mapa
    shiny::observe({
      datas <- datas_resumo()
      if (!length(datas)) return(NULL)
      session$sendCustomMessage("painel-map-years", list(
        sliderId = session$ns("resumo_data"),
        indicatorId = session$ns("localidade"),
        indicator = input$localidade,
        years = I(as.integer(seq_along(datas))),
        labels = I(as.character(rotulos_resumo()))))
    })

    resumo_data <- shiny::reactive({
      datas <- datas_resumo()
      if (!length(datas)) return(as.Date(NA))
      i <- suppressWarnings(as.integer(input$resumo_data)[1])
      if (is.na(i)) i <- length(datas)
      i <- max(1L, min(i, length(datas)))
      datas[i]
    })

    # Cartões do resumo: membros do grupo Resumo (curados no app do
    # beep); sem grupo, os compostos da hierarquia (7 eixos, 4 objetivos e
    # os estratos PNAD); sem nenhum dos dois, um cartão por indicador do
    # catalogo agrupado por fonte — em todos os casos com o valor mais
    # recente na localidade e a posicao dela entre os municipios da
    # propria UF e do pais naquela data (uma leitura cacheada por
    # indicador/data; NA fora do nivel municipal)
    rotulo_chip <- function(mid, data_ref) {
      v <- resumo_vals()
      if (is.na(data_ref)) return(format(data_ref, "%Y"))
      if (!NROW(v)) return(format(data_ref, "%Y"))
      datas <- sort(unique(v$refdate[v$mdata_id == mid]))
      datas <- datas[!is.na(datas)]
      if (!length(datas)) return(format(data_ref, "%Y"))
      rot <- painel_rotulo_data(datas)
      pos <- match(data_ref, datas)
      if (!is.na(pos)) unname(rot[pos]) else format(data_ref, "%Y")
    }

    resumo <- shiny::reactive({
      v <- resumo_vals()
      r <- if (NROW(grupo_resumo)) {
        painel_resumo_membros(grupo_resumo, v, resumo_data())
      } else if (NROW(hierarquia) && NROW(compostos)) {
        painel_resumo_grupos(hierarquia, compostos, v, resumo_data())
      } else {
        painel_resumo_fontes(fontes, v, resumo_data())
      }
      if (!NROW(r)) return(r)
      ranks <- lapply(seq_len(nrow(r)), function(i)
        painel_ranking_local_cache(r$mdata_id[i], input$localidade,
                                   as.integer(format(r$refdate[i], "%Y")),
                                   refdate = r$refdate[i]))
      r$rank_uf <- vapply(ranks, function(x) x$rank_uf[1], numeric(1))
      r$n_uf <- vapply(ranks, function(x) x$n_uf[1], numeric(1))
      r$rank_br <- vapply(ranks, function(x) x$rank_br[1], numeric(1))
      r$n_br <- vapply(ranks, function(x) x$n_br[1], numeric(1))
      r
    })

    output$resumo <- shiny::renderUI({
      shiny::validate(shiny::need(nrow(md) > 0,
        "Banco de dados do painel sem indicadores (tabela mdata vazia): confira as variáveis user, password, host e dbname e reinicie a sessão R antes de relançar o app."))
      shiny::req(input$localidade)
      r <- resumo()
      chips <- lapply(seq_len(nrow(r)), function(i) {
        ranking <- painel_ranking_texto(r$rank_uf[i], r$n_uf[i],
                                        r$rank_br[i], r$n_br[i])
        delta <- if (is.finite(r$valor_ant[i]) && is.finite(r$valor[i]) &&
                     !identical(r$refdate[i], r$refdate_ant[i]))
          paste0("Var. ", rotulo_chip(r$mdata_id[i], r$refdate_ant[i]),
                 "-", rotulo_chip(r$mdata_id[i], r$refdate[i]), ": ",
                 if (r$valor[i] >= r$valor_ant[i]) "+" else "-",
                 painel_num(abs(r$valor[i] - r$valor_ant[i]),
                            r$unidade[i])) else NULL
        tags$div(class = "painel-resumo-chip",
          tags$div(class = "painel-resumo-chip-rotulo", r$rotulo[i]),
          tags$div(class = "painel-resumo-chip-valor",
            painel_num(r$valor[i], r$unidade[i]),
            tags$small(paste0(" (",
              rotulo_chip(r$mdata_id[i], r$refdate[i]), ")"))),
          if (!is.null(delta))
            tags$div(class = "painel-resumo-chip-delta", delta),
          if (!is.null(ranking)) {
            tags$div(class = "painel-resumo-chip-ranking",
                     paste0("(", ranking, ")"))
          })
      })
      tagList(
        if (length(chips)) {
          tags$div(class = "painel-resumo-grade", chips)
        } else {
          tags$p(class = "painel-resumo-nota",
            "Sem valores dos indicadores do resumo para esta localidade.")
        },
        tags$div(class = "painel-resumo-acoes",
          shiny::actionButton(session$ns("mostrar_mais"),
            if (expandido()) "Mostrar menos" else "Mostrar mais")))
    })

    shiny::observeEvent(input$mostrar_mais, {
      expandido(!expandido())
    })

    # Accordeon do "mostrar mais": raizes (Eixos, Objetivos ou Por
    # fonte) > grupo > indicador com mini-grafico da serie na localidade
    # corrente. indicador_bloco recebe a linha do catalogo (hierarquia ou
    # fontes), que traz data_name/orig_name/data_class_id
    indicador_bloco <- function(linha) {
      mid <- linha$mdata_id[1]
      nome <- linha$data_name[1]
      if (is.na(nome) || !nzchar(nome)) nome <- linha$orig_name[1]
      composto <- !is.na(linha$data_class_id[1]) &&
        linha$data_class_id[1] == 4
      tags$div(class = "painel-grupo-indicador",
        tags$strong(nome),
        if (isTRUE(composto)) tags$small(" · indicador composto"),
        tags$small(paste0(" (", linha$orig_name[1], ")")),
        shiny::plotOutput(session$ns(paste0("mini_", mid)), height = "110px"))
    }

    grupo_bloco <- function(gid) {
      linhas <- hierarquia[hierarquia$datagroup_id == gid, , drop = FALSE]
      linhas <- linhas[!duplicated(linhas$mdata_id), , drop = FALSE]
      if (!nrow(linhas)) return(NULL)
      tags$details(class = "painel-grupo painel-grupo-nivel2",
        tags$summary(linhas$datagroup_name[1],
          tags$small(paste0(" · ", nrow(linhas), " indicadores"))),
        tags$div(class = "painel-grupo-corpo",
          lapply(seq_len(nrow(linhas)), function(i) indicador_bloco(linhas[i, ]))))
    }

    raiz_bloco <- function(rnome, aberta = FALSE) {
      filhos <- hierarquia[hierarquia$raiz_nome == rnome,
                           c("datagroup_id", "datagroup_name")]
      filhos <- unique(filhos)
      filhos <- filhos[order(filhos$datagroup_id), ]
      ids <- unique(hierarquia$mdata_id[hierarquia$raiz_nome == rnome &
                                          !is.na(hierarquia$mdata_id)])
      tags$details(class = "painel-grupo", open = aberta,
        tags$summary(rnome,
          tags$small(paste0(" · ", length(ids), " indicadores"))),
        tags$div(class = "painel-grupo-corpo",
          lapply(filhos$datagroup_id, grupo_bloco)))
    }

    # Fallback sem eixos/objetivos: raiz unica "Por fonte" com um bloco
    # por fonte do catalogo, indicadores na ordem do mdata_id
    fonte_bloco <- function(fnome) {
      linhas <- fontes[fontes$fonte == fnome, , drop = FALSE]
      if (!nrow(linhas)) return(NULL)
      tags$details(class = "painel-grupo painel-grupo-nivel2",
        tags$summary(fnome,
          tags$small(paste0(" · ", nrow(linhas), " indicadores"))),
        tags$div(class = "painel-grupo-corpo",
          lapply(seq_len(nrow(linhas)), function(i) indicador_bloco(linhas[i, ]))))
    }

    output$detalhes <- shiny::renderUI({
      shiny::req(expandido())
      if (nrow(hierarquia)) {
        raizes <- c("Eixos", "Objetivos", "Estratos PNAD")
        raizes <- raizes[raizes %in% unique(hierarquia$raiz_nome)]
        raizes <- c(raizes, setdiff(unique(hierarquia$raiz_nome), raizes))
        return(lapply(seq_along(raizes), function(i)
          raiz_bloco(raizes[i], aberta = i == 1)))
      }
      if (!nrow(fontes)) return(NULL)
      nomes_fontes <- unique(fontes$fonte[!is.na(fontes$fonte)])
      ids <- fontes$mdata_id[!is.na(fontes$mdata_id)]
      tagList(tags$details(class = "painel-grupo", open = TRUE,
        tags$summary("Por fonte",
          tags$small(paste0(" · ", length(ids), " indicadores"))),
        tags$div(class = "painel-grupo-corpo",
          lapply(nomes_fontes, fonte_bloco))))
    })

    # Mini-graficos: outputs registrados uma unica vez para os indicadores
    # da hierarquia e do catalogo de fontes; cada render filtra
    # resumo_vals() pelo proprio id
    ids_hierarquia <- unique(c(hierarquia$mdata_id, fontes$mdata_id))
    ids_hierarquia <- ids_hierarquia[!is.na(ids_hierarquia)]
    invisible(lapply(ids_hierarquia, function(mid) {
      local({
        id <- mid
        output[[paste0("mini_", id)]] <- shiny::renderPlot({
          v <- resumo_vals()[resumo_vals()$mdata_id == id, ]
          if (!nrow(v)) {
            return(ggplot2::ggplot() +
              ggplot2::annotate("text", x = 0, y = 0, label = "Sem dados",
                                color = "#8a8a8a", size = 3.4) +
              ggplot2::theme_void())
          }
          ggplot2::ggplot(v, ggplot2::aes(x = as.Date(refdate), y = value)) +
            ggplot2::geom_line(color = cor(), linewidth = 0.7) +
            ggplot2::geom_point(color = cor(), size = 1.4) +
            ggplot2::theme_minimal(base_size = 10) +
            ggplot2::theme(axis.title = ggplot2::element_blank())
        }, bg = "transparent")
      })
    }))
  })
}

## To be copied in the UI
# mod_panel_regiao_ui("panel_regiao_1")

## To be copied in the server
# mod_panel_regiao_server("panel_regiao_1")
