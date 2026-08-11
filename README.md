# Satellite Pointing Simulation

這個專案使用 MATLAB 依據 TLE 軌道資料與 ADCS 姿態紀錄，重建 BK-1 / BK-2 兩顆衛星的姿態，並計算衛星之間的 body-axis pointing angle，用來分析衛星指向是否接近目標方向。

## 專案目的

本專案主要分析：

- **BK-2** 對 **BK-1 body** 的指向角度
- **BK-1** 對 **BK-2** 的指向角度
- BK-1 / BK-2 各 body axis 與目標方向的夾角
- 衛星與中壢地面站的可視時間與通訊 link schedule
- MATLAB satellite scenario viewer 中的衛星姿態與指向視覺化

## 資料夾內容

| 檔案 / 資料夾 | 說明 |
| --- | --- |
| `all_simulate.m` | 主要 MATLAB 模擬程式 |
| `TLE/` | TLE 與 ADCS 來源資料 |
| `1785970000-RIoT-2-10slog.csv` | ADCS 姿態紀錄 |
| `BK2_red_axis_to_BK1_body_pointing_angle.csv` | BK-2 red axis 指向 BK-1 body 的角度結果 |
| `BK2_all_body_axes_to_BK1_body_pointing_angle.csv` | BK-2 六個 body axes 指向 BK-1 body 的角度結果 |
| `BK1_red_axis_to_BK2_pointing_angle.csv` | BK-1 red axis 指向 BK-2 的角度結果 |
| `BK1_all_body_axes_to_BK2_pointing_angle.csv` | BK-1 六個 body axes 指向 BK-2 的角度結果 |
| `8-6.pptx` | 簡報資料 |
| `衛星指向影片.mp4` | 衛星指向模擬影片 |
| `*.png` | 模擬截圖 |

## 執行環境

建議使用：

- MATLAB
- Satellite Communications Toolbox
- MATLAB 中可使用 quaternion / DCM 轉換函式，例如 `dcm2quat`

## 執行方式

1. 開啟 MATLAB。
2. 將 Current Folder 切換到此專案資料夾。
3. 執行：

```matlab
all_simulate
```

程式會自動完成：

1. 讀取 TLE 與 ADCS 姿態資料。
2. 建立 BK-1 / BK-2 的 satellite scenario。
3. 將 ADCS 姿態資料轉換並套用到衛星模型。
4. 計算兩顆衛星之間的指向角度。
5. 匯出 pointing angle CSV。
6. 計算中壢地面站 access / link interval。
7. 開啟 MATLAB satellite scenario viewer 進行視覺化。

## 模擬流程

### 1. 建立衛星軌道

程式使用 TLE 建立兩顆衛星：

- `BK-2`
- `BK-1`

並用 `satelliteScenario` 建立模擬場景。

### 2. 讀取姿態資料

BK-2 使用 quaternion 欄位重建姿態：

- `iEstimatedORCquaternionQ0`
- `iEstimatedORCquaternionQ1`
- `iEstimatedORCquaternionQ2`
- `iEstimatedORCquaternionQ3`

BK-1 使用 Euler angle 欄位重建姿態：

- `iEstimatedrollangle`
- `iEstimatedpitchangle`
- `iEstimatedyawangle`

### 3. 座標轉換

程式會將衛星的 orbital reference frame 轉換到 ECI inertial frame，再結合 body attitude，得到衛星 body axes 在慣性座標中的方向。

### 4. 指向角度計算

程式會計算：

- BK-2 red axis 到 BK-1 body 的夾角
- BK-2 六個 body axes 到 BK-1 body 的夾角
- BK-1 red axis 到 BK-2 的夾角
- BK-1 六個 body axes 到 BK-2 的夾角

角度越小，代表該 body axis 越接近指向目標。

### 5. 地面站與通訊分析

程式加入中壢地面站：

- Latitude: `24.96`
- Longitude: `121.22`
- Sensor view angle: `30 deg`
- Transmitter frequency: `2.4 GHz`
- Transmitter power: `10 W`

並計算：

- Satellite-to-ground-station geometric access
- Sensor-limited access
- Communication link schedule

## 主要結果

根據 `BK2_red_axis_to_BK1_body_pointing_angle.csv`：

- BK-2 red axis 指向 BK-1 body 的最小角度：**1.6207 deg**
- 最小角度發生時間：**05-Aug-2026 22:53:24 UTC**
- 最接近目標的 BK-2 body axis：**+X red axis**
- 程式設定的 steady target angle：**1.82 deg**
- steady tolerance：**+/- 0.10 deg**

## 輸出 CSV 說明

### `BK2_red_axis_to_BK1_body_pointing_angle.csv`

| 欄位 | 說明 |
| --- | --- |
| `UtcTime` | UTC 時間 |
| `Bk2RedAxisToBk1BodyAngleDeg` | BK-2 red axis 與 BK-1 body 方向的夾角 |
| `SteadyErrorDeg` | 與 steady target angle 的誤差 |
| `IsNearSteady` | 是否落在 steady tolerance 範圍內 |

### `BK2_all_body_axes_to_BK1_body_pointing_angle.csv`

| 欄位 | 說明 |
| --- | --- |
| `UtcTime` | UTC 時間 |
| `PlusXRedDeg` | +X red axis 指向角度 |
| `MinusXRedDeg` | -X red axis 指向角度 |
| `PlusYGreenDeg` | +Y green axis 指向角度 |
| `MinusYGreenDeg` | -Y green axis 指向角度 |
| `PlusZBlueDeg` | +Z blue axis 指向角度 |
| `MinusZBlueDeg` | -Z blue axis 指向角度 |

## GitHub 上傳建議

建議上傳：

- `README.md`
- `.gitignore`
- `all_simulate.m`
- `TLE/`
- 角度分析結果 CSV
- 重要截圖
- `8-6.pptx`，若需要一起保留簡報

`衛星指向影片.mp4` 檔案較大，建議使用 Git LFS，或改放在 GitHub Release / Google Drive，再於 README 補上連結。

## 備註

- 目前程式使用 `1785970000-RIoT-2-10slog.csv` 作為 ADCS 來源資料。
- Quaternion scale 設為 `1e-4`。
- BK-1 Euler angle scale 設為 `0.01 deg`。
- Attitude direction 設為 `bodyToOrc`。
- 若 TLE 或 ADCS 檔案位置改變，需要同步修改 `all_simulate.m` 中的路徑設定。
