# Workasave

Save your game's services, scripts, and settings, then load them into any place or game.

If you maintain a game with many places, Workasave lets you set up an environment once and bring it everywhere. You choose which services to save, then load that save into another place with **Replace** or **Merge**.

## Features

- Save any combination of services: Workspace (non-physical items), Lighting, MaterialService, ReplicatedFirst, ReplicatedStorage, ServerScriptService, ServerStorage, StarterGui, StarterPack, StarterPlayer, SoundService, Teams, TextChatService, Chat, LocalizationService, Players, and TestService.
- Everything under a service is kept: scripts, folders, values, models and parts (outside Workspace), tags, and attributes.
- The properties, tags, and attributes of the services themselves are saved too, such as Lighting settings.
- **Replace** deletes the current contents of the chosen services and loads the save, so the place matches it exactly.
- **Merge** compares item by item (script source, properties, attributes, tags), updates only what differs, adds what is missing, and keeps everything else.
- Overwrite an existing save. Only the services you tick are replaced inside that save; the rest of it stays as it was.
- An automatic backup is made before every load, and the whole load is one undo step (Ctrl+Z).
- Saves are compressed and split into chunks, so large environments work.
- Saves are stored in your Studio plugin settings, so they are available in every place and game on that computer.

## Install

**From the Creator Store:** search for "Workasave" and install it.

**From source:** build `Workasave.lua` (see below) and put it in your Studio Plugins folder:

```
%LOCALAPPDATA%\Roblox\Plugins
```

Restart Studio. A **Workasave** button appears in the Plugins tab.

## Usage

1. Click **Workasave** in the Plugins tab to open the window.
2. **Save:** pick a name (or choose an existing save to overwrite), tick the services you want, and press Save. Expand a service to see what is inside it.
3. **Load:** pick a save, choose Replace or Merge, tick the services to load, and confirm.

## What is not saved

- Parts and models directly in Workspace, and Terrain. Workspace folders that contain parts are skipped as a whole, and the Save screen marks them.
- References to instances outside the saved set. Links inside a save survive; a link to something you didn't save will be empty after loading.
- Saves are stored per computer, not synced between computers or accounts.

## How it works

- Instances are serialized with `SerializationService`, compressed with `EncodingService` (Zstandard), converted to base64, and stored in 512 KB chunks with `plugin:SetSetting`.
- Service properties are read generically through `ReflectionService`, so properties Roblox adds later are picked up without code changes.
- Loads read and decode everything before touching the place, so a broken save fails safely.
- Saves are never stored by writing files, and the plugin makes no web requests. `HttpService` is only used for JSON encoding and decoding.

## Project layout

| File | Purpose |
| --- | --- |
| `Core.lua` | Save, load, merge, and storage logic |
| `UI.lua` | The floating window |
| `Main.lua` | Toolbar button and window setup |
| `icon.png` | Toolbar icon source |

The plugin is a single script made by joining the three source files in this order: `Core.lua`, `UI.lua`, `Main.lua`.

## Build

PowerShell:

```powershell
$parts = "Core.lua", "UI.lua", "Main.lua" | ForEach-Object { [IO.File]::ReadAllText($_) }
[IO.File]::WriteAllText("Workasave.lua", ($parts -join "`n"), (New-Object Text.UTF8Encoding($false)))
```

Write the file as UTF-8 without a byte-order mark. Luau rejects a BOM at the start of a script.

To publish, paste the contents of `Workasave.lua` into a Script in Studio, right-click it, and choose **Save/Publish as Plugin...**.

## Contributing

Issues and pull requests are welcome. Please test a save and a load (Replace and Merge) in a scratch place before submitting changes.

## License

Released under the [MIT License](LICENSE).
