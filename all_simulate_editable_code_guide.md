# all_simulate_editable.m 程式碼使用說明

本文件說明 `all_simulate_editable.m` 的用途、執行方式、可修改參數、輸出結果與常見錯誤處理。這支 MATLAB 程式用來模擬 BK-2 衛星的本體座標軸是否能穩定指向 BK-1 衛星，並自動產生 CSV、PNG、HTML dashboard，以及可選的 MP4 3D 動畫。

## 1. 程式用途

`all_simulate_editable.m` 是一支可直接編輯參數的衛星指向模擬主程式。它會完成以下工作：

- 讀取 BK-2 的 ADCS/LDCS 姿態遙測 CSV。
- 使用 TLE 建立 BK-2 與 BK-1 的 LEO 軌道場景。
- 將 BK-2 的 quaternion 姿態資料轉換成 inertial frame 下的 body axis 方向。
- 計算 BK-2 指定 body axis 與 BK-2 到 BK-1 視線方向的夾角。
- 判斷是否進入 `1.82 deg +/- 0.10 deg` 的穩態指向範圍。
- 輸出任務摘要、逐點資料、圖表、dashboard。
- 可選擇開啟 MATLAB `satelliteScenarioViewer` 互動式 Earth viewer。
- 可選擇輸出 MP4 3D 指向動畫。

## 2. 執行方式

在 MATLAB Command Window 輸入：

```matlab
cd("C:\Users\USER\OneDrive\桌面\實習\8-12")
all_simulate_editable
```

如果只想用 batch/headless 模式執行，不想開啟互動式 viewer，可以在系統環境變數中設定 `SKIP_SCENARIO_VIEWER=1`，或在 PowerShell 執行：

```powershell
$env:SKIP_SCENARIO_VIEWER='1'
& 'C:\Program Files\MATLAB\R2026a\bin\matlab.exe' -batch "cd('C:\Users\USER\OneDrive\桌面\實習\8-12'); all_simulate_editable"
```

## 3. 建議只修改的區塊

程式最上方有一段：

```matlab
%% 1. EDIT HERE ONLY
```

一般使用時只需要修改這個區塊。下面的 `%% 2. Main program` 和 local functions 是計算邏輯，除非要改演算法，否則不建議修改。

## 4. 主要參數說明

### 4.1 專案資料夾與輸出前綴

```matlab
projectDir = fileparts(mfilename("fullpath"));

cfg.outputDir = projectDir;
cfg.outputPrefix = "BK2_to_BK1";
```

說明：

- `projectDir` 會自動抓取 `all_simulate_editable.m` 所在資料夾。
- `cfg.outputDir` 代表輸出檔案要放在哪裡。
- `cfg.outputPrefix` 是輸出檔名前綴。

如果不想覆蓋舊結果，可以改成：

```matlab
cfg.outputPrefix = "BK2_to_BK1_test01";
```

### 4.2 ADCS/LDCS CSV 檔案路徑

```matlab
cfg.adcsFile = "C:\Users\USER\OneDrive\桌面\實習\8-12\TLE\1785970000-RIoT-2-10slog.csv";
```

這一行是最常修改的地方。更換資料時，只要把引號中間改成新的 CSV 完整路徑即可。

範例：

```matlab
cfg.adcsFile = "C:\Users\USER\Downloads\new_adcs_file.csv";
```

注意：

- 路徑必須指向實際存在的 `.csv` 檔案。
- 如果 MATLAB 顯示 `Cannot find ADCS CSV`，代表這個路徑錯誤、檔案不存在，或中文路徑編碼有問題。
- 若遇到中文路徑問題，建議把 CSV 放到英文路徑，例如 `C:\ADCS_Data\file.csv`。

### 4.3 Primary satellite 設定

```matlab
cfg.primary.name = "BK-2";
cfg.primary.tle = [
    "BK-2"
    "1 ..."
    "2 ..."
];
```

Primary satellite 是要檢查 body axis 指向能力的衛星。本程式目前設定為 BK-2。

### 4.4 Target satellite 設定

```matlab
cfg.target.name = "BK-1";
cfg.target.tle = [
    "BK-1"
    "1 ..."
    "2 ..."
];
```

Target satellite 是被 BK-2 指向的目標衛星。本程式目前設定為 BK-1。

### 4.5 ADCS 欄位設定

時間欄位：

```matlab
cfg.timeColumn = "uEstTimeintegerseconds";
```

BK-2 quaternion 欄位：

```matlab
cfg.primary.quatColumns = [
    "iEstimatedORCquaternionQ0"
    "iEstimatedORCquaternionQ1"
    "iEstimatedORCquaternionQ2"
    "iEstimatedORCquaternionQ3"
];
cfg.primary.quatScale = 1e-4;
cfg.primary.quatOrder = "xyzw";
cfg.primary.attitudeDirection = "bodyToOrc";
```

說明：

- `quatScale = 1e-4` 表示 CSV 內 quaternion 值需要乘上 `1e-4` 還原。
- `quatOrder = "xyzw"` 表示欄位順序為 `[qx, qy, qz, qw]`。
- `attitudeDirection = "bodyToOrc"` 表示 quaternion 是由 body frame 轉到 ORC/LVLH frame。

Target satellite Euler 欄位：

```matlab
cfg.target.eulerColumns = [
    "iEstimatedrollangle"
    "iEstimatedpitchangle"
    "iEstimatedyawangle"
];
cfg.target.eulerScaleDeg = 0.01;
```

這些欄位目前主要用來確認 CSV 格式符合預期。

## 5. 指向任務判定設定

目前任務設定為 BK-2 的 `+X red` body axis 指向 BK-1：

```matlab
cfg.pointing.bodyAxis = [1, 0, 0];
cfg.pointing.axisLabel = "+X red";
cfg.steady.targetAngleDeg = 1.82;
cfg.steady.toleranceDeg = 0.10;
```

判定條件：

- 目標角度：`1.82 deg`
- 容許誤差：`+/- 0.10 deg`
- 若某個時間點的指向角落在 `1.72 deg` 到 `1.92 deg` 之間，就會被判定為 near-steady。

Body axis 對照表：

| 指向軸 | `bodyAxis` | `axisLabel` |
| --- | --- | --- |
| +X red | `[1, 0, 0]` | `"+X red"` |
| -X red | `[-1, 0, 0]` | `"-X red"` |
| +Y green | `[0, 1, 0]` | `"+Y green"` |
| -Y green | `[0, -1, 0]` | `"-Y green"` |
| +Z blue | `[0, 0, 1]` | `"+Z blue"` |
| -Z blue | `[0, 0, -1]` | `"-Z blue"` |

## 6. Scenario、Video、Viewer 設定

### 6.1 模擬取樣時間

```matlab
cfg.scenario.sampleTimeSec = 10;
```

代表每 10 秒建立一個 simulation sample。

### 6.2 MP4 動畫輸出

```matlab
cfg.video.enable = false;
```

預設不重新輸出 MP4，因為影片輸出較花時間。如果需要產生 MP4，改成：

```matlab
cfg.video.enable = true;
```

MP4 設定：

```matlab
cfg.video.frameCount = 90;
cfg.video.frameRate = 12;
cfg.video.quality = 90;
cfg.video.vectorScaleKm = 1800;
cfg.video.earthRadiusKm = 6371;
```

### 6.3 MATLAB 互動式 Earth viewer

```matlab
cfg.viewer.enable = true;
cfg.viewer.playOnOpen = true;
cfg.viewer.showDetails = true;
```

如果不想開啟 viewer：

```matlab
cfg.viewer.enable = false;
```

如果在 batch mode 或沒有 MATLAB desktop，程式會自動略過 viewer。

## 7. 輸出檔案

程式執行後會產生以下檔案：

| 輸出檔案 | 說明 |
| --- | --- |
| `BK2_to_BK1_pointing_dashboard_data.csv` | 每個時間點的指向角、穩態誤差、是否 near-steady、兩星距離 |
| `BK2_to_BK1_mission_summary.csv` | 關鍵任務事件摘要 |
| `BK2_to_BK1_pointing_dashboard_chart.png` | 指向角折線圖 |
| `BK2_to_BK1_pointing_dashboard.html` | 可用瀏覽器開啟的 dashboard |
| `BK2_to_BK1_3D_pointing_animation.mp4` | 可選的 3D 指向動畫 |

## 8. Dashboard Data CSV 欄位

`BK2_to_BK1_pointing_dashboard_data.csv` 主要欄位：

| 欄位 | 說明 |
| --- | --- |
| `UtcTime` | UTC 時間 |
| `AngleDeg` | BK-2 指定 body axis 與 BK-2 到 BK-1 視線方向的夾角 |
| `SteadyErrorDeg` | 與目標穩態角 `1.82 deg` 的差值 |
| `IsNearSteady` | 是否落在 `+/- 0.10 deg` 容許範圍內 |
| `RangeKm` | BK-2 與 BK-1 的距離，單位 km |

## 9. Mission Summary CSV 欄位

`BK2_to_BK1_mission_summary.csv` 會記錄：

| Event | 說明 |
| --- | --- |
| `Start descending` | 指向角第一次開始下降的時間 |
| `First steady entry` | 第一次進入穩態範圍的時間 |
| `Best pointing` | 全時段最佳指向角 |

目前模擬結果範例：

| Event | UTC Time | Angle |
| --- | --- | --- |
| Start descending | 05-Aug-2026 22:47:20 UTC | 70.418 deg |
| First steady entry | 05-Aug-2026 22:48:34 UTC | 1.889 deg |
| Best pointing | 05-Aug-2026 22:53:24 UTC | 1.621 deg |

## 10. 程式主要流程

```text
讀取使用者設定
        ↓
檢查 ADCS CSV 是否存在
        ↓
檢查必要欄位是否存在
        ↓
讀取時間、quaternion、Euler angle
        ↓
建立 BK-2 / BK-1 satelliteScenario
        ↓
計算每個時間點的兩星位置與 body axis 方向
        ↓
計算 pointing angle
        ↓
判斷 steady entry / best pointing / mission status
        ↓
輸出 CSV、PNG、HTML、可選 MP4
        ↓
開啟 MATLAB interactive viewer
```

## 11. 常見錯誤與解法

### 11.1 Cannot find ADCS CSV

代表：

- `cfg.adcsFile` 路徑錯誤。
- CSV 檔案不存在。
- 中文路徑或 OneDrive 同步狀態造成 MATLAB 找不到檔案。

解法：

```matlab
cfg.adcsFile = "C:\Users\USER\Downloads\your_file.csv";
```

確認路徑指到實際 CSV。

### 11.2 Missing required columns

代表 CSV header 和程式設定的欄位名稱不一致。請檢查：

```matlab
cfg.timeColumn
cfg.primary.quatColumns
cfg.target.eulerColumns
```

欄位名稱必須和 CSV 第一列完全相同。

### 11.3 Quaternion data contains zero-norm rows

代表 quaternion 有全零或無效資料列。請檢查 ADCS CSV 是否有缺值或異常值。

### 11.4 Viewer 沒有開啟

可能原因：

- `cfg.viewer.enable = false`
- MATLAB 在 batch/headless 模式執行
- 設定了環境變數 `SKIP_SCENARIO_VIEWER`
- MATLAB desktop 不可用

如果只需要輸出檔案，viewer 沒開啟不影響結果。

## 12. 建議使用方式

一般開發與展示：

```matlab
cfg.video.enable = false;
cfg.viewer.enable = true;
```

產出報告與 dashboard：

```matlab
cfg.video.enable = false;
cfg.viewer.enable = false;
```

需要完整展示影片：

```matlab
cfg.video.enable = true;
cfg.viewer.enable = true;
```

## 13. 快速更換 ADCS/LDCS 資料檔

如果只是換資料檔，通常只需要改這一行：

```matlab
cfg.adcsFile = "貼上你的 ADCS 或 LDCS CSV 完整路徑";
```

然後執行：

```matlab
all_simulate_editable
```
