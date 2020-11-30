#!/usr/bin/env bash

umask "${YO_UMASK:-077}"
set -o pipefail
set -e

# Defaults to ~/.config
TOP_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"

# Defaults to ~/.config/yo
YO_CONFIG_DIR="${YO_CONFIG_DIR:-$TOP_CONFIG_DIR/yo}"
mkdir -p "$YO_CONFIG_DIR"

# Defaults to ~/.config/token
YO_TOKEN_PATH="${YO_TOKEN_PATH:-$YO_CONFIG_DIR/token}"

YO_BASE_URL="${YO_BASE_URL:-https://api.yocli.io}"

text_display_qr() {
    if (( 22 < "$(tput lines)" )); then
        echo -n "$1" | qrencode -t utf8
    else
        echo "Your terminal is too small to display the pairing QR Code properly."
        echo "try making it larger and invoking \`yo\` again!"
        exit 1
    fi
}

display_qr() {
    local title="yo"
    if [[ -n $DISPLAY || -n $WAYLAND_DISPLAY ]]; then
        if type feh >/dev/null 2>&1; then
            echo -n "$1" | qrencode --size 10 -o - | feh -x --title "$title" -g +200+200 - &
        elif type gm >/dev/null 2>&1; then
            echo -n "$1" | qrencode --size 10 -o - | gm display -title "$title" -geometry +200+200 - &
        elif type display >/dev/null 2>&1; then
            echo -n "$1" | qrencode --size 10 -o - | display -title "$title" -geometry +200+200 - &
        else
            text_display_qr "$1"
        fi
    else
        text_display_qr "$1"
    fi
}

yo() {
    curl --silent -o /dev/null -w '%{http_code}' \
         -X POST -F pc_token="$(< "$YO_TOKEN_PATH")" \
         -L "${YO_BASE_URL}/yo" 2>/dev/null
}

yo_repeatedly() {
    for (( i=0; "$i"<"${3:-256}"; i++ )); do
        local status
        status="$(yo)"
        if (("$status"<"${1}" || "${2}"<="$status" )); then
            break
        fi
        if [ -n "$!" ] && ! ps -p "$!" >/dev/null; then
            echo "Aborted." >&2
            exit 1
        fi
        sleep 1
    done
    echo "$status"
}

new_token() {
    local yo_token
    yo_token="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    echo "$yo_token" > "$YO_TOKEN_PATH"
    echo "$yo_token"
}

link_w_qr() {
    display_qr "${YO_BASE_URL}/?p=${1}"
    local status
    status="$(yo_repeatedly 400 500)"
    [ -n "$!" ] && kill $!
    if ((500 <= "$status" && "$status" < 600)); then
        echo "It seems that the yo backend at '$YO_BASE_URL' is down right now, please try again later."
    else
        echo "Sucessfully linked a mobile device!"
    fi
}

source "$(dirname "$0")/platform/$(uname | cut -d _ -f 1 | tr '[:upper:]' '[:lower:]').sh" 2>/dev/null # PLATFORM_FUNCTION_FILE

if [ ! -f "$YO_TOKEN_PATH" ]; then
    echo "No mobile device linked. Let's fix that :-)"
    link_w_qr "$(new_token)"
else
    status="$(yo_repeatedly 500 600 5)"
    if [ "$status" -ne 204 ]; then
        if [ "$status" -eq 404 ]; then
            echo "No mobile device linked. Let's fix that :-)"
            link_w_qr "$(new_token)"
        elif ((500 <= "$status" && "$status" < 600)); then
            echo "It seems that the yo backend at '$YO_BASE_URL' is down right now, please try again later."
        else
            echo "Unknown error."
        fi
    fi
fi
