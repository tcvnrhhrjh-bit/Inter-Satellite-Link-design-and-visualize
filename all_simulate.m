%% 
%% Reconstruct satellite attitude from selectable TLE and selectable ADCS
clear; clc; close all;

%% 1. Paths
thisFile = mfilename("fullpath");
outDir = fileparts(thisFile);
rootDir = fileparts(outDir);
archiveDir = fullfile(rootDir, "work", "archive");

fallbackRoot = "C:\Users\USER\Documents\Codex\2026-07-07\tle-matlab";
fallbackOutDir = fullfile(fallbackRoot, "outputs");
fallbackArchiveDir = fullfile(fallbackRoot, "work", "archive");

%% 2. TLE：在這裡換 TLE
tleInput = [
    "BK-2"
    "1 68474U 26067BL  26217.41809322  .00001833  00000+0  18271-3 0  9993"
    "2 68474  97.7575 174.9918 0003909  83.8734 276.2930 14.92787143 19076"
];

%% 3. ADCS：在這裡換 ADCS

% 打入ADCS資料的：完整路徑
adcsInput = fullfile(outDir, "TLE", "1785970000-RIoT-2-10slog.csv");

% 如果 ADCS 欄位名稱不同，只改這裡
timeColumn = "uEstTimeintegerseconds";

quatColumns = [
    "iEstimatedORCquaternionQ0"
    "iEstimatedORCquaternionQ1"
    "iEstimatedORCquaternionQ2"
    "iEstimatedORCquaternionQ3"
];

% 如果 ADCS 四元數已經是正常小數，例如 0.1234，就改成 1
% 如果像原本資料一樣需要乘 1e-4，就保持 1e-4
quatScale = 1e-4;

% 你的欄位順序：
% "xyzw" = [qx qy qz qw]
% "wxyz" = [qw qx qy qz]
quatOrder = "xyzw";

attitudeDirection = "bodyToOrc"; % Options: "bodyToOrc" or "orcToBody"

% Second satellite: use the 10-second RIoT-2 log. Its roll/pitch/yaw
% columns are centi-degrees, so -3484 means -34.84 deg.
secondTleInput = [
    "BK-1"
    "1 66741U 25276CD  26217.45573656  .00005021  00000+0  22758-3 0  9999"
    "2 66741  97.4211 290.4626 0006195 162.4087 197.7365 15.21282281 35219"
];

secondAdcsInput = fullfile(outDir, "TLE", "1785970000-RIoT-2-10slog.csv");
secondTimeColumn = "uEstTimeintegerseconds";
secondEulerColumns = [
    "iEstimatedrollangle"
    "iEstimatedpitchangle"
    "iEstimatedyawangle"
];
secondEulerScaleDeg = 0.01;
secondAttitudeDirection = "bodyToOrc";
steadyTargetAngleDeg = 1.82;
steadyToleranceDeg = 0.10;

%% 4. Resolve TLE and ADCS files
tleFile = resolveTleInput(tleInput, outDir, fallbackOutDir);
satelliteName = tleNameFromFile(tleFile);

quatCsv = resolveAdcsInput(adcsInput, outDir, archiveDir, fallbackArchiveDir);
secondTleFile = resolveTleInput(secondTleInput, outDir, fallbackOutDir);
secondSatelliteName = tleNameFromFile(secondTleFile);
secondAdcsCsv = resolveAdcsInput(secondAdcsInput, outDir, archiveDir, fallbackArchiveDir);

if ~isfile(tleFile)
    error("Cannot find TLE file. Checked: %s", tleFile);
end

if ~isfile(quatCsv)
    error("Cannot find ADCS quaternion CSV. Checked: %s", quatCsv);
end

if ~isfile(secondTleFile)
    error("Cannot find second satellite TLE file. Checked: %s", secondTleFile);
end

if ~isfile(secondAdcsCsv)
    error("Cannot find second satellite ADCS CSV. Checked: %s", secondAdcsCsv);
end

%% 5. Read ADCS quaternion data
qRaw = readtable(quatCsv, "VariableNamingRule", "preserve");

clockUnix = qRaw{:, timeColumn};
tUtc = datetime(clockUnix, "ConvertFrom", "posixtime", "TimeZone", "UTC");

qData = double([
    qRaw{:, quatColumns(1)}, ...
    qRaw{:, quatColumns(2)}, ...
    qRaw{:, quatColumns(3)}, ...
    qRaw{:, quatColumns(4)}]) * quatScale;

if quatOrder == "xyzw"
    qBodyOrc = qData;
elseif quatOrder == "wxyz"
    qBodyOrc = [qData(:,2), qData(:,3), qData(:,4), qData(:,1)];
else
    error("quatOrder must be 'xyzw' or 'wxyz'.");
end

qNorm = vecnorm(qBodyOrc, 2, 2);
qBodyOrc = qBodyOrc ./ qNorm;

n = height(qRaw);

%% 5-1. Read second satellite Euler attitude data
secondRaw = readtable(secondAdcsCsv, "VariableNamingRule", "preserve");

requireTableColumns(secondRaw, [secondTimeColumn; secondEulerColumns], "second satellite ADCS CSV");

secondClockUnix = secondRaw{:, secondTimeColumn};
secondTUtc = datetime(secondClockUnix, "ConvertFrom", "posixtime", "TimeZone", "UTC");

secondEulerDeg = double([
    secondRaw{:, secondEulerColumns(1)}, ...
    secondRaw{:, secondEulerColumns(2)}, ...
    secondRaw{:, secondEulerColumns(3)}]) * secondEulerScaleDeg;

validSecond = ~isnat(secondTUtc) & all(isfinite(secondEulerDeg), 2);
secondTUtc = secondTUtc(validSecond);
secondEulerDeg = secondEulerDeg(validSecond, :);
[secondTUtc, secondUniqueIdx] = unique(secondTUtc, "stable");
secondEulerDeg = secondEulerDeg(secondUniqueIdx, :);

if isempty(secondTUtc)
    error("Second satellite ADCS CSV has no valid time/attitude rows.");
end

secondN = numel(secondTUtc);

%% 6. Build satellite scenario
scenarioStart = min([tUtc(1); secondTUtc(1)]);
scenarioStop = max([tUtc(end); secondTUtc(end)]);
sc = satelliteScenario(scenarioStart, scenarioStop, 60);

sat = satellite(sc, tleFile, "Name", satelliteName);
sat2 = satellite(sc, secondTleFile, "Name", secondSatelliteName);

sat.Visual3DModel = "SmallSat.glb";
sat.Visual3DModelScale = 0.4;
sat2.Visual3DModel = "SmallSat.glb";
sat2.Visual3DModelScale = 0.4;

% Body-frame direction axes for attitude checking.
% Keep the scale modest so the axes do not hide the satellite model.
coordinateAxes(sat, "Scale", 0.7);
coordinateAxes(sat2, "Scale", 0.7);

%% 7. Compute attitude in inertial frame
qInertial = zeros(n, 4); % [qw qx qy qz]

for k = 1:n
    [rk, vk] = states(sat, tUtc(k), "CoordinateFrame", "inertial");

    R_eci_from_orc = eciFromLvlh(rk(:).', vk(:).');
    R_orc_from_body = quatScalarLastToDcm(qBodyOrc(k, :));

    if attitudeDirection == "bodyToOrc"
        R_eci_from_body = R_eci_from_orc * R_orc_from_body;
    else
        R_eci_from_body = R_eci_from_orc * R_orc_from_body.';
    end

    qInertial(k, :) = dcm2quat(R_eci_from_body.');
end

%% 8. Inject attitude
attitudeTT = timetable(tUtc, qInertial);
pointAt(sat, attitudeTT, "ExtrapolationMethod", "nadir");

qInertial2 = zeros(secondN, 4); % [qw qx qy qz]

for k = 1:secondN
    [rk, vk] = states(sat2, secondTUtc(k), "CoordinateFrame", "inertial");

    R_eci_from_orc = eciFromLvlh(rk(:).', vk(:).');
    R_orc_from_body = euler321DegToDcm(secondEulerDeg(k, :));

    if secondAttitudeDirection == "bodyToOrc"
        R_eci_from_body = R_eci_from_orc * R_orc_from_body;
    else
        R_eci_from_body = R_eci_from_orc * R_orc_from_body.';
    end

    qInertial2(k, :) = dcm2quat(R_eci_from_body.');
end

secondAttitudeTT = timetable(secondTUtc, qInertial2);
pointAt(sat2, secondAttitudeTT, "ExtrapolationMethod", "nadir");

checkTime = max(tUtc(1), secondTUtc(1));
[sat1CheckR, ~] = states(sat, checkTime, "CoordinateFrame", "inertial");
[sat2CheckR, ~] = states(sat2, checkTime, "CoordinateFrame", "inertial");
satDistanceKm = norm(sat1CheckR(:) - sat2CheckR(:)) / 1000;
fprintf("BK-2 and BK-1 distance at %s UTC: %.3f km\n", string(checkTime), satDistanceKm);

%% 8-1. BK-2 red axis pointing angle to BK-1 body
commonTUtc = intersect(tUtc, secondTUtc, "stable");
pointingAngleDeg = nan(numel(commonTUtc), 1);
axisNames = ["+X red", "-X red", "+Y green", "-Y green", "+Z blue", "-Z blue"];
bodyAxes = [
     1,  0,  0;
    -1,  0,  0;
     0,  1,  0;
     0, -1,  0;
     0,  0,  1;
     0,  0, -1].';
allAxisPointingAngleDeg = nan(numel(commonTUtc), numel(axisNames));

for k = 1:numel(commonTUtc)
    thisTime = commonTUtc(k);
    idxFirst = find(tUtc == thisTime, 1, "first");

    [bk2R, bk2V] = states(sat, thisTime, "CoordinateFrame", "inertial");
    [bk1R, ~] = states(sat2, thisTime, "CoordinateFrame", "inertial");

    R_eci_from_orc = eciFromLvlh(bk2R(:).', bk2V(:).');
    R_orc_from_body = quatScalarLastToDcm(qBodyOrc(idxFirst, :));

    if attitudeDirection == "bodyToOrc"
        R_eci_from_body = R_eci_from_orc * R_orc_from_body;
    else
        R_eci_from_body = R_eci_from_orc * R_orc_from_body.';
    end

    redAxisEci = R_eci_from_body(:, 1);
    bk2ToBk1Eci = bk1R(:) - bk2R(:);
    pointingAngleDeg(k) = angleBetweenVectorsDeg(redAxisEci, bk2ToBk1Eci);

    for axisIdx = 1:numel(axisNames)
        thisAxisEci = R_eci_from_body * bodyAxes(:, axisIdx);
        allAxisPointingAngleDeg(k, axisIdx) = angleBetweenVectorsDeg(thisAxisEci, bk2ToBk1Eci);
    end
end

[bestPointingAngleDeg, bestPointingIdx] = min(pointingAngleDeg);
steadyErrorDeg = abs(pointingAngleDeg - steadyTargetAngleDeg);
steadyFlag = steadyErrorDeg <= steadyToleranceDeg;
[bestAxisAngleDeg, bestAxisLinearIdx] = min(allAxisPointingAngleDeg(:));
[bestAxisTimeIdx, bestAxisIdx] = ind2sub(size(allAxisPointingAngleDeg), bestAxisLinearIdx);

angleDiff = diff(pointingAngleDeg);
descentStartIdx = find(angleDiff < 0, 1, "first");
steadyEntryIdx = NaN;
turnToSteadyDuration = seconds(nan);

if ~isempty(descentStartIdx)
    steadyEntryAfterDescent = find(steadyFlag(descentStartIdx:end), 1, "first");

    if ~isempty(steadyEntryAfterDescent)
        steadyEntryIdx = descentStartIdx + steadyEntryAfterDescent - 1;
        turnToSteadyDuration = commonTUtc(steadyEntryIdx) - commonTUtc(descentStartIdx);
    end
end

fprintf("Best BK-2 red-axis pointing to BK-1 body: %s UTC, angle %.3f deg\n", ...
    string(commonTUtc(bestPointingIdx)), bestPointingAngleDeg);
fprintf("Steady-state target angle: %.2f deg, tolerance: +/- %.2f deg\n", ...
    steadyTargetAngleDeg, steadyToleranceDeg);
fprintf("Samples inside steady-state band: %d\n", nnz(steadyFlag));
if ~isnan(steadyEntryIdx)
    fprintf("Descent starts at %s UTC, angle %.3f deg\n", ...
        string(commonTUtc(descentStartIdx)), pointingAngleDeg(descentStartIdx));
    fprintf("First steady-state entry at %s UTC, angle %.3f deg\n", ...
        string(commonTUtc(steadyEntryIdx)), pointingAngleDeg(steadyEntryIdx));
    fprintf("Rotation time from descent start to steady state: %.1f s\n", ...
        seconds(turnToSteadyDuration));
else
    fprintf("No steady-state entry was found after the first descending point.\n");
end
fprintf("Best BK-2 body-axis pointing to BK-1 body is %s at %s UTC, angle %.3f deg\n", ...
    axisNames(bestAxisIdx), string(commonTUtc(bestAxisTimeIdx)), bestAxisAngleDeg);

pointingTable = table(commonTUtc(:), pointingAngleDeg(:), steadyErrorDeg(:), steadyFlag(:), ...
    VariableNames=["UtcTime", "Bk2RedAxisToBk1BodyAngleDeg", "SteadyErrorDeg", "IsNearSteady"]);
pointingCsv = fullfile(outDir, "BK2_red_axis_to_BK1_body_pointing_angle.csv");
writetable(pointingTable, pointingCsv);
disp("BK-2 red-axis to BK-1 body pointing angle CSV exported to:");
disp(pointingCsv);

allAxisPointingTable = table(commonTUtc(:), ...
    allAxisPointingAngleDeg(:, 1), allAxisPointingAngleDeg(:, 2), ...
    allAxisPointingAngleDeg(:, 3), allAxisPointingAngleDeg(:, 4), ...
    allAxisPointingAngleDeg(:, 5), allAxisPointingAngleDeg(:, 6), ...
    VariableNames=["UtcTime", "PlusXRedDeg", "MinusXRedDeg", "PlusYGreenDeg", ...
    "MinusYGreenDeg", "PlusZBlueDeg", "MinusZBlueDeg"]);
allAxisPointingCsv = fullfile(outDir, "BK2_all_body_axes_to_BK1_body_pointing_angle.csv");
writetable(allAxisPointingTable, allAxisPointingCsv);
disp("BK-2 all-axis to BK-1 body pointing angle CSV exported to:");
disp(allAxisPointingCsv);

figure("Name", "BK-2 red-axis pointing angle to BK-1 body", "Color", "w");
plot(commonTUtc, pointingAngleDeg, "r-o", "LineWidth", 1.4, "MarkerSize", 4);
hold on;
yline(steadyTargetAngleDeg, "--", "Steady angle 1.82 deg", "LineWidth", 1.2);
yline(steadyTargetAngleDeg + steadyToleranceDeg, ":", "LineWidth", 1.0);
yline(steadyTargetAngleDeg - steadyToleranceDeg, ":", "LineWidth", 1.0);
scatter(commonTUtc(bestPointingIdx), bestPointingAngleDeg, 70, "b", "filled");
bestLabel = sprintf("Best %.2f deg", bestPointingAngleDeg);
text(commonTUtc(bestPointingIdx), bestPointingAngleDeg, "  " + bestLabel, ...
    "VerticalAlignment", "bottom", "FontWeight", "bold");
if any(steadyFlag)
    scatter(commonTUtc(steadyFlag), pointingAngleDeg(steadyFlag), 55, "g", "filled");
end
if ~isempty(descentStartIdx)
    xline(commonTUtc(descentStartIdx), ":", "Start descending", "LineWidth", 1.2, ...
        "LabelOrientation", "horizontal", "LabelVerticalAlignment", "top");
end
if ~isnan(steadyEntryIdx)
    xline(commonTUtc(steadyEntryIdx), ":", "Steady entry", "LineWidth", 1.2, ...
        "LabelOrientation", "horizontal", "LabelVerticalAlignment", "bottom");

    annotationY = max(pointingAngleDeg, [], "omitnan") * 0.72;
    plot([commonTUtc(descentStartIdx), commonTUtc(steadyEntryIdx)], [annotationY, annotationY], ...
        "k-", "LineWidth", 1.4);
    scatter([commonTUtc(descentStartIdx), commonTUtc(steadyEntryIdx)], [annotationY, annotationY], ...
        35, "k", "filled");
    text(commonTUtc(descentStartIdx) + turnToSteadyDuration / 2, annotationY + 5, ...
        sprintf("Turn to steady state = %.1f s", seconds(turnToSteadyDuration)), ...
        "HorizontalAlignment", "center", "FontWeight", "bold", "BackgroundColor", "w");
end
grid on;
ylim([0, max(110, ceil(max(pointingAngleDeg, [], "omitnan") / 10) * 10)]);
xlabel("UTC time");
ylabel("Angle (deg)");
title("BK-2 red axis angle to BK-1 body");
subtitle(sprintf("Steady target %.2f +/- %.2f deg; minimum %.2f deg at %s UTC", ...
    steadyTargetAngleDeg, steadyToleranceDeg, bestPointingAngleDeg, string(commonTUtc(bestPointingIdx))));

figure("Name", "BK-2 all body-axis pointing angles to BK-1 body", "Color", "w");
plot(commonTUtc, allAxisPointingAngleDeg, "LineWidth", 1.2);
hold on;
yline(steadyTargetAngleDeg, "--", "Steady target angle", "LineWidth", 1.2);
scatter(commonTUtc(bestAxisTimeIdx), bestAxisAngleDeg, 70, "k", "filled");
text(commonTUtc(bestAxisTimeIdx), bestAxisAngleDeg, ...
    sprintf("  Best %s %.2f deg", axisNames(bestAxisIdx), bestAxisAngleDeg), ...
    "VerticalAlignment", "bottom", "FontWeight", "bold");
grid on;
ylim([0, 180]);
xlabel("UTC time");
ylabel("Angle (deg)");
title("BK-2 body-axis angles to BK-1 body");
subtitle("Use this to confirm which BK-2 body axis is actually pointing toward BK-1 body");
legend(axisNames, "Location", "eastoutside");

%% 9. Ground station and access
gs = groundStation(sc, 24.96, 121.22, "Name", "Zhongli_GS");%%更改激基站位置

% Sensor / antenna view angle limit
sensorViewAngle = 30;   % 視角限制

sensor = conicalSensor(sat, ...
    "MaxViewAngle", sensorViewAngle, ...
    "Name", "Sat_Sensor");
sensor2 = conicalSensor(sat2, ...
    "MaxViewAngle", sensorViewAngle, ...
    "Name", "Sat2_Sensor");

tx = transmitter(sat, ...
    "Frequency", 2.4e9, ...
    "Power", 10); 
tx2 = transmitter(sat2, ...
    "Frequency", 2.4e9, ...
    "Power", 10);

rx = receiver(gs, "Name", "Zhongli_Rx");

lnk = link(tx, rx);
lnk2 = link(tx2, rx);

% Satellite-to-ground-station geometric access, without sensor cone limit
acSatGs = access(sat, gs);
acSat2Gs = access(sat2, gs);

% Sensor-to-ground-station access, with MaxViewAngle limit
acSensorGs = access(sensor, gs);
acSensor2Gs = access(sensor2, gs);

%% 9-1. Ground station access schedule table

accessTable = accessIntervals(acSatGs);
sensorAccessTable = accessIntervals(acSensorGs);
linkTable = linkIntervals(lnk);
secondAccessTable = accessIntervals(acSat2Gs);
secondSensorAccessTable = accessIntervals(acSensor2Gs);
secondLinkTable = linkIntervals(lnk2);

disp("====== Satellite to Zhongli_GS geometric access ======");
disp(accessTable);

disp("====== Sensor-limited access to Zhongli_GS ======");
disp(sensorAccessTable);

disp("====== Communication link schedule ======");
disp(linkTable);

disp("====== Second satellite to Zhongli_GS geometric access ======");
disp(secondAccessTable);

disp("====== Second satellite sensor-limited access to Zhongli_GS ======");
disp(secondSensorAccessTable);

disp("====== Second satellite communication link schedule ======");
disp(secondLinkTable);

if ~isempty(sensorAccessTable)
    sensorAccessCsv = fullfile(outDir, satelliteName + "_Zhongli_GS_sensor_limited_access_schedule.csv");
    writetable(sensorAccessTable, sensorAccessCsv);
    disp("Sensor-limited access schedule CSV exported to:");
    disp(sensorAccessCsv);
else
    disp("No sensor-limited access time.");
end

if ~isempty(linkTable)
    linkCsv = fullfile(outDir, satelliteName + "_Zhongli_GS_link_schedule.csv");
    writetable(linkTable, linkCsv);
    disp("Communication link schedule CSV exported to:");
    disp(linkCsv);
else
    disp("No communication link time.");
end

if ~isempty(secondSensorAccessTable)
    secondSensorAccessCsv = fullfile(outDir, secondSatelliteName + "_Zhongli_GS_sensor_limited_access_schedule.csv");
    writetable(secondSensorAccessTable, secondSensorAccessCsv);
    disp("Second satellite sensor-limited access schedule CSV exported to:");
    disp(secondSensorAccessCsv);
else
    disp("No second satellite sensor-limited access time.");
end

if ~isempty(secondLinkTable)
    secondLinkCsv = fullfile(outDir, secondSatelliteName + "_Zhongli_GS_link_schedule.csv");
    writetable(secondLinkTable, secondLinkCsv);
    disp("Second satellite communication link schedule CSV exported to:");
    disp(secondLinkCsv);
else
    disp("No second satellite communication link time.");
end
%% 10. Viewer
viewer = satelliteScenarioViewer(sc, "ShowDetails", true);

show(sat);
show(sat2);
show(gs);

% Keep the camera unlocked so the two satellites can be seen separately
% after zooming out to an Earth view.
% camtarget(viewer, sat);

disp("Camera is unlocked. Zoom out to see BK-2 and BK-1 separately.");
play(sc);

%% Local functions

function adcsFile = resolveAdcsInput(adcsInput, outDir, archiveDir, fallbackArchiveDir)
    adcsText = string(adcsInput);

    if strlength(strtrim(adcsText)) == 0
        [fileName, folderName] = uigetfile( ...
            {"*.csv;*.txt", "ADCS files (*.csv, *.txt)"; "*.*", "All files"}, ...
            "Select an ADCS CSV file");

        if isequal(fileName, 0)
            error("No ADCS file selected.");
        end

        adcsFile = fullfile(folderName, fileName);
        return
    end

    if isfile(adcsText)
        adcsFile = char(adcsText);
        return
    end

    candidate = fullfile(outDir, adcsText);
    if isfile(candidate)
        adcsFile = candidate;
        return
    end

    candidate = fullfile(archiveDir, adcsText);
    if isfile(candidate)
        adcsFile = candidate;
        return
    end

    candidate = fullfile(fallbackArchiveDir, adcsText);
    if isfile(candidate)
        adcsFile = candidate;
        return
    end

    error("Cannot find ADCS file from adcsInput: %s", adcsText);
end

function tleFile = resolveTleInput(tleInput, outDir, fallbackOutDir)
    if iscell(tleInput) || (isstring(tleInput) && numel(tleInput) > 1)
        tleFile = writeTempTleFile(tleInput);
        return
    end

    tleText = string(tleInput);

    if strlength(strtrim(tleText)) == 0
        [fileName, folderName] = uigetfile( ...
            {"*.tle;*.txt", "TLE files (*.tle, *.txt)"; "*.*", "All files"}, ...
            "Select a TLE file");

        if isequal(fileName, 0)
            error("No TLE file selected.");
        end

        tleFile = fullfile(folderName, fileName);
        return
    end

    if contains(tleText, newline) || startsWith(strtrim(tleText), "1 ")
        tleFile = writeTempTleFile(splitlines(tleText));
        return
    end

    if isfile(tleText)
        tleFile = char(tleText);
        return
    end

    candidate = fullfile(outDir, tleText);
    if isfile(candidate)
        tleFile = candidate;
        return
    end

    candidate = fullfile(fallbackOutDir, tleText);
    if isfile(candidate)
        tleFile = candidate;
        return
    end

    error("Cannot find TLE file from tleInput: %s", tleText);
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

function satelliteName = tleNameFromFile(tleFile)
    lines = readlines(tleFile);
    lines = lines(strlength(strtrim(lines)) > 0);

    if isempty(lines)
        satelliteName = "Selected_TLE_Satellite";
        return
    end

    firstLine = strtrim(lines(1));

    if startsWith(firstLine, "1 ") || startsWith(firstLine, "2 ")
        [~, baseName] = fileparts(tleFile);
        satelliteName = string(baseName);
    else
        satelliteName = matlab.lang.makeValidName(firstLine);
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

function requireTableColumns(tbl, columns, labelText)
    names = string(tbl.Properties.VariableNames);
    missing = setdiff(string(columns), names);

    if ~isempty(missing)
        error("Missing required columns in %s: %s", labelText, strjoin(missing, ", "));
    end
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
