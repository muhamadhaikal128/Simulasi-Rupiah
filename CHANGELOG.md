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
