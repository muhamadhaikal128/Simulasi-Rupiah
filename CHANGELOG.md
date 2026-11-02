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

## v4.1 — 1 Nov 2026: asumsi skenario dari sheet Excel

- Sheet baru `scenario_inputs` di `input/Database_Rupiah_Bulanan.xlsx`: satu baris per skenario × bulan
  ke-h (1–6) dengan `dxy_pct` (DXY kumulatif vs anchor, %), `tb_shift_usdbn` dan `flows_shift_idrtn`
  (geser terhadap median Baseline BVARX; kosong = bulan itu tidak dikunci). Isi default = asumsi v4,
  sehingga hasil seharusnya sama dengan run v4.
- `06_final_scenarios.do` membaca dan memvalidasi sheet (nama skenario, h lengkap, DXY terisi), menyimpan
  input yang dipakai ke `T0_scenario_inputs`, lalu meneruskannya ke Mata.
- `02_bvarx_functions.do`: `bv_future` menerima jalur DXY per bulan (selain skalar akhir horizon);
  `bv_scen_cond` dan `bv_final_run` memakai input per bulan.
- Global `cond_horizons`, `dxy_shock`, `tb_shock`, `flows_shock`, `dxy_severe`, `tb_severe`,
  `flows_severe`, `shock_mat` dihapus dari `00_master.do`; diganti `scen_sheet`.
- Label bulan pada tabel dan judul grafik skenario (06, 10) mengikuti anchor, tidak lagi ditulis tetap
  "Sep-26 / Des-26 / Mar-27".

## v4.1.1 — 2 Nov 2026: perbaikan impor sheet dan tabel bantu skenario

- Perbaikan: `06_final_scenarios.do` membaca sheet `scenario_inputs` dengan `cellrange(A1)`.
  `cellrange(A1:E200)` di v4.1 ditolak Stata ("lower right row is after the data area"), sehingga
  run penuh v4.1 berhenti di modul 06.
- Sheet `scenario_inputs`: tabel bantu di kolom H–L untuk mengisi target dalam angka asli (TB USD bn,
  flows Rp tn, DXY level indeks) bersama baseline BVARX dan DXY anchor (O3–O4). Kolom C–E yang dibaca
  model kini berupa rumus (geser = target − baseline; dxy_pct = DXY target ÷ anchor − 1). Isi default
  menghasilkan input yang sama dengan v4. Petunjuk dipindah ke kolom N.
- Eksperimen di luar repo (scratchpad, 2 Nov 2026), spesifikasi BVARX v4.1 sebagai pembanding:
  menambah selisih BI–Fed, VIX, atau keduanya memperburuk skor validation (0,927 → 0,985 / 0,949 / 0,985)
  dan test (1,025 → 1,039 / 1,034 / 1,031). VIX +10% → rupiah +0,13% (t 2,3); selisih BI–Fed tidak
  berpengaruh ke rupiah (t −0,3). UST10Y level memburuk tajam (val 1,09, test 1,11); perubahan UST10Y
  setara di test (1,024) tetapi lebih buruk di validation (0,966); +25 bp → rupiah +0,20% (t 1,4),
  flows −Rp3,7 tn, cadangan −0,29%. Spesifikasi utama tidak diubah.
- Eksperimen BMA di luar repo (scratchpad, 2 Nov 2026): prediktor disamakan dengan BVARX. Tanpa UST
  (32 model) rata-rata relative RMSE 0,954; dengan lag kedua seperti BVARX (512 model) 0,955; base
  (6 prediktor) 0,950. Forecast Mar 2027 18.185 / 18.220 vs 18.196. BMA base dipertahankan.

## v4.2 — 2 Nov 2026: prediktor pasar BMA dari rata-rata bulanan

- `database_monthly`: kolom baru `usdidr_avg`, `dxy_avg`, `ust10y_avg` = rata-rata bulanan data harian
  Bloomberg (USD/IDR IDR REGN, DXY, USGG10YR; semua baris harian dalam bulan). Sumber dicatat di sheet
  `sources`. September 2026 = rata-rata 1–22 Sep (data harian terakhir).
- `09_bma.do`: `ds`, `ddxy`, `dust` kini perubahan rata-rata bulanan (sebelumnya nilai akhir bulan).
  Target tetap kurs akhir bulan. BVARX tidak berubah.
- `01_import_audit.do`: berhenti dengan pesan jelas jika kolom rata-rata tidak ada.
- Alasan (uji scratchpad, target tetap kurs akhir bulan): rata-rata relative RMSE validation + test
  0,944 vs 0,950, lebih baik di 6/6 kombinasi periode × horizon. Dipilih setelah melihat test.
- Hasil run v4.2, 2 Nov 2026 13:13 (pertama kali juga menjalankan v4.1/v4.1.1 penuh): test BMA
  relative RMSE 0,987 / 0,934 / 0,857, Clark-West p 0,25 / 0,056 / 0,020, coverage 80% 0,92 / 0,85 /
  0,81; validation 0,982 / 0,977 / 0,924. PIP perubahan kurs 0,72 / 0,79 / 0,69. USD/IDR Mar 2027:
  Baseline 18.192 [17.254–19.181], Upside 17.920, Adverse 18.461, Severe Adverse 18.930
  [17.954–19.959]. Rasio skenario BVARX, ESS, dan input skenario (`T0_scenario_inputs`) identik
  dengan v4.
- Eksperimen lain di scratchpad (tidak dipakai): prediktor tambahan dari data harian (premi NDF 1M,
  selisih akhir bulan vs rata-rata, perubahan CDS 5Y) dihentikan sebelum selesai atas keputusan
  pengguna. ARIMA(p,1,q), p,q ≤ 2, dengan drift: validation memilih ARIMA(1,1,1) (skor 0,866) tetapi
  test 1,03 / 1,01 / 1,06; estimasi akhir MA = −1,00 (batas non-invertible), forecast Mar 2027 17.321.
  ARIMA(0,1,2) terbaik di test (0,906) tetapi hanya peringkat 4 di validation. BMA dipertahankan.

## Dokumentasi — 2 Nov 2026: flowchart hubungan antarvariabel

- Manual: Gambar 5.1 (hubungan antarvariabel BMA) dan Gambar 6.1 (BVARX); nomor gambar lain di Bab 5–6 bergeser. Deck: slide yang sama di bagian 05 dan 06; deck kini mengikuti urutan bab manual.
- Koefisien posterior BMA (origin Sep 2026, rata-rata 64 model): perubahan kurs bulan ini −0,05 / −0,09 / −0,08 (h = 1 / 3 / 6), jadi tandanya pembalikan, bukan momentum; istilah "momentum" di manual, deck, dan README diganti. DXY dan UST10Y positif; flows, trade balance, dan cadangan praktis nol. Efek 1 sd prediktor ≤ 0,17% vs konstanta +1,70% di h = 6.
- Eksperimen scratchpad (tidak dipakai): skenario tanpa Monte Carlo (BVARX dengan rata-rata posterior) memberi rasio hampir identik (Severe Adverse Mar 2027 18.899 vs 18.930); regresi langsung per horizon memberi efek skenario 20–25% lebih kecil dan tidak lebih akurat pada uji dengan jalur DXY/TB/flows aktual (DM p 0,24–0,97). Jumlah draw 10.000 dan 30.000 menggeser hasil gabungan ≤ Rp31 dibanding 6.000; tetap 6.000.

## v4.3 — 2 Nov 2026: data Oktober 2026, skenario outflow, 10.000 draw

- Data: pasar sampai Oktober 2026 (file Asset Market Updater per 2 Nov; akhir Oktober USD/IDR 18.127,
  DXY 101,879, UST10Y 4,93%); rata-rata harian September dihitung ulang sebulan penuh; trade balance
  September (BPS 2 Nov: ekspor 27,59, impor 24,23, surplus 3,36); VIX, BI-Rate, Fed funds Oktober;
  flows Oktober sementara dari Grand_Capital_Flows_ACUAN (7) (saham s.d. 30 Okt, SBN s.d. 29 Okt,
  SRBI proxy mingguan): −17,16. TB dan cadangan Oktober belum rilis. Bulan lengkap terakhir September,
  anchor Oktober; horizon November 2026 – April 2027.
- Skenario: flows Adverse dan Severe Adverse dikunci pada outflow absolut setiap bulan (input pengguna):
  13,95 / 13,95 / 20,92 / 20,92 / 27,90 / 41,84 (total 139,48) dan 24,75 / 24,75 / 37,13 / 37,13 / 49,51 /
  74,26 (total 247,53). DXY (+2%, +5%, −2%) dan TB (−1, −2, +1 di h = 3 dan 6) tetap; Upside tidak diubah.
- `00_master.do`: `n_final` standard 6.000 → 10.000 (ESS Severe Adverse 0,09 = 927 draw efektif).
- Hasil: BMA test 0,979 / 0,926 / 0,848 (27 forecast), Clark-West p 0,17 / 0,040 / 0,016, coverage 80%
  0,93 / 0,85 / 0,81. USD/IDR Apr 2027: Baseline 18.459 [17.508–19.461], Upside 18.174, Adverse 19.417,
  Severe Adverse 20.166 [19.128–21.262] (+5,2% dan +9,3% di atas baseline).
- Manual, deck, README diperbarui; flowchart contoh skenario dan Monte Carlo memakai angka baru.
- Uji scratchpad DMA/DMS (Raftery dkk. 2010; Koop & Korobilis 2012): λ terpilih 1 (koefisien tetap),
  rata-rata relative RMSE 0,928 vs BMA 0,944, tidak signifikan (DM p 0,15–0,99). BMA dipertahankan.

## v4.4 — 3 Nov 2026: skenario kelima Mild Adverse; asal angka outflow MSCI; deck ringkas

- Skenario kelima **Mild Adverse** (kode 5): DXY +1%, TB −0,5 vs baseline (h = 3, 6), outflow tiap bulan
  4,96 / 4,96 / 7,44 / 7,44 / 9,92 / 14,87 (total Rp49,58 tn). Kode skenario 1–4 tidak berubah.
- Kode: 02 (loop skenario sampai 5), 06 dan 10 (validasi nama dan jumlah baris, label, jalur DXY
  dxy_mild, fan chart, grafik makro, tabel PNG berurutan Baseline → Mild → Adverse → Severe → Upside).
  Sheet scenario_inputs: 30 baris (5 skenario × 6 bulan).
- Asal outflow (Estimasi_Outflow_MSCI_6_Bulan.xlsx, berbasis DEN_MSCI.pptx 19 Okt 2026): potensi saham
  Standalone 7,96 / 14,86 / 21,76 − pasif 4,5, × 50% dalam 6 bulan, + SBN 2/5/10% dari US$50 miliar =
  US$2,73 / 7,68 / 13,63 miliar × JISDOR 18.161; bobot bulanan 10/10/15/15/20/30%.
- Hasil Apr 2027: Mild Adverse 18.914 [17.939–19.941] (+2,5% vs baseline, ESS 0,76). Empat skenario lain
  identik dengan v4.3 (seed sama).
- Manual: Mild Adverse di Tabel 1.2, 6.2, 7.1, 7.4, 7.5 dan Bab 9 (Tabel 9.3 baru; nomor tabel 9.x
  berikutnya bergeser); paragraf asal angka outflow di Bab 7.1.
- Deck baru output/Simulasi_Rupiah_Ringkas_v2.pptx (24 slide, urutan: tujuan → konsep → skenario dan
  logika outflow → BMA → BVARX → hasil gabungan → evaluasi, diagnostik, treatment). Deck lengkap lama
  (Simulasi_Rupiah_BMA_BVARX.pptx) belum memuat Mild Adverse.

## v4.5 — 3 Nov 2026: BVARX tanpa dummy outlier

- `00_master.do`: `grid_dum` 1 → 0. BVARX hanya dipakai untuk efek skenario (stress test), sehingga bulan
  krisis (Okt-15, Nov-18, Mar-20, Apr-20) harus ikut membentuk koefisien dan residual correlation.
- Uji scratchpad pada spesifikasi lama (2014, lag 2, λ 0,03): residual correlation flows–kurs −0,36 → −0,44;
  Severe Adverse Apr 2027 20.166 → 20.784; test relative RMSE 1,04 / 1,02 / 0,96 → 1,09 / 1,06 / 0,95;
  coverage 80% test 0,81 / 0,74 / 0,70 → 0,93 / 0,81 / 0,93.
- Validation diulang tanpa dummy dan memilih awal 2013, lag 1, λ 0,03, prior UIP (skor 0,978; terbaik tanpa
  UIP 1,003). Selisih BI–Fed masuk sebagai eksogen di keempat persamaan, koefisien persamaan kurs berpusat
  di 1/12; ke depan dibuat datar di nilai terakhir. Sampel training Mar 2013 – Sep 2026 (163 bulan).
- Sheet scenario_inputs: H/J baseline diperbarui dari T9 run baru; K absolut Mild/Adverse/Severe tetap,
  I dan K Upside dihitung ulang agar geserannya tetap.
- Hasil: residual correlation flows–kurs −0,42, cadangan–kurs −0,39, flows–cadangan +0,48; efek +1% DXY
  ke kurs +0,35% (0,20–0,50). BVARX test 1,11 / 1,12 / 1,05 (interval bootstrap memuat 1), coverage 80%
  0,93 / 0,81 / 0,93; ESS Severe Adverse 0,18. USD/IDR Apr 2027: Baseline 18.459 (BMA, tidak berubah),
  Upside 18.170, Mild Adverse 19.093, Adverse 19.790, Severe Adverse 20.774 [19.704–21.903]
  (+3,4%, +7,2%, +12,5% vs baseline).
- Deck ringkas v2 diperbarui. Manual (docx/pdf), deck lengkap, dan README belum diperbarui ke v4.5.
- Perbaikan teks entri v4.3 dan v4.4 yang rusak saat ditulis lewat PowerShell.