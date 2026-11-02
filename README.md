# Cross-platform Mega Man Legends 2 port

> **Work in progress.** The game is not complete: expect missing areas, unfinished features and bugs.

The goal is to port Mega Man Legends 2 to Godot/Redot for Linux, Windows, macOS and WebAssembly, with mobile support as a possible additional target. The client should extract its required assets from the user's disc files rather than distribute exported game data.

The current implementation loads thirteen ST0F areas and fifteen Flutter rooms from ST04–ST07. Flutter uses the original bareheaded player with normal hands and disables firing. Gameplay includes the original gauges, dungeon minimap, geometry collision and dungeon room transitions. The title menu uses the original logo, background, selection art and audio; the pause controls use the extracted menu frames and font. The full game and automatic client-side disc import are still in development.

## Status

Work in progress. The table is generated from `docs/regression_sweep.md` (headless sweep that starts every area and walks around) and from the stages that run the game's own recompiled code (`RUNNER_VALIDATED` in `tools/models.py`). It shows what loads and which logic is original; it is not a full playthrough, so a "Yes" does not mean a mission is finished. Story flow is not verified end to end.

- **All stages / Some stages**: scripts, actors and scenes come from the original code running in the runner. **Port scripts only**: rebuilt scripts and scenes in the port.
- **Loads without errors**: every area starts and is standable in the headless sweep. "Mostly" lists the areas that do not.

| Location | Stages | Areas | Original game code | Loads without errors | Known issues |
| --- | --- | ---: | --- | --- | --- |
| Debug area | ST00 | 2 | Port scripts only | Yes | - |
| Sulphur-Bottom opening | ST02 | 2 | Port scripts only | Yes | - |
| Flutter opening | ST03 | 4 | Port scripts only | Yes | - |
| Flutter | ST04, ST05, ST06, ST07 | 15 | Port scripts only | Yes | Runner support exists (ST04–ST07 are in the runner stage list) but is switched off until it is tested in play; purchases and repairs are not verified |
| Yosyonke City | ST08, ST09, ST0A, ST0B, ST0C, ST47 | 16 | Some stages | Yes | ST08 and ST0B stay on port scripts (landing, scene 0x27 do not run on the original code) |
| Calinca Tundra | ST0D, ST0E | 5 | All stages | Yes | - |
| Abandoned Mine | ST0F | 13 | All stages | Yes | - |
| Forbidden Island | ST10, ST11, ST1D | 6 | Some stages | Yes | - |
| Manda Ruins | ST12, ST13, ST14 | 23 | All stages | Yes | - |
| Nino Island | ST15, ST16, ST18, ST19 | 12 | All stages | Yes | - |
| King Glydon | ST17 | 3 | All stages | Yes | - |
| Ruminoa City | ST1A, ST1B | 7 | All stages | Yes | - |
| Forbidden Island / Sulphur-Bottom scenes | ST1C | 6 | All stages | Yes | - |
| Flutter fire | ST1E | 3 | Port scripts only | Yes | - |
| Glyde's Base | ST1F, ST30, ST31 | 9 | All stages | Yes | - |
| Kito Village | ST20 | 2 | All stages | Yes | - |
| Calbania Plains | ST21, ST22, ST23 | 3 | All stages | Yes | - |
| Pokte Plains | ST24 | 3 | All stages | Yes | - |
| Pokte Village | ST25 | 7 | All stages | Yes | - |
| Saul Kada Ruins | ST26, ST27, ST28, ST33, ST34 | 29 | All stages | Yes | - |
| Kimotoma City | ST29, ST2A, ST2B, ST2C, ST3B, ST3C | 19 | All stages | Yes | ST3C: after scene 0x5D (area 2, story 12) the flag that advances the story is never set (boss not found) |
| Calinca Ruins | ST2D, ST2E, ST2F | 31 | All stages | Yes | - |
| Pokte Mayor's Home | ST32 | 1 | All stages | Yes | - |
| Nino Ruins | ST35, ST36, ST37, ST38 | 49 | All stages | Yes | - |
| Flutter new-game scene | ST39 | 2 | All stages | Yes | - |
| Sulphur-Bottom / Forbidden Island scenes | ST3A | 4 | Port scripts only | Yes | - |
| Sulphur-Bottom | ST3D, ST3E, ST3F, ST4B | 19 | Some stages | Yes | - |
| Elysium | ST40 | 14 | All stages | Yes | - |
| Defense Area | ST41, ST42 | 31 | All stages | Yes | - |
| Mother Zone | ST43, ST44, ST45, ST4C, ST58, ST5C | 27 | All stages | Yes | - |
| Nino Island / Flutter scenes | ST46 | 3 | All stages | Yes | - |
| Saul Kada Desert | ST48 | 2 | All stages | Yes | - |
| Flutter / Dropship scenes | ST49 | 4 | Port scripts only | Yes | - |
| Tutorial | ST4A | 7 | All stages | Yes | - |
| Guild Ruins | ST4D | 9 | All stages | Yes | - |
| Pokte Caverns | ST4E, ST51 | 13 | All stages | Yes | - |
| Kito Caverns | ST4F | 15 | All stages | Mostly | ST4F: area 14 is an unreachable stub; no clear spawn |
| Kimotoma Caverns | ST50 | 11 | All stages | Yes | - |
| Sera / Master scenes | ST52 | 5 | All stages | Yes | - |
| Calinca Tundra scenes | ST53 | 3 | All stages | Yes | - |
| Rocket launch ending | ST54 | 3 | All stages | Yes | Ending music (XA) not verified in a full run |
| License Test Ruins | ST55 | 7 | All stages | Yes | - |
| Master's Room | ST56 | 1 | All stages | Yes | - |
| Game credits | ST57 | 1 | All stages | Yes | Credits music is not played; the page clock is inferred (see docs/progression.md) |
| Manda Circuit | ST59 | 1 | All stages | Yes | - |
| Calinca Circuit | ST5A | 1 | All stages | Yes | - |
| Saul Kada Circuit | ST5B | 1 | All stages | Yes | - |

### Open bugs

- Manda Ruins: frog enemies reported passing through walls; not reproduced yet.
- Pokte Caverns (ST4E): barrier in area 4 and the route from area 4 to 9 are unverified.
- Flutter fire mission (ST1E): doors between rooms need verification.
- Tutorial: walking through the first-room door is unconfirmed after the door fix.
- Native town NPC collision boxes are about 3 cm off.
- Some achievements are not wired to their triggers.
- Roll's behaviour at the Flutter landing has not been compared with the original.
- Web build: single-thread only for now (no worker thread), so heavy scenes run slower than on desktop.

## Running and building

Open this folder with Redot 26.2 and run `scenes/main.tscn`. WASD navigates menus and runs relative to the camera during gameplay; hold Shift to walk, mouse movement or Q/E orbits it, Space jumps, left mouse fires, right mouse holds shoulder aim, Tab (or the right trigger) holds lock-on, R interacts or grabs/throws, F kicks, O respawns, Ctrl releases the mouse, and Esc opens the pause controls. During any cutscene (story scenes, the opening, original-code scenes, the Flutter map's launch and landing) hold Left Shift to fast-forward (x4), hold Left Ctrl to rewind and press P to pause; the Input Map actions are `cutscene_fast`, `cutscene_rewind` and `cutscene_pause`, and a small indicator shows the mode in the top right corner. Mouse4 remains an alternate for grabbing/throwing; grabbing, throwing, and kicking are disabled in safe rooms. Aiming reduces movement speed and limits how quickly Mega Man turns; camera and shots collide with level geometry.

Requirements: Python 3.13+, FFmpeg on `PATH`, FluidSynth (downloaded automatically on Windows; install `libfluidsynth` on Linux/macOS) and your own PAL SLES-03556 disc image as BIN/CUE. `unicorn` and `capstone` are installed automatically into `build/pydeps`. Then run `python tools/assets.py "<path-to-disc.cue>"` from this folder. This extracts every ISO file and exports every stage archive, model archive, player variant, texture upload, sound bank, sequence, XA archive and STR movie, plus the runtime's menus, HUD, player, routes and cutscene data into `assets/` (about 4 GB). Generated game assets, disc data and local dependencies are ignored by Git.

Existing output files are never replaced unless you ask: `--overwrite` replaces everything and `--overwrite-only PATTERN` (repeatable glob relative to this folder, such as `assets/dialogue/*` or `assets/levels/ST10/**`) replaces only matching files. `--only world|models|textures|ui|audio|cinematics|media` and `--stage STxx` (both repeatable) process a subset, and `python tools/assets.py --help` lists the groups. `build/asset_coverage.json` records source hashes, exported assets and unresolved decoders; errors return a nonzero exit status. Requirements, every flag, output locations, importing into Redot, web export and troubleshooting are in [docs/tools.md](docs/tools.md). Extracted content does not imply that every stage's gameplay scripts and actor bindings are implemented.

The extraction code is `tools/assets.py` (the single command line) plus six modules: `disc.py` handles disc transport, section decoding and the output policy; `world.py` handles maps, terrain, lighting, room metadata, shops, location names and stage logic; `models.py` handles models, skeletons, animation banks, special weapons and effects; `ui.py` handles menu/HUD artwork, fonts and fades; `audio.py` handles sound banks, sequences and XA; `cinematics.py` handles native cutscene data and the scene and mission exporters. Web packaging (`export_web.py`) and the asset server remain separate tools.

The player contains the original mesh, palettes, skeleton and recovered control clips at the traced player-to-level scale. Buster firing uses native controls 112/113 on bones 5–7 and emits from bone 7; the mesh opens in the native idle pose. Jumping uses native takeoff, rise, fall and landing controls and the original held-jump and release-braking values. Maps retain their original corner brightness and recovered mine depth cueing. Room routes and actor activation boxes come from the disc, while gameplay collision currently comes from rendered meshes. The recovered dungeon actors support movement, hit flashes, damage, death and collectible zenny or vitality drops; enemy effects and combat behavior remain incomplete. Inventory and tutorial lesson scripts are not implemented; the Tutorial menu opens the original ST4A:0 area. New Game starts the traced ST39 Flutter introduction, enters the ST1E fire mission, and runs the ST3A flight and ST08 landing scenes before returning to the Flutter entrance; the ship exit connects to Yosyonke through the native town doors. Save Game offers new slots and overwriting existing slots; Continue lists saves with their room, date and health. Loading restores position, health capacity, zenny, defeated actors and explored minimap cells, including previously visited stages. F1 opens additional settings, session cheats and a room selector using native area IDs.

Settings, achievement unlocks, saves and the asset cache are stored in the user data folder `MorenoLand/Legends`. Achievement set and badges by Searo (RetroAchievements), used with permission.

Runtime code uses GDScript and the Compatibility renderer. The Web export preset includes asset manifests and disables threads; browser mouse capture begins on a canvas click. Native gameplay has been exercised; a browser export has not been verified.
