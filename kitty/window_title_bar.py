# Custom window title bar for kitty (loaded via window_title_template "{custom}").
#
# Renders the full bar line: the title centered (same look as the old
# templates) plus a dim "super + drag to move" hint in the right corner of the
# ACTIVE window's bar. The hint disappears when the bar is too narrow.
#
# kitty passes no bar width to templates, so we look it up from the window's
# title-bar screen. Any failure falls back to the plain title (see kitty.conf).

from kitty.boss import get_boss
from kitty.fast_data_types import get_options, wcswidth
from kitty.window_title_bar import WindowTitleFormatter as fmt

HINT = 'super + drag to move'
HINT_COLOR = '_555555'      # gray, low contrast on the #1f1f1f active bar
ACCENT = '_3794ff'          # the blue "●" for the active window
RIGHT_MARGIN = 1            # cells between the hint and the bar's right edge
MIN_GAP = 3                 # min cells between title and hint, else hide hint


def _bar_columns(window_id: int) -> int:
    w = get_boss().window_id_map.get(window_id)
    pts = getattr(w, '_title_bar_screen', None) if w else None
    return pts.screen.columns if pts is not None else 0


def _progress(window_id: int) -> str:
    w = get_boss().window_id_map.get(window_id)
    p = getattr(w, 'progress', None)
    if p is None:
        return ''
    state = getattr(p.state, 'name', '')
    if state == 'indeterminate':
        return '[…] '
    if state not in ('', 'unset') and p.percent > 0:
        return f'[{p.percent}%] '
    return ''


def draw_window_title(data) -> str:
    opts = get_options()
    bell = opts.bell_on_tab if data.needs_attention else ''
    activity = opts.tab_activity_symbol if data.has_activity_since_last_focus else ''
    progress = _progress(data.window_id)
    title = data.title

    # Plain text (for width math) and styled text, kept in sync.
    if data.is_active:
        plain = f'{bell}● {progress}{title}'
        styled = (f'{fmt.fg.red}{bell}{getattr(fmt.fg, ACCENT)}● '
                  f'{fmt.fg.window}{progress}{fmt.bold}{title}{fmt.nobold}')
    else:
        plain = f'{bell}{activity}{progress}{title}'
        styled = f'{fmt.fg.red}{bell}{activity}{fmt.fg.window}{progress}{title}'

    cols = _bar_columns(data.window_id)
    if cols <= 0:
        return styled

    content_w = wcswidth(plain)
    left_pad = max(0, (cols - content_w) // 2)
    line = ' ' * left_pad + styled

    if data.is_active:
        hint_w = wcswidth(HINT)
        gap = cols - left_pad - content_w - hint_w - RIGHT_MARGIN
        if gap >= MIN_GAP:
            line += f'{fmt.fg.window}' + ' ' * gap + f'{getattr(fmt.fg, HINT_COLOR)}{HINT}'
    return line
