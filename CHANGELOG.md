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
