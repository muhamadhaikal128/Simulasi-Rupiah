**# 5. SENSITIVITY: SPESIFIKASI CHANGES
* Rmd: chunk sensitivity-changes. Perubahan log USD/IDR, cadangan, DXY; TB dan flows tetap.
* Hyperparameter sama dengan spesifikasi terkunci; bukan pemilihan model baru dari test.
* Menulis: intermediate/test_changes.dta, sensitivity.dta
* Output:  tables/T6_sensitivity_levels_changes

mata: hz = strtoreal(tokens(st_global("horizons")))
use "$data\database.dta", clear
mata: Dc = bv_load("changes")
mata: R = bv_backtest(Dc, $best_start, $best_p, $best_lambda, $include_ust, ///
	($test_from::$test_to), $n_test, 30000, $release_lag, hz)
mata: bv_tostata(R, bv_bt_names())
format origin target %tm
save "$data\test_changes.dta", replace
bv_score
keep horizon relative_rmse rmse_bvar coverage80 coverage95
rename (relative_rmse rmse_bvar coverage80 coverage95) (=_changes)
tempfile ch
save `ch'

use "$data\test_scores_levels.dta", clear
keep horizon relative_rmse rmse_bvar rmse_rw coverage80 coverage95
rename (relative_rmse rmse_bvar coverage80 coverage95) (=_levels)
merge 1:1 horizon using `ch', nogen
order horizon rmse_rw rmse_bvar_levels rmse_bvar_changes relative_rmse_levels relative_rmse_changes
format rmse* %9.1f
format relative_rmse* coverage* %6.3f
list, noobs clean
save "$data\sensitivity.dta", replace
bv_out tab "T6_sensitivity_levels_changes"
