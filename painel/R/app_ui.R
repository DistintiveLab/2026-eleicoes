# UI do painel: composicao dos blocos de R/painel_ui.R. Para adicionar ou
# remover uma aba, edite painel_abas() em R/painel_ui.R — ou componha aqui
# com shiny::tabPanel() + um novo R/mod_*.R no padrao dos existentes.

app_ui <- function() {
  titulo <- painel_brand_titulo("Painel Eleições")
  subtitulo <- painel_brand_subtitulo("beep — banco de dados do painel")
  paleta <- painel_brand_paleta("brasil")
  shiny::tagList(
    painel_recursos("www", paleta),
    painel_topbar(titulo, subtitulo),
    do.call(shiny::navbarPage, c(
      list(title = shiny::tags$span(class = "painel-marca-mobile", titulo),
           id = "painel_nav", selected = "virada", windowTitle = titulo,
           collapsible = TRUE, lang = "pt-BR"),
      painel_abas())),
    painel_aviso_carregando(),
    painel_rodape(painel_brand_contato())
  )
}
