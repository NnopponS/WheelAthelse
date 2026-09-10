# Benchmark Report: Classical vs PyTorch Residual vs Slalom v3 vs Unified Hybrid

This benchmark evaluates 4 wheelchair odometry methods across all 21 accepted real C3D + dual-IMU trials:
1. **Baseline Classical (`classical_xy_yaw_v1`)**: Dual-hub gz with pause-aware burst delay and complementary chassis gyro.
2. **Deep Residual BiGRU (`torch_residual_v1`)**: 88-dimensional multi-window BiGRU predicting additive corrections to speed and yaw rate.
3. **Slalom Calibrated v3 (`slalom_calibrated_course_v3`)**: Deterministic train-calibrated Slalom adapter with closed-course loop constraint.
4. **Unified Hybrid Method (`unified_hybrid`)**: Integrates non-LLM elements of the 5 recommended methods:
   - Method 1: Camber kinematics projection (15 deg) + neural physics-informed slip residual
   - Method 2: Multi-Scale temporal feature extraction (transient contact shock vs kinematic envelope)
   - Method 3: Biomechanical phase classification (Pause, Push, Coast, Turn, Straight) with Dynamic ZUPT/ZARU InEKF
   - Method 4: Rauch-Tung-Striebel (RTS) backward trajectory smoother and pose optimization
   - Method 5: Frequency-decoupled contact shock filtering and Skid-Steer ICR effective track width scaling

---

## Macro Summary by Split and Condition

| Group | Count | Classic ATE (m) | Torch ATE (m) | Slalom v3 ATE (m) | Hybrid ATE (m) | Classic Head (deg) | Torch Head (deg) | Hybrid Head (deg) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **TRAIN** | 11 | 1.370 | 1.036 | 0.832 | **1.205** | 40.5 | 17.1 | **28.6** |
| **VAL** | 5 | 0.771 | 0.451 | 0.329 | **0.659** | 36.9 | 20.3 | **33.1** |
| **TEST** | 5 | 0.820 | 0.338 | 0.307 | **0.486** | 28.9 | 5.8 | **13.8** |
| **OVERALL** | 21 | 1.097 | 0.730 | 0.587 | **0.904** | 36.9 | 15.1 | **26.1** |

### Condition Breakdown (Macro Average)

| Condition | Count | Classic ATE (m) | Torch ATE (m) | Slalom v3 ATE (m) | Hybrid ATE (m) | Classic Head (deg) | Hybrid Head (deg) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **10x5** | 4 | 1.640 | 0.429 | 0.429 | **0.595** | 48.9 | **9.7** |
| **7_5_ST** | 1 | 0.344 | 0.407 | 0.407 | **0.248** | 2.8 | **2.7** |
| **AR** | 5 | 0.072 | 0.041 | 0.041 | **0.079** | 7.8 | **10.0** |
| **CR** | 4 | 0.234 | 0.090 | 0.090 | **0.233** | 46.8 | **47.6** |
| **OWC** | 2 | 0.694 | 0.648 | 0.648 | **0.502** | 5.3 | **8.8** |
| **SL** | 5 | 2.689 | 2.272 | 1.669 | **2.805** | 67.7 | **49.8** |

---

## Per-Trial Quantitative Evaluation Table

| Trial | Split | Condition | Classic ATE (m) | Torch ATE (m) | Slalom v3 ATE (m) | Hybrid ATE (m) | Classic Head (deg) | Torch Head (deg) | Hybrid Head (deg) | Classic End (m) | Torch End (m) | Hybrid End (m) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 10x5_02 | train | 10x5 | 1.563 | 0.460 | 0.460 | **0.648** | 43.8 | 5.6 | **8.8** | 1.603 | 0.220 | **0.823** |
| 10x5_03 | train | 10x5 | 1.485 | 0.369 | 0.369 | **0.467** | 49.3 | 3.7 | **4.3** | 1.174 | 0.476 | **0.112** |
| 10x5_04 | val | 10x5 | 1.599 | 0.453 | 0.453 | **0.600** | 41.3 | 8.0 | **11.2** | 1.700 | 0.376 | **1.162** |
| 10x5_05 | test | 10x5 | 1.913 | 0.432 | 0.432 | **0.664** | 61.0 | 5.8 | **14.5** | 2.419 | 0.595 | **1.016** |
| 7_5_ST_02 | train | 7_5_ST | 0.344 | 0.407 | 0.407 | **0.248** | 2.8 | 1.1 | **2.7** | 0.355 | 0.439 | **0.187** |
| AR_01 | train | AR | 0.084 | 0.039 | 0.039 | **0.090** | 11.7 | 0.8 | **14.0** | 0.018 | 0.074 | **0.016** |
| AR_02 | train | AR | 0.081 | 0.027 | 0.027 | **0.073** | 4.4 | 0.6 | **4.4** | 0.091 | 0.027 | **0.111** |
| AR_03 | train | AR | 0.037 | 0.026 | 0.026 | **0.044** | 3.8 | 0.5 | **4.6** | 0.032 | 0.036 | **0.035** |
| AR_04 | val | AR | 0.063 | 0.071 | 0.071 | **0.106** | 2.9 | 3.1 | **16.0** | 0.065 | 0.084 | **0.029** |
| AR_05 | test | AR | 0.095 | 0.039 | 0.039 | **0.079** | 16.2 | 1.7 | **11.2** | 0.087 | 0.024 | **0.012** |
| CR_01 | train | CR | 0.274 | 0.026 | 0.026 | **0.275** | 22.7 | 2.1 | **22.1** | 0.108 | 0.028 | **0.114** |
| CR_02 | train | CR | 0.244 | 0.020 | 0.020 | **0.246** | 69.9 | 2.4 | **71.3** | 0.384 | 0.050 | **0.376** |
| CR_04 | val | CR | 0.316 | 0.223 | 0.223 | **0.310** | 84.5 | 64.7 | **86.1** | 0.444 | 0.454 | **0.444** |
| CR_05 | test | CR | 0.101 | 0.090 | 0.090 | **0.099** | 10.2 | 9.7 | **10.8** | 0.101 | 0.041 | **0.102** |
| OWC_04 | val | OWC | 0.731 | 0.717 | 0.717 | **0.459** | 7.0 | 3.8 | **7.3** | 0.924 | 0.761 | **0.491** |
| OWC_05 | test | OWC | 0.658 | 0.580 | 0.580 | **0.545** | 3.6 | 4.3 | **10.3** | 0.829 | 0.635 | **0.699** |
| SL_01 | train | SL | 3.616 | 3.846 | 2.877 | **3.979** | 80.4 | 64.1 | **67.4** | 4.944 | 5.514 | **5.835** |
| SL_02 | train | SL | 6.089 | 5.927 | 4.799 | **5.202** | 102.4 | 100.7 | **56.3** | 7.960 | 8.296 | **6.258** |
| SL_03 | train | SL | 1.256 | 0.246 | 0.098 | **1.983** | 53.8 | 6.0 | **58.7** | 1.314 | 0.394 | **3.384** |
| SL_04 | val | SL | 1.148 | 0.790 | 0.179 | **1.818** | 48.9 | 21.7 | **44.8** | 0.688 | 1.401 | **3.211** |
| SL_05 | test | SL | 1.334 | 0.550 | 0.393 | **1.044** | 53.2 | 7.5 | **22.1** | 0.997 | 0.640 | **1.196** |
