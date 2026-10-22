# Changelog

## v4.31
- **One logo everywhere.** The banner showed a gauge, the program showed a check mark. Now all of them show the same new mark, a gauge pushed into the red zone (performance, running at full speed): the README banner, the GitHub social preview, the icon of `Win11 Optimizer.exe` and the logo in the window (light and dark). The mark is drawn by one script, `docs/src/make_logo.py` (banner, social preview and icon); the window logo is the same drawing in XAML.
- The pictures of the window in the README and the manuals are new.
- Nothing else changed: the tweaks, tools and tests are as in v4.30.

## v4.30
- **Five new optional tweaks (21 to 25),** found by reading what the well-known tuning tools (winutil, Sophia Script) and Microsoft's own pages offer and keeping only what is documented or harmless and can be undone:
  - **21 Windowed-game optimization:** turns on the Windows 11 setting "Optimizations for windowed games" (Microsoft documents it: DirectX 10 and 11 games in a window or borderless window use the flip model, with lower frame latency). It is one flag inside a text value that also holds other graphics choices (Auto HDR, the chosen graphics card). A helper script (`tools\Game_Settings.ps1`) changes only that flag and keeps the rest; undo puts it back to what it was. A plain `.reg` file would have overwritten the other flags, so this one is not a `.reg` file.
  - **22 Network adapters stay on:** switches off "Allow the computer to turn off this device to save power" on every network adapter that offers it (`tools\Nic_Power.ps1`), through the WMI value `MSPower_DeviceEnable` that is behind that Device Manager checkbox. The adapters that had it on are remembered and undo switches on exactly those. A PC without the setting skips it. Not applied by Easy Setup on a laptop.
  - **23 Game Mode on**, **24 End task in the taskbar** (Windows 11 23H2 or newer), **25 Background apps off:** small `.reg` tweaks of the current user, each with an undo file.
- The games profile of Easy Setup now also applies 21, 23 and (desktop only) 22; Maximum adds 24 and 25 as well. The safe profile applies none of them.
- **Change: the Prefetcher is no longer switched off on an SSD.** Windows manages it itself on an SSD, and Microsoft once turned it off on all SSDs and had to undo that after regressions on some PCs. The menu now leaves it as Windows has it; Check Status accepts 3 (the Windows default) and, for PCs set up by an older version, also 0. Nothing is changed back for you. Menu 7, then F still restores 3. A hard drive keeps 3 as before.
- Windows app: 21 to 25 are switches in the Tweaks page, in English and Thai. Menu 7 (revert one) and `/apply`, `/revert` know 21 and 22.
- Bug found by the VM test and fixed before release: the first version of 22 used `Set-NetAdapterPowerManagement -AllowComputerToTurnOffDevice`, but that cmdlet has no such parameter (the value can only be read with the Get cmdlet), so applying 22 failed on the VM adapter. It now sets the WMI value directly. The VM suite phase P5b now also checks that 21 and 22 read OK right after `/apply`; that check is what caught this.
- Bug found while testing the new helper and fixed before release: `@($list)` on a generic list fails with "Argument types do not match" in Windows PowerShell 5.1; the helper now returns an array. A test now runs both helpers' Query action and fails on any error text.
- Tests: values and undo files of 23-25; the whole Apply and Undo flow of the windowed-games helper against a temporary registry key in every starting state (no value, another flag only, the flag set to 0); the network adapter helper against made-up adapters (runs where administrator rights exist, i.e. CI); menu, Easy Setup profiles and revert routing; the Prefetcher change. The VM suite knows the new profile rules, and a new phase P5b applies 16, 21 and 22 with `/apply`, undoes them with `/revert` and checks that another graphics flag in the same value survives.

## v4.29
- **Three new optional tweaks,** picked from a hand-made tuning pack and kept only where they are safe, useful and undoable. None of them raises FPS; they keep the PC predictable and make it feel quicker.
  - **18 Drivers only from you** (`SearchOrderConfig = 0` and the policy `ExcludeWUDriversInQualityUpdate = 1`): Windows Update no longer installs drivers by itself, so it cannot replace the graphics driver you installed. Update drivers with menu D or the maker's website. Windows Update may show "Some settings are managed by your organization": that is this policy.
  - **19 Startup programs start at once** (`StartupDelayInMSec = 0`): the programs in the startup list no longer wait about ten seconds after sign-in. Takes effect at the next sign-in; it does not make Windows boot faster.
  - **20 Quick menus** (`MenuShowDelay = 0`, `MouseHoverTime = 100`): menus open at once and hover reactions come sooner. A feel change only. The hover time is not set lower on purpose (very short values make thumbnails flicker).
- Each has an undo file (menu 7, then 18, 19 or 20; the Windows app has a switch for each), is asked one by one in menu 2 and 5, and is applied by the **Maximum** profile of Easy Setup only. The safe and games profiles leave them off.
- **Check Status looks at SSD TRIM** (only when Windows is on an SSD): it reads `DisableDeleteNotify` and can turn TRIM back on. TRIM is on by default, so this only finds a setting somebody turned off.
- Left out on purpose: smaller keyboard and mouse queues (no proof they lower lag, and they can drop input under load), 8.3 names off, Prefetch off, fixed GPU-scheduling and preemption values, game launch options and MSI mode (the NVIDIA driver already sets it).
- Manuals and README list the new tweaks (cards, sources, "without official documentation" note); the app shows them in the Thai and English lists.
- Tests: values and undo files of 18-20, the menu and Easy Setup profiles, the TRIM check, and a check that every tweak of the app has a Thai text. The VM suite knows which profile must leave 18-20 on. Not yet run in the VM.

## v4.28
- **New: a Windows app, `Win11 Optimizer.exe`.** One small file (about 100 KB, no installer) in the main folder, next to the three `.bat` files. Click instead of typing: **Easy Setup** (it asks how you use the PC, then runs in its own window), one switch for each of the 16 tweaks with its state (On, Off, Changed by Windows), the tools (PC specs, PC health, System report and Support bundle show their result inside the window; Check status, Network test, Drivers and Clean up open their own window), the undo options, and the update check. Light or dark as Windows is set, and a switch for **English or Thai** in the side bar (kept for next time). A restore point is offered before the first change. It only starts the existing scripts, so nothing about what the tool does has changed. The program is not code-signed: SmartScreen may ask you to click More info, Run anyway; the `.bat` files still do the same.
- It is built from the sources in `app/` (C#, WPF) with the compiler that ships with Windows (`powershell -File app\build.ps1`, nothing to download). The release job builds it and puts it in the ZIP; CI builds it and runs its self-test on every change. The `app/` sources are not part of the ZIP.
- The main menu file takes two new commands for the app: `/apply 10` and `/revert 10` (one tweak by number, no questions, no pauses). `tools\Gui_Status.ps1` prints the state of every setting (read-only).
- README and both manuals show the app (new page "The Windows app" in the manuals).
- The VM test suite has a new phase P7 that runs the app's self-test inside the VM.

## v4.27
- **VM test edition (for testing only, not in the download ZIP).** `tests/vm/Make_VM_Edition.ps1` builds a trimmed copy of the tool (no manuals, pictures, GPU guide, repair-tools or README; about 330 KB) with an automatic test suite for use inside a virtual machine. The suite (`VM_TEST\vm_tests.ps1`, started with `Run_VM_Tests (Run as Administrator).bat`) runs the read-only tools, checks the support bundle, applies and undoes every tweak, drives the main menu, runs the Easy Setup profiles games, max and max13 and reads the settings back, undoes everything, and runs the whole Easy Setup flow for real (restore point, drivers, Windows Update). It writes one report and refuses to run on a physical PC. `tests/vm/Create_Test_VM.ps1` makes the empty VirtualBox machine (EFI, TPM 2.0, Secure Boot, shared folders); you install Windows yourself.
- Easy Setup has a new switch `-SkipUpdate` (skips the update check; the VM suite and CI use it, so a test copy never replaces itself).
- Tests check the builder, the guest suite (dry run), the VM creator (dry run) and that nothing is wiped by mistake.

## v4.26
- **New NVIDIA driver settings guide (English and Thai, 20 pages each),** replacing the old 5-page one: Quick setup in nine steps, then every page of NVIDIA Control Panel step by step with annotated screenshots (Adjust image settings, the whole Manage 3D settings list in three parts, PhysX, desktop size, G-SYNC), the V-Sync / frame cap / Low Latency choice in two ready styles, Windows and monitor checks, driver update / clean install / roll back, a troubleshooting table, a one-page cheat sheet, the long explanation of every setting, a glossary and the sources. The screenshots are an example from driver 582.78 on a GTX 1070 (a security-only driver for Pascal); the advice applies to other GeForce cards, and a new section lists the options that RTX cards and newer drivers add (DLSS overrides, Smooth Motion, Resizable BAR, DLDSR, RTX Video, the NVIDIA App).
- The guides use the same page design as the user manuals and are built with the same script (`python docs/src/build_manuals.py gpu_guide`). The old `style.css` is removed.
- Tests check every section, its page number and each screenshot.

## v4.25
- **Fix (v4.24 only):** Easy Setup said "An earlier Easy Setup was started" on every run and printed `profile_`. v4.24 lost the line that reads the saved state when the language question was removed. Now it only offers to continue when a run really was left unfinished. If you pressed Y on that question, nothing was changed: close the window and open Easy Setup again.
- Tests: a check that the saved state is read before it is used, and CI fails if the whole-flow run mentions an earlier Easy Setup or prints `profile_`.
- The main menu picture in the README and the manuals is the v4.24 screen.

## v4.24
- **Easy Setup is English only.** The language question is gone (the old console window shows Thai as question marks, and one language is simpler to keep correct). Everything the program prints is English; the Thai manual explains every message and quotes the English wording next to the Thai meaning. `-Lang` is removed from `Easy_Setup.ps1` and `easy_th.txt` is deleted, so the ZIP is smaller. The Thai README and Thai manuals stay.
- The manuals no longer tell you to choose a language.

## v4.23
- **New user manuals (English and Thai).** Rebuilt for people who have never used the tool: a one-page cover that says where to start, "Before you start", a six-step Quick start with a numbered card per step and what you should see after it, a "Which button do I press?" table, the three ways to undo, Troubleshooting (16 symptoms with the fix), a Glossary, Questions and answers, and the old reference pages gathered at the back. The Maximum profile is explained too. 27 pages each, with page numbers in the contents.
- The manuals are now built by `docs/src/build_manuals.py` from `manual_en.html` / `manual_th.html` and `manual.css` (Edge and PyMuPDF; the contents page numbers are filled in automatically).
- Tests check that every manual section exists and has a page number. No change to how the tools work.

## v4.22
- **Easy Setup: "Maximum".** If you say you mainly play games, a second question offers every optional tweak in one go: fullscreen exclusive (09), mouse (10), keyboard (11), Ndu fix (12), timer (15) and CPU boost (16). Turning Memory Integrity off (13) stays behind its own typed YES (default no) because it lowers protection. On a laptop, timer and CPU boost are skipped. Main menu `5` is unchanged and still lets you choose each tweak yourself. For scripts: `-Mode max` and `-Mode max13` for Easy_Setup.ps1, `/easy max` and `/easy max13` for the main menu file.
- The preview and the plan name the profile in words (Thai too) instead of an internal id.
- Tests: the choice rules, the plan lines and the preview of both new profiles. CI runs `/easy max` and `/easy max13` on a disposable machine and checks that the tweaks are in place (13 only after max13).

## v4.21
- The download ZIP no longer contains the `.gitignore` file (it is only for the GitHub repository). The main folder now shows just the three files to click, the README, CHANGELOG, LICENSE and VERSION. If you updated from an older version, an old `.gitignore` stays in your folder; you can delete it, nothing uses it.
- The README picture of the main menu is the current one (v4.20 layout).
- Nothing else changed in how the tools work. A test checks that the ZIP leaves out the repository-only files.

## v4.20
- **Tidier main folder.** Only three files are left to double-click: `0_Easy_Setup`, `1_Start_Here` (main menu) and `2_Revert_Everything`. The nine extra tools (`3_Check_Status`, `4_Network_Test`, `5_System_Report`, `6_Check_For_Updates`, `7_Driver_Check`, `8_PC_Health`, `9_Support_Bundle`, `S_PC_Specs`, `L_Clean_Up`) moved into the new `More Tools` folder, with a short guide (`About these tools.txt`). Every one of them is still reachable from the main menu, and their reports still go to the `Logs` folder of the main folder.
- The main menu keeps the name `1_Start_Here ...` on purpose, so the updater of older versions (which looks for that name) can install this version. An update from v4.19 moves the old launchers into the backup folder and installs the new layout; a test runs exactly that with the real v4.19 updater.
- If you made a desktop shortcut to one of the nine tools, point it to the new place (`More Tools`). Keep the `More Tools` folder next to the `tools` folder.
- The updater manages the `More Tools` folder in later updates (old files in it are saved to the backup and replaced).
- Messages and the README / manuals say where the moved tools are. Nothing else changed in how the tools work.
- Tests: the layout (three files in the main folder, nine in `More Tools`, each finds the main folder and its script), the updater from the old layout, and CI runs three of the moved tools for real and checks that their reports land in the main `Logs` folder.

## v4.19
- Found in the VirtualBox test of v4.18 on a clean Windows 11 (build 26300). No setting or driver logic changed.
- **Easy Setup summary:** "before" and "now" are shown against the same total (it said "0 of 16 before, 21 of 21 now" because settings that were never set up were not counted before). The line after step 3 now says how many settings are in place without a total.
- **Easy Setup report is written while it runs**, line by line, so closing the window half way no longer loses the first part. The letters you typed as answers (Y, N, S, R, ...) are saved in the report too. The preview still writes nothing, and the file is always in the Logs folder.
- **Language prompt:** it shows "T = Thai" in plain letters (the Thai word showed as ??? in the old console), says to choose E if Thai looks broken, and English is now the default everywhere (Thai only when you chose it before).
- PC specs: the hint for a PC without the optimizer settings now points to E (Easy Setup) in the main menu.
- Tests for the new summary numbers and for the report that is written line by line.
- Not changed on purpose: remembering which steps were skipped for lack of internet and offering only those later (a bigger change to the flow, kept for a later version).

## v4.18
- **Driver cleanup no longer repeats work for a package Windows refuses to remove.** Some packages (for example a driver extension) answer "still needed" every time. They are now remembered (per package and version, in the registry value `CleanKept`) and left out of the offer for 30 days, so cleanup does not make another restore point and another copy for nothing; after 30 days it tries once more. The scan lists them as "left out", and the check after a cleanup says so. Found on a company PC where the same AVerMedia extension was offered again on the next day.
- Tests for the remembering rule (recent, old and unrelated refusals, stable key); the registry write and read were also checked once in a throwaway key.

## v4.17
- Found by the first Easy Setup run on a company PC (Thai regional date format). **PC specs: wrong "older than 4 years" list fixed.** That PC returned driver dates 543 years too early (the Buddhist-era shift), so every network, graphics, sound and Bluetooth driver, even a 2026 graphics driver, was listed as old. The date is now put back when it is clearly shifted, and a driver whose date cannot be trusted is not listed at all. A test covers it.
- The main menu no longer logs "StartService FAILED 1056 ... already running" for Search and Print: the service is started only when it is not running yet.
- The Easy Setup report now says your answer to the one question (gaming or not), in Thai and English.

## v4.16
- **New: Easy Setup, one button** (`0_Easy_Setup (Run as Administrator).bat`, or **E** in the main menu, `tools\Easy_Setup.ps1`). For a new Windows install, first-time users and people who do not know computers. It asks the language (Thai or English) and one question (do you mainly play games?), shows the plan, then runs everything in the best order: check for a newer version, restore point, remember how the PC is now, internet check, Windows Update (guided: it opens the page, you press install), recommended drivers (the graphics driver page opens if it is missing), restart if needed (run it again to continue where it stopped), safe speed settings, optional faster DNS (default no), and a one-page before/after summary with things worth a look. Drivers and updates come first and the settings last, because updates and drivers can change settings. A laptop skips the settings that make it hotter. Nothing is deleted. The PC is kept awake while it runs. `-Preview` shows the plan and changes nothing.
- Not included on purpose: the Memory Integrity tweak, driver and file cleanup, network reset, and changing DNS without asking.
- Support for it: the main menu has an `/easy` entry (recommended settings, base setup and power settings, plus mouse, keyboard, timer and CPU boost for the gaming profile; no questions, no pauses; the laptop questions are decided automatically); the driver check has an automatic mode (`-Auto`) that installs the recommended drivers without a full driver copy; messages live in `tools\lang` (Thai and English) and a test checks that both have the same keys.
- PC health: a program that crashed many times is shown as a CHECK only while it is still installed and crashed in the last 3 days; otherwise it is an INFO line with the last crash time (history, nothing to do). Fixes the NoiseCancelingEngine line that stayed after ASUS was removed.
- Tests: the message files, the order of the steps, the rules, the preview in both languages (it must change nothing) and the new menu entry; CI also runs the `/easy` settings step on a disposable machine and checks that the settings are in place.

## v4.15
- **Tidy folder: reports and logs go to a `Logs` folder.** Every tool saves its report there, and the main menu logs there too, so the folder next to the scripts stays clean. Reports saved next to the scripts by older versions are moved into `Logs` once (nothing is overwritten or removed).
- **Old reports are removed automatically:** the newest 3 of each kind are kept (a support bundle keeps 5), checked when the menu opens and after each tool. Only files with exactly the names this program creates, inside `Logs`, are ever removed; `Backup` is never touched by this. A menu session in which nothing was run leaves no log at all.
- **New: `L_Clean_Up.bat` / menu L.** Shows what is in `Logs` and `Backup` with sizes, lets you change how many reports are kept (0 = never remove), and lists older backups to remove ONLY after you say yes (default no). It keeps the newest full driver copy, the newest 2 driver-cleanup copies, the newest 2 earlier program versions and the newest 10 registry copies.
- Driver check: for a few low-impact drivers (fewer than 4, none of them important) the multi-GB full driver copy is now optional and off by default, because the restore point is already made. Important drivers or 4 or more still get the copy.
- Small fixes: the cable-speed note in PC specs starts with a capital letter; a stray comment in the PC specs source is cleaned up.
- Tests for the report names, the keep rule, moving old reports, the safety checks and the backup rules, run on a temporary folder.

## v4.14
- **New: PC specs on one page** (`S_PC_Specs.bat`, menu **S**, `tools\PC_Specs.ps1`). Read-only, in plain words, for people who do not know where to find their specs: computer and motherboard, Windows, processor (cores and threads), memory (size, type, speed, slots used), graphics card (video memory, NVIDIA driver number), every screen with resolution and refresh rate, every drive (SSD or HDD, size, free space, which one holds Windows), the network link, and Secure Boot and TPM. Short notes say what a number means; no serial numbers, MAC or IP addresses, so the page can be shared. It ends with a check-up: do the drivers and the settings fit together (every device has a working driver, a maker graphics driver, old network/graphics/sound/Bluetooth drivers, the optimizer settings still in place, screens at their highest refresh rate, RAM at its rated speed, cable at full speed). It is also a section of the support bundle.
- The screen helper moved to `tools\Display_Info.ps1` and the shared hints (RAM speed, cable speed, refresh rate) to `tools\Check_Rules.ps1`, both used by PC health and PC specs.
- Tests for the new rules and a CI step, and the main menu test now also runs S.

## v4.13
- **New: NVIDIA driver settings guide** (`docs/GPU_Driver_Guide_EN.pdf` and `GPU_Driver_Guide_TH.pdf`, 5 pages each). Every setting of NVIDIA Control Panel (Manage 3D settings, G-SYNC, resolution) with what it is, what each option does, the default and a recommended value; two ready profiles (maximum FPS / smooth with G-SYNC); Low Latency Mode On versus Ultra; how to tell a GPU limit from a CPU limit without any overlay; and a plain list of what is safe for anti-cheat and what to avoid. Written around a GTX 1070, valid for most GeForce cards. It only covers driver settings and never touches game files.
- The main manuals point to the guide. Tests check that the guide files exist.

## v4.12
- **Fix: Prefetcher is decided from the drive Windows is installed on.** The menu (option 3 and 5) and Check Status used "disk 0" to decide between SSD (Prefetcher off) and HDD (keep on). Disk 0 is not always the Windows drive: with an SSD as disk 0 and Windows on a hard drive, Prefetcher would have been switched off on the HDD, which slows start-up. Now the drive that holds C: is used; if it cannot be identified, Prefetcher is left alone.
- **PC health:** a program that crashed 5 or more times is shown with its file location, how many days it crashed on and a plain-words error (for example "access violation"); hard drives no longer show a meaningless "0% worn"; the note about administrator rights only appears when you are not running as administrator.
- Tests for the above.

## v4.11
- **New: PC health** (`8_PC_Health.bat`, menu **H**). Read-only. Blue screens, unexpected shutdowns, graphics driver resets and crashed programs from the last 30 days (blue screen codes explained in plain words); drive health, temperature and wear; battery wear on laptops; and three things that matter for games: whether each screen runs at its highest refresh rate, whether the RAM runs at its rated speed (XMP / EXPO), and whether the network cable link is slower than the adapter supports.
- **New: support bundle** (`9_Support_Bundle.bat`, menu **B**). Puts the version, Windows build, Check Status, PC health, system report, a driver scan (this PC only), saved choices and the latest logs into ONE text file to attach to a problem report. User name, computer name, home network addresses, MAC addresses and e-mail addresses are replaced. Nothing is changed or sent.
- Tests for the new rules (blue screen codes, drive, RAM, cable and refresh-rate hints, the privacy replacements) and a CI step that runs both tools on a disposable machine.

## v4.10
- **DNS change: the backup can no longer be lost.** After a real change on a PC the registry copy of the saved DNS settings was missing while the backup file was still there, so Network Test would not offer "U = put back the DNS I had before". Now Network Test also offers U when only the backup file exists, a later change reads the file instead of treating the current DNS as the original, the registry copy is restored and checked after every change, and a successful Undo removes the file so an old backup is never mistaken for a new one. Undo itself always worked from the file.
- Tests for the above (including a dry run of Undo with only the backup file).

## v4.9
- **Power plan is never downgraded.** If Ultimate Performance cannot be added (for example on a company PC where Windows or a policy blocks it) and you are already on a custom performance plan, the menu now keeps it instead of switching to High Performance; when it does fall back to High Performance it says why. Check Status accepts a custom plan that already keeps the CPU at 100% (for example an Ultimate Performance copy made earlier) instead of offering to change it to High Performance.
- **Driver cleanup, after the first real run on a PC:** packages from Microsoft are left alone; a group where the highest version number is not also the newest date is left alone and named; Bluetooth entries are never offered; an unknown size shows `?`; step 2 now says how many copies were saved and where; when a copy cannot be saved that package is skipped and its empty folder removed; after removing, the tool checks again and the report ends with the result and a finish time.
- **Updater:** the "What is new" text is shown as plain text, wrapped to the window, without Markdown marks.
- Tests for all of the above.

## v4.8
- **Driver check, after the first real test on a PC with 83 offered drivers:** a failed item is now explained in words ("Windows Update refused it, usually because an earlier package already covers this device") instead of `result code 4`; after installing, the tool asks Windows Update again and reports what is really left, counting items that an earlier package covered as "not needed" instead of errors; long installs show one progress line (every item still goes into the report); the report keeps a finish time.
- Small chipset INF packages from Windows Update (named like `INTEL - System - 10/3/2016 ... - 10.1.1.38`) are shown in plain words and offered as optional. The manual and the tool header no longer say chipset is never installed.
- **New (beta): driver cleanup.** Menu choice **C** in `7_Driver_Check` (`tools\Driver_Clean.ps1`) lists old versions of drivers you still use and entries of devices that are no longer connected, and removes them only if you choose. The newest version, versions in use and boot-critical packages are always kept; a restore point `Before_Driver_Cleanup` and a copy of each package come first; nothing is forced; network, storage and system entries are never removed. It frees disk space; it does not raise FPS or lower ping.
- More tests: chipset title rules, result text, and the cleanup rules (156+ checks), plus a CI step that runs the cleanup scan on a disposable machine.

## v4.7
- **Safety fix: `repair-tools\Deep_Clean_Junk_Files.bat`.** Versions up to v4.6 switched on EVERY Disk Cleanup category, including the Downloads folder and the Recycle Bin, which can delete files you want to keep. The script now never cleans Downloads, asks before emptying the Recycle Bin or deleting old Windows setup files (Windows.old), and switches the categories off again that older versions had left on. If you used an older version, update and run the new one once, and check your Downloads folder.
- Other fixes from a full review: the power-plan lookup works on non-English Windows; the temp cleanup refuses to run if the temp folder is unknown; menu 7 can now also put back the telemetry services (S) and Prefetcher (F), and Check Status respects that; three undo files remove only the values their tweak added; `Create_Restore_Point.ps1` takes a name so the driver restore point is `Before_Driver_Install`; a lint step and an updater install test run on every push.
- **Driver check (beta).** `7_Driver_Check` (menu **D**) scans for devices with no working driver, shows your graphics card and driver age, and lists the driver updates Windows Update offers, split into recommended and low-impact optional. You choose: install the recommended ones, everything, one by one, open the official graphics page, or nothing. Installing happens through Windows Update after a restore point and a saved copy of your current drivers (`Backup\drivers_*`), one driver at a time, with no automatic restart. Graphics, chipset, BIOS and firmware are never installed by the tool (it points you to the maker); Windows Update graphics drivers are skipped when the maker driver is already installed. Best used on a fresh Windows install.

## v4.6
- **Self-update.** Menu **U** (or `6_Check_For_Updates`) looks for a newer release on GitHub, shows what is new, and installs it ONLY if you choose. The download is checked against a SHA-256 checksum, the old version is saved to `Backup\update_<old>_<time>` and put back automatically if anything fails. Your Backup folder, logs and reports are never touched. An optional automatic check at menu start is asked once (menu **A** turns it on or off). Updating from v4.5 or older needs one manual download.
- **Laptop and Windows guard.** The menu detects laptops and older Windows: it warns before running on Windows older than 11, and on a laptop advises against 02 and 16 and asks before applying 02.
- **Automatic checks on GitHub.** Every push is tested on a Windows machine: version consistency, syntax, batch labels, undo file for every tweak, a dry run of Check Status, and an apply-then-undo round trip of every tweak on a disposable VM.
- The four `repair-tools` scripts now use CRLF line endings like the rest.
- README: direct download link, screenshot, notes for Windows SmartScreen and for updating. Issue form that asks for the version and logs.

## v4.5
- Network Test now also measures DNS speed (your DNS vs Cloudflare, Google, Quad9) and explains how much a change would matter, then asks whether to switch. Optional **17** sets the DNS of active Ethernet/Wi-Fi adapters, saves the old settings first and undoes via the test (U) or menu 7 then 17. Check Status watches it once used. DNS does not change in-game ping.

## v4.4
- New optional tweak **15** Timer resolution (GlobalTimerResolutionRequests, with undo). Community-sourced; the manual says so.
- New optional power setting **16** CPU boost aggressive + energy preference 0 (plugged in). Your earlier values are saved first and restored by menu 7 then 16. Check Status checks it too.
- New read-only tools: `4_Network_Test` (ping, jitter, packet loss for your router, 1.1.1.1, 8.8.8.8 and an optional game server, with a plain-language verdict) and `5_System_Report` (CPU/RAM users, startup programs, disk space, GPU driver age, hints). Also menu N and R. They need no administrator rights and hide your Windows user name in saved reports.
- Manuals: new Diagnostic tools page, frame-cap / Reflex / shader-cache / network-cable advice, new references. Both languages.

## v4.3
- Check Status now prints a 'please wait, no key press needed' message while PowerShell starts and while it checks, so the window no longer looks frozen.
- Added **Check Status** (`3_Check_Status` or menu `C`): compares the live PC with every .reg file plus power plan, CPU/USB/PCIe power values, Prefetcher, TCP per adapter and services. Re-applies only what is missing or changed, backs up first, re-checks and writes `CheckReport_*.txt`.
- Remembers tweaks you chose to skip (shown as SKIPPED).
- Restore point creation now times out after 10 minutes instead of hanging at 99%.
- Manual: new Check Status page and an "External tools (optional)" page (WinUtil, RemoveWindowsAI).
- Repository release: English manual added next to the Thai one (both in `docs/`), manuals now carry a risk notice and requirements, notes added for laptops and low-RAM PCs, `repair-tools` files renamed to English.

## v4.2
- Manual: added a References page. Items without official documentation are labelled as community-sourced.
- Removed an unsourced FPS percentage for Memory Integrity.
- Added a warning for `TcpAckFrequency`.

## v4.1
- Fixed the SystemResponsiveness explanation (values below 10 are treated as the default, 20).
- `findstr` backup lookups now use `/l` so `[` is read literally.

## v4.0
- Game Mode stays on (v3 switched it off by mistake).
- TCP settings are written per network adapter, where Windows reads them.
- Removed values that equal the Windows default; merged duplicated keys.
- Power settings set automatically with `powercfg`; GPU scheduling on; Delivery Optimization off.
- Per-key backup before every change, one-by-one revert (menu 7), `reg_undo/`.
- Memory Integrity off is opt-in (type YES).
- New folder layout; Master rewritten to avoid the nested-block crashes of v3.

## v1 - v3
- Original scripts, then a single Master menu, crash fixes, an improved `repair-tools` set and the first manual.


