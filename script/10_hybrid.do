**# 10. MODEL GABUNGAN: BASELINE BMA + SELISIH SKENARIO BVARX
* Baseline = forecast BMA (09): paling akurat out-of-sample (test 2024-2026, relative RMSE
*            0,99 / 0,94 / 0,86; Clark-West signifikan 5% di h = 6).
* Skenario  = baseline BMA x rasio (median skenario BVARX / median Baseline BVARX) per bulan.
*            BVARX dipakai untuk efek bersyarat DXY, trade balance, dan flows (06), karena BMA
*            (regresi prediktif langsung) tidak menerima jalur variabel ke depan.
* Rentang   = rentang BMA digeser dengan rasio yang sama (lebar relatif tetap). Rentang ini memuat
*            ketidakpastian forecast BMA, bukan ketidakpastian tambahan dari jalur skenario.
* Menulis: intermediate/hybrid_scenarios.dta
* Output:  tables/T15_hybrid_scenarios, T16_hybrid_summary, T17_hybrid_baseline_test,
*          T18_hybrid_scenario_assumptions, T19_hybrid_forecast_compare;
*          figures/10_hybrid_fan, 10_hybrid_table, 10_hybrid_scenario_table, 10_hybrid_macro,
*          10_test_h1/h3/h6, 10_test_rmse, 10_forecast_compare, 10_forecast_compare_table (.png)

**## 10.1 Rasio skenario BVARX terhadap Baseline BVARX
use "$data\scenario_spot.dta", clear
keep scenario mdate median
bysort mdate: egen double base_bvarx = max(cond(scenario == 1, median, .))
gen double ratio = median/base_bvarx
rename median median_bvarx
tempfile rat
save `rat'

**## 10.2 Gabungkan dengan forecast BMA
use "$data\bma_final.dta", clear
keep mdate median lower80 upper80 lower95 upper95
rename (median lower80 upper80 lower95 upper95) (bma_median bma_lower80 bma_upper80 bma_lower95 bma_upper95)
merge 1:m mdate using `rat', assert(match) nogen
foreach v in median lower80 upper80 lower95 upper95 {
	gen double `v' = bma_`v'*ratio
}
gen double spot_anchor = $anchor_spot
gen double pct_vs_anchor = 100*(median/spot_anchor - 1)
gen double scen_shift_pct = 100*(ratio - 1)
bv_scenlab
sort scenario mdate
order scenario mdate median lower80 upper80 lower95 upper95 pct_vs_anchor scen_shift_pct ///
	median_bvarx bma_median
format mdate %tm
format median lower* upper* spot_anchor median_bvarx bma_median %9.0f
format pct_vs_anchor scen_shift_pct ratio %6.2f
save "$data\hybrid_scenarios.dta", replace
list scenario mdate lower80 median upper80 pct_vs_anchor scen_shift_pct, noobs sepby(scenario)
bv_out tab "T15_hybrid_scenarios"

* Ringkasan pada akhir horizon
preserve
	keep if mdate == $final_origin + $H_final
	keep scenario mdate median lower80 upper80 lower95 upper95 pct_vs_anchor scen_shift_pct
	list, noobs clean
	bv_out tab "T16_hybrid_summary"
restore

**## 10.3 Tabel PNG: forecast bulanan per skenario
preserve
	gen str32 cell = strtrim(string(median, "%9.0fc")) + "  [" + strtrim(string(lower80, "%9.0fc")) + " - " + strtrim(string(upper80, "%9.0fc")) + "]"
	keep scenario mdate cell
	reshape wide cell, i(mdate) j(scenario)
	gen str12 bulan = string(mdate, "%tmMon_CCYY")
	sort mdate
	bv_pngtable bulan cell1 cell2 cell3 cell4, file("$fig\10_hybrid_table.png") ///
		title("Forecast USD/IDR per skenario: median [rentang 80%], anchor `: di %tmMon_CCYY $final_origin' = `=strtrim(string($anchor_spot, "%9.0fc"))'") ///
		heads("Bulan" "Baseline (BMA)" "Adverse" "Upside" "Severe Adverse") widths(14 26 26 26 26) ///
		note("Baseline = BMA. Skenario = Baseline BMA x (skenario / baseline) BVARX. Rentang = interval prediktif 80% BMA, digeser sesuai skenario.")
restore

**## 10.4 Fan chart: riwayat 24 bulan + Baseline BMA (band 80/95%) + median skenario
keep scenario mdate median lower80 upper80 lower95 upper95
reshape wide median lower80 upper80 lower95 upper95, i(mdate) j(scenario)
tempfile hw
save `hw'
use mdate usdidr using "$data\database.dta", clear
keep if mdate > $final_origin - 24 & mdate <= $final_origin
append using `hw'
sort mdate
forval s = 1/4 {
	replace median`s' = usdidr if mdate == $final_origin
}
local anch : di %tmMon_CCYY $final_origin
twoway (rarea lower951 upper951 mdate, color("24 90 141%10") lwidth(none)) ///
	(rarea lower801 upper801 mdate, color("24 90 141%22") lwidth(none)) ///
	(line usdidr mdate, lcolor(black) lwidth(medthick)) ///
	(line median1 mdate, lcolor("24 90 141") lwidth(medthick)) ///
	(line median2 mdate, lcolor("164 87 23") lwidth(medthick) lpattern(dash)) ///
	(line median3 mdate, lcolor("35 114 74") lwidth(medthick) lpattern(shortdash)) ///
	(line median4 mdate, lcolor("170 30 30") lwidth(medthick) lpattern(longdash)), ///
	xline($final_origin, lcolor(gs10) lpattern(dot)) ///
	title("USD/IDR: Baseline BMA dan skenario (efek skenario dari BVARX)", size(medium)) ///
	subtitle("Band Baseline BMA 80% dan 95%; anchor `anch'", size(small)) ///
	xtitle("") ytitle("IDR per USD") xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) ///
	legend(order(3 "Aktual" 4 "Baseline (BMA)" 5 "Adverse" 6 "Upside" 7 "Severe Adverse" 2 "Band 80%" 1 "Band 95%") rows(2) size(small) position(6)) ///
	graphregion(color(white)) name(hybrid_fan, replace)
graph save "$gph\10_hybrid_fan.gph", replace
graph export "$fig\10_hybrid_fan.png", replace width(1800)

**## 10.5 Tabel PNG ringkasan skenario: asumsi makro (BVARX) + hasil USD/IDR (gabungan)
use "$data\scenario_macro_paths.dta", clear
keep if inlist(mdate, $final_origin + 3, $final_origin + 6)
gen byte hh = mdate - $final_origin
keep scenario hh dxy tb flows
reshape wide dxy tb flows, i(scenario) j(hh)
gen double dxy_pct6 = 100*(dxy6/$dxy0 - 1)
tempfile mac
save `mac'
use "$data\hybrid_scenarios.dta", clear
keep if inlist(mdate, $final_origin + 3, $final_origin + 6)
gen byte hh = mdate - $final_origin
keep scenario hh median lower80 upper80
reshape wide median lower80 upper80, i(scenario) j(hh)
merge 1:1 scenario using `mac', nogen
bv_scenlab
sort scenario
gen double pct6 = 100*(median6/$anchor_spot - 1)
keep scenario dxy_pct6 tb3 tb6 flows3 flows6 median3 median6 lower806 upper806 pct6
order scenario dxy_pct6 tb3 tb6 flows3 flows6 median3 median6 lower806 upper806 pct6
save "$data\hybrid_summary_table.dta", replace
bv_out tab "T18_hybrid_scenario_assumptions"
gen str24 c1 = ""
gen str12 c2 = cond(dxy_pct6 >= 0, "+", "") + strtrim(string(dxy_pct6, "%5.1f")) + "%"
gen str10 c3 = strtrim(string(tb3, "%5.1f"))
gen str10 c4 = strtrim(string(tb6, "%5.1f"))
gen str10 c5 = strtrim(string(flows3, "%6.1f"))
gen str10 c6 = strtrim(string(flows6, "%6.1f"))
gen str12 c7 = strtrim(string(median3, "%9.0fc"))
gen str40 c8 = strtrim(string(median6, "%9.0fc")) + " [" + strtrim(string(lower806, "%9.0fc")) + "-" + strtrim(string(upper806, "%9.0fc")) + "]"
gen str10 c9 = cond(pct6 >= 0, "+", "") + strtrim(string(pct6, "%5.1f")) + "%"
forval i = 1/`=_N' {
	local sl : label scen `=scenario[`i']'
	qui replace c1 = "`sl'" in `i'
}
local m0 : di %tmMon_YY $final_origin
local m3 : di %tmMon_YY $final_origin + 3
local m6 : di %tmMon_YY $final_origin + 6
bv_pngtable c1 c2 c3 c4 c5 c6 c7 c8 c9, file("$fig\10_hybrid_scenario_table.png") ///
	title("Ringkasan skenario USD/IDR: Baseline BMA, efek skenario dari BVARX (anchor `: di %tmMon_CCYY $final_origin' = `=strtrim(string($anchor_spot, "%9.0fc"))')") ///
	heads("Skenario" "DXY `m6'" "TB `m3'" "TB `m6'" "Flows `m3'" "Flows `m6'" "USD/IDR `m3'" "USD/IDR `m6' [80%]" "vs `m0'") ///
	widths(18 11 10 10 12 12 14 26 10) ///
	note("Asumsi DXY/TB/flows dan efek skenario dari BVARX; Baseline dan rentang dari BMA. TB dalam USD bn, flows dalam Rp tn.")

**## 10.6 Grafik asumsi makro per skenario (sama dengan input skenario BVARX)
graph use "$gph\6_scenario_macro.gph"
graph export "$fig\10_hybrid_macro.png", replace width(2600)

**## 10.7 Backtest baseline (BMA): aktual vs baseline vs RW, RMSE, dan coverage interval
use "$data\bma_test_backtest.dta", clear
gen target = origin + h
format target %tm
gen double point   = rw*exp(yhat/100)
gen double lower80 = rw*exp((yhat - invnormal(0.90)*ysd)/100)
gen double upper80 = rw*exp((yhat + invnormal(0.90)*ysd)/100)
gen double lower95 = rw*exp((yhat - invnormal(0.975)*ysd)/100)
gen double upper95 = rw*exp((yhat + invnormal(0.975)*ysd)/100)
gen byte c80 = actual >= lower80 & actual <= upper80
gen byte c95 = actual >= lower95 & actual <= upper95
preserve
	collapse (mean) coverage80 = c80 coverage95 = c95, by(h)
	rename h horizon
	merge 1:1 horizon using "$data\bma_test_scores.dta", keepusing(relative_rmse cw_p dm_p direction) nogen
	order horizon relative_rmse cw_p dm_p direction coverage80 coverage95
	format relative_rmse cw_p dm_p direction coverage* %6.3f
	list, noobs clean
	bv_out tab "T17_hybrid_baseline_test"
restore
foreach hh of global horizons {
	twoway (rarea lower80 upper80 target if h == `hh', color("24 90 141%15") lwidth(none)) ///
		(line actual target if h == `hh', lcolor(black) lwidth(medthick)) ///
		(line point target if h == `hh', lcolor("24 90 141") lwidth(medthick)) ///
		(line rw target if h == `hh', lcolor("164 87 23") lpattern(dash)), ///
		title("Test: horizon `hh' bulan (BMA)", size(medium)) ///
		xtitle("Bulan target") ytitle("IDR per USD") ///
		legend(order(2 "Aktual" 3 "Baseline (BMA)" 4 "Random walk" 1 "Band 80%") rows(1) size(small) position(6)) ///
		xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) graphregion(color(white)) name(htest`hh', replace)
	graph export "$fig\10_test_h`hh'.png", replace width(1800)
}
use "$data\bma_test_scores.dta", clear
graph bar rmse_bma rmse_rw, over(horizon, relabel(1 "h=1" 2 "h=3" 3 "h=6")) ///
	bar(1, color("24 90 141")) bar(2, color("164 87 23")) ///
	legend(order(1 "Baseline (BMA)" 2 "Random walk") rows(1) position(6)) ///
	ytitle("RMSE (IDR per USD)") blabel(bar, format(%9.0f) size(vsmall)) ///
	title("Test 2024-2026: RMSE BMA vs random walk", size(medium)) ///
	graphregion(color(white)) name(htest_rmse, replace)
graph export "$fig\10_test_rmse.png", replace width(1800)

**## 10.8 Perbandingan forecast: BMA vs BVARX vs random walk
* RW + drift BI-Fed tetap ada di tabel komponen (T12/T13, T6_benchmarks), tidak ditampilkan di gambar.
use "$data\forecast_compare.dta", clear
keep if inlist(model, "bvar", "rw")
keep model mdate median lower80 upper80
tempfile fcm
save `fcm'
use "$data\bma_final.dta", clear
keep mdate median lower80 upper80
gen str16 model = "bma"
append using `fcm'
gen byte model_id = cond(model == "bma", 1, cond(model == "bvar", 2, 3))
sort model_id mdate
save "$data\hybrid_forecast_compare.dta", replace
bv_out tab "T19_hybrid_forecast_compare"
preserve
	gen str32 cell = strtrim(string(median, "%9.0fc")) + "  [" + strtrim(string(lower80, "%9.0fc")) + " - " + strtrim(string(upper80, "%9.0fc")) + "]"
	keep model_id mdate cell
	reshape wide cell, i(mdate) j(model_id)
	gen str12 bulan = string(mdate, "%tmMon_CCYY")
	sort mdate
	bv_pngtable bulan cell1 cell2 cell3, file("$fig\10_forecast_compare_table.png") ///
		title("Forecast USD/IDR per model: median [rentang 80%] (Baseline, DXY datar)") ///
		heads("Bulan" "BMA" "BVARX" "Random walk") widths(14 28 28 28) ///
		note("BMA = Baseline. BVARX dipakai untuk efek skenario; forecast baseline-nya ditampilkan sebagai pembanding.")
restore
keep model_id mdate median
reshape wide median, i(mdate) j(model_id)
tempfile cw
save `cw'
use mdate usdidr using "$data\database.dta", clear
keep if mdate > $final_origin - 24 & mdate <= $final_origin
append using `cw'
sort mdate
forval m = 1/3 {
	replace median`m' = usdidr if mdate == $final_origin
}
twoway (line usdidr mdate, lcolor(black) lwidth(medthick)) ///
	(line median1 mdate, lcolor("24 90 141") lwidth(thick)) ///
	(line median2 mdate, lcolor(purple) lpattern(dash)) ///
	(line median3 mdate, lcolor("164 87 23") lpattern(longdash)), ///
	xline($final_origin, lcolor(gs10) lpattern(dot)) ///
	title("USD/IDR: forecast median per model (Baseline, DXY datar)", size(medium)) ///
	xtitle("") ytitle("IDR per USD") xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) ///
	legend(order(1 "Aktual" 2 "BMA" 3 "BVARX" 4 "Random walk") rows(1) size(small) position(6)) ///
	graphregion(color(white)) name(hybrid_cmp, replace)
graph export "$fig\10_forecast_compare.png", replace width(1800)
