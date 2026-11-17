#!/bin/bash
# ==============================================================================
#  gpSP+ Core Manager (RetroArch 32-bit) - ArkOS / dArkOS (640x480 Default)
#  Installs/uninstalls gpSP+ for retroarch32 and updates es_systems.cfg (GBA)
#  Author: Victor Cibas | Refactored for Stability | v1.1 Fix
# ==============================================================================

# Abort on undeclared variables (helps catch typos before they cause logic errors)
set -u

# ------------------------------------------------------------------------------
# 1. Paths, OS Detection & Global Variables
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/gpsp_plus"
THEME_RC="/tmp/gpsp_plus_dark.dialogrc"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Detect target user safely
if [ -d "/home/ark" ]; then
    TARGET_USER="ark"
    TARGET_HOME="/home/ark"
else
    TARGET_USER="${SUDO_USER:-$(whoami)}"
    TARGET_HOME="$(eval echo "~$TARGET_USER" 2>/dev/null || echo "/home/$TARGET_USER")"
fi

CORES_DIR="$TARGET_HOME/.config/retroarch32/cores"

# Support user-level override if present, otherwise fallback to system-wide es_systems.cfg
if [ -f "$TARGET_HOME/.emulationstation/es_systems.cfg" ]; then
    ES_CFG="$TARGET_HOME/.emulationstation/es_systems.cfg"
else
    ES_CFG="/etc/emulationstation/es_systems.cfg"
fi
ES_BAK="${ES_CFG}.bak_gpsp_plus_${TIMESTAMP}"

# Detect OS branding for UI title bar safely
OS_NAME="ArkOS/dArkOS"
if [ -f /usr/share/plymouth/themes/text.plymouth ]; then
    DETECTED_OS=$(grep -i '^title=' /usr/share/plymouth/themes/text.plymouth 2>/dev/null | cut -d'=' -f2 | awk '{print $1}')
    [ -n "$DETECTED_OS" ] && OS_NAME="$DETECTED_OS"
fi
BACKTITLE=" $OS_NAME // gpSP+ manager v1.1 (RetroArch 32-bit) | by Victor Cibas"

# Detect active TTY safely (Prevents "not a tty" crash in dialog)
CURR_TTY="$(tty 2>/dev/null)"
if [ -z "$CURR_TTY" ] || [[ "$CURR_TTY" == *"not a tty"* ]]; then
    if [ -e /dev/tty1 ] && [ -z "${SSH_CONNECTION:-}" ]; then
        CURR_TTY="/dev/tty1"
    else
        CURR_TTY="/dev/tty" # Fallback
    fi
fi

# ------------------------------------------------------------------------------
# 2. Adaptive UI Setup & Gamepad Controls
# ------------------------------------------------------------------------------
setup_ui() {
    # Default Fallbacks
    FB_W=640
    FB_H=480

    if [ -r /sys/class/graphics/fb0/virtual_size ]; then
        IFS=',' read -r DETECTED_W DETECTED_H < /sys/class/graphics/fb0/virtual_size 2>/dev/null || true
        if [[ "${DETECTED_W:-0}" =~ ^[0-9]+$ ]] && [ "${DETECTED_W:-0}" -gt 0 ]; then
            FB_W="$DETECTED_W"
            FB_H="$DETECTED_H"
        fi
    fi

    # Graceful font setup handling
    if [ "$CURR_TTY" = "/dev/tty1" ]; then
        if [ "$FB_W" -le 480 ]; then
            for f in /usr/share/consolefonts/Lat7-Terminus14.psf.gz \
                     /usr/share/consolefonts/Uni3-Terminus14.psf.gz \
                     /usr/share/consolefonts/Lat7-Terminus16.psf.gz; do
                [ -f "$f" ] && setfont "$f" > "$CURR_TTY" 2>&1 && break
            done
        elif [ "$FB_W" -ge 1024 ]; then
            for f in /usr/share/consolefonts/Lat7-Terminus24x12.psf.gz \
                     /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz \
                     /usr/share/consolefonts/Lat7-Terminus16.psf.gz; do
                [ -f "$f" ] && setfont "$f" > "$CURR_TTY" 2>&1 && break
            done
        else
            for f in /usr/share/consolefonts/Lat7-Terminus16.psf.gz \
                     /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz; do
                [ -f "$f" ] && setfont "$f" > "$CURR_TTY" 2>&1 && break
            done
        fi
    fi

    # Custom modern dark theme for dialog
    cat << 'EOF' > "$THEME_RC"
aspect = 0
separate_widget = ""
tab_len = 0
visit_items = OFF
use_shadow = OFF
use_colors = ON
screen_color = (CYAN,BLACK,ON)
shadow_color = (BLACK,BLACK,ON)
dialog_color = (WHITE,BLACK,OFF)
title_color = (CYAN,BLACK,ON)
border_color = (CYAN,BLACK,ON)
button_active_color = (BLACK,CYAN,ON)
button_inactive_color = (WHITE,BLACK,OFF)
button_key_active_color = (BLACK,CYAN,ON)
button_key_inactive_color = (CYAN,BLACK,ON)
button_label_active_color = (BLACK,CYAN,ON)
button_label_inactive_color = (WHITE,BLACK,OFF)
inputbox_color = (WHITE,BLACK,OFF)
inputbox_border_color = (CYAN,BLACK,ON)
searchbox_color = (WHITE,BLACK,OFF)
searchbox_title_color = (CYAN,BLACK,ON)
searchbox_border_color = (CYAN,BLACK,ON)
position_indicator_color = (CYAN,BLACK,ON)
menubox_color = (WHITE,BLACK,OFF)
menubox_border_color = (CYAN,BLACK,ON)
item_color = (WHITE,BLACK,OFF)
item_selected_color = (BLACK,CYAN,ON)
tag_color = (CYAN,BLACK,ON)
tag_selected_color = (BLACK,CYAN,ON)
tag_key_color = (CYAN,BLACK,ON)
tag_key_selected_color = (BLACK,CYAN,ON)
check_color = (WHITE,BLACK,OFF)
check_selected_color = (BLACK,CYAN,ON)
uarrow_color = (CYAN,BLACK,ON)
darrow_color = (CYAN,BLACK,ON)
itemhelp_color = (WHITE,BLACK,OFF)
form_active_text_color = (BLACK,CYAN,ON)
form_text_color = (WHITE,BLACK,OFF)
form_item_readonly_color = (CYAN,BLACK,ON)
gauge_color = (CYAN,BLACK,ON)
border2_color = (CYAN,BLACK,ON)
inputbox_border2_color = (CYAN,BLACK,ON)
searchbox_border2_color = (CYAN,BLACK,ON)
menubox_border2_color = (CYAN,BLACK,ON)
EOF
    export DIALOGRC="$THEME_RC"

    # Standard Input controller logic (gptokeyb)
    GPTOKEYB_PID=""
    GPTOKEYB_BIN=""
    for bin in /opt/inttools/gptokeyb /usr/local/bin/gptokeyb; do
        if [ -x "$bin" ]; then GPTOKEYB_BIN="$bin"; break; fi
    done
    [ -z "$GPTOKEYB_BIN" ] && GPTOKEYB_BIN="$(command -v gptokeyb 2>/dev/null || true)"

    if [ -n "$GPTOKEYB_BIN" ] && [ -x "$GPTOKEYB_BIN" ]; then
        sudo chmod 666 /dev/uinput 2>/dev/null || true
        for db in /opt/inttools/gamecontrollerdb.txt \
                  /roms/tools/PortMaster/gamecontrollerdb.txt \
                  /roms2/tools/PortMaster/gamecontrollerdb.txt \
                  /opt/system/Tools/PortMaster/gamecontrollerdb.txt; do
            if [ -f "$db" ]; then
                export SDL_GAMECONTROLLERCONFIG_FILE="$db"
                break
            fi
        done

        # Uses the system's default key mapping configuration
        if [ -f /opt/inttools/keys.gptk ]; then
            "$GPTOKEYB_BIN" -1 "dialog" -c "/opt/inttools/keys.gptk" >/dev/null 2>&1 &
        else
            "$GPTOKEYB_BIN" -1 "dialog" >/dev/null 2>&1 &
        fi
        GPTOKEYB_PID=$!
    fi

    # Fallback to standard 30x80 if dimension gathering fails
    read -r ROWS COLS < <(stty size < "$CURR_TTY" 2>/dev/null || echo "30 80")
    [ -z "${ROWS:-}" ] || [ "$ROWS" -le 0 ] && ROWS=30
    [ -z "${COLS:-}" ] || [ "$COLS" -le 0 ] && COLS=80

    # Ensure bounds are safe to prevent dialog crash
    BOX_W=$((COLS - 6))
    [ "$BOX_W" -gt 72 ] && BOX_W=72
    [ "$BOX_W" -lt 46 ] && BOX_W=46

    BOX_H=$((ROWS - 4))
    [ "$BOX_H" -gt 24 ] && BOX_H=24
    [ "$BOX_H" -lt 18 ] && BOX_H=18

    INFO_W=$((BOX_W - 6))
    [ "$INFO_W" -lt 40 ] && INFO_W=40
}

cleanup() {
    # Safe cleanup on exit
    if [ -n "${GPTOKEYB_PID:-}" ] && kill -0 "$GPTOKEYB_PID" 2>/dev/null; then
        kill "$GPTOKEYB_PID" >/dev/null 2>&1 || true
    fi
    pkill -f "gptokeyb -1 dialog" >/dev/null 2>&1 || true
    rm -f "$THEME_RC"
    printf "\033c" > "$CURR_TTY" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

center_line() {
    local text="$1"
    local width="$2"
    local len=${#text}
    if [ "$len" -ge "$width" ]; then
        printf "%s" "$text"
    else
        local pad=$(( (width - len) / 2 ))
        printf "%*s%s" "$pad" "" "$text"
    fi
}

build_header() {
    local inner_w=$((BOX_W - 4))
    local div_w=$((inner_w - 4))
    [ "$div_w" -gt 54 ] && div_w=54
    [ "$div_w" -lt 36 ] && div_w=36

    local divider
    divider=$(printf '%*s' "$div_w" '' | tr ' ' '=')

    local l1 l2 l3 l4 sub cred div s1 s2 s3
    l1=$(center_line '   ___  ___  ___  ___    _   ' "$inner_w")
    l2=$(center_line '  / __|| _ \/ __|| _ \ _| |_ ' "$inner_w")
    l3=$(center_line ' | (_ ||  _/\__ \|  _/|_   _|' "$inner_w")
    l4=$(center_line '  \___||_|  |___/|_|    |_|  ' "$inner_w")
    sub=$(center_line "RetroArch 32-bit Core Manager" "$inner_w")
    cred=$(center_line "w" "$inner_w")
    div=$(center_line "$divider" "$inner_w")

    local st_block_w=34
    local st_pad=$(( (inner_w - st_block_w) / 2 ))
    [ "$st_pad" -lt 1 ] && st_pad=1
    local pad_str
    pad_str=$(printf "%*s" "$st_pad" "")

    s1="${pad_str}Source (gpsp_plus) : [$ST_SRC]"
    s2="${pad_str}RetroArch 32-bit   : [$ST_CORE]"
    s3="${pad_str}ES Config (GBA)    : [$ST_CFG]"

    if [ "$ROWS" -lt 23 ]; then
        printf "%s\n%s\n%s\n%s\n%s\n%s\n%s" "$sub" "$cred" "$div" "$s1" "$s2" "$s3" ""
    else
        printf "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s" \
            "$l1" "$l2" "$l3" "$l4" "$sub" "$cred" "$div" "$s1" "$s2" "$s3"
    fi
}

# ------------------------------------------------------------------------------
# 3. System Status & es_systems.cfg XML Handler
# ------------------------------------------------------------------------------
check_status() {
    ST_SRC="MISSING"
    ST_CORE="MISSING"
    ST_CFG="PENDING"

    # 1. Source check safely
    if [ -d "$SRC_DIR" ]; then
        SO_SRC=$(find "$SRC_DIR" -maxdepth 1 -type f -name "*.so" 2>/dev/null | head -n 1)
        INFO_SRC=$(find "$SRC_DIR" -maxdepth 1 -type f -name "*.info" 2>/dev/null | head -n 1)
        if [ -n "$SO_SRC" ] && [ -n "$INFO_SRC" ]; then
            ST_SRC="OK"
        fi
    fi

    # 2. Installed core check
    if [ -f "$CORES_DIR/gpsp_plus_libretro.so" ] && [ -f "$CORES_DIR/gpsp_plus_libretro.info" ]; then
        ST_CORE="INSTALLED"
    fi

    # 3. ES XML Check (Robust Python execution)
    if [ -f "$ES_CFG" ] && sudo python3 - "$ES_CFG" "check" 2>/dev/null << 'PYEOF'
import re, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        text = f.read()
    for sys_m in re.finditer(r'<system\b[^>]*>.*?</system>', text, re.DOTALL):
        s_block = sys_m.group(0)
        if re.search(r'<name>\s*gba\s*</name>', s_block):
            emu_m = re.search(r'<emulator\b[^>]*name=["\']retroarch32["\'][^>]*>.*?</emulator>', s_block, re.DOTALL)
            if emu_m and re.search(r'<core>\s*gpsp_plus\s*</core>', emu_m.group(0)):
                sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYEOF
    then
        ST_CFG="ACTIVE"
    fi
}

edit_es_systems() {
    local ACTION="$1"

    # Always create a fresh backup before modifying
    sudo cp -p "$ES_CFG" "$ES_BAK" || return 1

    # Python handler with stderr capturing for crash prevention
    sudo python3 - "$ES_CFG" "$ACTION" << 'PYEOF'
import os, re, sys, tempfile

cfg_path = sys.argv[1]
action = sys.argv[2]

try:
    st = os.stat(cfg_path)
    with open(cfg_path, "r", encoding="utf-8") as f:
        content = f.read()

    sys_pattern = re.compile(r'<system\b[^>]*>.*?</system>', re.DOTALL)
    emu_pattern = re.compile(r'<emulator\b[^>]*name=["\']retroarch32["\'][^>]*>.*?</emulator>', re.DOTALL)
    cores_pattern = re.compile(r'<cores\b[^>]*>.*?</cores>', re.DOTALL)

    modified = False
    status = "not_found"

    def process_cores(cores_m):
        global modified, status
        c_block = cores_m.group(0)
        has_plus = re.search(r'<core>\s*gpsp_plus\s*</core>', c_block)

        if action == "install":
            if has_plus:
                status = "already_present"
                return c_block
            gpsp_m = re.search(r'([ \t]*)<core>\s*gpsp\s*</core>', c_block)
            if gpsp_m:
                indent = gpsp_m.group(1)
                replacement = f"{gpsp_m.group(0)}\n{indent}<core>gpsp_plus</core>"
                modified = True
                status = "installed"
                return c_block[:gpsp_m.start()] + replacement + c_block[gpsp_m.end():]
            else:
                any_core = re.search(r'([ \t]*)<core>', c_block)
                indent = any_core.group(1) if any_core else "\t\t\t\t\t"
                close_m = re.search(r'([ \t]*)</cores>', c_block)
                if close_m:
                    modified = True
                    status = "installed"
                    ins = f"{indent}<core>gpsp_plus</core>\n{close_m.group(0)}"
                    return c_block[:close_m.start()] + ins + c_block[close_m.end():]
            return c_block

        elif action == "uninstall":
            if not has_plus:
                status = "not_present"
                return c_block
            new_block, count = re.subn(r'[ \t]*<core>\s*gpsp_plus\s*</core>[ \t]*\r?\n?', '', c_block)
            if count > 0:
                modified = True
                status = "uninstalled"
            return new_block

        return c_block

    def process_emu(emu_m):
        return cores_pattern.sub(process_cores, emu_m.group(0), count=1)

    def process_system(sys_m):
        s_block = sys_m.group(0)
        if re.search(r'<name>\s*gba\s*</name>', s_block):
            return emu_pattern.sub(process_emu, s_block, count=1)
        return s_block

    new_content = sys_pattern.sub(process_system, content)

    if modified:
        # Removed ET.fromstring validation to prevent crashes on non-compliant es_systems.cfg (ArkOS)
        dir_name = os.path.dirname(cfg_path)
        fd, tmp_path = tempfile.mkstemp(dir=dir_name, prefix=".es_systems_")
        try:
            with os.fdopen(fd, "w", encoding="utf-8", newline="") as tf:
                tf.write(new_content)
            os.chmod(tmp_path, st.st_mode & 0o777)
            os.chown(tmp_path, st.st_uid, st.st_gid)
            os.replace(tmp_path, cfg_path)
        except Exception as file_ex:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
            raise file_ex

    print(status)
except Exception as e:
    print(f"Error executing python script: {str(e)}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

show_error() {
    local msg="$1"
    dialog --ascii-lines \
           --backtitle "$BACKTITLE" \
           --title " [ ERROR ] " \
           --msgbox "\n$msg" \
           13 "$BOX_W" > "$CURR_TTY" < "$CURR_TTY"
}

# ------------------------------------------------------------------------------
# 4. Menu Actions
# ------------------------------------------------------------------------------
do_install() {
    check_status

    if [ "$ST_SRC" != "OK" ]; then
        show_error "Could not find .so and .info files in:\n\n$SRC_DIR\n\nPlace 'gpsp_plus_libretro.so' and 'gpsp_plus_libretro.info' inside the 'gpsp_plus' subfolder and try again."
        return
    fi

    dialog --ascii-lines \
           --backtitle "$BACKTITLE" \
           --title " [ INSTALLING CORE ] " \
           --infobox "\nCopying core files to RetroArch 32-bit...\nTarget: retroarch32/cores\nPlease wait." \
           7 "$INFO_W" > "$CURR_TTY"
    sleep 1

    # Safe file copy operations
    mkdir -p "$CORES_DIR" || { show_error "Failed to create directory:\n$CORES_DIR"; return; }
    cp -f "$SRC_DIR"/*.so "$CORES_DIR/" || { show_error "Failed to copy .so core files."; return; }
    cp -f "$SRC_DIR"/*.info "$CORES_DIR/" || { show_error "Failed to copy .info core files."; return; }
    
    chmod 755 "$CORES_DIR"/*.so 2>/dev/null || true
    chmod 644 "$CORES_DIR"/*.info 2>/dev/null || true
    chown -R "$TARGET_USER:$TARGET_USER" "$CORES_DIR" 2>/dev/null || true

    dialog --ascii-lines \
           --backtitle "$BACKTITLE" \
           --title " [ UPDATING EMULATIONSTATION ] " \
           --infobox "\nAdding <core>gpsp_plus</core> under:\nGBA -> retroarch32 (es_systems.cfg)..." \
           6 "$INFO_W" > "$CURR_TTY"
    sleep 1

    # Capture output safely
    RESULT=$(edit_es_systems "install" 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -ne 0 ]; then
        show_error "Failed to update es_systems.cfg:\n\n$RESULT\n\nThe original file was preserved."
        return
    fi

    if dialog --ascii-lines \
              --backtitle "$BACKTITLE" \
              --title " [ INSTALLATION COMPLETE ] " \
              --yes-label "Restart ES" \
              --no-label "Back" \
              --yesno "\ngpSP+ core installed for RetroArch 32-bit!\n\n- Copied to retroarch32/cores\n- Added <core>gpsp_plus</core> to GBA\n\nRestart EmulationStation now to load the core?" \
              13 "$BOX_W" > "$CURR_TTY" < "$CURR_TTY"; then
        restart_es
    fi
}

do_uninstall() {
    if ! dialog --ascii-lines \
                --backtitle "$BACKTITLE" \
                --title " [ CONFIRM UNINSTALL ] " \
                --yes-label "Uninstall" \
                --no-label "Cancel" \
                --yesno "\nRemove gpSP+ core from RetroArch 32-bit?\n\nThis will:\n1. Delete gpsp_plus_libretro from retroarch32\n2. Remove <core>gpsp_plus</core> from es_systems.cfg" \
                12 "$BOX_W" > "$CURR_TTY" < "$CURR_TTY"; then
        return
    fi

    dialog --ascii-lines \
           --backtitle "$BACKTITLE" \
           --title " [ REMOVING CORE ] " \
           --infobox "\nRemoving RetroArch 32-bit core files and updating es_systems.cfg..." \
           6 "$INFO_W" > "$CURR_TTY"
    sleep 1

    # Clean removal
    rm -f "$CORES_DIR/gpsp_plus_libretro.so" "$CORES_DIR/gpsp_plus_libretro.info" || true
    
    RESULT=$(edit_es_systems "uninstall" 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -ne 0 ]; then
        show_error "Core files were removed, but an issue occurred while editing es_systems.cfg:\n\n$RESULT"
        return
    fi

    if dialog --ascii-lines \
              --backtitle "$BACKTITLE" \
              --title " [ UNINSTALL COMPLETE ] " \
              --yes-label "Restart ES" \
              --no-label "Back" \
              --yesno "\ngpSP+ core removed from RetroArch 32-bit!\n\nRestart EmulationStation now to refresh the core list?" \
              11 "$BOX_W" > "$CURR_TTY" < "$CURR_TTY"; then
        restart_es
    fi
}

show_details() {
    check_status
    SNIPPET="Block not found or file missing."
    if [ -f "$ES_CFG" ]; then
        SNIPPET_TXT=$(sudo python3 - "$ES_CFG" 2>/dev/null << 'PYEOF'
import re, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        text = f.read()
    for sys_m in re.finditer(r'<system\b[^>]*>.*?</system>', text, re.DOTALL):
        s_block = sys_m.group(0)
        if re.search(r'<name>\s*gba\s*</name>', s_block):
            emu_m = re.search(r'<emulator\b[^>]*name=["\']retroarch32["\'][^>]*>.*?</emulator>', s_block, re.DOTALL)
            if emu_m:
                print(emu_m.group(0).strip())
                break
except Exception:
    pass
PYEOF
        )
        [ -n "$SNIPPET_TXT" ] && SNIPPET="$SNIPPET_TXT"
    fi

    dialog --ascii-lines \
           --backtitle "$BACKTITLE" \
           --title " [ SYSTEM DIAGNOSTICS ] " \
           --msgbox "System : $OS_NAME (${FB_W}x${FB_H}, ${COLS}x${ROWS} cols)\nTarget : RetroArch 32-bit (retroarch32)\nSource : $SRC_DIR\nCores  : $CORES_DIR\nConfig : $ES_CFG\n\nCurrent block (GBA -> retroarch32):\n----------------------------------------\n$SNIPPET" \
           "$BOX_H" "$BOX_W" > "$CURR_TTY" < "$CURR_TTY"
}

restart_es() {
    dialog --ascii-lines \
           --backtitle "$BACKTITLE" \
           --title " [ RESTARTING ] " \
           --infobox "\nRestarting EmulationStation..." \
           5 "$INFO_W" > "$CURR_TTY"
    sleep 1
    
    # Graceful and forceful restart patterns used by ArkOS
    sudo systemctl restart emulationstation >/dev/null 2>&1 || killall emulationstation >/dev/null 2>&1 || true
    exit 0
}

confirm_exit() {
    if dialog --ascii-lines \
              --backtitle "$BACKTITLE" \
              --title " [ CONFIRM EXIT ] " \
              --yes-label "Yes, Exit" \
              --no-label "No, Return" \
              --defaultno \
              --yesno "\nAre you sure you want to exit the manager?" \
              7 "$BOX_W" > "$CURR_TTY" < "$CURR_TTY"; then
        return 0 # True - user wants to exit
    else
        return 1 # False - user pressed "No"
    fi
}

# ------------------------------------------------------------------------------
# 5. Main Interface Loop
# ------------------------------------------------------------------------------
setup_ui

while true; do
    check_status
    HEADER="$(build_header)"

    # Safely swap file descriptors to capture choice output if running outside pure TTY
    CHOICE=$(dialog --clear \
                    --no-collapse \
                    --ascii-lines \
                    --backtitle "$BACKTITLE" \
                    --title " [ MAIN MENU ] " \
                    --ok-label "Select" \
                    --cancel-label "Exit" \
                    --menu "$HEADER" \
                    "$BOX_H" "$BOX_W" 5 \
                    "1" "Install gpSP+ (RetroArch 32-bit)" \
                    "2" "Uninstall gpSP+ (RetroArch 32-bit)" \
                    "3" "View Status & es_systems.cfg" \
                    "4" "Restart EmulationStation" \
                    "5" "Exit" \
                    2>&1 > "$CURR_TTY" < "$CURR_TTY")

    RET=$?
    
    # Catch Cancel/Back button presses
    if [ $RET -ne 0 ]; then
        confirm_exit && break
        continue
    fi

    case "$CHOICE" in
        1) do_install ;;
        2) do_uninstall ;;
        3) show_details ;;
        4) restart_es ;;
        5) confirm_exit && break ;;
        *) break ;; # Safeguard
    esac
done

exit 0