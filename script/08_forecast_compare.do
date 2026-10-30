**# 8. PERBANDINGAN FORECAST AKHIR: BVARX CHANGES VS BENCHMARK
* Forecast Okt 2026 - Mar 2027 dari anchor final_origin (Baseline, DXY datar).
* Model:
*   1 bvar      BVARX changes (spesifikasi terkunci, baseline dari 06)
*   2 rw        random walk tanpa drift
*   3 rw_drift  random walk + drift selisih suku bunga BI - Fed (logika forward rate)
*   4 combo     rata-rata bvar dan rw_drift (median dan batas interval)
* Interval RW: volatilitas historis log-return bulanan seluruh sampel.
* Menulis: intermediate/forecast_compare.dta
* Output:  tables/T12_forecast_compare, T13_forecast_compare_wide;
*          figures/8_forecast_compare.png, 8_forecast_compare_table.png

**## 8.1 BVARX: baseline dari 06
use "$data\scenario_spot.dta", clear
keep if scenario == 1
keep mdate lower95 lower80 median upper80 upper95
gen str16 model = "bvar"
gen byte model_id = 1
tempfile acc
save `acc'

**## 8.2 Random walk dan random walk + drift
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
gen byte model_id = cond(rwtype == 1, 2, 3)
drop h rwtype dr
append using `acc'

**## 8.3 Kombinasi: rata-rata bvar dan rw_drift
preserve
	keep if inlist(model, "bvar", "rw_drift")
	collapse (mean) median lower80 upper80 lower95 upper95, by(mdate)
	gen str16 model = "combo"
	gen byte model_id = 4
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

**## 8.4 Grafik
preserve
	keep model_id mdate median
	reshape wide median, i(mdate) j(model_id)
	tempfile w
	save `w'
	use mdate usdidr using "$data\database.dta", clear
	keep if mdate > $final_origin - 24 & mdate <= $final_origin
	append using `w'
	sort mdate
	forval m = 1/4 {
		replace median`m' = usdidr if mdate == $final_origin
	}
	twoway (line usdidr mdate, lcolor(black) lwidth(medthick)) ///
		(line median1 mdate, lcolor("24 90 141") lwidth(medthick)) ///
		(line median2 mdate, lcolor(gs8) lpattern(shortdash)) ///
		(line median3 mdate, lcolor("164 87 23") lwidth(medthick) lpattern(dash)) ///
		(line median4 mdate, lcolor(purple) lwidth(medthick) lpattern(longdash)), ///
		xline($final_origin, lcolor(gs10) lpattern(dot)) ///
		title("USD/IDR: forecast median BVARX vs benchmark (Baseline, DXY datar)", size(medium)) ///
		xtitle("") ytitle("IDR per USD") xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) ///
		legend(order(1 "Aktual" 2 "BVARX ($model_mode)" 3 "Random walk" 4 "RW + drift BI-Fed" 5 "Kombinasi") ///
			rows(1) size(small) position(6)) ///
		graphregion(color(white)) name(fc_compare, replace)
	graph save "$gph\8_forecast_compare.gph", replace
	graph export "$fig\8_forecast_compare.png", replace width(1800)
restore

**## 8.5 Tabel PNG: forecast median [rentang 80%] per model
* Skor test (relative RMSE vs RW) untuk catatan kaki, dari 04_test
local sc ""
preserve
	use "$data\test_scores.dta", clear
	sort horizon
	forval i = 1/`=_N' {
		local sep = cond(`i' > 1, "/", "")
		local sc `sc'`sep'`=strtrim(string(relative_rmse[`i'], "%4.2f"))'
	}
restore
gen str32 cell = strtrim(string(median, "%9.0fc")) + "  [" + strtrim(string(lower80, "%9.0fc")) + " - " + strtrim(string(upper80, "%9.0fc")) + "]"
keep model_id mdate cell
reshape wide cell, i(mdate) j(model_id)
gen str12 bulan = string(mdate, "%tmMon_CCYY")
sort mdate
bv_pngtable bulan cell1 cell2 cell3 cell4, file("$fig\8_forecast_compare_table.png") ///
	title("Forecast USD/IDR per model: median [rentang 80%] (Baseline, DXY datar)") ///
	heads("Bulan" "BVARX ($model_mode)" "Random walk" "RW + drift BI-Fed" "Kombinasi") ///
	widths(14 26 26 26 26) ///
	note("Kombinasi = rata-rata BVARX dan RW + drift. Test 2024-2026, relative RMSE BVARX vs random walk (h = 1/3/6): `sc' (< 1 = lebih akurat).")
