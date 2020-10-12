"""
weighted sampling: takes (unnormalized) log probs and returns index
"""
function wsample_logprob(logProbs::Vector{T}) where {T <: Number}
  log_p_max = maximum(logProbs)
  p = exp.(logProbs .- log_p_max)
  return Distributions.wsample(p)
end


"""
log 1 minus. For example, `log1m(.3) == log(1 - .3) == log1p(-.3) == log(.7)`.
"""
log1m(x::T) where {T <: Number} = log1p(-x)


"""
Convert a vector of indices to a one-hot matrix, given also the number of
categories.
"""
function to_onehot(indvec::Vector{Int}, categories::Int)
  N = length(indvec)
  onehot_matrix = zeros(Int, N, categories)
  for n in 1:N
    onehot_matrix[n, indvec[n]] = 1
  end
  return onehot_matrix
end


"""
log pdf of gaussian mixture model, for a vector of x of size N and (m: mixture
locations, s: mixture scales, w: mixture weights) each vectors of size K
"""
function gmmlogpdf(x, m, s, w; dims)
  return logsumexp(normlogpdf.(m, s, x) .+ log.(w), dims=dims)
end


"""
log pdf of gaussian mixture model, for a scalar x N and (m: mixture locations,
s: mixture scales, w: mixture weights) each vectors of size K
"""
function gmmlogpdf(x::Real, m, s, w)
  return logsumexp(normlogpdf.(m, s, x) .+ log.(w))
end