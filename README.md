# win11-optimizer

## Download / ดาวน์โหลด

### [Download the latest ZIP (click here) / ดาวน์โหลดไฟล์ ZIP ล่าสุด (กดที่นี่)](https://github.com/Kensukeimagery/win11-optimizer/releases/latest/download/win11-optimizer.zip)

1. Click the link above. The ZIP downloads by itself, no GitHub account needed. / กดลิงก์ด้านบน ไฟล์ ZIP จะโหลดทันที ไม่ต้องมีบัญชี GitHub
2. Right-click the ZIP > **Extract All**, then open the extracted folder. Do not run files from inside the ZIP. / คลิกขวาที่ ZIP > **Extract All** แล้วเปิดโฟลเดอร์ที่แตกออกมา อย่ารันไฟล์จากในไฟล์ ZIP
3. Read the manual in `docs/` first (English or Thai), then follow the quick start below. / อ่านคู่มือในโฟลเดอร์ `docs/` ก่อน (มีทั้งไทยและอังกฤษ) แล้วทำตามขั้นตอนเริ่มใช้งานด้านล่าง

Link not working? Use the green **Code** button on this page > **Download ZIP**. / ถ้าลิงก์ใช้ไม่ได้ ให้กดปุ่มสีเขียว **Code** ในหน้านี้ > **Download ZIP**

---

[ภาษาไทย](#ภาษาไทย) | [English](#english)

---

## English

A small, transparent set of batch/registry scripts to tune Windows 11 for gaming and lower background load. Every change lives in a readable `.reg` file, is backed up before it is applied, and can be reverted one by one.

> **Use at your own risk.** These scripts edit the registry and power settings. Use them only on your own PC. Create a restore point first (the script offers to). Some antivirus tools may flag `.bat` files that edit the registry; read the files before running.

### Quick start
1. Download the ZIP (see the link at the top), extract it, and **keep all folders next to the scripts**.
2. Right-click `1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat` > **Run as administrator**.
3. Press `5` (restore point + everything). Answer the Y/N questions for the optional tweaks.
4. Restart Windows.
5. Later (for example after a big Windows update) run `3_Check_Status` to find settings that were reset.

### Layout
| Path | Purpose |
|---|---|
| `docs/` | Manuals (PDF, English and Thai): run order, what each .reg does, manual Windows settings, references. HTML sources are in `docs/src/` |
| `1_Start_Here ... .bat` | Main menu |
| `2_Revert_Everything ... .bat` | Restore to the `Before_PC_Optimizer` restore point |
| `3_Check_Status ... .bat` | Check which tweaks are still applied |
| `4_Network_Test.bat` | Read-only ping, jitter and packet-loss test (no admin needed) |
| `5_System_Report.bat` | Read-only report of CPU/RAM users, startup programs, disk space, GPU driver age (no admin needed) |
| `reg/` | Tweaks: `1_Recommended` (01-08), `2_Optional` (09-13), `3_Power` (14) |
| `reg_undo/` | One undo file per tweak (Windows defaults) |
| `tools/` | PowerShell helpers used by the menu (keep this folder) |
| `repair-tools/` | Deep clean, network reset, Bluetooth fix, DISM + SFC |

### Main menu
`1` Recommended, `2` Optional 09-13, 15, 16 (one by one), `3` Base setup (power plan, services, SSD/HDD check, temp cleanup), `4` Power settings, `5` Everything, `6` Restore point only, `7` Revert one tweak, `8` Disk type, `9` Power Options, `C` Check status, `N` Network test, `R` System report.

### Honest expectations
These tweaks give small, situational gains. GPU driver updates, in-game settings, XMP/EXPO and cooling matter far more. Items without official Microsoft documentation are marked as community-sourced in the manual's References page.

### Requirements
Windows 11, administrator rights. Built for desktops; expect more heat and battery drain on laptops. Manuals: [English](docs/Manual_EN_v4.5.pdf) and [Thai](docs/Manual_TH_v4.5.pdf). The scripts print English.

### License
MIT, see `LICENSE`.

---

## ภาษาไทย

ชุดสคริปต์ .bat/.reg ที่โปร่งใส สำหรับปรับ Windows 11 ให้เหมาะกับการเล่นเกมและลดโหลดเบื้องหลัง ทุกการเปลี่ยนแปลงอยู่ในไฟล์ .reg ที่เปิดอ่านได้ ถูกสำรองก่อนแก้ และย้อนกลับได้ทีละข้อ

> **ใช้ด้วยความเสี่ยงของตัวเอง** สคริปต์แก้ registry และ power settings ใช้กับเครื่องของตัวเองเท่านั้น สร้างจุดคืนค่าก่อนเสมอ (สคริปต์ถามให้) แอนตี้ไวรัสบางตัวอาจเตือนไฟล์ .bat ที่แก้ registry ควรเปิดอ่านก่อนรัน

### เริ่มใช้งาน
1. ดาวน์โหลดไฟล์ ZIP (ลิงก์อยู่ด้านบนสุด) แตกไฟล์ และ**เก็บทุกโฟลเดอร์ไว้ข้างสคริปต์**
2. คลิกขวา `1_Start_Here - PC_Optimizer_Master (Run as Administrator).bat` > **Run as administrator**
3. กด `5` (จุดคืนค่า + ทุกอย่าง) แล้วตอบ Y/N ข้อ Optional
4. รีสตาร์ทเครื่อง
5. หลังอัปเดต Windows ใหญ่ๆ ให้รัน `3_Check_Status` เพื่อดูว่าค่าไหนถูกรีเซ็ต

รายละเอียดแต่ละไฟล์ ลำดับการรัน และการตั้งค่า Windows เพิ่มเติมอยู่ในคู่มือ PDF: [ภาษาไทย](docs/Manual_TH_v4.5.pdf) | [English](docs/Manual_EN_v4.5.pdf)

### ความคาดหวังที่เป็นจริง
tweak เหล่านี้ให้ผลเล็กน้อยเฉพาะสถานการณ์ ไดรเวอร์การ์ดจอ การตั้งค่าในเกม XMP/EXPO และการระบายความร้อนสำคัญกว่ามาก รายการที่ไม่มีเอกสารทางการของ Microsoft ระบุไว้ในหน้าแหล่งอ้างอิงของคู่มือ

### สัญญาอนุญาต
MIT ดูไฟล์ `LICENSE`

