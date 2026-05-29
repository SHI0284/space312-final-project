tic;
clc; clear; close all;
format longG;

% SPACE312 Final Project
% GTO-to-GEO-KOMPSAT-2A transfer trajectory optimization
%
% This script is intentionally self-contained. It uses only standard MATLAB
% functions and local functions included at the end of this file.
%
% Main strategy:
%   1) Dense zero-revolution Lambert sweep over transfer duration.
%   2) Coarser multi-revolution Lambert sweep for longer-duration candidates.
%   3) Pareto filtering in [sum dV, transfer time].
%   4) Optional direct-shooting refinement of selected Pareto points.
%   5) Required figures, result table, visibility intervals, and GIF animation.
%
% Units: km, s, km/s, rad unless stated otherwise.

%% User switches
runShootingRefinement = false;    % Set true for optional slow direct-shooting refinement.
runMultiRevLambert = true;        % Adds multi-revolution Lambert candidates.
makeAnimation = true;             % Writes a rendezvous animation GIF in the results folder.
saveFigureFiles = true;           % Writes separate PNG files and leaves figures open as docked tabs.
exportCaseFolders = false;        % Set true only when you want separate case folders.

% Instructor guidance: choose one representative design point after defining
% a mission priority.
% Options: "fast_with_dv_margin", "low_dv", "knee", or "fast".
% Submitted mission priority: complete rendezvous inside a practical
% four-day early-orbit commissioning window, then minimize total Delta V inside
% that window. This treats propellant as the limiting mission resource once the
% transfer remains short enough for realistic operations.
missionPriority = "low_dv";
timeWeight = 0.50;                % Used only for missionPriority = "knee".
deltaVWeight = 0.50;              % Used only for missionPriority = "knee".
deltaVMarginPercent = 3.0;        % Used only for missionPriority = "fast_with_dv_margin".
representativeMinTOFDays = 1.0;   % Representative solution search lower bound.
representativeMaxTOFDays = 4.0;    % Practical representative-design upper bound. Use inf for no upper bound.
multiRevTOFSamples = 400;         % Coarser than the zero-rev sweep to keep runtime reasonable.
maxLambertRevs = 20;              % Maximum complete revolutions to try for Lambert candidates.
terminalPositionToleranceKm = 10; % Candidate must actually arrive within this distance of the target.

resultsDir = fullfile(pwd,'results');
if ~exist(resultsDir,'dir')
    mkdir(resultsDir);
end

%% Given constants and states
mu = 398600.4418;                 % Earth gravitational parameter [km^3/s^2]
Re = 6378.137;                    % Earth equatorial radius [km]
wE = 7.2921150e-5;                % Earth rotation rate [rad/s]
rGEO = (mu/wE^2)^(1/3);           % GEO radius [km]
JD0 = 2461192.5;                  % Julian date at t0
thetaERA0 = deg2rad(249.1551677); % Earth rotation angle at t0 [rad]
lambdaGEO = deg2rad(128.2);       % GEO-KOMPSAT-2A longitude east [rad]
UTC0 = [2026 6 1 0 0 0];

R0 = [-42164.1729; 0.0000; 0.0000];
V0minus = [0.000000; -1.458327; -0.664598];

% Per instructor clarification, the Section 3.2 target state vector is the
% authoritative boundary condition for this project.
RGEO0 = [41244.6079; 12577.3213; 0.0000];
VGEO0 = [-0.917153; 2.934683; 0.000000];

targetRadius0 = norm(RGEO0);
targetSpeed0 = norm(VGEO0);
targetRadialSpeed0 = dot(RGEO0,VGEO0)/targetRadius0;

fprintf('\nSection 3.2 target-state diagnostics:\n');
fprintf('  |RGEO0|          = %.6f km\n',targetRadius0);
fprintf('  nominal rGEO     = %.6f km\n',rGEO);
fprintf('  |VGEO0|          = %.6f km/s\n',targetSpeed0);
fprintf('  radial speed     = %.6e km/s\n',targetRadialSpeed0);
fprintf('  Note: nonzero radial speed / radius mismatch makes the propagated target path non-circular.\n');

% KHU global campus approximation, used for the required visibility plot.
KHU.lat = deg2rad(37.2411);
KHU.lon = deg2rad(127.0802);
KHU.h = 0.08;
KHU.name = 'KHU';

%% Search grid
tofDaysDense = linspace(1,30,20000);
tofSecondsDense = tofDaysDense*86400;
nTOF = numel(tofDaysDense);

targetSweepTimeGrid = [0, tofSecondsDense];
[RtargetSweep,VtargetSweep] = propagateTrajectory(RGEO0,VGEO0,targetSweepTimeGrid,mu);
RtargetSweep = RtargetSweep(:,2:end);
VtargetSweep = VtargetSweep(:,2:end);

records = struct('method',{},'tofDays',{},'tof',{},'direction',{}, ...
    'V1plus',{},'V2minus',{},'dV1',{},'dV2',{},'dVtotal',{}, ...
    'Rtarget',{},'Vtarget',{},'posErrFinal',{}, ...
    'nRev',{},'aPhase',{},'rpPhase',{});

fprintf('Commence GTO-to-GEO-KOMPSAT-2A search...\n');
fprintf('Dense Lambert sweep: %d time-of-flight samples, prograde and retrograde.\n',nTOF);

for k = 1:nTOF
    tof = tofSecondsDense(k);
    Rtarget = RtargetSweep(:,k);
    Vtarget = VtargetSweep(:,k);

    for direction = ["Prograde","Retrograde"]
        try
            [V1plus,V2minus] = LambertTd(R0,Rtarget,tof,mu,char(direction));
            if any(~isfinite(V1plus)) || any(~isfinite(V2minus))
                continue;
            end

            dV1 = norm(V1plus - V0minus);
            dV2 = norm(Vtarget - V2minus);

            newRecord = makeRecord("Lambert",tofDaysDense(k),tof,direction, ...
                V1plus,V2minus,dV1,dV2,Rtarget,Vtarget,0);
            records(end+1) = newRecord; %#ok<SAGROW>
        catch
            % Singular or non-convergent Lambert cases are skipped.
        end
    end
end

fprintf('Lambert candidates generated: %d\n',numel(records));

if runMultiRevLambert
    fprintf('Adding multi-revolution Lambert candidates: %d TOF samples, up to %d revolutions.\n', ...
        multiRevTOFSamples,maxLambertRevs);
    sampleIdx = unique(round(linspace(1,nTOF,multiRevTOFSamples)));
    nBeforeMultiRev = numel(records);

    for ii = 1:numel(sampleIdx)
        k = sampleIdx(ii);
        tof = tofSecondsDense(k);
        tofDays = tofDaysDense(k);
        Rtarget = RtargetSweep(:,k);
        Vtarget = VtargetSweep(:,k);

        for direction = ["Prograde","Retrograde"]
            maxRevHere = min(maxLambertRevs,max(1,floor(tofDays)));
            for nRev = 1:maxRevHere
                for lowPath = [true false]
                    try
                        [V1list,V2list] = LambertMultiRevIzzo(R0,Rtarget,tof,mu, ...
                            char(direction),nRev,lowPath);
                        for q = 1:size(V1list,2)
                            V1plus = V1list(:,q);
                            V2minus = V2list(:,q);
                            if any(~isfinite(V1plus)) || any(~isfinite(V2minus))
                                continue;
                            end

                            dV1 = norm(V1plus - V0minus);
                            dV2 = norm(Vtarget - V2minus);
                            rec = makeRecord("MultiRevLambert",tofDays,tof, ...
                                sprintf('%s, M=%d, %s',char(direction),nRev,pathName(lowPath)), ...
                                V1plus,V2minus,dV1,dV2,Rtarget,Vtarget,0);
                            rec.nRev = nRev;
                            records(end+1) = rec; %#ok<SAGROW>
                        end
                    catch
                        % Infeasible multi-revolution branches are skipped.
                    end
                end
            end
        end
    end

    fprintf('Multi-revolution Lambert candidates added: %d\n',numel(records)-nBeforeMultiRev);
end

records = addSamePointPhasingCandidates(records,R0,V0minus,RGEO0,VGEO0, ...
    mu,wE,rGEO,Re,lambdaGEO);
fprintf('Candidates after adding GEO-radius phasing family: %d\n',numel(records));

%% Optional direct-shooting refinement
% This step is included because long-duration rendezvous can hide useful
% multi-revolution/phasing solutions that a simple zero-revolution Lambert
% sweep may miss. The optimizer minimizes dV plus a large terminal-position
% penalty, using only fminsearch.
if runShootingRefinement && ~isempty(records)
    fprintf('Refining selected Pareto and grid candidates with direct shooting...\n');
    seedIdx = chooseRefinementSeeds(records,30);

    % Add several analytic-looking guesses around the initial GTO apogee
    % speed and GEO speed. They make the search less dependent on Lambert.
    extraTofDays = unique([1:1:30, 1.5:1:29.5]);
    for q = 1:numel(extraTofDays)
        seed.V1plus = initialVelocityGuess(R0,V0minus,extraTofDays(q),mu,rGEO);
        seed.tofDays = extraTofDays(q);
        seed.method = "Guess";
        seedIdx(end+1) = seed; %#ok<SAGROW>
    end

    maxRefine = min(numel(seedIdx),12);
    options = optimset('Display','off','MaxIter',160,'MaxFunEvals',260, ...
        'TolX',1e-8,'TolFun',1e-8);

    for s = 1:maxRefine
        tofDays = seedIdx(s).tofDays;
        tof = tofDays*86400;
        [Rtarget,Vtarget] = targetGEOState(tof,RGEO0,VGEO0,mu);
        vSeed = seedIdx(s).V1plus(:);

        scale = [3; 3; 3];
        x0 = vSeed ./ scale;
        objective = @(x) shootingObjective(x.*scale,R0,V0minus,Rtarget,Vtarget,tof,mu);

        try
            xBest = fminsearch(objective,x0,options);
            V1plus = xBest(:).*scale;
            [Rf,V2minus] = propagateState(R0,V1plus,tof,mu);
            posErr = norm(Rf - Rtarget);

            if posErr < 5.0
                dV1 = norm(V1plus - V0minus);
                dV2 = norm(Vtarget - V2minus);
                records(end+1) = makeRecord("Shooting",tofDays,tof,"Direct", ...
                    V1plus,V2minus,dV1,dV2,Rtarget,Vtarget,posErr); %#ok<SAGROW>
            end
        catch
        end

        if mod(s,10) == 0
            fprintf('  Refinement %d / %d complete, records: %d\n',s,maxRefine,numel(records));
        end
    end
end

%% Pareto set and representative solutions
records = validateParetoReachability(records,R0,mu,terminalPositionToleranceKm);
valid = [records.dVtotal] < 20 & [records.tofDays] >= 1 & [records.tofDays] <= 30;
records = records(valid);

paretoMask = paretoFilter([records.dVtotal].',[records.tofDays].');
pareto = records(paretoMask);
[~,order] = sort([pareto.tofDays]);
pareto = pareto(order);

% Representative points: fastest, knee-ish, lowest dV, plus a few spread-out
% Pareto points for the final report table. The submitted design point is
% selected separately using the mission priority above.
reportSet = chooseReportSet(pareto,8);
representativeCandidates = buildRepresentativeCandidateSet(records, ...
    representativeMinTOFDays,representativeMaxTOFDays);
representativeSolution = chooseRepresentativeSolution(representativeCandidates,missionPriority, ...
    timeWeight,deltaVWeight,deltaVMarginPercent);
reportSet = includeSolution(reportSet,representativeSolution);
fastSolution = pareto(1);
[~,minDvIdx] = min([pareto.dVtotal]);
minDvSolution = pareto(minDvIdx);
bestForAnimation = representativeSolution; % Submitted design point based on mission priority.

fprintf('\nPareto-optimal candidates: %d\n',numel(pareto));
fprintf('Mission priority for submitted design point: %s\n',char(missionPriority));
if strcmpi(missionPriority,"knee")
    fprintf('  Knee score weights: time %.2f, total dV %.2f\n', ...
        timeWeight,deltaVWeight);
    fprintf('  Representative candidate constraint: %.2f <= TOF <= %.2f days\n', ...
        representativeMinTOFDays,representativeMaxTOFDays);
    fprintf('  Constrained Pareto candidates available: %d\n',numel(representativeCandidates));
elseif strcmpi(missionPriority,"fast_with_dv_margin")
    fprintf('  dV margin from minimum-dV Pareto point: %.2f%%\n',deltaVMarginPercent);
    fprintf('  Representative candidate constraint: %.2f <= TOF <= %.2f days\n', ...
        representativeMinTOFDays,representativeMaxTOFDays);
    fprintf('  Constrained Pareto candidates available: %d\n',numel(representativeCandidates));
elseif strcmpi(missionPriority,"low_dv") || strcmpi(missionPriority,"fast")
    fprintf('  Representative candidate constraint: %.2f <= TOF <= %.2f days\n', ...
        representativeMinTOFDays,representativeMaxTOFDays);
    fprintf('  Constrained Pareto candidates available: %d\n',numel(representativeCandidates));
end
fprintf('Fastest Pareto point: TOF %.6f days, total dV %.6f km/s\n', ...
    fastSolution.tofDays,fastSolution.dVtotal);
fprintf('Lowest-dV Pareto point: TOF %.6f days, total dV %.6f km/s\n', ...
    minDvSolution.tofDays,minDvSolution.dVtotal);
printResultTable(reportSet);
writeResultCsv(fullfile(resultsDir,'FinalProject_ParetoResults.csv'),pareto);
writeResultCsv(fullfile(resultsDir,'FinalProject_ReportSolutions.csv'),reportSet);

%% Build trajectory and required plots for selected solution
nPlot = 2200;
timeGrid = linspace(0,bestForAnimation.tof,nPlot);
[Rtraj,Vtraj] = propagateTrajectory(R0,bestForAnimation.V1plus,timeGrid,mu);
RtargetMotion = zeros(3,nPlot);
VtargetMotion = zeros(3,nPlot);
for k = 1:nPlot
    [RtargetMotion(:,k),VtargetMotion(:,k)] = targetGEOState(timeGrid(k),RGEO0,VGEO0,mu);
end
positionError = vecnorm(Rtraj - RtargetMotion,2,1);
radius = vecnorm(Rtraj,2,1);
elevation = visibilityElevation(Rtraj,timeGrid,JD0,KHU,Re);
intervals = visibilityIntervals(timeGrid,elevation);

if saveFigureFiles
    plotPareto(pareto,reportSet,fullfile(resultsDir,'Pareto_dV_vs_TOF.png'));
    plotTrajectory3D(Rtraj,RtargetMotion,bestForAnimation,R0,RGEO0,Re,rGEO, ...
        fullfile(resultsDir,'Trajectory3D.png'));
    plotRadius(timeGrid,radius,rGEO,fullfile(resultsDir,'Radius_vs_Time.png'));
    plotFinalError(timeGrid,positionError,fullfile(resultsDir,'Position_Error_Final_Window.png'));
    plotManeuverBars(bestForAnimation,fullfile(resultsDir,'DeltaV_Maneuvers.png'));
    plotVisibility(timeGrid,elevation,intervals,fullfile(resultsDir,'KHU_Visibility.png'));
end

if makeAnimation
    try
        animateTransferGif(Rtraj,RtargetMotion,timeGrid,bestForAnimation,Re,rGEO, ...
            fullfile(resultsDir,'GTO_to_GEO_KOMPSAT2A_Animation.gif'));
    catch ME
        warning('GIF animation was skipped because getframe failed: %s',ME.message);
    end
end

fprintf('\nSubmitted representative design point:\n');
fprintf('  Method       : %s\n',bestForAnimation.method);
fprintf('  TOF          : %.6f days\n',bestForAnimation.tofDays);
fprintf('  dV1          : %.6f km/s\n',bestForAnimation.dV1);
fprintf('  dV2          : %.6f km/s\n',bestForAnimation.dV2);
fprintf('  dVtotal      : %.6f km/s\n',bestForAnimation.dVtotal);
fprintf('  final error  : %.6e km\n',positionError(end));

fprintf('\nKHU visibility intervals for selected trajectory, elevation > 0 deg:\n');
if isempty(intervals)
    fprintf('  No visible interval found.\n');
else
    for k = 1:size(intervals,1)
        fprintf('  %2d: %.4f to %.4f days after t0, duration %.2f min\n', ...
            k,intervals(k,1)/86400,intervals(k,2)/86400,(intervals(k,2)-intervals(k,1))/60);
    end
end

fprintf('\nFigures are displayed as docked tabs, and output files are saved in: %s\n',resultsDir);
fprintf('Simulation Time: %.3f seconds\n',toc);

%% Export separated case folders for easier report/inspection workflow
if exportCaseFolders
    caseList = [fastSolution, representativeSolution, minDvSolution];
    caseNames = ["fast_solution", "representative_mission_priority", "min_dv_solution"];
    for c = 1:numel(caseList)
        exportCaseFolder(caseList(c),caseNames(c),resultsDir,R0,RGEO0,VGEO0,mu,wE,JD0,KHU,Re,rGEO);
    end
end

%% ========================================================================
% Local functions
% ========================================================================
function rec = makeRecord(method,tofDays,tof,direction,V1plus,V2minus,dV1,dV2,Rtarget,Vtarget,posErr)
    rec.method = char(method);
    rec.tofDays = tofDays;
    rec.tof = tof;
    rec.direction = char(direction);
    rec.V1plus = V1plus(:);
    rec.V2minus = V2minus(:);
    rec.dV1 = dV1;
    rec.dV2 = dV2;
    rec.dVtotal = dV1 + dV2;
    rec.Rtarget = Rtarget(:);
    rec.Vtarget = Vtarget(:);
    rec.posErrFinal = posErr;
    rec.nRev = NaN;
    rec.aPhase = NaN;
    rec.rpPhase = NaN;
end

function [R,V] = targetGEOState(t,RGEO0,VGEO0,mu)
    % The instructor clarified that the Section 3.2 state vector is the
    % project boundary condition. Propagate that target state with the same
    % two-body model used for the transfer spacecraft.
    if abs(t) < eps
        R = RGEO0;
        V = VGEO0;
    else
        [R,V] = propagateState(RGEO0,VGEO0,t,mu);
    end
end

function records = addSamePointPhasingCandidates(records,R0,V0minus,RGEO0,VGEO0,mu,wE,rGEO,Re,lambdaGEO)
    % If the moving GEO target reaches the initial GTO apogee inertial
    % direction at arrival, the spacecraft can use an equatorial phasing
    % orbit that starts and ends at the same GEO-radius point. This exploits
    % the special geometry of the project and usually beats the pure
    % zero-revolution Lambert baseline for long-duration cases.
    if abs(norm(RGEO0) - rGEO) > 1e-3 || abs(dot(RGEO0,VGEO0)) > 1e-3
        fprintf(['Skipping analytic same-point phasing family because the Section 3.2 ', ...
            'target state is not a circular GEO-radius state.\n']);
        return;
    end

    thetaTarget0 = atan2(RGEO0(2),RGEO0(1));
    thetaStart = atan2(R0(2),R0(1));
    dtheta = mod(thetaStart - thetaTarget0,2*pi);
    tangent = cross([0;0;1],R0(:));
    tangent = tangent/norm(tangent);
    minPerigee = Re + 250;

    for m = 0:60
        tof = (dtheta + 2*pi*m)/wE;
        tofDays = tof/86400;
        if tofDays < 1 || tofDays > 30
            continue;
        end

        for nRev = 1:80
            orbitPeriod = tof/nRev;
            a = (mu*(orbitPeriod/(2*pi))^2)^(1/3);
            if a <= 0
                continue;
            end

            if a < rGEO
                rp = 2*a - rGEO;
                if rp < minPerigee
                    continue;
                end
            else
                rp = rGEO;
            end

            vPhase = sqrt(mu*(2/rGEO - 1/a));
            if ~isreal(vPhase) || ~isfinite(vPhase)
                continue;
            end

            Vphase = vPhase*tangent;
            [Rtarget,Vtarget] = targetGEOState(tof,RGEO0,VGEO0,mu);
            dV1 = norm(Vphase - V0minus);
            dV2 = norm(Vtarget - Vphase);
            posErr = norm(Rtarget - R0);

            if posErr < 1e-2
                rec = makeRecord("Phasing",tofDays,tof, ...
                    sprintf('N=%d, lon=%.1fE',nRev,rad2deg(lambdaGEO)), ...
                    Vphase,Vphase,dV1,dV2,Rtarget,Vtarget,posErr);
                rec.nRev = nRev;
                rec.aPhase = a;
                rec.rpPhase = rp;
                records(end+1) = rec; %#ok<AGROW>
            end
        end
    end
end

function [V1plus,V2minus] = LambertTd(R1,R2,dt,mu,mode)
    r1 = norm(R1);
    r2 = norm(R2);
    cosPhi = max(-1,min(1,dot(R1,R2)/(r1*r2)));
    phi = acos(cosPhi);
    R3 = cross(R1,R2);

    if strcmpi(mode,'Prograde')
        if R3(3) <= 0
            phi = 2*pi - phi;
        end
    elseif strcmpi(mode,'Retrograde')
        if R3(3) >= 0
            phi = 2*pi - phi;
        end
    end

    if abs(1 - cos(phi)) < 1e-12
        error('Lambert singular geometry.');
    end
    A = sin(phi)*sqrt(r1*r2/(1 - cos(phi)));
    if abs(A) < 1e-12
        error('Lambert singular A.');
    end

    z = -100;
    [S,C] = stumpff(z);
    y = r1 + r2 + A*(z*S - 1)/sqrt(C);
    F = inf;

    while z < 100
        [S,C] = stumpff(z);
        y = r1 + r2 + A*(z*S - 1)/sqrt(C);
        if y > 0 && C > 0
            F = (y/C)^(3/2)*S + A*sqrt(y) - sqrt(mu)*dt;
            if F >= 0
                break;
            end
        end
        z = z + 0.1;
    end
    if ~isfinite(F) || F < 0
        error('Lambert bracket failed.');
    end

    tolerance = 1e-8;
    nmax = 1000;
    ratio = 1;
    n = 0;

    while abs(ratio) > tolerance && n < nmax
        n = n + 1;
        [S,C] = stumpff(z);
        y = r1 + r2 + A*(z*S - 1)/sqrt(C);
        if y <= 0
            z = z + 0.1;
            continue;
        end
        F = (y/C)^(3/2)*S + A*sqrt(y) - sqrt(mu)*dt;

        if abs(z) < 1e-8
            dF = sqrt(2)/40*y^(3/2) + A/8*(sqrt(y) + A*sqrt(1/(2*y)));
        else
            dF = (y/C)^(3/2)*(1/(2*z)*(C - 3*S/(2*C)) + 3*S^2/(4*C)) ...
                + A/8*(3*S*sqrt(y)/C + A*sqrt(C/y));
        end

        ratio = F/dF;
        z = z - ratio;
    end

    if n >= nmax || ~isfinite(z)
        error('Lambert iteration did not converge.');
    end

    f = 1 - y/r1;
    g = A*sqrt(y/mu);
    gdot = 1 - y/r2;

    if abs(g) < 1e-12
        error('Lambert g singular.');
    end
    V1plus = (R2 - f*R1)/g;
    V2minus = (gdot*R2 - R1)/g;
end

function [V1list,V2list] = LambertMultiRevIzzo(R1,R2,dt,mu,mode,M,lowPath)
    r1 = norm(R1);
    r2 = norm(R2);
    cVec = R2(:) - R1(:);
    c = norm(cVec);
    s = 0.5*(r1 + r2 + c);
    if c < 1e-10 || s <= 0 || M < 1
        error('Invalid multi-revolution Lambert geometry.');
    end

    lambda = sqrt(max(0,1 - c/s));
    ih = cross(R1(:),R2(:));
    if norm(ih) < 1e-12
        error('Multi-revolution Lambert singular plane.');
    end
    ih = ih/norm(ih);

    if strcmpi(mode,'Prograde')
        if ih(3) < 0
            ih = -ih;
            lambda = -lambda;
        end
    elseif strcmpi(mode,'Retrograde')
        if ih(3) >= 0
            ih = -ih;
            lambda = -lambda;
        end
    else
        error('mode must be Prograde or Retrograde.');
    end

    if ~lowPath
        lambda = -lambda;
    end

    Ttarget = sqrt(2*mu/s^3)*dt;
    xRoots = findIzzoXRoots(lambda,M,Ttarget);
    if isempty(xRoots)
        error('No multi-revolution Lambert root found.');
    end

    ir1 = R1(:)/r1;
    ir2 = R2(:)/r2;
    it1 = cross(ih,ir1);
    it2 = cross(ih,ir2);

    gamma = sqrt(mu*s/2);
    rho = (r1 - r2)/c;
    sigma = sqrt(max(0,1 - rho^2));

    V1list = zeros(3,numel(xRoots));
    V2list = zeros(3,numel(xRoots));
    for k = 1:numel(xRoots)
        x = xRoots(k);
        y = sqrt(max(0,1 - lambda^2*(1 - x^2)));
        vr1 = gamma*((lambda*y - x) - rho*(lambda*y + x))/r1;
        vr2 = -gamma*((lambda*y - x) + rho*(lambda*y + x))/r2;
        vt = gamma*sigma*(y + lambda*x);
        vt1 = vt/r1;
        vt2 = vt/r2;
        V1list(:,k) = vr1*ir1 + vt1*it1;
        V2list(:,k) = vr2*ir2 + vt2*it2;
    end
end

function xRoots = findIzzoXRoots(lambda,M,Ttarget)
    epsX = 1e-8;
    xGrid = linspace(-1 + epsX,1 - epsX,900);
    fGrid = nan(size(xGrid));
    for k = 1:numel(xGrid)
        fGrid(k) = izzoTimeOfFlight(xGrid(k),lambda,M) - Ttarget;
    end

    xRoots = [];
    for k = 1:numel(xGrid)-1
        f1 = fGrid(k);
        f2 = fGrid(k+1);
        if ~isfinite(f1) || ~isfinite(f2)
            continue;
        end
        if f1 == 0
            xRoots(end+1) = xGrid(k); %#ok<AGROW>
        elseif f1*f2 < 0
            try
                root = fzero(@(x) izzoTimeOfFlight(x,lambda,M) - Ttarget, ...
                    [xGrid(k), xGrid(k+1)]);
                if isfinite(root) && root > -1 && root < 1
                    if isempty(xRoots) || all(abs(xRoots - root) > 1e-6)
                        xRoots(end+1) = root; %#ok<AGROW>
                    end
                end
            catch
            end
        end
    end
end

function T = izzoTimeOfFlight(x,lambda,M)
    oneMinusX2 = 1 - x^2;
    if oneMinusX2 <= 0
        T = NaN;
        return;
    end
    y = sqrt(max(0,1 - lambda^2*oneMinusX2));
    arg = x*y + lambda*oneMinusX2;
    arg = max(-1,min(1,arg));
    psi = acos(arg);
    T = ((psi + M*pi)/sqrt(oneMinusX2) + lambda*y - x)/oneMinusX2;
end

function name = pathName(lowPath)
    if lowPath
        name = 'low';
    else
        name = 'high';
    end
end

function [S,C] = stumpff(z)
    if z > 0
        sqz = sqrt(z);
        S = (sqz - sin(sqz))/sqz^3;
        C = (1 - cos(sqz))/z;
    elseif z < 0
        sqz = sqrt(-z);
        S = (sinh(sqz) - sqz)/sqz^3;
        C = (cosh(sqz) - 1)/(-z);
    else
        S = 1/6;
        C = 1/2;
    end
end

function seedList = chooseRefinementSeeds(records,nSeed)
    paretoMask = paretoFilter([records.dVtotal].',[records.tofDays].');
    p = records(paretoMask);
    [~,idx] = sort([p.dVtotal]);
    idx = idx(1:min(nSeed,numel(idx)));
    seedList = struct('method',{},'tofDays',{},'V1plus',{});
    for k = 1:numel(idx)
        seedList(k).method = p(idx(k)).method;
        seedList(k).tofDays = p(idx(k)).tofDays;
        seedList(k).V1plus = p(idx(k)).V1plus;
    end
end

function Vguess = initialVelocityGuess(R0,V0minus,tofDays,mu,rGEO)
    radial = R0/norm(R0);
    hhat = cross(R0,V0minus);
    hhat = hhat/norm(hhat);
    that = cross(hhat,radial);
    vCirc = sqrt(mu/rGEO);
    factor = 0.85 + 0.25*sin(2*pi*tofDays/7);
    Vguess = factor*vCirc*that;
end

function J = shootingObjective(V1plus,R0,V0minus,Rtarget,Vtarget,tof,mu)
    try
        [Rf,Vf] = propagateState(R0,V1plus,tof,mu);
        posErr = norm(Rf - Rtarget);
        dV = norm(V1plus - V0minus) + norm(Vtarget - Vf);
        speedPenalty = max(0,norm(V1plus) - 7)^2;
        J = dV + 5000*(posErr/42164.173)^2 + 100*speedPenalty;
        if ~isfinite(J)
            J = 1e12;
        end
    catch
        J = 1e12;
    end
end

function [Rf,Vf] = propagateState(R0,V0,dt,mu)
    options = odeset('RelTol',1e-10,'AbsTol',1e-12);
    [~,X] = ode45(@(t,X) twoBodyEOM(t,X,mu),[0 dt],[R0(:); V0(:)],options);
    Rf = X(end,1:3).';
    Vf = X(end,4:6).';
end

function [R,V] = propagateTrajectory(R0,V0,tGrid,mu)
    options = odeset('RelTol',1e-10,'AbsTol',1e-12);
    [~,X] = ode45(@(t,X) twoBodyEOM(t,X,mu),tGrid,[R0(:); V0(:)],options);
    R = X(:,1:3).';
    V = X(:,4:6).';
end

function records = validateParetoReachability(records,R0,mu,tolKm)
    % A Lambert velocity candidate is useful only if numerical propagation
    % actually reaches the intended final target. This guard is especially
    % important for experimental multi-revolution branches.
    maxPass = 20;
    totalChecked = 0;
    totalRejected = 0;

    for pass = 1:maxPass
        basicMask = [records.dVtotal] < 20 & [records.tofDays] >= 1 & [records.tofDays] <= 30;
        if ~any(basicMask)
            break;
        end

        basicIdx = find(basicMask);
        paretoMask = paretoFilter([records(basicIdx).dVtotal].',[records(basicIdx).tofDays].');
        checkIdx = basicIdx(paretoMask);
        keep = true(size(records));
        changed = false;

        for q = 1:numel(checkIdx)
            idx = checkIdx(q);
            totalChecked = totalChecked + 1;

            try
                oldDVTotal = records(idx).dVtotal;
                [Rf,Vf] = propagateState(R0,records(idx).V1plus,records(idx).tof,mu);
                posErr = norm(Rf - records(idx).Rtarget);
                records(idx).posErrFinal = posErr;
                records(idx).V2minus = Vf;
                records(idx).dV2 = norm(records(idx).Vtarget - Vf);
                records(idx).dVtotal = records(idx).dV1 + records(idx).dV2;
                if abs(records(idx).dVtotal - oldDVTotal) > 1e-8
                    changed = true;
                end

                if ~isfinite(posErr) || posErr > tolKm
                    keep(idx) = false;
                    totalRejected = totalRejected + 1;
                    changed = true;
                end
            catch
                keep(idx) = false;
                totalRejected = totalRejected + 1;
                changed = true;
            end
        end

        records = records(keep);
        if ~changed
            break;
        end
    end

    fprintf('Reachability check: propagated %d Pareto-level candidates; rejected %d with final error > %.3g km.\n', ...
        totalChecked,totalRejected,tolKm);
end

function dX = twoBodyEOM(~,X,mu)
    R = X(1:3);
    V = X(4:6);
    dX = [V; -mu*R/norm(R)^3];
end

function mask = paretoFilter(dV,tofDays)
    n = numel(dV);
    mask = true(n,1);
    for i = 1:n
        if ~isfinite(dV(i)) || ~isfinite(tofDays(i))
            mask(i) = false;
            continue;
        end
        dominated = (dV <= dV(i) & tofDays <= tofDays(i)) & ...
                    (dV < dV(i) | tofDays < tofDays(i));
        dominated(i) = false;
        if any(dominated)
            mask(i) = false;
        end
    end
end

function reportSet = chooseReportSet(pareto,nPick)
    if isempty(pareto)
        error('No Pareto solution found.');
    end
    [~,fastIdx] = min([pareto.tofDays]);
    [~,lowDvIdx] = min([pareto.dVtotal]);
    spread = round(linspace(1,numel(pareto),min(nPick,numel(pareto))));
    idx = unique([fastIdx, spread, lowDvIdx]);
    reportSet = pareto(idx);
    [~,order] = sort([reportSet.tofDays]);
    reportSet = reportSet(order);
end

function candidates = buildRepresentativeCandidateSet(records,minTOFDays,maxTOFDays)
    candidateMask = [records.tofDays] >= minTOFDays & [records.tofDays] <= maxTOFDays;
    candidates = records(candidateMask);
    if isempty(candidates)
        error('No candidate solution satisfies %.3f <= TOF <= %.3f days.', ...
            minTOFDays,maxTOFDays);
    end

    paretoMask = paretoFilter([candidates.dVtotal].',[candidates.tofDays].');
    candidates = candidates(paretoMask);
    [~,order] = sort([candidates.tofDays]);
    candidates = candidates(order);
end

function sol = chooseRepresentativeSolution(candidates,missionPriority,timeWeight,deltaVWeight,deltaVMarginPercent)
    if isempty(candidates)
        error('No representative candidate solution found.');
    end

    switch lower(char(missionPriority))
        case 'fast_with_dv_margin'
            sol = chooseFastWithinDvMargin(candidates,deltaVMarginPercent);
        case 'fast'
            [~,idx] = min([candidates.tofDays]);
            sol = candidates(idx);
        case 'low_dv'
            [~,idx] = min([candidates.dVtotal]);
            sol = candidates(idx);
        case 'knee'
            sol = chooseKneeSolution(candidates,timeWeight,deltaVWeight);
        otherwise
            error('missionPriority must be "fast_with_dv_margin", "low_dv", "knee", or "fast".');
    end
end

function sol = chooseFastWithinDvMargin(pareto,deltaVMarginPercent)
    dV = [pareto.dVtotal];
    minDV = min(dV);
    dVLimit = minDV*(1 + deltaVMarginPercent/100);
    feasible = pareto(dV <= dVLimit);
    if isempty(feasible)
        error('No Pareto solution found within %.2f%% of minimum dV.',deltaVMarginPercent);
    end

    [~,idx] = min([feasible.tofDays]);
    sol = feasible(idx);
end

function sol = chooseKneeSolution(pareto,timeWeight,deltaVWeight)
    %#ok<INUSD>
    % Normalize transfer time and total dV, then select the point with the
    % largest perpendicular distance from the chord connecting the fastest and
    % lowest-Delta-V endpoints. This geometric Pareto knee captures the point
    % where additional waiting starts producing only small fuel savings.
    tof = [pareto.tofDays];
    dV = [pareto.dVtotal];

    if numel(pareto) <= 2
        [~,idx] = min([pareto.dVtotal]);
        sol = pareto(idx);
        return;
    end

    tofRange = max(tof) - min(tof);
    if tofRange < eps
        tofNorm = zeros(size(tof));
    else
        tofNorm = (tof - min(tof)) / tofRange;
    end

    dVRange = max(dV) - min(dV);
    if dVRange < eps
        dVNorm = zeros(size(dV));
    else
        dVNorm = (dV - min(dV)) / dVRange;
    end

    p1 = [tofNorm(1), dVNorm(1)];
    p2 = [tofNorm(end), dVNorm(end)];
    chord = p2 - p1;
    chordNorm = norm(chord);
    if chordNorm < eps
        [~,idx] = min([pareto.dVtotal]);
        sol = pareto(idx);
        return;
    end

    distance = zeros(size(tofNorm));
    for k = 1:numel(tofNorm)
        pk = [tofNorm(k), dVNorm(k)];
        distance(k) = abs(det([chord; pk - p1])) / chordNorm;
    end
    distance([1,end]) = -inf;

    [~,idx] = max(distance);
    sol = pareto(idx);
end

function reportSet = includeSolution(reportSet,sol)
    tolTOF = 1e-9;
    tolDV = 1e-9;
    isPresent = false;
    for k = 1:numel(reportSet)
        sameTOF = abs(reportSet(k).tofDays - sol.tofDays) < tolTOF;
        sameDV = abs(reportSet(k).dVtotal - sol.dVtotal) < tolDV;
        sameMethod = strcmp(reportSet(k).method,sol.method);
        if sameTOF && sameDV && sameMethod
            isPresent = true;
            break;
        end
    end

    if ~isPresent
        reportSet(end+1) = sol; %#ok<AGROW>
    end

    [~,order] = sort([reportSet.tofDays]);
    reportSet = reportSet(order);
end

function exportCaseFolder(sol,caseName,resultsDir,R0,RGEO0,VGEO0,mu,wE,JD0,KHU,Re,rGEO)
    caseDir = fullfile(resultsDir,char(caseName));
    if ~exist(caseDir,'dir')
        mkdir(caseDir);
    end

    nPlot = 2200;
    timeGrid = linspace(0,sol.tof,nPlot);
    [Rtraj,~] = propagateTrajectory(R0,sol.V1plus,timeGrid,mu);
    RtargetMotion = zeros(3,nPlot);
    for k = 1:nPlot
        [RtargetMotion(:,k),~] = targetGEOState(timeGrid(k),RGEO0,VGEO0,mu);
    end
    radius = vecnorm(Rtraj,2,1);
    positionError = vecnorm(Rtraj - RtargetMotion,2,1);
    elevation = visibilityElevation(Rtraj,timeGrid,JD0,KHU,Re);
    intervals = visibilityIntervals(timeGrid,elevation);

    plotTrajectory3D(Rtraj,RtargetMotion,sol,R0,RGEO0,Re,rGEO, ...
        fullfile(caseDir,'Trajectory3D.png'));
    plotRadius(timeGrid,radius,rGEO,fullfile(caseDir,'Radius_vs_Time.png'));
    plotFinalError(timeGrid,positionError,fullfile(caseDir,'Position_Error_Final_Window.png'));
    plotManeuverBars(sol,fullfile(caseDir,'DeltaV_Maneuvers.png'));
    plotVisibility(timeGrid,elevation,intervals,fullfile(caseDir,'KHU_Visibility.png'));

    fid = fopen(fullfile(caseDir,'case_summary.txt'),'w');
    fprintf(fid,'Case: %s\n',char(caseName));
    fprintf(fid,'Method: %s\n',sol.method);
    fprintf(fid,'Direction/detail: %s\n',sol.direction);
    fprintf(fid,'TOF_days: %.10f\n',sol.tofDays);
    fprintf(fid,'dV1_km_s: %.10f\n',sol.dV1);
    fprintf(fid,'dV2_km_s: %.10f\n',sol.dV2);
    fprintf(fid,'dVtotal_km_s: %.10f\n',sol.dVtotal);
    fprintf(fid,'FinalPositionError_km: %.10e\n',sol.posErrFinal);
    fprintf(fid,'nRev: %.0f\n',sol.nRev);
    fprintf(fid,'aPhase_km: %.10f\n',sol.aPhase);
    fprintf(fid,'rpPhase_km: %.10f\n',sol.rpPhase);
    fclose(fid);
end

function printResultTable(solutions)
    fprintf('\nRepresentative result table\n');
    fprintf('Idx Method       TOF [days]   dV1 [km/s]   dV2 [km/s]   dVtotal [km/s]   Final err [km]\n');
    fprintf('-----------------------------------------------------------------------------------------\n');
    for k = 1:numel(solutions)
        fprintf('%3d %-10s %10.5f   %10.6f   %10.6f   %13.6f   %13.6g\n', ...
            k,solutions(k).method,solutions(k).tofDays,solutions(k).dV1, ...
            solutions(k).dV2,solutions(k).dVtotal,solutions(k).posErrFinal);
    end
end

function writeResultCsv(fileName,solutions)
    fid = fopen(fileName,'w');
    fprintf(fid,'Method,Direction,TOF_days,dV1_km_s,dV2_km_s,dVtotal_km_s,FinalPositionError_km,nRev,aPhase_km,rpPhase_km,V1x,V1y,V1z,V2minus_x,V2minus_y,V2minus_z\n');
    for k = 1:numel(solutions)
        fprintf(fid,'%s,%s,%.10f,%.10f,%.10f,%.10f,%.10e,%.0f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f,%.10f\n', ...
            solutions(k).method,solutions(k).direction,solutions(k).tofDays, ...
            solutions(k).dV1,solutions(k).dV2,solutions(k).dVtotal,solutions(k).posErrFinal, ...
            solutions(k).nRev,solutions(k).aPhase,solutions(k).rpPhase, ...
            solutions(k).V1plus(1),solutions(k).V1plus(2),solutions(k).V1plus(3), ...
            solutions(k).V2minus(1),solutions(k).V2minus(2),solutions(k).V2minus(3));
    end
    fclose(fid);
end

function plotPareto(pareto,reportSet,fileName)
    fig = figure('Color','w');
    hold on; grid on; box on;
    plot([pareto.tofDays],[pareto.dVtotal],'b.-','LineWidth',1.5,'MarkerSize',12, ...
        'DisplayName','Pareto candidates');
    plot([reportSet.tofDays],[reportSet.dVtotal],'rp','MarkerFaceColor','y','MarkerSize',13, ...
        'DisplayName','Report solutions');
    xlabel('Transfer duration \Deltat [days]');
    ylabel('Total impulsive \Deltav [km/s]');
    title('Pareto Front: GTO-to-GEO-KOMPSAT-2A Transfer');
    legend('Location','best');
    drawnow;
    exportgraphics(fig,fileName,'Resolution',220);
end

function plotTrajectory3D(Rtraj,RtargetMotion,sol,R0,RGEO0,Re,rGEO,fileName)
    fig = figure('Color','w');
    hold on; grid on; axis equal; box on;
    [xe,ye,ze] = sphere(80);
    surf(Re*xe,Re*ye,Re*ze,'FaceColor',[0.55 0.72 0.95], ...
        'EdgeColor','none','FaceAlpha',0.35,'DisplayName','Earth');
    plotGTOReference(Re,rGEO);
    plotGEOReference(rGEO);
    plot3(RtargetMotion(1,:),RtargetMotion(2,:),RtargetMotion(3,:), ...
        'Color',[0.1 0.5 0.1],'LineWidth',1.2,'DisplayName','Section 3.2 target motion');
    plot3(Rtraj(1,:),Rtraj(2,:),Rtraj(3,:),'r-','LineWidth',2.0,'DisplayName','Optimized transfer');
    plot3(R0(1),R0(2),R0(3),'ko','MarkerFaceColor','w','MarkerSize',8,'DisplayName','Initial GTO apogee');
    plot3(sol.Rtarget(1),sol.Rtarget(2),sol.Rtarget(3),'ks','MarkerFaceColor','y','MarkerSize',9,'DisplayName','Final GEO target');
    plot3(RGEO0(1),RGEO0(2),RGEO0(3),'gd','MarkerFaceColor','g','MarkerSize',7,'DisplayName','Section 3.2 target at t0');
    xlabel('ECI x [km]'); ylabel('ECI y [km]'); zlabel('ECI z [km]');
    title(sprintf('Selected Transfer: TOF %.3f days, total \\Deltav %.4f km/s',sol.tofDays,sol.dVtotal));
    view(38,24);
    camlight; lighting gouraud;
    legend('Location','bestoutside');
    drawnow;
    exportgraphics(fig,fileName,'Resolution',220);
end

function plotGTOReference(Re,rGEO)
    mu = 398600.4418;
    rp = Re + 250;
    ra = rGEO;
    a = (rp + ra)/2;
    e = (ra - rp)/(ra + rp);
    inc = deg2rad(24.5);
    theta = linspace(0,2*pi,700);
    p = a*(1 - e^2);
    r = p./(1 + e*cos(theta));
    rpqw = [r.*cos(theta); r.*sin(theta); zeros(size(theta))];
    R1 = [1 0 0; 0 cos(inc) -sin(inc); 0 sin(inc) cos(inc)];
    reci = R1*rpqw;
    plot3(reci(1,:),reci(2,:),reci(3,:),'k--','LineWidth',0.9,'DisplayName','Initial GTO');
end

function plotGEOReference(rGEO)
    th = linspace(0,2*pi,600);
    plot3(rGEO*cos(th),rGEO*sin(th),zeros(size(th)),'k:','LineWidth',1.1,'DisplayName','Nominal GEO radius');
end

function plotRadius(timeGrid,radius,rGEO,fileName)
    fig = figure('Color','w');
    plot(timeGrid/86400,radius,'b-','LineWidth',1.8); hold on; grid on; box on;
    yline(rGEO,'k--','GEO radius');
    xlabel('Time after t0 [days]');
    ylabel('Radius [km]');
    title('Spacecraft Radius vs. Time');
    drawnow;
    exportgraphics(fig,fileName,'Resolution',220);
end

function plotFinalError(timeGrid,positionError,fileName)
    finalWindow = max(timeGrid) - min(6*3600,max(timeGrid));
    idx = timeGrid >= finalWindow;
    fig = figure('Color','w');
    semilogy((timeGrid(idx)-max(timeGrid))/3600,positionError(idx),'r-','LineWidth',1.8);
    grid on; box on;
    xlabel('Time relative to arrival [hr]');
    ylabel('Position error to moving GEO target [km]');
    title('Position Error Near Final Target');
    drawnow;
    exportgraphics(fig,fileName,'Resolution',220);
end

function plotManeuverBars(sol,fileName)
    fig = figure('Color','w');
    bar([sol.dV1 sol.dV2 sol.dVtotal]);
    grid on; box on;
    set(gca,'XTickLabel',{'Initial burn \Deltav_1','GEO insertion \Deltav_2','Total'});
    ylabel('\Deltav [km/s]');
    title('Impulsive Maneuver Magnitudes');
    drawnow;
    exportgraphics(fig,fileName,'Resolution',220);
end

function elevation = visibilityElevation(Reci,timeGrid,JD0,GS,Re)
    n = numel(timeGrid);
    elevation = zeros(1,n);
    gsECEF = (Re + GS.h)*[cos(GS.lat)*cos(GS.lon); cos(GS.lat)*sin(GS.lon); sin(GS.lat)];
    T = [ sin(GS.lat)*cos(GS.lon),  sin(GS.lat)*sin(GS.lon), -cos(GS.lat); ...
         -sin(GS.lon),              cos(GS.lon),              0; ...
          cos(GS.lat)*cos(GS.lon),  cos(GS.lat)*sin(GS.lon),  sin(GS.lat)];

    for k = 1:n
        ERA = 2*pi*(0.7790572732640 + 1.00273781191135448*(JD0 - 2451545 + timeGrid(k)/86400));
        EciToEcef = [cos(ERA), sin(ERA), 0; -sin(ERA), cos(ERA), 0; 0, 0, 1];
        rhoECEF = EciToEcef*Reci(:,k) - gsECEF;
        rhoSEZ = T*rhoECEF;
        elevation(k) = asin(rhoSEZ(3)/norm(rhoSEZ));
    end
end

function intervals = visibilityIntervals(timeGrid,elevation)
    visible = elevation > 0;
    intervals = [];
    if ~any(visible)
        return;
    end
    changes = diff([false visible false]);
    starts = find(changes == 1);
    stops = find(changes == -1) - 1;
    for k = 1:numel(starts)
        intervals(k,1) = timeGrid(starts(k)); %#ok<AGROW>
        intervals(k,2) = timeGrid(stops(k)); %#ok<AGROW>
    end
end

function plotVisibility(timeGrid,elevation,intervals,fileName)
    fig = figure('Color','w');
    plot(timeGrid/86400,rad2deg(elevation),'b-','LineWidth',1.3); hold on; grid on; box on;
    yline(0,'k--','Horizon');
    for k = 1:size(intervals,1)
        patch([intervals(k,1) intervals(k,2) intervals(k,2) intervals(k,1)]/86400, ...
            [-90 -90 90 90],[0.8 1.0 0.8],'EdgeColor','none','FaceAlpha',0.25);
    end
    plot(timeGrid/86400,rad2deg(elevation),'b-','LineWidth',1.3);
    xlabel('Time after t0 [days]');
    ylabel('Elevation from KHU [deg]');
    title('Visibility Intervals from KHU');
    ylim([-90 90]);
    drawnow;
    exportgraphics(fig,fileName,'Resolution',220);
end

function plotSummaryFigure(pareto,reportSet,Rtraj,RtargetMotion,sol,R0,RGEO0, ...
    timeGrid,radius,positionError,elevation,intervals,Re,rGEO,fileName)
    fig = figure('Color','w');

    subplot(2,3,1);
    hold on; grid on; box on;
    plot([pareto.tofDays],[pareto.dVtotal],'b.-','LineWidth',1.2,'MarkerSize',8);
    plot([reportSet.tofDays],[reportSet.dVtotal],'rp','MarkerFaceColor','y','MarkerSize',9);
    plot(sol.tofDays,sol.dVtotal,'ko','MarkerFaceColor','g','MarkerSize',8);
    xlabel('\Deltat [days]');
    ylabel('Total \Deltav [km/s]');
    title('Pareto Front');

    subplot(2,3,2);
    hold on; grid on; axis equal; box on;
    [xe,ye,ze] = sphere(36);
    surf(Re*xe,Re*ye,Re*ze,'FaceColor',[0.55 0.72 0.95], ...
        'EdgeColor','none','FaceAlpha',0.35);
    plotGTOReference(Re,rGEO);
    plotGEOReference(rGEO);
    plot3(RtargetMotion(1,:),RtargetMotion(2,:),RtargetMotion(3,:), ...
        'Color',[0.1 0.5 0.1],'LineWidth',1.0);
    plot3(Rtraj(1,:),Rtraj(2,:),Rtraj(3,:),'r-','LineWidth',1.5);
    plot3(R0(1),R0(2),R0(3),'ko','MarkerFaceColor','w','MarkerSize',6);
    plot3(sol.Rtarget(1),sol.Rtarget(2),sol.Rtarget(3),'ks','MarkerFaceColor','y','MarkerSize',7);
    plot3(RGEO0(1),RGEO0(2),RGEO0(3),'gd','MarkerFaceColor','g','MarkerSize',6);
    xlabel('ECI x [km]'); ylabel('ECI y [km]'); zlabel('ECI z [km]');
    title('3D Trajectory');
    view(38,24);

    subplot(2,3,3);
    plot(timeGrid/86400,radius,'b-','LineWidth',1.4); hold on; grid on; box on;
    yline(rGEO,'k--','GEO');
    xlabel('Time [days]');
    ylabel('Radius [km]');
    title('Radius vs Time');

    subplot(2,3,4);
    finalWindow = max(timeGrid) - min(6*3600,max(timeGrid));
    idx = timeGrid >= finalWindow;
    semilogy((timeGrid(idx)-max(timeGrid))/3600,positionError(idx),'r-','LineWidth',1.4);
    grid on; box on;
    xlabel('Time to arrival [hr]');
    ylabel('Error [km]');
    title('Final Position Error');

    subplot(2,3,5);
    bar([sol.dV1 sol.dV2 sol.dVtotal]);
    grid on; box on;
    set(gca,'XTickLabel',{'\Deltav_1','\Deltav_2','Total'});
    ylabel('\Deltav [km/s]');
    title('Maneuver Magnitudes');

    subplot(2,3,6);
    plot(timeGrid/86400,rad2deg(elevation),'b-','LineWidth',1.1); hold on; grid on; box on;
    yline(0,'k--','Horizon');
    for k = 1:size(intervals,1)
        patch([intervals(k,1) intervals(k,2) intervals(k,2) intervals(k,1)]/86400, ...
            [-90 -90 90 90],[0.8 1.0 0.8],'EdgeColor','none','FaceAlpha',0.25);
    end
    plot(timeGrid/86400,rad2deg(elevation),'b-','LineWidth',1.1);
    xlabel('Time [days]');
    ylabel('Elevation [deg]');
    title('KHU Visibility');
    ylim([-90 90]);

    if ~isempty(fileName)
        exportgraphics(fig,fileName,'Resolution',220);
    end
end

function animateTransferGif(Rtraj,RtargetMotion,timeGrid,sol,Re,rGEO,fileName)
    fig = figure('Color','w','WindowStyle','normal');
    ax = axes('Parent',fig);
    hold(ax,'on'); grid(ax,'on'); axis(ax,'equal'); box(ax,'on');
    [xe,ye,ze] = sphere(50);
    surf(ax,Re*xe,Re*ye,Re*ze,'FaceColor',[0.55 0.72 0.95], ...
        'EdgeColor','none','FaceAlpha',0.4);
    th = linspace(0,2*pi,400);
    plot3(ax,rGEO*cos(th),rGEO*sin(th),zeros(size(th)),'k:','LineWidth',1);
    plot3(ax,Rtraj(1,:),Rtraj(2,:),Rtraj(3,:),'r:','LineWidth',1);
    plot3(ax,RtargetMotion(1,:),RtargetMotion(2,:),RtargetMotion(3,:), ...
        'Color',[0.1 0.55 0.1],'LineStyle',':','LineWidth',1);
    sat = plot3(ax,Rtraj(1,1),Rtraj(2,1),Rtraj(3,1),'ro','MarkerFaceColor','r','MarkerSize',7);
    tgt = plot3(ax,RtargetMotion(1,1),RtargetMotion(2,1),RtargetMotion(3,1),'gs','MarkerFaceColor','g','MarkerSize',7);
    path = plot3(ax,nan,nan,nan,'r-','LineWidth',1.8);
    xlabel(ax,'ECI x [km]'); ylabel(ax,'ECI y [km]'); zlabel(ax,'ECI z [km]');
    title(ax,sprintf('GTO-to-GEO-KOMPSAT-2A, TOF %.2f days, total \\Deltav %.3f km/s', ...
        sol.tofDays,sol.dVtotal));
    view(ax,38,24);
    xlim(ax,[-52000 52000]); ylim(ax,[-52000 52000]); zlim(ax,[-24000 24000]);
    legend(ax,{'Earth','Nominal GEO radius','Transfer reference','Section 3.2 target motion','Spacecraft','Target'}, ...
        'Location','bestoutside');

    nFrame = 160;
    idx = unique(round(linspace(1,size(Rtraj,2),nFrame)));
    for j = 1:numel(idx)
        k = idx(j);
        sat.XData = Rtraj(1,k); sat.YData = Rtraj(2,k); sat.ZData = Rtraj(3,k);
        tgt.XData = RtargetMotion(1,k); tgt.YData = RtargetMotion(2,k); tgt.ZData = RtargetMotion(3,k);
        path.XData = Rtraj(1,1:k); path.YData = Rtraj(2,1:k); path.ZData = Rtraj(3,1:k);
        title(ax,sprintf('t = %.2f days / %.2f days',timeGrid(k)/86400,sol.tofDays));
        drawnow;
        frame = getframe(ax);
        [im,map] = rgb2ind(frame2im(frame),256);
        if j == 1
            imwrite(im,map,fileName,'gif','LoopCount',inf,'DelayTime',0.045);
        else
            imwrite(im,map,fileName,'gif','WriteMode','append','DelayTime',0.045);
        end
    end
end
