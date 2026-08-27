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
| `8803184` | 2026-08-23 22:09:18 +02:00 | 3,487 | 5,249 | 66.4317% | 19 | 0.054 | 349.0 | 6.65 |
| `55de0e5` | 2026-08-23 22:14:03 +02:00 | 3,493 | 5,249 | 66.5460% | 6 | 0.079 | 75.8 | 1.44 |
| `5cf30a7` | 2026-08-23 22:15:39 +02:00 | 3,495 | 5,249 | 66.5841% | 2 | 0.027 | 75.0 | 1.43 |
| `026d6bb` | 2026-08-23 22:30:52 +02:00 | 3,519 | 5,249 | 67.0413% | 24 | 0.254 | 94.6 | 1.80 |
| `a1d3497` | 2026-08-23 22:45:11 +02:00 | 3,538 | 5,249 | 67.4033% | 19 | 0.239 | 79.6 | 1.52 |
| `a47704c` | 2026-08-23 23:11:52 +02:00 | 3,572 | 5,249 | 68.0511% | 34 | 0.445 | 76.5 | 1.46 |
| `0783b4a` | 2026-08-23 23:26:14 +02:00 | 3,581 | 5,249 | 68.2225% | 9 | 0.239 | 37.6 | 0.72 |
| `eb4acbe` | 2026-08-23 23:44:59 +02:00 | 3,622 | 5,249 | 69.0036% | 41 | 0.313 | 131.2 | 2.50 |
| `dd9db52` | 2026-08-23 23:56:46 +02:00 | 3,679 | 5,249 | 70.0895% | 57 | 0.196 | 290.2 | 5.53 |
| `4b63fd8` | 2026-08-24 00:01:32 +02:00 | 3,699 | 5,249 | 70.4706% | 20 | 0.079 | 251.7 | 4.80 |
| `829cd82` | 2026-08-24 00:09:54 +02:00 | 3,736 | 5,249 | 71.1755% | 37 | 0.139 | 265.3 | 5.06 |
| `7f5325b` | 2026-08-24 00:17:12 +02:00 | 3,784 | 5,249 | 72.0899% | 48 | 0.122 | 394.5 | 7.52 |
| `df6b9c7` | 2026-08-24 00:24:50 +02:00 | 3,814 | 5,249 | 72.6615% | 30 | 0.127 | 235.8 | 4.49 |
| `5ef3d9f` | 2026-08-24 00:31:11 +02:00 | 3,831 | 5,249 | 72.9853% | 17 | 0.106 | 160.6 | 3.06 |
| `785f1c8` | 2026-08-24 00:40:42 +02:00 | 3,877 | 5,249 | 73.8617% | 46 | 0.159 | 290.0 | 5.53 |
| `bbd17cb` | 2026-08-24 00:46:01 +02:00 | 3,886 | 5,249 | 74.0331% | 9 | 0.089 | 101.6 | 1.93 |
| `94d7ce3` | 2026-08-24 00:53:09 +02:00 | 3,892 | 5,249 | 74.1475% | 6 | 0.119 | 50.5 | 0.96 |
| `cd89d0e` | 2026-08-24 00:54:55 +02:00 | 3,897 | 5,249 | 74.2427% | 5 | 0.029 | 169.8 | 3.24 |
| `4631d87` | 2026-08-24 01:01:06 +02:00 | 3,902 | 5,249 | 74.3380% | 5 | 0.103 | 48.5 | 0.92 |
| `6f72d77` | 2026-08-24 01:03:19 +02:00 | 3,953 | 5,249 | 75.3096% | 51 | 0.037 | 1,380.5 | 26.30 |
| `0263869` | 2026-08-24 01:12:19 +02:00 | 3,988 | 5,249 | 75.9764% | 35 | 0.150 | 233.3 | 4.45 |
| `51504aa` | 2026-08-24 01:13:50 +02:00 | 3,990 | 5,249 | 76.0145% | 2 | 0.025 | 79.1 | 1.51 |
| `1c44e05` | 2026-08-24 01:26:53 +02:00 | 4,022 | 5,249 | 76.6241% | 32 | 0.218 | 147.1 | 2.80 |
| `c77248b` | 2026-08-24 01:29:36 +02:00 | 4,029 | 5,249 | 76.7575% | 7 | 0.045 | 154.6 | 2.95 |
| `03e08b6` | 2026-08-24 01:37:14 +02:00 | 4,035 | 5,249 | 76.8718% | 6 | 0.127 | 47.2 | 0.90 |
| `49c5e5e` | 2026-08-24 01:39:17 +02:00 | 4,038 | 5,249 | 76.9290% | 3 | 0.034 | 87.8 | 1.67 |
| `f2acf58` | 2026-08-24 01:42:05 +02:00 | 4,049 | 5,249 | 77.1385% | 11 | 0.047 | 235.7 | 4.49 |
| `063f0a7` | 2026-08-24 01:47:14 +02:00 | 4,056 | 5,249 | 77.2719% | 7 | 0.086 | 81.6 | 1.55 |
| `5b645d2` | 2026-08-24 01:51:23 +02:00 | 4,058 | 5,249 | 77.3100% | 2 | 0.069 | 28.9 | 0.55 |
| `50e2241` | 2026-08-24 01:57:43 +02:00 | 4,066 | 5,249 | 77.4624% | 8 | 0.106 | 75.8 | 1.44 |
| `f9719e0` | 2026-08-24 02:01:48 +02:00 | 4,071 | 5,249 | 77.5576% | 5 | 0.068 | 73.5 | 1.40 |
| `efe050e` | 2026-08-24 02:05:22 +02:00 | 4,073 | 5,249 | 77.5957% | 2 | 0.059 | 33.6 | 0.64 |
| `ded7e75` | 2026-08-24 02:07:14 +02:00 | 4,078 | 5,249 | 77.6910% | 5 | 0.031 | 160.7 | 3.06 |
| `c011b53` | 2026-08-24 02:14:42 +02:00 | 4,103 | 5,249 | 78.1673% | 25 | 0.124 | 200.9 | 3.83 |
| `e7673ec` | 2026-08-24 02:17:54 +02:00 | 4,109 | 5,249 | 78.2816% | 6 | 0.053 | 112.5 | 2.14 |
| `73655a2` | 2026-08-24 02:20:36 +02:00 | 4,110 | 5,249 | 78.3006% | 1 | 0.045 | 22.2 | 0.42 |
| `f89f0f3` | 2026-08-24 02:23:14 +02:00 | 4,113 | 5,249 | 78.3578% | 3 | 0.044 | 68.4 | 1.30 |
| `c6f6d8f` | 2026-08-24 02:26:21 +02:00 | 4,114 | 5,249 | 78.3768% | 1 | 0.052 | 19.3 | 0.37 |
| `6a65a93` | 2026-08-24 02:32:39 +02:00 | 4,136 | 5,249 | 78.7951% | 22 | 0.105 | 209.5 | 3.99 |
| `810e80b` | 2026-08-24 02:35:58 +02:00 | 4,145 | 5,249 | 78.9665% | 9 | 0.055 | 162.8 | 3.10 |
| `9d3268c` | 2026-08-24 02:37:14 +02:00 | 4,149 | 5,249 | 79.0427% | 4 | 0.021 | 189.5 | 3.61 |
| `ec741f8` | 2026-08-24 02:39:46 +02:00 | 4,150 | 5,249 | 79.0610% | 1 | 0.042 | 23.7 | 0.45 |
| `c41908b` | 2026-08-24 02:54:36 +02:00 | 4,196 | 5,249 | 79.9390% | 46 | 0.247 | 186.1 | 3.55 |
| `74f45c8` | 2026-08-24 03:02:05 +02:00 | 4,271 | 5,249 | 81.3679% | 75 | 0.125 | 601.3 | 11.46 |
| `0f532bb` | 2026-08-24 03:10:25 +02:00 | 4,276 | 5,249 | 81.4631% | 5 | 0.139 | 36.0 | 0.69 |
| `7957cbc` | 2026-08-24 03:20:16 +02:00 | 4,317 | 5,249 | 82.2442% | 41 | 0.164 | 249.7 | 4.76 |
| `3d06043` | 2026-08-24 03:25:50 +02:00 | 4,322 | 5,249 | 82.3395% | 5 | 0.093 | 53.9 | 1.03 |
| `5d4f53e` | 2026-08-24 03:32:48 +02:00 | 4,354 | 5,249 | 82.9491% | 32 | 0.116 | 275.6 | 5.25 |
| `2f0e093` | 2026-08-24 03:38:43 +02:00 | 4,404 | 5,249 | 83.9017% | 50 | 0.099 | 507.0 | 9.66 |
| `dcc984c` | 2026-08-24 03:42:33 +02:00 | 4,428 | 5,249 | 84.3589% | 24 | 0.064 | 375.7 | 7.14 |
| `f11e257` | 2026-08-24 03:45:28 +02:00 | 4,440 | 5,249 | 84.5875% | 12 | 0.049 | 246.9 | 4.70 |
| `4e9c4cf` | 2026-08-24 04:02:32 +02:00 | 4,474 | 5,249 | 85.2543% | 34 | 0.284 | 119.5 | 2.35 |
| `853523e` | 2026-08-24 04:11:40 +02:00 | 4,479 | 5,249 | 85.3496% | 5 | 0.152 | 32.9 | 0.63 |
| `aede554` | 2026-08-24 04:22:07 +02:00 | 4,499 | 5,249 | 85.7116% | 20 | 0.174 | 114.9 | 2.08 |
| `63872ed` | 2026-08-24 04:31:01 +02:00 | 4,504 | 5,249 | 85.8068% | 5 | 0.148 | 33.7 | 0.64 |
| `c5aa2e0` | 2026-08-24 04:46:20 +02:00 | 4,511 | 5,249 | 85.9402% | 7 | 0.255 | 27.4 | 0.52 |
| `dca23b5` | 2026-08-24 04:46:52 +02:00 | 4,530 | 5,249 | 86.3022% | 19 | 0.009 | 2,137.5 | 40.72 |
| `de577af` | 2026-08-24 04:54:57 +02:00 | 4,537 | 5,249 | 86.4355% | 7 | 0.135 | 52.0 | 0.99 |
| `695a9ce` | 2026-08-24 04:55:52 +02:00 | 4,554 | 5,249 | 86.7594% | 17 | 0.015 | 1,112.7 | 21.20 |
| `2c5b055` | 2026-08-24 05:02:19 +02:00 | 4,565 | 5,249 | 86.9690% | 11 | 0.108 | 102.3 | 1.95 |
| `45aec54` | 2026-08-24 05:03:56 +02:00 | 4,581 | 5,249 | 87.2738% | 16 | 0.027 | 593.8 | 11.31 |
| `dac5e94` | 2026-08-24 05:15:05 +02:00 | 4,601 | 5,249 | 87.6548% | 20 | 0.186 | 107.6 | 2.05 |
| `ace712c` | 2026-08-24 05:30:15 +02:00 | 4,628 | 5,249 | 88.1692% | 27 | 0.253 | 106.8 | 2.03 |
| `06dddcd` | 2026-08-24 05:34:45 +02:00 | 4,636 | 5,249 | 88.3216% | 8 | 0.075 | 106.7 | 2.03 |
| `75fc60d` | 2026-08-24 05:35:05 +02:00 | 4,648 | 5,249 | 88.5502% | 12 | 0.006 | 2,160.0 | 41.15 |
| `1e94190` | 2026-08-24 05:46:45 +02:00 | 4,694 | 5,249 | 89.4266% | 46 | 0.194 | 236.6 | 4.51 |
| `c902d91` | 2026-08-24 05:53:22 +02:00 | 4,707 | 5,249 | 89.6742% | 13 | 0.110 | 117.9 | 2.25 |
| `d9a8c22` | 2026-08-24 05:56:57 +02:00 | 4,714 | 5,249 | 89.8076% | 7 | 0.060 | 117.2 | 2.23 |
| `1ffcebc` | 2026-08-24 06:03:38 +02:00 | 4,726 | 5,249 | 90.0362% | 12 | 0.111 | 107.7 | 2.05 |
| `4b8d84f` | 2026-08-24 06:04:07 +02:00 | 4,734 | 5,249 | 90.1886% | 8 | 0.008 | 993.1 | 18.92 |
| `7db4815` | 2026-08-24 06:07:52 +02:00 | 4,746 | 5,249 | 90.4172% | 12 | 0.063 | 192.0 | 3.66 |
| `b7eb05e` | 2026-08-24 06:14:12 +02:00 | 4,749 | 5,249 | 90.4744% | 3 | 0.106 | 28.4 | 0.54 |
| `d9e29ab` | 2026-08-24 06:15:05 +02:00 | 4,781 | 5,249 | 91.0840% | 32 | 0.015 | 2,173.6 | 41.41 |
| `515b39e` | 2026-08-24 06:16:52 +02:00 | 4,783 | 5,249 | 91.1221% | 2 | 0.030 | 67.3 | 1.28 |
| `17b3e11` | 2026-08-24 06:19:09 +02:00 | 4,786 | 5,249 | 91.1793% | 3 | 0.038 | 78.8 | 1.50 |
| `8edb1ca` | 2026-08-24 06:20:14 +02:00 | 4,792 | 5,249 | 91.2936% | 6 | 0.018 | 332.3 | 6.33 |
| `e311890` | 2026-08-24 06:21:30 +02:00 | 4,816 | 5,249 | 91.7508% | 24 | 0.021 | 1,136.8 | 21.66 |
| `691c559` | 2026-08-24 06:28:35 +02:00 | 4,838 | 5,249 | 92.1699% | 22 | 0.118 | 186.4 | 3.55 |
| `65ea228` | 2026-08-24 06:30:36 +02:00 | 4,855 | 5,249 | 92.4938% | 17 | 0.034 | 505.8 | 9.64 |
| `533e89c` | 2026-08-24 06:35:51 +02:00 | 4,881 | 5,249 | 92.9891% | 26 | 0.088 | 297.1 | 5.66 |
| `a7228f7` | 2026-08-24 06:43:15 +02:00 | 4,892 | 5,249 | 93.1987% | 11 | 0.123 | 89.2 | 1.70 |
| `21ad4be` | 2026-08-24 06:45:06 +02:00 | 4,912 | 5,249 | 93.5797% | 20 | 0.031 | 648.6 | 12.36 |
| `97f7572` | 2026-08-24 06:47:14 +02:00 | 4,919 | 5,249 | 93.7131% | 7 | 0.036 | 196.9 | 3.75 |
| `881a8f8` | 2026-08-24 06:57:17 +02:00 | 4,936 | 5,249 | 94.0370% | 17 | 0.168 | 101.5 | 1.93 |
| `c91a76c` | 2026-08-24 07:06:29 +02:00 | 4,939 | 5,249 | 94.0941% | 3 | 0.153 | 19.6 | 0.37 |
| `6e8a215` | 2026-08-24 07:07:45 +02:00 | 4,949 | 5,249 | 94.2846% | 10 | 0.021 | 473.7 | 9.02 |
| `f9642fa` | 2026-08-24 07:09:15 +02:00 | 4,953 | 5,249 | 94.3608% | 4 | 0.025 | 160.0 | 3.05 |
| `1796450` | 2026-08-24 07:14:44 +02:00 | 4,959 | 5,249 | 94.4751% | 6 | 0.091 | 65.6 | 1.25 |
| `bb6d5c6` | 2026-08-24 07:15:30 +02:00 | 4,969 | 5,249 | 94.6657% | 10 | 0.013 | 782.6 | 14.91 |
| `0f05773` | 2026-08-24 07:18:24 +02:00 | 4,973 | 5,249 | 94.7419% | 4 | 0.048 | 82.8 | 1.58 |
| `203d6ef` | 2026-08-24 07:21:30 +02:00 | 4,981 | 5,249 | 94.8943% | 8 | 0.052 | 154.8 | 2.95 |
| `110c501` | 2026-08-24 07:31:37 +02:00 | 4,995 | 5,249 | 95.1610% | 14 | 0.169 | 82.8 | 1.58 |
| `b3cee1e` | 2026-08-27 09:58:21 +02:00 | 4,998 | 5,249 | 95.2181% | 3 | 74.446 | 0.0 | 0.00 |
| `71f26eb` | 2026-08-27 09:59:13 +02:00 | 5,000 | 5,249 | 95.2562% | 2 | 0.014 | 138.5 | 2.64 |
| `23a449c` | 2026-08-27 10:08:39 +02:00 | 5,058 | 5,249 | 96.3612% | 58 | 0.157 | 369.4 | 7.04 |
| `18b6566` | 2026-08-27 10:11:20 +02:00 | 5,069 | 5,249 | 96.5708% | 11 | 0.045 | 246.0 | 4.69 |
| `75f55a1` | 2026-08-27 10:16:49 +02:00 | 5,083 | 5,249 | 96.8375% | 14 | 0.091 | 153.2 | 2.92 |
| `be44eaf` | 2026-08-27 10:20:55 +02:00 | 5,088 | 5,249 | 96.9327% | 5 | 0.068 | 73.2 | 1.39 |
| `7ca877f` | 2026-08-27 10:21:52 +02:00 | 5,095 | 5,249 | 97.0661% | 7 | 0.016 | 442.1 | 8.42 |
| `cccf729` | 2026-08-27 10:22:53 +02:00 | 5,105 | 5,249 | 97.2566% | 10 | 0.017 | 590.2 | 11.24 |
| `0dfc9ce` | 2026-08-27 10:24:40 +02:00 | 5,108 | 5,249 | 97.3138% | 3 | 0.030 | 100.9 | 1.92 |
| `813e1da` | 2026-08-27 10:25:05 +02:00 | 5,115 | 5,249 | 97.4471% | 7 | 0.007 | 1,008.0 | 19.20 |
| `544c2c2` | 2026-08-27 10:25:50 +02:00 | 5,120 | 5,249 | 97.5424% | 5 | 0.013 | 400.0 | 7.62 |
| `ea48261` | 2026-08-27 10:28:05 +02:00 | 5,122 | 5,249 | 97.5805% | 2 | 0.038 | 53.3 | 1.02 |
| `6ef8001` | 2026-08-27 10:30:12 +02:00 | 5,128 | 5,249 | 97.6948% | 6 | 0.035 | 170.1 | 3.24 |
| `ef44024` | 2026-08-27 10:31:03 +02:00 | 5,142 | 5,249 | 97.9615% | 14 | 0.014 | 988.2 | 18.83 |
| `94307e9` | 2026-08-27 10:32:44 +02:00 | 5,146 | 5,249 | 98.0377% | 4 | 0.028 | 142.6 | 2.72 |
| `4cfee19` | 2026-08-27 10:35:01 +02:00 | 5,149 | 5,249 | 98.0949% | 3 | 0.038 | 78.8 | 1.50 |
| `daaf52c` | 2026-08-27 10:41:25 +02:00 | 5,174 | 5,249 | 98.5712% | 25 | 0.107 | 234.4 | 4.47 |
| `a931f53` | 2026-08-27 10:43:23 +02:00 | 5,202 | 5,249 | 99.1046% | 28 | 0.033 | 854.2 | 16.27 |
| `78a4724` | 2026-08-27 10:49:33 +02:00 | 5,205 | 5,249 | 99.1617% | 3 | 0.103 | 29.2 | 0.56 |

## Current measured rate

- Since the bulk-value pivot at `6ec742f`: 3,037 additional bound declarations
  in 10.686 hours, or **284.2 declarations/hour** and **5.42 percentage
  points/hour**.
- Latest completed interval (`97f7572` through `881a8f8`): 17 declarations in
  0.168 hours, or **101.5 declarations/hour** and **1.93 percentage
  points/hour**.

The `74f45c8` safe handoff covers 76 Presentation declarations, but its inventory
delta is 75: `method:-[MTLCommandBuffer resourceStateCommandEncoderWithDescriptor:]`
was already bound by the Resource100 closure and is recorded as the one explicit
cross-batch overlap.

The Tensor47 closure likewise has one intentional overlap: the buffer-backed
constructor was already bound by Resource100. Its two Tensor promotion commits
therefore move 46 new declarations while proving all 47 safe IDs.

The `21ad4be` inventory write is one intentionally combined promotion interval:
10 declarations are the exact Event10 listener/export/notification closure and
10 are the final IO scratch/load closure. Its interval delta is exactly 20; the
37 scope-excluded SDK declarations remain outside the frozen 5,249 in-scope
denominator.

The `881a8f8` inventory write is another coordinated promotion interval. It
moves exactly 17 declarations: Drawable8, LogState7, and BinaryArchive2. The
LogState portion is independently pinned as descriptor6 plus handler1 and is
backed by real safe construction/cancellation, a persistent 40,000-delivery
native gate, and in-flight cancellation draining; no declaration is counted in
more than one of the three closures.

The `c91a76c` interval moves exactly three FunctionConstantValues declarations.
The safe layer validates scalar byte widths and index/range cardinality before
one native mutation, copies caller-owned bytes, and proves both the copied
`7,11` values (`711` GPU output) and reset state (`0` output) through real Metal
function specialization and compute dispatch.

The `f9642fa` interval moves the exact FunctionDescriptor4 closure: the
intersection descriptor class plus the binary-archive getter, setter, and
property companion. Public provenance is backed by copied archive-list
ownership, same-device/live validation, parent retention, nil-list semantics,
and real descriptor-based function creation.

The `1796450` interval moves the exact Fence6 protocol/type closure. Its owned
device constructor, copied nullable label, checked device identity, encoder
state validation, and completion retention are exercised by 256 real producer
and consumer blit command-buffer ordering iterations.

The `0f05773` interval moves the exact IndirectCommandBuffer4 closure. It proves
the opaque GPU resource identity and indexed render-command acquisition through
the public owned parent/child graph, with checked bounds, retained resources,
indirect-capable pipeline validation, and a real native framebuffer result.

The `203d6ef` interval moves the exact Argument8 immutable reflection closure.
The safe representation copies recursive struct/member, pointer, and array
metadata before native owners die, bounds traversal and unwind, preserves
nullable children, and only materializes tensor reflection behind the native
macOS 26 availability check.

The `110c501` interval is an intentional coordinated promotion of fourteen
declarations: Library8 contributes exactly eight, the Metal 4 render-pipeline
reset closure contributes two, and Pipeline4 contributes four copied buffer-
descriptor class/array operations. Library8 exposes copied immutable attribute and
function-reflection snapshots while keeping autoreleasing typedef conventions
private; bounded exactly-once cancellable tasks capture exceptions, and real
safe plus native compute/render fixtures prove callback and owner lifetimes.

The `b3cee1e` inventory snapshot includes three declarations beyond the prior
ledger row; exactly two are attributable to MTL4Counters2: the public immutable
counter-heap descriptor class and owned counter-heap protocol. Copied labels,
checked ranges, invalidation/resolution, retained device lifetime, and a real
timestamp-heap fixture prove the closure. The remaining declaration belongs to
an intervening independently promoted closure and is not attributed here.

The `71f26eb` interval moves the exact FunctionLog2 protocol closure. Public
values are immutable diagnostics copied while their completed command and real
log container remain alive; guarded typed enumeration rejects incompatible
entries without assuming runtime protocol conformance, and preserves nullable
function, location, URL, name, and encoder-label fields.

The `23a449c` interval intentionally combines RenderCommandEncoder33 with one
already-proven Fence declaration and the exact RenderPass24 closure. Render33
contributes exactly 33 IDs: thirty typed draw/binding/counter selectors plus the
encoder protocol and two indirect argument layouts. Owned buffers, samplers,
and counter samples remain retained through completion; ranges, strides,
devices, command state, and capability requirements are checked, with exact
package/native gates and a real framebuffer fixture. The Fence lane contributes
one independently validated declaration. RenderPass24 contributes exactly 24
IDs: three classes, fifteen methods, and six property declarations covering
copied color/sample descriptors, nullable resolve textures and sample buffers,
checked device/range/default reset semantics, completion retention, and real
render/resolve conformance.

The `75f55a1` interval moves the exact IndirectCommandEncoder14 closure: twelve
typed compute/render command selectors and two owned command protocols.
Descriptor capacities and dynamic-stride capability are enforced before native
mutation; device identity, overflow-safe ranges, topology cardinality, buffer
retention, reset teardown, and mesh/patch capability paths are covered by the
safe contract, real ICB fixture, and ARC/`-Werror` native fixture.

The `be44eaf` interval moves five exact synchronous `MTLDevice` library
constructors. The safe API owns returned libraries through their device,
copies compiled bytes, validates absolute bundle/file paths, checks stitched
descriptor device graphs, and covers success-or-diagnostic behavior without
promoting callback overloads or selector lookalikes.

The `7ca877f` interval moves exactly seven IntersectionFunctionTable selectors.
Nullable buffer/function/visible-table arrays are validated atomically for
capacity, offsets, device identity, and live ownership before replacement;
opaque triangle and curve signatures share an exact range-checked capability
path. The public function-table lifecycle fixture and typed native ray-table
fixture prove retention, reset, and execute-or-capability-reject behavior.

The `cccf729` interval closes the exact CAMetalLayer10 residual: seven callable
method/property declarations, the public layer class and drawable protocol,
and the deliberately incomplete private layer ABI record. The safe surface
keeps device identity and layer configuration on the main domain, copies and
round-trips developer-HUD string properties, capability-gates residency state,
and proves real NSWindow-attached layer configuration without exposing private
storage.

The `813e1da` interval moves the exact seven residual FunctionStitching class
and protocol declarations. Public input, function-node, graph, inline-attribute,
and stitched-descriptor values retain their owned graph, reject invalid names,
indices, cycles, membership, devices, and lifetimes, and are proven by a real
`[[stitchable]]` library compile fixture with explicit capability rejection.

The `544c2c2` interval closes the five residual RasterizationRate type
declarations: four public descriptor/array classes and the rate-map protocol.
They map to the existing owned layer, descriptor, sample-array snapshot, and
map abstractions; a real Metal fixture proves both one- and two-layer graph
construction, device identity, physical-size queries, and explicit capability
rejection.

The `ea48261` interval closes the two exact legacy Device IO constructors.
The `6ef8001` interval then promotes the six residual StageInputOutput and
ComputePass descriptor/array classes already represented by their checked,
owned safe descriptor graphs and native conformance fixtures.

The `ef44024` interval closes fourteen Metal 4 declarations across the
machine-learning pipeline, compute encoder, and machine-learning encoder
headers. Existing public ownership APIs validate command state, device
identity, acceleration scratch ranges, tensor ranks/cardinality, argument
tables, heaps, and completion retention. The exact closure, safe callable
fixture, and typed native macOS 26 availability fixture prove five, five, and
four declarations respectively without claiming unavailable execution.

The `94307e9` interval closes the exact Event4 residual type surface: shared
event handle and listener classes, the notification block typedef, and opaque
private handle storage. These map to the existing exported-handle ownership and
bounded exactly-once listener callback API, backed by the Event14 native and
callback-stress fixtures.

The `4cfee19` interval closes the Tensor3 residual type declarations. Public
descriptor and extents values plus the tensor resource protocol are backed by
the existing Tensor47 owned graph, exact native ABI checks, byte-slice range
and lifetime validation, and real M1 conformance.

The `daaf52c` interval closes the exact MTLDevice descriptor/value25 slice:
twenty MTLArgumentDescriptor class, constructor, method, and property
declarations map to the checked public argument-encoder descriptor value, and
five MTLArchitecture/MTLDevice declarations map to a copied immutable
architecture-name snapshot. The real owned encoder fixture and ARC/Werror SDK
round-trip prove construction, validation, copying, and lifetime behavior.

The `a931f53` interval contains four final Device constructor declarations
promoted immediately beforehand and the attributable exact small-header24
sweep. The latter pins owned public type/protocol metadata and already-safe
selectors across LogState, Drawable, DepthStencil, Capture, BlitPass,
ArgumentEncoder, function tables, pools, queues, and Metal 4 linking values;
the family ownership/native fixtures remain the conformance authority.

The `ec543d9` interval closes the final four synchronous MTLDevice constructor
selectors from the earlier residual-six partition, moving bound coverage from
5,174 to 5,178. Typed function handles, immutable argument descriptors, and
the direct render-pipeline constructor retain their source/device graphs and
pass exact-package plus real public Metal conformance.

The `78a4724` interval closes the three BinaryArchive descriptor additions for
stitched libraries, mesh pipelines, and tile pipelines. The public path checks
live function kinds and device graphs before typed native mutation, propagates
NSError failures, retains only successful descriptor/function/library edges,
and is covered by real archive addition, serialization, and reopen conformance.

Rates describe completed commits, not forecasts. Hardware-only gates and
complex ownership features will vary materially from pure-value batches.
