# Tamer

## The vision

Tamer helps a Hunter on World of Warcraft: Forever know what their pet should learn next, how to unlock it, and which beast teaches it. You open one small window and see your next step, without digging through a database of beasts, abilities, ranks and locations.

If you're working on this project, whether you're a person or an AI, these are the goals that decide what to do:

- **Show what matters right now, not everything that exists.** The next useful upgrade beats a full list of beasts.
- **Answer three questions on every screen.** What does my pet already know? What can I teach it right now? What should I go learn next?
- **Explain the difference.** Never leave the player to work out "known by the Hunter", "trained on the pet" and "available from a wild beast" on their own.
- **Keep up by itself.** Find missing ranks from the pet's family and update as the pet levels, without the player tracking anything.
- **One main screen.** A new feature has to earn its place, and it shouldn't make the dashboard harder to read.

The full plan is in [docs/plan.md](docs/plan.md).

## What it is

So far the addon loads, keeps its saved data in `TamerDB`, and answers `/tamer`. The pet dashboard isn't built yet.

## Setup

1. Close the game and extract the zip into your AddOns folder, so its files end up in `AddOns/Tamer/`:

   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`
   - **macOS:** `/Applications/World of Warcraft/_forever_/Interface/AddOns/`

   Create the `AddOns` folder if it isn't there. Your game may be installed somewhere else.

2. Start the game. If addons load individually, turn on Tamer at the character screen.

## Commands

| Command | What it does |
| --- | --- |
| `/tamer` | Show your pet's next step |
| `/tamer help` | List the commands |

## Working on the addon

These commands need [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell), which also runs on macOS. To link the project into the game so edits load directly, run:

```powershell
./install-addon.ps1
```

Pass `-WowPath` if the game isn't in the default location. Restart the game after linking.

The addon is in `addon/Tamer/`. Edits load with `/reload`. A brand-new file needs a game restart and an entry in `Tamer.toc`.

To test the addon outside the game, run the harness with [LuaJIT](https://luajit.org/). See [tools/harness/README.md](tools/harness/README.md).

```sh
luajit tools/harness/harness.lua
```

### Releasing

Pushing a version tag publishes to CurseForge and GitHub. See [docs/RELEASING.md](docs/RELEASING.md).

### Building the zip

This builds `dist/Tamer-<version>.zip` with the addon:

```powershell
./tools/build-release.ps1
```

To update, replace the whole `Tamer` folder with the new one. Saved data isn't stored there, so it stays.
