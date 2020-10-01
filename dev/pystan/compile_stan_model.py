import pickle
import pystan

sm = pystan.StanModel("model.stan")

with open('.model.pkl', 'wb') as f:
    pickle.dump(sm, f)