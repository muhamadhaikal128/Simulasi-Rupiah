**# 9. BAYESIAN MODEL AVERAGING (bmaregress) VS RANDOM WALK TANPA DRIFT
* Regresi prediktif langsung per horizon h: y_h(t) = 100*[log S(t+h) - log S(t)] pada prediktor
* yang diketahui di akhir bulan t. 6 kandidat (2^6 = 64 model, enumerasi penuh):
*   ds    perubahan 100 log USD/IDR bulan t          (pasar, bulan t)
*   ddxy  perubahan 100 log DXY bulan t              (pasar, bulan t)
*   dust  perubahan UST10Y bulan t (pp)               (pasar, bulan t)
*   flow2 net flows bulan t-2 (Rp10 tn)               (jeda rilis 2 bulan)
*   tb2   trade balance bulan t-2 (USD bn)            (jeda rilis 2 bulan)
*   dres2 perubahan 100 log cadangan bulan t-2        (jeda rilis 2 bulan)
* Prior: g-prior Zellner dengan g tetap (dipilih di validation dari $bma_g_grid; "n" = g = n, UIP),
*        prior model binomial dengan peluang inklusi $bma_inc per prediktor (0.5 = seragam atas model).
* Forecast BMA = rata-rata posterior predictive dibobot probabilitas posterior model (bmapredict, mean).
* Anti look-ahead: training hanya bulan t dengan t + h <= origin; estimasi ulang di setiap origin;
*        g dipilih hanya di validation; test hanya untuk menilai.
* Uji: Diebold-Mariano (koreksi HLN) dan Clark-West (model bersarang terhadap RW), varians Newey-West lag h-1.
* Menulis: intermediate/bma_backtests.dta, bma_*.dta
* Output:  tables/B1_bma_validation_g, B2_bma_test_scores, B3_bma_vs_bvarx, B5_bma_final_forecast,
*          B6_bma_top_models_h*; diagnostics/B4_bma_pip_final;
*          figures/9_bma_pip_by_origin.png, 9_bma_test_h3.png, 9_bma_cum_sse.png

**## 9.1 Data dan prediktor
use "$data\database.dta", clear
tsset mdate, monthly
gen double ds    = dy_s
gen double ddxy  = dx_dxy
gen double dust  = D.ust10y_pct
gen double flow2 = L2.net_flows_idrtn/10
gen double tb2   = L2.trade_bal_usdbn
gen double dres2 = L2.dy_res
* target untuk semua horizon 1..H_final (forecast akhir bulanan); evaluasi tetap pada $horizons
forval h = 1/$H_final {
	gen double y`h' = F`h'.y_s - y_s
}
local first = mdate[1]
save "$data\bma_data.dta", replace

**## 9.2 Program: satu estimasi BMA untuk horizon h, origin r, nilai g
cap program drop bv_bma_one
program define bv_bma_one, rclass
	args h r g
	local gopt = cond("`g'" == "n", "gprior(uip)", "gprior(fixed `g')")
	qui bmaregress y`h' $bma_preds if mdate + `h' <= `r' & mdate >= ym($bma_start, 1), ///
		mprior(binomial $bma_inc) `gopt' notable noheader
	return scalar n = e(N)
	tempname P
	matrix `P' = e(pip)
	foreach v of global bma_preds {
		local j = colnumb(`P', "`v'")
		if !missing(`j') return scalar pip_`v' = `P'[1, `j']
		else {
			local j = rownumb(`P', "`v'")
			return scalar pip_`v' = `P'[`j', 1]
		}
	}
	cap drop _bma_m _bma_s
	qui bmapredict _bma_m if mdate == `r', mean
	qui bmapredict _bma_s if mdate == `r', std
	qui sum _bma_m if mdate == `r'
	return scalar yhat = r(mean)
	qui sum _bma_s if mdate == `r'
	return scalar ysd = r(mean)
	drop _bma_m _bma_s
end

* Statistik t Newey-West (Bartlett, lag L) untuk rata-rata x
mata:
real scalar bma_nwt(real colvector x, real scalar L)
{
	real colvector e
	real scalar n, m, v, l
	n = rows(x)
	m = mean(x)
	e = x :- m
	v = sum(e:^2)/n
	for (l = 1; l <= min((L, n - 1)); l++) {
		v = v + 2*(1 - l/(L + 1))*sum(e[|l+1 \ n|] :* e[|1 \ n-l|])/n
	}
	return(m/sqrt(v/n))
}

// Matriks Stata -> dataset: kolom "row" = nama baris, kolom lain = nama kolom (dibuat valid)
void bma_mat2data(string scalar name)
{
	real matrix M
	string colvector rs, cs
	string scalar v
	real scalar j
	M  = st_matrix(name)
	rs = st_matrixrowstripe(name)[., 2]
	cs = st_matrixcolstripe(name)[., 2]
	stata("clear")
	st_addobs(rows(M))
	(void) st_addvar("str32", "row")
	st_sstore(., "row", rs)
	for (j = 1; j <= cols(M); j++) {
		v = strtoname(cs[j])
		if (v == "" | v == "row" | _st_varindex(v) < .) v = "c" + strofreal(j)
		(void) st_addvar("double", v)
		st_store(., v, M[., j])
	}
}
end

**## 9.3 Program: backtest untuk daftar origin dan satu g (hasil di-append ke file)
cap program drop bv_bma_bt
program define bv_bma_bt
	args g period o1 o2 file
	local pipv ""
	local pipe ""
	foreach v of global bma_preds {
		local pipv `pipv' pip_`v'
		local pipe `pipe' (r(pip_`v'))
	}
	use "$data\bma_data.dta", clear
	local first = mdate[1]
	tempname pb
	postfile `pb' str6 g str12 period origin h n actual rw yhat ysd yact `pipv' using "`file'", replace
	forval r = `o1'/`o2' {
		local ir = `r' - `first' + 1
		foreach h of global horizons {
			local act = usdidr[`ir' + `h']
			local s0 = usdidr[`ir']
			bv_bma_one `h' `r' `g'
			post `pb' ("`g'") ("`period'") (`r') (`h') (r(n)) (`act') (`s0') (r(yhat)) (r(ysd)) ///
				(100*ln(`act'/`s0')) `pipe'
		}
	}
	postclose `pb'
end

**## 9.4 Program: skor per horizon (RMSE, relatif RW, arah, DM-HLN, Clark-West)
cap program drop bv_bma_score
program define bv_bma_score
	gen double point = rw*exp(yhat/100)
	gen double e_m = (actual - point)^2
	gen double e_r = (actual - rw)^2
	gen double dl = e_m - e_r
	gen double cwf = yact^2 - ((yact - yhat)^2 - yhat^2)
	gen double dirok = sign(yhat) == sign(yact)
	tempfile base res
	save `base'
	tempname ps
	postfile `ps' horizon n rmse_bma rmse_rw relative_rmse direction dm_hln dm_p cw_t cw_p using `res'
	foreach h of global horizons {
		use `base', clear
		keep if h == `h'
		sort origin
		qui sum e_m
		local mm = r(mean)
		local n = r(N)
		qui sum e_r
		local mr = r(mean)
		qui sum dirok
		local dir = r(mean)
		mata: st_local("dm", strofreal(bma_nwt(st_data(., "dl"), `h' - 1), "%20.0g"))
		mata: st_local("cw", strofreal(bma_nwt(st_data(., "cwf"), `h' - 1), "%20.0g"))
		local hln = `dm'*sqrt((`n' + 1 - 2*`h' + `h'*(`h' - 1)/`n')/`n')
		post `ps' (`h') (`n') (sqrt(`mm')) (sqrt(`mr')) (sqrt(`mm'/`mr')) (`dir') ///
			(`hln') (2*ttail(`n' - 1, abs(`hln'))) (`cw') (1 - normal(`cw'))
	}
	postclose `ps'
	use `res', clear
end

**## 9.5 Validation: pilih g (aturan tie: skor dalam 1% dari minimum -> g terkecil)
tempname pv
postfile `pv' str6 g gnum score rrmse_h1 rrmse_h3 rrmse_h6 using "$data\bma_validation.dta", replace
local k 0
foreach g of global bma_g_grid {
	local ++k
	di as txt "BMA validation: g = `g'"
	tempfile v`k'
	bv_bma_bt `g' validation $val_from $val_to `v`k''
	use `v`k'', clear
	bv_bma_score
	qui sum relative_rmse
	local sc = r(mean)
	post `pv' ("`g'") (cond("`g'" == "n", ., real("`g'"))) (`sc') (relative_rmse[1]) (relative_rmse[2]) (relative_rmse[3])
}
postclose `pv'
use "$data\bma_validation.dta", clear
qui sum score
gen byte eligible = score <= r(min)*1.01
* g = n (UIP) diperlakukan sebagai shrinkage paling lemah
replace gnum = 1e9 if missing(gnum)
gsort -eligible gnum
gen byte chosen = _n == 1
global bma_best_g = g[1]
drop gnum
format score rrmse_h* %6.3f
list, noobs clean
bv_out tab "B1_bma_validation_g"
di as res "BMA: g terpilih = $bma_best_g"

* simpan backtest validation untuk g terpilih
local k 0
foreach g of global bma_g_grid {
	local ++k
	if "`g'" == "$bma_best_g" {
		use `v`k'', clear
		save "$data\bma_val_backtest.dta", replace
	}
}

**## 9.6 Test out-of-sample (g terkunci)
tempfile tt
bv_bma_bt $bma_best_g test $test_from $test_to `tt'
use `tt', clear
save "$data\bma_test_backtest.dta", replace
bv_bma_score
format rmse_* %9.1f
format relative_rmse direction dm_hln dm_p cw_t cw_p %6.3f
list, noobs
save "$data\bma_test_scores.dta", replace
bv_out tab "B2_bma_test_scores"

* Perbandingan dengan BVARX pada origin test yang sama
use "$data\test_scores.dta", clear
keep horizon relative_rmse
rename relative_rmse relative_rmse_bvarx
merge 1:1 horizon using "$data\bma_test_scores.dta", keepusing(relative_rmse) nogen
rename relative_rmse relative_rmse_bma
format relative_rmse_* %6.3f
list, noobs clean
bv_out tab "B3_bma_vs_bvarx"

**## 9.7 Forecast akhir dan PIP sampel penuh (origin = final_origin)
use "$data\bma_data.dta", clear
local ir = $final_origin - mdate[1] + 1
foreach v of global bma_preds {
	if missing(`v'[`ir']) {
		di as error "BMA: prediktor `v' kosong pada final_origin"
		exit 459
	}
}
local s0 = usdidr[`ir']
tempname pf pp
postfile `pf' h mdate mean_pct sd_pct median lower95 lower80 upper80 upper95 using "$data\bma_final.dta", replace
postfile `pp' str8 predictor h pip using "$data\bma_pip_final.dta", replace
* forecast untuk setiap bulan 1..H_final; PIP dan model teratas hanya dilaporkan untuk $horizons
local hzlist $horizons
forval h = 1/$H_final {
	local evalh : list posof "`h'" in hzlist
	bv_bma_one `h' $final_origin $bma_best_g
	local m = r(yhat)
	local s = r(ysd)
	if `evalh' {
		foreach v of global bma_preds {
			post `pp' ("`v'") (`h') (r(pip_`v'))
		}
	}
	* interval: pendekatan normal untuk campuran predictive (mean dan sd analitis BMA)
	post `pf' (`h') ($final_origin + `h') (`m') (`s') (`s0'*exp(`m'/100)) ///
		(`s0'*exp((`m' - invnormal(0.975)*`s')/100)) (`s0'*exp((`m' - invnormal(0.90)*`s')/100)) ///
		(`s0'*exp((`m' + invnormal(0.90)*`s')/100)) (`s0'*exp((`m' + invnormal(0.975)*`s')/100))
	if !`evalh' continue
	* model teratas (probabilitas posterior model)
	di as txt _n "BMA h = `h': 10 model dengan probabilitas posterior tertinggi"
	bmastats models, top(10)
	tempname S V
	matrix `S' = r(summary)
	matrix `V' = r(varinclmat)
	preserve
		clear
		mata: bma_mat2data("`S'")
		gen rank = _n
		bv_out tab "B6_bma_top_models_h`h'"
		clear
		mata: bma_mat2data("`V'")
		bv_out diag "B6_bma_varinclusion_h`h'"
	restore
}
postclose `pf'
postclose `pp'
use "$data\bma_final.dta", clear
format mdate %tm
format mean_pct sd_pct %6.2f
format median lower* upper* %9.0f
list, noobs clean
bv_out tab "B5_bma_final_forecast"
use "$data\bma_pip_final.dta", clear
reshape wide pip, i(predictor) j(h)
format pip* %6.3f
list, noobs clean
bv_out diag "B4_bma_pip_final"

**## 9.8 Grafik
* PIP sepanjang origin (validation + test, g terpilih)
use "$data\bma_val_backtest.dta", clear
append using "$data\bma_test_backtest.dta"
format origin %tm
local k 0
foreach h of global horizons {
	local ++k
	twoway (line pip_ds origin if h == `h', lcolor("24 90 141")) ///
		(line pip_ddxy origin if h == `h', lcolor("164 87 23")) ///
		(line pip_dust origin if h == `h', lcolor("35 114 74")) ///
		(line pip_flow2 origin if h == `h', lcolor(purple)) ///
		(line pip_tb2 origin if h == `h', lcolor(gs8)) ///
		(line pip_dres2 origin if h == `h', lcolor(maroon)), ///
		yline(0.5, lpattern(dot) lcolor(gs10)) ylabel(0(0.25)1) ///
		title("h = `h'", size(medium)) xtitle("") ytitle("PIP") ///
		xlabel(#4, format(%tmCCYY) labsize(small)) legend(off) ///
		graphregion(color(white)) name(pip`k', replace) nodraw
}
graph combine pip1 pip2 pip3, cols(3) graphregion(color(white)) xsize(12) ysize(4) ///
	title("BMA: posterior inclusion probability per origin (g = $bma_best_g)", size(medium)) ///
	note("Biru = USD/IDR (t); oranye = DXY (t); hijau = UST10Y (t); ungu = flows (t-2); abu = trade balance (t-2); merah tua = cadangan (t-2).", size(vsmall)) ///
	name(bma_pip, replace)
graph export "$fig_bma\9_bma_pip_by_origin.png", replace width(2400)

* Test h = 3: aktual vs BMA vs RW
use "$data\bma_test_backtest.dta", clear
gen target = origin + h
format target %tm
gen double point = rw*exp(yhat/100)
twoway (line actual target if h == 3, lcolor(black) lwidth(medthick)) ///
	(line point target if h == 3, lcolor("24 90 141") lwidth(medthick)) ///
	(line rw target if h == 3, lcolor("164 87 23") lpattern(dash)), ///
	title("Test h = 3: aktual vs BMA vs random walk", size(medium)) xtitle("Bulan target") ytitle("IDR per USD") ///
	legend(order(1 "Aktual" 2 "BMA" 3 "Random walk") rows(1) position(6)) ///
	xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) graphregion(color(white)) name(bma_h3, replace)
graph export "$fig_bma\9_bma_test_h3.png", replace width(1800)

* Selisih kumulatif squared error (RW - BMA): naik = BMA lebih akurat
sort h origin
gen double dse = (actual - rw)^2 - (actual - point)^2
by h: gen double cum_dse = sum(dse)
twoway (line cum_dse target if h == 1, lcolor("24 90 141") lwidth(medthick)) ///
	(line cum_dse target if h == 3, lcolor("164 87 23") lwidth(medthick)) ///
	(line cum_dse target if h == 6, lcolor("35 114 74") lwidth(medthick)), ///
	yline(0, lpattern(dot)) title("Selisih kumulatif squared error: RW - BMA (naik = BMA lebih akurat)", size(medium)) ///
	xtitle("Bulan target") ytitle("") legend(order(1 "h = 1" 2 "h = 3" 3 "h = 6") rows(1) position(6)) ///
	xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) graphregion(color(white)) name(bma_cum, replace)
graph export "$fig_bma\9_bma_cum_sse.png", replace width(1800)
