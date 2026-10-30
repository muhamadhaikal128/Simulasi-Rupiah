# Changelog: Simulasi Rupiah (BVARX)

## v1 — 30 Okt 2026: port Stata dari manual R Markdown

Sumber: `input/reference/Manual_Model_Rupiah_BVARX.Rmd`. Desain (variabel, prior, grid,
validation/test, information set, skenario) mengikuti manual; implementasi ditulis ulang di Mata.

Perbedaan terhadap versi R:
- Angka tidak identik dengan R karena generator acak berbeda (seed sama tidak memberi draw sama).
- Wishart di-draw dengan dekomposisi Bartlett (setara `rWishart`).
- Resampling importance weight memakai inverse-CDF pada uniform terurut, lalu diacak ulang.
- Uji ADF: lag 0–6 dipilih dengan BIC pada sampel bersama, lalu `dfuller` (pendekatan untuk
  `urca::ur.df(selectlags = "BIC")`); diperluas ke cadangan, DXY, TB, flows.
- Tambahan output: bootstrap dengan blok 3/6/12 sekaligus, Ljung-Box Q(12) dan uji normalitas
  residual, grafik test untuk tiap horizon, grafik RMSE, fan chart dengan riwayat 24 bulan dan band
  95%, grafik median TB/flows/cadangan per skenario, tabel median semua variabel per skenario.
- Semua tabel disimpan sebagai CSV dan sheet Excel di `output/rupiah_bvarx_results.xlsx`.

## v2 — 30 Okt 2026: orientasi forecast operasional

Masalah v1: BVARX level menarik kurs ke rata-rata sampel, sehingga forecast Mar 2027 = 16.798
(apresiasi 6%) dan test 2024–2026 kalah dari random walk (relative RMSE 1,29 / 1,37 / 1,66).

Perubahan:
- Prior dummy sum-of-coefficients / initial-observation (`soc`) ditambahkan ke grid validation.
  Validation tetap memilih `soc = 0`.
- Forecast akhir dan skenario memakai spesifikasi **changes** (`global final_mode`), dengan test
  2024–2026 relative RMSE 1,07 / 1,04 / 0,95. Catatan: pilihan ini dibuat setelah melihat test.
- Skenario: Baseline, Upside, Adverse, Severe Adverse (DXY +5%, TB −USD2 bn, flows −Rp30 tn).
- `08_forecast_compare.do`: BVARX level / level+dummy / changes, random walk, random walk + drift
  BI–Fed, dan kombinasi.
- Grafik asumsi makro (`6_scenario_macro.png`) dan tabel ringkas skenario (`6_scenario_table.png`, T14).

Hasil run 30 Okt 2026 14:32 (USD/IDR Mar 2027, median [80%]): Baseline 18.033 [16.992–19.258],
Adverse 18.325, Upside 17.754, Severe Adverse 18.855 [17.753–20.089].

## v3 — 30 Okt 2026: semua tahap memakai BVARX changes

- Validation, test, bootstrap, forecast akhir, dan skenario memakai spesifikasi changes
  (`global model_mode "changes"`). Grid validation kembali ke 12 spesifikasi (tanpa `soc`, yang hanya
  relevan untuk model level).
- `05_sensitivity.do` (perbandingan level vs changes) dihapus dari pipeline utama.
- `08_forecast_compare.do` hanya membandingkan BVARX changes dengan random walk, random walk + drift
  BI–Fed, dan kombinasinya.
- File hasil test diganti nama: `test_forecasts.dta`, `test_scores.dta`.
- Tabel PNG baru: `6_forecast_table.png` (forecast bulanan per skenario) dan
  `8_forecast_compare_table.png` (forecast per model), lewat program `bv_pngtable` di master.
- Versi v2 (script, intermediate, output) disalin ke `archive/v2_levels/`; path master arsip
  diarahkan ke folder arsip.
- Catatan: memilih changes sebagai model utama dilakukan setelah melihat hasil test v2.
- Uji unit root ditulis ulang: ADF (lag BIC) + Phillips-Perron, tiap seri dalam `capture` dengan
  progres per seri; diaktifkan lagi (`run_adf 1`). Output `D2_unit_root`. Penyebab macet sebelumnya
  belum dipastikan (terjadi di sesi Stata MCP, pada seri TB/flows).
- Musiman: harmonik kedua sin/cos periode 6 bulan (`global seas_harm 2`) karena residual trade balance
  v2 masih berautokorelasi di lag 6 dan 12 (Ljung-Box p < 0,001).
- Diagnostik baru `D6_dxy_effect`: efek kontemporer +1% DXY pada tiap variabel (mean, sd, interval 90%).

Hasil run v3, 30 Okt 2026 14:53 (spesifikasi: start 2013, lag 2, lambda 0,1; N = 161, Apr 2013 – Agu 2026):
- Test 2024–2026, relative RMSE vs random walk: 1,12 / 1,11 / 0,98 (h = 1/3/6); semua interval
  bootstrap meliputi 1. Coverage 80%: 0,96 / 0,81 / 0,96.
- Unit root: cadangan dan DXY unit root di level, stasioner di perubahan; TB dan flows stasioner;
  level kurs stasioner di sekitar tren (p = 0,02).
- Efek DXY +1% (bulan yang sama): USD/IDR +0,36% [0,21–0,52], flows −Rp3,5 tn, cadangan −0,29%.
- Residual trade balance masih berautokorelasi (Ljung-Box p < 0,001) walau dengan harmonik kedua.
- USD/IDR Mar 2027, median [80%]: Baseline 18.062 [16.801–19.354], Upside 17.667, Adverse 18.409,
  Severe Adverse 19.023 [17.806–20.366].
