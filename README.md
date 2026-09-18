# Stage Drawer

A Stage Manager-style window switcher for the [Omarchy](https://omarchy.org/) shell.

Push the pointer against the left edge of the screen and a drawer slides in with
a preview of every other open window — across all workspaces, including windows
hidden by `show-desktop`. Click one to switch to it and make it full width (or
fullscreen, if that's how you were already working). A **Back to tiles** button
restores the normal tiled layout.

It works over full-width and fullscreen windows, so you can get back out of a
maximized app without reaching for a keybinding.

## Install

```bash
omarchy plugin add https://github.com/sumanthmukkala/omarchy-stage-drawer --enable
```

To update later:

```bash
omarchy plugin update com.sumanthmukkala.stage-drawer
```

To remove:

```bash
omarchy plugin remove com.sumanthmukkala.stage-drawer
```

## Requirements

- Omarchy with `omarchy-shell` (Quickshell)
- Hyprland
- `jq` and `hyprctl` (both standard on Omarchy)

## Built to stay cheap

It was written for an older Intel MacBook Air, so it avoids the things that make
this kind of overlay expensive:

- The trigger is an **event-driven hover strip**, not a timer polling the cursor.
- Window previews are a **single captured frame** taken when the drawer opens
  (`live: false`), not live-updating thumbnails.
- Previews are **destroyed when the drawer closes**, so nothing is retained while
  the drawer is idle.

It also leaves an 80px gap at the bottom of the edge strip so it doesn't fight a
bottom-left hot corner, if you use one.

## Theming

The drawer draws from `qs.Commons` (`Color.menu`, `Style.cornerRadius`,
`Style.font`, …), so it follows whatever Omarchy theme is active. There is
nothing to configure.

## Tuning

The constants at the top of `Drawer.qml` are the knobs worth touching:

| Property | Default | What it does |
| --- | --- | --- |
| `drawerWidth` | `240` | Width of the drawer panel |
| `edgeWidth` | `2` | How many pixels of screen edge arm the trigger |
| `edgeBottomGap` | `80` | Dead zone at the bottom, to spare a hot corner |
| `openDelayMs` | `120` | Hover time before it slides in |
| `closeDelayMs` | `300` | Grace period before it slides out |

Edits apply on save — the plugin is not `keepLoaded`, so no shell restart needed.

## How it works

Two pieces:

- **`Drawer.qml`** — the UI. The edge strip, the slide animation, the previews.
- **`stage-switch`** — a small bash helper the QML shells out to. Hyprland window
  manipulation goes through `hyprctl`, so focus changes, fullscreen state, and
  pulling windows back off special workspaces happen here.

## License

MIT — see [LICENSE](LICENSE).
