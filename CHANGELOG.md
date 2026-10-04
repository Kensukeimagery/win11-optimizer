# Changelog

## v4.7
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


