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

## v3.2 — 30 Okt 2026: prior trade balance

- Prior mean koefisien lag sendiri trade balance di model changes = 0,7 (`global tb_prior_mean`),
  sebelumnya 0. TB adalah level yang persisten (autokorelasi 0,69 di lag 1, masih 0,52 di lag 12),
  sehingga prior 0 dengan shrinkage ketat menekan persistensi dan meninggalkan autokorelasi residual.
  Flows tidak persisten (autokorelasi ≤ 0,16), prior tetap 0.
- Percobaan dummy Lebaran (libur dan menjelang Idul Fitri) tidak memperbaiki residual TB dan
  menurunkan akurasi test; dibatalkan dan tidak masuk repo.
- Hasil run v3.2 (15:51): Ljung-Box residual TB turun dari Q = 78 ke 49 (masih p < 0,001); akurasi
  test praktis sama (1,12 / 1,11 / 0,99); Baseline Mar 2027 = 18.071, Severe Adverse = 18.977.

## v3.3 — 30 Okt 2026: perbaikan akurasi

- Grid validation diperluas: lambda 0,03 / 0,05 / 0,10 / 0,30 (v3 memilih 0,10 = batas bawah grid lama),
  UST10Y (0/1), dan selisih BI rate − Fed funds sebagai eksogen (0/1). Total 96 spesifikasi. Aturan
  tie menambahkan: tanpa UST, lalu tanpa selisih suku bunga.
- Selisih suku bunga ke depan dianggap tetap di nilai origin.
- `T6_benchmarks`: RMSE BVARX, random walk, random walk + drift BI–Fed, dan kombinasi (rata-rata BVARX
  dan RW + drift) pada periode validation dan test yang sama.
- Hasil run v3.3 (15:57): validation memilih 2013, lag 2, lambda 0,03, tanpa UST, tanpa selisih suku
  bunga. Test BVARX 1,11 / 1,11 / 0,99 (praktis sama). `T6_benchmarks`: RW + drift BI–Fed lebih akurat
  dari random walk di validation (0,99 / 0,98 / 0,93) dan test (0,99 / 0,98 / 0,94); kombinasi terbaik di
  validation (0,97 / 0,98 / 0,89) tapi 1,05 / 1,03 / 0,94 di test.

## v3.4 — 30 Okt 2026: VIX

- VIX (perubahan 100 × log) sebagai eksogen opsional di grid validation (`global grid_vix "0 1"`);
  ke depan dianggap tetap (perubahan 0). UST dikeluarkan dari grid (`grid_ust "0"`) karena tidak terpilih
  di v3.3. Grid tetap 96 spesifikasi.
- Diagnostik `D7_vix_effect` (efek kontemporer +1% VIX) jika VIX terpilih.
- Hasil run v3.4 (16:15): VIX terpilih (11 spesifikasi teratas memakai VIX); spesifikasi 2013, lag 1,
  lambda 0,03. Test BVARX 1,08 / 1,08 / 1,03; kombinasi 1,03 / 1,02 / 0,96; RW + drift tetap terbaik
  (0,99 / 0,98 / 0,94). VIX +10% → rupiah +0,26%, flows −Rp1,6 tn (bulan yang sama).
- Perbandingan di luar repo: VAR biasa (prior datar) lag 1 setara BVARX (test 1,11 / 1,10 / 1,00);
  VAR biasa lag 2 overfit di validation (1,11 / 1,16 / 1,07).

## v3.5 — 30 Okt 2026: impulse dummy bulan ekstrem

- Impulse dummy (1 di bulan itu, 0 lainnya) untuk bulan dengan |perubahan kurs| > 2,5 sd:
  Okt 2015, Nov 2018, Mar 2020, Apr 2020 (`global outlier_months`), sebagai opsi di grid validation
  (`grid_dum "0 1"`). Ke depan bernilai 0: tujuannya membersihkan estimasi dari lonjakan ekstrem.
- Eksogen yang konstan di sampel training (mis. dummy di luar sampel) dibuang otomatis.
- Selisih suku bunga dikeluarkan dari grid (`grid_rate "0"`) karena ditolak di v3.3 dan v3.4.
  Grid tetap 96 spesifikasi.
- Catatan: daftar bulan ditentukan dari seluruh sampel, jadi untuk origin validation lama ada sedikit
  informasi masa depan dalam pemilihan bulan (bukan dalam nilai data).
- Hasil run v3.5 (16:32): dummy terpilih (10 spesifikasi teratas), VIX tidak terpilih bersama dummy;
  spesifikasi 2014, lag 2, lambda 0,03. Test BVARX 1,05 / 1,04 / 0,98 (terbaik sejauh ini), kombinasi
  1,02 / 1,00 / 0,95. Tetapi coverage 80% turun ke 0,81 / 0,77 / 0,69: dummy mengecilkan volatilitas
  residual kurs (sd 2,2% → 1,5%), sehingga rentang terlalu sempit.
- Perbaikan: file diagnostik VIX dihapus jika VIX tidak terpilih (sebelumnya file basi tertinggal).

## v3.6 — 30 Okt 2026: prior UIP (alternatif kombinasi)

- Selisih BI rate − Fed funds masuk persamaan kurs dengan koefisien berpusat di 1/12 (uncovered interest
  parity: selisih 1 pp/tahun → depresiasi 1/12 % per bulan), sd prior 0,05 (satuan terstandar)
  (`global grid_uip "0 1"`, `uip_sd`). Tujuannya memasukkan "jangkar" RW + drift ke dalam model,
  menggantikan kombinasi 50:50.
- VIX dan dummy ditetapkan sesuai hasil v3.5 (`grid_vix "0"`, `grid_dum "1"`); grid 48 spesifikasi.

## BMA (R Markdown) — 30 Okt 2026

- `script/BMA_Rupiah.Rmd`: Bayesian Model Averaging untuk forecast langsung h = 1, 3, 6 bulan,
  6 prediktor (perubahan USD/IDR, DXY, UST10Y; flows, trade balance, perubahan cadangan dengan jeda
  2 bulan), 64 model, g-prior Zellner dengan prior seragam atas model; g dipilih di validation dari
  0,25 / 1 / 4 / n. Evaluasi vs random walk tanpa drift pada origin validation dan test yang sama
  dengan BVARX: RMSE, relative RMSE, Diebold-Mariano (koreksi HLN), Clark-West. Output PIP per origin
  dan sampel penuh, 10 model teratas, forecast akhir dengan interval dari campuran predictive.
- Ditulis tanpa dijalankan (R tidak terpasang di komputer pengembangan); belum ada hasil.
- `script/09_bma.do`: versi Stata dari BMA yang sama, memakai `bmaregress` bawaan (g-prior tetap,
  `mprior(binomial 0.5)`, enumerasi 64 model) dan `bmapredict, mean/std`. Ikut dijalankan dari
  `00_master.do` (`global run_bma 1`). Belum dijalankan.
- Hasil run 30 Okt 2026 18:05 (BMA, g = 0,25 terpilih di validation): test relative RMSE vs RW
  0,99 / 0,94 / 0,86 (BVARX v3.5: 1,05 / 1,04 / 0,98); Clark-West p = 0,23 / 0,07 / 0,02;
  rata-rata validation + test: BMA 0,950, kombinasi 0,962, RW + drift 0,965, BVARX 0,976.
  PIP semua prediktor sekitar 0,5 (tertinggi: perubahan kurs 0,69 dan UST 0,62 di h = 3).
  BMA Mar 2027: 18.196 [80%: 17.254–19.190].

## v4 — 30 Okt 2026: model gabungan (Baseline BMA + skenario BVARX)

- Snapshot v3.5 (BVARX + BMA, termasuk hasil run 18:05) disalin ke `archive/v3_5_bvarx/`.
- `10_hybrid.do`: Baseline = forecast BMA; Adverse / Upside / Severe Adverse = Baseline BMA × rasio
  (median skenario / median Baseline) BVARX per bulan. Rentang = interval BMA digeser dengan rasio yang
  sama. Output `T15_hybrid_scenarios`, `T16_hybrid_summary`, `10_hybrid_fan.png`, `10_hybrid_table.png`.
- `09_bma.do`: forecast akhir kini untuk setiap bulan 1–6 (dibutuhkan model gabungan); PIP dan model
  teratas tetap dilaporkan untuk h = 1, 3, 6.
- `bma_g_grid` dikunci ke 0,25 (terpilih di validation 18:05) agar run lebih cepat.
- `archive/v3_5_bvarx/` dibersihkan menjadi BVARX saja (script 09/BMA, tabel B*, grafik 9_bma, dataset
  bma_* dihapus dari arsip; master arsip tanpa global/pemanggilan BMA). Catatan: workbook Excel dan
  run_log di arsip masih memuat sheet/log BMA dari run 18:05. Folder utama = model gabungan lengkap.
- Folder utama dibersihkan (output/intermediate lama sudah ada di arsip). Grafik komponen dipisah:
  `output/figures/komponen_bvarx/` dan `output/figures/komponen_bma/`; `output/figures/` hanya hasil
  model gabungan dan grafik data.
- `10_hybrid.do` dilengkapi agar setara dengan set output BVARX: tabel ringkasan skenario (asumsi +
  hasil), grafik asumsi makro, backtest baseline (BMA) per horizon dengan band 80%, RMSE vs benchmark,
  perbandingan forecast antar model, serta `T17_hybrid_baseline_test` (relative RMSE, Clark-West,
  DM, arah, dan coverage interval 80/95% baseline BMA).
- RW + drift BI–Fed dan kombinasi dikeluarkan dari semua gambar (10_test_rmse, 10_forecast_compare,
  8_forecast_compare beserta tabel PNG-nya); angkanya tetap di tabel CSV/Excel (T6, T12, T13, T19).
- Hasil run v4, 30 Okt 2026 18:40: USD/IDR Mar 2027 Baseline (BMA) 18.196 [80%: 17.254–19.190],
  Upside 17.924, Adverse 18.465, Severe Adverse 18.935 [17.954–19.969]. Backtest baseline: relative RMSE
  0,99 / 0,94 / 0,86, Clark-West p 0,23 / 0,07 / 0,02, coverage 80% 0,92 / 0,85 / 0,81.
- README ditulis ulang: cara kerja model gabungan (BMA, BVARX, penggabungan), evaluasi, keterbatasan.
- Label diperjelas: baseline ditulis "BMA" (bukan "gabungan"); gabungan hanya untuk skenario (Baseline BMA + efek BVARX).
