# Test harness

`harness.lua` runs the addon outside the game. It loads the files in `Tamer.toc` order, stands in for the game's functions and events, and drives the addon's flows. It finishes with a count of passed and failed checks.

It proves the addon's logic, not that the game has the functions it stands in for, so still try changes in the game.

## Running it

It needs [LuaJIT](https://luajit.org/) or any Lua 5.1, the same version the game uses. On a Mac, `brew install luajit`. From the repository:

```sh
luajit tools/harness/harness.lua
```

Every check should pass, ending in a line like `RESULT: 10 passed, 0 failed`. A failure prints `FAIL` with the check's name. The last line lists anything the addon read from the game that the harness doesn't provide, which is fine for functions the addon checks for before using, and for `TamerDB` before the first load.

To test another copy of the addon, pass its folder:

```sh
luajit tools/harness/harness.lua addon/Tamer
```
