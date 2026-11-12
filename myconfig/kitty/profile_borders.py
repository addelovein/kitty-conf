# Kitty watcher: border colors are global in kitty (set-colors --match-tab
# still patches every OS window), so re-apply them on focus change based on the
# focused window's `profile` user var (set by kitty_profile / kitty_recolor).
from typing import Any

from kitty.boss import Boss
from kitty.fast_data_types import get_options
from kitty.window import Window

# Keep in sync with _kitty_profile_palette in shell/zsh/kitty.zsh.
PROFILE_BORDERS = {
    'green': ('#56c98a', '#224734'),
    'blue': ('#62d6ff', '#1f2a36'),
    'red': ('#ff6b86', '#3a1f24'),
}


def _hex(c: Any) -> str:
    if c is None:
        return 'none'
    return f'#{c.red:02x}{c.green:02x}{c.blue:02x}'


def on_focus_change(boss: Boss, window: Window, data: dict[str, Any]) -> None:
    if not data.get('focused'):
        return
    profile = window.user_vars.get('profile', '')
    colors = PROFILE_BORDERS.get(profile)
    if colors is None:
        # No profile: fall back to the configured (kitty.conf) border colors.
        opts = get_options()
        colors = (_hex(opts.active_border_color), _hex(opts.inactive_border_color))
    boss.call_remote_control(window, (
        'set-colors',
        f'active_border_color={colors[0]}',
        f'inactive_border_color={colors[1]}',
    ))
