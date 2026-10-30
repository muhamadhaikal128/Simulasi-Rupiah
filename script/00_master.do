**# 0. MASTER: Forecast dan skenario USD/IDR dengan BVARX
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
*   output/figures      grafik PNG siap pakai
*   output/tables       tabel hasil (CSV), juga disalin ke workbook ringkasan
*   output/diagnostics  uji dan diagnostik (unit root, residual, ESS, akar companion)
*   output/gph          grafik kerja Stata (.gph)
global results "$base\output"
global fig "$results\figures"
global tab "$results\tables"
global diag "$results\diagnostics"
global gph "$results\gph"
global xlsx "$results\rupiah_bvarx_results.xlsx"
foreach d in data results fig tab diag gph {
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

**## 0.1 Parameter manual (setara blok params di Rmd)
* profile: quick (cek alur) | standard | publication (angka untuk naskah)
global profile "standard"
* 1 = tambahkan UST10Y sebagai eksogen (putuskan di tahap validation)
global include_ust 0
* 1 = jalankan sensitivity spesifikasi changes
global run_sensitivity 1
* 1 = jalankan uji ADF (01, bagian 1.6). Sementara 0: loop ADF macet di sesi MCP, sedang di-debug
global run_adf 0
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
global grid_lambda "0.10 0.30"
* Origin validation (Jan 2021 - Jun 2023) dan awal test (Jan 2024)
global val_from = ym(2021,1)
global val_to   = ym(2023,6)
global test_from = ym(2024,1)
* Horizon final forecast dan skenario
global H_final 6
* Skenario ilustratif: titik pembatas (bulan ke-) dan besaran shock
global cond_horizons "3 6"
global dxy_shock 0.02
global tb_shock 1
global flows_shock 10

set seed $seed

**## 0.3 Log
cap log close main
log using "$results\run_log.log", replace text name(main)
di "Mulai: `c(current_date)' `c(current_time)'  profile=$profile  include_ust=$include_ust"
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
* 05: sensitivity changes
if $run_sensitivity do "$script\05_sensitivity.do"
* 06: fit akhir, diagnostik, baseline dan skenario bersyarat
do "$script\06_final_scenarios.do"
* 07: ekspor ringkasan Excel dan narasi hasil
do "$script\07_export.do"

timer off 1
timer list 1
di "Selesai: `c(current_date)' `c(current_time)'"
log close main
