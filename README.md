# [Case FNP] O que o GTFS revela sobre o transporte coletivo de Fortaleza

Case técnico para o cargo de Analista Pleno da Gerência de Mobilidade da Frente Nacional de Prefeitas e Prefeitos (FNP). Ele tem dois desafios:

1. **Por que o GTFS importa para a gestão municipal.** Uso o GTFS de Fortaleza/CE e cruzo os dados com população, renda e empregos do IPEA.
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
| Moradores a até 500 m de uma parada | 99,7% |
| Moradores a até 500 m de ônibus frequente | 79,5% (≈ 496 mil pessoas sem) |

**Por faixa de renda** (quintis de renda per capita):

| Quintil | Ônibus frequente a até 500 m | Empregos alcançáveis em 60 min de ônibus* |
|---|---|---|
| Q1 (20% mais pobres) | 72,9% | 28,3% |
| Q3 | 80,4% | 48,2% |
| Q5 (20% mais ricos) | 87,7% | 70,9% |

\* Indicador calculado pelo IPEA com a rede de 2019.

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
│   ├── 00_baixar_dados.R      baixa as bases do IPEA (rodar uma vez)
│   └── 01_analise.R           auditoria do feed, indicadores, cruzamentos, mapas
├── data/raw/
│   ├── gtfs_fortaleza.zip     GTFS enviado no case (não editar)
│   └── aop_*.gpkg             IPEA – Acesso a Oportunidades (hexágonos H3)
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
   source("scripts/00_baixar_dados.R")  # só se os .gpkg não estiverem em data/raw
   source("scripts/01_analise.R")       # cerca de 15 segundos
   ```

## Fontes

- **GTFS de Fortaleza:** arquivo enviado pela FNP no case.
- **IPEA – Projeto Acesso a Oportunidades** (pacote `aopdata`), em hexágonos H3 de cerca de 0,1 km²:
  - população e renda per capita (Censo 2010);
  - empregos formais (RAIS 2019);
  - acessibilidade por transporte público no pico (2019).

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
7. **Cruzamentos:** os resultados são separados por quintil de renda e comparados com o indicador do IPEA de empregos acessíveis em 60 minutos.

## Limitações

- O feed não tem viagens de dia útil, por isso o **sábado** é o dia de referência.
- A população é do **Censo 2010**.
- A acessibilidade do IPEA foi calculada com a rede de **2019**, não com este feed.
- As distâncias são em **linha reta**, o que subestima a caminhada real.
- O GTFS mostra a **oferta programada**, não a realizada. Para medir a realizada, seria preciso cruzar com o GPS dos ônibus.
