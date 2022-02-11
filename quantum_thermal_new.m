clear all;
close all;
clc;

figure;
set(gcf, 'position', [200, 200, 600, 600])

nelx = 150;
nely = 150;
rmin = 1.4;
volfrac0 = 0.5;
volfrac = 1.0;
vol = floor(volfrac0 * nelx * nely);
%% MATERIAL PROPERTIES
k0 = 1; % good thermal conductivity
kmin = 1e-3; % poor thermal conductivity
%% PREPARE FINITE ELEMENT ANALYSIS
KE = [2/3 -1/6 -1/3 -1/6
    -1/6 2/3 -1/6 -1/3
    -1/3 -1/6 2/3 -1/6
    -1/6 -1/3 -1/6 2/3];
nodenrs = reshape(1:(1 + nelx) * (1 + nely), 1 + nely, 1 + nelx);
edofVec = reshape(nodenrs(1:end - 1, 1:end - 1) + 1, nelx * nely, 1);
edofMat = repmat(edofVec, 1, 4) + repmat([0 nely + [1 0] -1], nelx * nely, 1);
iK = reshape(kron(edofMat, ones(4, 1))', 16 * nelx * nely, 1);
jK = reshape(kron(edofMat, ones(1, 4))', 16 * nelx * nely, 1);
% DEFINE LOADS AND SUPPORTS (HALF MBB-BEAM)
F = sparse(1:(nelx + 1) * (nely + 1), 1, 0.01, (nelx + 1) * (nely + 1), 1);
% F = sparse(ceil((nelx+1)*(nely+1)/2), 1, 1, (nelx + 1) * (nely + 1), 1);
U = zeros((nely + 1) * (nelx + 1), 1);
fixeddofs = nely / 2 + 1 - floor(nely / 20):nely / 2 + 1 + floor(nely / 20);
alldofs = 1:(nely + 1) * (nelx + 1);
freedofs = setdiff(alldofs, fixeddofs);
%% PREPARE FILTER
iH = ones(nelx * nely * ((ceil(rmin) - 1) + 1)^2, 1);
jH = ones(size(iH));
sH = zeros(size(iH));
k = 0;

for i1 = 1:nelx

    for j1 = 1:nely
        e1 = (i1 - 1) * nely + j1;

        for i2 = max(i1 - (ceil(rmin) - 1), 1):min(i1 + (ceil(rmin) - 1), nelx)

            for j2 = max(j1 - (ceil(rmin) - 1), 1):min(j1 + (ceil(rmin) - 1), nely)
                e2 = (i2 - 1) * nely + j2;
                k = k + 1;
                iH(k) = e1;
                jH(k) = e2;
                sH(k) = max(0, rmin - sqrt((i1 - i2)^2 + (j1 - j2)^2));
            end

        end

    end

end

H = sparse(iH, jH, sH);
Hs = sum(H, 2);
%% INITIALIZE ITERATION
x = zeros(nely, nelx);
x(1:floor(nely * nelx / 2)) = 1;
loop = 0;

lowPhysics = 0.2;
highPhysics = 0.8;
dPhysics = 0.9;

stage = 1;
totalLoop = 0;
epsilon = 1e-3;

numFeasibleCut = 0;

compliance = [];
volume = [];
%
% stage = 2;
% load('x_thermal');

colormap(gray); imagesc(1 - x); caxis([0 1]); axis equal; axis off; drawnow;

while highPhysics < 0.99
    loop = loop + 1;
    Lower = 0;
    Upper = 1e9;

    lowPhysics = lowPhysics * dPhysics;
    highPhysics = 1 - lowPhysics;

    %     colormap(gray); imagesc(1 - x); caxis([0 1]); axis equal; axis off; drawnow;

    innerLoop = 0;
    exitFlag = 1;
    xOptimal = x;
    xTarget = [];
    ceTarget = [];
    cTarget = [];

    xFeasible = [];
    ceFeasible = [];
    cFeasible = [];

    xPhys = x;
    xPhys(x == 1) = highPhysics;
    xPhys(x == 0) = lowPhysics;
    colormap(gray); imagesc(1 - xPhys); caxis([0 1]); axis equal; axis off; drawnow;

    while (1)
        innerLoop = innerLoop + 1;

        % primal problem
        xPhys = x;
        xPhys(x == 1) = highPhysics;
        xPhys(x == 0) = lowPhysics;
        sK = reshape(KE(:) * (xPhys(:)' * (k0 - kmin)), 16 * nelx * nely, 1);
        K = sparse(iK, jK, sK); K = (K + K') / 2;
        U(freedofs) = K(freedofs, freedofs) \ F(freedofs);
        ce = reshape(sum((U(edofMat) * KE) .* U(edofMat), 2), nely, nelx);
        c = sum(sum((xPhys * k0) .* ce));
        ce(:) = ce .* xPhys;
        ce(:) = H * (ce(:) ./ Hs);
        
        if c < Upper
            xOptimal = x;
            Upper = c;
        end

        % check feasibility
        if norm(U) > 1e9
            numFeasibleCut = numFeasibleCut + 1;
            U(freedofs) = feasibilityCut(K(freedofs, freedofs), F(freedofs), Upper);
            ce = reshape(sum((U(edofMat) * KE) .* U(edofMat), 2), nely, nelx);
            c = sum(sum((Emin + xPhys * (E0 - Emin)) .* ce));

            xFeasible = [xFeasible reshape(x, [], 1)];
            ceFeasible = [ceFeasible; reshape(ce, 1, [])];
            cFeasible = [cFeasible; c];
        else
            xTarget = [xTarget reshape(x, [], 1)];
            ceTarget = [ceTarget; reshape(ce, 1, [])];
            cTarget = [cTarget; c];
            index = [];
%             index = 1:length(cTarget);

                        for i = 1:length(cTarget)
            
                            if (cTarget(i) <= c)
                                index = [index; i];
                            end
            
                        end

        end

        % master problem
        % if stage == 1
        [xResult, cost, exitFlag] = gbdMasterCut(xTarget(:, index), cTarget(index), ceTarget(index, :), xFeasible, cFeasible, ceFeasible, vol);
        %                 [xResult, cost, exitFlag] = gbdMasterCutRelaxed(xTarget(:, index), cTarget(index), ceTarget(index, :), xFeasible, cFeasible, ceFeasible, vol);
        % else
        %     [xResult, cost, exitFlag] = gbdMasterCutQuantum(xTarget(:, index), cTarget(index), ceTarget(index, :), xFeasible, cFeasible, ceFeasible, vol);
        % end

        x = reshape(xResult, size(x, 1), size(x, 2));
        
        x(x > 0.5) = 1;
        x(x <= 0.5) = 0;

        xPhys = x;
        xPhys(x == 1) = highPhysics;
        xPhys(x == 0) = lowPhysics;
        colormap(gray); imagesc(1 - xPhys); caxis([0 1]); axis equal; axis off; drawnow;

        if cost > Upper || (Upper - cost) / Upper < epsilon
            compliance = [compliance; Upper];
            volume = [volume; vol];

            fprintf(' It.:%5i Obj.:%11.4f Vol.:%7.3f, Gap.:%5.3f%%\n', loop, Upper, sum(x(:)), (Upper - cost) / Upper * 100);

            break;
        end

        compliance = [compliance; Upper];
        volume = [volume; vol];

        fprintf(' It.:%5i Obj.:%11.4f Vol.:%7.3f, Gap.:%5.3f%%\n', loop, Upper, sum(x(:)), (Upper - cost) / Upper * 100);

    end

    x = xOptimal;

    totalLoop = totalLoop + innerLoop;

    if stage == 1 && volfrac <= volfrac0
        stage = 2;
    elseif stage == 2
        stage = 3;
    end

end

disp(numFeasibleCut)
disp(Upper)
disp(totalLoop)

figure;
hold on;
yyaxis left
plot(compliance, 'b.-');
yyaxis right
plot(volume ./ (nelx * nely), 'r.-');

% save('x_thermal', 'x');

function [x, objFunc, exitFlag] = gbdMasterCut(y, obj, weight, yFeasible, objFeasible, weightFeasible, vol)
    n = size(y, 2);
    m = size(yFeasible, 2);
    l = size(y, 1);
    f = zeros(1, l + 1);
    f(1) = 1;
    lb = zeros(1, l + 1);
    lb(1) = -inf;
    ub = ones(1, l + 1);
    ub(1) = inf;

    A = zeros(n + m + 1, l + 1);
    b = zeros(n + m + 1, 1);

    for i = 1:n
        A(i, 1) = -1;
        A(i, 2:end) = -weight(i, :);
        b(i) = -obj(i) - weight(i, :) * y(:, i);
    end

    for i = 1:m
        A(i + n, 2:end) = weightFeasible(i, :);
        b(i + n) = objFeasible(i);
    end

    intcon = 1:l;
    intcon = intcon + 1;

    A(end, :) = ones(1, l + 1);
    A(end, 1) = 0;
    b(end) = vol;

    %     Aeq = ones(1, l + 1);
    %     Aeq(1, 1) = 0;
    %     beq = vol;

    %     options = optimoptions('intlinprog','IntegerPreprocess','none');
    [x, objFunc, exitFlag, ~] = intlinprog(f, intcon, A, b, [], [], lb, ub);

    if exitFlag ~= 1
        x = y;
    else
        x = x(2:end);
    end

end

function [x, objFunc, exitFlag] = gbdMasterCutRelaxed(y, obj, weight, yFeasible, objFeasible, weightFeasible, vol)
    n = size(y, 2);
    m = size(yFeasible, 2);
    l = size(y, 1);

    xOptimal = y(:, 1);
    objOptimal = inf;

    for i = 1:n
        f = -weight(i, :);
        lb = zeros(1, l);
        ub = ones(1, l);

        intcon = 1:l;

        A = ones(1, l);
        b = vol;

        %     options = optimoptions('intlinprog','IntegerPreprocess','none');
        [x, ~, exitFlag, ~] = intlinprog(f, intcon, [], [], A, b, lb, ub);

        if exitFlag == 1
            objFunc = -inf;

            for j = 1:n
                objSelect = obj(j) - weight(j, :) * (x - y(:, j));

                if objSelect > objFunc
                    objFunc = objSelect;
                end

            end

            if objFunc < objOptimal
                xOptimal = x;
                objOptimal = objFunc;
            end

        end

    end

    x = xOptimal;
    objFunc = objOptimal;
end

function [x, objFunc, exitFlag] = gbdMasterCutQuantum(y, obj, weight, yFeasible, objFeasible, weightFeasible, vol)
    exitFlag = 1;

    % reduce the amount of variables
    weightSparse = sparse(weight);
    [~, nonzero] = find(weightSparse);
    nonzero = unique(sort(nonzero));

    weightReduced = weight(:, nonzero);
    objReduced = obj;
    yReduced = y(nonzero, :);

    save('quantum.mat', 'weightReduced', 'objReduced', 'yReduced', 'vol');
    system('python3 cut_solver.py');
    load('result.mat');

    x = zeros(size(y, 1), 1);
    x(nonzero) = res;

    [xCompare, objFuncCompare, ~] = gbdMasterCut(y, obj, weight, yFeasible, objFeasible, weightFeasible, vol);
    fprintf("norm difference: %f\n", norm(x - xCompare, 1));
    disp([objFunc, objFuncCompare]);
end

function lambda = feasibilityCut(K, f, UB)
    n = length(f);

    A = -f';
    b = -UB;

    lambda = fmincon(@(x)(0), zeros(n, 1), A, b, [], [], [], [], @con);

    function [c, ceq] = con(x)
        c = x' * K * x - f' * x;
        ceq = [];
    end

end
