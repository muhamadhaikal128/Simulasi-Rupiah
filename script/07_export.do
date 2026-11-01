**# 7. EKSPOR RINGKASAN, SETTINGS, DAN NARASI HASIL
* Rmd: chunk narasi-hasil, ekspor-audit.
* Output: tables/S0_settings, A0_database_imported; output/narasi_hasil.txt
*         (semua tabel juga ada sebagai sheet di output/rupiah_bvarx_results.xlsx)

**## 7.1 Settings penelitian (reproduksibilitas)
clear
local items profile seed n_val n_test n_final horizons release_lag ///
	grid_start grid_p grid_lambda grid_ust grid_rate grid_vix grid_dum grid_uip uip_sd best_start best_p best_lambda best_ust best_rate best_vix best_dum best_uip outlier_months H_final model_mode seas_harm tb_prior_mean scen_sheet cond_steps
local n : word count `items'
set obs `=`n'+6'
gen str24 setting = ""
gen str60 value = ""
local i 0
foreach s of local items {
	local ++i
	replace setting = "`s'" in `i'
	replace value = "${`s'}" in `i'
}
local ++i
replace setting = "validation_origins" in `i'
replace value = "`: di %tm $val_from' - `: di %tm $val_to'" in `i'
local ++i
replace setting = "test_origins" in `i'
replace value = "`: di %tm $test_from' - `: di %tm $test_to'" in `i'
local ++i
replace setting = "latest_complete" in `i'
replace value = "`: di %tm $latest_complete'" in `i'
local ++i
replace setting = "final_origin" in `i'
replace value = "`: di %tm $final_origin'" in `i'
local ++i
replace setting = "stata_version" in `i'
replace value = "`c(stata_version)' `c(edition_real)'" in `i'
local ++i
replace setting = "run_date" in `i'
replace value = "`c(current_date)' `c(current_time)'" in `i'
list, noobs clean
bv_out tab "S0_settings"

**## 7.2 Database yang diimpor
use "$data\database.dta", clear
drop y_* dy_* x_* dx_* sin12 cos12 date
bv_out tab "A0_database_imported"

**## 7.3 Narasi hasil (terisi otomatis)
use "$data\test_scores.dta", clear
tempname fh
file open `fh' using "$results\narasi_hasil.txt", write replace text
file write `fh' "NARASI HASIL (draft otomatis, profile = $profile)" _n _n
file write `fh' "Spesifikasi terpilih dalam grid menggunakan awal sampel $best_start, lag $best_p, dan lambda " %4.2f ($best_lambda) " (model $model_mode). "
file write `fh' "Pemilihannya menggunakan validation, sedangkan hasil berikut berasal dari test yang terpisah." _n _n
forval i = 1/`=_N' {
	file write `fh' "Pada horizon " %1.0f (horizon[`i']) " bulan, relative RMSE adalah " %5.3f (relative_rmse[`i'])
	file write `fh' ", dengan RMSE BVARX " %7.1f (rmse_bvar[`i']) " dan RW " %7.1f (rmse_rw[`i']) " rupiah per USD. "
	if relative_rmse[`i'] < 1 file write `fh' "BVARX mempunyai error lebih kecil secara deskriptif pada horizon ini. "
	else file write `fh' "Random walk mempunyai error lebih kecil secara deskriptif pada horizon ini. "
	file write `fh' "Coverage 80%/95%: " %4.2f (coverage80[`i']) "/" %4.2f (coverage95[`i']) ". "
	file write `fh' "Temuan ini belum menyatakan keunggulan signifikan dan tetap bergantung pada information set serta vintage data." _n _n
}
use "$data\test_bootstrap.dta", clear
keep if block == 6
forval i = 1/`=_N' {
	file write `fh' "Bootstrap (blok 6) h=" %1.0f (horizon[`i']) ": interval 95% relative RMSE " %5.3f (lower[`i']) "-" %5.3f (upper[`i'])
	if covers_one[`i'] file write `fh' " (meliputi 1: belum ada bukti kuat mengungguli RW)." _n
	else file write `fh' " (tidak meliputi 1)." _n
}
file write `fh' _n
use "$data\scenario_spot.dta", clear
keep if mdate == $final_origin + $H_final
forval i = 1/`=_N' {
	local sc : label scen `=scenario[`i']'
	file write `fh' "Skenario `sc': median USD/IDR pada `: di %tmMon_CCYY $final_origin + $H_final' adalah " %7.0f (median[`i'])
	file write `fh' ", dengan rentang predictive 80% " %7.0f (lower80[`i']) "-" %7.0f (upper80[`i']) "." _n
}
file write `fh' _n "Bersyarat pada jalur DXY dan pembatasan observabel yang dijelaskan. Skenario adalah proyeksi bersama model, bukan estimasi efek kausal tunggal." _n
file close `fh'
type "$results\narasi_hasil.txt"
