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
    printf '>>> [%s] %s\n' "$1" "$2"
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
    log "系统" "正在检查运行环境"

    if command_exists unzip; then
        log "依赖" "已检测到 unzip"
        return
    fi

    if command_exists jar; then
        log "依赖" "未找到 unzip，改用 jar 作为解压后备方案"
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
                log "错误" "未找到 zip 文件参数"
                return 1
            fi

            jar xf "$zip_file"
        }
        export -f unzip
        return
    fi

    log "警告" "未找到 unzip 或 jar，后续解压可能失败"
}

load_custom_variables() {
    if [ -z "$CUSTOM_VARIABLES" ]; then
        return
    fi

    log "环境" "正在加载 CUSTOM_VARIABLES"
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
        log "端口" "未检测到容器端口，将继续使用模块默认端口"
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

    log "端口" "已检测到容器端口: $detected_port (来源: $detected_source)"
    log "端口" "已导出 SERVER_PORT/PORT/CONTAINER_PORT/INTERNAL_PORT"
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
    printf 'export %s=%s\n' "$name" "$escaped" >> "$ENV_FILE"
}

write_env_file() {
    local var_name=""

    printf '#!/usr/bin/env bash\n' > "$ENV_FILE" || return 1
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
        log "同步" "从 GitHub 刷新 $LOCAL_SCRIPT 失败"
        rm -f "$tmp_file"
        return 1
    fi

    mv "$tmp_file" "$LOCAL_SCRIPT"
    chmod +x "$LOCAL_SCRIPT"
    log "同步" "本地启动脚本已更新到 $LOCAL_SCRIPT"
    return 0
}

build_cron_line() {
    printf "@reboot /bin/bash -lc 'if [ -f \"%s\" ]; then . \"%s\"; fi; nohup /bin/bash \"%s\" >/dev/null 2>&1 &' # %s\n" \
        "$ENV_FILE" "$ENV_FILE" "$LOCAL_SCRIPT" "$AUTOSTART_MARKER"
}

install_autostart() {
    local current_cron=""
    local cron_line=""

    if ! command_exists crontab; then
        log "自启" "未找到 crontab，跳过开机自启设置"
        return
    fi

    current_cron="$(crontab -l 2>/dev/null || true)"
    cron_line="$(build_cron_line)"

    {
        printf '%s\n' "$current_cron" | grep -Fv "$AUTOSTART_MARKER" | grep -Fv "$LOCAL_SCRIPT" || true
        printf '%s' "$cron_line"
    } | crontab -

    if [ $? -eq 0 ]; then
        log "自启" "开机自启任务已刷新"
    else
        log "自启" "写入开机自启任务失败"
    fi
}

setup_persistence() {
    echo ""
    log "系统" "正在刷新本地脚本和持久化环境"

    sync_local_script || true

    if write_env_file; then
        log "环境" "当前环境已保存到 $ENV_FILE"
    else
        log "环境" "保存当前环境失败"
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
    if printf '%s' "$cmd_str" | grep -Eq -- '(^|[[:space:]])(-e[[:space:]]|--endpoint| -t[[:space:]]|--token)'; then
        return 1
    fi

    printf '%s' "$cmd_str" | grep -Eq 'NZ_SERVER[[:space:]]*=' && printf '%s' "$cmd_str" | grep -Eq 'NZ_CLIENT_SECRET[[:space:]]*='
}

normalize_komari_args() {
    local raw_cmd="$1"
    local args=""

    if printf '%s' "$raw_cmd" | grep -Eq '(sudo[[:space:]]+)?([^[:space:]]+/)?(bash|sh)[[:space:]]+-s[[:space:]]+--'; then
        args="$(printf '%s' "$raw_cmd" | sed -E 's/^.*(sudo[[:space:]]+)?([^[:space:]]+\/)?(bash|sh)[[:space:]]+-s[[:space:]]+--[[:space:]]*//')"
    elif printf '%s' "$raw_cmd" | grep -q 'install\.sh'; then
        args="$(printf '%s' "$raw_cmd" | sed -E 's/^.*install\.sh[[:space:]]*//')"
        if printf '%s' "$args" | grep -q '^[[:space:]]*|'; then
            args="$(printf '%s' "$args" | sed -E 's/^[[:space:]]*\|[[:space:]]*//')"
            args="$(printf '%s' "$args" | sed -E 's/^(sudo[[:space:]]+)?([^[:space:]]+\/)?(bash|sh)[[:space:]]+//')"
            args="$(printf '%s' "$args" | sed -E 's/^-s[[:space:]]+--[[:space:]]*//')"
        fi
    else
        args="$raw_cmd"
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

classify_probe_command() {
    local cmd_str="$1"

    if is_nezha_command "$cmd_str"; then
        printf 'nezha'
        return 0
    fi

    if is_komari_command "$cmd_str"; then
        printf 'komari'
        return 0
    fi

    return 1
}

collect_probe_commands() {
    local line=""
    local line_index=1
    local command_type=""

    echo "----------------------------------------------------"
    echo "                  双探针统一输入区                  "
    echo "----------------------------------------------------"
    echo "这里同时接收【哪吒】和【Komari】两种探针命令："
    echo "1. 哪吒：粘贴包含 NZ_SERVER / NZ_CLIENT_SECRET 的命令"
    echo "2. Komari：粘贴官方安装命令，或只贴 -e/--endpoint 与 -t/--token 参数"
    echo "3. 若命令里带 sudo / sh -s -- / bash -s --，脚本会自动忽略安装外壳"
    echo "4. 可以连续粘贴多行，脚本会逐行自动区分并分别接收"
    echo "5. 首行等待 ${TIMEOUT} 秒，后续空行或 1 秒无输入自动结束"
    echo "----------------------------------------------------"
    printf "请输入探针命令（哪吒 / Komari）> "

    if ! IFS= read -r -t "$TIMEOUT" line; then
        echo ""
        log "探针" "未输入任何新命令，将尝试使用预设或本地配置"
        return
    fi

    echo ""
    while true; do
        if [ -z "$line" ]; then
            break
        fi

        command_type="$(classify_probe_command "$line" 2>/dev/null || true)"

        if [ "$command_type" = "nezha" ]; then
            NEZHA_CMD_SOURCE="$line"
            log "探针" "第 ${line_index} 条已识别为【哪吒】命令"
        elif [ "$command_type" = "komari" ]; then
            KOMARI_CMD_SOURCE="$line"
            log "探针" "第 ${line_index} 条已识别为【Komari】命令"
        else
            log "探针" "第 ${line_index} 条未识别，已忽略。请粘贴【哪吒】环境变量命令或【Komari】安装命令"
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
        log "哪吒" "不支持当前架构: $(uname -m)"
        return 1
    fi

    url="https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch_code}.zip"
    log "哪吒" "正在下载哪吒探针 (${arch_code})"

    if ! download_file "$url" "$zip_file"; then
        log "哪吒" "下载哪吒探针失败"
        return 1
    fi

    if ! unzip -o "$zip_file" >/dev/null 2>&1; then
        log "哪吒" "解压哪吒探针失败"
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
            log "哪吒" "未找到新命令或本地配置，跳过启动"
            return
        fi

        if ! ensure_nezha_binary; then
            return
        fi

        log "哪吒" "正在使用本地 nezha.yml 启动"
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
        log "哪吒" "解析 NZ_SERVER 或 NZ_CLIENT_SECRET 失败，已跳过"
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

    log "哪吒" "已生成 $config_file"
    log "哪吒" "正在后台启动哪吒探针"
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
        log "Komari" "不支持当前架构: $(uname -m)"
        return 1
    fi

    url="https://github.com/komari-monitor/komari-agent/releases/latest/download/komari-agent-linux-${arch_code}"
    log "Komari" "正在下载 Komari 探针 (${arch_code})"

    if ! download_file "$url" "$bin_file"; then
        log "Komari" "下载 Komari 探针失败"
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
            log "Komari" "未找到新命令或本地参数，跳过启动"
            return
        fi

        final_args="$(cat "$args_file")"
        log "Komari" "正在使用本地 komari-agent.args 启动"
    else
        final_args="$(normalize_komari_args "$cmd_str")"
        endpoint="$(extract_komari_value "$final_args" "-e" "--endpoint")"
        token="$(extract_komari_value "$final_args" "-t" "--token")"

        if [ -z "$endpoint" ]; then
            log "Komari" "解析 --endpoint/-e 失败，已跳过"
            return
        fi

        if [ -z "$token" ] && ! printf '%s' "$final_args" | grep -q -- '--auto-discovery'; then
            log "Komari" "缺少 --token/-t，且未开启 --auto-discovery，已跳过"
            return
        fi

        printf '%s\n' "$final_args" > "$args_file"
        log "Komari" "参数已保存到 $args_file"
    fi

    if ! ensure_komari_binary; then
        return
    fi

    log "Komari" "正在后台启动 Komari 探针"
    sh -c "\"$PWD/$bin_file\" $final_args" &
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
    echo ">>> [主程序] 准备启动 Argosbx 业务"
    echo "===================================================="

    if [ ! -f "$ARGOS_SCRIPT_NAME" ]; then
        log "Argosbx" "未找到本地 argosbx.sh，正在下载"
        if ! download_file "$ARGOS_SCRIPT_URL" "$ARGOS_SCRIPT_NAME"; then
            log "Argosbx" "下载 argosbx.sh 失败"
            return 1
        fi
    fi

    chmod +x "$ARGOS_SCRIPT_NAME"
    log "Argosbx" "正在加载并运行 Argosbx，所有环境变量已自动继承"
    bash "$ARGOS_SCRIPT_NAME" "$argos_action"
}

show_probe_summary() {
    local nezha_file_exists="$1"
    local komari_file_exists="$2"

    echo "----------------------------------------------------"
    echo "                  双探针识别结果                    "
    echo "----------------------------------------------------"

    if [ -n "$NEZHA_CMD_SOURCE" ]; then
        log "哪吒" "已接收新的哪吒命令"
    elif [ -n "$PRESET_NEZHA_COMMAND" ]; then
        NEZHA_CMD_SOURCE="$PRESET_NEZHA_COMMAND"
        log "哪吒" "使用脚本预设配置"
    elif [ "$nezha_file_exists" = "true" ]; then
        log "哪吒" "使用本地 nezha.yml 配置"
    else
        log "哪吒" "未检测到可用配置，将跳过启动"
    fi

    if [ -n "$KOMARI_CMD_SOURCE" ]; then
        log "Komari" "已接收新的 Komari 命令"
    elif [ -n "$PRESET_KOMARI_COMMAND" ]; then
        KOMARI_CMD_SOURCE="$PRESET_KOMARI_COMMAND"
        log "Komari" "使用脚本预设配置"
    elif [ "$komari_file_exists" = "true" ]; then
        log "Komari" "使用本地 komari-agent.args 配置"
    else
        log "Komari" "未检测到可用配置，将跳过启动"
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
    log "初始化" "当前工作目录已切换到 $HOME"

    check_dependencies
    load_custom_variables
    detect_container_port
    setup_persistence

    NEZHA_CMD_SOURCE="${NZ_CMD:-}"
    KOMARI_CMD_SOURCE="${KOMARI_CMD:-}"
    argos_action="$(resolve_argos_action "$@")"

    if [ -n "$NEZHA_CMD_SOURCE" ]; then
        log "配置" "检测到环境变量 NZ_CMD，将优先使用哪吒命令"
    fi

    if [ -n "$KOMARI_CMD_SOURCE" ]; then
        log "配置" "检测到环境变量 KOMARI_CMD，将优先使用 Komari 命令"
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
    log "Argosbx" "已确定运行模式: $argos_action"

    start_nezha "$NEZHA_CMD_SOURCE"
    start_komari "$KOMARI_CMD_SOURCE"
    start_argosbx "$argos_action"

    echo ""
    log "保活" "正在启动后台保活进程"
    nohup sh -c 'while true; do sleep 3600; done' >/dev/null 2>&1 &

    log "完成" "所有任务已触发，脚本执行完毕"
}

main "$@"
