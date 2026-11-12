---
name: kitty-show
description: Show an image, screenshot, chart or rendered diagram to the user in a kitty side window, or run a deploy/CI watch or other live output in the user's TEMP window (ktemp). Use when the user asks to "show", "display" or "open" an image in the terminal, or when you produced a visual (plot, generated asset, screenshot) the user should look at now. Only works when Claude runs inside kitty (KITTY_WINDOW_ID is set).
---

# kitty-show

Images you Read, image paths you mention in a reply (if the file exists),
and https image URLs in a reply (ending in .png/.jpg/…, no query string) are
shown to the user automatically by a hook, in a floating panel. Write the
full path or URL of any image you produce or refer to; call `kshow` yourself only to show
something again or several images side by side mid-turn.

Your Bash tool's output is captured, not a terminal, so `kitten icat` run
directly never draws anything. Use `kshow`: each call opens a new split in the
user's right-hand column that shows the images until the user presses a key,
so several can be open side by side with earlier ones.

The column's TEMP window is the user's bash shell, and also yours for anything
the user should watch live. Use `ktemp`:

```bash
ktemp 'npm run dev'                          # type it into the TEMP shell
ktemp --split --title "▶ deploy web" gh run watch 1234
                                             # own split, kept until a key
                                             # (use for each GH deploy/pipeline log)
```

Long commands need nothing either: any Bash command you run in the
foreground that takes more than a few seconds is mirrored live in its own
split automatically. Use `ktemp` only for things you are NOT waiting on.

GitHub runs need nothing: a hook opens a `gh run watch` split by itself when
you run `gh workflow run` or `gh run watch <id>`.

Prefer `--split` for watches/logs so the TEMP shell stays free; several splits
can run at once. A plain `ktemp` falls back to a split when TEMP is busy.
Use your own Bash tool for output you need to read yourself; `ktemp` output
does not come back to you.

The column is shared by every Claude session in the kitty tab, so TEMP may
be in use by another session; a busy TEMP falls back to a split. Don't run
`kshow --close` while another session's splits may still be wanted.

```bash
kshow /abs/path/plot.png               # one image
kshow a.png b.jpg                      # several, stacked
kshow --close                          # close all image/job splits in the tab
KSHOW_SIZE=60% kshow big.png           # wider viewer (default 45%)
```

If `kshow` is not on PATH, use `~/.config/myconfig/bin/kshow`.

Rules:
- Check `[ -n "$KITTY_WINDOW_ID" ]` first; outside kitty, tell the user the path instead.
- Formats: PNG, JPEG, GIF (animated), WebP, BMP, TIFF. Convert SVG/PDF to PNG first
  (e.g. `sips -s format png in.pdf --out out.png`, or `rsvg-convert`).
- Each `kshow` call adds a split; it never takes focus. The user closes each
  with any key. Without the right column, one viewer window is reused instead.
- To look at the image yourself, use the Read tool on the file — `kshow` is for the user.
