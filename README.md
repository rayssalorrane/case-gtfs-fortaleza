# [Case FNP] O que o GTFS revela sobre o transporte coletivo de Fortaleza

Case técnico para o cargo de Analista Pleno da Gerência de Mobilidade da Frente Nacional de Prefeitas e Prefeitos (FNP). Ele tem dois desafios:

1. **Por que o GTFS importa para a gestão municipal.** Uso o GTFS de Fortaleza/CE e cruzo os dados com população e renda do Censo 2022 (IBGE) e com empregos e acessibilidade do IPEA.
2. **Como apoiar um município a construir e publicar o seu GTFS.** A proposta está na apresentação, em `docs/`.

## Principais resultados

Os números são de um sábado, que é o dia de referência (veja as limitações).

| Indicador | Valor |
|---|---|
| Linhas em operação / viagens | 273 / 20.656 |
| Quilômetros programados | 212 mil |
| Pico de ônibus rodando ao mesmo tempo | 948 (às 07h40) |
| Velocidade mediana das viagens | 15,4 km/h |
| Linhas-sentido com ônibus a cada 15 min ou menos no pico (6h–8h) | 22% |
| Moradores a até 500 m de uma parada | 99,3% |
| Moradores a até 500 m de ônibus frequente | 76,8% (≈ 561 mil pessoas sem) |

**Por faixa de renda** (quintis do rendimento médio do responsável pelo domicílio, Censo 2022; cada quintil reúne cerca de 20% da população):

| Quintil | Renda média do responsável | Ônibus frequente a até 500 m | Empregos alcançáveis em 60 min de ônibus* |
|---|---|---|---|
| Q1 (20% mais pobres) | R$ 1.280 | 71,6% | 29,8% |
| Q2 | R$ 1.547 | 78,2% | 38,7% |
| Q3 | R$ 1.940 | 72,6% | 44,0% |
| Q4 | R$ 2.757 | 77,8% | 54,2% |
| Q5 (20% mais ricos) | R$ 7.471 | 84,0% | 67,5% |

\* Indicador calculado pelo IPEA com a rede de 2019, ponderado pela população de 2022.

**Qualidade do feed recebido:**
- não há viagens de dia útil: o serviço existe no calendário, mas nenhuma viagem o usa;
- o calendário venceu em 03/07/2026;
- os campos `direction_id`, `trip_headsign`, `block_id` e `wheelchair_boarding` estão 100% vazios;
- 7% das viagens apontam para um trajeto (`shape`) muito maior que o percurso real, nas linhas circulares;
- 45 linhas estão cadastradas sem nenhuma viagem.

## Estrutura

```
├── case-gtfs-fortaleza.Rproj
├── scripts/
│   ├── 00_baixar_dados.R      baixa as bases do IPEA e do IBGE (rodar uma vez)
│   └── 01_analise.R           auditoria do feed, indicadores, cruzamentos, mapas
├── data/raw/
│   ├── gtfs_fortaleza.zip     GTFS enviado no case (não editar)
│   ├── aop_*.gpkg             IPEA – Acesso a Oportunidades (hexágonos H3)
│   └── censo2022/             IBGE – setores censitários, população e renda (Censo 2022)
├── output/
│   ├── indicadores_gtfs.xlsx  todas as tabelas (qualidade, oferta, frequência, cobertura…)
│   └── figuras/               mapas da rede, da cobertura e do acesso a empregos
└── docs/
    └── apresentacao_case_fnp.pptx   apresentação de 10 min (roteiro nas notas)
```

## Como rodar

1. Abra o `case-gtfs-fortaleza.Rproj` no RStudio.
2. Restaure os pacotes com `renv::restore()`. Se preferir, instale direto:
   ```r
   install.packages(c("sf", "aopdata", "data.table", "ggplot2", "openxlsx"))
   ```
3. Rode os scripts:
   ```r
   source("scripts/00_baixar_dados.R")  # só baixa o que ainda não estiver em data/raw
   source("scripts/01_analise.R")       # cerca de 15 segundos
   ```

## Fontes

- **GTFS de Fortaleza:** arquivo enviado pela FNP no case.
- **IBGE – Censo Demográfico 2022, agregados por setor censitário:**
  - população (tema Básico, `v0001`);
  - rendimento nominal médio mensal do responsável pelo domicílio (`V06004`) e número de responsáveis (`V06001`);
  - malha de setores do Ceará.
- **IPEA – Projeto Acesso a Oportunidades** (pacote `aopdata`), em hexágonos H3 de cerca de 0,1 km²:
  - empregos formais (RAIS 2019);
  - acessibilidade por transporte público no pico (2019);
  - população do Censo 2010, usada só para comparação (aba "Censo 2022 x 2010" da planilha).

## Método

1. **Auditoria do feed:** contagens, campos vazios, calendário, linhas sem viagem e consistência entre trajeto e paradas.
2. **Horários:** os horários das paradas intermediárias são interpolados entre os pontos de controle.
3. **Sentido:** vem do sufixo do `shape_id` (`-I` = ida, `-V` = volta), porque `direction_id` está vazio.
4. **Oferta:**
   - viagens e ônibus em operação, calculados a cada 5 minutos;
   - distância medida pela sequência de paradas;
   - velocidade = distância ÷ duração.
5. **Frequência no pico (sábado, 6h–8h):** intervalo médio = 120 min ÷ viagens, por linha e sentido.
6. **Cobertura:** parte de cada hexágono a até 500 m (em linha reta) de uma parada:
   - de qualquer parada atendida;
   - ou de uma parada com linha de intervalo ≤ 15 min.

   A população é ponderada por essa área.
7. **Censo 2022 nos hexágonos:** cada setor censitário é repartido entre os hexágonos que toca, proporcionalmente à área (interpolação areal). A renda do hexágono é a média dos setores, ponderada pelo número de responsáveis.
8. **Cruzamentos:** os hexágonos são ordenados pela renda e divididos em cinco grupos com cerca de 20% da população cada. Em cada grupo calculo a cobertura e o indicador do IPEA de empregos acessíveis em 60 minutos.

## Limitações

- O feed não tem viagens de dia útil, por isso o **sábado** é o dia de referência.
- A renda de 2022 é o **rendimento médio do responsável** pelo domicílio, não a renda per capita. É a medida que o IBGE divulga por setor.
- A população é repartida pela **área** do setor, como se fosse uniforme dentro dele. Em setores grandes e pouco ocupados, isso espalha moradores por áreas vazias.
- Os empregos (RAIS) e a acessibilidade do IPEA são de **2019**. A acessibilidade foi calculada com a rede daquele ano, não com este feed.
- As distâncias são em **linha reta**, o que subestima a caminhada real.
- O GTFS mostra a **oferta programada**, não a realizada. Para medir a realizada, seria preciso cruzar com o GPS dos ônibus.
