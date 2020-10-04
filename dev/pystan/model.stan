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

  // Collects only the finite values in x.
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

  // Skew-t log pdf.
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

  // Log likelihood for mixture.
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
  int<lower=0> N_T;  // Number of observations in sample T.
  int<lower=0> N_C; // Number of observations in sample C.
  real y_T[N_T];  // Sample T, the log-transformed data with support on entire real line.
  real y_C[N_C];  // Sample C, the log-transformed data with support on entire real line.
  int<lower=0> K;  // number of mixture components.

  // Hyper parameters for priors.
  real<lower=0> a_gamma;
  real<lower=0> b_gamma;
  real<lower=0> a_p;
  real<lower=0> b_p;
  vector<lower=0>[K] a_eta;
  real mu_bar;
  real m_phi;
  real<lower=0> s_mu;
  real<lower=0> s_phi;
  real<lower=0> a_sigma;
  real<lower=0> b_sigma;
  real<lower=0> m_nu;
  real<lower=0> s_nu;
}

transformed data {
  int<lower=0, upper=N_C> N_neginf_C = count_inf(y_C);  // number of -Inf in sample C
  int<lower=0, upper=N_C> N_finite_C = N_C - N_neginf_C;  // number of finite values in samples C
  real y_finite_C[N_finite_C] = collect_finite(y_C);  // only the finite values in sample C

  int<lower=0, upper=N_T> N_neginf_T = count_inf(y_T);  // number of -Inf in sample T
  int<lower=0, upper=N_T> N_finite_T = N_T - N_neginf_T;  // number of finite values in samples T
  real y_finite_T[N_finite_T] = collect_finite(y_T);  // only the finite values in sample T
}

parameters {
  real<lower=0, upper=1> gamma_T;
  real<lower=0, upper=1> gamma_C;

  simplex[K] eta_T;
  simplex[K] eta_C;

  vector[K] mu;  // mixture locations. (Don't care about order.)
  vector[K] phi;  // mixture skewnesses.
  vector<lower=0>[K] sigma_sq;  // mixture scales.
  vector<lower=0>[K] nu;  // mixture degrees of freedoms.

  real<lower=0, upper=1> p;
}

transformed parameters {
  vector<lower=0>[K] sigma = sqrt(sigma_sq);
  real gamma_T_star = p * gamma_T + (1 - p) * gamma_C;
  vector[K] eta_T_star = (p * eta_T * (1 - gamma_T) + 
                          (1 - p) * eta_C * (1 - gamma_C)) / (1 - gamma_T_star);
}

model {
  p ~ beta(a_p, b_p);  // prob. treatment has effect.

  // Probability of zeros.
  gamma_T ~ beta(a_gamma, b_gamma);
  gamma_C ~ beta(a_gamma, b_gamma);

  // Mixture weights.
  eta_T ~ dirichlet(a_eta);
  eta_C ~ dirichlet(a_eta);

  // Mixture parameters.
  mu ~ normal(mu_bar, s_mu);  // locations
  sigma_sq ~ inv_gamma(a_sigma, b_sigma);  // squared scale
  nu ~ lognormal(m_nu, s_nu);  // degrees of freedom
  phi ~ normal(m_phi, s_phi);  // skewness
  
  // This is just a trick.
  N_neginf_C ~ binomial(N_C, gamma_C);
  N_neginf_T ~ binomial(N_T, gamma_T_star);

  // Increment log target density (i.e. log unnormalized joint posterior).
  target += loglike(y_finite_C, eta_C, nu, mu, sigma, phi);
  target += loglike(y_finite_T, eta_T_star, nu, mu, sigma, phi);
}
