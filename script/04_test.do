**# 4. TEST TERKUNCI: BVARX VS RANDOM WALK
* Rmd: chunk test-terkunci, bootstrap-error, plot-error-test.
* Origin Jan 2024 s/d (bulan lengkap terakhir - 6). Spesifikasi dari 03, tidak dipilih ulang.
* Menulis: intermediate/test_levels.dta, test_scores_levels.dta, test_bootstrap.dta
* Output:  tables/T3_test_forecasts, T4_test_scores, T5_test_bootstrap;
*          figures/4_test_h1.png, 4_test_h3.png, 4_test_h6.png, 4_test_rmse.png

local hmax : word count $horizons
local hmax : word `hmax' of $horizons
global test_to = $latest_complete - `hmax'
assert $test_from > $val_to + `hmax'
mata: hz = strtoreal(tokens(st_global("horizons")))

use "$data\database.dta", clear
mata: D = bv_load("levels")
mata: R = bv_backtest(D, $best_start, $best_p, $best_lambda, $include_ust, ///
	($test_from::$test_to), $n_test, 20000, $release_lag, hz, $best_soc)
mata: bv_tostata(R, bv_bt_names())
format origin target %tm
save "$data\test_levels.dta", replace
bv_out tab "T3_test_forecasts"
qui levelsof origin
di "Origin test: " %tm $test_from " sampai " %tm $test_to "; jumlah origin per horizon: `r(r)'"

**## 4.1 Skor per horizon
bv_score
format rmse* mae* log_rmse* width80 %9.1f
format relative_rmse direction_accuracy coverage* min_ess_ratio %6.3f
list, noobs
save "$data\test_scores_levels.dta", replace
bv_out tab "T4_test_scores"

**## 4.2 Circular block bootstrap relative RMSE (blok 3/6/12, R = 1000)
* Interval meliputi 1 -> belum ada bukti kuat mengungguli random walk.
tempname pb
postfile `pb' horizon block lower upper using "$data\test_bootstrap.dta", replace
foreach h of global horizons {
	use "$data\test_levels.dta", clear
	keep if horizon == `h'
	sort origin
	foreach b in 3 6 12 {
		mata: ci = bv_boot_rrmse(st_data(., "actual"), st_data(., "point"), st_data(., "rw"), 1000, `b', 77)
		mata: st_local("lo", strofreal(ci[1], "%20.0g")); st_local("hi", strofreal(ci[2], "%20.0g"))
		post `pb' (`h') (`b') (`lo') (`hi')
	}
}
postclose `pb'
use "$data\test_bootstrap.dta", clear
merge m:1 horizon using "$data\test_scores_levels.dta", keepusing(relative_rmse) nogen
gen byte covers_one = lower <= 1 & upper >= 1
order horizon block relative_rmse lower upper covers_one
format relative_rmse lower upper %6.3f
list, noobs clean
save "$data\test_bootstrap.dta", replace
bv_out tab "T5_test_bootstrap"

**## 4.3 Grafik aktual vs BVARX vs RW per horizon
foreach h of global horizons {
	use "$data\test_levels.dta", clear
	keep if horizon == `h'
	twoway (rarea lower80 upper80 target, color("24 90 141%15") lwidth(none)) ///
		(line actual target, lcolor(black) lwidth(medthick)) ///
		(line point target, lcolor("24 90 141") lwidth(medthick)) ///
		(line rw target, lcolor("164 87 23") lpattern(dash)), ///
		title("Test: horizon `h' bulan", size(medium)) xtitle("Bulan target") ytitle("IDR per USD") ///
		legend(order(2 "Aktual" 3 "BVARX median" 4 "RW" 1 "Band 80% BVARX") rows(1) size(small) position(6)) ///
		xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) graphregion(color(white)) name(test_h`h', replace)
	graph save "$gph\4_test_h`h'.gph", replace
	graph export "$fig\4_test_h`h'.png", replace width(1800)
}

use "$data\test_scores_levels.dta", clear
graph bar rmse_bvar rmse_rw, over(horizon, relabel(1 "h=1" 2 "h=3" 3 "h=6")) ///
	bar(1, color("24 90 141")) bar(2, color("164 87 23")) ///
	legend(order(1 "BVARX" 2 "Random walk") rows(1) position(6)) ytitle("RMSE (IDR per USD)") ///
	title("Test: RMSE BVARX vs random walk", size(medium)) blabel(bar, format(%9.0f) size(vsmall)) ///
	graphregion(color(white)) name(test_rmse, replace)
graph save "$gph\4_test_rmse.gph", replace
graph export "$fig\4_test_rmse.png", replace width(1800)
