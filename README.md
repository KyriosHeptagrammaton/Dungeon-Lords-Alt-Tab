# Dungeon Lords — Borderless + Widescreen + UI Scale Fix

A patch for the original **Dungeon Lords** (2005, `dlords.exe` from January 2006) that makes it play nicely on modern Windows and widescreen monitors.

## What it changes

- **Borderless window, no mode switch.** The game covers your whole screen without changing the display resolution. Alt-Tab in and out works without freezing or a black screen.
- **3D at your desktop's native resolution.** This works at any size: 1080p, 1440p, 4K, 16:10 or ultrawide.
- **The resolution option now sets the UI size:**

  | Option in the menu | Now means | Result |
  |---|---|---|
  | 4th (labelled 1600x1200) | 1920x1080 | Normal-size UI, full width |
  | 5th (labelled 2048x1536) | 1280x720 | 1.5× bigger UI, full width |
  | 800x600 / 1024x768 / 1280x1024 | unchanged | Bigger UI with black bars at the sides |

  The UI art is scaled smoothly while the 3D stays sharp.
- **The equipment screen** places the character model correctly in the new 1920x1080 and 1280x720 modes.
- **Closing works.** Closing from the taskbar ✕ or with Alt+F4 really quits the game. Before, it kept running in the background with the music playing.

## Requirements

- `dlords.exe` from January 2006, exactly **2,707,456 bytes**. The installer accepts either:
  - the untouched exe (SHA-256 `D7E05B26E3574BE3317B26338F8ED4C21EE10900EF048FFF81B42663330ED954`), or
  - the exe with the WSGF 1920x1080 hex edit (SHA-256 `FF3483DBDDAF23A447E03E39401E81F1178F9FCFA6623608ADAAF644ED618E75`).
- Other versions (Steam, MMXII, Collector's Edition) are **not** supported. The installer checks the version and refuses to change anything it doesn't recognise.

## Install

1. Download this repository (green **Code** button → **Download ZIP**) and unzip it.
2. Copy `Install.bat`, `patch.ps1` and `Uninstall.bat` into your Dungeon Lords folder, next to `dlords.exe`.
3. Double-click **Install.bat**. If the game is under Program Files, it will ask for administrator permission.
4. In the game's options, choose the **4th** or **5th** resolution.

The installer keeps your original as `dlords_original.exe`, and it checks that the patched file is byte-for-byte correct before replacing `dlords.exe`. To undo the patch, run **Uninstall.bat**.

## Important Windows settings

Right-click `dlords.exe` → **Properties** → **Compatibility**:

- **Do not** tick "Run this program as an administrator". When the game runs elevated, Windows can stop sending it mouse and keyboard input, and the menus stop responding.
- Ticking **"Disable fullscreen optimizations"** is recommended.

**Saves:** if the game is installed under Program Files, Windows quietly redirects new saves to `%LOCALAPPDATA%\VirtualStore\Program Files (x86)\Dreamcatcher\Dungeon Lords`. To keep all your saves in one place, install or copy the game to a folder such as `C:\Games\Dungeon Lords`.

## Known limitations

- The in-game brightness (gamma) slider has no effect in borderless mode.
- The menu still shows the old resolution names.
- Pre-rendered cutscene movies keep their original size.

## How it works

The patch adds a new code section (`.dlfix`) to the exe and hooks the game in several places:

- **Display:** the Direct3D 9 device is created windowed, with a backbuffer at desktop size.
- **Rendering:** the viewport and 2D draw calls are redirected so the 3D fills the screen.
- **UI:** the software-drawn UI canvas is uploaded to a texture and drawn scaled.
- **Mouse:** mouse coordinates and the cursor clip rectangle are mapped back to the game's resolution.
- **Closing:** `WM_CLOSE` shuts down DirectInput, releases the mouse and exits cleanly.

The source is in [`src/`](src):

- [`patch.s`](src/patch.s) is the x86 assembly.
- [`build.py`](src/build.py) applies it to `dlords.exe`. Run `python3 build.py dlords.exe` on Linux or WSL with binutils installed. It needs the hex-edited exe as input.

This repository doesn't contain any of Dungeon Lords' own files, so you need your own copy of the game.
