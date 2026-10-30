**# 8. PERBANDINGAN FORECAST AKHIR ANTAR MODEL (orientasi forecast operasional)
* Forecast Okt 2026 - Mar 2027 dari anchor final_origin, DXY datar (baseline).
* Model:
*   bvar_levels      BVARX level, spesifikasi terkunci (soc dari validation)
*   bvar_levels_soc  BVARX level + dummy sum-of-coefficients/initial-observation (soc = 1)
*   bvar_changes     BVARX changes (tanpa tarikan ke rata-rata)
*   rw               random walk tanpa drift
*   rw_drift         random walk + drift selisih suku bunga BI - Fed (logika forward rate)
*   combo            rata-rata median bvar_changes dan rw_drift
* Interval RW: volatilitas historis log-return bulanan seluruh sampel.
* Menulis: intermediate/forecast_compare.dta
* Output:  tables/T12_forecast_compare, T13_forecast_compare_wide; figures/8_forecast_compare.png

local chz = "strtoreal(tokens(st_global(" + char(34) + "cond_horizons" + char(34) + ")))"
tempfile acc
local first 1
local k 0
foreach spec in "levels $best_soc bvar_levels" "levels 1 bvar_levels_soc" "changes 0 bvar_changes" {
	local ++k
	tokenize `spec'
	use "$data\database.dta", clear
	mata: D = bv_load("`1'")
	mata: bv_final_run($latest_complete, $final_origin, $H_final, $best_start, $best_p, $best_lambda, ///
		$include_ust, $n_final, $shock_mat, `chz', `2')
	mata: bv_tostata(select(FIN_tab, FIN_tab[., 1] :== 1), ("scenario", "mdate", "lower95", "lower80", "median", "upper80", "upper95", "ess", "ess_ratio"))
	gen str16 model = "`3'"
	gen byte model_id = `k'
	drop scenario ess ess_ratio
	if !`first' append using `acc'
	save `acc', replace
	local first 0
}

**## 8.1 Random walk dan random walk + drift
use "$data\database.dta", clear
tsset mdate, monthly
gen double dl = D.y_s/100
qui sum dl
local sig = r(sd)
qui sum usdidr if mdate == $final_origin
local s0 = r(mean)
qui sum bi_ff_diff_pp if mdate == $final_origin
local drift = r(mean)/100/12
di "Anchor " %9.0f `s0' "; vol bulanan " %6.4f `sig' "; drift per bulan (BI-Fed/12) " %7.5f `drift'
clear
set obs $H_final
gen mdate = $final_origin + _n
gen h = _n
expand 2
bysort mdate: gen byte rwtype = _n
gen double dr = cond(rwtype == 2, `drift', 0)
gen double median  = `s0'*exp(dr*h)
gen double lower80 = `s0'*exp(dr*h + invnormal(0.10)*sqrt(h)*`sig')
gen double upper80 = `s0'*exp(dr*h + invnormal(0.90)*sqrt(h)*`sig')
gen double lower95 = `s0'*exp(dr*h + invnormal(0.025)*sqrt(h)*`sig')
gen double upper95 = `s0'*exp(dr*h + invnormal(0.975)*sqrt(h)*`sig')
gen str16 model = cond(rwtype == 1, "rw", "rw_drift")
gen byte model_id = cond(rwtype == 1, 4, 5)
drop h rwtype dr
append using `acc'

**## 8.2 Kombinasi: rata-rata median bvar_changes dan rw_drift
preserve
	keep if inlist(model, "bvar_changes", "rw_drift")
	collapse (mean) median lower80 upper80 lower95 upper95, by(mdate)
	gen str16 model = "combo"
	gen byte model_id = 6
	tempfile cb
	save `cb'
restore
append using `cb'
gen double spot_anchor = `s0'
gen double pct_vs_anchor = 100*(median/spot_anchor - 1)
sort model_id mdate
order model_id model mdate lower95 lower80 median upper80 upper95 pct_vs_anchor
format mdate %tm
format lower* median upper* spot_anchor %9.0f
format pct_vs_anchor %6.2f
save "$data\forecast_compare.dta", replace
list model mdate lower80 median upper80 pct_vs_anchor, noobs sepby(model)
bv_out tab "T12_forecast_compare"

* Tabel ringkas: median per model (kolom) per bulan (baris)
preserve
	keep model mdate median
	replace median = round(median)
	reshape wide median, i(mdate) j(model) string
	rename median* *
	list, noobs clean
	bv_out tab "T13_forecast_compare_wide"
restore

**## 8.3 Grafik
keep model_id mdate median
reshape wide median, i(mdate) j(model_id)
tempfile w
save `w'
use mdate usdidr using "$data\database.dta", clear
keep if mdate > $final_origin - 24 & mdate <= $final_origin
append using `w'
sort mdate
forval m = 1/6 {
	replace median`m' = usdidr if mdate == $final_origin
}
twoway (line usdidr mdate, lcolor(black) lwidth(medthick)) ///
	(line median1 mdate, lcolor("24 90 141") lwidth(medthick)) ///
	(line median2 mdate, lcolor("24 90 141") lpattern(dash)) ///
	(line median3 mdate, lcolor("35 114 74") lwidth(medthick)) ///
	(line median4 mdate, lcolor(gs8) lpattern(shortdash)) ///
	(line median5 mdate, lcolor("164 87 23") lwidth(medthick)) ///
	(line median6 mdate, lcolor(purple) lwidth(medthick) lpattern(longdash)), ///
	xline($final_origin, lcolor(gs10) lpattern(dot)) ///
	title("USD/IDR: forecast median per model (DXY datar)", size(medium)) ///
	xtitle("") ytitle("IDR per USD") xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) ///
	legend(order(1 "Aktual" 2 "BVARX level" 3 "BVARX level + dummy" 4 "BVARX changes" ///
		5 "Random walk" 6 "RW + drift BI-Fed" 7 "Kombinasi") rows(2) size(small) position(6)) ///
	graphregion(color(white)) name(fc_compare, replace)
graph save "$gph\8_forecast_compare.gph", replace
graph export "$fig\8_forecast_compare.png", replace width(1800)
