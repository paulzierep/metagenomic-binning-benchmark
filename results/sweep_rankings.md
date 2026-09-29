# Issue #25 sweep — medium-dataset ranking

Rule: bin stats first (CheckM2 comp/cont + HQ/MQ + F1 = 2·c·p/(c+p), p = 100−cont), then wall time tiebreak. Only the winning parameter set advances to CAMI II/III human.

| Rank | Cell | Commit | Seed | Params (non-ref) | Wall | Bins | CheckM2 comp | CheckM2 cont | HQ / MQ | F1 | CheckM1 comp / cont |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `sweep_001_ref` | `95f5ea8` | 42 | reference (defaults) | 2827 | 17 | 34.22 | 4.11 | 0 / 2 | 50.44 | 32.00 / 5.31 |
