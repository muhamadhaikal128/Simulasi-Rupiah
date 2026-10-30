# Simulasi Rupiah: Forecast dan Skenario USD/IDR dengan BVARX

Port Stata (Mata) dari `input/reference/Manual_Model_Rupiah_BVARX.Rmd`. Sistem bulanan
`y = (100 log USD/IDR, trade balance, flows/10, 100 log cadangan valas)` dengan eksogen
`100 log DXY` (+ UST10Y opsional) dan musiman sin/cos. Prior Minnesota-style konjugat
(matrix-normal inverse-Wishart), posterior draws independen, conditional forecast dengan hard
conditions pada observabel (Waggoner & Zha, 1999). Benchmark: random walk tanpa drift.

Riwayat versi: lihat `CHANGELOG.md`.

## Run

Di Stata: `do "script/00_master.do"`. Jalankan seluruh file (bukan per baris). Tutup
`Database_Rupiah_Bulanan.xlsx` dan `output/rupiah_bvarx_results.xlsx` di Excel dulu.
Ubah `global base` di atas file jika folder pindah.

Setting di `00_master.do`:

| Global | Arti | Default |
|---|---|---|
| `profile` | `quick` (cek alur) / `standard` / `publication` (jumlah draw) | `standard` |
| `include_ust` | 1 = UST10Y ikut eksogen (putuskan lewat validation) | 0 |
| `run_sensitivity` | 1 = jalankan spesifikasi changes | 1 |
| `grid_start`, `grid_p`, `grid_lambda` | Grid validation | 2013/2014/2017, 1/2, 0.10/0.30 |
| `release_lag` | Jeda rilis makro konservatif (bulan) | 2 |
| `dxy_shock`, `tb_shock`, `flows_shock` | Besaran skenario ilustratif | 2%, USD1 bn, Rp10 tn |

## Struktur folder

| Folder | Isi | Ditulis kode? |
|---|---|---|
| `input/` | `Database_Rupiah_Bulanan.xlsx` (sheet `database_monthly`, `flow_components`, `rating_events`, `sources`) | tidak |
| `input/reference/` | Manual R Markdown asli | tidak |
| `script/` | Do-file 00–07 | — |
| `intermediate/` | Dataset `.dta` hasil olahan (database, backtest, skor, skenario) | ya |
| `output/` | Hasil (lihat di bawah) | ya |
| `archive/` | Versi lama | tidak |

## Alur do-file

| File | Isi |
|---|---|
| `00_master.do` | Path, setting, log, memanggil 01–07 |
| `01_import_audit.do` | Impor 4 sheet, audit struktur/missing/flows, deskriptif, grafik data, ADF |
| `02_bvarx_functions.do` | Fungsi Mata: `bv_fit`, `bv_draw`, `bv_future`, `bv_predict`, `bv_backtest`, `bv_boot_rrmse`; program `bv_score` |
| `03_validation.do` | Grid 12 spesifikasi pada origin Jan 2021–Jun 2023, aturan tie, kunci spesifikasi |
| `04_test.do` | Test Jan 2024–(bulan lengkap terakhir − 6) vs RW, bootstrap blok 3/6/12, grafik |
| `05_sensitivity.do` | Spesifikasi changes dengan hyperparameter sama |
| `06_final_scenarios.do` | Fit akhir, diagnostik residual, baseline + skenario tekanan/dukungan, fan chart |
| `07_export.do` | Settings, database yang diimpor, narasi hasil otomatis |

## Output

Semua tabel juga tersedia sebagai sheet di **`output/rupiah_bvarx_results.xlsx`**.

| Lokasi | Isi |
|---|---|
| `output/run_log.log` | Log lengkap run terakhir |
| `output/narasi_hasil.txt` | Draft narasi hasil (terisi otomatis) |
| `output/tables/` | `S0_settings`, `A0_*` (sumber, rating, database), `T1_descriptive`, `T2_validation_grid`, `T3_test_forecasts`, `T4_test_scores`, `T5_test_bootstrap`, `T6_sensitivity_levels_changes`, `T7_baseline`, `T8_scenarios`, `T9_scenario_paths_all`, `T10_scenario_inputs`, `T11_global_paths` |
| `output/diagnostics/` | `D1_audit_missing`, `D2_unit_root_adf`, `D3_residual_tests` (Ljung-Box Q12, normalitas), `D4_residual_corr`, `D5_scenario_ess_roots` |
| `output/figures/` | `1_data_series`, `4_test_h1/h3/h6`, `4_test_rmse`, `6_residual_acf`, `6_scenarios_fan`, `6_scenarios_vars` |
| `output/gph/` | Grafik kerja Stata |

## Cara membaca

- `relative_rmse < 1`: BVARX lebih akurat dari RW secara deskriptif; `> 1` RW lebih akurat.
- `coverage80`/`coverage95` mendekati 0.80/0.95 = kalibrasi interval wajar (baca bersama `width80`).
- Interval bootstrap yang meliputi 1: belum ada bukti kuat mengungguli RW.
- ESS rendah (`low_ess = 1`) = hasil skenario masih draft; tambah draw.
- Skenario adalah proyeksi bersyarat, bukan efek kausal. Backtest pseudo-real-time (latest vintage).
