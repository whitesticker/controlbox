# System Monitor sensor groups (SMC key prefixes)

The Sensors submenu sections temperatures by physical location with `SensorGroup.of(_:)` in `SensorMonitor.swift`. Matching is on the first two characters of the SMC key, case-sensitive.

| Group | Prefixes | Source |
|---|---|---|
| CPU | `Tp`, `Te`, `TC`, `Tc` | `Tp` cores documented by Stats / macmon / smctemp (M1/M2). `TC*` look like CPU-wide summaries (`TCMz` tracks the hottest core). |
| GPU | `Tg`, `TG` | Documented. |
| SoC (other on-chip) | `Tf` | On M3 these are CPU/GPU cores; unmapped on M1/M2. The hottest M2 Max reading (`Tf06`, ~67 °C) is here. |
| Memory & storage | `TH` (except Intel `TH0P` heatsink), `TM`, `Tm` | `TH0x` is NAND in Stats. |
| Power delivery | `TP`, `TR`, `TV` | Inferred from names (PMU / regulator dies). |
| Enclosure & airflow | `Ta`, `TA`, `TS`, `Ts` | `TaFL`/`TaFR`/`TaRL`/`TaRR` are the four air corners. |
| Battery & wireless | `TB…T`, `TW` | Documented (laptops / Intel). |
| Other | everything else (`Th`, `TI`, `TB0p`, …) | Unknown. Kept visible. |

M2 Max Mac Studio (Mac14,13): 213 readings, stable across samples: CPU 60, GPU 16, SoC 40, Memory & storage 4, Power 51, Enclosure 15, Other 27.

The plausibility floor is 15 °C. At 5 °C, eight non-temperature keys got through (`Ta0D`/`Ta0H`/`Ta0L`/`Ta0W` at 9 °C, `Tf01`/`Tf11`/`Tf21`/`Tf31` at 5–11 °C).

## Do not

- Match prefixes case-insensitively. `TP*` is power delivery; `Tp*` is CPU.
- Claim a location for a prefix without a source or a clear name pattern. Put it in Other.
