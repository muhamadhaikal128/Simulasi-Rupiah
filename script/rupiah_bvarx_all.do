* ============================================================================
* rupiah_bvarx_all.do: SEMUA MODUL (00-07) DALAM SATU FILE, siap copy-paste.
* Cara pakai: buka Do-file Editor (doedit), paste seluruh isi, klik Do (Ctrl+D).
* Jangan paste ke Command window (blok Mata dan /// hanya jalan sebagai do-file).
* File ini digabung dari 00_master.do ... 07_export.do; isi dan urutan sama.
* ============================================================================

**# 0. MASTER: Forecast dan skenario USD/IDR dengan BVARX
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

**## 0.1 Parameter manual (setara blok params di Rmd)
* profile: quick (cek alur) | standard | publication (angka untuk naskah)
global profile "standard"
* 1 = tambahkan UST10Y sebagai eksogen (putuskan di tahap validation)
global include_ust 0
* 1 = jalankan sensitivity spesifikasi changes
global run_sensitivity 1
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
* Skenario ilustratif: titik pembatas (bulan ke-) dan besaran shock
global cond_horizons "3 6"
global dxy_shock 0.02
global tb_shock 1
global flows_shock 10

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
	d.mdate  = st_data(., "mdate")
	d.usdidr = st_data(., "usdidr")
	d.dxy    = st_data(., "dxy")
	d.ust    = st_data(., "x_ust")
	if (mode == "levels") {
		d.Y    = st_data(., ("y_s", "y_tb", "y_flows", "y_res"))
		d.Xall = st_data(., ("x_dxy", "x_ust", "sin12", "cos12"))
	}
	else {
		d.Y    = st_data(., ("dy_s", "y_tb", "y_flows", "dy_res"))
		d.Xall = st_data(., ("dx_dxy", "x_ust", "sin12", "cos12"))
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
struct bvfit scalar bv_fit(struct bvdata scalar d, real scalar cutoff, real scalar start_year,
	real scalar p, real scalar lambda, real scalar inc_ust)
{
	struct bvfit scalar f
	real colvector idx, good, r, yj
	real rowvector own, v0, arvar
	real matrix Y0, X0, Ys, Xs, Z, C0, V0i, E, D, S0, Xr
	real scalar K, i, j, l, T, nu0, last

	K = cols(d.Y)
	f.xc = inc_ust ? (1, 2, 3, 4) : (1, 3, 4)
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

	f.Vn = cholinv(V0i + cross(Z, Z))
	f.Vn = (f.Vn + f.Vn')/2
	f.Cn = f.Vn*(V0i*C0 + cross(Z, Ys))
	E = Ys - Z*f.Cn
	D = f.Cn - C0
	nu0 = K + 2
	S0 = diag(arvar*(nu0 - K - 1))
	f.Sn = S0 + cross(E, E) + D'*V0i*D
	f.Sn = (f.Sn + f.Sn')/2
	f.LV = cholesky(f.Vn)

	last = idx[T]
	f.hist = (d.Y[|last-p+1, 1 \ last, K|] :- f.my) :/ f.sy
	f.nu = nu0 + T
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
	Xall = xd, u.ust, sin(2*pi()*mon/12), cos(2*pi()*mon/12)
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
	real scalar seed_base, real scalar rlag, real rowvector hz)
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
		f  = bv_fit(d, origin - rlag, start_year, p, lambda, inc_ust)
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
	gen double rmse_bvar = sqrt(_eb2)
	gen double rmse_rw = sqrt(_er2)
	gen double relative_rmse = rmse_bvar/rmse_rw
	gen double log_rmse_bvar = sqrt(_lb2)
	gen double log_rmse_rw = sqrt(_lr2)
	drop _eb2 _er2 _lb2 _lr2
	order horizon n rmse_bvar rmse_rw relative_rmse mae_bvar mae_rw log_rmse_bvar log_rmse_rw ///
		direction_accuracy coverage80 coverage95 coverage80_rw coverage95_rw width80 min_ess_ratio
end

* ---------------------------------------------------------------- 03_validation.do
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

* ---------------------------------------------------------------- 04_test.do
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
	($test_from::$test_to), $n_test, 20000, $release_lag, hz)
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
		legend(order(2 "Aktual" 3 "BVARX median" 4 "RW" 1 "Band 80% BVARX") rows(1) size(small)) ///
		xlabel(, format(%tmMon_CCYY)) graphregion(color(white)) name(test_h`h', replace)
	graph save "$gph\4_test_h`h'.gph", replace
	graph export "$fig\4_test_h`h'.png", replace width(1800)
}

use "$data\test_scores_levels.dta", clear
graph bar rmse_bvar rmse_rw, over(horizon, relabel(1 "h=1" 2 "h=3" 3 "h=6")) ///
	bar(1, color("24 90 141")) bar(2, color("164 87 23")) ///
	legend(order(1 "BVARX" 2 "Random walk") rows(1)) ytitle("RMSE (IDR per USD)") ///
	title("Test: RMSE BVARX vs random walk", size(medium)) blabel(bar, format(%9.0f) size(vsmall)) ///
	graphregion(color(white)) name(test_rmse, replace)
graph save "$gph\4_test_rmse.gph", replace
graph export "$fig\4_test_rmse.png", replace width(1800)

* ---------------------------------------------------------------- 05_sensitivity.do
if $run_sensitivity {
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
}

* ---------------------------------------------------------------- 06_final_scenarios.do
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
cap label drop scen
label define scen 0 "bridge" 1 "baseline" 2 "tekanan_input" 3 "dukungan_input"

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
label values scenario scen
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
label values scenario scen
format mdate %tm
format *_median %9.2f
save "$data\scenario_paths_all.dta", replace
bv_out tab "T9_scenario_paths_all"

mata: bv_tostata(FIN_cond, ("scenario", "step", "mdate", "variable", "value_model"))
label values scenario scen
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
label values scenario scen
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
	xtitle("") ytitle("IDR per USD") xlabel(, format(%tmMon_CCYY)) ///
	legend(order(3 "Aktual" 4 "Baseline median" 5 "Input tekanan" 6 "Input dukungan" 2 "Band 80%" 1 "Band 95%") rows(2) size(small)) ///
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
		title("`t'", size(medium)) xtitle("") ytitle("") xlabel(, format(%tmMon_CCYY) labsize(small)) ///
		legend(order(1 "Baseline" 2 "Tekanan" 3 "Dukungan") rows(1) size(small)) ///
		graphregion(color(white)) name(sv`k', replace) nodraw
}
graph combine sv1 sv2 sv3, cols(3) graphregion(color(white)) xsize(12) ysize(4) name(scen_vars, replace)
graph save "$gph\6_scenarios_vars.gph", replace
graph export "$fig\6_scenarios_vars.png", replace width(2400)

* ---------------------------------------------------------------- 07_export.do
**# 7. EKSPOR RINGKASAN, SETTINGS, DAN NARASI HASIL
* Rmd: chunk narasi-hasil, ekspor-audit.
* Output: tables/S0_settings, A0_database_imported; output/narasi_hasil.txt
*         (semua tabel juga ada sebagai sheet di output/rupiah_bvarx_results.xlsx)

**## 7.1 Settings penelitian (reproduksibilitas)
clear
local items profile include_ust run_sensitivity seed n_val n_test n_final horizons release_lag ///
	grid_start grid_p grid_lambda best_start best_p best_lambda H_final cond_horizons ///
	dxy_shock tb_shock flows_shock
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
use "$data\test_scores_levels.dta", clear
tempname fh
file open `fh' using "$results\narasi_hasil.txt", write replace text
file write `fh' "NARASI HASIL (draft otomatis, profile = $profile)" _n _n
file write `fh' "Spesifikasi terpilih dalam grid menggunakan awal sampel $best_start, lag $best_p, dan lambda " %4.2f ($best_lambda) ". "
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


timer off 1
timer list 1
di "Selesai: `c(current_date)' `c(current_time)'"
log close main
