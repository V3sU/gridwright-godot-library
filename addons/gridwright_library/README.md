# Gridwright Library for Godot

Browse every Gridwright pixel art pack inside the Godot editor and install it into your project with one click. Samples install with a free Gridwright account; a full pack installs once you've bought it on gridwright.store.

- **A "Gridwright" dock** with every pack: cover, grid size, engines and file size. Search, or filter by category, by what's installed or by what you've bought.
- **Install** puts a pack you've bought into `res://gridwright/<pack>/`. **Install sample** puts in any pack's free sample.
- **Buy** opens the pack's page on gridwright.store. Each pack is bought once; back in the editor, the dock sees it and the card turns into **Install**.
- **Packs with a Godot demo work in place.** The demo's scenes, tilesets and SpriteFrames are pointed at their new folder, so you can open the demo scene straight from the dock.
- **Make project pixel-perfect** sets Nearest filtering and pixel snapping, shows each change before it applies, and can be undone.
- Plain GDScript, MIT licence, no dependencies. Written for Godot 4.2 or newer, tested on 4.7.2.

**Want every pack?** The [$20 Gridwright bundle on itch.io](https://itch.io/s/207198) has them all. **Need art made for your game?** We make [custom packs](https://gridwright.store/custom?ref=godot) to your brief.

## Install the addon

1. Copy the `addons/gridwright_library` folder into your project's `addons/` folder (or install it from the Asset Library).
2. Open **Project > Project Settings > Plugins** and enable **Gridwright Library**.
3. The **Gridwright** dock appears on the right, next to the Inspector.

## Get your key

1. Make a free account or sign in at [gridwright.store/account](https://gridwright.store/account?ref=godot), and copy your plugin key. It starts with `gwp_`.
2. Paste it into the dock and press **Check**. The dock shows your email and how many packs you've bought.

The key is kept in the editor's own settings (Editor Settings, `gridwright_library/key`), never in your project, so it can't end up in a commit. It is only sent to gridwright.store over HTTPS. Download links are signed by the server and get no key.

## What installs

- **Samples:** every pack's free sample installs with any Gridwright account.
- **Full packs:** each pack is bought once on its page at gridwright.store (the **Buy** button opens it). After that it installs from the dock whenever you need it, in any of your projects (there is a daily download limit).
- The $20 bundle on itch.io is bought and downloaded on itch.io, so its packs don't unlock here.

## Use it

- **Install** downloads the pack, unpacks it into `res://gridwright/<pack>/` and lets Godot import it. The message at the top names the pack's README and has buttons for **Show in FileSystem**, **Open README** and, for packs with a Godot demo, **Open demo scene**.
- **Install again** replaces the files that came with the pack and leaves anything else in that folder alone. Nothing outside `res://gridwright/` is ever written.
- Folders inside the zip are kept as they are. The zip's own `.import` and `.uid` files are skipped, so Godot imports everything fresh.
- A pack's demo project keeps its settings as `project.godot.txt` (a second `project.godot` would make Godot hide that folder). Your own project settings don't change.
- **Make project pixel-perfect** changes:
  - Default texture filter: Nearest (sprites stay sharp when scaled)
  - Snap 2D transforms to pixel and Snap 2D vertices to pixel (nothing shimmers between pixels)
  - Only if you tick it: stretch mode `viewport` with integer scaling (the game draws at its base size and scales by whole numbers)

  **Undo** puts the old values back. A setting you changed by hand since then is left as it is. The old values are kept in `.godot/editor/`, not in `project.godot`.

## Messages you may see

| Message | What to do |
|---|---|
| Paste your Gridwright key first | Copy it from your account page. |
| This key doesn't work | Copy it again from your account page. |
| Not bought yet | Press **Open the pack page** and buy it there. Its sample installs now. |
| You've reached today's download limit | Try again tomorrow. |
| Can't reach gridwright.store | Check your internet connection. |

## Privacy

The addon talks only to gridwright.store: the pack list, your account (from your key: your email and what you've bought) and download links. Cover pictures and the last pack list are cached in `user://gridwright_library/` so the dock opens fast. There is no tracking.

## Licences

- **The addon's code** is MIT licensed (see `LICENSE`).
- **The packs** follow the Gridwright licence that ships in each pack (`LICENSE.txt`): use them in personal and commercial games, but don't resell or share the asset files themselves.

## More from Gridwright

- Every Gridwright pack in one go: the $20 bundle on itch.io, https://itch.io/s/207198
- Art made for your game: custom packs, https://gridwright.store/custom?ref=godot
- Single packs: https://gridwright.store/library?ref=godot
- Help and news: Discord, https://discord.gg/CmXcSgBQ6V
