* ============================================================================
* rupiah_bvarx_all.do: SEMUA MODUL DALAM SATU FILE, siap copy-paste (v3, BVARX changes).
* Cara pakai: buka Do-file Editor (doedit), paste seluruh isi, klik Do (Ctrl+D).
* Jangan paste ke Command window (blok Mata dan /// hanya jalan sebagai do-file).
* Digabung dari 00_master.do, 01-04, 06-08; isi dan urutan sama.
* ============================================================================

**# 0. MASTER: Forecast dan skenario USD/IDR dengan BVARX
* v3: semua tahap memakai BVARX changes (lihat CHANGELOG.md).
* Port Stata dari input/reference/Manual_Model_Rupiah_BVARX.Rmd (versi R).
* Jalankan seluruh file ini sebagai do-file: do "script/00_master.do".
* Tutup Database_Rupiah_Bulanan.xlsx dan output Excel di Excel sebelum menjalankan.
* Bookmark **# / **## dapat dipakai di Do-file Editor (Stata 17+).
* Jangan menaruh komentar "//" di akhir baris "global".

version 19
clear all
set more off
set varabbrev off
set linesize 120

*****************************
****** Global Settings ******
*****************************

global base "C:\Users\LENOVO05\github\Simulasi-Rupiah"

* Data mentah (tidak pernah ditulis oleh kode)
global source "$base\input"
global data_file "$source\Database_Rupiah_Bulanan.xlsx"
* Do-file
global script "$base\script"
* Dataset Stata hasil olahan
global data "$base\intermediate"
* Hasil akhir
*   output/figures      grafik PNG siap pakai
*   output/tables       tabel hasil (CSV), juga disalin ke workbook ringkasan
*   output/diagnostics  uji dan diagnostik (unit root, residual, ESS, akar companion)
*   output/gph          grafik kerja Stata (.gph)
global results "$base\output"
global fig "$results\figures"
global tab "$results\tables"
global diag "$results\diagnostics"
global gph "$results\gph"
global xlsx "$results\rupiah_bvarx_results.xlsx"
foreach d in data results fig tab diag gph {
	cap mkdir "${`d'}"
}
cap erase "$xlsx"

* bv_out: simpan dataset di memori sebagai CSV (folder tab/diag) dan sheet di workbook ringkasan
cap program drop bv_out
program define bv_out
	args folder name
	export delimited using "${`folder'}/`name'.csv", replace
	cap export excel using "$xlsx", sheet("`name'", replace) firstrow(variables)
	if _rc {
		di as error "Gagal menulis $xlsx (sheet `name'). Tutup file di Excel lalu jalankan ulang."
		exit 603
	}
end

* bv_pngtable: render variabel string di memori sebagai tabel PNG (satu baris per observasi)
*   heads() = judul kolom (dalam tanda kutip), widths() = lebar tiap kolom (satuan kanvas)
cap program drop bv_pngtable
program define bv_pngtable
	syntax varlist, File(string) Title(string) Heads(string asis) Widths(numlist) [Note(string)]
	local nv : word count `varlist'
	local nr = _N
	local x 2
	local j 0
	foreach w of numlist `widths' {
		local ++j
		local x`j' = `x'
		local x = `x' + `w'
	}
	local xmax = `x'
	local step = 88/(`nr' + 1)
	local txt ""
	forval j = 1/`nv' {
		local h : word `j' of `heads'
		local txt `txt' text(96 `x`j'' "`h'", place(e) size(small) color(black))
	}
	forval i = 1/`nr' {
		local y = 96 - `step'*`i'
		local j 0
		foreach v of local varlist {
			local ++j
			local s = `v'[`i']
			local txt `txt' text(`y' `x`j'' "`s'", place(e) size(small))
		}
	}
	local yl = 96 - `step'/2
	twoway scatteri 0 0 100 `xmax', msymbol(none) xscale(off range(0 `xmax')) yscale(off range(0 100)) ///
		xlabel(none) ylabel(none) `txt' yline(`yl', lcolor(gs10)) ///
		title(`"`title'"', size(medium)) note(`"`note'"', size(vsmall)) ///
		graphregion(color(white)) plotregion(style(none)) legend(off) ///
		xsize(`=max(8, `xmax'/9)') ysize(`=max(3, 1.2 + 0.45*`nr')') name(pngtab, replace)
	graph export "`file'", replace width(2400)
end

**## 0.1 Parameter manual (setara blok params di Rmd)
* profile: quick (cek alur) | standard | publication (angka untuk naskah)
global profile "standard"
* 1 = tambahkan UST10Y sebagai eksogen (putuskan di tahap validation)
global include_ust 0
* Jumlah harmonik musiman sin/cos: 1 = periode 12 bulan (manual), 2 = + periode 6 bulan
* (residual trade balance v2 masih berautokorelasi di lag 6 dan 12)
global seas_harm 2
* 1 = jalankan uji unit root ADF + Phillips-Perron (01, bagian 1.6)
global run_adf 1
* Seed utama (setara set.seed(30102026) di Rmd)
global seed 30102026

* Jumlah posterior draws per tahap, mengikuti profile
if "$profile" == "quick" {
	global n_val 60
	global n_test 150
	global n_final 600
}
else if "$profile" == "standard" {
	global n_val 200
	global n_test 1000
	global n_final 6000
}
else if "$profile" == "publication" {
	global n_val 1000
	global n_test 5000
	global n_final 30000
}
else {
	di as error "profile harus quick, standard, atau publication"
	exit 198
}

**## 0.2 Rancangan eksperimen (ditetapkan sebelum melihat hasil)
* Horizon evaluasi (bulan) dan jeda rilis makro konservatif
global horizons "1 3 6"
global release_lag 2
* Grid validation: start year, lag, lambda (shrinkage)
global grid_start "2013 2014 2017"
global grid_p "1 2"
global grid_lambda "0.10 0.30"
* Origin validation (Jan 2021 - Jun 2023) dan awal test (Jan 2024)
global val_from = ym(2021,1)
global val_to   = ym(2023,6)
global test_from = ym(2024,1)
* Horizon final forecast dan skenario
global H_final 6
* Model: BVARX dalam perubahan (changes) untuk validation, test, forecast, dan skenario.
* USD/IDR, cadangan, DXY = perubahan 100*log bulanan; TB dan flows = arus bulanan.
* Versi level (v1-v2, menarik kurs ke rata-rata sampel) diarsipkan di archive/v2_levels/.
global model_mode "changes"
* Skenario ilustratif: titik pembatas (bulan ke-) dan besaran shock
global cond_horizons "3 6"
* Adverse / Upside: DXY +/-2% pada akhir horizon, TB -/+ USD1 bn, flows -/+ Rp10 tn
global dxy_shock 0.02
global tb_shock 1
global flows_shock 10
* Severe Adverse: DXY +5%, TB -USD2 bn, flows -Rp30 tn
global dxy_severe 0.05
global tb_severe 2
global flows_severe 30
* Matriks shock untuk Mata (baris: Adverse, Upside, Severe Adverse; kolom: DXY, TB, flows)
global shock_mat "(($dxy_shock, -$tb_shock, -$flows_shock) \ (-$dxy_shock, $tb_shock, $flows_shock) \ ($dxy_severe, -$tb_severe, -$flows_severe))"

set seed $seed

**## 0.3 Log
cap log close main
log using "$results\run_log.log", replace text name(main)
di "Mulai: `c(current_date)' `c(current_time)'  profile=$profile  include_ust=$include_ust"
timer clear 1
timer on 1


* ---------------------------------------------------------------- 01_import_audit.do
**# 1. IMPOR DAN AUDIT DATABASE
* Rmd: chunk impor-database, audit-flow-dan-deskriptif, unit-root-opsional.
* Menulis: intermediate/database.dta, flow_components.dta, sources.dta, rating_events.dta,
*          audit_missing.dta, descriptive.dta, unit_root.dta
* Output:  tables/A0_*, T1_descriptive; diagnostics/D1_audit_missing, D2_unit_root;
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
* harmonik kedua (periode 6 bulan) untuk musiman trade balance
gen double sin6    = sin(4*_pi*month/12)
gen double cos6    = cos(4*_pi*month/12)
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

**## 1.6 Unit root: ADF dan Phillips-Perron, sampel 2014+ dengan data inti lengkap
* H0 = unit root. p < 0,05 -> tolak H0 (stasioner). Pembenaran model changes: level kurs, cadangan,
* DXY diharapkan unit root, perubahannya stasioner. Bukan bukti kointegrasi.
* Lag ADF 0-6 dipilih dengan BIC pada sampel bersama (setara ur.df selectlags = "BIC").
* Tiap seri dibungkus capture: satu seri gagal tidak menghentikan run; progres dicetak per seri.
if $run_adf {
preserve
	keep if year >= 2014 & complete_check == 1
	tsset mdate, monthly
	gen double l_usdidr = ln(usdidr)
	gen double l_res = ln(fx_reserves_usdbn)
	gen double l_dxy = ln(dxy)
	gen double d_l_usdidr = D.l_usdidr
	gen double d_l_res = D.l_res
	gen double d_l_dxy = D.l_dxy
	gen double tb = trade_bal_usdbn
	gen double flows = net_flows_idrtn
	gen double trend_t = _n
	tempname pu
	postfile `pu' str16 series str8 det lags N adf_tau adf_p pp_z pp_p rc using "$data\unit_root.dta", replace
	* level dengan trend; perubahan dan arus dengan konstanta saja
	foreach spec in "l_usdidr trend" "d_l_usdidr drift" "l_res trend" "d_l_res drift" ///
		"l_dxy trend" "d_l_dxy drift" "tb drift" "flows drift" {
		gettoken v det : spec
		local det = strtrim("`det'")
		local tr = cond("`det'" == "trend", "trend_t", "")
		local ppopt = cond("`det'" == "trend", "trend", "")
		di as txt "Unit root: `v' (`det')"
		local best .
		local N .
		local tau .
		local p .
		local ppz .
		local ppp .
		capture noisily {
			* sampel bersama untuk semua lag (lag maksimum 6)
			qui regress D.`v' L.`v' `tr' L(1/6)D.`v'
			tempvar s
			qui gen byte `s' = e(sample)
			local best 0
			local bic_best = .
			forval k = 0/6 {
				if `k' == 0 qui regress D.`v' L.`v' `tr' if `s'
				else qui regress D.`v' L.`v' `tr' L(1/`k')D.`v' if `s'
				local bic = -2*e(ll) + e(rank)*ln(e(N))
				if `bic' < `bic_best' {
					local bic_best = `bic'
					local best = `k'
				}
			}
			qui dfuller `v', `det' lags(`best')
			local N = r(N)
			local tau = r(Zt)
			local p = r(p)
			qui pperron `v', `ppopt' lags(4)
			local ppz = r(Zt)
			local ppp = r(p)
		}
		local rc = _rc
		post `pu' ("`v'") ("`det'") (`best') (`N') (`tau') (`p') (`ppz') (`ppp') (`rc')
	}
	postclose `pu'
	use "$data\unit_root.dta", clear
	gen str28 adf_conclusion = cond(rc != 0, "gagal dihitung", cond(adf_p < 0.05, "stasioner (tolak H0)", "unit root (gagal tolak H0)"))
	gen str28 pp_conclusion = cond(rc != 0, "gagal dihitung", cond(pp_p < 0.05, "stasioner (tolak H0)", "unit root (gagal tolak H0)"))
	format adf_tau adf_p pp_z pp_p %8.3f
	list, noobs clean
	bv_out diag "D2_unit_root"
restore
}

* ---------------------------------------------------------------- 02_bvarx_functions.do
**# 2. FUNGSI MATA BVARX
* Rmd: chunk fungsi-estimasi, fungsi-jalur-dan-kondisi, fungsi-backtest, bootstrap-error.
* Hanya mendefinisikan fungsi (tidak menulis file). Jalankan sebelum 03-07.
*
* Model (setelah standardisasi dengan data training saja):
*   Y = Z C + U,  Sigma ~ IW(S0, nu0),  C | Sigma ~ MN(C0, V0, Sigma)
*   Z = [1, lag 1..p dari y, eksogen x];  y = (100 log S, TB, F/10, 100 log R)
*   x = (100 log DXY, [UST10Y], sin12, cos12)
* Prior Minnesota-style konjugat; posterior draws independen (tanpa MCMC).
* Conditional forecast (Waggoner-Zha, hard conditions pada observabel) dengan
* importance weight = density kondisi, lalu resampling. ESS dilaporkan.

cap program drop bv_score
mata: mata clear

**## 2.1 Struktur data dan helper
mata:
mata set matastrict on

struct bvdata {
	real colvector mdate, usdidr, dxy, ust
	real matrix Y, Xall
	real scalar nharm
	string scalar mode
}

struct bvfit {
	real matrix Cn, Vn, LV, Sn, hist, resid
	real rowvector my, sy, mx, sx, xc
	real colvector idx
	real scalar nu, K, p, M, n, cutoff, start_year, lambda, last_spot
	string scalar mode
}

struct bvfut {
	real colvector times, dxy, ust
	real matrix X, cond
	real scalar origin, h
}

struct bvpred {
	real matrix paths, spot, cond
	real colvector w, times
	real scalar ess, ndraw, root_gt1, root_gt105
}

// Muat data dari dataset Stata di memori (database.dta). mode = "levels" | "changes"
struct bvdata scalar bv_load(string scalar mode)
{
	struct bvdata scalar d
	if (mode != "levels" & mode != "changes") _error("mode harus levels atau changes")
	d.mode   = mode
	d.nharm  = strtoreal(st_global("seas_harm"))
	if (missing(d.nharm)) d.nharm = 1
	d.mdate  = st_data(., "mdate")
	d.usdidr = st_data(., "usdidr")
	d.dxy    = st_data(., "dxy")
	d.ust    = st_data(., "x_ust")
	if (mode == "levels") {
		d.Y    = st_data(., ("y_s", "y_tb", "y_flows", "y_res"))
		d.Xall = st_data(., ("x_dxy", "x_ust", "sin12", "cos12", "sin6", "cos6"))
	}
	else {
		d.Y    = st_data(., ("dy_s", "y_tb", "y_flows", "dy_res"))
		d.Xall = st_data(., ("dx_dxy", "x_ust", "sin12", "cos12", "sin6", "cos6"))
	}
	if (any((d.mdate[|2 \ rows(d.mdate)|] - d.mdate[|1 \ rows(d.mdate)-1|]) :!= 1)) {
		_error("mdate harus berurutan tanpa celah")
	}
	return(d)
}

// Baris data untuk bulan m (mdate %tm)
real scalar bv_row(struct bvdata scalar d, real scalar m)
{
	real scalar r
	r = m - d.mdate[1] + 1
	if (r < 1 | r > rows(d.mdate)) _error("bulan di luar data: " + strofreal(m))
	return(r)
}

// Quantile tipe 7 (default R) untuk tiap kolom X
real matrix bv_quantile(real matrix X, real rowvector probs)
{
	real matrix Q
	real colvector x
	real scalar j, k, n, h, lo
	n = rows(X)
	Q = J(cols(probs), cols(X), .)
	for (j = 1; j <= cols(X); j++) {
		x = sort(X[., j], 1)
		for (k = 1; k <= cols(probs); k++) {
			h  = (n - 1)*probs[k] + 1
			lo = floor(h)
			Q[k, j] = lo >= n ? x[n] : x[lo] + (h - lo)*(x[lo+1] - x[lo])
		}
	}
	return(Q)
}

// Standar deviasi sampel (pembagi n-1)
real scalar bv_sd(real colvector x)
{
	return(sqrt(variance(x)))
}

// Simpan matriks R ke dataset Stata baru (mengganti data di memori)
void bv_tostata(real matrix R, string rowvector names)
{
	real scalar j
	stata("clear")
	st_addobs(rows(R))
	for (j = 1; j <= cols(names); j++) (void) st_addvar("double", names[j])
	st_store(., names, R)
}
end

**## 2.2 Estimasi posterior (Rmd: fit_bvar)
mata:
// soc = 0: prior manual saja. soc > 0: tambah dummy sum-of-coefficients dan
// dummy-initial-observation (Doan-Litterman-Sims; Sims-Zha 1998) dengan tightness mu = delta = soc.
// Dummy menahan tarikan ke rata-rata sampel (spurious mean reversion) pada model level.
struct bvfit scalar bv_fit(struct bvdata scalar d, real scalar cutoff, real scalar start_year,
	real scalar p, real scalar lambda, real scalar inc_ust, real scalar soc)
{
	struct bvfit scalar f
	real colvector idx, good, r, yj
	real rowvector own, v0, arvar, ybar, xbar, zr
	real matrix Y0, X0, Ys, Xs, Z, C0, V0i, E, D, S0, Xr, Yd, Zd, Ya, Za, Ea
	real scalar K, i, j, l, T, nu0, last

	K = cols(d.Y)
	f.xc = inc_ust ? (1, 2, 3, 4) : (1, 3, 4)
	// harmonik musiman kedua (periode 6 bulan), global seas_harm = 2
	if (d.nharm >= 2) f.xc = f.xc, (5, 6)
	idx = selectindex(d.mdate :>= 12*(start_year - 1960) :& d.mdate :<= cutoff)
	idx = select(idx, idx :> p)
	good = J(rows(idx), 1, 0)
	for (i = 1; i <= rows(idx); i++) {
		good[i] = !hasmissing(d.Y[|idx[i]-p, 1 \ idx[i], K|]) & !hasmissing(d.Xall[idx[i], f.xc])
	}
	idx = select(idx, good)
	T = rows(idx)
	if (T < 36) _error("sampel training < 36 bulan")
	if (d.mdate[idx[T]] != cutoff) _error("observasi terakhir training tidak sama dengan cutoff")
	if (any((idx[|2 \ T|] - idx[|1 \ T-1|]) :!= 1)) _error("sampel training tidak berurutan")

	Y0 = d.Y[idx, .]
	f.my = mean(Y0)
	f.sy = sqrt(diagonal(variance(Y0)))'
	X0 = d.Xall[idx, f.xc]
	f.mx = mean(X0)
	f.sx = sqrt(diagonal(variance(X0)))'
	if (any(f.sy :<= 0) | any(f.sx :<= 0)) _error("variabel konstan pada sampel training")
	Ys = (Y0 :- f.my) :/ f.sy
	Xs = (X0 :- f.mx) :/ f.sx
	Z = J(T, 1, 1)
	for (l = 1; l <= p; l++) Z = Z, ((d.Y[idx :- l, .] :- f.my) :/ f.sy)
	Z = Z, Xs

	// Varians innovation AR(1) per variabel, training saja
	arvar = J(1, K, .)
	for (j = 1; j <= K; j++) {
		yj = Ys[|2, j \ T, j|]
		Xr = J(T-1, 1, 1), Ys[|1, j \ T-1, j|]
		r  = yj - Xr*(invsym(cross(Xr, Xr))*cross(Xr, yj))
		arvar[j] = max((mean(r:^2), 1e-4))
	}

	// Prior: mean own first lag = 1 untuk level (log kurs, log cadangan), 0 lainnya
	f.M = cols(Z)
	C0  = J(f.M, K, 0)
	own = d.mode == "levels" ? (1, 0, 0, 1) : J(1, K, 0)
	for (j = 1; j <= K; j++) C0[1+j, j] = own[j]
	v0 = 100
	for (l = 1; l <= p; l++) v0 = v0, lambda^2 :/ (l^2 :* arvar)
	v0 = v0, J(1, cols(f.xc), 0.5^2)
	V0i = diag(1 :/ v0)

	// Dummy observations (hanya model level): ybar = rata-rata p observasi pra-sampel
	Ya = Ys
	Za = Z
	if (soc > 0 & d.mode == "levels") {
		ybar = mean((d.Y[|idx[1]-p, 1 \ idx[1]-1, K|] :- f.my) :/ f.sy)
		xbar = mean(Xs[|1, 1 \ p, cols(Xs)|])
		Yd = diag(ybar/soc)
		Zd = J(K, 1, 0)
		for (l = 1; l <= p; l++) Zd = Zd, diag(ybar/soc)
		Zd = Zd, J(K, cols(Xs), 0)
		zr = 1/soc
		for (l = 1; l <= p; l++) zr = zr, ybar/soc
		zr = zr, xbar/soc
		Ya = Ys \ Yd \ (ybar/soc)
		Za = Z \ Zd \ zr
	}

	f.Vn = cholinv(V0i + cross(Za, Za))
	f.Vn = (f.Vn + f.Vn')/2
	f.Cn = f.Vn*(V0i*C0 + cross(Za, Ya))
	E  = Ys - Z*f.Cn
	Ea = Ya - Za*f.Cn
	D = f.Cn - C0
	nu0 = K + 2
	S0 = diag(arvar*(nu0 - K - 1))
	f.Sn = S0 + cross(Ea, Ea) + D'*V0i*D
	f.Sn = (f.Sn + f.Sn')/2
	f.LV = cholesky(f.Vn)

	last = idx[T]
	f.hist = (d.Y[|last-p+1, 1 \ last, K|] :- f.my) :/ f.sy
	f.nu = nu0 + rows(Ya)
	f.K = K
	f.p = p
	f.n = T
	f.idx = idx
	f.cutoff = cutoff
	f.start_year = start_year
	f.lambda = lambda
	f.mode = d.mode
	f.last_spot = d.usdidr[last]
	f.resid = E :* f.sy
	return(f)
}

// Satu draw posterior: Sigma ~ IW(Sn, nu) lewat Bartlett, C | Sigma ~ MN(Cn, Vn, Sigma)
void bv_draw(struct bvfit scalar f, real matrix C, real matrix Sigma)
{
	real matrix L, A, LA
	real scalar i, j
	L = cholesky(cholinv(f.Sn))
	A = J(f.K, f.K, 0)
	for (i = 1; i <= f.K; i++) {
		A[i, i] = sqrt(rchi2(1, 1, f.nu - i + 1))
		for (j = 1; j < i; j++) A[i, j] = rnormal(1, 1, 0, 1)
	}
	LA = L*A
	Sigma = cholinv(LA*LA')
	Sigma = (Sigma + Sigma')/2
	C = f.Cn + f.LV*rnormal(f.M, f.K, 0, 1)*cholesky(Sigma)'
}
end

**## 2.3 Jalur masa depan dan conditional forecast (Rmd: make_future, forecast_system, predict_paths)
mata:
// Jalur eksogen dari cutoff+1 sampai origin+h. DXY menuju (1+g) pada akhir horizon, UST +du.
// Bulan s/d origin memakai realisasi DXY/UST dan USD/IDR sebagai kondisi bridge.
struct bvfut scalar bv_future(struct bvfit scalar f, struct bvdata scalar d, real scalar origin,
	real scalar h, real scalar g, real scalar du)
{
	struct bvfut scalar u
	real colvector frac, known, logdxy, xd, mon, ix
	real scalar r0, H, i
	real matrix Xall
	if (origin < f.cutoff | h < 1) _error("origin harus >= cutoff dan h >= 1")
	u.origin = origin
	u.h = h
	u.times = ((f.cutoff + 1) :: (origin + h))
	H = rows(u.times)
	r0 = bv_row(d, origin)
	if (missing(d.dxy[r0])) _error("DXY tidak tersedia pada origin")
	frac  = ((u.times :- origin) :* (u.times :> origin)) / h
	u.dxy = d.dxy[r0] :* (1 + g):^frac
	u.ust = d.ust[r0] :+ du :* frac
	known = u.times :<= origin
	ix = J(0, 1, .)
	for (i = 1; i <= H; i++) {
		if (known[i]) {
			u.dxy[i] = d.dxy[bv_row(d, u.times[i])]
			u.ust[i] = d.ust[bv_row(d, u.times[i])]
			ix = ix \ i
		}
	}
	logdxy = 100*ln(u.dxy)
	if (f.mode == "changes") {
		xd = logdxy - ((100*ln(d.dxy[bv_row(d, f.cutoff)])) \ logdxy[|1 \ H|])[|1 \ H|]
	}
	else xd = logdxy
	mon = mod(u.times, 12) :+ 1
	Xall = xd, u.ust, sin(2*pi()*mon/12), cos(2*pi()*mon/12), sin(4*pi()*mon/12), cos(4*pi()*mon/12)
	u.X = Xall[., f.xc]
	// Kondisi: kolom (step, variabel 1..4, nilai). Bridge USD/IDR teramati.
	u.cond = J(0, 3, .)
	for (i = 1; i <= rows(ix); i++) {
		u.cond = u.cond \ (ix[i], 1, d.Y[bv_row(d, u.times[ix[i]]), 1])
	}
	return(u)
}

// Mean jalur (standar) dan matriks G (Y_f = mu + G z) untuk satu draw parameter
void bv_system(struct bvfit scalar f, real matrix C, real matrix Sigma, real matrix Xs,
	real colvector mu, real matrix G, real scalar root)
{
	real matrix hist, mus, Acat, Psi, L, a, comp
	real rowvector z
	real scalar K, p, H, h, j, l
	K = f.K
	p = f.p
	H = rows(Xs)
	hist = f.hist
	mus = J(H, K, .)
	for (h = 1; h <= H; h++) {
		z = 1
		for (l = 1; l <= p; l++) z = z, hist[rows(hist)-l+1, .]
		z = z, Xs[h, .]
		mus[h, .] = z*C
		hist = hist \ mus[h, .]
	}
	// A_l = (blok koefisien lag l)'; disusun [A_1, ..., A_p]
	Acat = J(K, 0, .)
	for (l = 1; l <= p; l++) Acat = Acat, C[|1+(l-1)*K+1, 1 \ 1+l*K, K|]'
	// Koefisien MA: psi_0 = I, psi_j = sum_l A_l psi_{j-l}; disimpan berdampingan
	Psi = I(K), J(K, K*(H-1), 0)
	for (j = 1; j <= H-1; j++) {
		a = J(K, K, 0)
		for (l = 1; l <= min((p, j)); l++) {
			a = a + Acat[|1, (l-1)*K+1 \ K, l*K|]*Psi[|1, (j-l)*K+1 \ K, (j-l+1)*K|]
		}
		Psi[|1, j*K+1 \ K, (j+1)*K|] = a
	}
	L = cholesky(Sigma)
	G = J(H*K, H*K, 0)
	for (h = 1; h <= H; h++) {
		for (j = 1; j <= h; j++) {
			G[|(h-1)*K+1, (j-1)*K+1 \ h*K, j*K|] = Psi[|1, (h-j)*K+1 \ K, (h-j+1)*K|]*L
		}
	}
	mu = vec(mus')
	// Akar companion terbesar: diagnostik, bukan filter draw
	if (p == 1) comp = Acat
	else comp = Acat \ (I(K*(p-1)), J(K*(p-1), K, 0))
	root = max(abs(eigenvalues(comp)))
}

// Simulasi jalur bersyarat. extra = kondisi tambahan (step, var, nilai) dalam satuan model.
struct bvpred scalar bv_predict(struct bvfit scalar f, struct bvfut scalar u, real scalar ndraw,
	real matrix extra, real scalar seed)
{
	struct bvpred scalar pr
	real matrix cond, Xs, C, Sigma, G, RG, Q, Qi, paths, S, Ym
	real colvector pos, target, logw, roots, mu, z, delta, yf, cw, uu, keep, w
	real rowvector sy_c, my_c
	real scalar K, H, b, npos, root, i, k, ldq

	rseed(seed)
	K = f.K
	H = rows(u.times)
	cond = u.cond \ extra
	npos = rows(cond)
	if (npos) {
		if (any(cond[., 1] :< 1) | any(cond[., 1] :> H)) _error("step kondisi di luar horizon")
		if (hasmissing(cond)) _error("nilai kondisi tidak lengkap")
		pos = (cond[., 1] :- 1)*K + cond[., 2]
		if (rows(uniqrows(pos)) != npos) _error("kondisi ganda pada step/variabel yang sama")
		my_c = f.my[cond[., 2]']
		sy_c = f.sy[cond[., 2]']
		target = (cond[., 3] - my_c') :/ sy_c'
	}
	Xs = (u.X :- f.mx) :/ f.sx
	paths = J(ndraw, H*K, .)
	logw  = J(ndraw, 1, 0)
	roots = J(ndraw, 1, .)
	for (b = 1; b <= ndraw; b++) {
		bv_draw(f, C, Sigma)
		bv_system(f, C, Sigma, Xs, mu, G, root)
		z = rnormal(H*K, 1, 0, 1)
		if (npos) {
			RG = G[pos, .]
			Q  = RG*RG'
			Qi = cholinv(Q)
			delta = target - mu[pos]
			ldq = 2*sum(ln(diagonal(cholesky(Q))))
			logw[b] = -0.5*(npos*ln(2*pi()) + ldq + delta'*Qi*delta)
			z = z + RG'*(Qi*(delta - RG*z))
		}
		yf = mu + G*z
		Ym = rowshape(yf, H) :* f.sy :+ f.my
		paths[b, .] = rowshape(Ym, 1)
		roots[b] = root
	}
	if (hasmissing(paths) | hasmissing(logw)) _error("jalur atau bobot tidak finite")
	w = exp(logw :- max(logw))
	w = w / sum(w)
	pr.ess = 1/sum(w:^2)
	// Resampling sistematis-berurut sesuai bobot (campuran parameter conditional)
	cw = runningsum(w)
	uu = sort(runiform(ndraw, 1), 1)
	keep = J(ndraw, 1, .)
	k = 1
	for (i = 1; i <= ndraw; i++) {
		while (k < ndraw & cw[k] < uu[i]) k++
		keep[i] = k
	}
	keep = keep[order(runiform(ndraw, 1), 1)]
	paths = paths[keep, .]
	for (i = 1; i <= npos; i++) {
		if (max(abs(paths[., pos[i]] :- cond[i, 3])) > 1e-6) _error("kondisi tidak terpenuhi")
	}
	S = paths[., (0..(H-1))*K :+ 1]
	if (f.mode == "changes") {
		// akumulasi perubahan log dari spot pada cutoff
		S = S*(lowertriangle(J(H, H, 1)))' :+ 100*ln(f.last_spot)
	}
	pr.paths = paths
	pr.spot = exp(S/100)
	pr.w = w
	pr.ndraw = ndraw
	pr.root_gt1 = sum(w :* (roots :> 1))
	pr.root_gt105 = sum(w :* (roots :> 1.05))
	pr.times = u.times
	pr.cond = cond
	return(pr)
}

// Ringkasan spot per step: (mdate, lower95, lower80, median, upper80, upper95, ess, ess_ratio)
real matrix bv_summary(struct bvpred scalar pr, real rowvector steps)
{
	real matrix Q
	Q = bv_quantile(pr.spot[., steps], (0.025, 0.10, 0.5, 0.90, 0.975))'
	return((pr.times[steps'], Q, J(cols(steps), 1, pr.ess), J(cols(steps), 1, pr.ess/pr.ndraw)))
}

// Median jalur variabel j pada step s (satuan model)
real scalar bv_median_path(struct bvpred scalar pr, real scalar s, real scalar j, real scalar K)
{
	return(bv_quantile(pr.paths[., (s-1)*K + j], 0.5))
}
end

**## 2.4 Backtest dan bootstrap (Rmd: run_backtest, relative_rmse_ci)
mata:
// Untuk tiap origin r: fit sampai r - release_lag, bridge USD/IDR sampai r, forecast h.
// Kolom keluaran: lihat bv_bt_names().
real matrix bv_backtest(struct bvdata scalar d, real scalar start_year, real scalar p,
	real scalar lambda, real scalar inc_ust, real colvector origins, real scalar ndraw,
	real scalar seed_base, real scalar rlag, real rowvector hz, real scalar soc)
{
	struct bvfit scalar f
	struct bvfut scalar u
	struct bvpred scalar pr
	real matrix R, q
	real rowvector steps
	real colvector actual, hist, hcol
	real scalar o, origin, base, sig, r0, i
	R = J(0, 16, .)
	hcol = hz'
	for (o = 1; o <= rows(origins); o++) {
		origin = origins[o]
		f  = bv_fit(d, origin - rlag, start_year, p, lambda, inc_ust, soc)
		u  = bv_future(f, d, origin, max(hz), 0, 0)
		pr = bv_predict(f, u, ndraw, J(0, 3, .), seed_base + origin)
		steps = origin :+ hz :- f.cutoff
		q  = bv_quantile(pr.spot[., steps], (0.025, 0.10, 0.5, 0.90, 0.975))'
		r0 = bv_row(d, origin)
		base = d.usdidr[r0]
		actual = J(cols(hz), 1, .)
		for (i = 1; i <= cols(hz); i++) actual[i] = d.usdidr[bv_row(d, origin + hz[i])]
		if (hasmissing(actual)) _error("aktual target belum tersedia")
		// Interval RW: volatilitas teramati s/d origin, drift nol
		hist = ln(d.usdidr[|1 \ r0|])
		sig  = bv_sd(hist[|2 \ r0|] - hist[|1 \ r0-1|])
		R = R \ (J(cols(hz), 1, origin), origin :+ hcol, hcol, actual, J(cols(hz), 1, base),
			q[., 3], q[., 2], q[., 4], q[., 1], q[., 5],
			base :* exp(invnormal(0.10) :* sqrt(hcol) :* sig),
			base :* exp(invnormal(0.90) :* sqrt(hcol) :* sig),
			base :* exp(invnormal(0.025) :* sqrt(hcol) :* sig),
			base :* exp(invnormal(0.975) :* sqrt(hcol) :* sig),
			J(cols(hz), 1, pr.ess/pr.ndraw), J(cols(hz), 1, pr.root_gt1))
	}
	return(R)
}

string rowvector bv_bt_names()
{
	return(("origin", "target", "horizon", "actual", "rw", "point", "lower80", "upper80",
		"lower95", "upper95", "rw_lower80", "rw_upper80", "rw_lower95", "rw_upper95",
		"ess_ratio", "root_gt1"))
}

// Circular block bootstrap relative RMSE (BVARX / RW); keluaran (lower, upper) 95%
real rowvector bv_boot_rrmse(real colvector actual, real colvector point, real colvector rw,
	real scalar R, real scalar block, real scalar seed)
{
	real colvector bs, starts, ix
	real scalar n, b, nb, i
	rseed(seed)
	n  = rows(actual)
	nb = ceil(n/block)
	bs = J(R, 1, .)
	for (b = 1; b <= R; b++) {
		starts = ceil(runiform(nb, 1)*n)
		ix = J(0, 1, .)
		for (i = 1; i <= nb; i++) ix = ix \ (mod((starts[i] - 1) :+ (0::(block-1)), n) :+ 1)
		ix = ix[|1 \ n|]
		bs[b] = sqrt(mean((actual[ix] - point[ix]):^2) / mean((actual[ix] - rw[ix]):^2))
	}
	return(bv_quantile(bs, (0.025, 0.975))')
}
end

**## 2.5 Skor per horizon (Rmd: score_by_h), program Stata
* Input: dataset backtest di memori (kolom bv_bt_names). Output: satu baris per horizon.
program define bv_score
	gen double _eb2 = (actual - point)^2
	gen double _er2 = (actual - rw)^2
	gen double _aeb = abs(actual - point)
	gen double _aer = abs(actual - rw)
	gen double _lb2 = (100*ln(actual/point))^2
	gen double _lr2 = (100*ln(actual/rw))^2
	gen double _dir = sign(point - rw) == sign(actual - rw)
	gen double _c80 = actual >= lower80 & actual <= upper80
	gen double _c95 = actual >= lower95 & actual <= upper95
	gen double _c80rw = actual >= rw_lower80 & actual <= rw_upper80
	gen double _c95rw = actual >= rw_lower95 & actual <= rw_upper95
	gen double _w80 = upper80 - lower80
	collapse (count) n=origin (mean) _eb2 _er2 mae_bvar=_aeb mae_rw=_aer _lb2 _lr2 ///
		direction_accuracy=_dir coverage80=_c80 coverage95=_c95 coverage80_rw=_c80rw ///
		coverage95_rw=_c95rw width80=_w80 (min) min_ess_ratio=ess_ratio, by(horizon)
	format n %9.0g
	gen double rmse_bvar = sqrt(_eb2)
	gen double rmse_rw = sqrt(_er2)
	gen double relative_rmse = rmse_bvar/rmse_rw
	gen double log_rmse_bvar = sqrt(_lb2)
	gen double log_rmse_rw = sqrt(_lr2)
	drop _eb2 _er2 _lb2 _lr2
	order horizon n rmse_bvar rmse_rw relative_rmse mae_bvar mae_rw log_rmse_bvar log_rmse_rw ///
		direction_accuracy coverage80 coverage95 coverage80_rw coverage95_rw width80 min_ess_ratio
end

**## 2.6 Run akhir: baseline + skenario (dipakai 06 dan 08)
* Skenario: 1 Baseline, 2 Adverse, 3 Upside, 4 Severe Adverse.
mata:
// Ringkasan jalur semua variabel (median, satuan alami) per step: (scen, mdate, s, tb, flows, res)
// Model changes: cadangan dalam perubahan log (bukan level), jadi kolom res dikosongkan.
real matrix bv_paths_median(struct bvpred scalar pr, real rowvector steps, real scalar sc, string scalar mode)
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
	if (mode == "levels") M[., 6] = exp(M[., 6]/100)
	else M[., 6] = J(rows(M), 1, .)
	return(M)
}

// Kondisi skenario: TB dan flows = median baseline + (dtb, dfl) pada horizon chz
real matrix bv_scen_cond(struct bvpred scalar pb, real scalar origin, real scalar cutoff, real rowvector chz, real scalar dtb, real scalar dfl)
{
	real matrix X
	real scalar i, s
	X = J(0, 3, .)
	for (i = 1; i <= cols(chz); i++) {
		s = origin + chz[i] - cutoff
		X = X \ (s, 2, bv_median_path(pb, s, 2, 4) + dtb)
		X = X \ (s, 3, bv_median_path(pb, s, 3, 4) + dfl/10)
	}
	return(X)
}

// Efek kontemporer DXY (dampak bulan yang sama) per persamaan, satuan asli model:
// +1 unit x_dxy (= +1% DXY pada model changes) -> perubahan y_j. Posterior marginal C_ij
// adalah matrix-t: mean Cn_ij, varians Vn_ii * Sn_jj / (nu - K - 1).
// Keluaran K x 3: (persamaan, mean, sd).
real matrix bv_dxy_effect(struct bvfit scalar f)
{
	real matrix R
	real scalar r, j, sc
	r = 1 + f.K*f.p + 1
	R = J(f.K, 3, .)
	for (j = 1; j <= f.K; j++) {
		sc = f.sy[j]/f.sx[1]
		R[j, 1] = j
		R[j, 2] = f.Cn[r, j]*sc
		R[j, 3] = sqrt(f.Vn[r, r]*f.Sn[j, j]/(f.nu - f.K - 1))*sc
	}
	return(R)
}

// shock = matriks 3 x 3: baris = skenario Adverse, Upside, Severe Adverse; kolom = (pertumbuhan DXY, delta TB USD bn, delta flows Rp tn)
void bv_final_run(real scalar cutoff, real scalar origin, real scalar H, real scalar sy0, real scalar p, real scalar lambda, real scalar inc_ust, real scalar nd, real matrix shock, real rowvector chz, real scalar soc)
{
	external struct bvdata scalar D
	external real matrix FIN_resid, FIN_tab, FIN_diag, FIN_cond, FIN_glob, FIN_vars, FIN_info, FIN_dxy
	struct bvfit scalar f
	struct bvfut scalar ub, u
	struct bvpred scalar pb, ps
	real matrix xc, xs, bridge
	real rowvector fsteps
	real colvector known
	real scalar i, j, r, k

	f = bv_fit(D, cutoff, sy0, p, lambda, inc_ust, soc)
	FIN_resid = D.mdate[f.idx], f.resid
	FIN_info = (f.n, D.mdate[f.idx[1]], f.cutoff, origin)
	FIN_dxy = bv_dxy_effect(f)

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

	// Tabel spot: (scen, mdate, lower95, lower80, median, upper80, upper95, ess, ess_ratio)
	FIN_tab  = (J(cols(fsteps), 1, 1), bv_summary(pb, fsteps))
	FIN_vars = bv_paths_median(pb, fsteps, 1, f.mode)
	FIN_diag = (1, pb.ess, pb.ess/nd, pb.root_gt1, pb.root_gt105)
	xc = J(rows(bridge), 1, 0), bridge
	FIN_glob = ub.times, ub.dxy
	for (k = 1; k <= rows(shock); k++) {
		xs = bv_scen_cond(pb, origin, f.cutoff, chz, shock[k, 2], shock[k, 3])
		u = bv_future(f, D, origin, H, shock[k, 1], 0)
		u.cond = bridge
		ps = bv_predict(f, u, nd, xs, 40001)
		FIN_tab  = FIN_tab \ (J(cols(fsteps), 1, k+1), bv_summary(ps, fsteps))
		FIN_vars = FIN_vars \ bv_paths_median(ps, fsteps, k+1, f.mode)
		FIN_diag = FIN_diag \ (k+1, ps.ess, ps.ess/nd, ps.root_gt1, ps.root_gt105)
		xc = xc \ (J(rows(xs), 1, k+1), xs)
		FIN_glob = FIN_glob, u.dxy
	}
	// Kondisi: (scen, step, mdate, variabel, nilai model); scen 0 = bridge (dipakai semua skenario)
	FIN_cond = xc[., (1..2)], ub.times[xc[., 2]], xc[., (3..4)]
}
end

* ---------------------------------------------------------------- 03_validation.do
**# 3. VALIDATION: PILIH START YEAR, LAG, LAMBDA (BVARX changes)
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
mata: D = bv_load("$model_mode")

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
				$n_val, 10000, $release_lag, hz, 0)
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

di as res "Spesifikasi terkunci: start=$best_start  p=$best_p  lambda=$best_lambda  (model $model_mode)"
if $best_start != 2014 di as txt "Catatan: 2014 tidak terpilih; laporkan apa adanya (jangan pindahkan test)."

* ---------------------------------------------------------------- 04_test.do
**# 4. TEST TERKUNCI: BVARX (changes) VS RANDOM WALK
* Rmd: chunk test-terkunci, bootstrap-error, plot-error-test.
* Origin Jan 2024 s/d (bulan lengkap terakhir - 6). Spesifikasi dari 03, tidak dipilih ulang.
* Menulis: intermediate/test_forecasts.dta, test_scores.dta, test_bootstrap.dta
* Output:  tables/T3_test_forecasts, T4_test_scores, T5_test_bootstrap;
*          figures/4_test_h1.png, 4_test_h3.png, 4_test_h6.png, 4_test_rmse.png

local hmax : word count $horizons
local hmax : word `hmax' of $horizons
global test_to = $latest_complete - `hmax'
assert $test_from > $val_to + `hmax'
mata: hz = strtoreal(tokens(st_global("horizons")))

use "$data\database.dta", clear
mata: D = bv_load("$model_mode")
mata: R = bv_backtest(D, $best_start, $best_p, $best_lambda, $include_ust, ///
	($test_from::$test_to), $n_test, 20000, $release_lag, hz, 0)
mata: bv_tostata(R, bv_bt_names())
format origin target %tm
save "$data\test_forecasts.dta", replace
bv_out tab "T3_test_forecasts"
qui levelsof origin
di "Origin test: " %tm $test_from " sampai " %tm $test_to "; jumlah origin per horizon: `r(r)'"

**## 4.1 Skor per horizon
bv_score
format rmse* mae* log_rmse* width80 %9.1f
format relative_rmse direction_accuracy coverage* min_ess_ratio %6.3f
list, noobs
save "$data\test_scores.dta", replace
bv_out tab "T4_test_scores"

**## 4.2 Circular block bootstrap relative RMSE (blok 3/6/12, R = 1000)
* Interval meliputi 1 -> belum ada bukti kuat mengungguli random walk.
tempname pb
postfile `pb' horizon block lower upper using "$data\test_bootstrap.dta", replace
foreach h of global horizons {
	use "$data\test_forecasts.dta", clear
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
merge m:1 horizon using "$data\test_scores.dta", keepusing(relative_rmse) nogen
gen byte covers_one = lower <= 1 & upper >= 1
order horizon block relative_rmse lower upper covers_one
format relative_rmse lower upper %6.3f
list, noobs clean
save "$data\test_bootstrap.dta", replace
bv_out tab "T5_test_bootstrap"

**## 4.3 Grafik aktual vs BVARX vs RW per horizon
foreach h of global horizons {
	use "$data\test_forecasts.dta", clear
	keep if horizon == `h'
	twoway (rarea lower80 upper80 target, color("24 90 141%15") lwidth(none)) ///
		(line actual target, lcolor(black) lwidth(medthick)) ///
		(line point target, lcolor("24 90 141") lwidth(medthick)) ///
		(line rw target, lcolor("164 87 23") lpattern(dash)), ///
		title("Test: horizon `h' bulan (BVARX $model_mode)", size(medium)) xtitle("Bulan target") ytitle("IDR per USD") ///
		legend(order(2 "Aktual" 3 "BVARX median" 4 "Random walk" 1 "Band 80% BVARX") rows(1) size(small) position(6)) ///
		xlabel(#8, format(%tmMon_CCYY) labsize(small) angle(30)) graphregion(color(white)) name(test_h`h', replace)
	graph save "$gph\4_test_h`h'.gph", replace
	graph export "$fig\4_test_h`h'.png", replace width(1800)
}

use "$data\test_scores.dta", clear
graph bar rmse_bvar rmse_rw, over(horizon, relabel(1 "h=1" 2 "h=3" 3 "h=6")) ///
	bar(1, color("24 90 141")) bar(2, color("164 87 23")) ///
	legend(order(1 "BVARX" 2 "Random walk") rows(1) position(6)) ytitle("RMSE (IDR per USD)") ///
	title("Test 2024-2026: RMSE BVARX $model_mode vs random walk", size(medium)) blabel(bar, format(%9.0f) size(vsmall)) ///
	graphregion(color(white)) name(test_rmse, replace)
graph save "$gph\4_test_rmse.gph", replace
graph export "$fig\4_test_rmse.png", replace width(1800)

* ---------------------------------------------------------------- 06_final_scenarios.do
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

* ---------------------------------------------------------------- 07_export.do
**# 7. EKSPOR RINGKASAN, SETTINGS, DAN NARASI HASIL
* Rmd: chunk narasi-hasil, ekspor-audit.
* Output: tables/S0_settings, A0_database_imported; output/narasi_hasil.txt
*         (semua tabel juga ada sebagai sheet di output/rupiah_bvarx_results.xlsx)

**## 7.1 Settings penelitian (reproduksibilitas)
clear
local items profile include_ust seed n_val n_test n_final horizons release_lag ///
	grid_start grid_p grid_lambda best_start best_p best_lambda H_final model_mode seas_harm cond_horizons ///
	dxy_shock tb_shock flows_shock dxy_severe tb_severe flows_severe
local n : word count `items'
set obs `=`n'+6'
gen str24 setting = ""
gen str60 value = ""
local i 0
foreach s of local items {
	local ++i
	replace setting = "`s'" in `i'
	replace value = "${`s'}" in `i'
}
local ++i
replace setting = "validation_origins" in `i'
replace value = "`: di %tm $val_from' - `: di %tm $val_to'" in `i'
local ++i
replace setting = "test_origins" in `i'
replace value = "`: di %tm $test_from' - `: di %tm $test_to'" in `i'
local ++i
replace setting = "latest_complete" in `i'
replace value = "`: di %tm $latest_complete'" in `i'
local ++i
replace setting = "final_origin" in `i'
replace value = "`: di %tm $final_origin'" in `i'
local ++i
replace setting = "stata_version" in `i'
replace value = "`c(stata_version)' `c(edition_real)'" in `i'
local ++i
replace setting = "run_date" in `i'
replace value = "`c(current_date)' `c(current_time)'" in `i'
list, noobs clean
bv_out tab "S0_settings"

**## 7.2 Database yang diimpor
use "$data\database.dta", clear
drop y_* dy_* x_* dx_* sin12 cos12 date
bv_out tab "A0_database_imported"

**## 7.3 Narasi hasil (terisi otomatis)
use "$data\test_scores.dta", clear
tempname fh
file open `fh' using "$results\narasi_hasil.txt", write replace text
file write `fh' "NARASI HASIL (draft otomatis, profile = $profile)" _n _n
file write `fh' "Spesifikasi terpilih dalam grid menggunakan awal sampel $best_start, lag $best_p, dan lambda " %4.2f ($best_lambda) " (model $model_mode). "
file write `fh' "Pemilihannya menggunakan validation, sedangkan hasil berikut berasal dari test yang terpisah." _n _n
forval i = 1/`=_N' {
	file write `fh' "Pada horizon " %1.0f (horizon[`i']) " bulan, relative RMSE adalah " %5.3f (relative_rmse[`i'])
	file write `fh' ", dengan RMSE BVARX " %7.1f (rmse_bvar[`i']) " dan RW " %7.1f (rmse_rw[`i']) " rupiah per USD. "
	if relative_rmse[`i'] < 1 file write `fh' "BVARX mempunyai error lebih kecil secara deskriptif pada horizon ini. "
	else file write `fh' "Random walk mempunyai error lebih kecil secara deskriptif pada horizon ini. "
	file write `fh' "Coverage 80%/95%: " %4.2f (coverage80[`i']) "/" %4.2f (coverage95[`i']) ". "
	file write `fh' "Temuan ini belum menyatakan keunggulan signifikan dan tetap bergantung pada information set serta vintage data." _n _n
}
use "$data\test_bootstrap.dta", clear
keep if block == 6
forval i = 1/`=_N' {
	file write `fh' "Bootstrap (blok 6) h=" %1.0f (horizon[`i']) ": interval 95% relative RMSE " %5.3f (lower[`i']) "-" %5.3f (upper[`i'])
	if covers_one[`i'] file write `fh' " (meliputi 1: belum ada bukti kuat mengungguli RW)." _n
	else file write `fh' " (tidak meliputi 1)." _n
}
file write `fh' _n
use "$data\scenario_spot.dta", clear
keep if mdate == $final_origin + $H_final
forval i = 1/`=_N' {
	local sc : label scen `=scenario[`i']'
	file write `fh' "Skenario `sc': median USD/IDR pada `: di %tmMon_CCYY $final_origin + $H_final' adalah " %7.0f (median[`i'])
	file write `fh' ", dengan rentang predictive 80% " %7.0f (lower80[`i']) "-" %7.0f (upper80[`i']) "." _n
}
file write `fh' _n "Bersyarat pada jalur DXY dan pembatasan observabel yang dijelaskan. Skenario adalah proyeksi bersama model, bukan estimasi efek kausal tunggal." _n
file close `fh'
type "$results\narasi_hasil.txt"

* ---------------------------------------------------------------- 08_forecast_compare.do
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

timer off 1
timer list 1
di "Selesai: `c(current_date)' `c(current_time)'"
log close main
