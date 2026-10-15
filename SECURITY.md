# Security policy

## Supported versions

Only the latest release receives fixes. Press `U` in the main menu, or run `More Tools\6_Check_For_Updates`, to get it.

## Reporting a problem

If you find a security problem in this project (a script that changes more than it says, an updater weakness, a way to make a tool run unwanted code), open an [issue](https://github.com/Kensukeimagery/win11-optimizer/issues/new/choose) titled **Security: <short topic>** and leave the technical details out. The maintainer will reply with a private way to send them. Please do not post exploit steps in public.

## How the project protects you

- Every change is a plain text file you can read before you run it.
- A restore point is made before settings change, and each tweak has an undo file.
- The updater downloads only from this repository's releases, checks the SHA-256 checksum and the file size, rejects ZIP files with unsafe paths, saves the old version first and puts it back if anything fails.
- The tools send nothing about you. The update check contacts github.com, and the driver search uses Windows Update.
- Files are not code-signed, so Windows SmartScreen may warn. Download releases only from this repository's [releases page](https://github.com/Kensukeimagery/win11-optimizer/releases).
