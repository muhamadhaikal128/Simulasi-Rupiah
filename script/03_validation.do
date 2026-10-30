**# 3. VALIDATION: PILIH START YEAR, LAG, LAMBDA
* Rmd: chunk fungsi-backtest (bagian grid). Origin Jan 2021 - Jun 2023, target terakhir Des 2023.
* Skor = rata-rata relative RMSE (BVARX/RW) pada h = 1, 3, 6. Lebih kecil lebih baik.
* Aturan tie (ditetapkan sebelum melihat test): skor dalam 1% dari minimum -> pilih 2014,
* lalu 2013, lalu 2017; kemudian lag lebih pendek; kemudian lambda lebih kecil (shrinkage kuat).
* Menulis: intermediate/validation_grid.dta, validation_backtests.dta
* Output:  tables/T2_validation_grid; globals best_start best_p best_lambda

local hmax : word count $horizons
local hmax : word `hmax' of $horizons
assert $val_to + `hmax' <= ym(2023,12)
mata: hz = strtoreal(tokens(st_global("horizons")))

use "$data\database.dta", clear
mata: D = bv_load("levels")

tempname pv
postfile `pv' start_year p double lambda score rrmse_h1 rrmse_h3 rrmse_h6 min_ess_ratio ///
	using "$data\validation_grid.dta", replace
tempfile allbt
local first 1
foreach sy of global grid_start {
	foreach p of global grid_p {
		foreach lam of global grid_lambda {
			di as txt "Validation: start=`sy' p=`p' lambda=`lam'"
			mata: R = bv_backtest(D, `sy', `p', `lam', $include_ust, ($val_from::$val_to), ///
				$n_val, 10000, $release_lag, hz)
			mata: bv_tostata(R, bv_bt_names())
			gen start_year = `sy'
			gen p = `p'
			gen double lambda = `lam'
			if !`first' append using `allbt'
			save `allbt', replace
			local first 0
			keep if start_year == `sy' & p == `p' & lambda == `lam'
			bv_score
			qui sum relative_rmse
			local sc = r(mean)
			forval i = 1/3 {
				local r`i' = relative_rmse[`i']
			}
			qui sum min_ess_ratio
			post `pv' (`sy') (`p') (`lam') (`sc') (`r1') (`r2') (`r3') (r(min))
		}
	}
}
postclose `pv'
use `allbt', clear
format origin target %tm
save "$data\validation_backtests.dta", replace

**## 3.1 Kunci spesifikasi
use "$data\validation_grid.dta", clear
qui sum score
gen byte eligible = score <= r(min)*1.01
gen byte pref = cond(start_year == 2014, 0, cond(start_year == 2013, 1, 2))
gsort -eligible pref p lambda
gen byte chosen = _n == 1
global best_start = start_year[1]
global best_p = p[1]
global best_lambda = lambda[1]
drop pref
sort score
format score rrmse_h* min_ess_ratio %9.4f
list, noobs clean
save "$data\validation_grid.dta", replace
bv_out tab "T2_validation_grid"

di as res "Spesifikasi terkunci: start=$best_start  p=$best_p  lambda=$best_lambda"
if $best_start != 2014 di as txt "Catatan: 2014 tidak terpilih; laporkan apa adanya (jangan pindahkan test)."
