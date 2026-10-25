Windows 11 Optimizer - VM TEST EDITION
=======================================

This is a trimmed copy of the tool for testing inside a virtual machine. It is NOT for your real PC.
Left out: the manuals and pictures, the GPU guide, repair-tools, the README files, the repository tests.
Added: the VM_TEST folder with an automatic test suite, and tests\Test-RegRoundTrip.ps1.

HOW TO TEST (about 10 minutes without the long Easy Setup run, up to an hour with it)
  1. In VirtualBox take a snapshot of the clean Windows, for example "01 clean Windows".
  2. In the VM open this folder (the shared folder "optimizer", or copy it into the VM).
  3. Right-click  Run_VM_Tests (Run as Administrator).bat  and choose Run as administrator.
     Add -SkipEasyFull after the name (in a command window) to skip the long real Easy Setup run.
  4. Read the SUMMARY at the end. Every phase says PASS or FAIL.
  5. The report and the outputs of every phase are saved in the shared folder "reports"
     (on the host: the _reports folder next to this folder), or on the VM desktop in VMTEST_Reports.
  6. Go back to the snapshot before the next run.

FROM THE HOST, WITHOUT TOUCHING THE VM (VirtualBox)
  powershell -File tests\vm\Run_In_VM.ps1
  It restores the snapshot "04 updates finished, UAC prompt off" (the clean Windows after its background updates were installed; with the older snapshot 02 the updates install during the run and the restore point times out), boots the VM, copies this edition into it, runs the suite elevated,
  waits for the summary and copies the reports to _reports\run_<time> here. About 15 minutes on a slow host.
  The VM account is the throwaway one from VirtualBox's unattended install (vboxuser / changeme). Take snapshots only while the VM is
  powered off: restoring the saved state of a running VM crashed the VM on the test host.

WHAT THE SUITE DOES
  P0   checks the VM (administrator, free space, internet) and turns System Protection on
  P1   runs every read-only tool and checks the support bundle (sections present, no user or computer name)
  P2   applies and undoes every tweak and checks each one (tests\Test-RegRoundTrip.ps1)
  P3   runs the main menu with typed answers (starts, reverts one tweak, shows health, bundle, specs, exits)
  P4   Easy Setup settings step for the profiles games, max and max13, then reads the settings back
  P5   undoes everything with the undo files and checks that nothing still reads OK
  P6   Easy Setup, the whole flow for real: restore point, drivers, Windows Update, settings, summary
It refuses to run on a physical PC.

NOT AUTOMATED (do these by hand in the VM, then look at the result)
  - 2_Revert_Everything (it uses System Restore and restarts the VM)
  - Easy Setup answered by hand (typing Y, N, R, S at the questions) and a restart in the middle ("continue where it stopped")
  - Menu L (clean up), the DNS choice, the laptop path

The report from the VM can be sent back: copy the VMTEST_<date> folder from the "reports" folder.

------------------------------------------------------------------------------------------------
ภาษาไทย (สั้นๆ)
  นี่คือชุดทดสอบสำหรับใช้ในเครื่องเสมือน (VM) เท่านั้น ห้ามใช้กับเครื่องจริง
  1. ถ่าย snapshot ของ Windows ที่สะอาดใน VirtualBox ก่อน
  2. ใน VM เปิดโฟลเดอร์นี้ (shared folder ชื่อ optimizer) คลิกขวา Run_VM_Tests (Run as Administrator).bat แล้วเลือก Run as administrator
  3. อ่านสรุปท้ายจอ แต่ละข้อขึ้น PASS หรือ FAIL
  4. รายงานอยู่ใน shared folder ชื่อ reports (บนเครื่องจริงคือโฟลเดอร์ _reports ข้างโฟลเดอร์นี้)
  5. ก่อนรันรอบใหม่ ให้กลับไปที่ snapshot
  ส่วนที่ต้องทดสอบด้วยมือ: 2_Revert_Everything, การตอบคำถาม Easy Setup เอง, รีสตาร์ทกลางทาง, เมนู L
