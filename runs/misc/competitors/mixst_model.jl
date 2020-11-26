import Pkg; Pkg.activate("../../../")

using CytofDensityEstimation; const cde = CytofDensityEstimation
import CytofDensityEstimation: Util.SkewT

using Turing
using Distributions
using BSON
using StatsPlots
using StatsFuns
import Random
import LinearAlgebra

nunique(x) = length(unique(x))

make_priors(K) = (a_tau=0.5, b_tau=1, a_omega=2.5, m_mu=0, s_mu=3,
                  m_psi=-1, s_psi=0.5, m_nu=2, s_nu=0.5, a_eta=fill(1/K, K))

function make_aux(y)
  v = one.(y)
  zeta = rand.(truncated.(Normal.(0, 1 ./ sqrt.(v)), 0, Inf))
  return (v=v, zeta=zeta)
end

@model function MixST(y, K, v, zeta; priors=make_priors(K))
  N = length(y)

  eta ~ Dirichlet(K, 1/K)
  lambda ~ filldist(Categorical(eta), N)

  mu ~ filldist(Normal(priors[:m_mu], priors[:s_mu]), K)
  psi ~ filldist(Normal(priors[:m_psi], priors[:s_psi]), K)

  tau ~ Gamma(priors[:a_tau], priors[:b_tau])
  omega ~ arraydist(InverseGamma.(fill(priors[:a_omega], K), tau))

  nu ~ filldist(LogNormal(priors[:m_nu], priors[:s_nu]), K)

  # v .~ Gamma.(nu[lambda] / 2, 2 ./ nu[lambda])
  # zeta .~ truncate.(Normal.(0, sqrt.(1 ./ v)), 0, Inf)

  for n in 1:N
    k = lambda[n]
    y[n] ~ Normal(mu[k] + psi[k] * zeta[n], sqrt(omega[k] ./ v[n]))
  end
end

function make_cond(y, K, v, zeta; priors=make_priors(K), skew=true, tdist=true)
  N = length(y)

  function update_v!(c)
    if tdist
      nu = c.nu[c.lambda]
      omega = c.omega[c.lambda]
      psi = c.psi[c.lambda]
      mu = c.mu[c.lambda]

      shape = nu/2 .+ 1
      rate = (nu + zeta .^ 2 + ((y - mu - psi .* zeta) .^ 2) ./ omega) / 2
    
      for n in eachindex(v)
        v[n] = rand(Gamma(shape[n], 1/rate[n]))
      end
    else
      v .= 1
    end
  end

  function update_zeta!(c)
    if skew
      psi = c.psi[c.lambda]
      omega = c.omega[c.lambda]
      mu = c.mu[c.lambda]

      vnew = 1 ./ (v + (psi .^ 2) .* v ./ omega)
      mnew = vnew .* v .* psi .* (y - mu) ./ omega

      for n in eachindex(zeta)
        zeta[n] = rand(truncated(Normal(mnew[n], sqrt(vnew[n])), 0, Inf))
      end
    else
      zeta .= 0
    end
  end

  function cond_eta(c)
    anew = priors[:a_eta] .+ 0
    for n in eachindex(c.lambda)
      anew[c.lambda[n]] += 1
    end

    return Dirichlet(anew)
  end

  function cond_tau(c)
    new_shape = priors[:a_tau] + K * priors[:a_omega]
    new_rate = priors[:b_tau] + sum(1 ./ c.omega)
    return Gamma(new_shape, 1 / new_rate)
  end

  function cond_lambda(c)
    logeta = log.(c.eta)
    lambda_prob = [let
                     loc = c.mu + c.psi * zeta[n]
                     scale = sqrt.(c.omega) / sqrt(v[n])

                     logmix = normlogpdf.(loc, scale, y[n]) + logeta
                     tdist && (logmix .+= gammalogpdf.(c.nu / 2, 2 ./ c.nu, v[n]))
                     logmix .-= logsumexp(logmix)
                     exp.(logmix)
                   end for n in eachindex(y)]
    return arraydist(Categorical.(lambda_prob))
  end

  function cond_mu(c)
    m_mu, s_mu = priors[:m_mu], priors[:s_mu]

    vkernels = zero.(c.mu)
    mkernels = zero.(c.mu)

    for n in eachindex(y)
      k = c.lambda[n]
      vkernels[k] += v[n]
      mkernels[k] += (y[n] - c.psi[k] * zeta[n]) * v[n]
    end

    vnew = 1 ./ (s_mu^-2 .+ vkernels ./ c.omega)
    mnew = vnew .* (m_mu/(s_mu^2) .+ mkernels ./ c.omega)
    
    return arraydist(Normal.(mnew, sqrt.(vnew)))
  end

  function cond_omega(c)
    a, b = priors[:a_omega], c.tau
    akernel = zero.(c.omega)
    bkernel = zero.(c.omega)

    for n in eachindex(y)
      k = c.lambda[n]
      akernel[k] += 1
      bkernel[k] += v[n] * (y[n] - c.mu[k] - c.psi[k] * zeta[n]) ^ 2
    end

    anew = a .+ akernel / 2
    bnew = b .+ bkernel / 2

    return arraydist(InverseGamma.(anew, bnew))
  end

  function cond_psi(c)
    if skew
      m, s = priors[:m_psi], priors[:s_psi]
      vkernel = zero.(c.psi)
      mkernel = zero.(c.psi)

      # Update kernels
      for n in eachindex(v)
        k = c.lambda[n]
        vkernel[k] += zeta[n]^2 * v[n] / c.omega[k]
        mkernel[k] += zeta[n] * (y[n] - c.mu[k]) * v[n] / c.omega[k]
      end

      vnew = 1 ./ (s^-2 .+ vkernel)
      mnew = vnew .* (m/s^2 .+ mkernel)

      return arraydist(Normal.(mnew, sqrt.(vnew)))
    else
      return filldist(Normal(0, 0), K)
    end
  end

  function update_vzeta!(c)
    update_v!(c)
    update_zeta!(c)
  end

  return (eta=cond_eta, lambda=cond_lambda, tau=cond_tau, mu=cond_mu,
          omega=cond_omega, psi=cond_psi, update_vzeta=update_vzeta!)
end

function make_sampler(y, K, v, zeta; skew=true, tdist=true)
  cond = make_cond(y, K, v, zeta, skew=skew, tdist=tdist)
  nu_sampler = MH(LinearAlgebra.I(K) * 1e-2, :nu)
  Gibbs(GibbsConditional(:lambda, function(c)
                         out = cond[:lambda](c); cond[:update_vzeta](c); out; end),
        GibbsConditional(:eta, cond[:eta]),
        GibbsConditional(:mu, cond[:mu]),
        GibbsConditional(:tau, cond[:tau]),
        GibbsConditional(:omega, cond[:omega]),
        GibbsConditional(:psi, cond[:psi]),
        nu_sampler,
        # repeat some updates for efficiency.
        GibbsConditional(:tau, function(c) cond[:update_vzeta](c); cond[:tau](c); end),
        GibbsConditional(:omega, cond[:omega]),
        GibbsConditional(:psi, cond[:psi]),
        nu_sampler)
end

nclusters(chain) = nunique.(eachrow(group(chain, :lambda).value.data[:,:,1]))