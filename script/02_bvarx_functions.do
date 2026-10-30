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
