"""
Computes the parameters of the inverse gamma distribution, given a mean and
standard deviation.
"""
function invgammamoment(m, s)
  v = s ^ 2
  a = (m / s) ^ 2 + 2
  b = m * (a - 1)
  return a, b
end


function generate_sample(; N::Int, gamma::Real, eta::AbstractVector{<:Real},
                         loc::AbstractVector{<:Real},
                         scale::AbstractVector{<:Real},
                         df::AbstractVector{<:Real},
                         skew::AbstractVector{<:Real})
  K = length(eta)
  Ninf= rand(Binomial(N, gamma))
  Nfinite = N - Ninf
  mm = MixtureModel([SkewT(loc[k], scale[k], df[k], skew[k]) for k in 1:K], eta)
  yfinite = rand(mm, Nfinite)
  return [yfinite; fill(-Inf, Ninf)], mm
end


function generate_samples(; NC, NT, gammaC, gammaT, etaC, etaT, 
                          loc, scale, df, skew)
  K = length(loc)
  @assert K == length(etaC) == length(etaT)
  @assert K == length(scale) == length(df) == length(skew)
  yC, mmC = generate_sample(N=NC, gamma=gammaC, eta=etaC, loc=loc, scale=scale,
                            df=df, skew=skew)
  yT, mmT = generate_sample(N=NT, gamma=gammaT, eta=etaT, loc=loc, scale=scale,
                            df=df, skew=skew)
  return (yC=yC, yT=yT, gammaC=gammaC, gammaT=gammaT, etaC=etaC, etaT=etaT,
          loc=loc, scale=scale, df=df, skew=skew, mmC=mmC, mmT=mmT)
end
