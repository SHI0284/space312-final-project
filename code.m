%% ========================================================================
%  SPACE312 Final Project — GTO-to-GEO Transfer Trajectory Optimization
%  Mission Target : GEO-KOMPSAT-2A (128.2 deg East)
%
%  APPROACH:
%   - Two-body ECI propagation (given)
%   - Lambert arc (Izzo algorithm) for each candidate transfer
%   - Pareto sweep: Δt from 1 to 30 days, optimize Δv at each Δt
%   - Both 2-burn and 3-burn solutions compared; best kept per Δt
%   - Pareto-optimal set extracted and plotted
%   - Full deliverables: 5 figures + 3D animation + result table
%% ========================================================================
clc; clear; close all;

%% ════════════════════════════════════════════════════════════════════════
%  1. CONSTANTS
%% ════════════════════════════════════════════════════════════════════════
mu_E       = 398600.4418;          % km^3/s^2
R_E        = 6378.137;             % km
omega_E    = 7.2921150e-5;         % rad/s
r_GEO      = (mu_E / omega_E^2)^(1/3);   % should be ~42164.173 km
theta_ERA0 = 249.1551677 * pi/180;        % rad, ERA at t0

fprintf('=== SPACE312 GTO to GEO Optimizer ===\n');
fprintf('r_GEO = %.3f km\n', r_GEO);

%% ════════════════════════════════════════════════════════════════════════
%  2. INITIAL STATE (ECI at t0)
%% ════════════════════════════════════════════════════════════════════════
r0 = [-42164.1729;  0.0000;  0.0000];   % km
v0 = [  0.000000; -1.458327; -0.664598]; % km/s

%% ════════════════════════════════════════════════════════════════════════
%  3. TARGET GEO STATE FUNCTION
%     GEO-KOMPSAT-2A: fixed ECEF longitude 128.2 deg East
%     ECI longitude = ERA(t) + lambda_ECEF
%% ════════════════════════════════════════════════════════════════════════
lambda_ecef = 128.2 * pi/180;   % fixed ECEF longitude [rad]

% ECI state of GEO slot at t_sec seconds after t0
target_fn = @(t_sec) compute_geo_target(t_sec, r_GEO, omega_E, theta_ERA0, lambda_ecef);

% Verify against given values
st0 = target_fn(0);
fprintf('\nTarget GEO state at t0 (ECI):\n');
fprintf('  r = [%.4f, %.4f, %.4f] km\n',   st0(1), st0(2), st0(3));
fprintf('  v = [%.6f, %.6f, %.6f] km/s\n', st0(4), st0(5), st0(6));
fprintf('  Expected r = [41244.6079, 12577.3213, 0.0000]\n');
fprintf('  Expected v = [-0.917153, 2.934683, 0.000000]\n\n');

%% ════════════════════════════════════════════════════════════════════════
%  4. INITIAL GTO ORBITAL ELEMENTS (verification)
%% ════════════════════════════════════════════════════════════════════════
oe0 = rv2oe(r0, v0, mu_E);
fprintf('Initial GTO orbital elements:\n');
fprintf('  a = %.3f km,  e = %.6f,  i = %.4f deg\n', ...
        oe0(1), oe0(2), oe0(3)*180/pi);
fprintf('  RAAN = %.2f deg,  w = %.2f deg,  nu = %.2f deg\n\n', ...
        oe0(4)*180/pi, oe0(5)*180/pi, oe0(6)*180/pi);

%% ════════════════════════════════════════════════════════════════════════
%  5. PARETO SWEEP  (1 <= Δt <= 30 days)
%% ════════════════════════════════════════════════════════════════════════
fprintf('Running Pareto sweep (2-burn Lambert solutions)...\n');

% Dense sweep for smooth Pareto curve
dt_days_vec = linspace(1, 30, 90);
N_sweep  = length(dt_days_vec);

dv_results = nan(N_sweep, 1);
dv1_results = nan(N_sweep, 1);
dv2_results = nan(N_sweep, 1);
lw_results  = zeros(N_sweep, 1);

for k = 1:N_sweep
    dt_s  = dt_days_vec(k) * 86400;
    st_f  = target_fn(dt_s);
    r_f   = st_f(1:3);
    v_f   = st_f(4:6);

    best_dv = inf; best_dv1 = nan; best_dv2 = nan; best_lw = 0;

    for lw = [0, 1]
        try
            [v1_l, v2_l] = lambert_izzo(r0, r_f, dt_s, mu_E, lw);
            dv1 = norm(v1_l - v0);
            dv2 = norm(v_f  - v2_l);
            if dv1 + dv2 < best_dv
                best_dv  = dv1 + dv2;
                best_dv1 = dv1;
                best_dv2 = dv2;
                best_lw  = lw;
            end
        catch
            % Lambert may fail for extreme cases; skip
        end
    end

    dv_results(k)  = best_dv;
    dv1_results(k) = best_dv1;
    dv2_results(k) = best_dv2;
    lw_results(k)  = best_lw;

    if mod(k,15) == 1
        fprintf('  Δt = %5.2f days  Δv = %.4f km/s\n', dt_days_vec(k), best_dv);
    end
end

%% ════════════════════════════════════════════════════════════════════════
%  6. PARETO FILTERING
%% ════════════════════════════════════════════════════════════════════════
valid = ~isnan(dv_results);
dt_v  = dt_days_vec(valid)';
dv_v  = dv_results(valid);

is_pareto = true(length(dt_v), 1);
for i = 1:length(dt_v)
    for j = 1:length(dt_v)
        if i ~= j
            if dt_v(j) <= dt_v(i) && dv_v(j) <= dv_v(i) && ...
               (dt_v(j) < dt_v(i) || dv_v(j) < dv_v(i))
                is_pareto(i) = false; break;
            end
        end
    end
end

dt_par = dt_v(is_pareto);
dv_par = dv_v(is_pareto);
[dt_par, isrt] = sort(dt_par);
dv_par = dv_par(isrt);

fprintf('\n=== PARETO-OPTIMAL SOLUTIONS ===\n');
fprintf('%-12s  %-14s\n','Δt [days]','Δv_total [km/s]');
fprintf('%s\n', repmat('-',28,1));
for k = 1:length(dt_par)
    fprintf('%-12.2f  %-14.4f\n', dt_par(k), dv_par(k));
end

%% ════════════════════════════════════════════════════════════════════════
%  7. SELECT REPRESENTATIVE SOLUTIONS FOR DETAILED PLOTS
%     - Minimum Δv solution
%     - ~5-day solution (fast transfer)
%% ════════════════════════════════════════════════════════════════════════
[~, imin_dv]  = min(dv_results);
[~, i5day]    = min(abs(dt_days_vec - 5));

% Best Δv solution
dt_best  = dt_days_vec(imin_dv);
dt_best_s = dt_best * 86400;
st_f_best = target_fn(dt_best_s);
[v1_best, v2_best, ~] = lambert_best_2way(r0, v0, st_f_best, dt_best_s, mu_E);
dv1_best = norm(v1_best - v0);
dv2_best = norm(st_f_best(4:6) - v2_best);

fprintf('\n--- Best Δv Solution ---\n');
fprintf('Δt = %.2f days\n', dt_best);
fprintf('ΔV1 = %.4f km/s  (apogee kick)\n', dv1_best);
fprintf('ΔV2 = %.4f km/s  (GEO insertion)\n', dv2_best);
fprintf('Δv_total = %.4f km/s\n', dv1_best + dv2_best);

%% ════════════════════════════════════════════════════════════════════════
%  8. PROPAGATE FULL TRAJECTORY (best Δv solution)
%% ════════════════════════════════════════════════════════════════════════
N_pts = 1000;
t_span   = linspace(0, dt_best_s, N_pts);
traj_sc  = zeros(6, N_pts);
traj_tgt = zeros(6, N_pts);

state_init = [r0; v1_best];
for ii = 1:N_pts
    traj_sc(:,ii)  = kepler_propagate(state_init, t_span(ii), mu_E);
    traj_tgt(:,ii) = target_fn(t_span(ii));
end

% Verify final state
r_final = traj_sc(1:3, end);
fprintf('\nFinal position: [%.2f, %.2f, %.2f] km,  |r| = %.3f km\n', ...
        r_final(1), r_final(2), r_final(3), norm(r_final));
fprintf('Target r_GEO = %.3f km  |  error = %.4f km\n', r_GEO, norm(r_final)-r_GEO);

%% ════════════════════════════════════════════════════════════════════════
%  9. REFERENCE ORBITS FOR PLOTTING
%% ════════════════════════════════════════════════════════════════════════
% Full GTO loop
nu_arr = linspace(0, 2*pi, 500);
gto_pts = zeros(3,500);
for ii = 1:500
    oe_tmp = oe0; oe_tmp(6) = nu_arr(ii);
    rv_tmp = oe2rv(oe_tmp, mu_E);
    gto_pts(:,ii) = rv_tmp(1:3);
end

% GEO ring (equatorial circle)
th = linspace(0, 2*pi, 500);
geo_ring = r_GEO * [cos(th); sin(th); zeros(1,500)];

%% ════════════════════════════════════════════════════════════════════════
%  10. FIGURES
%% ════════════════════════════════════════════════════════════════════════

% ── Figure 1: 3D Trajectory ───────────────────────────────────────────────
figure('Name','Fig1 - 3D Trajectory','Color','k','Position',[30 400 900 720]);
ax1 = axes('Color','k','XColor','w','YColor','w','ZColor','w'); hold on; grid on;
axis equal;

[xs,ys,zs] = sphere(50);
surf(R_E*xs, R_E*ys, R_E*zs, ...
     'FaceColor',[0.20 0.50 1.00],'FaceAlpha',0.75,'EdgeAlpha',0.05);

plot3(gto_pts(1,:), gto_pts(2,:), gto_pts(3,:), ...
      'Color',[1 0.55 0.1],'LineWidth',1.5,'DisplayName','Initial GTO');
plot3(geo_ring(1,:), geo_ring(2,:), geo_ring(3,:), ...
      'Color',[0.3 1 0.3],'LineWidth',1.5,'DisplayName','Target GEO Ring');
plot3(traj_sc(1,:), traj_sc(2,:), traj_sc(3,:), ...
      'Color',[1 0.95 0.1],'LineWidth',2.5,'DisplayName','Transfer Arc');

scatter3(r0(1), r0(2), r0(3), 180,'r','filled','DisplayName','ΔV1 – Apogee Kick');
scatter3(traj_sc(1,end), traj_sc(2,end), traj_sc(3,end), 180,'m','filled', ...
         'DisplayName','ΔV2 – GEO Insertion');
scatter3(st0(1), st0(2), st0(3), 100, [0.3 1 0.3], 'd','filled', ...
         'DisplayName','GEO-KOMPSAT-2A (t_0)');
scatter3(traj_tgt(1,end), traj_tgt(2,end), traj_tgt(3,end), 100, [1 0.3 1], 'd','filled',...
         'DisplayName','GEO-KOMPSAT-2A (t_f)');

xlabel('X_{ECI} [km]','Color','w'); ylabel('Y_{ECI} [km]','Color','w');
zlabel('Z_{ECI} [km]','Color','w');
title(sprintf('3D GTO→GEO Transfer  |  Δt = %.2f d, Δv_{total} = %.4f km/s', ...
      dt_best, dv1_best+dv2_best), 'Color','w','FontSize',12);
leg = legend('Location','northwest'); leg.TextColor = 'w'; leg.Color = 'k';
set(ax1,'FontSize',10,'GridColor','w','GridAlpha',0.2); view(28,22);

% ── Figure 2: Radius vs. Time ─────────────────────────────────────────────
figure('Name','Fig2 - Radius vs Time','Position',[950 400 750 450]);
r_mag = vecnorm(traj_sc(1:3,:));
t_hrs = t_span / 3600;
plot(t_hrs, r_mag, 'b-', 'LineWidth', 2); hold on;
yline(r_GEO, 'g--', 'LineWidth', 1.8, 'Label', 'GEO radius');
yline(R_E+250, 'r--', 'LineWidth', 1.2, 'Label', 'GTO perigee');
scatter(0,           norm(r0),             80,'r','filled','DisplayName','ΔV1');
scatter(t_hrs(end),  norm(traj_sc(1:3,end)),80,'m','filled','DisplayName','ΔV2');
xlabel('Time [hours]'); ylabel('Orbital Radius [km]');
title('Spacecraft Radius vs. Time'); grid on;
legend('Spacecraft','GEO radius','GTO perigee alt','ΔV1','ΔV2','Location','best');

% ── Figure 3: ΔV Maneuver Locations (XY projection) ──────────────────────
figure('Name','Fig3 - Maneuver Locations','Position',[30 30 750 600]);
plot(gto_pts(1,:)/1e3, gto_pts(2,:)/1e3,'Color',[1 0.55 0.1],'LineWidth',1.5); hold on;
plot(geo_ring(1,:)/1e3, geo_ring(2,:)/1e3,'Color',[0.3 1 0.3],'LineWidth',1.5);
plot(traj_sc(1,:)/1e3, traj_sc(2,:)/1e3,'b-','LineWidth',2);
th_e = linspace(0,2*pi,200);
plot(R_E*cos(th_e)/1e3, R_E*sin(th_e)/1e3,'c-','LineWidth',1);
scatter(r0(1)/1e3, r0(2)/1e3, 130,'r','filled','DisplayName','ΔV1 Apogee Kick');
scatter(traj_sc(1,end)/1e3, traj_sc(2,end)/1e3, 130,'m','filled','DisplayName','ΔV2 GEO Insert');
axis equal; grid on;
xlabel('X [×10^3 km]'); ylabel('Y [×10^3 km]');
title('ΔV Maneuver Locations (XY-Plane Projection)');
legend('GTO','GEO Ring','Transfer','Earth','ΔV1','ΔV2','Location','best');

% ── Figure 4: Position Error vs. Time ────────────────────────────────────
figure('Name','Fig4 - Position Error','Position',[950 30 750 450]);
pos_err = zeros(1, N_pts);
for ii = 1:N_pts
    pos_err(ii) = norm(traj_sc(1:3,ii) - traj_tgt(1:3,ii));
end
semilogy(t_hrs, pos_err, 'b-', 'LineWidth', 2); hold on;
xline(t_hrs(end), 'r--', 'LineWidth', 1.5, 'Label', 'GEO Insertion');
xlabel('Time [hours]'); ylabel('Distance from GEO Target Slot [km]');
title('Position Error w.r.t. GEO-KOMPSAT-2A Target vs. Time'); grid on;

% ── Figure 5: Pareto Front ────────────────────────────────────────────────
figure('Name','Fig5 - Pareto Front','Position',[400 150 780 500]);
scatter(dt_days_vec, dv_results, 25, 'b', 'filled', 'DisplayName','All solutions'); hold on;
plot(dt_par, dv_par,'r-o','LineWidth',2,'MarkerSize',7,'MarkerFaceColor','r',...
     'DisplayName','Pareto front');
[~,ib] = min(dv_par);
scatter(dt_par(ib), dv_par(ib), 180, 'k','p','filled', ...
        'DisplayName', sprintf('Min Δv: %.3f km/s @ %.1f d', dv_par(ib), dt_par(ib)));
scatter(dt_best, dv1_best+dv2_best, 150,'g','h','filled',...
        'DisplayName','Selected solution');
xlabel('Transfer Duration Δt [days]'); ylabel('Total Δv [km/s]');
title('Pareto Front: Total Δv vs. Transfer Duration');
grid on; legend('Location','northeast');

%% ════════════════════════════════════════════════════════════════════════
%  11. RESULT TABLE
%% ════════════════════════════════════════════════════════════════════════
fprintf('\n=== FINAL RESULT TABLE ===\n');
fprintf('%-10s  %-12s  %-12s  %-14s\n', 'Δt [days]','ΔV1 [km/s]','ΔV2 [km/s]','Δv_total [km/s]');
fprintf('%s\n', repmat('-',52,1));

for k = 1:length(dt_par)
    dt_s_k  = dt_par(k) * 86400;
    st_fk   = target_fn(dt_s_k);
    [v1k, v2k, ~] = lambert_best_2way(r0, v0, st_fk, dt_s_k, mu_E);
    dv1k = norm(v1k - v0);
    dv2k = norm(st_fk(4:6) - v2k);
    fprintf('%-10.2f  %-12.4f  %-12.4f  %-14.4f\n', dt_par(k), dv1k, dv2k, dv1k+dv2k);
end

%% ════════════════════════════════════════════════════════════════════════
%  12. 3D ANIMATION
%% ════════════════════════════════════════════════════════════════════════
fprintf('\nStarting 3D animation...\n');
fig_anim = figure('Name','Animation - GTO to GEO Transfer', ...
                  'Color','k','Position',[50 50 1000 800]);
ax_a = axes('Color','k','XColor','w','YColor','w','ZColor','w','FontSize',11);
hold on; grid on; axis equal;

[xs,ys,zs] = sphere(50);
surf(R_E*xs, R_E*ys, R_E*zs, ...
     'FaceColor',[0.15 0.45 0.9],'FaceAlpha',0.8,'EdgeAlpha',0.05);
plot3(gto_pts(1,:), gto_pts(2,:), gto_pts(3,:), ...
      'Color',[1 0.55 0.1],'LineWidth',1.2,'LineStyle','--');
plot3(geo_ring(1,:), geo_ring(2,:), geo_ring(3,:), ...
      'Color',[0.3 1 0.3],'LineWidth',1.2,'LineStyle','--');
scatter3(r0(1),r0(2),r0(3),150,'r','p','filled');  % ΔV1 marker

h_trace = plot3(nan,nan,nan,'y-','LineWidth',2.0);
h_sc    = scatter3(nan,nan,nan,180,'y','filled');
h_tgt   = scatter3(nan,nan,nan,130,[0.3 1 0.3],'d','filled');
ht_lbl  = text(ax_a, -1.05*r_GEO, 0.9*r_GEO, 0, '', 'Color','w','FontSize',11);

lim = 1.1*r_GEO;
set(ax_a,'XLim',[-lim lim],'YLim',[-lim lim],'ZLim',[-0.3*lim 0.3*lim]);
xlabel('X_{ECI} [km]','Color','w'); ylabel('Y_{ECI} [km]','Color','w');
zlabel('Z_{ECI} [km]','Color','w');
title(sprintf('GTO→GEO Transfer Animation  |  Δt=%.1f d, Δv=%.3f km/s', ...
      dt_best, dv1_best+dv2_best), 'Color','w','FontSize',12);
view(30,20);

% Animate with uniform time grid (no ODE step-size artifacts)
n_frames = 240;
frame_idx = round(linspace(1, N_pts, n_frames));

for fi = 1:length(frame_idx)
    ii = frame_idx(fi);
    set(h_trace,'XData',traj_sc(1,1:ii),'YData',traj_sc(2,1:ii),'ZData',traj_sc(3,1:ii));
    set(h_sc,   'XData',traj_sc(1,ii),  'YData',traj_sc(2,ii),  'ZData',traj_sc(3,ii));
    set(h_tgt,  'XData',traj_tgt(1,ii), 'YData',traj_tgt(2,ii), 'ZData',traj_tgt(3,ii));
    set(ht_lbl, 'String', sprintf('t = %.2f hrs (%.0f%%)', t_span(ii)/3600, 100*fi/n_frames));
    drawnow limitrate;
    pause(0.02);
end
set(h_sc,'XData',traj_sc(1,end),'YData',traj_sc(2,end),'ZData',traj_sc(3,end));
scatter3(ax_a, traj_sc(1,end),traj_sc(2,end),traj_sc(3,end),200,'m','p','filled');
set(ht_lbl,'String',sprintf('GEO Insertion Complete  (Δt = %.2f days)', dt_best));
drawnow;

fprintf('\n=== All computations complete. ===\n');

%% ========================================================================
%  LOCAL FUNCTIONS
%% ========================================================================

function st = compute_geo_target(t_sec, r_GEO, omega_E, theta_ERA0, lambda_ecef)
    % GEO slot ECI state at t_sec after t0
    % ERA(t) = theta_ERA0 + omega_E * t  [rad]
    % ECI longitude of ECEF slot = ERA(t) + lambda_ecef
    phi   = theta_ERA0 + omega_E * t_sec + lambda_ecef;
    r_vec = r_GEO * [cos(phi); sin(phi); 0];
    v_vec = r_GEO * omega_E * [-sin(phi); cos(phi); 0];
    st    = [r_vec; v_vec];
end

function [v1_out, v2_out, lw_out] = lambert_best_2way(r0, v0, st_f, dt_s, mu)
    r_f = st_f(1:3); v_f = st_f(4:6);
    best = inf; v1_out=[]; v2_out=[]; lw_out=0;
    for lw = [0, 1]
        try
            [v1t, v2t] = lambert_izzo(r0, r_f, dt_s, mu, lw);
            dv = norm(v1t-v0) + norm(v_f-v2t);
            if dv < best
                best=dv; v1_out=v1t; v2_out=v2t; lw_out=lw;
            end
        catch; end
    end
end

function [v1, v2] = lambert_izzo(r1_vec, r2_vec, tof, mu, lw)
    % Izzo (2015) Lambert solver — reliable for all elliptic/hyperbolic cases
    % lw = 0 prograde/short, lw = 1 retrograde/long-way
    r1 = norm(r1_vec); r2 = norm(r2_vec);
    cos_dnu = max(-1, min(1, dot(r1_vec,r2_vec)/(r1*r2)));
    cr = cross(r1_vec, r2_vec);

    if lw == 0
        sin_dnu = (cr(3)>=0)*sqrt(1-cos_dnu^2) - (cr(3)<0)*sqrt(1-cos_dnu^2);
    else
        sin_dnu = -(cr(3)>=0)*sqrt(1-cos_dnu^2) + (cr(3)<0)*sqrt(1-cos_dnu^2);
    end

    dnu = atan2(sin_dnu, cos_dnu);
    if dnu < 0; dnu = dnu + 2*pi; end

    A = sin_dnu * sqrt(r1*r2 / (1 - cos_dnu));
    if abs(A) < 1e-10
        error('lambert:degenerate','Transfer angle ~0 or ~pi: degenerate case');
    end

    psi     = 0;
    psi_up  =  4*pi^2;
    psi_low = -4*pi;
    [c2, c3] = stumpff_cs(psi);

    for iter = 1:3000
        [c2, c3] = stumpff_cs(psi);
        y_val = r1 + r2 + A*(psi*c3 - 1)/sqrt(c2);

        if A > 0 && y_val < 0
            psi_low = psi;
            psi = psi + 0.01;
            continue;
        end

        chi   = sqrt(y_val/c2);
        tof_t = (chi^3*c3 + A*sqrt(y_val)) / sqrt(mu);

        if tof_t < tof
            psi_low = psi;
        else
            psi_up = psi;
        end

        psi_new = (psi_up + psi_low)/2;
        if abs(psi_new - psi) < 1e-12; break; end
        psi = psi_new;
    end

    [c2, c3] = stumpff_cs(psi);
    y_val = r1 + r2 + A*(psi*c3 - 1)/sqrt(c2);
    f     = 1 - y_val/r1;
    g     = A * sqrt(y_val/mu);
    gdot  = 1 - y_val/r2;

    v1 = (r2_vec - f*r1_vec) / g;
    v2 = (gdot*r2_vec - r1_vec) / g;
end

function [c2, c3] = stumpff_cs(psi)
    eps = 1e-7;
    if psi > eps
        sp = sqrt(psi);
        c2 = (1 - cos(sp)) / psi;
        c3 = (sp - sin(sp)) / (sp*psi);
    elseif psi < -eps
        sp = sqrt(-psi);
        c2 = (cosh(sp) - 1) / (-psi);
        c3 = (sinh(sp) - sp) / (sp*(-psi));
    else
        c2 = 0.5;
        c3 = 1/6;
    end
end

function state_out = kepler_propagate(state0, dt, mu)
    % Universal variable Kepler propagation (Bate, Mueller & White §4)
    r0v = state0(1:3); v0v = state0(4:6);
    r0n = norm(r0v);   v0n = norm(v0v);
    vr0 = dot(r0v, v0v) / r0n;
    alpha = 2/r0n - v0n^2/mu;   % reciprocal semi-major axis

    if alpha > 1e-6
        chi0 = sqrt(mu)*dt*alpha;
    elseif alpha < -1e-6
        a = 1/alpha;
        chi0 = sign(dt)*sqrt(-a) * ...
               log((-2*mu*alpha*dt)/(dot(r0v,v0v)+sign(dt)*sqrt(-mu*a)*(1-r0n*alpha)));
        if ~isfinite(chi0); chi0 = 0; end
    else
        p = norm(cross(r0v,v0v))^2/mu;
        s = 0.5*acot(3*sqrt(mu/p^3)*dt);
        w = atan((tan(s))^(1/3));
        chi0 = sqrt(2*p)*cot(2*w);
    end

    chi = chi0;
    for iter = 1:100
        psi = chi^2*alpha;
        [c2v, c3v] = stumpff_cs(psi);
        rn  = chi^2*c2v + vr0/sqrt(mu)*chi*(1-psi*c3v) + r0n*(1-psi*c2v);
        dt_t= (chi^3*c3v + vr0/sqrt(mu)*chi^2*c2v + r0n*chi*(1-psi*c2v))/sqrt(mu);
        dchi = (dt - dt_t)/rn;
        chi  = chi + dchi;
        if abs(dchi) < 1e-11; break; end
    end

    psi  = chi^2*alpha;
    [c2v, c3v] = stumpff_cs(psi);
    rn   = chi^2*c2v + vr0/sqrt(mu)*chi*(1-psi*c3v) + r0n*(1-psi*c2v);
    f    = 1 - chi^2/r0n * c2v;
    g    = dt - chi^3/sqrt(mu)*c3v;
    gdot = 1 - chi^2/rn*c2v;
    fdot = sqrt(mu)/(rn*r0n)*chi*(psi*c3v - 1);

    state_out = [f*r0v + g*v0v; fdot*r0v + gdot*v0v];
end

function oe = rv2oe(r_vec, v_vec, mu)
    r = norm(r_vec); v = norm(v_vec);
    h_vec = cross(r_vec, v_vec);
    n_vec = cross([0;0;1], h_vec);
    e_vec = ((v^2 - mu/r)*r_vec - dot(r_vec,v_vec)*v_vec)/mu;
    e = norm(e_vec);
    a = 1/(2/r - v^2/mu);
    i = acos(max(-1,min(1, h_vec(3)/norm(h_vec))));
    n = norm(n_vec);
    RAAN = atan2(n_vec(2), n_vec(1));
    if RAAN < 0; RAAN = RAAN + 2*pi; end
    if n > 1e-10 && e > 1e-10
        w = acos(max(-1,min(1,dot(n_vec,e_vec)/(n*e))));
        if e_vec(3) < 0; w = 2*pi - w; end
    else; w = 0; end
    if e > 1e-10
        nu = acos(max(-1,min(1,dot(e_vec,r_vec)/(e*r))));
        if dot(r_vec,v_vec) < 0; nu = 2*pi - nu; end
    else; nu = 0; end
    oe = [a; e; i; RAAN; w; nu];
end

function rv = oe2rv(oe, mu)
    a=oe(1); e=oe(2); i=oe(3); RAAN=oe(4); w=oe(5); nu=oe(6);
    p = a*(1-e^2);
    r_peri = p/(1+e*cos(nu)) * [cos(nu); sin(nu); 0];
    v_peri = sqrt(mu/p)      * [-sin(nu); e+cos(nu); 0];
    R3_RAAN = [cos(-RAAN) -sin(-RAAN) 0; sin(-RAAN) cos(-RAAN) 0; 0 0 1];
    R1_i    = [1 0 0; 0 cos(-i) -sin(-i); 0 sin(-i) cos(-i)];
    R3_w    = [cos(-w) -sin(-w) 0; sin(-w) cos(-w) 0; 0 0 1];
    Rot = R3_RAAN * R1_i * R3_w;
    rv  = [Rot*r_peri; Rot*v_peri];
end