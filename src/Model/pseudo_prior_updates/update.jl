# TODO: Check.

include("update_beta.jl")

function update_state_via_pseudo_prior!(state::State,
                                        state0::State, state1::State,
                                        data::Data, prior::Prior,
                                        tuners0::Tuners, tuners1::Tuners;
                                        rep_aux::Integer=1,
                                        fix::Vector{Symbol}=Symbol[],
                                        flags::Vector{Flag}=Flag[])
  # Update beta.
  update_beta_via_pseudo_prior!(state, state0, state1, data, prior)


  # State: beta = 0
  update_state!(state0, data, prior, tuners0, fix=[fix; [:p, :beta]],
                flags=flags)
  for _ in 1:rep_aux
    update_state!(state0, data, prior, tuners0, flags=flags,
                  fix=[fix; [:p, :beta, :lambda, :gamma, :eta]])
  end


  # State: beta = 1
  update_state!(state1, data, prior, tuners1, fix=[fix; [:p, :beta]],
                flags=flags)
  for _ in 1:rep_aux
    update_state!(state1, data, prior, tuners1, flags=flags,
                  fix=[fix; [:p, :beta, :lambda, :gamma, :eta]])
  end


  # Update current state.
  state.beta ? assumefields!(state, state1) : assumefields!(state, state0)
end
