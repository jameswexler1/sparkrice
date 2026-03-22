#!/usr/bin/env python3
"""
tui_treni_curses.py
A curses-based TUI for fetching Italian trains using ViaggiaTreno APIs.
Enhanced with pywal colors, unicode box-drawing, emojis, and train type coloring.
Requirements: pip install requests pytz
Usage: python3 tui_treni_curses.py
"""
import curses
import requests
import json
import os
from datetime import datetime, timedelta
import pytz
import time
import calendar

BASE_URL = "http://www.viaggiatreno.it/infomobilita/resteasy/viaggiatreno"
TZ = pytz.timezone("Europe/Rome")

# ── Session cache (origin + route are immutable; delays are never cached) ──
_cache_origin = {}   # train_number -> (origin_id, timestamp_ms)
_cache_route  = {}   # (origin_id, train_number, timestamp_ms) -> stops list

# ── Train type metadata ───────────────────────────────────────────────────────
TRAIN_META = {
    "FR":  {"emoji": "🔴", "label": "Frecciarossa",  "color_idx": 6},
    "FA":  {"emoji": "🟠", "label": "Frecciargento", "color_idx": 6},
    "FB":  {"emoji": "🟡", "label": "Frecciabianca",  "color_idx": 6},
    "IC":  {"emoji": "🔵", "label": "Intercity",      "color_idx": 5},
    "ICN": {"emoji": "🌙", "label": "InterCity Notte","color_idx": 5},
    "EC":  {"emoji": "🌍", "label": "EuroCity",       "color_idx": 5},
    "REG": {"emoji": "🚂", "label": "Regionale",      "color_idx": 4},
    "RV":  {"emoji": "🚃", "label": "Reg. Veloce",    "color_idx": 4},
}
DEFAULT_META = {"emoji": "🚆", "label": "Treno", "color_idx": 4}

# ── Delay severity ────────────────────────────────────────────────────────────
def delay_emoji(minutes):
    if minutes <= 0:   return "✅"
    if minutes <= 5:   return "🟡"
    if minutes <= 15:  return "🟠"
    return "🔴"

def delay_str(minutes):
    if minutes <= 0: return "In orario"
    return f"+{minutes} min"

# ── Pywal color loader ────────────────────────────────────────────────────────
def load_wal_colors():
    """Load pywal colors from ~/.cache/wal/colors. Returns list of 16 hex strings or None."""
    path = os.path.expanduser("~/.cache/wal/colors")
    try:
        with open(path) as f:
            colors = [line.strip() for line in f if line.strip().startswith("#")]
        if len(colors) >= 16:
            return colors[:16]
    except Exception:
        pass
    return None

def hex_to_curses_rgb(hex_color):
    """Convert #rrggbb to curses 0-1000 range RGB tuple."""
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return int(r / 255 * 1000), int(g / 255 * 1000), int(b / 255 * 1000)

def init_wal_colors(wal_colors):
    """
    Initialize curses color pairs from pywal palette.
    Color pair assignments:
      1  = default text         (color7 on default bg)
      2  = header/title         (color6 on default bg, bold)
      3  = delay: on time       (color2 on default bg)
      4  = REG trains           (color4 on default bg)
      5  = IC trains            (color6 on default bg)
      6  = FR/fast trains       (color1 on default bg)
      7  = selected row         (default bg on color4)
      8  = delay: warning       (color3 on default bg)
      9  = delay: late          (color1 on default bg)
      10 = border/box           (color8 on default bg)
      11 = dim/secondary        (color8 on default bg)
      12 = favorites header     (color5 on default bg)
      13 = status bar           (color0 on color6)
    """
    if wal_colors and curses.can_change_color():
        for i, hex_col in enumerate(wal_colors[:16]):
            try:
                r, g, b = hex_to_curses_rgb(hex_col)
                curses.init_color(i, r, g, b)
            except Exception:
                pass

    # Define pairs using wal color indices (fallback to terminal defaults if needed)
    pairs = [
        (1,  7,  -1),   # normal text
        (2,  6,  -1),   # header accent
        (3,  2,  -1),   # on time (green)
        (4,  4,  -1),   # REG (blue)
        (5,  6,  -1),   # IC (cyan)
        (6,  1,  -1),   # FR fast (red)
        (7,  0,   4),   # selected highlight
        (8,  3,  -1),   # warning delay (yellow)
        (9,  1,  -1),   # late delay (red)
        (10, 8,  -1),   # borders (dark)
        (11, 8,  -1),   # dim secondary
        (12, 5,  -1),   # favorites accent (magenta)
        (13, 0,   6),   # status bar
    ]
    for pair_n, fg, bg in pairs:
        try:
            curses.init_pair(pair_n, fg, bg)
        except Exception:
            pass

# ── Box drawing helpers ───────────────────────────────────────────────────────
BOX = {
    "tl": "┌", "tr": "┐", "bl": "└", "br": "┘",
    "h":  "─", "v":  "│", "lt": "├", "rt": "┤",
    "tt": "┬", "bt": "┴", "cross": "┼",
}

def draw_box(win, y, x, height, width, attr=0):
    """Draw a unicode box on win at (y,x) with given dimensions."""
    h, w = win.getmaxyx()
    if y + height > h or x + width > w:
        return
    try:
        win.addstr(y,              x,             BOX["tl"] + BOX["h"] * (width-2) + BOX["tr"], attr)
        win.addstr(y + height - 1, x,             BOX["bl"] + BOX["h"] * (width-2) + BOX["br"], attr)
        for row in range(1, height - 1):
            win.addstr(y + row, x,             BOX["v"], attr)
            win.addstr(y + row, x + width - 1, BOX["v"], attr)
    except curses.error:
        pass

def draw_hline(win, y, x, width, attr=0, left_joint=False, right_joint=False):
    """Draw a horizontal separator line, optionally with T-joints."""
    lc = BOX["lt"] if left_joint else BOX["h"]
    rc = BOX["rt"] if right_joint else BOX["h"]
    try:
        win.addstr(y, x, lc + BOX["h"] * (width - 2) + rc, attr)
    except curses.error:
        pass

def safe_addstr(win, y, x, text, attr=0):
    h, w = win.getmaxyx()
    if y < 0 or y >= h or x < 0 or x >= w:
        return
    max_len = w - x - 1
    if max_len <= 0:
        return
    try:
        win.addstr(y, x, text[:max_len], attr)
    except curses.error:
        pass

def centered(text, width):
    """Center text within width."""
    if len(text) >= width:
        return text[:width]
    pad = (width - len(text)) // 2
    return " " * pad + text

# ── API functions ─────────────────────────────────────────────────────────────
def build_js_datetime_string(dt):
    return dt.strftime("%a %b %d %Y %H:%M:%S GMT%z")

def get_next_departures(station_id, custom_dt):
    date_str = build_js_datetime_string(custom_dt)
    url = f"{BASE_URL}/partenze/{station_id}/{date_str}"
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            return resp.json()
    except Exception:
        pass
    return None

def get_train_origin_and_timestamp(train_number):
    if train_number in _cache_origin:
        return _cache_origin[train_number]
    url = f"{BASE_URL}/cercaNumeroTrenoTrenoAutocomplete/{train_number}"
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            text = resp.text.strip()
            for line in text.split("\n"):
                parts = line.split("|")
                if len(parts) == 2:
                    right = parts[1].split("-")
                    if len(right) >= 3:
                        result = right[1], right[2]
                        _cache_origin[train_number] = result
                        return result
    except Exception:
        pass
    return None, None

def get_full_route(origin_id, train_number, timestamp_ms):
    key = (origin_id, train_number, timestamp_ms)
    if key in _cache_route:
        return _cache_route[key]
    url = f"{BASE_URL}/tratteCanvas/{origin_id}/{train_number}/{timestamp_ms}"
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            _cache_route[key] = data
            return data
    except Exception:
        pass
    return None

def get_train_status(origin_id, train_number, timestamp_ms):
    url = f"{BASE_URL}/andamentoTreno/{origin_id}/{train_number}/{timestamp_ms}"
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            return resp.json()
    except Exception:
        pass
    return None

def format_timestamp_epoch_ms(ms):
    try:
        ts = int(ms) // 1000
        dt = datetime.fromtimestamp(ts, TZ)
        return dt.strftime("%H:%M")
    except Exception:
        return "  -  "

def resolve_station(name, stdscr):
    url = f"{BASE_URL}/cercaStazione/{name}"
    try:
        resp = requests.get(url, timeout=10)
        if resp.status_code != 200:
            return None, None
        data = resp.json()
        if not data:
            return None, None
    except Exception:
        return None, None

    target_lower = name.lower()
    exact = [s for s in data if
             (s.get("label") or "").lower() == target_lower or
             (s.get("nomeLungo") or "").lower() == target_lower]
    if len(exact) == 1:
        return exact[0].get("id"), exact[0].get("nomeLungo") or name

    # Multiple results: selection modal
    selected = 0
    scroll_top = 0
    border_attr = curses.color_pair(10)
    header_attr = curses.color_pair(2) | curses.A_BOLD
    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()
        modal_w = min(70, w - 4)
        modal_h = min(len(data) + 6, h - 4)
        mx = (w - modal_w) // 2
        my = (h - modal_h) // 2
        draw_box(stdscr, my, mx, modal_h, modal_w, border_attr)
        title = f" 🔍 Stazioni trovate per '{name}' "
        safe_addstr(stdscr, my, mx + (modal_w - len(title)) // 2, title, header_attr)
        safe_addstr(stdscr, my + 1, mx + 2,
                    "j/k  naviga   Enter  seleziona   q  annulla",
                    curses.color_pair(11))
        draw_hline(stdscr, my + 2, mx, modal_w, border_attr, left_joint=True, right_joint=True)
        visible = modal_h - 5
        for idx in range(scroll_top, min(scroll_top + visible, len(data))):
            station = data[idx]
            long_name = station.get("nomeLungo") or station.get("label") or "(sconosciuta)"
            code = station.get("id") or "?"
            is_sel = (idx == selected)
            attr = curses.color_pair(7) | curses.A_BOLD if is_sel else curses.color_pair(1)
            prefix = " ▶ " if is_sel else "   "
            line = f"{prefix}{long_name}  [{code}]"
            safe_addstr(stdscr, my + 3 + (idx - scroll_top), mx + 1, line.ljust(modal_w - 2), attr)
        stdscr.refresh()
        key = stdscr.getch()
        if key in (curses.KEY_UP, ord('k')) and selected > 0:
            selected -= 1
            if selected < scroll_top:
                scroll_top = selected
        elif key in (curses.KEY_DOWN, ord('j')) and selected < len(data) - 1:
            selected += 1
            if selected >= scroll_top + visible:
                scroll_top = selected - visible + 1
        elif key == 10:
            chosen = data[selected]
            return chosen.get("id"), chosen.get("nomeLungo") or name
        elif key in (27, ord('q')):
            return None, None

def time_picker_modal(stdscr, current_dt):
    year   = current_dt.year
    month  = current_dt.month
    day    = current_dt.day
    hour   = current_dt.hour
    minute = current_dt.minute // 5 * 5
    fields = ["Anno", "Mese", "Giorno", "Ora", "Minuti"]
    selected_field = 0
    border_attr = curses.color_pair(10)
    header_attr = curses.color_pair(2) | curses.A_BOLD
    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()
        modal_w = 44
        modal_h = 14
        mx = (w - modal_w) // 2
        my = (h - modal_h) // 2
        draw_box(stdscr, my, mx, modal_h, modal_w, border_attr)
        title = " 🕐 Seleziona orario "
        safe_addstr(stdscr, my, mx + (modal_w - len(title)) // 2, title, header_attr)
        safe_addstr(stdscr, my + 1, mx + 2,
                    "j/k campo   h/l valore   Enter ok   q annulla",
                    curses.color_pair(11))
        draw_hline(stdscr, my + 2, mx, modal_w, border_attr, True, True)
        field_vals = [year, f"{month:02d}", f"{day:02d}", f"{hour:02d}", f"{minute:02d}"]
        for i, (fname, fval) in enumerate(zip(fields, field_vals)):
            is_sel = (i == selected_field)
            lattr = curses.color_pair(2) | curses.A_BOLD if is_sel else curses.color_pair(11)
            vattr = curses.color_pair(7) | curses.A_BOLD if is_sel else curses.color_pair(1)
            arrow = "◀ " if is_sel else "  "
            safe_addstr(stdscr, my + 3 + i, mx + 2, f"{fname:<8}", lattr)
            safe_addstr(stdscr, my + 3 + i, mx + 11, f" {fval} ", vattr)
            if is_sel:
                safe_addstr(stdscr, my + 3 + i, mx + 17, " ▶", curses.color_pair(2))
        draw_hline(stdscr, my + 9, mx, modal_w, border_attr, True, True)
        preview = f"  📅 {year}-{month:02d}-{day:02d}  🕐 {hour:02d}:{minute:02d}"
        safe_addstr(stdscr, my + 10, mx + 2, preview, curses.color_pair(5) | curses.A_BOLD)
        stdscr.refresh()
        key = stdscr.getch()
        if key in (curses.KEY_UP, ord('k')) and selected_field > 0:
            selected_field -= 1
        elif key in (curses.KEY_DOWN, ord('j')) and selected_field < 4:
            selected_field += 1
        elif key in (curses.KEY_LEFT, ord('h')):
            if selected_field == 0:   year = max(2020, year - 1)
            elif selected_field == 1: month = (month - 2) % 12 + 1
            elif selected_field == 2:
                day -= 1
                if day < 1:
                    month = (month - 2) % 12 + 1
                    if month == 12: year -= 1
                    day = calendar.monthrange(year, month)[1]
            elif selected_field == 3: hour = (hour - 1) % 24
            elif selected_field == 4: minute = (minute - 5) % 60
        elif key in (curses.KEY_RIGHT, ord('l')):
            if selected_field == 0:   year += 1
            elif selected_field == 1: month = month % 12 + 1
            elif selected_field == 2:
                max_day = calendar.monthrange(year, month)[1]
                day = day % max_day + 1
            elif selected_field == 3: hour = (hour + 1) % 24
            elif selected_field == 4: minute = (minute + 5) % 60
        elif key == 10:
            try:
                new_dt = TZ.localize(datetime(year, month, day, hour, minute))
                return new_dt
            except ValueError:
                pass
        elif key in (27, ord('q')):
            return None

def fetch_trains(dep_id, dep_name, arr_id, arr_name, custom_dt, stdscr):
    h, w = stdscr.getmaxyx()
    spinner = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    spin_i = [0]
    border_attr = curses.color_pair(10)
    header_attr = curses.color_pair(2) | curses.A_BOLD

    def draw_loading(msg):
        stdscr.clear()
        mw, mh = 52, 7
        mx = (w - mw) // 2
        my = (h - mh) // 2
        draw_box(stdscr, my, mx, mh, mw, border_attr)
        title = " 🚄 Ricerca treni in corso "
        safe_addstr(stdscr, my, mx + (mw - len(title)) // 2, title, header_attr)
        spin = spinner[spin_i[0] % len(spinner)]
        spin_i[0] += 1
        safe_addstr(stdscr, my + 2, mx + 4, f" {spin}  {msg[:mw-8]}", curses.color_pair(5))
        route = f"  🚉 {dep_name}  →  {arr_name}"
        safe_addstr(stdscr, my + 4, mx + 2, route[:mw-4], curses.color_pair(1))
        stdscr.refresh()

    found = []
    error_msg = ""
    max_check_per_batch = 30
    min_trains = 5
    max_iterations = 10
    iteration = 0
    query_dt = custom_dt

    while len(found) < min_trains and iteration < max_iterations:
        draw_loading(f"Scaricando partenze... (trovati {len(found)})")
        departures = get_next_departures(dep_id, query_dt)
        if not departures:
            error_msg = "⚠️  Errore API partenze."
            break
        now_ms = int(query_dt.timestamp() * 1000)
        upcoming = [t for t in departures
                    if int(t.get("orarioPartenza") or t.get("partenzaTeorico") or 0) >= now_ms]
        if not upcoming:
            error_msg = "⚠️  Nessuna partenza trovata."
            break
        for train in sorted(upcoming, key=lambda t: int(
                t.get("orarioPartenza") or t.get("partenzaTeorico") or 0))[:max_check_per_batch]:
            train_number = train.get("numeroTreno")
            if not train_number:
                continue
            draw_loading(f"Analisi treno {train_number}... (trovati {len(found)})")
            origin_id, timestamp_ms = get_train_origin_and_timestamp(train_number)
            if not origin_id:
                continue
            stops = get_full_route(origin_id, train_number, timestamp_ms)
            if not stops:
                continue
            dep_index = next((idx for idx, stop in enumerate(stops)
                              if (stop.get("stazione") or "").strip().lower() == dep_name.lower()), None)
            if dep_index is None:
                continue
            arr_index = next((idx for idx in range(dep_index + 1, len(stops))
                              if (stops[idx].get("stazione") or "").strip().lower() == arr_name.lower()), None)
            if arr_index is None:
                continue
            scheduled = format_timestamp_epoch_ms(
                train.get("orarioPartenza") or train.get("partenzaTeorico") or 0)
            ritardo  = int(train.get("ritardo") or 0)
            full_dest = train.get("destinazione") or "-"
            tipo      = (train.get("categoria") or "REG").upper()
            # Compute journey duration
            dep_ms  = int(train.get("orarioPartenza") or train.get("partenzaTeorico") or 0)
            arr_raw = stops[arr_index].get("arrivoTeorico") or stops[arr_index].get("partenzaTeorica") or 0
            arr_ms  = int(arr_raw) if arr_raw else 0
            if dep_ms and arr_ms and arr_ms > dep_ms:
                duration_min = (arr_ms - dep_ms) // 60000
                dur_str = f"{duration_min//60}h{duration_min%60:02d}m" if duration_min >= 60 else f"{duration_min}min"
            else:
                dur_str = "-"
            found.append({
                "numero":    str(train_number),
                "scheduled": scheduled,
                "ritardo":   ritardo,
                "full_dest": full_dest,
                "tipo":      tipo,
                "origin_id": origin_id,
                "timestamp_ms": timestamp_ms,
                "duration":  dur_str,
            })
        if upcoming:
            last_ms = sorted(upcoming, key=lambda t: int(
                t.get("orarioPartenza") or t.get("partenzaTeorico") or 0))[-1].get("orarioPartenza") or 0
            query_dt = datetime.fromtimestamp(last_ms / 1000, TZ) + timedelta(minutes=1)
        iteration += 1

    if not found:
        return [], error_msg or "⚠️  Nessun treno trovato."
    return found, f"✅ Trovati {len(found)} treni."

# ── Help overlay ──────────────────────────────────────────────────────────────
def draw_help_overlay(stdscr):
    h, w = stdscr.getmaxyx()
    border_attr = curses.color_pair(10)
    header_attr = curses.color_pair(2) | curses.A_BOLD
    key_attr    = curses.color_pair(5) | curses.A_BOLD
    desc_attr   = curses.color_pair(1)
    sections = [
        ("Navigazione", [
            ("j / k",       "Su / Giù"),
            ("h / l",       "Sinistra / Destra"),
            ("Enter",       "Seleziona / Conferma"),
            ("i",           "Modalità inserimento"),
            ("Esc",         "Modalità normale / Indietro"),
        ]),
        ("Azioni", [
            ("r",           "Aggiorna risultati"),
            ("t",           "Scegli orario"),
            ("f",           "Cambia filtro tipo treno"),
            ("b",           "Torna ai risultati"),
            ("?",           "Mostra questo aiuto"),
            (":q",          "Esci"),
        ]),
        ("Legenda treni", [
            ("🔴 FR/FA/FB",  "Frecce (alta velocità)"),
            ("🔵 IC/ICN/EC", "Intercity / EuroCity"),
            ("🚂 REG/RV",    "Regionale / Reg. Veloce"),
        ]),
    ]
    total_lines = sum(len(v) + 2 for _, v in sections) + 2
    mw = 52
    mh = min(total_lines, h - 4)
    mx = (w - mw) // 2
    my = (h - mh) // 2
    draw_box(stdscr, my, mx, mh, mw, border_attr)
    title = " ❓ Aiuto — TreNOT "
    safe_addstr(stdscr, my, mx + (mw - len(title)) // 2, title, header_attr)
    row = my + 1
    for sec_title, items in sections:
        if row >= my + mh - 1: break
        safe_addstr(stdscr, row, mx + 2, f"  {sec_title}", curses.color_pair(12) | curses.A_BOLD)
        row += 1
        for key, desc in items:
            if row >= my + mh - 1: break
            safe_addstr(stdscr, row, mx + 4, f"{key:<14}", key_attr)
            safe_addstr(stdscr, row, mx + 19, desc[:mw-21], desc_attr)
            row += 1
        row += 1
    safe_addstr(stdscr, my + mh - 1, mx + 2,
                BOX["h"] * (mw - 4), border_attr)
    safe_addstr(stdscr, my + mh - 1, mx + (mw - 18) // 2,
                " Premi ? per chiudere ", curses.color_pair(11))
    stdscr.refresh()
    while True:
        k = stdscr.getch()
        if k in (ord('?'), ord('q'), 27, 10):
            break

# ── Main ──────────────────────────────────────────────────────────────────────
def main(stdscr):
    stdscr.keypad(True)
    curses.curs_set(0)
    curses.use_default_colors()

    wal_colors = load_wal_colors()
    init_wal_colors(wal_colors)

    dep_name = ""
    arr_name = ""
    dep_id   = None
    arr_id   = None
    trains   = []
    error_msg = ""
    vim_mode  = "normal"
    last_refresh = 0
    last_refresh_details = 0
    app_mode  = "input"
    custom_dt = datetime.now(TZ)
    query_time_str = "adesso"
    favorites = ["Pavia", "Voghera", "Milano Centrale", "Milano Rogoredo", "Milano Lambrate"]
    status    = "NORMAL  j/k naviga   i inserisci   Enter conferma   ? aiuto   :q esci"
    section   = "header"
    header_row = 0
    header_col = 0
    body_selected = 0
    favorites_scroll = 0
    results_scroll   = 0
    selected_train   = 0
    current_train    = None
    train_details    = None
    details_scroll   = 0
    filter_type      = "all"

    while True:
        stdscr.clear()
        h, w = stdscr.getmaxyx()

        # ── Top bar ───────────────────────────────────────────────────────────
        topbar = f" 🚄 TreNOT  [{vim_mode.upper()} MODE] "
        safe_addstr(stdscr, 0, 0, " " * w, curses.color_pair(13))
        safe_addstr(stdscr, 0, 0, topbar, curses.color_pair(13) | curses.A_BOLD)
        now_str = datetime.now(TZ).strftime("%H:%M:%S")
        safe_addstr(stdscr, 0, w - len(now_str) - 2, now_str, curses.color_pair(13))

        # ── Status bar ────────────────────────────────────────────────────────
        safe_addstr(stdscr, h-1, 0, " " * w, curses.color_pair(13))
        safe_addstr(stdscr, h-1, 1, status[:w-2], curses.color_pair(13))
        if error_msg:
            safe_addstr(stdscr, h-2, 1, error_msg[:w-2], curses.color_pair(9) | curses.A_BOLD)

        # ── Input / Results ───────────────────────────────────────────────────
        if app_mode in ("input", "results"):
            # Route header box
            draw_box(stdscr, 1, 0, 4, w, curses.color_pair(10))

            dep_label = "🚉 Partenza"
            arr_label = "🏁 Arrivo"
            dep_val   = dep_name if dep_name else "(vuoto)"
            arr_val   = arr_name if arr_name else "(vuoto)"

            dep_attr  = (curses.color_pair(7) | curses.A_BOLD) if (section == "header" and header_row == 0 and header_col == 0) else curses.color_pair(5)
            arr_attr  = (curses.color_pair(7) | curses.A_BOLD) if (section == "header" and header_row == 1) else curses.color_pair(4)
            swap_attr = (curses.color_pair(7) | curses.A_BOLD) if (section == "header" and header_row == 0 and header_col == 1) else curses.color_pair(12)

            safe_addstr(stdscr, 2, 2,  f"{dep_label}: ", curses.color_pair(11))
            safe_addstr(stdscr, 2, 14, dep_val, dep_attr)
            swap_x = min(w - 12, 45)
            safe_addstr(stdscr, 2, swap_x, "[ Swap ]", swap_attr)
            safe_addstr(stdscr, 3, 2,  f"{arr_label}:  ", curses.color_pair(11))
            safe_addstr(stdscr, 3, 14, arr_val, arr_attr)

            if app_mode == "input":
                # Favorites panel
                panel_y = 5
                panel_h = h - 7
                draw_box(stdscr, panel_y, 0, panel_h, w, curses.color_pair(10))
                fav_title = " ⭐ Stazioni preferite "
                safe_addstr(stdscr, panel_y, 2, fav_title, curses.color_pair(12) | curses.A_BOLD)
                visible_fav = panel_h - 2
                for idx in range(favorites_scroll, min(favorites_scroll + visible_fav, len(favorites))):
                    fav = favorites[idx]
                    is_sel = (section == "body" and body_selected == idx)
                    attr = curses.color_pair(7) | curses.A_BOLD if is_sel else curses.color_pair(1)
                    prefix = " ▶ " if is_sel else "   "
                    safe_addstr(stdscr, panel_y + 1 + (idx - favorites_scroll), 1,
                                f"{prefix}{idx+1}. {fav}".ljust(w - 3), attr)

            elif app_mode == "results":
                # Filter badge
                filter_labels = {"all": "Tutti 🚆", "reg": "REG 🚂", "ic": "IC 🔵"}
                filter_badge  = f" Filtro: {filter_labels.get(filter_type, filter_type)} "
                safe_addstr(stdscr, 3, swap_x - len(filter_badge) - 2,
                            filter_badge, curses.color_pair(8))

                filtered_trains = trains
                if filter_type == "reg":
                    filtered_trains = [t for t in trains if t['tipo'] in ("REG","RV")]
                elif filter_type == "ic":
                    filtered_trains = [t for t in trains if t['tipo'] in ("IC","ICN","EC")]
                # Clamp selection to valid range
                if filtered_trains:
                    selected_train = min(selected_train, len(filtered_trains) - 1)
                    results_scroll = min(results_scroll, len(filtered_trains) - 1)
                else:
                    selected_train = 0
                    results_scroll = 0

                results_y = 5
                results_h = h - 7
                draw_box(stdscr, results_y, 0, results_h, w, curses.color_pair(10))

                route_title = f" 🗺  {dep_name}  →  {arr_name}   📅 {query_time_str} "
                safe_addstr(stdscr, results_y, 2, route_title,
                            curses.color_pair(2) | curses.A_BOLD)
                draw_hline(stdscr, results_y + 1, 0, w, curses.color_pair(10), True, True)

                # Column headers — positions match data row addstr x values exactly
                hdr_attr = curses.color_pair(11) | curses.A_BOLD
                safe_addstr(stdscr, results_y + 2,  2, f"{'Tipo':<8}",     hdr_attr)
                safe_addstr(stdscr, results_y + 2, 10, f"{'Treno':<7}",    hdr_attr)
                safe_addstr(stdscr, results_y + 2, 17, f"{'Orario':<7}",   hdr_attr)
                safe_addstr(stdscr, results_y + 2, 24, f"{'Durata':<8}",   hdr_attr)
                safe_addstr(stdscr, results_y + 2, 32, f"{'Ritardo':<14}", hdr_attr)
                safe_addstr(stdscr, results_y + 2, 46, 'Destinazione',      hdr_attr)
                draw_hline(stdscr, results_y + 3, 0, w, curses.color_pair(10), True, True)

                visible = results_h - 6
                if not filtered_trains:
                    safe_addstr(stdscr, results_y + 4, 3,
                                "⚠️  Nessun treno trovato per questo filtro.",
                                curses.color_pair(9))
                else:
                    for idx in range(results_scroll, min(results_scroll + visible, len(filtered_trains))):
                        t = filtered_trains[idx]
                        meta    = TRAIN_META.get(t['tipo'], DEFAULT_META)
                        emoji   = meta["emoji"]
                        tipo_cp = curses.color_pair(meta["color_idx"])
                        d_emoji = delay_emoji(t['ritardo'])
                        d_str   = delay_str(t['ritardo'])
                        if t['ritardo'] <= 0:
                            d_attr = curses.color_pair(3)
                        elif t['ritardo'] <= 5:
                            d_attr = curses.color_pair(8)
                        else:
                            d_attr = curses.color_pair(9)
                        is_sel  = (idx == selected_train)
                        row_y   = results_y + 4 + (idx - results_scroll)
                        bold    = curses.A_BOLD if is_sel else 0
                        # ▶ cursor indicator in left margin — no background fill
                        cursor = "▶" if is_sel else " "
                        safe_addstr(stdscr, row_y, 0, cursor,
                                    curses.color_pair(2) | curses.A_BOLD if is_sel else curses.color_pair(11))
                        # Draw each column — colors preserved, just bolded when selected
                        safe_addstr(stdscr, row_y, 2,  f"{emoji} {t['tipo']:<4}", tipo_cp | bold)
                        safe_addstr(stdscr, row_y, 10, f"{t['numero']:<7}",        curses.color_pair(1) | bold)
                        safe_addstr(stdscr, row_y, 17, f"{t['scheduled']:<7}",     curses.color_pair(2) | bold)
                        safe_addstr(stdscr, row_y, 24, f"{t['duration']:<8}",      curses.color_pair(11) | bold)
                        safe_addstr(stdscr, row_y, 32, f"{d_emoji} {d_str:<11}",   d_attr | bold)
                        dest_x = 46
                        safe_addstr(stdscr, row_y, dest_x, t['full_dest'][:w - dest_x - 2],
                                    curses.color_pair(1) | bold)

        # ── Details ───────────────────────────────────────────────────────────
        elif app_mode == "details":
            curses.curs_set(0)
            meta    = TRAIN_META.get(current_train['tipo'], DEFAULT_META)
            emoji   = meta["emoji"]
            tipo_cp = curses.color_pair(meta["color_idx"])

            draw_box(stdscr, 1, 0, 4, w, curses.color_pair(10))
            header_text = f" {emoji} {current_train['tipo']} {current_train['numero']}  →  {current_train['full_dest']} "
            safe_addstr(stdscr, 1, (w - len(header_text)) // 2,
                        header_text, tipo_cp | curses.A_BOLD)

            if train_details:
                last_station  = train_details.get("stazioneUltimoRilevamento", "-")
                last_time     = format_timestamp_epoch_ms(train_details.get("oraUltimoRilevamento", 0))
                overall_delay = train_details.get("ritardo", 0)
                d_emoji       = delay_emoji(overall_delay)
                d_str         = delay_str(overall_delay)
                info = f"  {d_emoji} {d_str}   📍 Ultimo rilevamento: {last_station} alle {last_time}"
                safe_addstr(stdscr, 2, 1, info[:w-2],
                            curses.color_pair(3) if overall_delay <= 0 else curses.color_pair(9))

            draw_hline(stdscr, 4, 0, w, curses.color_pair(10), True, True)

            # Column headers for stops
            col_hdr = f"  {'Stazione':<28} {'P.Teo':>6}  {'P.Rea':>6}  {'Rit':>4}  {'A.Teo':>6}  {'A.Rea':>6}  {'Rit':>4}"
            safe_addstr(stdscr, 5, 0, col_hdr[:w-1], curses.color_pair(11) | curses.A_BOLD)
            draw_hline(stdscr, 6, 0, w, curses.color_pair(10), True, True)

            fermate  = train_details.get("fermate", []) if train_details else []
            visible  = h - 10
            for idx in range(details_scroll, min(details_scroll + visible, len(fermate))):
                stop      = fermate[idx]
                station   = (stop.get("stazione") or "-")[:26]
                s_dep     = format_timestamp_epoch_ms(stop.get("partenzaTeorica", 0)) if stop.get("partenzaTeorica") else "  -  "
                a_dep     = format_timestamp_epoch_ms(stop.get("partenzaReale", 0))   if stop.get("partenzaReale")   else "  -  "
                d_dep     = str(stop.get("ritardoPartenza", "-")) if "ritardoPartenza" in stop else "-"
                s_arr     = format_timestamp_epoch_ms(stop.get("arrivoTeorico", 0))   if stop.get("arrivoTeorico")   else "  -  "
                a_arr     = format_timestamp_epoch_ms(stop.get("arrivoReale", 0))     if stop.get("arrivoReale")     else "  -  "
                d_arr     = str(stop.get("ritardoArrivo", "-"))   if "ritardoArrivo"   in stop else "-"
                passed    = bool(stop.get("arrivoReale") or stop.get("partenzaReale"))
                row_attr  = curses.color_pair(11) if passed else curses.color_pair(1)
                pin       = "📍 " if passed else "   "
                line = f"  {pin}{station:<26} {s_dep:>6}  {a_dep:>6}  {d_dep:>4}  {s_arr:>6}  {a_arr:>6}  {d_arr:>4}"
                safe_addstr(stdscr, 7 + (idx - details_scroll), 0, line[:w-1], row_attr)

            if not fermate:
                safe_addstr(stdscr, 7, 3, "⚠️  Nessun dettaglio disponibile.", curses.color_pair(9))

        stdscr.refresh()

        # ── Auto-refresh ──────────────────────────────────────────────────────
        if app_mode == "results" and time.time() - last_refresh > 60:
            trains, msg = fetch_trains(dep_id, dep_name, arr_id, arr_name, custom_dt, stdscr)
            error_msg = msg if not trains else ""
            last_refresh = time.time()
            status = "🔄 Aggiornamento automatico completato."
        elif app_mode == "details" and time.time() - last_refresh_details > 60:
            train_details = get_train_status(
                current_train["origin_id"], current_train["numero"], current_train["timestamp_ms"])
            last_refresh_details = time.time()
            status = "🔄 Dettagli aggiornati."

        # ── Input ─────────────────────────────────────────────────────────────
        stdscr.timeout(1000)
        key = stdscr.getch()
        if key == -1:  # timeout, just redraw (updates clock)
            continue

        if vim_mode == "normal":
            if key == ord('?'):
                draw_help_overlay(stdscr)

            elif key in (ord('i'), ord('a')):
                if app_mode in ("results", "details"):
                    app_mode = "input"
                    dep_id = arr_id = None
                    status = "Torna in input. Modifica e premi Enter."
                    continue
                if section == "header" and header_col == 0:
                    vim_mode = "insert"
                    curses.curs_set(1)
                    status = "INSERT  Digita nella casella   Esc  torna a normale"

            elif key == ord('r'):
                error_msg = ""
                if app_mode == "results":
                    trains, msg = fetch_trains(dep_id, dep_name, arr_id, arr_name, custom_dt, stdscr)
                    error_msg = msg if not trains else ""
                    last_refresh = time.time()
                    status = "🔄 Risultati aggiornati."
                elif app_mode == "details":
                    train_details = get_train_status(
                        current_train["origin_id"], current_train["numero"], current_train["timestamp_ms"])
                    if not train_details:
                        error_msg = "⚠️  Errore nel recupero dettagli."
                    last_refresh_details = time.time()
                    status = "🔄 Dettagli aggiornati."

            elif key == ord('t') and app_mode in ("results", "details", "input"):
                new_dt = time_picker_modal(stdscr, custom_dt)
                if new_dt:
                    custom_dt = new_dt
                    query_time_str = custom_dt.strftime("%d/%m %H:%M")
                    if dep_id and arr_id:
                        trains, msg = fetch_trains(dep_id, dep_name, arr_id, arr_name, custom_dt, stdscr)
                        error_msg = msg if not trains else ""
                        last_refresh = time.time()
                        app_mode = "results"
                    status = f"🕐 Orario impostato: {query_time_str}"

            elif key == ord('f') and app_mode == "results":
                cycle = {"all": "reg", "reg": "ic", "ic": "all"}
                filter_type = cycle.get(filter_type, "all")
                results_scroll = 0
                selected_train = 0
                labels = {"all": "Tutti", "reg": "Solo REG", "ic": "Solo IC"}
                status = f"🔍 Filtro: {labels.get(filter_type)}"

            elif key in (ord('j'), curses.KEY_DOWN):
                if app_mode == "details":
                    max_scroll = max(0, len(train_details.get("fermate", [])) - (h - 10))
                    details_scroll = min(details_scroll + 1, max_scroll)
                elif section == "header":
                    if header_row == 0:
                        header_row = 1; header_col = 0
                    elif header_row == 1:
                        section = "body"
                        body_selected = favorites_scroll
                        selected_train = results_scroll
                elif section == "body":
                    if app_mode == "input":
                        if body_selected < len(favorites) - 1:
                            body_selected += 1
                            if body_selected >= favorites_scroll + (h - 12):
                                favorites_scroll += 1
                    elif app_mode == "results":
                        filtered_trains = [t for t in trains if filter_type == "all"
                                           or (filter_type == "reg" and t['tipo'] in ("REG","RV"))
                                           or (filter_type == "ic" and t['tipo'] in ("IC","ICN","EC"))]
                        if selected_train < len(filtered_trains) - 1:
                            selected_train += 1
                            visible = h - 11
                            if selected_train >= results_scroll + visible:
                                results_scroll += 1

            elif key in (ord('k'), curses.KEY_UP):
                if app_mode == "details":
                    details_scroll = max(0, details_scroll - 1)
                elif section == "body":
                    if app_mode == "input":
                        if body_selected > 0:
                            body_selected -= 1
                            if body_selected < favorites_scroll:
                                favorites_scroll -= 1
                        else:
                            section = "header"; header_row = 1; header_col = 0
                    elif app_mode == "results":
                        if selected_train > 0:
                            selected_train -= 1
                            if selected_train < results_scroll:
                                results_scroll -= 1
                        else:
                            section = "header"; header_row = 1; header_col = 0
                elif section == "header":
                    if header_row == 1:
                        header_row = 0; header_col = 0

            elif key in (ord('l'), curses.KEY_RIGHT):
                if section == "header" and header_row == 0:
                    header_col = 1

            elif key in (ord('h'), curses.KEY_LEFT):
                if section == "header":
                    header_col = 0

            elif key == 10:  # Enter
                error_msg = ""
                if app_mode == "details":
                    pass
                elif section == "header":
                    if header_col == 1:  # Swap
                        dep_name, arr_name = arr_name, dep_name
                        dep_id, arr_id     = arr_id, dep_id
                        status = "⇄ Partenza e arrivo invertiti."
                        if app_mode == "results" and dep_id and arr_id:
                            trains, msg = fetch_trains(dep_id, dep_name, arr_id, arr_name, custom_dt, stdscr)
                            error_msg = msg if not trains else ""
                            last_refresh = time.time()
                    elif header_col == 0 and app_mode == "input":
                        if header_row == 0 and dep_name and not dep_id:
                            dep_id, dep_name = resolve_station(dep_name, stdscr)
                            if not dep_id: error_msg = "⚠️  Stazione di partenza non trovata."
                        elif header_row == 1 and arr_name and not arr_id:
                            arr_id, arr_name = resolve_station(arr_name, stdscr)
                            if not arr_id: error_msg = "⚠️  Stazione di arrivo non trovata."
                        if dep_id and arr_id:
                            trains, msg = fetch_trains(dep_id, dep_name, arr_id, arr_name, custom_dt, stdscr)
                            error_msg = msg if not trains else ""
                            app_mode = "results"
                            last_refresh = time.time()
                            section = "header"; header_row = 0; header_col = 0
                            status = "NORMAL  j/k naviga   r aggiorna   t orario   f filtro   Enter dettagli   ? aiuto"

                elif section == "body" and app_mode == "input":
                    selected_name = favorites[body_selected]
                    if not dep_id:
                        dep_name = selected_name
                        dep_id, dep_name = resolve_station(dep_name, stdscr)
                        if not dep_id: error_msg = f"⚠️  '{selected_name}' non trovata come partenza."
                    elif not arr_id:
                        arr_name = selected_name
                        arr_id, arr_name = resolve_station(arr_name, stdscr)
                        if not arr_id: error_msg = f"⚠️  '{selected_name}' non trovata come arrivo."
                    if dep_id and arr_id:
                        trains, msg = fetch_trains(dep_id, dep_name, arr_id, arr_name, custom_dt, stdscr)
                        error_msg = msg if not trains else ""
                        app_mode = "results"
                        last_refresh = time.time()
                        section = "header"; header_row = 0; header_col = 0
                        status = "NORMAL  j/k naviga   r aggiorna   t orario   f filtro   Enter dettagli   ? aiuto"

                elif section == "body" and app_mode == "results":
                    filtered_trains = [t for t in trains if filter_type == "all"
                                       or (filter_type == "reg" and t['tipo'] in ("REG","RV"))
                                       or (filter_type == "ic" and t['tipo'] in ("IC","ICN","EC"))]
                    if filtered_trains:
                        current_train = filtered_trains[selected_train]
                        train_details = get_train_status(
                            current_train["origin_id"], current_train["numero"], current_train["timestamp_ms"])
                        if train_details:
                            app_mode = "details"
                            details_scroll = 0
                            last_refresh_details = time.time()
                            status = "NORMAL  j/k scorre   r aggiorna   b/Esc torna   ? aiuto"
                        else:
                            error_msg = "⚠️  Impossibile recuperare i dettagli."

            elif key == ord(':'):
                cmd = ""
                while True:
                    safe_addstr(stdscr, h-1, 0, " " * (w-1), curses.color_pair(13))
                    safe_addstr(stdscr, h-1, 0, ":" + cmd, curses.color_pair(13) | curses.A_BOLD)
                    stdscr.refresh()
                    ck = stdscr.getch()
                    if ck == 10:
                        if cmd == "q": return
                        break
                    elif ck in (127, curses.KEY_BACKSPACE):
                        cmd = cmd[:-1]
                    elif 32 <= ck <= 126:
                        cmd += chr(ck)

            elif key in (27, ord('b'), 127, curses.KEY_BACKSPACE):
                if app_mode == "details":
                    app_mode = "results"
                    status = "NORMAL  j/k naviga   r aggiorna   t orario   f filtro   Enter dettagli   ? aiuto"
                elif app_mode == "results":
                    app_mode = "input"
                    dep_id = arr_id = None
                    status = "NORMAL  j/k naviga   i inserisci   Enter conferma   ? aiuto   :q esci"
                else:
                    break

        elif vim_mode == "insert":
            if key == 27:
                vim_mode = "normal"
                curses.curs_set(0)
                status = "NORMAL  j/k naviga   i inserisci   Enter conferma   ? aiuto   :q esci"
            elif key in (127, curses.KEY_BACKSPACE):
                if section == "header" and header_col == 0:
                    if header_row == 0 and dep_name:
                        dep_name = dep_name[:-1]; dep_id = None
                    elif header_row == 1 and arr_name:
                        arr_name = arr_name[:-1]; arr_id = None
            elif key == 10:
                vim_mode = "normal"
                curses.curs_set(0)
                # Auto-advance field
                if header_row == 0 and dep_name:
                    header_row = 1
                elif header_row == 1 and arr_name:
                    dep_id, dep_name = resolve_station(dep_name, stdscr)
                    arr_id, arr_name = resolve_station(arr_name, stdscr)
                    if dep_id and arr_id:
                        trains, msg = fetch_trains(dep_id, dep_name, arr_id, arr_name, custom_dt, stdscr)
                        error_msg = msg if not trains else ""
                        app_mode = "results"
                        last_refresh = time.time()
                        section = "header"; header_row = 0; header_col = 0
                        status = "NORMAL  j/k naviga   r aggiorna   t orario   f filtro   Enter dettagli   ? aiuto"
            elif 32 <= key <= 126:
                if section == "header" and header_col == 0:
                    if header_row == 0:
                        dep_name += chr(key); dep_id = None
                    elif header_row == 1:
                        arr_name += chr(key); arr_id = None

if __name__ == "__main__":
    curses.wrapper(main)
