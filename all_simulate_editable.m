%% Editable satellite pointing mission dashboard and interactive Earth viewer
clear; clc; close all;

%% 1. EDIT HERE ONLY
% This file is self-contained. Change the values in this block, then run:
% all_simulate_editable

projectDir = fileparts(mfilename("fullpath"));

cfg.outputDir = projectDir;
cfg.outputPrefix = "BK2_to_BK1";

% ADCS/LDCS CSV file path.
% Paste the full CSV path between the quotes when changing data files.
% Example:
% cfg.adcsFile = "C:\Users\USER\Downloads\your_adcs_file.csv";
cfg.adcsFile = "C:\Users\USER\OneDrive\桌面\實習\8-12\TLE\1785970000-RIoT-2-10slog.csv";

% Primary satellite: this satellite body axis is checked.
cfg.primary.name = "BK-2";
cfg.primary.tle = [
    "BK-2"
    "1 68474U 26067BL  26217.41809322  .00001833  00000+0  18271-3 0  9993"
    "2 68474  97.7575 174.9918 0003909  83.8734 276.2930 14.92787143 19076"
];

% Target satellite: the primary satellite points toward this satellite body.
cfg.target.name = "BK-1";
cfg.target.tle = [
    "BK-1"
    "1 66741U 25276CD  26217.45573656  .00005021  00000+0  22758-3 0  9999"
    "2 66741  97.4211 290.4626 0006195 162.4087 197.7365 15.21282281 35219"
];

% ADCS time and attitude columns.
cfg.timeColumn = "uEstTimeintegerseconds";
cfg.primary.quatColumns = [
    "iEstimatedORCquaternionQ0"
    "iEstimatedORCquaternionQ1"
    "iEstimatedORCquaternionQ2"
    "iEstimatedORCquaternionQ3"
];
cfg.primary.quatScale = 1e-4;
cfg.primary.quatOrder = "xyzw"; % "xyzw" or "wxyz"
cfg.primary.attitudeDirection = "bodyToOrc"; % "bodyToOrc" or "orcToBody"

% Target Euler columns are checked so the CSV format is verified.
% In this CSV, -3484 means -34.84 deg, so scale = 0.01.
cfg.target.eulerColumns = [
    "iEstimatedrollangle"
    "iEstimatedpitchangle"
    "iEstimatedyawangle"
];
cfg.target.eulerScaleDeg = 0.01;
cfg.target.attitudeDirection = "bodyToOrc";

% Pointing judgment. [1 0 0] means primary satellite +X red body axis.
cfg.pointing.bodyAxis = [1, 0, 0];
cfg.pointing.axisLabel = "+X red";
cfg.steady.targetAngleDeg = 1.82;
cfg.steady.toleranceDeg = 0.10;

% Scenario settings.
cfg.scenario.sampleTimeSec = 10;

% Custom MP4 plot3 video. This is disabled by default because the MATLAB
% satelliteScenarioViewer below looks better and has the time slider.
cfg.video.enable = false;
cfg.video.frameCount = 90;
cfg.video.frameRate = 12;
cfg.video.quality = 90;
cfg.video.vectorScaleKm = 1800;
cfg.video.earthRadiusKm = 6371;

% Interactive MATLAB satelliteScenarioViewer settings. This is the Earth
% viewer with the time slider, play/pause button, satellite models, and axes.
cfg.viewer.enable = true;
cfg.viewer.playOnOpen = true;
cfg.viewer.showDetails = true;
cfg.viewer.openInBatch = false;
cfg.viewer.primaryModel = "SmallSat.glb";
cfg.viewer.targetModel = "SmallSat.glb";
cfg.viewer.primaryModelScale = 0.4;
cfg.viewer.targetModelScale = 0.4;
cfg.viewer.bodyAxisDisplayScale = 0.7;

% Output file names. Change outputPrefix if you do not want to overwrite
% previous dashboard/video outputs.
cfg.outputs.dashboardCsv = cfg.outputPrefix + "_pointing_dashboard_data.csv";
cfg.outputs.summaryCsv = cfg.outputPrefix + "_mission_summary.csv";
cfg.outputs.chartPng = cfg.outputPrefix + "_pointing_dashboard_chart.png";
cfg.outputs.videoMp4 = cfg.outputPrefix + "_3D_pointing_animation.mp4";
cfg.outputs.dashboardHtml = cfg.outputPrefix + "_pointing_dashboard.html";

%% 2. Main program
outDir = cfg.outputDir;

if ~isfolder(outDir)
    mkdir(outDir);
end

if ~isfile(cfg.adcsFile)
    error("Cannot find ADCS CSV: %s", cfg.adcsFile);
end

validateConfig(cfg);

primaryTleFile = writeTempTleFile(cfg.primary.tle);
targetTleFile = writeTempTleFile(cfg.target.tle);

raw = readtable(cfg.adcsFile, "VariableNamingRule", "preserve");
requiredColumns = [cfg.timeColumn; cfg.primary.quatColumns; cfg.target.eulerColumns];
requireTableColumns(raw, requiredColumns, "ADCS CSV");

tUtc = datetime(raw{:, cfg.timeColumn}, "ConvertFrom", "posixtime", "TimeZone", "UTC");
qBodyOrc = readQuaternion(raw, cfg.primary.quatColumns, cfg.primary.quatScale, cfg.primary.quatOrder);
targetEulerDeg = double([raw{:, cfg.target.eulerColumns(1)}, raw{:, cfg.target.eulerColumns(2)}, ...
    raw{:, cfg.target.eulerColumns(3)}]) * cfg.target.eulerScaleDeg;

valid = ~isnat(tUtc) & all(isfinite(qBodyOrc), 2) & all(isfinite(targetEulerDeg), 2);
tUtc = tUtc(valid);
qBodyOrc = qBodyOrc(valid, :);
targetEulerDeg = targetEulerDeg(valid, :);
[tUtc, uniqueIdx] = unique(tUtc, "stable");
qBodyOrc = qBodyOrc(uniqueIdx, :);
targetEulerDeg = targetEulerDeg(uniqueIdx, :);

if numel(tUtc) < 2
    error("ADCS CSV must contain at least two valid time samples.");
end

sc = satelliteScenario(tUtc(1), tUtc(end), cfg.scenario.sampleTimeSec);
primarySat = satellite(sc, primaryTleFile, "Name", cfg.primary.name);
targetSat = satellite(sc, targetTleFile, "Name", cfg.target.name);

primarySat.Visual3DModel = cfg.viewer.primaryModel;
primarySat.Visual3DModelScale = cfg.viewer.primaryModelScale;
targetSat.Visual3DModel = cfg.viewer.targetModel;
targetSat.Visual3DModelScale = cfg.viewer.targetModelScale;

sampleCount = numel(tUtc);
pointingAngleDeg = nan(sampleCount, 1);
primaryPosKm = nan(sampleCount, 3);
targetPosKm = nan(sampleCount, 3);
pointingAxisEci = nan(sampleCount, 3);
rangeKm = nan(sampleCount, 1);
bodyAxis = cfg.pointing.bodyAxis(:) / norm(cfg.pointing.bodyAxis);
primaryQInertial = zeros(sampleCount, 4);
targetQInertial = zeros(sampleCount, 4);

for k = 1:sampleCount
    [primaryR, primaryV] = states(primarySat, tUtc(k), "CoordinateFrame", "inertial");
    [targetR, targetV] = states(targetSat, tUtc(k), "CoordinateFrame", "inertial");

    R_eci_from_orc = eciFromLvlh(primaryR(:), primaryV(:));
    R_orc_from_body = quatScalarLastToDcm(qBodyOrc(k, :));

    if cfg.primary.attitudeDirection == "bodyToOrc"
        R_eci_from_body = R_eci_from_orc * R_orc_from_body;
    else
        R_eci_from_body = R_eci_from_orc * R_orc_from_body.';
    end

    R_target_eci_from_orc = eciFromLvlh(targetR(:), targetV(:));
    R_target_orc_from_body = euler321DegToDcm(targetEulerDeg(k, :));

    if cfg.target.attitudeDirection == "bodyToOrc"
        R_target_eci_from_body = R_target_eci_from_orc * R_target_orc_from_body;
    else
        R_target_eci_from_body = R_target_eci_from_orc * R_target_orc_from_body.';
    end

    primaryToTarget = targetR(:) - primaryR(:);
    pointingAxisEci(k, :) = (R_eci_from_body * bodyAxis).';
    pointingAngleDeg(k) = angleBetweenVectorsDeg(pointingAxisEci(k, :), primaryToTarget);
    primaryPosKm(k, :) = primaryR(:).' / 1000;
    targetPosKm(k, :) = targetR(:).' / 1000;
    rangeKm(k) = norm(primaryToTarget) / 1000;
    primaryQInertial(k, :) = dcm2quat(R_eci_from_body.');
    targetQInertial(k, :) = dcm2quat(R_target_eci_from_body.');
end

pointAt(primarySat, timetable(tUtc, primaryQInertial), "ExtrapolationMethod", "nadir");
pointAt(targetSat, timetable(tUtc, targetQInertial), "ExtrapolationMethod", "nadir");

[bestAngleDeg, bestIdx] = min(pointingAngleDeg);
steadyErrorDeg = abs(pointingAngleDeg - cfg.steady.targetAngleDeg);
isNearSteady = steadyErrorDeg <= cfg.steady.toleranceDeg;

[descentStartIdx, steadyEntryIdx, turnToSteadySec] = findTurnToSteady( ...
    tUtc, pointingAngleDeg, isNearSteady);

missionStatus = "PASS";
if isnan(steadyEntryIdx)
    missionStatus = "NO_STEADY_ENTRY";
end

dashboardCsv = fullfile(outDir, cfg.outputs.dashboardCsv);
summaryCsv = fullfile(outDir, cfg.outputs.summaryCsv);
chartPng = fullfile(outDir, cfg.outputs.chartPng);
dashboardHtml = fullfile(outDir, cfg.outputs.dashboardHtml);
videoFile = "";

if cfg.video.enable
    videoFile = fullfile(outDir, cfg.outputs.videoMp4);
end

dashboardData = table(tUtc(:), pointingAngleDeg(:), steadyErrorDeg(:), ...
    isNearSteady(:), rangeKm(:), ...
    VariableNames=["UtcTime", "AngleDeg", "SteadyErrorDeg", "IsNearSteady", "RangeKm"]);
writetable(dashboardData, dashboardCsv);

summaryTable = table( ...
    ["Start descending"; "First steady entry"; "Best pointing"], ...
    [safeTime(tUtc, descentStartIdx); safeTime(tUtc, steadyEntryIdx); tUtc(bestIdx)], ...
    [safeValue(pointingAngleDeg, descentStartIdx); safeValue(pointingAngleDeg, steadyEntryIdx); bestAngleDeg], ...
    VariableNames=["Event", "UtcTime", "AngleDeg"]);
writetable(summaryTable, summaryCsv);

makePointingChart(cfg, tUtc, pointingAngleDeg, isNearSteady, ...
    descentStartIdx, steadyEntryIdx, turnToSteadySec, bestIdx, chartPng);

if cfg.video.enable
    makePointingVideo(cfg, tUtc, primaryPosKm, targetPosKm, pointingAxisEci, ...
        pointingAngleDeg, isNearSteady, videoFile);
end

writeDashboardHtml(cfg, dashboardHtml, dashboardCsv, summaryCsv, chartPng, videoFile, ...
    missionStatus, bestAngleDeg, tUtc(bestIdx), turnToSteadySec, ...
    descentStartIdx, steadyEntryIdx, tUtc, pointingAngleDeg, isNearSteady, rangeKm);

openInteractiveViewer(cfg, sc, primarySat, targetSat);

fprintf("\nMission status: %s\n", missionStatus);
fprintf("Primary satellite: %s\n", cfg.primary.name);
fprintf("Target satellite: %s\n", cfg.target.name);
fprintf("Pointing axis: %s\n", cfg.pointing.axisLabel);
fprintf("Best pointing: %.3f deg at %s UTC\n", bestAngleDeg, string(tUtc(bestIdx)));
if ~isnan(steadyEntryIdx)
    fprintf("Descent start: %s UTC, %.3f deg\n", ...
        string(tUtc(descentStartIdx)), pointingAngleDeg(descentStartIdx));
    fprintf("Steady entry: %s UTC, %.3f deg\n", ...
        string(tUtc(steadyEntryIdx)), pointingAngleDeg(steadyEntryIdx));
    fprintf("Rotation to steady state: %.1f s\n", turnToSteadySec);
else
    fprintf("No steady-state entry was found after the first descending point.\n");
end
fprintf("Dashboard exported: %s\n", dashboardHtml);
if cfg.video.enable
    fprintf("Custom 3D MP4 animation exported: %s\n", videoFile);
else
    fprintf("Custom 3D MP4 animation skipped. Use the MATLAB interactive Earth viewer timeline instead.\n");
end

function qBodyOrc = readQuaternion(raw, quatColumns, quatScale, quatOrder)
    qData = double([raw{:, quatColumns(1)}, raw{:, quatColumns(2)}, ...
        raw{:, quatColumns(3)}, raw{:, quatColumns(4)}]) * quatScale;

    if quatOrder == "xyzw"
        qBodyOrc = qData;
    elseif quatOrder == "wxyz"
        qBodyOrc = [qData(:, 2), qData(:, 3), qData(:, 4), qData(:, 1)];
    else
        error("cfg.primary.quatOrder must be 'xyzw' or 'wxyz'.");
    end

    qNorm = vecnorm(qBodyOrc, 2, 2);
    if any(qNorm == 0)
        error("Quaternion data contains zero-norm rows.");
    end
    qBodyOrc = qBodyOrc ./ qNorm;
end

function [descentStartIdx, steadyEntryIdx, turnToSteadySec] = findTurnToSteady(tUtc, angleDeg, isNearSteady)
    angleDiff = diff(angleDeg);
    descentStartIdx = find(angleDiff < 0, 1, "first");
    steadyEntryIdx = NaN;
    turnToSteadySec = NaN;

    if isempty(descentStartIdx)
        return
    end

    steadyEntryAfterDescent = find(isNearSteady(descentStartIdx:end), 1, "first");
    if isempty(steadyEntryAfterDescent)
        return
    end

    steadyEntryIdx = descentStartIdx + steadyEntryAfterDescent - 1;
    turnToSteadySec = seconds(tUtc(steadyEntryIdx) - tUtc(descentStartIdx));
end

function makePointingChart(cfg, tUtc, angleDeg, isNearSteady, ...
    descentStartIdx, steadyEntryIdx, turnSec, bestIdx, outputPng)
    steadyTarget = cfg.steady.targetAngleDeg;
    steadyTol = cfg.steady.toleranceDeg;

    fig = figure("Name", "Pointing mission judgment", "Color", "w", ...
        "Position", [100, 100, 1500, 760]);
    ax = axes(fig);
    hold(ax, "on");

    yMax = max(110, ceil(max(angleDeg, [], "omitnan") / 10) * 10);
    bandX = [tUtc(1), tUtc(end), tUtc(end), tUtc(1)];
    bandY = [steadyTarget - steadyTol, steadyTarget - steadyTol, ...
        steadyTarget + steadyTol, steadyTarget + steadyTol];
    patch(ax, bandX, bandY, [0.75, 0.95, 0.74], ...
        "EdgeColor", "none", "FaceAlpha", 0.45);

    plot(ax, tUtc, angleDeg, "Color", [0.86, 0.2, 0.16], "LineWidth", 2.2);
    hold on;
    scatter(ax, tUtc, angleDeg, 28, [0.86, 0.2, 0.16], "filled", ...
        "MarkerFaceAlpha", 0.28);
    scatter(ax, tUtc(isNearSteady), angleDeg(isNearSteady), 54, [0.16, 0.68, 0.22], "filled");
    yline(ax, steadyTarget, "--", sprintf("Steady %.2f deg", steadyTarget), ...
        "LineWidth", 1.3, "Color", [0.1, 0.45, 0.15]);
    scatter(ax, tUtc(bestIdx), angleDeg(bestIdx), 86, [0.1, 0.32, 0.82], "filled");
    text(ax, tUtc(bestIdx), angleDeg(bestIdx), sprintf("  Best %.2f deg", angleDeg(bestIdx)), ...
        "VerticalAlignment", "bottom", "FontWeight", "bold", "Color", [0.08, 0.18, 0.42]);

    if ~isempty(descentStartIdx)
        xline(ax, tUtc(descentStartIdx), ":", "Start descent", "LineWidth", 1.4, ...
            "Color", [0.25, 0.25, 0.25], ...
            "LabelOrientation", "horizontal", "LabelVerticalAlignment", "top");
    end

    if ~isnan(steadyEntryIdx)
        xline(ax, tUtc(steadyEntryIdx), ":", "LineWidth", 1.4, ...
            "Color", [0.25, 0.25, 0.25], ...
            "LabelOrientation", "horizontal");
        text(ax, tUtc(steadyEntryIdx), angleDeg(steadyEntryIdx) + yMax * 0.055, ...
            "Steady entry", "HorizontalAlignment", "center", ...
            "FontWeight", "bold", "Color", [0.12, 0.45, 0.18], ...
            "BackgroundColor", "w", "Margin", 3);
        annotationY = yMax * 0.78;
        plot(ax, [tUtc(descentStartIdx), tUtc(steadyEntryIdx)], [annotationY, annotationY], ...
            "-", "Color", [0.08, 0.08, 0.08], "LineWidth", 1.8);
        scatter(ax, [tUtc(descentStartIdx), tUtc(steadyEntryIdx)], [annotationY, annotationY], ...
            34, [0.08, 0.08, 0.08], "filled");
        text(ax, tUtc(descentStartIdx) + seconds(turnSec / 2), annotationY + yMax * 0.045, ...
            sprintf("Time to steady state: %.1f s", turnSec), ...
            "HorizontalAlignment", "center", "FontWeight", "bold", ...
            "BackgroundColor", "w", "Margin", 4);
    end

    grid(ax, "on");
    ax.GridAlpha = 0.16;
    ax.MinorGridAlpha = 0.08;
    ax.FontName = "Segoe UI";
    ax.FontSize = 12;
    ax.LineWidth = 1;
    ylim(ax, [0, yMax]);
    xlabel(ax, "UTC time");
    ylabel(ax, "Pointing angle (deg)");
    title(ax, sprintf("%s %s axis pointing to %s body", ...
        cfg.primary.name, cfg.pointing.axisLabel, cfg.target.name), ...
        "FontWeight", "bold");
    subtitle(ax, sprintf("Steady target %.2f +/- %.2f deg | minimum %.2f deg at %s UTC", ...
        steadyTarget, steadyTol, angleDeg(bestIdx), string(tUtc(bestIdx))));
    exportgraphics(fig, outputPng, "Resolution", 220);
    close(fig);
end

function makePointingVideo(cfg, tUtc, primaryPosKm, targetPosKm, pointingAxisEci, ...
    angleDeg, isNearSteady, outputVideo)
    frameCount = min(cfg.video.frameCount, numel(tUtc));
    frameIdx = unique(round(linspace(1, numel(tUtc), frameCount)));
    earthRadiusKm = cfg.video.earthRadiusKm;
    vectorScaleKm = cfg.video.vectorScaleKm;

    fig = figure("Name", "3D pointing animation", "Color", "k", ...
        "Position", [100, 100, 1280, 720]);
    ax = axes(fig);

    writer = VideoWriter(outputVideo, "MPEG-4");
    writer.FrameRate = cfg.video.frameRate;
    writer.Quality = cfg.video.quality;
    open(writer);

    maxRange = max(vecnorm([primaryPosKm; targetPosKm], 2, 2));
    axisLimit = max(earthRadiusKm + 1800, maxRange + 1200);

    for frameNumber = 1:numel(frameIdx)
        k = frameIdx(frameNumber);
        cla(ax);
        hold(ax, "on");
        [x, y, z] = sphere(80);
        surf(ax, earthRadiusKm*x, earthRadiusKm*y, earthRadiusKm*z, ...
            "FaceColor", [0.08, 0.24, 0.42], "EdgeColor", "none", "FaceAlpha", 0.88);
        light(ax, "Position", [1, -1, 1]);
        lighting(ax, "gouraud");

        plot3(ax, primaryPosKm(1:k, 1), primaryPosKm(1:k, 2), primaryPosKm(1:k, 3), ...
            "c-", "LineWidth", 1.2);
        plot3(ax, targetPosKm(1:k, 1), targetPosKm(1:k, 2), targetPosKm(1:k, 3), ...
            "-", "Color", [0.95, 0.8, 0.18], "LineWidth", 1.2);

        pPrimary = primaryPosKm(k, :);
        pTarget = targetPosKm(k, :);
        pointingVec = pointingAxisEci(k, :) / norm(pointingAxisEci(k, :)) * vectorScaleKm;
        losVec = pTarget - pPrimary;
        losVec = losVec / norm(losVec) * vectorScaleKm;

        plot3(ax, [pPrimary(1), pTarget(1)], [pPrimary(2), pTarget(2)], ...
            [pPrimary(3), pTarget(3)], "--", "Color", [1, 1, 1], "LineWidth", 1.0);
        quiver3(ax, pPrimary(1), pPrimary(2), pPrimary(3), ...
            pointingVec(1), pointingVec(2), pointingVec(3), 0, "r", ...
            "LineWidth", 3, "MaxHeadSize", 0.8);
        quiver3(ax, pPrimary(1), pPrimary(2), pPrimary(3), ...
            losVec(1), losVec(2), losVec(3), 0, "Color", [0.25, 1, 0.25], ...
            "LineWidth", 2, "MaxHeadSize", 0.7);

        scatter3(ax, pPrimary(1), pPrimary(2), pPrimary(3), 75, "r", "filled");
        scatter3(ax, pTarget(1), pTarget(2), pTarget(3), 75, [0.95, 0.8, 0.18], "filled");
        text(ax, pPrimary(1), pPrimary(2), pPrimary(3), "  " + cfg.primary.name, ...
            "Color", "w", "FontWeight", "bold");
        text(ax, pTarget(1), pTarget(2), pTarget(3), "  " + cfg.target.name, ...
            "Color", "w", "FontWeight", "bold");

        statusText = "Not steady";
        if isNearSteady(k)
            statusText = "Near steady";
        end
        title(ax, sprintf("%s to %s 3D pointing | %s UTC | angle %.2f deg | %s", ...
            cfg.primary.name, cfg.target.name, string(tUtc(k)), angleDeg(k), statusText), ...
            "Color", "w");
        subtitle(ax, sprintf("Red = %s %s axis; green = %s to %s direction; steady %.2f +/- %.2f deg", ...
            cfg.primary.name, cfg.pointing.axisLabel, cfg.primary.name, cfg.target.name, ...
            cfg.steady.targetAngleDeg, cfg.steady.toleranceDeg), ...
            "Color", [0.85, 0.85, 0.85]);

        axis(ax, "equal");
        xlim(ax, [-axisLimit, axisLimit]);
        ylim(ax, [-axisLimit, axisLimit]);
        zlim(ax, [-axisLimit, axisLimit]);
        grid(ax, "on");
        ax.Color = "k";
        ax.XColor = [0.8, 0.8, 0.8];
        ax.YColor = [0.8, 0.8, 0.8];
        ax.ZColor = [0.8, 0.8, 0.8];
        xlabel(ax, "ECI X (km)");
        ylabel(ax, "ECI Y (km)");
        zlabel(ax, "ECI Z (km)");
        view(ax, 36 + frameNumber * 0.5, 24);
        drawnow;
        writeVideo(writer, getframe(fig));
    end

    close(writer);
    close(fig);
end

function writeDashboardHtml(cfg, outputHtml, dashboardCsv, summaryCsv, chartPng, videoFile, ...
    missionStatus, bestAngle, bestTime, turnSec, descentStartIdx, steadyEntryIdx, ...
    tUtc, angleDeg, isNearSteady, rangeKm)
    [~, chartName, chartExt] = fileparts(chartPng);
    [~, dashboardName, dashboardExt] = fileparts(dashboardCsv);
    [~, summaryName, summaryExt] = fileparts(summaryCsv);

    if isnan(steadyEntryIdx)
        turnText = "No steady entry";
        descentText = "N/A";
        steadyText = "N/A";
    else
        turnText = sprintf("%.1f s", turnSec);
        descentText = sprintf("%s UTC / %.2f deg", string(tUtc(descentStartIdx)), angleDeg(descentStartIdx));
        steadyText = sprintf("%s UTC / %.2f deg", string(tUtc(steadyEntryIdx)), angleDeg(steadyEntryIdx));
    end

    angleSeries = join(compose("%.4f", angleDeg), ",");
    timeSeries = join(quoteForJs(string(tUtc, "yyyy-MM-dd HH:mm:ss")), ",");
    steadySeries = join(string(double(isNearSteady)), ",");
    steadyPercent = 100 * nnz(isNearSteady) / numel(isNearSteady);
    if isempty(descentStartIdx) || isnan(steadyEntryIdx)
        angleDropText = "N/A";
    else
        angleDropText = sprintf("%.2f deg", angleDeg(descentStartIdx) - angleDeg(steadyEntryIdx));
    end

    if cfg.video.enable && strlength(string(videoFile)) > 0
        [~, videoName, videoExt] = fileparts(videoFile);
        viewerPanel = [
            "<div class=""panel viewer-card""><h2>Custom MP4 Animation</h2>"
            sprintf("<video controls preload=""metadata"" src=""%s%s""></video>", videoName, videoExt)
            sprintf("<div class=""legend""><span><i class=""dot red""></i>%s %s axis</span><span><i class=""dot green""></i>%s to %s direction</span><span><i class=""dot gold""></i>%s track</span><span><i class=""dot blue""></i>%s track</span></div></div>", cfg.primary.name, cfg.pointing.axisLabel, cfg.primary.name, cfg.target.name, cfg.target.name, cfg.primary.name)
        ];
    else
        viewerPanel = [
            "<div class=""panel viewer-card""><span class=""eyebrow"">Interactive viewer</span><h2>MATLAB Earth Timeline</h2>"
            "<p class=""muted"">Open the script in normal MATLAB to use satelliteScenarioViewer with Earth, satellite models, play/pause, and a draggable time slider.</p>"
            sprintf("<div class=""viewer-meta""><span>%s</span><span>%s</span><span>%s axis</span></div>", cfg.primary.name, cfg.target.name, cfg.pointing.axisLabel)
            "</div>"
        ];
    end

    html = [
"<!doctype html>"
"<html lang=""zh-Hant"">"
"<head>"
"<meta charset=""utf-8"">"
"<meta name=""viewport"" content=""width=device-width,initial-scale=1"">"
"<title>Pointing Mission Dashboard</title>"
"<style>"
":root{color-scheme:dark;--bg:#090d12;--panel:#111821;--soft:#172332;--line:#263342;--text:#f4f7fb;--muted:#94a3b8;--red:#ef4444;--green:#6ee779;--blue:#7db7ff;--gold:#f3c64e;--ink:#dce7f3}*{box-sizing:border-box}body{margin:0;background:linear-gradient(180deg,#071018 0%,#0b1118 48%,#090d12 100%);color:var(--text);font-family:Segoe UI,Microsoft JhengHei,Arial,sans-serif}main{max-width:1240px;margin:0 auto;padding:28px}.hero{padding:24px 0 18px;border-bottom:1px solid rgba(255,255,255,.08);margin-bottom:18px}.eyebrow{display:block;color:#80d0ff;font-size:12px;text-transform:uppercase;letter-spacing:.12em;margin-bottom:8px}h1{font-size:34px;line-height:1.15;margin:0 0 8px}h2{font-size:18px;margin:0 0 14px}.muted,.sub{color:var(--muted);line-height:1.55;margin:0}.grid{display:grid;gap:14px}.cards{grid-template-columns:repeat(4,minmax(0,1fr));margin-bottom:14px}.card,.panel{background:rgba(17,24,33,.92);border:1px solid rgba(148,163,184,.22);border-radius:8px;padding:17px;box-shadow:0 12px 34px rgba(0,0,0,.22)}.card{min-height:112px}.label{color:var(--muted);font-size:13px}.value{font-size:27px;font-weight:760;margin-top:8px;line-height:1.15}.pass{color:var(--green)}.two{grid-template-columns:minmax(0,.88fr) minmax(440px,1.12fr);align-items:stretch}.viewer-card{background:linear-gradient(135deg,rgba(18,31,43,.96),rgba(16,24,31,.92));position:relative;overflow:hidden}.viewer-meta{display:flex;gap:8px;flex-wrap:wrap;margin-top:18px}.viewer-meta span{border:1px solid rgba(125,183,255,.35);background:rgba(125,183,255,.08);padding:8px 10px;border-radius:999px;color:#d8ecff;font-size:13px}img,video{width:100%;border-radius:8px;border:1px solid var(--line);background:#05070a}table{width:100%;border-collapse:collapse;font-size:14px}td,th{border-bottom:1px solid rgba(148,163,184,.18);padding:12px 8px;text-align:left}th{color:var(--muted);font-weight:600}.links{margin-top:14px}.links a{display:inline-block;color:#b8dcff;text-decoration:none;margin:6px 10px 0 0;border:1px solid rgba(125,183,255,.32);border-radius:999px;padding:8px 11px;background:rgba(125,183,255,.08)}.chart-panel{padding:12px}.chart-panel img{display:block}.chartBox{height:260px;border:1px solid rgba(148,163,184,.2);border-radius:8px;background:#0b1119;padding:12px}@media(max-width:900px){main{padding:18px}.cards,.two{grid-template-columns:1fr}.value{font-size:23px}h1{font-size:28px}}"
"</style>"
"</head>"
"<body><main>"
"<section class=""hero"">"
"<span class=""eyebrow"">Satellite pointing mission</span>"
sprintf("<h1>%s to %s Attitude Alignment</h1>", cfg.primary.name, cfg.target.name)
sprintf("<p class=""sub"">Judges whether the %s body %s axis points toward the %s body. Edit the top block of <b>all_simulate_editable.m</b> to change TLE, ADCS columns, steady target, or output names.</p>", cfg.primary.name, cfg.pointing.axisLabel, cfg.target.name)
"</section>"
"<section class=""grid cards"">"
sprintf("<div class=""card""><div class=""label"">Mission status</div><div class=""value pass"">%s</div></div>", missionStatus)
sprintf("<div class=""card""><div class=""label"">Time to steady state</div><div class=""value"">%s</div></div>", turnText)
sprintf("<div class=""card""><div class=""label"">Best pointing angle</div><div class=""value"">%.2f deg</div></div>", bestAngle)
sprintf("<div class=""card""><div class=""label"">Near-steady samples</div><div class=""value"">%.0f%%</div></div>", steadyPercent)
"</section>"
"<section class=""grid two"">"
viewerPanel
"<div class=""panel""><h2>Mission Events</h2><table><tbody>"
sprintf("<tr><th>Start descending</th><td>%s</td></tr>", descentText)
sprintf("<tr><th>First steady entry</th><td>%s</td></tr>", steadyText)
sprintf("<tr><th>Angle drop to steady</th><td>%s</td></tr>", angleDropText)
sprintf("<tr><th>Best pointing</th><td>%s UTC / %.2f deg</td></tr>", string(bestTime), bestAngle)
sprintf("<tr><th>Near-steady samples</th><td>%d / %d</td></tr>", nnz(isNearSteady), numel(isNearSteady))
sprintf("<tr><th>Average range</th><td>%.1f km</td></tr>", mean(rangeKm, "omitnan"))
"</tbody></table><div class=""links"">"
sprintf("<a href=""%s%s"">Angle data CSV</a>", dashboardName, dashboardExt)
sprintf("<a href=""%s%s"">Mission summary CSV</a>", summaryName, summaryExt)
"</div></div>"
"</section>"
"<section class=""panel chart-panel"" style=""margin-top:14px""><h2>Pointing Angle Chart</h2>"
sprintf("<img src=""%s%s"" alt=""Pointing chart"">", chartName, chartExt)
"</section>"
"<section class=""panel"" style=""margin-top:14px""><h2>Quick Check Line</h2><div class=""chartBox""><canvas id=""quickChart""></canvas></div></section>"
"<script>"
"const times=[" + timeSeries + "];"
"const angles=[" + angleSeries + "];"
"const steady=[" + steadySeries + "];"
"const canvas=document.getElementById('quickChart');const ctx=canvas.getContext('2d');function draw(){const r=canvas.getBoundingClientRect();canvas.width=r.width*devicePixelRatio;canvas.height=r.height*devicePixelRatio;ctx.scale(devicePixelRatio,devicePixelRatio);const w=r.width,h=r.height,p=32;ctx.clearRect(0,0,w,h);const maxA=Math.max(...angles,110),minA=0;ctx.strokeStyle='#2f3946';ctx.lineWidth=1;for(let i=0;i<=5;i++){const y=p+(h-2*p)*i/5;ctx.beginPath();ctx.moveTo(p,y);ctx.lineTo(w-p,y);ctx.stroke()}function xy(i,a){return [p+(w-2*p)*i/(angles.length-1),h-p-(h-2*p)*(a-minA)/(maxA-minA)]}ctx.strokeStyle='#f04438';ctx.lineWidth=2;ctx.beginPath();angles.forEach((a,i)=>{const [x,y]=xy(i,a);i?ctx.lineTo(x,y):ctx.moveTo(x,y)});ctx.stroke();ctx.fillStyle='#69e75d';steady.forEach((s,i)=>{if(s){const [x,y]=xy(i,angles[i]);ctx.beginPath();ctx.arc(x,y,4,0,Math.PI*2);ctx.fill()}});ctx.fillStyle='#aab4c0';ctx.fillText('Angle (deg)',8,16);ctx.fillText(times[0]+' UTC',p,h-8);ctx.textAlign='right';ctx.fillText(times[times.length-1]+' UTC',w-p,h-8)}addEventListener('resize',draw);draw();"
"</script>"
"</main></body></html>"
    ];

    writelines(html, outputHtml);
end

function openInteractiveViewer(cfg, sc, primarySat, targetSat)
    if ~cfg.viewer.enable
        return
    end

    if strlength(string(getenv("SKIP_SCENARIO_VIEWER"))) > 0
        disp("Interactive satelliteScenarioViewer skipped by SKIP_SCENARIO_VIEWER.");
        return
    end

    runningBatch = exist("batchStartupOptionUsed", "file") == 2 && batchStartupOptionUsed;
    if runningBatch && ~cfg.viewer.openInBatch
        disp("Interactive satelliteScenarioViewer skipped in MATLAB batch mode.");
        return
    end

    if ~usejava("desktop")
        disp("Interactive satelliteScenarioViewer skipped because MATLAB desktop is not available.");
        return
    end

    coordinateAxes(primarySat, "Scale", cfg.viewer.bodyAxisDisplayScale);
    coordinateAxes(targetSat, "Scale", cfg.viewer.bodyAxisDisplayScale);

    viewer = satelliteScenarioViewer(sc, "ShowDetails", cfg.viewer.showDetails);
    show(primarySat);
    show(targetSat);
    disp("Interactive Earth viewer opened. Use the timeline slider to inspect pointing time.");

    if cfg.viewer.playOnOpen
        play(sc);
    end

    assignin("base", "pointingViewer", viewer);
end

function validateConfig(cfg)
    if ~isfield(cfg, "primary") || ~isfield(cfg, "target")
        error("Config must define cfg.primary and cfg.target.");
    end
    if numel(cfg.primary.tle) < 3 || numel(cfg.target.tle) < 3
        error("Each TLE must contain a name line plus TLE line 1 and line 2.");
    end
    if norm(cfg.pointing.bodyAxis) == 0
        error("cfg.pointing.bodyAxis cannot be zero.");
    end
    if cfg.video.enable && (cfg.video.frameCount < 2 || cfg.video.frameRate <= 0)
        error("Video frameCount and frameRate must be positive.");
    end
end

function quoted = quoteForJs(values)
    values = string(values);
    quoted = """" + replace(values, """", "\""") + """";
end

function t = safeTime(times, idx)
    if isempty(idx) || isnan(idx)
        t = NaT("TimeZone", "UTC");
    else
        t = times(idx);
    end
end

function x = safeValue(values, idx)
    if isempty(idx) || isnan(idx)
        x = NaN;
    else
        x = values(idx);
    end
end

function tleFile = writeTempTleFile(tleLines)
    tleLines = string(tleLines);
    tleLines = tleLines(strlength(strtrim(tleLines)) > 0);
    if numel(tleLines) < 2
        error("tleInput must contain at least two TLE orbit lines.");
    end
    tleFile = tempname + ".tle";
    writelines(tleLines, tleFile);
end

function requireTableColumns(tbl, columns, labelText)
    names = string(tbl.Properties.VariableNames);
    missing = setdiff(string(columns), names);
    if ~isempty(missing)
        error("Missing required columns in %s: %s", labelText, strjoin(missing, ", "));
    end
end

function R = eciFromLvlh(r, v)
    r = r(:);
    v = v(:);
    z = -r / norm(r);
    h = cross(r, v);
    y = -h / norm(h);
    x = cross(y, z);
    R = [x, y, z];
end

function dcm = quatScalarLastToDcm(q)
    qx = q(1);
    qy = q(2);
    qz = q(3);
    qw = q(4);
    dcm = [
        1 - 2*(qy^2 + qz^2), 2*(qx*qy - qw*qz),     2*(qx*qz + qw*qy);
        2*(qx*qy + qw*qz),   1 - 2*(qx^2 + qz^2),   2*(qy*qz - qw*qx);
        2*(qx*qz - qw*qy),   2*(qy*qz + qw*qx),     1 - 2*(qx^2 + qy^2)];
end

function dcm = euler321DegToDcm(eulerDeg)
    roll = deg2rad(eulerDeg(1));
    pitch = deg2rad(eulerDeg(2));
    yaw = deg2rad(eulerDeg(3));

    cr = cos(roll);
    sr = sin(roll);
    cp = cos(pitch);
    sp = sin(pitch);
    cy = cos(yaw);
    sy = sin(yaw);

    rx = [
        1, 0, 0;
        0, cr, -sr;
        0, sr, cr];

    ry = [
        cp, 0, sp;
        0, 1, 0;
        -sp, 0, cp];

    rz = [
        cy, -sy, 0;
        sy, cy, 0;
        0, 0, 1];

    dcm = rz * ry * rx;
end

function angleDeg = angleBetweenVectorsDeg(a, b)
    a = a(:);
    b = b(:);
    if norm(a) == 0 || norm(b) == 0
        angleDeg = nan;
        return
    end
    a = a / norm(a);
    b = b / norm(b);
    angleDeg = acosd(max(-1, min(1, dot(a, b))));
end
