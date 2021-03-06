struct Data{T <: AbstractVector{<:Real}}
  yC::T
  yT::T
  yC_finite::T
  yT_finite::T
  NC::Int
  NT::Int
  NC_finite::Int
  NT_finite::Int
  ZC::Int
  ZT::Int
end


function Data(yC::AbstractVector{<:Real}, yT::AbstractVector{<:Real})
  yC_finite = yC[isfinite.(yC)]
  yT_finite = yT[isfinite.(yT)]
  NC = length(yC)
  NT = length(yT)
  NC_finite = length(yC_finite)
  NT_finite = length(yT_finite)
  ZC = NC - NC_finite
  ZT = NT - NT_finite
  Data(yC, yT, yC_finite, yT_finite, NC, NT, NC_finite, NT_finite, ZC, ZT)
end

const samplenames = ('C', 'T')

ref_yfinite(data::Data, i::Char) = (i == 'C') ? data.yC_finite : data.yT_finite
ref_N(data::Data, i::Char) = (i == 'C') ? data.NC : data.NT
ref_Nfinite(data::Data, i::Char) = (i == 'C') ? data.NC_finite : data.NT_finite
ref_Z(data::Data, i::Char) = (i == 'C') ? data.ZC : data.ZT

function subsample_data(data::Data, nc::Int, nt::Int)
  if nc > 0 && nt >0
    return Data(sample(data.yC, nc, replace=false),
                sample(data.yT, nt, replace=false))
  else
    return data
  end
end
