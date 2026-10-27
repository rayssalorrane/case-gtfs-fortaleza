# =============================================================================
# Case FNP – GTFS de Fortaleza
# Script 00: baixa as fontes de dados complementares (rodar uma vez)
# -----------------------------------------------------------------------------
# Fontes:
#   1. IPEA – Projeto Acesso a Oportunidades (pacote aopdata)
#      Grade de hexágonos H3 (resolução 9, ~0,1 km² cada) de Fortaleza com:
#        - empregos formais (RAIS 2019), escolas (Censo Escolar 2019) e
#          estabelecimentos de saúde (CNES 2019)
#        - acessibilidade por transporte público calculada pelo IPEA (2019)
#        - população e renda do Censo 2010 (só para comparação)
#   2. IBGE – Censo Demográfico 2022, agregados por setor censitário
#      população e renda de 2022 (usadas na análise)
#
# Obs.: o contorno do município nos mapas é a união dos próprios hexágonos do
# IPEA (o download dos limites do IBGE pelo pacote geobr travou nos testes).
#
# Saída: data/raw/*.gpkg e data/raw/censo2022/ (lidos pelo script 01_analise.R)
# Arquivos já baixados não são baixados de novo.
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

ja_tem <- function(nome) file.exists(file.path(DIR_RAW, nome))

if (!ja_tem("aop_populacao_2010.gpkg")) tentar("população e renda (Censo 2010)", {
  pop <- aopdata::read_population(city = "for", year = 2010, geometry = TRUE, showProgress = FALSE)
  salvar(pop, "aop_populacao_2010.gpkg")
})

if (!ja_tem("aop_uso_solo_2019.gpkg")) tentar("uso do solo: empregos, escolas, saúde (2019)", {
  uso <- aopdata::read_landuse(city = "for", year = 2019, geometry = TRUE, showProgress = FALSE)
  salvar(uso, "aop_uso_solo_2019.gpkg")
})

if (!ja_tem("aop_acesso_tp_2019.gpkg")) tentar("acessibilidade por transporte público (2019, pico)", {
  acc <- aopdata::read_access(city = "for", mode = "public_transport", year = 2019,
                              peak = TRUE, geometry = TRUE, showProgress = FALSE)
  salvar(acc, "aop_acesso_tp_2019.gpkg")
})

# ---- 2. IBGE / Censo Demográfico 2022 (setores censitários) ----------------------
# População e renda de 2022 por setor censitário. O script 01 redistribui esses
# valores nos hexágonos do IPEA, proporcionalmente à área.

options(timeout = 1200)
DIR_CENSO <- file.path(DIR_RAW, "censo2022")
dir.create(DIR_CENSO, showWarnings = FALSE, recursive = TRUE)
FTP <- "https://ftp.ibge.gov.br/Censos/Censo_Demografico_2022/Agregados_por_Setores_Censitarios"
baixar <- function(url, nome) {
  arq <- file.path(DIR_CENSO, nome)
  if (!file.exists(arq)) download.file(url, arq, mode = "wb", quiet = TRUE)
  cat("OK:", arq, "-", round(file.size(arq) / 1e6, 1), "MB\n")
}

tentar("malha de setores do Ceará com atributos (Censo 2022)", baixar(
  paste0(FTP, "/malha_com_atributos/setores/gpkg/UF/CE/CE_setores_CD2022.gpkg"), "CE_setores_CD2022.gpkg"))
tentar("agregados por setor: básico (Censo 2022)", baixar(
  paste0(FTP, "/Agregados_por_Setor_csv/Agregados_por_setores_basico_BR_20260520.zip"), "agregados_basico_BR.zip"))
tentar("dicionário de dados (Censo 2022)", baixar(
  paste0(FTP, "/dicionario_de_dados_agregados_por_setores_censitarios_20260520.xlsx"), "dicionario_agregados_setores.xlsx"))

FTP_RENDA <- "https://ftp.ibge.gov.br/Censos/Censo_Demografico_2022/Agregados_por_Setores_Censitarios_Rendimento_do_Responsavel"
tentar("rendimento do responsável por setor (Censo 2022)", baixar(
  paste0(FTP_RENDA, "/Agregados_por_setores_renda_responsavel_BR_20260508_csv.zip"), "agregados_renda_responsavel_BR.zip"))
tentar("dicionário do rendimento (Censo 2022)", baixar(
  paste0(FTP_RENDA, "/dicionario_de_dados_renda_responsavel_20260508.xlsx"), "dicionario_renda_responsavel.xlsx"))

cat("\nArquivos em", DIR_RAW, ":\n")
print(list.files(DIR_RAW))
