# Metal binding progress rate

This ledger measures committed safe/bound inventory progress. Times are Git
committer timestamps in Europe/Zagreb. `In scope` is total declarations minus
`scope-excluded`; availability-gated declarations remain in scope. Interval
rates use the exact elapsed wall time between commits. Percentage-point rates
use each row's contemporaneous completion percentage, so an audited exclusion
can change the denominator explicitly rather than being hidden.

| Commit | Timestamp | Bound | In scope | Bound % | Δ bound | Hours | Bound/hour | pp/hour |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `d0a2d79` | 2026-08-23 19:44:03 +02:00 | 1,847 | 5,259 | 35.1207% | — | — | — | — |
| `6ec742f` | 2026-08-23 20:16:11 +02:00 | 1,899 | 5,259 | 36.1095% | 52 | 0.536 | 97.1 | 1.85 |
| `ef257b8` | 2026-08-23 20:30:57 +02:00 | 2,359 | 5,259 | 44.8564% | 460 | 0.246 | 1,869.1 | 35.54 |
| `ee47ef0` | 2026-08-23 20:37:00 +02:00 | 2,494 | 5,259 | 47.4235% | 135 | 0.101 | 1,338.8 | 25.46 |
| `5061a4b` | 2026-08-23 20:44:28 +02:00 | 2,527 | 5,249 | 48.1425% | 33 | 0.124 | 265.2 | 5.78 |
| `c36fe2c` | 2026-08-23 20:56:35 +02:00 | 2,623 | 5,249 | 49.9714% | 96 | 0.202 | 475.4 | 9.06 |
| `5d06dd9` | 2026-08-23 21:03:58 +02:00 | 2,691 | 5,249 | 51.2669% | 68 | 0.123 | 552.6 | 10.53 |
| `c636970` | 2026-08-23 21:12:09 +02:00 | 2,792 | 5,249 | 53.1911% | 101 | 0.136 | 740.5 | 14.11 |
| `21420ef` | 2026-08-23 21:19:59 +02:00 | 2,903 | 5,249 | 55.3058% | 111 | 0.131 | 850.2 | 16.20 |
| `c5a2947` | 2026-08-23 21:41:36 +02:00 | 3,322 | 5,249 | 63.2882% | 419 | 0.360 | 1,163.0 | 22.16 |
| `2745475` | 2026-08-23 22:06:02 +02:00 | 3,468 | 5,249 | 66.0697% | 146 | 0.407 | 358.5 | 6.83 |

## Current measured rate

- Since the bulk-value pivot at `6ec742f`: 1,569 additional bound declarations
  in 1.831 hours, or **857.0 declarations/hour** and **16.36 percentage
  points/hour**.
- Latest completed interval (`c5a2947` through `2745475`): 146 declarations in
  0.407 hours, or **358.5 declarations/hour** and **6.83 percentage
  points/hour**.

Rates describe completed commits, not forecasts. Hardware-only gates and
complex ownership features will vary materially from pure-value batches.
