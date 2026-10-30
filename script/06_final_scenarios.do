**# 6. FIT AKHIR, DIAGNOSTIK, BASELINE DAN SKENARIO BERSYARAT
* Rmd: chunk fit-akhir-diagnostik, baseline-snapshot, conditional-scenarios, plot-skenario.
* Fit sampai bulan lengkap terakhir (latest_complete); anchor pasar = final_origin.
* Bulan di antara cutoff dan anchor dijembatani dengan observasi yang sudah ada di snapshot
* (USD/IDR, flows, cadangan; TB September kosong dibiarkan tak teramati). Aturan bridge makro
* ini hanya untuk forecast akhir, TIDAK dipakai dalam backtest.
* Model = global model_mode (changes). Skenario ilustratif (bukan shock struktural),
* besaran di 00_master.do: pada h = 3 dan 6, TB dan flows digeser terhadap median baseline, dan DXY
* menuju (1 + g) pada akhir horizon. 2 Adverse, 3 Upside, 4 Severe Adverse.
* Menulis: intermediate/final_residuals.dta, scenario_*.dta
* Output:  tables/T7_baseline, T8_scenarios, T9_scenario_paths_all, T10_scenario_inputs,
*          T11_global_paths; diagnostics/D3_residual_tests, D4_residual_corr, D5_scenario_ess_roots,
*          D6_dxy_effect;
*          T14_scenario_summary; figures/6_residual_acf.png, 6_scenarios_fan.png,
*          6_scenario_macro.png, 6_scenario_table.png

**## 6.2 Jalankan fit akhir dan skenario
use "$data\database.dta", clear
mata: D = bv_load("$model_mode")
mata: bv_final_run($latest_complete, $final_origin, $H_final, $best_start, $best_p, $best_lambda, ///
	$include_ust, $n_final, $shock_mat, strtoreal(tokens(st_global("cond_horizons"))), 0)
mata: st_global("fin_n", strofreal(FIN_info[1])); st_global("fin_from", strofreal(FIN_info[2]))
di "Training akhir: " %tm $fin_from " sampai " %tm $latest_complete "; N = $fin_n"

* label skenario
cap program drop bv_scenlab
program define bv_scenlab
	label define scen 0 "bridge" 1 "Baseline" 2 "Adverse" 3 "Upside" 4 "Severe Adverse", replace
	label values scenario scen
end

**## 6.3 Diagnostik residual (training akhir)
mata: bv_tostata(FIN_resid, ("mdate", "res_s", "res_tb", "res_flows", "res_res"))
format mdate %tm
tsset mdate, monthly
save "$data\final_residuals.dta", replace

* SD, Ljung-Box Q(12) dan uji normalitas (skewness/kurtosis) per persamaan
tempname pr
postfile `pr' str10 equation N sd lb_q12 lb_p12 sk_skew_p sk_kurt_p sk_joint_p ///
	using "$data\residual_tests.dta", replace
foreach v in res_s res_tb res_flows res_res {
	qui sum `v'
	local sd = r(sd)
	local N = r(N)
	qui wntestq `v', lags(12)
	local q = r(stat)
	local qp = r(p)
	* sktest: r(Utest) = (Pr skewness, Pr kurtosis, chi2, Prob>chi2)
	local skp .
	local kup .
	local jp .
	cap qui sktest `v'
	if !_rc {
		tempname U
		matrix `U' = r(Utest)
		local skp = `U'[1, 1]
		local kup = `U'[1, 2]
		local jp = `U'[1, colsof(`U')]
	}
	post `pr' ("`v'") (`N') (`sd') (`q') (`qp') (`skp') (`kup') (`jp')
}
postclose `pr'
preserve
	use "$data\residual_tests.dta", clear
	gen str30 lb_conclusion = cond(lb_p12 < 0.05, "autokorelasi tersisa (p<0.05)", "tidak ada bukti autokorelasi")
	format sd lb_q12 %9.3f
	format lb_p12 sk_* %6.3f
	list, noobs clean
	bv_out diag "D3_residual_tests"
restore

* Korelasi residual antar persamaan
preserve
	qui corr res_s res_tb res_flows res_res
	matrix C = r(C)
	clear
	svmat double C, names(col)
	gen str10 variable = ""
	local i 0
	foreach v in res_s res_tb res_flows res_res {
		local ++i
		replace variable = "`v'" in `i'
	}
	order variable
	format res_* %6.3f
	list, noobs clean
	bv_out diag "D4_residual_corr"
restore

* ACF residual (12 lag)
local i 0
foreach v in res_s res_tb res_flows res_res {
	local ++i
	local t : word `i' of "USD/IDR" "Trade balance" "Flows" "Cadangan"
	ac `v', lags(12) title("Residual `t'", size(medium)) ytitle("") xtitle("Lag") ///
		graphregion(color(white)) name(acf`i', replace) nodraw
}
graph combine acf1 acf2 acf3 acf4, cols(2) graphregion(color(white)) name(resid_acf, replace)
graph save "$gph\6_residual_acf.gph", replace
graph export "$fig\6_residual_acf.png", replace width(1800)

**## 6.4 Tabel baseline dan skenario
mata: bv_tostata(FIN_tab, ("scenario", "mdate", "lower95", "lower80", "median", "upper80", "upper95", "ess", "ess_ratio"))
bv_scenlab
format mdate %tm
gen double spot_anchor = .
preserve
	use "$data\database.dta", clear
	qui sum usdidr if mdate == $final_origin
	global anchor_spot = r(mean)
restore
replace spot_anchor = $anchor_spot
gen double pct_vs_anchor = 100*(median/spot_anchor - 1)
format lower* median upper* spot_anchor %9.0f
format pct_vs_anchor ess_ratio %6.2f
format ess %9.0f
save "$data\scenario_spot.dta", replace
list scenario mdate lower80 median upper80 pct_vs_anchor ess_ratio, noobs sepby(scenario)
bv_out tab "T8_scenarios"
preserve
	keep if scenario == 1
	bv_out tab "T7_baseline"
restore

mata: bv_tostata(FIN_vars, ("scenario", "mdate", "usdidr_median", "trade_bal_usdbn_median", "net_flows_idrtn_median", "fx_reserves_usdbn_median"))
bv_scenlab
format mdate %tm
format *_median %9.2f
save "$data\scenario_paths_all.dta", replace
bv_out tab "T9_scenario_paths_all"

mata: bv_tostata(FIN_cond, ("scenario", "step", "mdate", "variable", "value_model"))
bv_scenlab
format mdate %tm
gen str8 var_name = word("y_s y_tb y_flows y_res", variable)
* nilai dalam satuan alami
* model changes: variabel 1 dan 4 berupa perubahan 100*log (persen), bukan level
gen double value_natural = cond(variable == 3, value_model*10, cond((variable == 1 | variable == 4) & "$model_mode" == "levels", exp(value_model/100), value_model))
save "$data\scenario_conditions.dta", replace
list, noobs sepby(scenario)
bv_out tab "T10_scenario_inputs"

mata: bv_tostata(FIN_glob, ("mdate", "dxy_baseline", "dxy_adverse", "dxy_upside", "dxy_severe"))
format mdate %tm
format dxy_* %9.3f
save "$data\scenario_global_paths.dta", replace
bv_out tab "T11_global_paths"

mata: bv_tostata(FIN_diag, ("scenario", "ess", "ess_ratio", "root_gt1", "root_gt105"))
bv_scenlab
format ess %9.0f
format ess_ratio root_* %6.3f
gen byte low_ess = ess < 100 | ess_ratio < 0.01
list, noobs clean
save "$data\scenario_diag.dta", replace
bv_out diag "D5_scenario_ess_roots"
qui count if low_ess
if r(N) di as error "PERHATIAN: setidaknya satu skenario mempunyai ESS rendah. Gunakan sebagai draft; tambah draw."

* Efek kontemporer DXY: +1% DXY pada bulan yang sama -> perubahan tiap variabel (posterior mean, interval 90%)
* Hanya dampak bulan yang sama; dampak lanjutan lewat dinamika lag tidak termasuk.
mata: bv_tostata(FIN_dxy, ("eq", "effect", "sd"))
gen str24 variable = word("USD/IDR TB Flows Cadangan", eq)
gen str24 unit = ""
replace unit = cond("$model_mode" == "changes", "% perubahan", "100*log level") if inlist(eq, 1, 4)
replace unit = "USD bn" if eq == 2
* flows dalam model = Rp10 tn -> Rp tn
foreach v in effect sd {
	replace `v' = `v'*10 if eq == 3
}
replace unit = "Rp tn" if eq == 3
gen double lo90 = effect - invnormal(0.95)*sd
gen double hi90 = effect + invnormal(0.95)*sd
gen str24 conclusion = cond(lo90 > 0 | hi90 < 0, "berbeda dari nol (90%)", "tidak jelas (interval meliputi 0)")
drop eq
order variable unit effect sd lo90 hi90 conclusion
format effect sd lo90 hi90 %8.3f
list, noobs clean
save "$data\dxy_effect.dta", replace
bv_out diag "D6_dxy_effect"

**## 6.5 Grafik: fan chart baseline + median skenario, dengan riwayat 24 bulan
use "$data\scenario_spot.dta", clear
keep scenario mdate lower95 lower80 median upper80 upper95
reshape wide lower95 lower80 median upper80 upper95, i(mdate) j(scenario)
tempfile fc
save `fc'
use mdate usdidr using "$data\database.dta", clear
keep if mdate > $final_origin - 24 & mdate <= $final_origin
append using `fc'
sort mdate
* sambungkan garis median ke anchor
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
	title("USD/IDR: proyeksi bersyarat pada jalur skenario (model $model_mode)", size(medium)) ///
	subtitle("Band baseline 80% dan 95%; anchor `anch'", size(small)) ///
	xtitle("") ytitle("IDR per USD") xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) ///
	legend(order(3 "Aktual" 4 "Baseline" 5 "Adverse" 6 "Upside" 7 "Severe Adverse" 2 "Band 80%" 1 "Band 95%") rows(2) size(small) position(6)) ///
	graphregion(color(white)) name(scen_fan, replace)
graph save "$gph\6_scenarios_fan.gph", replace
graph export "$fig\6_scenarios_fan.png", replace width(1800)


**## 6.6 Asumsi makro per skenario: DXY, trade balance, flows (grafik + tabel ringkas)
* DXY: jalur eksogen yang diasumsikan. TB dan flows: median jalur model; pada Adverse/Upside/Severe
* Adverse nilainya dikunci di h = 3 dan 6 (titik berlabel), bulan lain mengikuti model.
use "$data\scenario_global_paths.dta", clear
rename (dxy_baseline dxy_adverse dxy_upside dxy_severe) (dxy1 dxy2 dxy3 dxy4)
reshape long dxy, i(mdate) j(scenario)
keep if mdate >= $final_origin
tempfile gl
save `gl'
use "$data\scenario_paths_all.dta", clear
keep scenario mdate usdidr_median trade_bal_usdbn_median net_flows_idrtn_median
rename (usdidr_median trade_bal_usdbn_median net_flows_idrtn_median) (usdidr tb flows)
merge 1:1 scenario mdate using `gl', nogen
bv_scenlab
sort scenario mdate
gen byte lab_pt = inlist(mdate, $final_origin + 3, $final_origin + 6)
foreach v in dxy tb flows {
	gen str8 l_`v' = string(`v', "%5.1f") if lab_pt
}
save "$data\scenario_macro_paths.dta", replace

local cols `""24 90 141" "164 87 23" "35 114 74" "170 30 30""'
local pats "solid dash shortdash longdash"
local k 0
foreach v in dxy tb flows {
	local ++k
	local t : word `k' of "DXY (indeks)" "Trade balance (USD bn)" "Net flows (Rp tn)"
	local plots ""
	forval s = 1/4 {
		local c : word `s' of `cols'
		local pt : word `s' of `pats'
		local plots `plots' (line `v' mdate if scenario == `s', lcolor("`c'") lpattern(`pt') lwidth(medthick))
		local plots `plots' (scatter `v' mdate if scenario == `s' & lab_pt, mcolor("`c'") msize(small) mlabel(l_`v') mlabcolor("`c'") mlabsize(vsmall) mlabposition(1))
	}
	twoway `plots', title("`t'", size(medium)) xtitle("") ytitle("") ylabel(, format(%6.1f) angle(0)) ///
		xlabel(#6, format(%tmMon_CCYY) labsize(vsmall) angle(30)) ///
		legend(off) ///
		graphregion(color(white)) name(mac`k', replace) nodraw
}
graph combine mac1 mac2 mac3, cols(3) graphregion(color(white)) xsize(13) ysize(4.8) ///
	title("Asumsi makro per skenario", size(medium)) ///
	note("Garis: Baseline = biru utuh; Adverse = oranye putus-putus; Upside = hijau titik-titik; Severe Adverse = merah putus panjang." ///
		"Angka berlabel = nilai pada h = 3 dan 6 bulan (dikunci pada skenario non-baseline). TB dan flows Baseline = median model.", size(vsmall)) ///
	name(scen_macro, replace)
graph save "$gph\6_scenario_macro.gph", replace
graph export "$fig\6_scenario_macro.png", replace width(2600)

**## 6.7 Tabel ringkas skenario (asumsi + hasil USD/IDR), juga sebagai PNG
use "$data\scenario_macro_paths.dta", clear
keep if inlist(mdate, $final_origin + 3, $final_origin + 6)
gen byte hh = mdate - $final_origin
keep scenario hh dxy tb flows usdidr
reshape wide dxy tb flows usdidr, i(scenario) j(hh)
preserve
	use "$data\scenario_global_paths.dta", clear
	qui sum dxy_baseline if mdate == $final_origin
	global dxy0 = r(mean)
restore
gen double dxy_pct6 = 100*(dxy6/$dxy0 - 1)
* batas 80% USD/IDR pada h = 6
preserve
	use "$data\scenario_spot.dta", clear
	keep if mdate == $final_origin + 6
	keep scenario lower80 upper80
	tempfile b80
	save `b80'
restore
merge 1:1 scenario using `b80', nogen
gen double pct_vs_anchor6 = 100*(usdidr6/$anchor_spot - 1)
bv_scenlab
sort scenario
order scenario dxy_pct6 tb3 tb6 flows3 flows6 usdidr3 usdidr6 lower80 upper80 pct_vs_anchor6
keep scenario dxy_pct6 tb3 tb6 flows3 flows6 usdidr3 usdidr6 lower80 upper80 pct_vs_anchor6
label var dxy_pct6 "DXY Mar-27 vs Sep-26 (%)"
label var tb3 "TB Des-26 (USD bn)"
label var tb6 "TB Mar-27 (USD bn)"
label var flows3 "Flows Des-26 (Rp tn)"
label var flows6 "Flows Mar-27 (Rp tn)"
label var usdidr3 "USD/IDR Des-26 (median)"
label var usdidr6 "USD/IDR Mar-27 (median)"
label var lower80 "USD/IDR Mar-27 batas bawah 80%"
label var upper80 "USD/IDR Mar-27 batas atas 80%"
label var pct_vs_anchor6 "Mar-27 vs Sep-26 (%)"
format dxy_pct6 tb* flows* pct_vs_anchor6 %6.1f
format usdidr* lower80 upper80 %9.0f
list, noobs clean
save "$data\scenario_summary.dta", replace
bv_out tab "T14_scenario_summary"

* Render tabel sebagai PNG (teks pada kanvas grafik)
local cx "3 22 33 44 55 66 79 94"
local heads `""Skenario" "DXY Mar-27" "TB Des-26" "TB Mar-27" "Flows Des-26" "Flows Mar-27" "USD/IDR Des-26" "USD/IDR Mar-27 (80%)""'
local units `""" "vs Sep-26" "USD bn" "USD bn" "Rp tn" "Rp tn" "median" "median [rentang]""'
local txt ""
forval j = 1/8 {
	local x : word `j' of `cx'
	local h : word `j' of `heads'
	local u : word `j' of `units'
	local txt `txt' text(92 `x' "`h'", place(e) size(small) color(black)) text(86 `x' "`u'", place(e) size(vsmall) color(gs7))
}
forval i = 1/`=_N' {
	local y = 84 - 16*`i'
	local sc : label scen `=scenario[`i']'
	local v2 = cond(dxy_pct6[`i'] >= 0, "+", "") + strtrim(string(dxy_pct6[`i'], "%5.1f")) + "%"
	local v3 = strtrim(string(tb3[`i'], "%5.1f"))
	local v4 = strtrim(string(tb6[`i'], "%5.1f"))
	local v5 = strtrim(string(flows3[`i'], "%6.1f"))
	local v6 = strtrim(string(flows6[`i'], "%6.1f"))
	local v7 = strtrim(string(usdidr3[`i'], "%9.0fc"))
	local v8 = strtrim(string(usdidr6[`i'], "%9.0fc")) + " [" + strtrim(string(lower80[`i'], "%9.0fc")) + "-" + strtrim(string(upper80[`i'], "%9.0fc")) + "]"
	local txt `txt' text(`y' 3 "`sc'", place(e) size(small))
	forval j = 2/8 {
		local x : word `j' of `cx'
		local txt `txt' text(`y' `x' "`v`j''", place(e) size(small))
	}
}
twoway scatteri 0 0 100 100, msymbol(none) xscale(off range(0 120)) yscale(off range(0 100)) ///
	xlabel(none) ylabel(none) `txt' ///
	yline(80, lcolor(gs10)) title("Ringkasan skenario USD/IDR (model $model_mode, anchor Sep-26 = `=strtrim(string($anchor_spot, "%9.0fc"))')", size(medium)) ///
	note("TB dan flows pada Adverse/Upside/Severe Adverse = median Baseline +/- shock (00_master.do). Rentang = interval prediktif 80%.", size(vsmall)) ///
	graphregion(color(white)) plotregion(style(none)) xsize(13) ysize(4) legend(off) name(scen_table, replace)
graph save "$gph\6_scenario_table.gph", replace
graph export "$fig\6_scenario_table.png", replace width(2600)

**## 6.8 Tabel PNG: forecast bulanan USD/IDR per skenario (median [rentang 80%])
use "$data\scenario_spot.dta", clear
keep scenario mdate median lower80 upper80
gen str32 cell = strtrim(string(median, "%9.0fc")) + "  [" + strtrim(string(lower80, "%9.0fc")) + " - " + strtrim(string(upper80, "%9.0fc")) + "]"
keep scenario mdate cell
reshape wide cell, i(mdate) j(scenario)
gen str12 bulan = string(mdate, "%tmMon_CCYY")
sort mdate
bv_pngtable bulan cell1 cell2 cell3 cell4, file("$fig\6_forecast_table.png") ///
	title("Forecast USD/IDR per skenario: median [rentang 80%] (model $model_mode, anchor Sep 2026 = `=strtrim(string($anchor_spot, "%9.0fc"))')") ///
	heads("Bulan" "Baseline" "Adverse" "Upside" "Severe Adverse") widths(14 26 26 26 26) ///
	note("Asumsi skenario: lihat 6_scenario_macro.png dan 6_scenario_table.png. Rentang = interval prediktif 80% (posterior predictive).")
