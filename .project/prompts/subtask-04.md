---
PROMPT FOR SUBTASK #4: Flutter — design system / theme / reusable components (UI สวย)
---
ใช้ impeccable + ui-ux-pro-max skill เพื่อสร้าง design system ของแอป WheelSense

Context:
- Project: WheelSense
- Subtask: #4 of 10
- Stack: Flutter / Dart (ยังไม่ต่อ BLE จริงในงานนี้ — ใช้ mock data)
- Depends on: #1. ทำขนานกับ firmware (#2/#3) ได้
- Files to touch: app/lib/theme/, app/lib/widgets/, app/lib/ui/ (showcase/preview page)

งานที่ต้องทำ:
1. สร้าง design system ของแอป:
   - color palette: โหมดสว่าง + มืด, contrast สูง (ใช้กลางแดดในสนามได้)
   - กำหนดสีประจำ L (ซ้าย) และ R (ขวา) ให้ต่างชัด ใช้สม่ำเสมอทั้งแอป
   - typography scale (google_fonts), spacing scale, radius, elevation/shadow
   - ThemeData กลาง + extension สำหรับสี L/R และ semantic colors (ok/warn/error)
2. สร้าง reusable widgets (พร้อม preview):
   - ConnectionCard (แสดงสถานะ L/R: connected/connecting/disconnected + battery + signal)
   - LiveMetricTile (ค่า accel/gyro แต่ละแกน)
   - PrimaryActionButton (start/stop ใหญ่ กดง่าย)
   - MarkEventButton
   - SessionListItem (สำหรับหน้า browse topic/trial/session)
   - StatusBadge, EmptyState, LoadingState, ErrorState
3. หน้า showcase/preview รวม component ทั้งหมด (ดูง่ายตอน dev + เป็น living style guide)
4. ออกแบบให้ปุ่มหลักใหญ่ กดง่ายขณะอยู่ในสนาม, อ่าน realtime ได้ชัดขณะเคลื่อนไหว

ก่อนเขียนโค้ด:
1. อ่าน .project/architecture.md (หัวข้อ Design) เพื่อให้ครบทุก component ที่ subtask อื่นต้องใช้
2. ใช้ ui-ux-pro-max ค้น pattern ที่เหมาะกับ data-collection / sensor app
3. commit ด้วยข้อความ: "feat(app): add design system, theme, and reusable UI components"

หลังเขียน:
1. flutter analyze ผ่าน, หน้า showcase รันได้
2. อัปเดต .project/progress.md ว่า subtask #4 เสร็จแล้ว

Done when:
- มี ThemeData + สี L/R + typography/spacing ครบ
- reusable component ครบตามรายการ + มีหน้า showcase
- UI ดูสวย สม่ำเสมอ พร้อมให้ subtask #5/#6/#8/#9 นำไปใช้
