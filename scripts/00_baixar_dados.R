# =============================================================================
# Case FNP – GTFS de Fortaleza
# Script 00: baixa as fontes de dados complementares (rodar uma vez)
# -----------------------------------------------------------------------------
# Fontes:
#   1. IPEA – Projeto Acesso a Oportunidades (pacote aopdata)
#      Grade de hexágonos H3 (resolução 9, ~0,1 km² cada) de Fortaleza com:
#        - população e renda per capita (Censo Demográfico 2010)
#        - empregos formais (RAIS 2019), escolas (Censo Escolar 2019) e
#          estabelecimentos de saúde (CNES 2019)
#        - acessibilidade por transporte público calculada pelo IPEA (2019)
#
# Obs.: o contorno do município nos mapas é a união dos próprios hexágonos do
# IPEA (o download dos limites do IBGE pelo pacote geobr travou nos testes).
#
# Saída: data/raw/*.gpkg  (os arquivos são lidos pelo script 01_analise.R)
# =============================================================================

pacotes <- c("sf", "aopdata", "data.table", "ggplot2", "openxlsx")
faltando <- setdiff(pacotes, rownames(installed.packages()))
if (length(faltando) > 0) install.packages(faltando)

suppressPackageStartupMessages({
  library(sf)
  library(data.table)
})

DIR_RAW <- file.path("data", "raw")
dir.create(DIR_RAW, showWarnings = FALSE, recursive = TRUE)
COD_FORTALEZA <- 2304400

salvar <- function(obj, nome) {
  arq <- file.path(DIR_RAW, nome)
  if (file.exists(arq)) file.remove(arq)
  sf::st_write(obj, arq, quiet = TRUE)
  cat("OK:", arq, "-", nrow(obj), "linhas\n")
}

tentar <- function(rotulo, expr) {
  tryCatch(expr, error = function(e) cat("FALHOU:", rotulo, "->", conditionMessage(e), "\n"))
}

# ---- 1. IPEA / Acesso a Oportunidades -------------------------------------------

tentar("população e renda (Censo 2010)", {
  pop <- aopdata::read_population(city = "for", year = 2010, geometry = TRUE, showProgress = FALSE)
  salvar(pop, "aop_populacao_2010.gpkg")
})

tentar("uso do solo: empregos, escolas, saúde (2019)", {
  uso <- aopdata::read_landuse(city = "for", year = 2019, geometry = TRUE, showProgress = FALSE)
  salvar(uso, "aop_uso_solo_2019.gpkg")
})

tentar("acessibilidade por transporte público (2019, pico)", {
  acc <- aopdata::read_access(city = "for", mode = "public_transport", year = 2019,
                              peak = TRUE, geometry = TRUE, showProgress = FALSE)
  salvar(acc, "aop_acesso_tp_2019.gpkg")
})

cat("\nArquivos em", DIR_RAW, ":\n")
print(list.files(DIR_RAW))
