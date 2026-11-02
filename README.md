# Simulasi Rupiah: Forecast USD/IDR dengan BMA, skenario dengan efek BVARX

Forecast bulanan kurs USD/IDR untuk 6 bulan ke depan, lengkap dengan rentang ketidakpastian dan
skenario makro (Upside, Adverse, Severe Adverse). Diadaptasi dari
`input/reference/Manual_Model_Rupiah_BVARX.Rmd` dan ditulis ulang di Stata (Mata + `bmaregress`).

Hasil run terakhir (3 Nov 2026, v4.4, data sampai Okt 2026), anchor Okt 2026 = 18.127:

| USD/IDR Apr 2027 | Median | Rentang 80% | vs Okt-26 |
|:--|--:|:--|--:|
| Baseline | 18.459 | 17.508 – 19.461 | +1,8% |
| Upside | 18.174 | 17.238 – 19.161 | +0,3% |
| Mild Adverse | 18.914 | 17.939 – 19.941 | +4,3% |
| Adverse | 19.417 | 18.417 – 20.472 | +7,1% |
| Severe Adverse | 20.166 | 19.128 – 21.262 | +11,3% |

## 1. Cara kerja model

Model ini menggabungkan dua model Bayesian, masing-masing dipakai untuk hal yang paling dikuasainya:

```
                 Database bulanan 2013–2026 (kurs, DXY, UST10Y, flows, trade balance, cadangan)
                                              │
              ┌───────────────────────────────┴───────────────────────────────┐
              ▼                                                               ▼
   BMA  (09_bma.do)                                         BVARX  (01–08)
   "Berapa kurs 1–6 bulan lagi?"                            "Kalau DXY/flows/TB bergerak X, kurs bergeser berapa?"
   → forecast titik + rentang (Baseline)                    → selisih tiap skenario terhadap baseline BVARX
              │                                                               │
              └───────────────────────────────┬───────────────────────────────┘
                                              ▼
                              Skenario  (10_hybrid.do)     
              Baseline = BMA;   Skenario = Baseline BMA × (skenario BVARX ÷ baseline BVARX)
```

Alasannya: pada uji out-of-sample, BMA paling akurat untuk forecast titik, tetapi BMA tidak bisa
menerima asumsi jalur variabel ke depan. BVARX sebaliknya: forecast titiknya setara random walk,
tetapi BVARX bisa menerjemahkan jalur DXY, trade balance, dan flows menjadi pergerakan kurs.

### 1.1 Baseline: Bayesian Model Averaging (BMA)

**Pertanyaan yang dijawab:** dengan informasi yang tersedia hari ini, berapa perubahan kurs
h bulan ke depan (h = 1, …, 6)?

1. **Satu regresi per horizon.** Target: perubahan kurs h bulan ke depan, 100 × [log kurs(t+h) − log kurs(t)].
   Prediktor diambil dari informasi yang sudah tersedia di akhir bulan t:

   | Prediktor | Isi | Data bulan |
   |:--|:--|:--|
   | `ds` | Perubahan rata-rata bulanan USD/IDR (dari data harian) | t |
   | `ddxy` | Perubahan rata-rata bulanan DXY | t |
   | `dust` | Perubahan rata-rata bulanan yield UST10Y | t |
   | `flow2` | Net flows asing (saham + SBN + SRBI) | t − 2 (jeda rilis) |
   | `tb2` | Trade balance | t − 2 |
   | `dres2` | Perubahan cadangan devisa | t − 2 |

2. **64 model.** Karena tidak pasti prediktor mana yang relevan, semua 2⁶ = 64 kombinasi prediktor
   diestimasi. Konstanta (drift depresiasi rata-rata) selalu ada.
3. **Bobot model dari data.** Tiap model diberi probabilitas posterior berdasarkan seberapa baik ia
   menjelaskan data (marginal likelihood g-prior Zellner), dengan peluang prior 50% per prediktor.
4. **Shrinkage.** g = 0,25 (dipilih di validation dari 0,25 / 1 / 4 / n): koefisien ditarik kuat ke
   nol, sehingga prediktor hanya menggeser forecast bila sinyalnya kuat.
5. **Forecast** = rata-rata forecast 64 model dibobot probabilitas posteriornya (`bmapredict`).
   Rentang 80/95% dari mean dan simpangan baku predictive BMA (pendekatan normal).
6. **PIP** (posterior inclusion probability) menunjukkan seberapa yakin data bahwa suatu prediktor
   relevan.

### 1.2 Skenario: BVARX

**Pertanyaan yang dijawab:** jika DXY, trade balance, dan flows mengikuti jalur tertentu, bagaimana
kurs bergerak?

1. **Sistem empat variabel** yang saling memengaruhi dan diramal bersama: perubahan USD/IDR, trade
   balance, net flows, dan perubahan cadangan devisa (lag 2 bulan).
2. **Variabel eksogen**: perubahan DXY, musiman (sin/cos 12 dan 6 bulan), dan dummy empat bulan
   ekstrem (Okt 2015, Nov 2018, Mar 2020, Apr 2020).
3. **Prior Minnesota konjugat** (λ = 0,03): koefisien ditarik ke "tidak ada hubungan", kecuali lag
   trade balance yang berpusat di 0,7 karena trade balance sangat persisten.
4. **Conditional forecast** (Waggoner & Zha, 1999): jalur DXY ditentukan sebagai input, sedangkan trade
   balance dan flows "dikunci" pada nilai skenario di bulan yang diisi di sheet skenario (TB: Jan-27
   dan Apr-27; flows Adverse/Severe: setiap bulan). Model menghitung jalur kurs
   yang konsisten dengan kondisi itu, dengan 10.000 simulasi posterior.
5. **Skenario:**

   | Skenario | DXY (s/d Apr-27) | Trade balance | Net flows asing (Nov-26 s/d Apr-27) |
   |:--|:--|:--|:--|
   | Baseline | datar | jalur model | jalur model |
   | Upside | −2% | +USD1 bn vs baseline | +Rp10 tn vs baseline (Jan, Apr) |
   | Mild Adverse | +1% | −USD0,5 bn | outflow 4,96 / 4,96 / 7,44 / 7,44 / 9,92 / 14,87 (total Rp49,58 tn) |
| Adverse | +2% | −USD1 bn | outflow 13,95 / 13,95 / 20,92 / 20,92 / 27,90 / 41,84 (total Rp139,48 tn) |
   | Severe Adverse | +5% | −USD2 bn | outflow 24,75 / 24,75 / 37,13 / 37,13 / 49,51 / 74,26 (total Rp247,53 tn) |

   Outflow adalah estimasi dampak usulan reklasifikasi MSCI ke Standalone (`Estimasi_Outflow_MSCI_6_Bulan.xlsx`):
   potensi outflow saham US$7,96 / 14,86 / 21,76 miliar dikurangi dana pasif US$4,5 miliar, 50% dijual dalam
   6 bulan, ditambah penjualan SBN asing 2% / 5% / 10% dari US$50 miliar = US$2,73 / 7,68 / 13,63 miliar
   (kurs JISDOR 18.161), dibagi per bulan dengan bobot 10/10/15/15/20/30%. Diisi sebagai angka asli di
   kolom K sheet skenario. Hasilnya setara kira-kira persentil 75 (Mild Adverse), 90 (Adverse), dan di atas
   persentil 95 (Severe Adverse) pergerakan rupiah 6 bulanan.

   Asumsi ini diisi per bulan di sheet **`scenario_inputs`** pada `input/Database_Rupiah_Bulanan.xlsx`
   (satu baris per skenario × bulan ke-h):

   | Kolom | Isi |
   |:--|:--|
   | `scenario` | Baseline, Adverse, Upside, Severe Adverse, Mild Adverse (nama tetap) |
   | `h` | Bulan ke-h setelah anchor, 1 sampai 6 |
   | `dxy_pct` | DXY kumulatif terhadap bulan anchor (%), wajib diisi |
   | `tb_shift_usdbn` | Trade balance dikunci = median Baseline BVARX + angka ini (USD bn); kosong = tidak dikunci |
   | `flows_shift_idrtn` | Net flows dikunci = median Baseline BVARX + angka ini (Rp tn); kosong = tidak dikunci |

   Kolom C–E tidak diketik langsung: isinya rumus dari **tabel bantu** di kolom H–L, tempat target diisi
   dalam angka asli (TB dalam USD bn, flows dalam Rp tn, DXY dalam level indeks), bersama baseline model
   (median baseline BVARX dari `T9_scenario_paths_all`) dan DXY anchor (sel O4). Rumusnya: geser = target −
   baseline, dan `dxy_pct` = (DXY target ÷ DXY anchor − 1) × 100. Baseline (H, J) dan anchor (O3, O4)
   perlu diperbarui setiap kali data bulan baru masuk.
   Isi saat ini sama dengan tabel di atas (DXY bergerak geometrik; TB dan flows Upside dikunci di h = 3 dan 6; flows Mild/Adverse/Severe di h = 1–6).
   Untuk periode baru cukup ubah angka di sheet itu, simpan, lalu jalankan `00_master.do`. Input yang
   dipakai tercatat di `output/tables/T0_scenario_inputs.csv`.

### 1.3 Skenario: Baseline BMA + efek skenario BVARX

Untuk setiap bulan dan skenario:

> **Skenario = Baseline BMA × (median skenario BVARX ÷ median Baseline BVARX)**

Contoh Apr 2027: di BVARX, Severe Adverse 9,25% di atas Baseline BVARX (20.059 ÷ 18.360), sehingga
Severe Adverse = 18.459 × 1,0925 = 20.166. Rentang skenario adalah rentang BMA yang digeser
dengan rasio yang sama.

## 2. Evaluasi

Semua model dinilai **out-of-sample** dengan origin bergulir dan information set yang sama:

- **Validation** (origin Jan 2021 – Jun 2023): memilih spesifikasi (start year, lag, λ, eksogen, g).
- **Test** (origin Jan 2024 – Mar 2026, 27 forecast per horizon): menilai akurasi.
- Di setiap origin model diestimasi ulang hanya dengan data yang sudah tersedia; variabel makro
  memakai jeda rilis 2 bulan.
- Benchmark: **random walk tanpa drift** (kurs ke depan = kurs hari ini).

Hasil test baseline (BMA), `T17_hybrid_baseline_test`:

| Horizon | Relative RMSE vs RW | Clark-West p | Arah benar | Coverage 80% | Coverage 95% |
|:--|--:|--:|--:|--:|--:|
| 1 bulan | 0,98 | 0,17 | 63% | 0,93 | 0,96 |
| 3 bulan | 0,93 | **0,04** | 74% | 0,85 | 0,96 |
| 6 bulan | 0,85 | **0,02** | 78% | 0,81 | 1,00 |

Relative RMSE di bawah 1 berarti lebih akurat dari random walk. Keunggulan signifikan secara
statistik di horizon 3 dan 6 bulan (5%); coverage interval mendekati target.

## 3. Keterbatasan

1. **Periode test ikut memengaruhi desain.** Pilihan model changes, dummy, BMA, prediktor rata-rata bulanan, dan cara menyusun skenario
   diambil setelah melihat hasil test 2024–2026, sehingga angka test cenderung optimistis. Bukti yang
   bersih hanya dari data baru (Okt 2026 dst.) dengan spesifikasi yang dibekukan.
2. **Keunggulan BMA terutama dari drift.** PIP prediktor sekitar 0,5 (sama dengan prior), kecuali
   perubahan kurs rata-rata bulanan (0,72 / 0,79 / 0,69 untuk h = 1 / 3 / 6; koefisien negatif = pembalikan, bukan momentum); g = 0,25 menyusutkan
   koefisien sekitar 80%. Forecast BMA pada dasarnya drift depresiasi historis ditambah sinyal kecil.
3. **Skenario adalah overlay**: baseline BMA digeser dengan efek dari BVARX, dua model dengan struktur berbeda. Rentang skenario tidak memuat
   ketidakpastian dari jalur skenario itu sendiri.
4. **Model linear untuk outflow ekstrem**: Rp100 tn flows di luar baseline ≈ 2,3% kurs berapa pun besarnya, dan bulan krisis dikeluarkan lewat dummy; Severe Adverse sebaiknya dibaca sebagai batas bawah. Data Oktober 2026 (flows) masih sementara; TB dan cadangan Oktober belum dirilis.
5. **Bulan dummy BVARX** dipilih dari seluruh sampel; dummy juga membuat interval BVARX terlalu sempit
   (dipakai hanya untuk selisih skenario, bukan rentang).
6. **Data latest vintage** (pseudo-real-time); baseline DXY datar; residual trade balance BVARX masih
   berautokorelasi.
7. **Data harian** untuk kolom rata-rata bulanan (`usdidr_avg`, `dxy_avg`, `ust10y_avg`) diambil dari file
   Bloomberg di luar repo; kolom itu perlu diperbarui manual setiap bulan.

## 4. Menjalankan

Di StataMP: `do "script/00_master.do"`. Jalankan seluruh file sekali, lalu tunggu sampai muncul
`Selesai` (sekitar 6–8 menit). Tutup `Database_Rupiah_Bulanan.xlsx` dan
`output/rupiah_bvarx_results.xlsx` di Excel dulu. Ubah `global base` jika folder pindah.
`script/rupiah_bvarx_all.do` berisi semua modul dalam satu file untuk dipaste di Do-file Editor.

Setting utama di `00_master.do`:

| Global | Arti | Nilai |
|:--|:--|:--|
| `profile` | Jumlah draw BVARX: `quick` / `standard` / `publication` | `standard` |
| `run_bma` | 1 = jalankan BMA (09) dan penyusunan skenario (10) | 1 |
| `bma_preds`, `bma_g_grid`, `bma_start` | Prediktor BMA, g (dikunci dari validation), awal sampel | 6 prediktor, 0.25, 2014 |
| `grid_start`, `grid_p`, `grid_lambda` | Grid validation BVARX | 2013/2014/2017, 1/2, 0.03–0.30 |
| `grid_dum`, `outlier_months` | Dummy bulan ekstrem BVARX | 1; 2015m10 2018m11 2020m3 2020m4 |
| `grid_vix`, `grid_rate`, `grid_ust`, `grid_uip` | Opsi eksogen BVARX (diuji, tidak terpilih) | 0, 0, 0, 0 1 |
| `tb_prior_mean`, `seas_harm` | Prior lag trade balance; harmonik musiman | 0.7; 2 |
| `release_lag` | Jeda rilis makro (bulan) | 2 |
| `scen_sheet` | Sheet asumsi skenario di workbook input (lihat 1.2) | `scenario_inputs` |

## 5. Struktur folder dan file

| Folder / file | Isi |
|:--|:--|
| `input/` | `Database_Rupiah_Bulanan.xlsx` (sheet `database_monthly`, `flow_components`, `rating_events`, `sources`, `scenario_inputs`); tidak ditulis kode |
| `input/reference/` | Manual R Markdown asli |
| `script/00_master.do` | Path, setting, program `bv_out` dan `bv_pngtable`, log, memanggil modul |
| `script/01_import_audit.do` | Impor, audit data, deskriptif, uji unit root (ADF, Phillips-Perron) |
| `script/02_bvarx_functions.do` | Fungsi Mata BVARX (estimasi, simulasi, conditional forecast, backtest, bootstrap) |
| `script/03_validation.do` | Grid validation BVARX dan penguncian spesifikasi |
| `script/04_test.do` | Test BVARX vs random walk, bootstrap, benchmark |
| `script/06_final_scenarios.do` | Fit akhir BVARX, diagnostik residual, skenario |
| `script/07_export.do` | Settings, database, narasi otomatis |
| `script/08_forecast_compare.do` | Perbandingan forecast BVARX dengan benchmark |
| `script/09_bma.do` | BMA: validation g, test, PIP, model teratas, forecast bulanan |
| `script/10_hybrid.do` | Skenario (Baseline BMA + efek BVARX), tabel, dan grafik utama |
| `script/BMA_Rupiah.Rmd` | Versi R Markdown dari BMA (terpisah, butuh R) |
| `intermediate/` | Dataset `.dta` hasil olahan |
| `output/` | Hasil (lihat bagian 6) |
| `archive/v3_5_bvarx/` | BVARX saja (v3.5), sebelum BMA dan skenario BMA + BVARX |
| `archive/v2_levels/` | BVARX versi level (v1–v2) |

## 6. Output

Semua tabel juga ada sebagai sheet di **`output/rupiah_bvarx_results.xlsx`**.

| Lokasi | Isi |
|:--|:--|
| `output/figures/` | **Hasil utama:** `10_hybrid_fan` (fan chart), `10_hybrid_table` (forecast bulanan per skenario), `10_hybrid_scenario_table` (asumsi + hasil), `10_hybrid_macro` (jalur asumsi), `10_test_h1/h3/h6` dan `10_test_rmse` (backtest baseline), `10_forecast_compare` (+ tabel); data: `1_data_series` |
| `output/figures/komponen_bvarx/` | Grafik komponen BVARX (`4_test_*`, `6_*`, `8_*`) |
| `output/figures/komponen_bma/` | Grafik komponen BMA (`9_bma_*`) |
| `output/tables/` | Hasil utama (BMA dan skenario): `T15`–`T19`. BMA: `B1`–`B6`. BVARX: `T2`–`T14`. Lainnya: `S0_settings`, `A0_*`, `T1_descriptive` |
| `output/diagnostics/` | `D1`–`D6` (audit, unit root, residual, ESS, efek DXY), `B4_bma_pip_final`, `B6_bma_varinclusion_*` |
| `output/run_log.log`, `output/narasi_hasil.txt` | Log run dan draft narasi |

## 7. Cara membaca

- **Relative RMSE** = RMSE model ÷ RMSE random walk; di bawah 1 berarti lebih akurat. Ini bukan R².
- **Clark-West p** < 0,05: model lebih akurat dari random walk secara signifikan. p besar berarti
  belum ada bukti, bukan bukti bahwa model lebih buruk.
- **Coverage 80%** mendekati 0,80 berarti rentang 80% terkalibrasi wajar.
- **PIP** mendekati 1: data yakin prediktor relevan; sekitar 0,5: tidak ada bukti (sama dengan prior).
- Skenario adalah proyeksi bersyarat pada asumsi DXY, trade balance, dan flows, bukan efek kausal.

Riwayat versi dan semua hasil run: `CHANGELOG.md`.
