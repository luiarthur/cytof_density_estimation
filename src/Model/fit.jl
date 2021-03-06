# TODO:
# - [ ] add documentation.

default_monitors() = [[:p, :beta, :gammaC, :gammaT, :etaC, :etaT, :mu, :nu,
                       :omega, :psi, :tau, :sigma, :phi]]

complete_monitors() = [default_monitors()[1],
                      [:lambdaC, :lambdaT, :vC, :vT, :zetaC, :zetaT]]

default_flags() = [UpdateBetaWithSkewT(), UpdateLambdaWithSkewT()]

function default_callback_fn(state::State, data::Data, prior::Prior,
                             iter::Int, pbar::MCMC.ProgressBars.ProgressBar)
  ll = round(loglike_latent_var(state, data), digits=3)
  MCMC.ProgressBars.set_postfix(pbar, loglike=ll)
  return Dict(:loglike => ll)
end

"""
- `init::State`: Initial state.
- `data::Data`: Data.
- `prior::Prior`: Priors.
- `tuners::Tuners`: Tuners.
- `nsamps::Vector{Int}`: Number of posterior samples for each monitor. Needs to
   be in descending order. Defaults to `[1000]`.
- `nburn::Int`: Number of burn-in iterations. Defaults to `1000`.
- `thin::Int`: Thinning factor for first monitor. Defaults to `1`.
- `monitors::Vector{Vector{Symbol}}`: Parameters to keep samples of. Defaults
   to `default_monitors()`.
- `fix::Vector{Symbol}`: Parameters to hold constant. Defaults to `Symbol[]`.
- `flags::Vector{Flag}`: Available options include `:update_beta_with_skewt`
   and `:update_lambda_with_skewt`.
   Defaults to `default_flags()`.
- `verbose::Int`: How much info to print. Defaults to 1.
- `callback_fn`: A function with signature `(state::State, data::Data,
   prior::Prior, iter::Int, pbar::ProgressBar)` that returns a dicionary of
   summary statistics. Enables one to add metrics to progress bar.
"""
function fit(init::State, data::Data, prior::Prior, tuners::Tuners;
             nsamps::Vector{Int}=[1000], nburn::Int=1000, thin::Int=1,
             monitors::Vector{Vector{Symbol}}=default_monitors(),
             callback_fn::Function=default_callback_fn,
             fix::Vector{Symbol}=Symbol[],
             rep_beta_flipped::Int=0,
             rep_aux::Int=1, seed=nothing,
             flags::Vector{Flag}=Flag[], verbose::Int=1)

  # Set random seed.
  seed == nothing || Random.seed!(seed)

  # `fix` and `flags` should be unique.
  fix = unique(fix)
  flags = unique(flags)

  # Print settings for sanity check.
  if verbose > 0
    println("seed: ", seed)
    println("flags: ", flags)
    println("rep_beta_flipped: ", rep_beta_flipped)
    println("rep_aux: ", rep_aux)
    println("fix: ", fix)
    println("monitors: ", monitors)
  end

  isfixed(sym::Symbol) = sym in fix

  function update!(state)
    prev_beta = state.beta
    update_state!(state, data, prior, tuners, fix=fix, flags=flags)
    if state.beta != prev_beta
      for _ in 1:rep_beta_flipped
        update_state!(state, data, prior, tuners, flags=flags,
                      fix=[fix; [:p, :beta]])
      end
    else
      for _ in 1:rep_aux
        update_state!(state, data, prior, tuners, flags=flags,
                      fix=[fix; [:p, :beta, :lambda, :gamma, :eta, :mu]])
      end
    end
  end

  function _callback_fn(state::State, iter::Int,
                       pbar::MCMC.ProgressBars.ProgressBar)
    return callback_fn(state, data, prior, iter, pbar)
  end

  chain, laststate, summarystats = MCMC.gibbs(
      init, update!, nsamps=nsamps, nburn=nburn, thin=thin, monitors=monitors,
      callback_fn=_callback_fn)

  return chain, laststate, summarystats
end
