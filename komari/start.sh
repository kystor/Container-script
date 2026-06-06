#!/usr/bin/env bash

export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

PRESET_NEZHA_COMMAND="${PRESET_NEZHA_COMMAND:-}"
PRESET_KOMARI_COMMAND="${PRESET_KOMARI_COMMAND:-}"
CUSTOM_VARIABLES="${CUSTOM_VARIABLES:-}"

SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh"
LOCAL_SCRIPT="$HOME/start.sh"
ENV_FILE="$HOME/.container-script.env"
AUTOSTART_MARKER="container-script-autostart"
KOMARI_BINARY_NAME="komari-agent"
ARGOS_SCRIPT_NAME="argosbx.sh"
ARGOS_SCRIPT_URL="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"
TIMEOUT="${TIMEOUT:-20}"

ARGOS_ENV_VARS=(
    vlpt vmpt vwpt hypt tupt xhpt vxpt anpt sspt arpt sopt
    warp uuid reym cdnym argo agn agk ippz name oap
)

PORT_ENV_VARS=(
    SERVER_PORT PORT PANEL_PORT LISTEN_PORT APP_PORT WEB_PORT
    CONTAINER_PORT INTERNAL_PORT
)

log() {
    printf '>>> [%s] %s
' "$1" "$2"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

download_file() {
    local url="$1"
    local output="$2"

    if command_exists curl; then
        curl -fsSL "$url" -o "$output"
        return $?
    fi

    if command_exists wget; then
        wget -qO "$output" "$url"
        return $?
    fi

    log "ERROR" "curl or wget is required to download files"
    return 1
}

check_dependencies() {
    log "SYSTEM" "Checking runtime environment"

    if command_exists unzip; then
        log "DEPS" "unzip detected"
        return
    fi

    if command_exists jar; then
        log "DEPS" "unzip not found, using jar as fallback"
        unzip() {
            local zip_file=""
            local arg=""

            for arg in "$@"; do
                if [[ "$arg" == *.zip ]]; then
                    zip_file="$arg"
                    break
                fi
            done

            if [ -z "$zip_file" ]; then
                log "ERROR" "zip file argument not found"
                return 1
            fi

            jar xf "$zip_file"
        }
        export -f unzip
        return
    fi

    log "WARN" "Neither unzip nor jar was found; archive extraction may fail"
}

load_custom_variables() {
    if [ -z "$CUSTOM_VARIABLES" ]; then
        return
    fi

    log "ENV" "Loading CUSTOM_VARIABLES"
    eval "export $CUSTOM_VARIABLES"
}

is_valid_port() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ]
}

detect_container_port() {
    local var_name=""
    local candidate=""
    local detected_port=""
    local detected_source=""

    for var_name in "${PORT_ENV_VARS[@]}"; do
        candidate="${!var_name-}"
        if is_valid_port "$candidate"; then
            detected_port="$candidate"
            detected_source="$var_name"
            break
        fi
    done

    if [ -z "$detected_port" ]; then
        log "PORT" "No container port detected, keeping module defaults"
        return
    fi

    export CONTAINER_PORT="$detected_port"
    export PORT="${PORT:-$detected_port}"
    export SERVER_PORT="${SERVER_PORT:-$detected_port}"
    export INTERNAL_PORT="${INTERNAL_PORT:-$detected_port}"
    export PANEL_PORT="${PANEL_PORT:-$detected_port}"

    if [ -z "${hypt:-}" ]; then
        export hypt="$detected_port"
    fi

    log "PORT" "Detected container port: $detected_port (source: $detected_source)"
    log "PORT" "Exported SERVER_PORT/PORT/CONTAINER_PORT/INTERNAL_PORT"
}

append_export_var() {
    local name="$1"
    local value=""
    local escaped=""

    if [ -z "${!name+x}" ]; then
        return
    fi

    value="${!name}"
    printf -v escaped '%q' "$value"
    printf 'export %s=%s
' "$name" "$escaped" >> "$ENV_FILE"
}

write_env_file() {
    local var_name=""

    printf '#!/usr/bin/env bash
' > "$ENV_FILE" || return 1
    chmod 600 "$ENV_FILE" 2>/dev/null || true

    for var_name in "${PORT_ENV_VARS[@]}"; do
        append_export_var "$var_name"
    done

    for var_name in "${ARGOS_ENV_VARS[@]}"; do
        append_export_var "$var_name"
    done

    append_export_var "NZ_CMD"
    append_export_var "KOMARI_CMD"
    append_export_var "CUSTOM_VARIABLES"

    return 0
}

sync_local_script() {
    local tmp_file="${LOCAL_SCRIPT}.tmp"

    if ! download_file "$SELF_URL" "$tmp_file"; then
        log "SYNC" "Failed to refresh $LOCAL_SCRIPT from GitHub"
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$LOCAL_SCRIPT"
    chmod +x "$LOCAL_SCRIPT"
    log "SYNC" "Local startup script refreshed at $LOCAL_SCRIPT"
    return 0
}

build_cron_line() {
    printf "@reboot /bin/bash -lc 'if [ -f "%s" ]; then . "%s"; fi; nohup /bin/bash "%s" >/dev/null 2>&1 &' # %s
"         "$ENV_FILE" "$ENV_FILE" "$LOCAL_SCRIPT" "$AUTOSTART_MARKER"
}

install_autostart() {
    local current_cron=""
    local cron_line=""

    if ! command_exists crontab; then
        log "AUTOSTART" "crontab not found, skipping reboot persistence"
        return
    fi

    current_cron="$(crontab -l 2>/dev/null || true)"
    cron_line="$(build_cron_line)"

    {
        printf '%s
' "$current_cron" | grep -Fv "$AUTOSTART_MARKER" | grep -Fv "$LOCAL_SCRIPT" || true
        printf '%s' "$cron_line"
    } | crontab -

    if [ $? -eq 0 ]; then
        log "AUTOSTART" "Reboot task refreshed"
    else
        log "AUTOSTART" "Failed to write reboot task"
    fi
}

setup_persistence() {
    echo ""
    log "SYSTEM" "Refreshing local script and persisted environment"

    sync_local_script || true

    if write_env_file; then
        log "ENV" "Saved current environment to $ENV_FILE"
    else
        log "ENV" "Failed to save current environment"
    fi

    install_autostart
}

get_arch_code() {
    local arch=""
    arch="$(uname -m)"

    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*|armv6*) echo "arm" ;;
        i386|i686) echo "386" ;;
        *) echo "" ;;
    esac
}

is_nezha_command() {
    local cmd_str="$1"
    printf '%s' "$cmd_str" | grep -q 'NZ_SERVER=' && printf '%s' "$cmd_str" | grep -q 'NZ_CLIENT_SECRET='
}

normalize_komari_args() {
    local raw_cmd="$1"
    local args="$raw_cmd"

    if printf '%s' "$raw_cmd" | grep -q 'bash -s --'; then
        args="$(printf '%s' "$raw_cmd" | sed 's/.*bash -s --[[:space:]]*//')"
    elif printf '%s' "$raw_cmd" | grep -q 'install\.sh'; then
        args="$(printf '%s' "$raw_cmd" | sed 's/.*install\.sh[[:space:]]*//')"
    fi

    printf '%s' "$args" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

extract_komari_value() {
    local args="$1"
    local short_key="$2"
    local long_key="$3"
    local value=""

    value="$(printf '%s' "$args" | sed -n "s/.*${long_key}[= ][[:space:]]*\([^ ]*\).*/\1/p" | head -n 1 | sed "s/["']//g")"
    if [ -z "$value" ]; then
        value="$(printf '%s' "$args" | sed -n "s/.*${short_key}[[:space:]]\([^ ]*\).*/\1/p" | head -n 1 | sed "s/["']//g")"
    fi

    printf '%s' "$value"
}

is_komari_command() {
    local cmd_str="$1"
    local args=""
    local endpoint=""
    local token=""

    args="$(normalize_komari_args "$cmd_str")"
    endpoint="$(extract_komari_value "$args" "-e" "--endpoint")"
    token="$(extract_komari_value "$args" "-t" "--token")"

    if [ -n "$endpoint" ] && { [ -n "$token" ] || printf '%s' "$args" | grep -q -- '--auto-discovery'; }; then
        return 0
    fi

    return 1
}

collect_probe_commands() {
    local line=""
    local line_index=1

    echo "----------------------------------------------------"
    echo "                 Probe Config Center                "
    echo "----------------------------------------------------"
    echo "Paste one or more probe commands."
    echo "1. NZ_SERVER + NZ_CLIENT_SECRET => Nezha"
    echo "2. -e/--endpoint + -t/--token => Komari"
    echo "3. Collection stops on blank line or 1 second idle"
    echo "----------------------------------------------------"
    printf "Enter probe command> "

    if ! IFS= read -r -t "$TIMEOUT" line; then
        echo ""
        log "PROBE" "No new probe command received; using preset or local config"
        return
    fi

    echo ""
    while true; do
        if [ -z "$line" ]; then
            break
        fi

        if is_nezha_command "$line"; then
            NEZHA_CMD_SOURCE="$line"
            log "PROBE" "Line ${line_index} detected as Nezha"
        elif is_komari_command "$line"; then
            KOMARI_CMD_SOURCE="$line"
            log "PROBE" "Line ${line_index} detected as Komari"
        else
            log "PROBE" "Line ${line_index} not recognized and was ignored"
        fi

        line_index=$((line_index + 1))

        if ! IFS= read -r -t 1 line; then
            break
        fi
    done
}

extract_assignment_value() {
    local cmd_str="$1"
    local key="$2"

    printf '%s' "$cmd_str" | grep -o "${key}=[^ ]*" | head -n 1 | cut -d= -f2 | sed "s/["']//g"
}

ensure_nezha_binary() {
    local bin_file="nezha-agent"
    local arch_code=""
    local zip_file="nezha.zip"
    local url=""

    if [ -f "$bin_file" ]; then
        chmod +x "$bin_file"
        return 0
    fi

    arch_code="$(get_arch_code)"
    if [ -z "$arch_code" ]; then
        log "NEZHA" "Unsupported architecture: $(uname -m)"
        return 1
    fi

    url="https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch_code}.zip"
    log "NEZHA" "Downloading nezha-agent (${arch_code})"

    if ! download_file "$url" "$zip_file"; then
        log "NEZHA" "Failed to download nezha-agent"
        return 1
    fi

    if ! unzip -o "$zip_file" >/dev/null 2>&1; then
        log "NEZHA" "Failed to extract nezha-agent"
        rm -f "$zip_file"
        return 1
    fi

    rm -f "$zip_file"
    chmod +x "$bin_file"
    return 0
}

start_nezha() {
    local cmd_str="$1"
    local bin_file="nezha-agent"
    local config_file="nezha.yml"
    local server=""
    local secret=""
    local tls=""

    if [ -z "$cmd_str" ]; then
        if [ ! -f "$config_file" ]; then
            log "NEZHA" "No command or local config found; skipping"
            return
        fi

        if ! ensure_nezha_binary; then
            return
        fi

        log "NEZHA" "Starting from existing local config"
        "./$bin_file" -c "$config_file" &
        return
    fi

    server="$(extract_assignment_value "$cmd_str" "NZ_SERVER")"
    secret="$(extract_assignment_value "$cmd_str" "NZ_CLIENT_SECRET")"
    tls="$(extract_assignment_value "$cmd_str" "NZ_TLS")"

    if [ -z "$tls" ]; then
        tls="false"
    fi

    if [ -z "$server" ] || [ -z "$secret" ]; then
        log "NEZHA" "Failed to parse NZ_SERVER or NZ_CLIENT_SECRET; skipping"
        return
    fi

    if ! ensure_nezha_binary; then
        return
    fi

    cat > "$config_file" <<EOF
server: $server
client_secret: $secret
tls: $tls
EOF

    log "NEZHA" "Generated $config_file"
    log "NEZHA" "Starting nezha-agent in background"
    "./$bin_file" -c "$config_file" &
}

ensure_komari_binary() {
    local bin_file="$KOMARI_BINARY_NAME"
    local arch_code=""
    local url=""

    if [ -f "$bin_file" ]; then
        chmod +x "$bin_file"
        return 0
    fi

    arch_code="$(get_arch_code)"
    if [ -z "$arch_code" ]; then
        log "KOMARI" "Unsupported architecture: $(uname -m)"
        return 1
    fi

    url="https://github.com/komari-monitor/komari-agent/releases/latest/download/komari-agent-linux-${arch_code}"
    log "KOMARI" "Downloading Komari Agent (${arch_code})"

    if ! download_file "$url" "$bin_file"; then
        log "KOMARI" "Failed to download Komari Agent"
        return 1
    fi

    chmod +x "$bin_file"
    return 0
}

start_komari() {
    local cmd_str="$1"
    local args_file="komari-agent.args"
    local bin_file="$KOMARI_BINARY_NAME"
    local final_args=""
    local endpoint=""
    local token=""

    if [ -z "$cmd_str" ]; then
        if [ ! -f "$args_file" ]; then
            log "KOMARI" "No command or local args found; skipping"
            return
        fi

        final_args="$(cat "$args_file")"
        log "KOMARI" "Starting from existing local args file"
    else
        final_args="$(normalize_komari_args "$cmd_str")"
        endpoint="$(extract_komari_value "$final_args" "-e" "--endpoint")"
        token="$(extract_komari_value "$final_args" "-t" "--token")"

        if [ -z "$endpoint" ]; then
            log "KOMARI" "Failed to parse --endpoint/-e; skipping"
            return
        fi

        if [ -z "$token" ] && ! printf '%s' "$final_args" | grep -q -- '--auto-discovery'; then
            log "KOMARI" "Missing --token/-t and --auto-discovery; skipping"
            return
        fi

        printf '%s
' "$final_args" > "$args_file"
        log "KOMARI" "Saved args to $args_file"
    fi

    if ! ensure_komari_binary; then
        return
    fi

    log "KOMARI" "Starting Komari Agent in background"
    sh -c ""$PWD/$bin_file" $final_args" &
}

resolve_argos_action() {
    if [ "$#" -gt 0 ] && [ -n "$1" ]; then
        printf '%s' "$1"
        return
    fi

    printf 'rep'
}

start_argosbx() {
    local argos_action="$1"

    echo ""
    echo "===================================================="
    echo ">>> [ARGOSBX] Starting main workload"
    echo "===================================================="

    if [ ! -f "$ARGOS_SCRIPT_NAME" ]; then
        log "ARGOSBX" "Local argosbx.sh not found, downloading"
        if ! download_file "$ARGOS_SCRIPT_URL" "$ARGOS_SCRIPT_NAME"; then
            log "ARGOSBX" "Failed to download argosbx.sh"
            return 1
        fi
    fi

    chmod +x "$ARGOS_SCRIPT_NAME"
    log "ARGOSBX" "Running bash $ARGOS_SCRIPT_NAME $argos_action with inherited environment"
    bash "$ARGOS_SCRIPT_NAME" "$argos_action"
}

show_probe_summary() {
    local nezha_file_exists="$1"
    local komari_file_exists="$2"

    echo "----------------------------------------------------"
    echo "                 Probe Config Result                "
    echo "----------------------------------------------------"

    if [ -n "$NEZHA_CMD_SOURCE" ]; then
        log "NEZHA" "Using newly detected command"
    elif [ -n "$PRESET_NEZHA_COMMAND" ]; then
        NEZHA_CMD_SOURCE="$PRESET_NEZHA_COMMAND"
        log "NEZHA" "Using preset command"
    elif [ "$nezha_file_exists" = "true" ]; then
        log "NEZHA" "Using existing local config"
    else
        log "NEZHA" "No usable config found; skipping"
    fi

    if [ -n "$KOMARI_CMD_SOURCE" ]; then
        log "KOMARI" "Using newly detected command"
    elif [ -n "$PRESET_KOMARI_COMMAND" ]; then
        KOMARI_CMD_SOURCE="$PRESET_KOMARI_COMMAND"
        log "KOMARI" "Using preset command"
    elif [ "$komari_file_exists" = "true" ]; then
        log "KOMARI" "Using existing local args"
    else
        log "KOMARI" "No usable config found; skipping"
    fi
}

main() {
    local nezha_file_exists="false"
    local komari_file_exists="false"
    local argos_action=""

    clear 2>/dev/null || true
    echo "===================================================="
    echo "                  Container-Script                  "
    echo "===================================================="

    cd "$HOME" || exit 1
    log "INIT" "Working directory switched to $HOME"

    check_dependencies
    load_custom_variables
    detect_container_port
    setup_persistence

    NEZHA_CMD_SOURCE="${NZ_CMD:-}"
    KOMARI_CMD_SOURCE="${KOMARI_CMD:-}"
    argos_action="$(resolve_argos_action "$@")"

    if [ -n "$NEZHA_CMD_SOURCE" ]; then
        log "CONFIG" "Detected external Nezha command from NZ_CMD"
    fi

    if [ -n "$KOMARI_CMD_SOURCE" ]; then
        log "CONFIG" "Detected external Komari command from KOMARI_CMD"
    fi

    if [ -f "nezha.yml" ]; then
        nezha_file_exists="true"
    fi

    if [ -f "komari-agent.args" ]; then
        komari_file_exists="true"
    fi

    if [ -z "$NEZHA_CMD_SOURCE" ] && [ -z "$KOMARI_CMD_SOURCE" ] && [ -t 0 ]; then
        collect_probe_commands
    fi

    show_probe_summary "$nezha_file_exists" "$komari_file_exists"
    log "ARGOSBX" "Resolved action: $argos_action"

    start_nezha "$NEZHA_CMD_SOURCE"
    start_komari "$KOMARI_CMD_SOURCE"
    start_argosbx "$argos_action"

    echo ""
    log "KEEPALIVE" "Starting keepalive process"
    nohup sh -c 'while true; do sleep 3600; done' >/dev/null 2>&1 &

    log "DONE" "All tasks were triggered"
}

main "$@"
