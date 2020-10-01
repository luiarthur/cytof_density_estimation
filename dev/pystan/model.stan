// Performance:
// - Map-reduce:
//       https://mc-stan.org/docs/2_22/stan-users-guide/using-map-reduce.html
// - Hierarchical Normal instead of direct t likelihood:
//       https://mc-stan.org/docs/2_22/stan-users-guide/reparameterization-section.html
// - Hurdle model:
//       https://mc-stan.org/docs/2_22/stan-users-guide/zero-inflated-section.html

functions {
  // Counts the number of infinities in array x.
  int count_inf(real[] x) {
    int num_inf = 0;
    for (n in 1:size(x)) {
      if (is_inf(x[n])) num_inf += 1;
    }
    return num_inf;
  }

  // Collect only the finite values in x.
  real[] collect_finite(real[] x) {
    int pos = 0;
    int num_inf = count_inf(x);
    real x_finite[size(x) - num_inf];
    for (n in 1:size(x)) {
      if (!is_inf(x[n])) {  // i.e., if x[n] is finite
         pos += 1;
         x_finite[pos] = x[n];
      }
    }
    return x_finite;
  }

  // nu:positive, loc:real, scale:positive, phi:real
  real skew_t_lpdf(real x, real nu, real loc, real scale, real phi) {
    real z;
    real u;
    real kernel;

    z = (x - loc) / scale;
    u = phi * z * sqrt((nu + 1) / (nu + z*z));
    kernel = student_t_lpdf(z | nu, 0, 1) + student_t_lcdf(u | nu + 1, 0, 1);

    return (kernel + log(2) - log(scale));
  }

  real loglike(real[] y_finite, vector eta,
               vector nu, vector loc, vector scale, vector phi) {
    
    int N_finite = size(y_finite);
    int K = rows(eta);
    vector[N_finite] res;
    vector[K] log_eta = log(eta);
    vector[K] lpdf_mix;

    for (n in 1:N_finite) {
      lpdf_mix[1:K] = log_eta;
      for (k in 1:K) {
        lpdf_mix[k] += skew_t_lpdf(y_finite[n] | nu[k], loc[k], scale[k], phi[k]);
      }
      res[n] = log_sum_exp(lpdf_mix);
    }

    // Vectorized for efficiency:
    // https://mc-stan.org/docs/2_22/stan-users-guide/vectorization.html
    return sum(res);
  }
}

data {
  int<lower=0> N_T;
  int<lower=0> N_C;
  real y_T[N_T];
  real y_C[N_C];
  int<lower=0> K;  // number of mixture components.

  // hyper parameters
  real<lower=0> a_gamma;
  real<lower=0> b_gamma;

  real<lower=0> a_p;
  real<lower=0> b_p;

  vector<lower=0>[K] a_eta;

  real xi_bar;
  real m_phi;
  real<lower=0> d_xi;
  real<lower=0> d_phi;
  real<lower=0> a_sigma;
  real<lower=0> b_sigma;
  real m_nu;
  real<lower=0> s_nu;
}

transformed data {
  int<lower=0, upper=N_C> N_neginf_C = count_inf(y_C);
  int<lower=0, upper=N_C> N_finite_C = N_C - N_neginf_C;
  real y_finite_C[N_finite_C] = collect_finite(y_C);

  int<lower=0, upper=N_T> N_neginf_T = count_inf(y_T);
  int<lower=0, upper=N_T> N_finite_T = N_T - N_neginf_T;
  real y_finite_T[N_finite_T] = collect_finite(y_T);
}

parameters {
  real<lower=0, upper=1> gamma_T;
  real<lower=0, upper=1> gamma_C;

  simplex[K] eta_T;
  simplex[K] eta_C;

  vector[K] xi;  // mixture locations. (Don't care about order.)
  vector[K] phi;  // mixture skewnesses.
  vector<lower=0>[K] sigma_sq;  // mixture scales.
  vector<lower=0>[K] nu;  // mixture degrees of freedoms.

  real<lower=0, upper=1> p;
}

transformed parameters {
  vector<lower=0>[K] sigma = sqrt(sigma_sq);
  real gamma_T_star = p * gamma_T + (1 - p) * gamma_C;
  vector[K] eta_T_star = ((eta_T * p * (1 - gamma_T) + 
                           eta_C * (1 - p) * (1 - gamma_C)) / (1 - gamma_T_star));
}

model {
  p ~ beta(a_p, b_p);  // prob. treatment has effect.

  gamma_T ~ beta(a_gamma, b_gamma);
  gamma_C ~ beta(a_gamma, b_gamma);

  eta_T ~ dirichlet(a_eta);
  eta_C ~ dirichlet(a_eta);

  sigma_sq ~ inv_gamma(a_sigma, b_sigma);
  xi ~ normal(xi_bar, d_xi * sigma);  // g-prior
  phi ~ normal(m_phi, d_phi * sigma);  // g-prior
  nu ~ lognormal(m_nu, s_nu);  // degrees of freedom
  
  N_neginf_C ~ binomial(N_C, gamma_C);
  N_neginf_T ~ binomial(N_T, gamma_T_star);

  target += loglike(y_finite_C, eta_C, nu, xi, sigma, phi);
  target += loglike(y_finite_T, eta_T_star, nu, xi, sigma, phi);
}