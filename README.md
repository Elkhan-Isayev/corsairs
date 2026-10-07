# ⚓ Corsairs: Wind of Freedom

[![Tests](https://github.com/Elkhan-Isayev/corsairs/actions/workflows/tests.yml/badge.svg)](https://github.com/Elkhan-Isayev/corsairs/actions/workflows/tests.yml)
[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An open-source, **built-from-scratch** remake made with **Godot 4.7**, inspired by [Pirates of the Caribbean (2003)](https://en.wikipedia.org/wiki/Pirates_of_the_Caribbean_(video_game)) — known in Russia as *Sea Dogs II* («Корсары 2», Akella). One codebase, every platform: **Windows 10/11, macOS, Linux, and the browser**.

No original game assets are used. The ships, props, photo-scanned textures and skies are free CC0 assets from [Poly Haven](https://polyhaven.com); the houses, people, heraldry, painted art and portraits were generated with [Higgsfield](https://higgsfield.ai) and prepared in Blender by scripts in this repo; the music was composed with [Suno](https://suno.com).

## 🎮 Play now

<a href="https://elkhan-isayev.github.io/corsairs/" target="_blank" rel="noopener noreferrer"><img src="https://img.shields.io/badge/%E2%96%B6%20PLAY%20IN%20BROWSER-elkhan--isayev.github.io%2Fcorsairs-2ea44f?style=for-the-badge" alt="PLAY IN BROWSER"></a>

Direct link: **<a href="https://elkhan-isayev.github.io/corsairs/" target="_blank" rel="noopener noreferrer">https://elkhan-isayev.github.io/corsairs/</a>** — no install needed, the web build is deployed to GitHub Pages automatically on every push.

---

## Screenshots

| Sea battle | Port town (walkable 3D) |
|---|---|
| ![Sea battle](docs/screenshots/battle.png) | ![Port town](docs/screenshots/town.png) |

| Boarding melee | Tavern interior |
|---|---|
| ![Boarding melee](docs/screenshots/boarding.png) | ![Tavern interior](docs/screenshots/interior.png) |

| The open sea (world map) | Port menu |
|---|---|
| ![The open sea](docs/screenshots/map.png) | ![Port menu](docs/screenshots/port.png) |

| Main menu | Sea chart |
|---|---|
| ![Main menu](docs/screenshots/menu.png) | ![Sea chart](docs/screenshots/chart.png) |

## Features

- 🌊 **3D naval combat** — sail physics with a real wind model, independent port/starboard batteries, muzzle smoke from every gun, enemy AI, boarding, sinking — and **enemy squadrons of up to four sail**. Sink them all and the sea is yours: you keep sailing in open waters. Break away far enough and you escape to the world map.
- 💣 **Four ammo types** with distinct damage profiles, just like the original: **cannonballs** (hull), **chain shot** (sails), **grapeshot** (crew), **bombs** (heavy, short-ranged).
- 🗺️ **A sailable open sea** — the world map is a real 3D ocean, Sea Dogs style: steer your miniature ship between 7 islands held by four nations plus a pirate haven. Days pass as you sail (wages, provisions), other sails cruise the horizon — the hostile ones will chase you straight into a 3D battle, and if you take the helm beside a peaceful sail, that ship (or its whole squadron, up to four hulls) appears on the full-scale sea and cruises along beside you. Press `M` for the parchment sea chart, `E` to drop anchor at an island, `Enter` to take the helm and sail the full-scale sea.
- 💰 **Living economy** — 16 trade goods; every colony has its own exports (cheap) and imports (expensive), prices react to stock levels and your Trade skill. Trade routes are profitable — and there's a unit test proving it.
- ⚔️ **RPG system** — 10 skills (Leadership, Fencing, Navigation, Accuracy, Cannons, Boarding, Defense, Repair, Trade, Luck), levels, and skill points.
- 🏴 **Nations & reputation** — England, France, Spain, Holland, and the Pirates; wars, diplomatic fallout for sinking ships, ports that close to hostile captains.
- 📜 **Governor quests** — cargo delivery, pirate hunting, passengers; deadlines and reputation penalties.
- 🛠️ **Port life** — market, shipyard with 11 ship classes (tartane → man-of-war) and trade-in, crew hiring, repairs.
- 💾 **Save system** — JSON saves with autosave after every voyage.
- ⛵ **Detailed period ships** — Poly Haven's 17th-century Dutch ships and pinnace (full PBR hulls, carved sterns, rigging, ratlines), prepared by `tools/blender/import_ships.py`: bow turned forward, sails split so they furl and unfurl, deck profile sampled for crews and boarding, ensign and pennant added. Every nation sails under its own tinted canvas and flies its own ensign (heraldry generated with Higgsfield).
- 🧍 **Real 3D people** — the captain, sailors, townsmen and townswomen are textured character models generated with Higgsfield and rigged in Blender by `tools/blender/build_people.py`; walking, fencing and deck crews all drive their skeletons.
- 🎨 **Painted art** — the main menu and port backdrops, an antique parchment sea chart and portraits of the governor, merchant, shipwright and your captain, generated with Higgsfield.
- 🎵 **Orchestral soundtrack composed with [Suno](https://suno.com)** — an epic main theme for the menu and ports, a driving naval battle score and a sea-shanty voyage tune for the open sea. Towns have no music, only the surf of the harbor (synthesized by `tools/generate_music.gd`).
- 🎥 **Free orbit camera** in battle — drag with the right mouse button, zoom with the wheel.
- 🏘️ **Walkable 3D port towns, each one unique** — every island has its own street plan (market plaza, Dutch canal rows, hillside terraces, a ramshackle pirate cove…), light and weather. Colonial houses and the tavern are 3D models generated with Higgsfield (Hunyuan3D); streets, quays, walls and roofs use photo-scanned PBR textures; barrels, sea chests, harbor cannons and lanterns are Poly Haven models; palms are built in Blender. **Every building is enterable**: furnished tavern, store, shipyard and governor's mansion with NPCs to talk to.
- 🌗 **Day & night cycle** — the sun wheels overhead in towns, at sea and in battle; dawn and dusk burn on the horizon, nights bring moonlight and lantern glow.
- 🏃 **Living decks** — carriage guns and sailors wandering the deck of every ship.
- 🕹️ **Arcade sailing** — the wind flavors your speed (±25% at most) but never stalls the ship; battles stay fast.
- ⚔️ **Third-person boarding** — cross to the enemy deck and fight with your cutlass while both crews clash around you; win to take the prize.
- ⛵ **Harbor mode** — board your ship at the quay, sail the bay past your own town, dock again or head for the open sea.

## Controls (sea battle)

| Key | Action |
|-----|--------|
| `W` / `S` | Raise / furl sails |
| `A` / `D` | Rudder left / right |
| `Q` / `E` | Fire port / starboard broadside |
| `R` | Cycle ammo type |
| `B` | Board the enemy (get close first!) |
| `RMB` drag | Orbit the camera |
| Wheel | Zoom |

On the open sea: `W/S/A/D` to sail, `M` — sea chart, `E` — drop anchor at an island, `Enter` — dock when near an island, otherwise take the helm (full-scale sailing; `Enter`/`Esc` returns to the map). In town: `WASD` to walk, `E` — enter buildings/board your ship, `Tab` — port menu.

## Running the game

You only need [Godot 4.x](https://godotengine.org/download) (free, ~100 MB, no install required).

```bash
# macOS
brew install --cask godot

# then, from the project folder
godot --path .
```

Or open the folder in the Godot editor and hit **F5**.

## Tests

The entire game core is covered by headless tests — **10 suites, ~1,100 assertions**, no window needed:

```bash
godot --headless --path . -s tests/run_tests.gd     # core unit tests
godot --headless --path . -s tests/smoke_scenes.gd  # smoke-walk through every scene
```

The core (`core/`) has zero scene dependencies: every system is a plain class with injectable, seeded RNG, so combat, trading, boarding, and quests are all deterministic under test. CI runs both commands on every push.

## Building for every platform

Godot exports this single project to Windows, macOS, Linux, and the Web. Presets are already configured in `export_presets.cfg`.

1. One-time: download export templates in the Godot editor — *Editor → Manage Export Templates → Download and Install*.
2. Export from the command line:

```bash
godot --headless --path . --export-release "Windows 11 (x86_64)" build/windows/corsairs.exe
godot --headless --path . --export-release "macOS (universal)"   build/macos/corsairs.zip
godot --headless --path . --export-release "Linux (x86_64)"      build/linux/corsairs.x86_64
godot --headless --path . --export-release "Web"                 build/web/index.html
```

The Windows build is a single self-contained 64-bit `.exe` (engine + assets embedded) — runs on Windows 10/11 with no dependencies. The web build can be hosted on any static hosting (itch.io, GitHub Pages).

## Project structure

```
core/      game logic — pure, scene-free, fully unit-tested
  ship.gd, ship_types.gd    ships, 11 hull classes, cargo, damage
  sailing.gd                wind model, speed & turning
  combat.gd, ammo.gd        broadsides, ranges, 4 ammo types
  boarding.gd               boarding fights & loot
  character.gd              skills, XP, leveling, gold
  goods.gd, market.gd       16 goods, colony markets, price dynamics
  world.gd                  archipelago, nations, diplomacy, reputation
  quests.gd                 governor quests
  game_state.gd             aggregate state, voyages, encounters, save/load
tests/     custom headless test framework + unit & smoke tests
scenes/    main_menu, open_sea (sailable world map), port_town, port, sea (3D battle), boarding
scripts/   scene scripts + the Game autoload (scene routing)
assets/    ships, props, houses, people (glTF), PBR textures, HDRI skies, art, water shader, music
tools/     Poly Haven fetcher, Blender import/build scripts, screenshot & ship-gallery capture, surf synthesizer
docs/      screenshots used by this README
```

### Design notes

- **Logic and presentation are strictly separated.** Scenes are thin: they read state, call core methods, and render. Anything that affects gameplay lives in `core/` and lands with a test.
- **Determinism first.** Every random roll goes through an injectable `RandomNumberGenerator`, so any battle or trade session can be reproduced from a seed.
- **Free assets, reproducible pipeline.** `python3 tools/fetch_polyhaven.py` downloads the CC0 textures and models; the `tools/blender/*.py` scripts turn them (and the Higgsfield generations) into game-ready glTF. No engine addons; the test framework is ~80 lines of GDScript.
- **Desktop first.** Native builds use Godot's Forward+ renderer (SSAO, SSIL, HDRI sky lighting, MSAA); the browser build runs the lighter Compatibility renderer.

## Roadmap

- [x] On-deck fencing during boarding — third-person melee with both crews fighting around you
- [x] Walkable port towns with enterable buildings
- [x] Harbor sailing: board your ship and sail the bay before heading to open sea
- [x] Open-sea world map you actually sail, with encounters visible as ships
- [ ] Squadrons & officers (Leadership already gates squadron size)
- [ ] Story campaign
- [x] Music (Suno score) & harbor ambience
- [ ] Sound effects
- [ ] Localization (RU and others — the UI is English)

## Legal

This is a clean-room homage. It contains no code, models, textures, music, or text from the original game and is not affiliated with Akella. If you want to run the **original** Sea Dogs II on Windows 11 — buy the game (GOG/Steam) and check out the officially open-sourced [storm-engine](https://github.com/storm-devs/storm-engine).

## License

[MIT](LICENSE)
