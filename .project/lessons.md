# WheelAthelse — Lessons Learned (Phase 1: subtask #1–#10)

> บันทึกปัญหา + วิธีแก้จากการพัฒนา Phase 1 เพื่อไม่ให้ซ้ำใน Phase 2

## Firmware (#1–#3)

### uint32 timestamp overflow
- **ปัญหา:** `DateTime.now().millisecondsSinceEpoch` (epoch ms) overflow `uint32`
  ใน BLE protocol (~1970 + 49 วัน)
- **วิธีแก้:** ใช้ relative timestamp (ตั้งแต่ boot) แทน absolute epoch
- **บทเรียน:** ตรวจสอบช่วงค่าของ data type ทุกครั้งที่ serialize ข้าม platform

### IMU batch parsing with seq gaps
- **ปัญหา:** ถ้า BLE notify หลุดบาง packet, seq จะกระโดด → ต้อง track gaps
- **วิธีแก้:** `ImuSeqTracker` ติดตาม seq ที่เห็นล่าสุด + รายงาน gap count
- **บทเรียน:** ออกแบบ protocol ให้ detect packet loss ได้ตั้งแต่แรก

## Flutter App (#4–#9)

### Widget test async hang (critical)
- **ปัญหา:** `await storage.saveSession()` ใน `stopRecording()` ค้างใน widget tests
  เพราะ test framework zone ไม่ pump microtasks จาก `async` methods ที่ไม่มี
  real async work
- **วิธีแก้:** ใช้ `tester.runAsync(() => ...)` เพื่อใช้ real event loop
- **บทเรียน:** ใน widget test, async methods ที่เป็น `async` โดยไม่มี `await`
  จะ hang — ใช้ `runAsync` เสมอ

### FutureBuilder infinite rebuild
- **ปัญหา:** `FutureBuilder(future: ref.read(...).listTopics())` ใน `build()`
  สร้าง Future ใหม่ทุก rebuild → `pumpAndSettle()` hang
- **วิธีแก้:** แปลงเป็น `ConsumerStatefulWidget` + cache Future ใน `initState()`
- **บทเรียน:** อย่าสร้าง Future ใหม่ใน `build()` — cache ใน `initState`

### share_plus v13 API deprecation
- **ปัญหา:** `Share.shareXFiles()` deprecated ใน share_plus v13
- **วิธีแก้:** ใช้ `SharePlus.instance.share(ShareParams(...))`
- **บทเรียน:** เช็ค version ของ package ก่อนเลือก API

### Abstract repository + in-memory fake file paths
- **ปัญหา:** `exportSession()` ใช้ `File(path)` แต่ `InMemoryStorageRepository`
  คืน `memory://` path → exception
- **วิธีแก้:** เพิ่ม `writeSessionCsv()` ใน interface — file impl เขียน disk,
  in-memory impl เป็น no-op
- **บทเรียน:** ออกแบบ abstract interface ให้รองรับทั้ง file-based และ in-memory
  โดยไม่ต้องมี `if (path.startsWith('memory://'))` hack

### BuildContext across async gaps
- **ปัญหา:** `if (mounted)` ไม่พอให้ lint `use_build_context_synchronously` ผ่าน
- **วิธีแก้:** ใช้ `if (!context.mounted) return;` แทน
- **บทเรียน:** lint เช็ค `context.mounted` ไม่ใช่ `State.mounted`

### Clock sync engine — NTP/PTP-lite via BLE
- **ปัญหา:** 2 ล้อมีนาฬิกาต่างกัน + BLE latency/jitter ทำให้ timestamp ไม่ align
- **วิธีแก้:** sync ping (round-trip) → offset estimation → linear drift fit →
  `timestamp_synced_ms` บน common timeline (นาฬิกามือถือ)
- **บทเรียน:** อย่าใช้ app timestamp ดิบ — ต้องมี clock sync engine

## Python tools (#10)

### Unicode encoding on Windows
- **ปัญหา:** `print("─" * 50)` ใน `check_session.py` พังบน Windows (cp1252)
- **วิธีแก้:** ใช้ ASCII (`"-" * 50`) แทน Unicode box-drawing
- **บทเรียน:** Python script ที่รันบน Windows หลีกเลี่ยง Unicode ใน print

## สรุปบทเรียนสำหรับ Phase 2
1. ตรวจสอบ data type range ทุกครั้งที่ serialize ข้าม platform
2. ออกแบบ protocol ให้ detect packet loss ได้
3. ใน widget test, ใช้ `tester.runAsync` สำหรับ async storage
4. อย่าสร้าง Future ใหม่ใน `build()` — cache ใน `initState`
5. เช็ค package version ก่อนเลือก API
6. ออกแบบ abstract interface ให้รองรับทั้ง file และ in-memory
7. ใช้ `context.mounted` ไม่ใช่ `State.mounted` สำหรับ lint
8. ต้องมี clock sync engine — อย่าใช้ timestamp ดิบ
9. หลีกเลี่ยง Unicode ใน Python print บน Windows

## Android Release / Deployment

### App crashes immediately on launch (ClassNotFoundException MainActivity)
- **?????:** APK ????????????????????? crash ?????. logcat: `java.lang.ClassNotFoundException: Didn't find class `com.wheelathlete.wheelathlete.MainActivity``n- **ROOT CAUSE:** `MainActivity.kt` ?????? `package com.WheelAthlete.WheelAthlete` (???????) ????????????? `com/wheelathlete/wheelathlete/` ??? namespace/applicationId ???????????. Kotlin ?????? package != directory ??? compile ???? ??? manifest `.MainActivity` ????????????
- **???????:** ??? `package` ?? MainActivity.kt ????????? directory + namespace (??????????????)
- **???????:**
  1. ??????? � ??? logcat ???????? (`adb logcat`). ???????????????/emulator ???????? AVD ???? `sdkmanager` + `avdmanager` ???? `flutter build apk` + `adb install` + `adb shell am start` + `adb logcat -d` ???????? stack trace ????
  2. Kotlin package ?????????? directory path ??? namespace ??? Gradle ????
  3. permissions (BLE/INTERNET) + proguard rules + google_fonts offline = ??????????????? root cause ??? crash ??? � ??????? harden ?????



---

# Phase 3 Lessons (subtask #20-#27)

## Riverpod 3.x removed StateProvider
- **Rule:** Use Notifier/NotifierProvider instead of StateProvider in flutter_riverpod 3.x+
- **Trigger:** When writing Riverpod providers with flutter_riverpod ^3.x
- **Skill:** dart-flutter-patterns
- **Severity:** medium

## PowerShell does not support heredoc
- **Rule:** Use git commit -F <file> instead of heredoc on Windows PowerShell
- **Trigger:** When committing multi-line messages on Windows
- **Skill:** git-workflow
- **Severity:** low

## showDialog returns Future<T?> not T?
- **Rule:** await showDialog result before applying ?? default
- **Trigger:** When writing confirmation dialogs returning bool
- **Skill:** dart-flutter-patterns
- **Severity:** medium

## flutter analyze catches undefined_method at compile time
- **Rule:** Use dynamic dispatch to test removed methods (throws NoSuchMethodError at runtime)
- **Trigger:** When testing that a removed method throws
- **Skill:** flutter-dart-code-review
- **Severity:** low

## IndexedStack keeps children alive - initState runs once
- **Rule:** Use ref.listen in build() not just initState for cross-tab state
- **Trigger:** When building cross-tab navigation with IndexedStack + Riverpod
- **Skill:** dart-flutter-patterns
- **Severity:** medium

## find.byType(TextField) matches multiple after adding search bars
- **Rule:** Use find.descendant(of: find.byType(AlertDialog), matching: ...) for dialog TextFields
- **Trigger:** When adding search/filter UI to pages with dialog tests
- **Skill:** flutter-dart-code-review
- **Severity:** low

## Config carry-over through countdown drops fields
- **Rule:** Explicitly forward ALL SessionConfig fields when reconstructing in notifier handoff
- **Trigger:** When adding new fields to SessionConfig and using countdown flow
- **Skill:** dart-flutter-patterns
- **Severity:** high (silent data loss)

## Sequential subagent loop for shared repo
- **Rule:** Run subagents SEQUENTIALLY not in parallel when they share the same git repo
- **Trigger:** When using run_subagent for multi-subtask implementation in a single repo
- **Skill:** continuous-agent-loop
- **Severity:** high (branch conflicts)
