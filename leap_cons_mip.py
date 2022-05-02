import matplotlib.pyplot as plt
import numpy as np
import scipy as sio
import pandas as pd

from dwave.system import LeapHybridCQMSampler
from dimod import ConstrainedQuadraticModel, BinaryQuadraticModel, QuadraticModel

import gurobipy as gp
from gurobipy import GRB
import scipy.io as sio


def populate_and_solve(m):
    data_dir = sio.loadmat('cons_mip.mat')
    weight = np.array(data_dir['weight'])
    b = np.array(data_dir['b'])
    Upper = np.max(np.abs(b))

    N = weight.shape[1]
    rhoTuple = m.addVars(N, vtype=GRB.BINARY)

    M = 10
    etaTuple = m.addVars(M+1, vtype=GRB.BINARY)
    eta = Upper*(1 - 1 / (2**M))*etaTuple[0]
    for i in range(1, M+1):
        eta += Upper/(2**i)*etaTuple[i]

    Nc = weight.shape[0]
    alphaTuple = m.addVars(Nc, M+1, vtype=GRB.BINARY)

    objExpr = eta

    A = Upper
    consExpr = 0
    for c in range(Nc):
        subConsExpr = 0
        for i in range(N):
            subConsExpr += -weight[c, i] * rhoTuple[i]
        alpha = Upper*(1 - 1 / (2**M))*alphaTuple[c, 0]
        for i in range(1, M+1):
            alpha += Upper/(2**i)*alphaTuple[c, i]
        subConsExpr = subConsExpr - eta + alpha - b[c]
        consExpr += A * (subConsExpr)**2

    subConsExpr = 0
    for i in range(0, N):
        subConsExpr += rhoTuple[i] / N
    subConsExpr -= data_dir['vol'][0, 0] / N
    consExpr += A * (subConsExpr)**2

    m.setObjective(objExpr + consExpr, GRB.MINIMIZE)
    m.optimize()

    eta = Upper*(1 - 1 / (2**N))*etaTuple[0].X
    for i in range(1, M+1):
        eta += Upper/(2**i)*etaTuple[i].X

    x = np.zeros((N, 1))
    for i in range(0, N):
        x[i] = rhoTuple[i].X

    return x


data_dir = sio.loadmat('cons_mip.mat')
weight = np.array(data_dir['weight'])
b = np.array(data_dir['b'])
Upper = np.max(np.abs(b))

N = weight.shape[1]
Nc = weight.shape[0]
M = 10
A = Upper

totalNum = N + Nc * (M+1)
Q = np.zeros((totalNum, totalNum))
c = np.zeros((totalNum, ))

etaCoefficient = np.zeros((M+1, ))
etaCoefficient[0] = Upper*(1 - 1 / (2**M))
for i in range(1, M+1):
    etaCoefficient[i] = Upper/(2**i)

alphaCoefficient = np.zeros((M+1, Nc))
for i in range(Nc):
    alphaCoefficient[0, i] = Upper*(1 - 1 / (2**M))
    for j in range(1, M+1):
        alphaCoefficient[j, i] = Upper/(2**j)

# objective function
coefficient = np.zeros((totalNum, 1))
for i in range(M+1):
    coefficient[N+i] = etaCoefficient[i]
c = coefficient

objOffset = 0
# cuts
for j in range(Nc):
    coefficient = np.zeros((totalNum, 1))
    for i in range(N):
        coefficient[i] = -weight[j, i]
    for i in range(M+1):
        coefficient[N+i] = -etaCoefficient[i]
    for i in range(M+1):
        coefficient[N+j*(M+1)+i] = alphaCoefficient[i, j]

    c += A * (coefficient**2 - b[j]*coefficient)
    Q += A * coefficient * coefficient.T

    objOffset += A * b[j]**2

# volume constraint
coefficient = coefficient = np.zeros((totalNum, 1))
for i in range(N):
    coefficient[i] = 1.0 / N
vol = data_dir['vol'][0, 0] / N
Q += A * coefficient * coefficient.T
c += A * (coefficient**2 - vol*coefficient)

objOffset += A * vol**2

obj = BinaryQuadraticModel(vartype='BINARY')
# constraint = QuadraticModel()
for i in range(totalNum):
    obj.add_variable(i)
    # constraint.add_variable('BINARY', i)

for i in range(totalNum):
    obj.set_linear(i, c[i])
    # constraint.set_linear(i, 1.0)
    for j in range(i+1, totalNum):
        obj.set_quadratic(i, j, Q[i, j] + Q[j, i])

cqm = ConstrainedQuadraticModel()
cqm.set_objective(obj)
# cqm.add_constraint(constraint, sense="==", rhs=vol)

sampler = LeapHybridCQMSampler(
    token="DEV-7521f7e94cf42f8fb0430b3d0bfbca3b00264a27")

sampleset = sampler.sample_cqm(cqm, label='lin mip')

feasible_sampleset = sampleset.filter(lambda row: row.is_feasible)

if not len(feasible_sampleset):
    raise ValueError("No feasible solution found")

x = np.zeros((totalNum, 1))
best = feasible_sampleset.first
selected_item_indices = [key for key, val in best.sample.items() if val == 1.0]
x[selected_item_indices] = 1
x = x[0:N]

connection_params = {
    # For Compute Server you need at least this
    #       "ComputeServer": "<server name>",
    #       "UserName": "<user name>",
    #       "ServerPassword": "<password>",

    # For Instant cloud you need at least this
    #       "CloudAccessID": "<access id>",
    #       "CloudSecretKey": "<secret>",
}

with gp.Env(params=connection_params) as env:
    with gp.Model(env=env) as model:
        xCompare = populate_and_solve(model)

print(np.linalg.norm(xCompare - x))
print(best.energy+objOffset)

fig = plt.figure()
fig.set_figheight(2)
fig.set_figwidth(6)
plt.imshow(1 - x.reshape(60, 20).T, cmap='gray', vmin=0, vmax=1)
plt.axis("off")
fig.tight_layout()
plt.savefig("leap_cons_mip.eps")
