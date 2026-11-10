# AGENTS.md — IceDOS **gaming**

> Utilizes the **IceDOS** framework. The full bible — module structure, config flow,
> the `icedos rebuild --build` test loop, `validate.*` helpers, dep loading — lives in
> **core**: <https://github.com/IceDOS/core/blob/main/AGENTS.md> — this file only
> covers what is specific to **gaming**.

## Non-negotiable rules (full detail in core)
- Build/test only via the `icedos` CLI — **never `sudo nixos-rebuild`**.
- **Never** `git commit/stash/reset/pull` — the user manages git.
- Every option uses a `validate.*`/`mk*Option` helper; **no untyped options**.
- Option-path segments that hold other options are **kebab-case** (`agent-bridge`); only leaf value keys are camelCase (`remoteLookup`).
- A module's `config.toml` defaults must mirror its `icedos.nix` defaults.
- Format with `icedos nixf .` after editing any `.nix`.

## Purpose
Gaming tooling: Proton launchers, performance layers, overlays, game mods, emulators and
gaming system tweaks. Steam itself and Sunshine stay in `apps`.

## Namespace
Every option here lives under `icedos.gaming.<module>` (`icedos.gaming.proton-launch`, ...).

## Layout
`modules/<category>/<name>/{icedos.nix,config.toml}`; `flake.nix` exposes them via
`icedosLib.scanModules { path = ./modules; filename = "icedos.nix"; }`, which recurses, and
`meta.name` (not the folder) names the module. The categories are:
- `launchers`: `aagl` (anime game launchers).
- `performance`: `gamemode`, `lsfg-vk`, `low-latency-vulkan-layer`, and
  `tweaks` (gaming sysctls, memlock limits and controller udev rules).
- `overlays`: `mangohud`, `steam-wayland-overlay`.
- `emulators`: `playstation/kytyps5` and `nintendo/nx2/` (`eglantine`, `lichii`, which share `mk-package.nix` and `update-common.sh`).
  `lichii` can also build from source (`build = "source"`) at a pinned rev with `source.patches` applied (`source-package.nix`).
- `servers`: `fromsoftware/bb/` (`bbsc-gameserver`, `shadnet-p2p`).
- `tools`: `gamescope`, `prefixer`, `proton-launch`, `steam-cloud-file-manager`, `unshade` (prunes shader caches during `icedos gc`),
  `fromsoftware/` (`bb/bbport`, `duskbloods/playdb-cnt` (The Duskbloods Network Test launcher), `me3`,
  `nightreign/reigntweak`, `sekiro/sekirofpsunlock`) and `nintendo/` (`nx/botw/savagewind`, `nx/totk/totk-recomp`, `nx2/hookshot`).
  `nintendo/nx2/hookshot` is the Ocarina of Time static recompilation. It has its own FHS wrapper around the upstream AppImage, not `mk-package.nix`, and its environment keeps the builder's self-updater off.
  `nintendo/nx/totk/totk-recomp` is the Tears of the Kingdom static recompilation. It has its own FHS wrapper around the upstream AppImage, adds `libdecor` for the built game, and adds `--play` because upstream has no launcher. The game and its files stay outside the store, in the folder picked during setup.
  `nintendo/nx/botw/savagewind` is the Breath of the Wild static recompilation. It has its own FHS wrapper around the upstream AppImage, and upstream publishes only prereleases, so its updater reads the release list.
  `gamescope/sunshine-headless` is `sunshine-headless-gamescope`, the gamescope backend for `apps#sunshine-headless`.
  Its options live in `icedos.gaming.gamescope.sunshine-headless`, and it registers itself in
  `icedos.applications.sunshine-headless.compositors.gamescope`.

## Cross-repo checks
`steamdeck` and `monitors` stay in `hardware`, so `hasModule` calls for them pass
`url = "github:icedos/hardware"`. `apps#steam` checks for `proton-launch`, `me3` and
`reigntweak` with `url = "github:icedos/gaming"`. `sunshine-headless-gamescope` depends on
`apps#sunshine-headless`, and `apps#steam-headless` depends on it with `url = "github:icedos/gaming"`.

## Test a change to this repo
Point this repo's `overrideUrl` at the local checkout in the config root
(`path:/abs/path/to/gaming`), then `icedos rebuild --build`.

## Pinned packages
Modules that package something not in nixpkgs keep the pin in `source.json` next to
`package.nix`, with an `update.sh` and an `update-<module>.yml` workflow over
`module-update.yml`. Their `build.toml` is the minimal config cache-server builds for a PR.

## Notable modules / gotchas
- `me3`: game mod loader (per-game profiles/natives/packages).
- `prefixer`, `proton-launch`: Proton prefix tooling (protontricks is deprecated here;
  use `prefixer <APP_ID> run <exe>`).
- `tweaks`: no options. It only sets kernel params, sysctls and limits, so be conservative
  and validate with `--build`.
