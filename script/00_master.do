**# 0. MASTER: Forecast dan skenario USD/IDR, model gabungan (Baseline BMA + skenario BVARX)
* v4: BVARX changes (01-08) untuk skenario bersyarat, BMA (09) untuk baseline, gabungan (10).
* Versi BVARX saja (v3.5) ada di archive/v3_5_bvarx/. Lihat CHANGELOG.md.
* Port Stata dari input/reference/Manual_Model_Rupiah_BVARX.Rmd (versi R).
* Jalankan seluruh file ini sebagai do-file: do "script/00_master.do".
* Tutup Database_Rupiah_Bulanan.xlsx dan output Excel di Excel sebelum menjalankan.
* Bookmark **# / **## dapat dipakai di Do-file Editor (Stata 17+).
* Jangan menaruh komentar "//" di akhir baris "global".

version 19
clear all
set more off
set varabbrev off
set linesize 120

*****************************
****** Global Settings ******
*****************************

global base "C:\Users\LENOVO05\github\Simulasi-Rupiah"

* Data mentah (tidak pernah ditulis oleh kode)
global source "$base\input"
global data_file "$source\Database_Rupiah_Bulanan.xlsx"
* Do-file
global script "$base\script"
* Dataset Stata hasil olahan
global data "$base\intermediate"
* Hasil akhir
*   output/figures                  grafik model gabungan (hasil utama) dan data
*   output/figures/komponen_bvarx   grafik komponen BVARX (test, skenario, residual)
*   output/figures/komponen_bma     grafik komponen BMA (PIP, test)
*   output/tables       tabel hasil (CSV), juga disalin ke workbook ringkasan
*   output/diagnostics  uji dan diagnostik (unit root, residual, ESS, akar companion)
*   output/gph          grafik kerja Stata (.gph)
global results "$base\output"
global fig "$results\figures"
global fig_bvarx "$fig\komponen_bvarx"
global fig_bma "$fig\komponen_bma"
global tab "$results\tables"
global diag "$results\diagnostics"
global gph "$results\gph"
global xlsx "$results\rupiah_bvarx_results.xlsx"
foreach d in data results fig fig_bvarx fig_bma tab diag gph {
	cap mkdir "${`d'}"
}
cap erase "$xlsx"

* bv_out: simpan dataset di memori sebagai CSV (folder tab/diag) dan sheet di workbook ringkasan
cap program drop bv_out
program define bv_out
	args folder name
	export delimited using "${`folder'}/`name'.csv", replace
	cap export excel using "$xlsx", sheet("`name'", replace) firstrow(variables)
	if _rc {
		di as error "Gagal menulis $xlsx (sheet `name'). Tutup file di Excel lalu jalankan ulang."
		exit 603
	}
end

* bv_pngtable: render variabel string di memori sebagai tabel PNG (satu baris per observasi)
*   heads() = judul kolom (dalam tanda kutip), widths() = lebar tiap kolom (satuan kanvas)
cap program drop bv_pngtable
program define bv_pngtable
	syntax varlist, File(string) Title(string) Heads(string asis) Widths(numlist) [Note(string)]
	local nv : word count `varlist'
	local nr = _N
	local x 2
	local j 0
	foreach w of numlist `widths' {
		local ++j
		local x`j' = `x'
		local x = `x' + `w'
	}
	local xmax = `x'
	local step = 88/(`nr' + 1)
	local txt ""
	forval j = 1/`nv' {
		local h : word `j' of `heads'
		local txt `txt' text(96 `x`j'' "`h'", place(e) size(small) color(black))
	}
	forval i = 1/`nr' {
		local y = 96 - `step'*`i'
		local j 0
		foreach v of local varlist {
			local ++j
			local s = `v'[`i']
			local txt `txt' text(`y' `x`j'' "`s'", place(e) size(small))
		}
	}
	local yl = 96 - `step'/2
	twoway scatteri 0 0 100 `xmax', msymbol(none) xscale(off range(0 `xmax')) yscale(off range(0 100)) ///
		xlabel(none) ylabel(none) `txt' yline(`yl', lcolor(gs10)) ///
		title(`"`title'"', size(medium)) note(`"`note'"', size(vsmall)) ///
		graphregion(color(white)) plotregion(style(none)) legend(off) ///
		xsize(`=max(8, `xmax'/9)') ysize(`=max(3, 1.2 + 0.45*`nr')') name(pngtab, replace)
	graph export "`file'", replace width(2400)
end

**## 0.1 Parameter manual (setara blok params di Rmd)
* profile: quick (cek alur) | standard | publication (angka untuk naskah)
global profile "standard"
* Jumlah harmonik musiman sin/cos: 1 = periode 12 bulan (manual), 2 = + periode 6 bulan
* (residual trade balance v2 masih berautokorelasi di lag 6 dan 12)
global seas_harm 2
* Prior mean own-lag trade balance (model changes). 0 = manual; 0.7 = sesuai autokorelasi TB
* (lag 1 = 0,69). Residual TB v3 masih berautokorelasi karena prior 0 + shrinkage ketat.
global tb_prior_mean 0.7
* 1 = jalankan uji unit root ADF + Phillips-Perron (01, bagian 1.6)
global run_adf 1
* Seed utama (setara set.seed(30102026) di Rmd)
global seed 30102026

* Jumlah posterior draws per tahap, mengikuti profile
if "$profile" == "quick" {
	global n_val 60
	global n_test 150
	global n_final 600
}
else if "$profile" == "standard" {
	global n_val 200
	global n_test 1000
	global n_final 6000
}
else if "$profile" == "publication" {
	global n_val 1000
	global n_test 5000
	global n_final 30000
}
else {
	di as error "profile harus quick, standard, atau publication"
	exit 198
}

**## 0.2 Rancangan eksperimen (ditetapkan sebelum melihat hasil)
* Horizon evaluasi (bulan) dan jeda rilis makro konservatif
global horizons "1 3 6"
global release_lag 2
* Grid validation: start year, lag, lambda (shrinkage)
global grid_start "2013 2014 2017"
global grid_p "1 2"
* lambda diperluas ke 0.03/0.05: v3 memilih 0.10 = batas bawah grid lama
global grid_lambda "0.03 0.05 0.10 0.30"
* Eksogen opsional, dipilih validation: UST10Y (level), selisih BI rate - Fed funds (level, pp),
* VIX (perubahan log). UST sudah diuji di v3.3 dan tidak terpilih, jadi grid_ust = 0 untuk menghemat waktu.
global grid_ust "0"
* selisih suku bunga ditolak validation di v3.3 dan v3.4 -> 0 untuk menghemat waktu
global grid_rate "0"
* VIX dan dummy ditetapkan dari hasil v3.5 (dummy terpilih; VIX tidak terpilih bersama dummy)
global grid_vix "0"
* Impulse dummy bulan ekstrem (|perubahan kurs| > 2,5 sd): 1 di bulan itu, 0 lainnya; dipilih validation
global grid_dum "1"
* Prior UIP: selisih BI-Fed masuk persamaan kurs dengan koefisien berpusat di 1/12 (depresiasi = selisih
* suku bunga per bulan); 0/1 dipilih validation. uip_sd = sd prior (satuan terstandar)
global grid_uip "0 1"
global uip_sd 0.05
* Bayesian Model Averaging (09_bma.do): regresi prediktif langsung, 6 prediktor, g-prior tetap
global run_bma 1
global bma_preds "ds ddxy dust flow2 tb2 dres2"
* g dikunci ke 0.25: terpilih di validation run 30 Okt 2026 18:05 dari grid 0.25/1/4/n
* (skor 0,968 / 0,973 / 0,992 / 0,987). Kembalikan ke "0.25 1 4 n" untuk validasi ulang g.
global bma_g_grid "0.25"
global bma_start 2014
global bma_inc 0.5
global outlier_months "2015m10 2018m11 2020m3 2020m4"
* Origin validation (Jan 2021 - Jun 2023) dan awal test (Jan 2024)
global val_from = ym(2021,1)
global val_to   = ym(2023,6)
global test_from = ym(2024,1)
* Horizon final forecast dan skenario
global H_final 6
* Model: BVARX dalam perubahan (changes) untuk validation, test, forecast, dan skenario.
* USD/IDR, cadangan, DXY = perubahan 100*log bulanan; TB dan flows = arus bulanan.
* Versi level (v1-v2, menarik kurs ke rata-rata sampel) diarsipkan di archive/v2_levels/.
global model_mode "changes"
* Asumsi skenario per bulan dibaca dari sheet ini di $data_file (06_final_scenarios.do):
* DXY kumulatif vs anchor (%), geser TB (USD bn) dan flows (Rp tn) terhadap median baseline;
* sel TB/flows kosong = bulan itu tidak dikunci. Default: Adverse DXY +2%, TB -1, flows -10;
* Upside kebalikannya; Severe Adverse DXY +5%, TB -2, flows -30 (TB/flows dikunci di h = 3 dan 6).
global scen_sheet "scenario_inputs"

set seed $seed

**## 0.3 Log
cap log close main
log using "$results\run_log.log", replace text name(main)
di "Mulai: `c(current_date)' `c(current_time)'  profile=$profile"
timer clear 1
timer on 1

*****************************
******** Run modules ********
*****************************

* 01: impor dan audit database, unit root, deskriptif
do "$script\01_import_audit.do"
* 02: fungsi Mata BVARX (estimasi, draw, conditional forecast, backtest)
do "$script\02_bvarx_functions.do"
* 03: validation grid -> spesifikasi terkunci
do "$script\03_validation.do"
* 04: test terkunci vs random walk, bootstrap relative RMSE
do "$script\04_test.do"
* 06: fit akhir, diagnostik, baseline dan skenario bersyarat
do "$script\06_final_scenarios.do"
* 07: ekspor ringkasan Excel dan narasi hasil
do "$script\07_export.do"
* 08: perbandingan forecast akhir: BVARX changes, random walk, random walk + drift, kombinasi
do "$script\08_forecast_compare.do"
* 09: Bayesian Model Averaging (bmaregress) vs random walk tanpa drift
if $run_bma do "$script\09_bma.do"
* 10: model gabungan: Baseline BMA + selisih skenario BVARX (butuh 06 dan 09)
if $run_bma do "$script\10_hybrid.do"

timer off 1
timer list 1
di "Selesai: `c(current_date)' `c(current_time)'"
log close main
