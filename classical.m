clear all;
close all;
clc;

figure;
set(gcf,'position',[200,200,600,200])

nelx = 120;
nely = 40;
rmin = 2;
volfrac0 = 0.5;
volfrac = 1.0;
%% MATERIAL PROPERTIES
E0 = 1;
Emin = 1e-9;
nu = 0.3;
%% PREPARE FINITE ELEMENT ANALYSIS
A11 = [12  3 -6 -3;  3 12  3  0; -6  3 12 -3; -3  0 -3 12];
A12 = [-6 -3  0  3; -3 -6 -3 -6;  0 -3 -6  3;  3 -6  3 -6];
B11 = [-4  3 -2  9;  3 -4 -9  4; -2 -9 -4 -3;  9  4 -3 -4];
B12 = [ 2 -3  4 -9; -3  2  9 -2;  4  9  2  3; -9 -2  3  2];
KE = 1/(1-nu^2)/24*([A11 A12;A12' A11]+nu*[B11 B12;B12' B11]);
nodenrs = reshape(1:(1+nelx)*(1+nely),1+nely,1+nelx);
edofVec = reshape(2*nodenrs(1:end-1,1:end-1)+1,nelx*nely,1);
edofMat = repmat(edofVec,1,8)+repmat([0 1 2*nely+[2 3 0 1] -2 -1],nelx*nely,1);
iK = reshape(kron(edofMat,ones(8,1))',64*nelx*nely,1);
jK = reshape(kron(edofMat,ones(1,8))',64*nelx*nely,1);
% DEFINE LOADS AND SUPPORTS (HALF MBB-BEAM)
F = sparse(2,1,-1,2*(nely+1)*(nelx+1),1);
U = zeros(2*(nely+1)*(nelx+1),1);
fixeddofs = union([1:2:2*(nely+1)],[2*(nelx+1)*(nely+1)]);
alldofs = [1:2*(nely+1)*(nelx+1)];
freedofs = setdiff(alldofs,fixeddofs);
%% PREPARE FILTER
iH = ones(nelx*nely*(2*(ceil(rmin)-1)+1)^2,1);
jH = ones(size(iH));
sH = zeros(size(iH));
k = 0;
for i1 = 1:nelx
  for j1 = 1:nely
    e1 = (i1-1)*nely+j1;
    for i2 = max(i1-(ceil(rmin)-1),1):min(i1+(ceil(rmin)-1),nelx)
      for j2 = max(j1-(ceil(rmin)-1),1):min(j1+(ceil(rmin)-1),nely)
        e2 = (i2-1)*nely+j2;
        k = k+1;
        iH(k) = e1;
        jH(k) = e2;
        sH(k) = max(0,rmin-sqrt((i1-i2)^2+(j1-j2)^2));
      end
    end
  end
end
H = sparse(iH,jH,sH);
Hs = sum(H,2);
%% INITIALIZE ITERATION
x = ones(nely,nelx);
loop = 0;

dvol = 200;
stage = 1;
totalLoop = 0;
epsilon = 1e-2;
while stage < 3
    loop = loop+1;
    Lower = 0;
    Upper = 1e9;
    
    if stage == 1
        vol = floor(volfrac * nelx * nely);
        vol = vol - dvol;
        volfrac = vol / (nelx * nely);
    end
    
    if stage == 2
        epsilon = 1e-5;
    end

%     vol = 1350;
    
%     load('x.mat');
%     x(xPhys>0.5) = 1;
%     x(xPhys<0.5) = 0;
    
%     subplot(2, 1, 1);
    colormap(gray); imagesc(1-x); caxis([0 1]); axis equal; axis off; drawnow;
    
    innerLoop = 0;
    exitFlag = 1;
    xOptimal = x;
    xTarget = [];
    ceTarget = [];
    cTarget = [];
    
    xFeasible = [];
    ceFeasible = [];
    cFeasible = [];
    
    % prepare the intitial solution
    xPhys = x;
    sK = reshape(KE(:)*(Emin+xPhys(:)'*(E0-Emin)),64*nelx*nely,1);
    K = sparse(iK,jK,sK); K = (K+K')/2;
    U(freedofs) = K(freedofs,freedofs)\F(freedofs);
    ce = reshape(sum((U(edofMat)*KE).*U(edofMat),2),nely,nelx);
    c = sum(sum((Emin+xPhys*(E0-Emin)).*ce));
    ce(:) = ce.*x;
    ce(:) = H*(ce(:)./Hs);
    
    [xResult, cost, exitFlag] = gbdMasterCut(reshape(x, [], 1), c, reshape(ce, 1, []), [], [], [], vol);
    
    x = reshape(xResult, size(x, 1), size(x, 2));
    xOptimal = x;
    
%     subplot(2, 1, 2);
    colormap(gray); imagesc(1-x); caxis([0 1]); axis equal; axis off; drawnow;
    
    while (1)
        innerLoop = innerLoop+1;
        disp((Upper-Lower)/Upper);
        
        % primal problem
        xPhys = x;
        sK = reshape(KE(:)*(Emin+xPhys(:)'*(E0-Emin)),64*nelx*nely,1);
        K = sparse(iK,jK,sK); K = (K+K')/2;
        U(freedofs) = K(freedofs,freedofs)\F(freedofs);
        ce = reshape(sum((U(edofMat)*KE).*U(edofMat),2),nely,nelx);
        c = sum(sum((Emin+xPhys*(E0-Emin)).*ce));
        ce(:) = ce.*x;
        ce(:) = H*(ce(:)./Hs);
        if c < Upper
            xOptimal = x;
            Upper = c;
        end
        
        % check feasibility
        if norm(U) > 1e9
            U(freedofs) = feasibilityCut(K(freedofs,freedofs), F(freedofs), Upper);
            ce = reshape(sum((U(edofMat)*KE).*U(edofMat),2),nely,nelx);
            c = sum(sum((Emin+xPhys*(E0-Emin)).*ce));
            
            xFeasible = [xFeasible reshape(x, [], 1)];
            ceFeasible = [ceFeasible; reshape(ce, 1, [])];
            cFeasible = [cFeasible; c];
        else
            xTarget = [xTarget reshape(x, [], 1)];
            ceTarget = [ceTarget; reshape(ce, 1, [])];
            cTarget = [cTarget; c];
            index = [];
            for i = 1:length(cTarget)
                if (cTarget(i) <= c)
                    index = [index; i];
                end
            end
        end
        
        % master problem
        [xResult, cost, exitFlag] = gbdMasterCut(xTarget(:, index), cTarget(index), ceTarget(index, :), xFeasible, cFeasible, ceFeasible, vol);
        
        if exitFlag == 1
            x = reshape(xResult, size(x, 1), size(x, 2));
        else
            break;
        end
        
%         subplot(2, 1, 1);
        colormap(gray); imagesc(1-xOptimal); caxis([0 1]); axis equal; axis off; drawnow;
%         subplot(2, 1, 2);
%         colormap(gray); imagesc(1-x); caxis([0 1]); axis equal; axis off; drawnow;
        
        if cost > Upper || (Upper - cost) / Upper < epsilon
            break;
        end
        
        fprintf(' It.:%5i Obj.:%11.4f Vol.:%7.3f, Gap.:%5.3f%%\n',loop,Upper,sum(x(:)), (Upper - cost) / Upper*100);
    end
    x = xOptimal;
    
    totalLoop = totalLoop + innerLoop;
    
    if stage == 1 && volfrac <= volfrac0
        stage = 2;
    elseif stage == 2
        stage = 3;
    end
end

function [x, objFunc, exitFlag] = gbdMasterCut(y, obj, weight, yFeasible, objFeasible, weightFeasible, vol)
    n = size(y, 2);
    m = size(yFeasible, 2);
    l = size(y, 1);
    f = zeros(1, l+1);
    f(1) = 1;
    lb = zeros(1, l+1);
    lb(1) = -inf;
    ub = ones(1, l+1);
    ub(1) = inf;
    
    A = zeros(n+m, l+1);
    b = zeros(n+m, 1);
    for i = 1:n
        A(i, 1) = -1;
        A(i, 2:end) = -weight(i, :);
        b(i) = -obj(i) - weight(i,:)*y(:, i);
    end
    
    for i = 1:m
        A(i+n, 2:end) = weightFeasible(i, :);
        b(i+n) = objFeasible(i);
    end
    
    intcon = 1:l;
    intcon = intcon + 1;
    
    Aeq = ones(1, l+1);
    Aeq(1, 1) = 0;
    beq = vol;
    
%     options = optimoptions('intlinprog','IntegerPreprocess','none');
    [x, objFunc, exitFlag, ~] = intlinprog(f, intcon, A, b, Aeq, beq, lb, ub);
    if exitFlag ~= 1
        x = y;
    else
        x = x(2:end);
    end
end

function lambda = feasibilityCut(K, f, UB)
    n = length(f);
    
    A = -f';
    b = -UB;
    
    lambda = fmincon(@(x)(0), zeros(n, 1), A, b, [], [], [], [], @con);
    
    function [c, ceq] = con(x)
        c = x'*K*x - f'*x;
        ceq = [];
    end
end