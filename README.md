# Time Pilot for [MiSTer](https://github.com/MiSTer-devel/Main_MiSTer/wiki)
An FPGA implementation of Time Pilot for the MiSTer platform

## Credits
- Sorgelig: MiSTer project lead, original port of Time Pilot to MiSTer
- Dar (http://darfpga.blogspot.fr): Original Time Pilot core design
- Ace: New Time Pilot core design & Konami custom chip implementations
- ElectronAsh: Assistance with Konami custom chip implementations
- Artemio Urbina: Hardware references for video timings, video output and audio output
- JimmyStones: High score saving support & pause feature
- Kitrinx: ROM loader

## Features
- Timing-accurate logic model made to match the original as closely as possible
- Keyboard and joystick controls
- High score saving (To save your scores, use the 'Save Settings' option in the OSD)
- T80s CPU by Daniel Wallner with fixes by MikeJ, Sorgelig, and others
- JT49 sound core by Jotego with modifications to the volume scale by Ace
- Fully-tuned switchable low-pass filters
- Option for normalized video timings to use with picky HDTVs and monitors (underclocks the game by ~1%)

## Installation
Place `*.rbf` into the "_Arcade/cores" folder on your SD card.  Then, place `*.mra` into the "_Arcade" folder and ROM files from MAME into "games/mame".

### ****ATTENTION****
ROMs are not included. In order to use this arcade core, you must provide the correct ROMs.

To simplify the process, .mra files are provided in the releases folder that specify the required ROMs along with their checksums.  The ROM's .zip filename refers to the corresponding file in the M.A.M.E. project.

Please refer to https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms for information on how to setup and use the environment.

Quick reference for folders and file placement:

/_Arcade/<game name>.mra
/_Arcade/cores/<game rbf>.rbf
/games/mame/<mame rom>.zip
/games/hbmame/<hbmame rom>.zip

## Controls
### Keyboard
| Key | Function |
| --- | --- |
| 1 | 1-Player Start |
| 2 | 2-Player Start |
| 5, 6 | Coin |
| 9 | Service Credit |
| Arrow keys | Movement |
| CTRL | Shot |

## Known Issues
1) The volume scale for the AY-3-8910s requires further tuning for proper accuracy
