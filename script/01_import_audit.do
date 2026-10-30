**# 1. IMPOR DAN AUDIT DATABASE
* Rmd: chunk impor-database, audit-flow-dan-deskriptif, unit-root-opsional.
* Menulis: intermediate/database.dta, flow_components.dta, sources.dta, rating_events.dta,
*          audit_missing.dta, descriptive.dta, unit_root.dta
* Output:  tables/A0_*, T1_descriptive; diagnostics/D1_audit_missing, D2_unit_root_adf;
*          figures/1_data_series.png

**## 1.1 Sheet pendukung
cap import excel using "$data_file", sheet("sources") firstrow allstring clear
if _rc {
	di as error "Tidak dapat membaca $data_file. Tutup file di Excel lalu jalankan ulang."
	exit 603
}
save "$data\sources.dta", replace
bv_out tab "A0_sources"

import excel using "$data_file", sheet("rating_events") firstrow clear
save "$data\rating_events.dta", replace
bv_out tab "A0_rating_events"

import excel using "$data_file", sheet("flow_components") firstrow clear
sort year month
save "$data\flow_components.dta", replace

**## 1.2 Sheet database_monthly dan pemeriksaan struktur
import excel using "$data_file", sheet("database_monthly") firstrow clear
foreach v in year month mdate usdidr trade_bal_usdbn net_flows_idrtn fx_reserves_usdbn dxy ust10y_pct core_complete {
	confirm numeric variable `v'
}
sort mdate
isid mdate
assert mdate - mdate[_n-1] == 1 if _n > 1
assert inrange(month, 1, 12)
assert mdate == ym(year, month)
format mdate %tm
tsset mdate, monthly

* core_complete harus sama dengan kelengkapan lima variabel inti
global core "usdidr trade_bal_usdbn net_flows_idrtn fx_reserves_usdbn dxy"
egen byte _nmiss = rowmiss($core)
gen byte complete_check = _nmiss == 0
drop _nmiss
assert core_complete == complete_check
assert usdidr > 0 & dxy > 0 & fx_reserves_usdbn > 0

* Flows gabungan = saham + SBN + SRBI (sheet flow_components)
merge 1:1 year month using "$data\flow_components.dta", keepusing(flow_saham_idrtn flow_sbn_idrtn flow_srbi_idrtn) assert(match) nogen
sort mdate
gen double _fsum = flow_saham_idrtn + flow_sbn_idrtn + flow_srbi_idrtn
assert abs(_fsum - net_flows_idrtn) < 1e-8
drop _fsum

* Audit missing pada variabel database mentah (September 2026 tidak memiliki ekspor/impor;
* sengaja tidak diisi nol atau interpolasi)
tempname pm
postfile `pm' str32 variable missing using "$data\audit_missing.dta", replace
foreach v of varlist _all {
	qui count if missing(`v')
	if r(N) > 0 post `pm' ("`v'") (r(N))
}
postclose `pm'
preserve
	use "$data\audit_missing.dta", clear
	list, noobs clean
	bv_out diag "D1_audit_missing"
restore

* Bulan lengkap terakhir (cutoff fit akhir) dan bulan pasar terakhir (anchor forecast akhir)
qui sum mdate if complete_check == 1
global latest_complete = r(max)
qui sum mdate if !missing(usdidr, dxy)
global final_origin = r(max)
di "Bulan lengkap terakhir: " %tm $latest_complete "   anchor pasar terakhir: " %tm $final_origin

**## 1.3 Transformasi model (Rmd: make_data)
* levels: 100 log USD/IDR, TB, flows/10, 100 log cadangan; eksogen 100 log DXY
gen double y_s     = 100*ln(usdidr)
gen double y_tb    = trade_bal_usdbn
gen double y_flows = net_flows_idrtn/10
gen double y_res   = 100*ln(fx_reserves_usdbn)
gen double x_dxy   = 100*ln(dxy)
* changes: perubahan log USD/IDR, cadangan, DXY; TB dan flows tetap
gen double dy_s    = D.y_s
gen double dy_res  = D.y_res
gen double dx_dxy  = D.x_dxy
gen double x_ust   = ust10y_pct
gen double sin12   = sin(2*_pi*month/12)
gen double cos12   = cos(2*_pi*month/12)
gen date = dofm(mdate)
format date %td
label var y_s "100 log USD/IDR"
label var y_tb "Trade balance (USD bn)"
label var y_flows "Flows gabungan (Rp10 tn)"
label var y_res "100 log cadangan valas"
label var x_dxy "100 log DXY"
save "$data\database.dta", replace

**## 1.4 Statistik deskriptif lima variabel inti
tempname ph
postfile `ph' str24 variable n mean sd min max using "$data\descriptive.dta", replace
foreach v of global core {
	qui sum `v'
	post `ph' ("`v'") (r(N)) (r(mean)) (r(sd)) (r(min)) (r(max))
}
postclose `ph'
preserve
	use "$data\descriptive.dta", clear
	list, noobs clean
	bv_out tab "T1_descriptive"
restore

**## 1.5 Grafik empat seri inti
local gopt "xtitle("") graphregion(color(white)) xlabel(, format(%tmCY))"
tsline usdidr, title("USD/IDR", size(medium)) ytitle("IDR/USD") `gopt' name(g1, replace) nodraw
tsline trade_bal_usdbn, title("Trade balance", size(medium)) ytitle("USD bn") `gopt' name(g2, replace) nodraw
twoway spike net_flows_idrtn mdate, title("Combined flows", size(medium)) ytitle("IDR tn") `gopt' name(g3, replace) nodraw
tsline fx_reserves_usdbn, title("Foreign currency reserves", size(medium)) ytitle("USD bn") `gopt' name(g4, replace) nodraw
graph combine g1 g2 g3 g4, cols(2) graphregion(color(white)) name(data_series, replace)
graph save "$gph\1_data_series.gph", replace
graph export "$fig\1_data_series.png", replace width(1800)

**## 1.6 Unit root (ADF), sampel 2014+ dengan data inti lengkap
* Lag ADF 0-6 dipilih dengan BIC pada sampel yang sama (setara ur.df selectlags="BIC").
* H0 = unit root. Bukan aturan otomatis untuk mendiferensiasi; tidak membuktikan kointegrasi.
preserve
	keep if year >= 2014 & complete_check == 1
	tsset mdate, monthly
	gen double l_usdidr = ln(usdidr)
	gen double l_res = ln(fx_reserves_usdbn)
	gen double l_dxy = ln(dxy)
	gen double d_l_usdidr = D.l_usdidr
	gen double d_l_res = D.l_res
	gen double d_l_dxy = D.l_dxy
	tempname pu
	postfile `pu' str16 series str8 det lags N tau pvalue using "$data\unit_root.dta", replace
	* level dengan trend; perubahan/arus dengan konstanta saja
	foreach spec in "l_usdidr trend" "d_l_usdidr drift" "l_res trend" "d_l_res drift" ///
		"l_dxy trend" "d_l_dxy drift" "trade_bal_usdbn drift" "net_flows_idrtn drift" {
		gettoken v det : spec
		local det = strtrim("`det'")
		local tr = cond("`det'" == "trend", "_trend", "")
		cap drop _trend
		gen _trend = _n
		* sampel bersama untuk semua lag (lag maksimum 6)
		qui reg D.`v' L.`v' `tr' L(1/6)D.`v'
		tempvar s
		gen byte `s' = e(sample)
		local best 0
		local bic_best .
		forval k = 0/6 {
			if `k' == 0 qui reg D.`v' L.`v' `tr' if `s'
			else qui reg D.`v' L.`v' `tr' L(1/`k')D.`v' if `s'
			local bic = -2*e(ll) + e(rank)*ln(e(N))
			if `bic' < `bic_best' {
				local bic_best = `bic'
				local best = `k'
			}
		}
		qui dfuller `v', `det' lags(`best')
		post `pu' ("`v'") ("`det'") (`best') (r(N)) (r(Zt)) (r(p))
	}
	postclose `pu'
	use "$data\unit_root.dta", clear
	gen str24 conclusion = cond(pvalue < 0.05, "tolak H0 (stasioner)", "gagal tolak H0 (unit root)")
	format tau pvalue %8.3f
	list, noobs clean
	bv_out diag "D2_unit_root_adf"
restore
