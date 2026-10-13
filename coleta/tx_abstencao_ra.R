###Filtra e prepara dados base
 dbdbase <- DBI::dbGetQuery(con,"SELECT * from geonamed_datavalues WHERE orig_name IN ('abstencoes','aptos')")
dbdbase <- dbdbase|>
    dplyr::mutate(data_freq_id=max(data_freq_id))|>

      tidyr::pivot_wider(names_from='orig_name',values_from = 'value', id_cols = c(local_id,refdate),values_fill = 0,unused_fn=dplyr::first)
###Cria indicador
dbdbase <- tx_abstencao_ra <- dbdbase |>
                     dplyr::rename(setNames(c('abstencoes','aptos'), c('a','b'))) |>
                dplyr::transmute(tx_abstencao_ra = a / b,refdate,local_id)
