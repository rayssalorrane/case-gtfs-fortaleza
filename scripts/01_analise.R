# =============================================================================
# Case FNP – O que o GTFS revela sobre o transporte coletivo de Fortaleza
# Script 01: auditoria do GTFS, indicadores de oferta e cruzamento com
#            população, renda e empregos (IPEA / Acesso a Oportunidades)
# -----------------------------------------------------------------------------
# Autora: Rayssa Lorrane
#
# Como rodar (a partir da raiz do projeto, abrindo o .Rproj):
#   source("scripts/00_baixar_dados.R")   # uma vez: baixa as bases do IPEA
#   source("scripts/01_analise.R")
#
# Entradas: data/raw/gtfs_fortaleza.zip  (GTFS da ETUFOR, março/2026)
#           data/raw/aop_*.gpkg          (IPEA, baixados pelo script 00)
# Saídas:   output/indicadores_gtfs.xlsx e output/figuras/*.png
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(sf)
  library(ggplot2)
  library(openxlsx)
})

ZIP_GTFS  <- file.path("data", "raw", "gtfs_fortaleza.zip")
DIR_RAW   <- file.path("data", "raw")
DIR_SAIDA <- "output"
DIR_FIG   <- file.path(DIR_SAIDA, "figuras")
dir.create(DIR_FIG, showWarnings = FALSE, recursive = TRUE)

CRS_UTM     <- 31984           # SIRGAS 2000 / UTM 24S: distâncias em metros
DIA_REF     <- "S"             # sábado: o feed não traz viagens de dia útil
PICO        <- c(6, 8)         # pico da manhã: 6h às 8h
RAIO        <- 500             # distância de caminhada até a parada (metros)
HEADWAY_MAX <- 15              # linha "frequente": ônibus a cada 15 min ou menos

# Paleta institucional (mesma da apresentação)
COR <- list(tinta = "#1B2B34", azul = "#0E5E6F", azul_claro = "#7FB7BE",
            laranja = "#E8871E", vermelho = "#C8553D", cinza = "#D9DCD6", fundo = "#F7F7F4")


# =============================================================================
# 1. LEITURA
# =============================================================================

tmp <- tempfile("gtfs_"); dir.create(tmp)
ler <- function(arq) fread(unzip(ZIP_GTFS, arq, exdir = tmp), colClasses = "character", encoding = "UTF-8")

routes   <- ler("routes.txt")
trips    <- ler("trips.txt")
stops    <- ler("stops.txt")
st       <- ler("stop_times.txt")
calendar <- ler("calendar.txt")
shapes   <- ler("shapes.txt")
fares    <- ler("fare_attributes.txt")

# "HH:MM:SS" -> segundos (o GTFS aceita horas acima de 24 para viagens após a meia-noite)
para_seg <- function(x) {
  p <- tstrsplit(x, ":", fixed = TRUE, type.convert = TRUE)
  ifelse(x == "", NA_real_, p[[1]] * 3600 + p[[2]] * 60 + p[[3]])
}

# Sentido da viagem: o campo direction_id está vazio; o sufixo do shape_id
# (-I = ida, -V = volta) traz essa informação.
trips[, sentido := fifelse(grepl("-V$", shape_id), "Volta", "Ida")]


# =============================================================================
# 2. AUDITORIA DE QUALIDADE DO FEED
# =============================================================================

vazio <- function(dt, col) if (col %in% names(dt)) mean(dt[[col]] == "") else 1
servicos_sem_viagem <- setdiff(calendar$service_id, unique(trips$service_id))
fim_validade <- as.Date(max(calendar$end_date), "%Y%m%d")

qualidade <- data.table(
  item = c("Linhas cadastradas", "Linhas com pelo menos uma viagem", "Paradas cadastradas",
           "Paradas usadas por alguma viagem", "Viagens (sábado)", "Viagens (domingo)",
           "Viagens de dia útil", "Fim da validade do calendário",
           "Horários de parada ausentes (stop_times)", "Viagens sem sentido (direction_id)",
           "Viagens sem destino (trip_headsign)", "Viagens sem veículo (block_id)",
           "Paradas sem informação de acessibilidade", "Linhas sem cor cadastrada"),
  valor = c(nrow(routes), uniqueN(trips$route_id), nrow(stops),
            uniqueN(st$stop_id), sum(trips$service_id == "S"), sum(trips$service_id == "D"),
            sum(trips$service_id == "U"), format(fim_validade, "%d/%m/%Y"),
            sprintf("%.1f%%", 100 * mean(st$arrival_time == "")),
            sprintf("%.0f%%", 100 * vazio(trips, "direction_id")),
            sprintf("%.0f%%", 100 * vazio(trips, "trip_headsign")),
            sprintf("%.0f%%", 100 * vazio(trips, "block_id")),
            sprintf("%.0f%%", 100 * vazio(stops, "wheelchair_boarding")),
            sprintf("%.0f%%", 100 * vazio(routes, "route_color"))),
  leitura = c("", "45 linhas sem viagens: Expressos, UECE, Unifor, Assembleia (típicas de dia útil)", "",
              "", "", "", paste("Serviço 'U' existe no calendário, mas nenhuma viagem o usa:",
                                paste(servicos_sem_viagem, collapse = ", ")),
              ifelse(fim_validade < Sys.Date(), "Feed vencido: apps deixam de mostrar os horários", "Válido"),
              "Normal: só pontos de controle têm horário; os demais são interpolados",
              "Recuperado pelo sufixo do shape_id (-I/-V)", "", "Impede estimar a frota pelo feed",
              "", "")
)
print(qualidade)


# =============================================================================
# 3. HORÁRIOS EM TODAS AS PARADAS (interpolação entre pontos de controle)
# =============================================================================

st[, `:=`(seq = as.integer(stop_sequence), seg = para_seg(arrival_time))]
setorder(st, trip_id, seq)
st[, k := seq_len(.N), by = trip_id]
st[, `:=`(seg_ant = nafill(seg, "locf"), seg_prox = nafill(seg, "nocb"),
          k_ant = nafill(fifelse(is.na(seg), NA_integer_, k), "locf"),
          k_prox = nafill(fifelse(is.na(seg), NA_integer_, k), "nocb")), by = trip_id]
st[, seg_i := fifelse(!is.na(seg), seg, seg_ant + (k - k_ant) / (k_prox - k_ant) * (seg_prox - seg_ant))]

viagens <- st[, .(inicio = min(seg_i), fim = max(seg_i), n_paradas = .N), by = trip_id][
  trips, on = "trip_id"][routes[, .(route_id, linha = route_short_name, nome = route_long_name)], on = "route_id", nomatch = 0]


# =============================================================================
# 4. INDICADORES DE OFERTA
# =============================================================================

# Extensão de cada itinerário (shape), em km
shapes_sf <- shapes[, .(lat = as.numeric(shape_pt_lat), lon = as.numeric(shape_pt_lon),
                        ordem = as.integer(shape_pt_sequence)), by = shape_id][order(shape_id, ordem)]
shapes_sf <- shapes_sf[, .(geometry = list(st_linestring(cbind(lon, lat)))), by = shape_id]
shapes_sf <- st_transform(st_sf(shapes_sf, geometry = st_sfc(shapes_sf$geometry, crs = 4326)), CRS_UTM)
shapes_sf$km <- as.numeric(st_length(shapes_sf)) / 1000
viagens <- merge(viagens, st_drop_geometry(shapes_sf)[, c("shape_id", "km")], by = "shape_id", all.x = TRUE)
setnames(viagens, "km", "km_shape")

# Distância percorrida pela viagem: soma das distâncias entre paradas consecutivas.
# Mais confiável que o shape: nas linhas circulares, cada viagem cobre só um
# trecho, mas aponta para o shape do circuito inteiro (60 km).
xy <- st_coordinates(st_transform(st_as_sf(stops[, .(stop_id, lon = as.numeric(stop_lon), lat = as.numeric(stop_lat))],
                                           coords = c("lon", "lat"), crs = 4326), CRS_UTM))
coords <- data.table(stop_id = stops$stop_id, x = xy[, 1], y = xy[, 2])
st[coords, `:=`(x = i.x, y = i.y), on = "stop_id"]
dist_viagem <- st[, .(km = sum(sqrt(diff(x)^2 + diff(y)^2)) / 1000), by = trip_id]
viagens <- merge(viagens, dist_viagem, by = "trip_id")
viagens[, `:=`(duracao_min = (fim - inicio) / 60, hora = floor(inicio / 3600))]
viagens[, vel_kmh := fifelse(duracao_min > 0, km / (duracao_min / 60), NA_real_)]

shape_incoerente <- viagens[km_shape > 1.5 * km, .N]
qualidade <- rbind(qualidade, data.table(
  item = "Viagens cujo shape é bem maior que o trajeto entre paradas",
  valor = sprintf("%s (%.0f%%)", format(shape_incoerente, big.mark = "."), 100 * shape_incoerente / nrow(viagens)),
  leitura = "Ex.: linhas circulares divididas em trechos que apontam para o shape do circuito inteiro"))

dias <- c(S = "Sábado", D = "Domingo")

# 4.1 Viagens por hora de partida
viagens_hora <- viagens[, .N, by = .(dia = dias[service_id], hora = hora %% 24)][order(dia, hora)]

# 4.2 Ônibus em operação ao longo do dia (viagens em andamento a cada 5 min)
grade_t <- seq(0, 30 * 3600, by = 300)
em_operacao <- rbindlist(lapply(names(dias), function(s) {
  v <- viagens[service_id == s]
  data.table(dia = dias[[s]], seg = grade_t,
             onibus = vapply(grade_t, function(t) sum(v$inicio <= t & v$fim > t), integer(1)))
}))
pico_frota <- em_operacao[, .SD[which.max(onibus)], by = dia]

# 4.3 Resumo por dia
resumo_dia <- viagens[, .(
  linhas = uniqueN(route_id), viagens = .N,
  veiculo_km = sum(km, na.rm = TRUE),
  velocidade_mediana_kmh = median(vel_kmh[is.finite(vel_kmh)], na.rm = TRUE),
  duracao_mediana_min = median(duracao_min)
), by = .(dia = dias[service_id])][pico_frota[, .(dia, onibus_pico = onibus, hora_pico = sprintf("%02d:%02d", seg %/% 3600, (seg %% 3600) %/% 60))], on = "dia"]
print(resumo_dia)

# 4.4 Frequência de cada linha/sentido no pico (dia de referência)
vref <- viagens[service_id == DIA_REF]
freq_linha <- vref[inicio >= PICO[1] * 3600 & inicio < PICO[2] * 3600,
                   .(viagens_pico = .N), by = .(route_id, linha, nome, sentido)]
freq_linha[, `:=`(viagens_hora = viagens_pico / diff(PICO), intervalo_min = 60 / (viagens_pico / diff(PICO)))]
todas_ls <- unique(vref[, .(route_id, linha, nome, sentido)])
freq_linha <- merge(todas_ls, freq_linha, by = c("route_id", "linha", "nome", "sentido"), all.x = TRUE)
freq_linha[, classe := cut(intervalo_min, c(0, 10, 15, 30, 60, Inf),
                           labels = c("Até 10 min", "10 a 15 min", "15 a 30 min", "30 a 60 min", "Mais de 60 min"))]
freq_linha[is.na(classe), classe := "Sem viagem no pico"]
dist_freq <- freq_linha[, .N, by = classe][, pct := 100 * N / sum(N)][order(classe)]
print(dist_freq)

# 4.5 Velocidade comercial por linha (mediana das viagens do sábado)
vel_linha <- vref[is.finite(vel_kmh), .(vel_kmh = median(vel_kmh), km = median(km), viagens = .N),
                  by = .(linha, nome)][order(vel_kmh)]


# =============================================================================
# 5. OFERTA NAS PARADAS (pico do dia de referência)
# =============================================================================

eventos <- st[trips[service_id == DIA_REF, .(trip_id, route_id, sentido)], on = "trip_id", nomatch = 0]
eventos <- eventos[seg_i >= PICO[1] * 3600 & seg_i < PICO[2] * 3600]
frequentes <- freq_linha[!is.na(intervalo_min) & intervalo_min <= HEADWAY_MAX, .(route_id, sentido)]
eventos[frequentes, frequente := TRUE, on = c("route_id", "sentido")]
oferta_parada <- eventos[, .(partidas_hora = .N / diff(PICO), linhas = uniqueN(route_id),
                             tem_frequente = any(frequente %in% TRUE)), by = stop_id]

paradas <- merge(stops[, .(stop_id, stop_name, lat = as.numeric(stop_lat), lon = as.numeric(stop_lon))],
                 oferta_parada, by = "stop_id", all.x = TRUE)
paradas[is.na(partidas_hora), `:=`(partidas_hora = 0, linhas = 0L, tem_frequente = FALSE)]
# parada atendida no dia de referência, em qualquer horário
paradas[, atendida := stop_id %in% st[trip_id %in% trips[service_id == DIA_REF, trip_id], unique(stop_id)]]
paradas_sf <- st_transform(st_as_sf(paradas, coords = c("lon", "lat"), crs = 4326), CRS_UTM)


# =============================================================================
# 6. CRUZAMENTO COM POPULAÇÃO, RENDA E EMPREGOS (IPEA)
# =============================================================================

hex <- st_transform(st_read(file.path(DIR_RAW, "aop_uso_solo_2019.gpkg"), quiet = TRUE), CRS_UTM)
acc <- st_drop_geometry(st_read(file.path(DIR_RAW, "aop_acesso_tp_2019.gpkg"), quiet = TRUE))
hex <- merge(hex, acc[, c("id_hex", "CMATT60", "CMATT30", "TMISB")], by = "id_hex", all.x = TRUE)
hex$area <- as.numeric(st_area(hex))

# Fração de cada hexágono a até 500 m de uma parada (área de influência)
fracao_coberta <- function(pts) {
  if (nrow(pts) == 0) return(rep(0, nrow(hex)))
  zona <- st_union(st_buffer(pts, RAIO))
  inter <- st_intersection(hex[, "id_hex"], zona)
  a <- setNames(as.numeric(st_area(inter)), inter$id_hex)
  out <- a[hex$id_hex]; out[is.na(out)] <- 0
  pmin(out / hex$area, 1)
}
hex$cob_qualquer   <- fracao_coberta(paradas_sf[paradas_sf$atendida, ])
hex$cob_frequente  <- fracao_coberta(paradas_sf[paradas_sf$tem_frequente, ])

# Partidas no pico dentro de cada hexágono
pj <- st_join(paradas_sf[, c("stop_id", "partidas_hora")], hex[, "id_hex"], join = st_within)
part_hex <- as.data.table(st_drop_geometry(pj))[, .(partidas_hora = sum(partidas_hora), paradas = .N), by = id_hex]
hex <- merge(hex, part_hex, by = "id_hex", all.x = TRUE)
hex$partidas_hora[is.na(hex$partidas_hora)] <- 0
hex$paradas[is.na(hex$paradas)] <- 0

H <- as.data.table(st_drop_geometry(hex))
H[, c("P001", "T001", "CMATT60", "CMATT30") := lapply(.SD, as.numeric), .SDcols = c("P001", "T001", "CMATT60", "CMATT30")]
total_empregos <- sum(H$T001)
H[, quintil := factor(R002, levels = 1:5, labels = c("Q1 (20% mais pobres)", "Q2", "Q3", "Q4", "Q5 (20% mais ricos)"))]

cobertura <- rbind(
  H[, .(grupo = "Total", populacao = sum(P001),
        pct_qualquer = 100 * sum(P001 * cob_qualquer) / sum(P001),
        pct_frequente = 100 * sum(P001 * cob_frequente) / sum(P001),
        empregos_60min_pct = 100 * weighted.mean(CMATT60, P001, na.rm = TRUE) / total_empregos)],
  H[!is.na(quintil), .(populacao = sum(P001),
        pct_qualquer = 100 * sum(P001 * cob_qualquer) / sum(P001),
        pct_frequente = 100 * sum(P001 * cob_frequente) / sum(P001),
        empregos_60min_pct = 100 * weighted.mean(CMATT60, P001, na.rm = TRUE) / total_empregos),
    by = .(grupo = quintil)][order(grupo)]
)
cobertura_empregos <- H[, .(empregos = sum(T001),
                            pct_empregos_frequente = 100 * sum(T001 * cob_frequente) / sum(T001))]
print(cobertura); print(cobertura_empregos)

# População sem parada frequente a 500 m, por quintil
sem_freq <- H[!is.na(quintil), .(pessoas_sem_freq = sum(P001 * (1 - cob_frequente))), by = quintil][order(quintil)]


# =============================================================================
# 7. FIGURAS
# =============================================================================

limite <- st_union(hex)   # contorno do município = união dos hexágonos do IPEA

tema_mapa <- theme_void(base_size = 13) +
  theme(legend.position = c(0.02, 0.02), legend.justification = c(0, 0),
        legend.title = element_text(face = "bold", size = 11), legend.text = element_text(size = 10),
        plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(6, 6, 6, 6))

# 7.1 Rede: paradas com tamanho e cor pela quantidade de ônibus por hora no pico
paradas_mapa <- paradas_sf[paradas_sf$partidas_hora > 0, ]
paradas_mapa$faixa <- cut(paradas_mapa$partidas_hora, c(0, 4, 12, 30, Inf),
                          labels = c("Até 4", "4 a 12", "12 a 30", "Mais de 30"))
paradas_mapa <- paradas_mapa[order(paradas_mapa$partidas_hora), ]
g_rede <- ggplot() +
  geom_sf(data = hex, aes(fill = P001), colour = NA) +
  scale_fill_gradient(low = "#F4F4F1", high = "#B9BCB4", guide = "none") +
  geom_sf(data = limite, fill = NA, colour = COR$tinta, linewidth = 0.3) +
  geom_sf(data = paradas_mapa, aes(colour = faixa, size = faixa), alpha = 0.85) +
  scale_colour_manual(values = c("#B5D3D7", COR$azul_claro, COR$azul, COR$laranja), name = "Ônibus por hora\nna parada (pico)") +
  scale_size_manual(values = c(0.25, 0.6, 1.1, 1.8), name = "Ônibus por hora\nna parada (pico)") +
  tema_mapa
ggsave(file.path(DIR_FIG, "mapa_rede.png"), g_rede, width = 8, height = 7.2, dpi = 220, bg = "white")

# 7.2 Cobertura de serviço frequente sobre a população
H_sf <- hex
H_sf$categoria <- with(H_sf, ifelse(P001 == 0, "Sem moradores",
                       ifelse(cob_frequente >= 0.5, "Ônibus frequente a até 500 m",
                       ifelse(cob_qualquer >= 0.5, "Só ônibus pouco frequente", "Sem parada a até 500 m"))))
H_sf$categoria <- factor(H_sf$categoria, levels = c("Ônibus frequente a até 500 m", "Só ônibus pouco frequente",
                                                    "Sem parada a até 500 m", "Sem moradores"))
g_cob <- ggplot() +
  geom_sf(data = H_sf, aes(fill = categoria), colour = "white", linewidth = 0.05) +
  scale_fill_manual(values = c(COR$azul, COR$laranja, COR$vermelho, "#ECEDEA"), name = NULL, drop = FALSE) +
  geom_sf(data = limite, fill = NA, colour = COR$tinta, linewidth = 0.3) +
  tema_mapa
ggsave(file.path(DIR_FIG, "mapa_cobertura.png"), g_cob, width = 8, height = 7.2, dpi = 220, bg = "white")

# 7.3 Acessibilidade a empregos em 60 min (IPEA, calculada com GTFS de 2019)
H_sf$acc60 <- 100 * H_sf$CMATT60 / total_empregos
g_acc <- ggplot() +
  geom_sf(data = H_sf[H_sf$P001 > 0, ], aes(fill = acc60), colour = NA) +
  scale_fill_gradient(low = "#F4E3C9", high = COR$azul, name = "% dos empregos\nalcançáveis em\n60 min de ônibus", limits = c(0, 100)) +
  geom_sf(data = limite, fill = NA, colour = COR$tinta, linewidth = 0.3) +
  tema_mapa
ggsave(file.path(DIR_FIG, "mapa_acesso_empregos.png"), g_acc, width = 8, height = 7.2, dpi = 220, bg = "white")


# =============================================================================
# 8. EXPORTAÇÃO
# =============================================================================

abas <- list(
  "Qualidade do feed"   = qualidade,
  "Resumo por dia"      = resumo_dia,
  "Viagens por hora"    = viagens_hora,
  "Onibus em operacao"  = em_operacao[, .(dia, hora = sprintf("%02d:%02d", seg %/% 3600, (seg %% 3600) %/% 60), onibus)],
  "Frequencia no pico"  = dist_freq,
  "Linhas no pico"      = freq_linha[order(intervalo_min)],
  "Velocidade linhas"   = vel_linha,
  "Cobertura"           = cobertura,
  "Cobertura empregos"  = cobertura_empregos,
  "Sem servico freq"    = sem_freq
)
wb <- createWorkbook()
for (nm in names(abas)) {
  tb <- as.data.frame(abas[[nm]])
  tb[] <- lapply(tb, function(x) if (is.numeric(x)) round(x, 2) else x)
  addWorksheet(wb, nm); writeData(wb, nm, tb, headerStyle = createStyle(textDecoration = "bold", fgFill = "#DDE8EA"))
  setColWidths(wb, nm, cols = seq_along(tb), widths = "auto")
}
saveWorkbook(wb, file.path(DIR_SAIDA, "indicadores_gtfs.xlsx"), overwrite = TRUE)
cat("\nArquivos gerados em", DIR_SAIDA, "\n")
