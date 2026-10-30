**# 3. VALIDATION: PILIH START YEAR, LAG, LAMBDA, EKSOGEN (BVARX changes)
* Rmd: chunk fungsi-backtest (bagian grid). Origin Jan 2021 - Jun 2023, target terakhir Des 2023.
* Skor = rata-rata relative RMSE (BVARX/RW) pada h = 1, 3, 6. Lebih kecil lebih baik.
* Grid: start year x lag x lambda x UST10Y x selisih BI-Fed x VIX x dummy outlier x prior UIP (sesuai global grid_*).
* Aturan tie (ditetapkan sebelum melihat test): skor dalam 1% dari minimum -> pilih 2014,
* lalu 2013, lalu 2017; kemudian lag lebih pendek; kemudian lambda lebih kecil (shrinkage kuat);
* kemudian tanpa UST, tanpa selisih suku bunga, tanpa VIX, tanpa dummy, tanpa prior UIP (model lebih sederhana).
* Menulis: intermediate/validation_grid.dta, validation_backtests.dta
* Output:  tables/T2_validation_grid; globals best_start best_p best_lambda best_ust best_rate best_vix best_dum best_uip

local hmax : word count $horizons
local hmax : word `hmax' of $horizons
assert $val_to + `hmax' <= ym(2023,12)
mata: hz = strtoreal(tokens(st_global("horizons")))

use "$data\database.dta", clear
mata: D = bv_load("$model_mode")

tempname pv
postfile `pv' start_year p double lambda ust rate vix dum uip score rrmse_h1 rrmse_h3 rrmse_h6 min_ess_ratio ///
	using "$data\validation_grid.dta", replace
tempfile allbt
local first 1
foreach sy of global grid_start {
	foreach p of global grid_p {
		foreach lam of global grid_lambda {
			foreach u of global grid_ust {
				foreach rt of global grid_rate {
				foreach vx of global grid_vix {
				foreach dm of global grid_dum {
				foreach ui of global grid_uip {
					di as txt "Validation: start=`sy' p=`p' lambda=`lam' ust=`u' rate=`rt' vix=`vx' dum=`dm' uip=`ui'"
					global use_rate `rt'
					global use_vix `vx'
					global use_dum `dm'
					global use_uip `ui'
					mata: R = bv_backtest(D, `sy', `p', `lam', `u', ($val_from::$val_to), ///
						$n_val, 10000, $release_lag, hz, 0)
					mata: bv_tostata(R, bv_bt_names())
					gen start_year = `sy'
					gen p = `p'
					gen double lambda = `lam'
					gen ust = `u'
					gen rate = `rt'
					gen vix = `vx'
					gen dum = `dm'
					gen uip = `ui'
					if !`first' append using `allbt'
					save `allbt', replace
					local first 0
					keep if start_year == `sy' & p == `p' & lambda == `lam' & ust == `u' & rate == `rt' & vix == `vx' & dum == `dm' & uip == `ui'
					bv_score
					qui sum relative_rmse
					local sc = r(mean)
					forval i = 1/3 {
						local r`i' = relative_rmse[`i']
					}
					qui sum min_ess_ratio
					post `pv' (`sy') (`p') (`lam') (`u') (`rt') (`vx') (`dm') (`ui') (`sc') (`r1') (`r2') (`r3') (r(min))
				}
			}
		}
	}
}
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
gsort -eligible pref p lambda ust rate vix dum uip
gen byte chosen = _n == 1
global best_start = start_year[1]
global best_p = p[1]
global best_lambda = lambda[1]
global best_ust = ust[1]
global best_rate = rate[1]
global use_rate $best_rate
global best_vix = vix[1]
global use_vix $best_vix
global best_dum = dum[1]
global use_dum $best_dum
global best_uip = uip[1]
global use_uip $best_uip
drop pref
sort score
format score rrmse_h* min_ess_ratio %9.4f
list in 1/10, noobs clean
save "$data\validation_grid.dta", replace
bv_out tab "T2_validation_grid"

di as res "Spesifikasi terkunci: start=$best_start  p=$best_p  lambda=$best_lambda  ust=$best_ust  rate=$best_rate  vix=$best_vix  dum=$best_dum  uip=$best_uip  (model $model_mode)"
if $best_start != 2014 di as txt "Catatan: 2014 tidak terpilih; laporkan apa adanya (jangan pindahkan test)."
