# Simulasi Rupiah: Forecast dan Skenario USD/IDR dengan BVARX

Forecast bulanan USD/IDR (horizon 6 bulan) dan skenario bersyarat dengan Bayesian VARX.
Diadaptasi dari `input/reference/Manual_Model_Rupiah_BVARX.Rmd` dan ditulis ulang di Stata (Mata).

**Model (v3): BVARX dalam perubahan (changes).**
Endogen: perubahan 100×log USD/IDR, trade balance (USD bn), net flows (Rp10 tn), dan perubahan
100×log cadangan valas. Eksogen: perubahan 100×log DXY (+ UST10Y opsional) dan musiman sin/cos.
Prior Minnesota-style konjugat (matrix-normal inverse-Wishart), posterior draws independen,
conditional forecast dengan hard conditions (Waggoner & Zha, 1999). Benchmark: random walk dan
random walk + drift selisih suku bunga BI–Fed.

Versi level (v1–v2) diarsipkan di `archive/v2_levels/`. Versi itu menarik kurs ke rata-rata sampel
dan kalah dari random walk pada test 2024–2026. Riwayat lengkap: `CHANGELOG.md`.

## Run

Di Stata: `do "script/00_master.do"`. Jalankan seluruh file, bukan per baris. Tutup
`Database_Rupiah_Bulanan.xlsx` dan `output/rupiah_bvarx_results.xlsx` di Excel dulu.
Alternatif: `script/rupiah_bvarx_all.do` berisi semua modul dalam satu file untuk dipaste di
Do-file Editor. Ubah `global base` di atas file jika folder pindah.

Setting di `00_master.do`:

| Global | Arti | Default |
|---|---|---|
| `profile` | `quick` (cek alur) / `standard` / `publication` (jumlah draw) | `standard` |
| `model_mode` | Bentuk data model | `changes` |
| `include_ust` | 1 = UST10Y ikut eksogen | 0 |
| `run_adf` | 1 = jalankan uji unit root ADF + Phillips-Perron | 1 |
| `seas_harm` | Harmonik musiman: 1 = periode 12 bulan, 2 = + periode 6 bulan | 2 |
| `grid_start`, `grid_p`, `grid_lambda` | Grid validation | 2013/2014/2017, 1/2, 0.10/0.30 |
| `release_lag` | Jeda rilis makro konservatif (bulan) | 2 |
| `dxy_shock`, `tb_shock`, `flows_shock` | Adverse / Upside (±) | 2%, USD1 bn, Rp10 tn |
| `dxy_severe`, `tb_severe`, `flows_severe` | Severe Adverse | 5%, USD2 bn, Rp30 tn |

## Struktur folder

| Folder | Isi | Ditulis kode? |
|---|---|---|
| `input/` | `Database_Rupiah_Bulanan.xlsx` (sheet `database_monthly`, `flow_components`, `rating_events`, `sources`) | tidak |
| `input/reference/` | Manual R Markdown asli | tidak |
| `script/` | Do-file 00–04, 06–08 dan `rupiah_bvarx_all.do` | — |
| `intermediate/` | Dataset `.dta` hasil olahan | ya |
| `output/` | Hasil (lihat di bawah) | ya |
| `archive/v2_levels/` | Script, intermediate, dan output versi level (v2), path sudah diarahkan ke folder arsip | hanya jika dijalankan dari arsip |

## Alur do-file

| File | Isi |
|---|---|
| `00_master.do` | Path, setting, program `bv_out` dan `bv_pngtable`, log, memanggil modul |
| `01_import_audit.do` | Impor 4 sheet, audit struktur/missing/flows, deskriptif, grafik data, ADF (opsional) |
| `02_bvarx_functions.do` | Fungsi Mata: `bv_fit`, `bv_draw`, `bv_future`, `bv_predict`, `bv_backtest`, `bv_boot_rrmse`, `bv_final_run`; program `bv_score` |
| `03_validation.do` | Grid 12 spesifikasi pada origin Jan 2021–Jun 2023, aturan tie, kunci spesifikasi |
| `04_test.do` | Test Jan 2024–(bulan lengkap terakhir − 6) vs random walk, bootstrap blok 3/6/12, grafik |
| `06_final_scenarios.do` | Fit akhir, diagnostik residual, Baseline/Adverse/Upside/Severe Adverse, grafik dan tabel |
| `07_export.do` | Settings, database yang diimpor, narasi hasil otomatis |
| `08_forecast_compare.do` | BVARX vs random walk, random walk + drift, dan kombinasi |

## Output

Semua tabel juga tersedia sebagai sheet di **`output/rupiah_bvarx_results.xlsx`**.

| Lokasi | Isi |
|---|---|
| `output/run_log.log` | Log lengkap run terakhir |
| `output/narasi_hasil.txt` | Draft narasi hasil (terisi otomatis) |
| `output/tables/` | `S0_settings`, `A0_*`, `T1_descriptive`, `T2_validation_grid`, `T3_test_forecasts`, `T4_test_scores`, `T5_test_bootstrap`, `T7_baseline`, `T8_scenarios`, `T9_scenario_paths_all`, `T10_scenario_inputs`, `T11_global_paths`, `T12`/`T13_forecast_compare`, `T14_scenario_summary` |
| `output/diagnostics/` | `D1_audit_missing`, `D2_unit_root` (ADF + Phillips-Perron), `D3_residual_tests` (Ljung-Box Q12, normalitas), `D4_residual_corr`, `D5_scenario_ess_roots`, `D6_dxy_effect` (efek +1% DXY pada bulan yang sama) |
| `output/figures/` | Data: `1_data_series`. Test: `4_test_h1/h3/h6`, `4_test_rmse`. Skenario: `6_scenarios_fan`, `6_scenario_macro`, `6_scenario_table`, `6_forecast_table`, `6_residual_acf`. Benchmark: `8_forecast_compare`, `8_forecast_compare_table` |
| `output/gph/` | Grafik kerja Stata |

## Cara membaca

- **Relative RMSE** = RMSE BVARX ÷ RMSE random walk. Di bawah 1 berarti BVARX lebih akurat. Ini bukan R².
- `coverage80` dan `coverage95` mendekati 0,80 dan 0,95 berarti interval terkalibrasi wajar (baca bersama `width80`).
- Interval bootstrap yang meliputi 1 berarti belum ada bukti kuat bahwa BVARX lebih baik atau lebih buruk dari random walk.
- `low_ess = 1` berarti hasil skenario masih draft; tambah jumlah draw.
- Skenario adalah proyeksi bersyarat pada asumsi DXY, trade balance, dan flows, bukan efek kausal. Backtest bersifat pseudo-real-time (latest vintage).
