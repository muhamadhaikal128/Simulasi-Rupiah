**# 6. FIT AKHIR, DIAGNOSTIK, BASELINE DAN SKENARIO BERSYARAT
* Rmd: chunk fit-akhir-diagnostik, baseline-snapshot, conditional-scenarios, plot-skenario.
* Fit sampai bulan lengkap terakhir (latest_complete); anchor pasar = final_origin.
* Bulan di antara cutoff dan anchor dijembatani dengan observasi yang sudah ada di snapshot
* (USD/IDR, flows, cadangan; TB September kosong dibiarkan tak teramati). Aturan bridge makro
* ini hanya untuk forecast akhir, TIDAK dipakai dalam backtest.
* Skenario ilustratif (bukan shock struktural): pada h = 3 dan 6, TB -/+ USD1 bn dan flows -/+ Rp10 tn
* terhadap median baseline; DXY menuju +/-2% pada akhir horizon.
* Menulis: intermediate/final_residuals.dta, scenario_*.dta
* Output:  tables/T7_baseline, T8_scenarios, T9_scenario_paths_all, T10_scenario_inputs,
*          T11_global_paths; diagnostics/D3_residual_tests, D4_residual_corr, D5_scenario_ess_roots;
*          figures/6_residual_acf.png, 6_scenarios_fan.png, 6_scenarios_vars.png

**## 6.1 Fungsi Mata untuk run akhir
mata:
// Ringkasan jalur semua variabel (median, satuan alami) per step: (scen, mdate, s, tb, flows, res)
real matrix bv_paths_median(struct bvpred scalar pr, real rowvector steps, real scalar sc)
{
	real matrix M
	real scalar i, j, K
	K = 4
	M = J(cols(steps), 6, .)
	for (i = 1; i <= cols(steps); i++) {
		M[i, 1] = sc
		M[i, 2] = pr.times[steps[i]]
		M[i, 3] = bv_quantile(pr.spot[., steps[i]], 0.5)
		for (j = 2; j <= K; j++) M[i, j+2] = bv_median_path(pr, steps[i], j, K)
	}
	// flows kembali ke Rp tn, cadangan kembali ke USD bn
	M[., 5] = M[., 5]*10
	M[., 6] = exp(M[., 6]/100)
	return(M)
}

void bv_final_run(real scalar cutoff, real scalar origin, real scalar H, real scalar sy0, real scalar p, real scalar lambda, real scalar inc_ust, real scalar nd, real scalar gdxy, real scalar dtb, real scalar dfl, real rowvector chz)
{
	external struct bvdata scalar D
	external real matrix FIN_resid, FIN_tab, FIN_diag, FIN_cond, FIN_glob, FIN_vars, FIN_info
	struct bvfit scalar f
	struct bvfut scalar ub, up, us
	struct bvpred scalar pb, pp, ps
	real matrix xc, xp, xs, bridge
	real rowvector fsteps
	real colvector known
	real scalar i, j, r, s, v

	f = bv_fit(D, cutoff, sy0, p, lambda, inc_ust)
	FIN_resid = D.mdate[f.idx], f.resid
	FIN_info = (f.n, D.mdate[f.idx[1]], f.cutoff, origin)

	ub = bv_future(f, D, origin, H, 0, 0)
	// Bridge makro yang sudah tersedia di snapshot (variabel 2..4)
	known = selectindex(ub.times :<= origin)
	for (i = 1; i <= rows(known); i++) {
		r = bv_row(D, ub.times[known[i]])
		for (j = 2; j <= 4; j++) {
			if (!missing(D.Y[r, j])) ub.cond = ub.cond \ (known[i], j, D.Y[r, j])
		}
	}
	bridge = ub.cond
	pb = bv_predict(f, ub, nd, J(0, 3, .), 40001)
	fsteps = selectindex(ub.times :> origin)'

	// Kondisi skenario terhadap median baseline
	xp = J(0, 3, .)
	xs = J(0, 3, .)
	for (i = 1; i <= cols(chz); i++) {
		s = origin + chz[i] - f.cutoff
		v = bv_median_path(pb, s, 2, 4)
		xp = xp \ (s, 2, v - dtb)
		xs = xs \ (s, 2, v + dtb)
		v = bv_median_path(pb, s, 3, 4)
		xp = xp \ (s, 3, v - dfl/10)
		xs = xs \ (s, 3, v + dfl/10)
	}
	up = bv_future(f, D, origin, H, gdxy, 0)
	us = bv_future(f, D, origin, H, -gdxy, 0)
	up.cond = bridge
	us.cond = bridge
	pp = bv_predict(f, up, nd, xp, 40001)
	ps = bv_predict(f, us, nd, xs, 40001)

	// Tabel spot per skenario: (scen, mdate, lower95, lower80, median, upper80, upper95, ess, ess_ratio)
	FIN_tab = (J(cols(fsteps), 1, 1), bv_summary(pb, fsteps))
	FIN_tab = FIN_tab \ (J(cols(fsteps), 1, 2), bv_summary(pp, fsteps))
	FIN_tab = FIN_tab \ (J(cols(fsteps), 1, 3), bv_summary(ps, fsteps))
	FIN_vars = bv_paths_median(pb, fsteps, 1) \ bv_paths_median(pp, fsteps, 2) \ bv_paths_median(ps, fsteps, 3)
	FIN_diag = (1, pb.ess, pb.ess/nd, pb.root_gt1, pb.root_gt105)
	FIN_diag = FIN_diag \ (2, pp.ess, pp.ess/nd, pp.root_gt1, pp.root_gt105)
	FIN_diag = FIN_diag \ (3, ps.ess, ps.ess/nd, ps.root_gt1, ps.root_gt105)
	// Kondisi: (scen, step, mdate, variabel, nilai model); scen 0 = bridge (dipakai semua skenario)
	xc = (J(rows(bridge), 1, 0), bridge) \ (J(rows(xp), 1, 2), xp) \ (J(rows(xs), 1, 3), xs)
	FIN_cond = xc[., (1..2)], ub.times[xc[., 2]], xc[., (3..4)]
	FIN_glob = ub.times, ub.dxy, up.dxy, us.dxy
}
end

**## 6.2 Jalankan fit akhir dan skenario
use "$data\database.dta", clear
mata: D = bv_load("levels")
mata: bv_final_run($latest_complete, $final_origin, $H_final, $best_start, $best_p, $best_lambda, ///
	$include_ust, $n_final, $dxy_shock, $tb_shock, $flows_shock, strtoreal(tokens(st_global("cond_horizons"))))
mata: st_global("fin_n", strofreal(FIN_info[1])); st_global("fin_from", strofreal(FIN_info[2]))
di "Training akhir: " %tm $fin_from " sampai " %tm $latest_complete "; N = $fin_n"

* label skenario
cap program drop bv_scenlab
program define bv_scenlab
	label define scen 0 "bridge" 1 "baseline" 2 "tekanan_input" 3 "dukungan_input", replace
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
gen double value_natural = cond(variable == 1 | variable == 4, exp(value_model/100), cond(variable == 3, value_model*10, value_model))
save "$data\scenario_conditions.dta", replace
list, noobs sepby(scenario)
bv_out tab "T10_scenario_inputs"

mata: bv_tostata(FIN_glob, ("mdate", "dxy_baseline", "dxy_tekanan", "dxy_dukungan"))
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
foreach s in 1 2 3 {
	replace median`s' = usdidr if mdate == $final_origin
}
local anch : di %tmMon_CCYY $final_origin
twoway (rarea lower951 upper951 mdate, color("24 90 141%10") lwidth(none)) ///
	(rarea lower801 upper801 mdate, color("24 90 141%22") lwidth(none)) ///
	(line usdidr mdate, lcolor(black) lwidth(medthick)) ///
	(line median1 mdate, lcolor("24 90 141") lwidth(medthick)) ///
	(line median2 mdate, lcolor("164 87 23") lwidth(medthick) lpattern(dash)) ///
	(line median3 mdate, lcolor("35 114 74") lwidth(medthick) lpattern(shortdash)), ///
	xline($final_origin, lcolor(gs10) lpattern(dot)) ///
	title("USD/IDR: proyeksi bersyarat pada jalur skenario", size(medium)) ///
	subtitle("Band baseline 80% dan 95%; anchor `anch'", size(small)) ///
	xtitle("") ytitle("IDR per USD") xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) ///
	legend(order(3 "Aktual" 4 "Baseline median" 5 "Input tekanan" 6 "Input dukungan" 2 "Band 80%" 1 "Band 95%") rows(2) size(small) position(6)) ///
	graphregion(color(white)) name(scen_fan, replace)
graph save "$gph\6_scenarios_fan.gph", replace
graph export "$fig\6_scenarios_fan.png", replace width(1800)

* Median TB, flows, cadangan per skenario
use "$data\scenario_paths_all.dta", clear
reshape wide usdidr_median trade_bal_usdbn_median net_flows_idrtn_median fx_reserves_usdbn_median, i(mdate) j(scenario)
local k 0
foreach v in trade_bal_usdbn net_flows_idrtn fx_reserves_usdbn {
	local ++k
	local t : word `k' of "Trade balance (USD bn)" "Flows (Rp tn)" "Cadangan valas (USD bn)"
	twoway (line `v'_median1 mdate, lcolor("24 90 141") lwidth(medthick)) ///
		(line `v'_median2 mdate, lcolor("164 87 23") lpattern(dash)) ///
		(line `v'_median3 mdate, lcolor("35 114 74") lpattern(shortdash)), ///
		title("`t'", size(medium)) xtitle("") ytitle("") xlabel(#4, format(%tmMon_CCYY) labsize(vsmall) angle(30)) ///
		legend(order(1 "Baseline" 2 "Tekanan" 3 "Dukungan") rows(1) size(small) position(6)) ///
		graphregion(color(white)) name(sv`k', replace) nodraw
}
graph combine sv1 sv2 sv3, cols(3) graphregion(color(white)) xsize(12) ysize(4) name(scen_vars, replace)
graph save "$gph\6_scenarios_vars.gph", replace
graph export "$fig\6_scenarios_vars.png", replace width(2400)
