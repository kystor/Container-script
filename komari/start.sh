#!/usr/bin/env bash

# ==========================================
# 0. 基础依赖检查
# ==========================================
check_dependencies() {
    echo ">>> [系统] 正在检查运行环境..."
    export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    if command -v unzip >/dev/null 2>&1; then
        echo ">>> [依赖] 已检测到 unzip"
        return
    fi

    echo ">>> [依赖] 未检测到 unzip，尝试使用 Java jar 兜底"
    if command -v jar >/dev/null 2>&1; then
        unzip() {
            local zip_file=""
            local arg=""
            for arg in "$@"; do
                if [[ "$arg" == *.zip ]]; then
                    zip_file="$arg"
                    break
                fi
            done

            if [ -n "$zip_file" ]; then
                echo ">>> [依赖] 使用 jar 解压: $zip_file"
                jar xf "$zip_file"
            else
                echo ">>> [错误] 未找到 zip 文件参数，无法解压"
                return 1
            fi
        }
        export -f unzip
    else
        echo ">>> [警告] 未找到 unzip，也未找到 jar，后续解压可能失败"
    fi
}

check_dependencies

# ==========================================
# 1. 脚本配置
# ==========================================
PRESET_NEZHA_COMMAND=""
PRESET_KOMARI_COMMAND=""
CUSTOM_VARIABLES=''

SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh"
LOCAL_SCRIPT="$HOME/start.sh"
KOMARI_BINARY_NAME="komari-agent"

cd "$HOME" || exit 1
echo ">>> [初始化] 工作目录已切换到: $HOME"

if [ -n "$CUSTOM_VARIABLES" ]; then
    echo ">>> [环境] 正在加载自定义环境变量..."
    eval "export $CUSTOM_VARIABLES"
fi

is_valid_port() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ] && [ "$value" -le 65535 ]
}

detect_container_port() {
    local candidate_vars="SERVER_PORT PORT PANEL_PORT LISTEN_PORT APP_PORT WEB_PORT CONTAINER_PORT INTERNAL_PORT"
    local var_name=""
    local candidate=""
    local detected_port=""
    local detected_source=""

    for var_name in $candidate_vars; do
        candidate="$(eval "printf '%s' \"\${$var_name}\"")"
        if is_valid_port "$candidate"; then
            detected_port="$candidate"
            detected_source="$var_name"
            break
        fi
    done

    if [ -z "$detected_port" ]; then
        echo ">>> [端口] 未检测到容器平台分配端口，将继续使用各模块默认端口"
        return
    fi

    export CONTAINER_PORT="$detected_port"
    export PORT="${PORT:-$detected_port}"
    export SERVER_PORT="${SERVER_PORT:-$detected_port}"
    export INTERNAL_PORT="${INTERNAL_PORT:-$detected_port}"
    export PANEL_PORT="${PANEL_PORT:-$detected_port}"

    if [ -z "$hypt" ]; then
        export hypt="$detected_port"
    fi

    echo ">>> [端口] 已检测到容器端口: $detected_port (来源: $detected_source)"
    echo ">>> [端口] 已导出 SERVER_PORT/PORT/CONTAINER_PORT/INTERNAL_PORT"
}

detect_container_port

# ==========================================
# 2. 自安装与开机自启
# ==========================================
setup_persistence() {
    echo ""
    echo ">>> [系统] 正在检查脚本完整性与开机自启..."

    curl -L -s -o "$LOCAL_SCRIPT" "$SELF_URL"
    chmod +x "$LOCAL_SCRIPT"

    local cron_var_string=""
    if [ -n "$hypt" ]; then
        cron_var_string="export hypt=\"$hypt\";"
    fi

    local cron_cmd=""
    if [ -n "$CUSTOM_VARIABLES" ]; then
        cron_cmd="@reboot eval \"export $CUSTOM_VARIABLES\"; $cron_var_string /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    else
        cron_cmd="@reboot $cron_var_string /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    fi

    if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q "$LOCAL_SCRIPT"; then
        echo ">>> [自启] 已存在开机自启任务，跳过"
        return
    fi

    if command -v crontab >/dev/null 2>&1; then
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        if [ $? -eq 0 ]; then
            echo ">>> [自启] 已成功添加开机自启任务"
        else
            echo ">>> [自启] 添加开机自启任务失败"
        fi
    else
        echo ">>> [自启] 未找到 crontab，跳过开机自启设置"
    fi
}

get_arch_code() {
    local arch
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
    echo "$cmd_str" | grep -q 'NZ_SERVER=' && echo "$cmd_str" | grep -q 'NZ_CLIENT_SECRET='
}

is_komari_command() {
    local cmd_str="$1"
    local args=""
    local endpoint=""
    local token=""

    args="$(normalize_komari_args "$cmd_str")"
    endpoint="$(extract_komari_value "$args" "-e" "--endpoint")"
    token="$(extract_komari_value "$args" "-t" "--token")"

    if [ -n "$endpoint" ] && { [ -n "$token" ] || echo "$args" | grep -q -- '--auto-discovery'; }; then
        return 0
    fi
    return 1
}

collect_probe_commands() {
    local line=""
    local line_index=1

    echo "----------------------------------------------------"
    echo "                    探针配置中心                    "
    echo "----------------------------------------------------"
    echo "支持一次性粘贴多条命令，脚本会逐行自动识别："
    echo "1. 包含 NZ_SERVER / NZ_CLIENT_SECRET -> 识别为哪吒"
    echo "2. 包含 -e/--endpoint 和 -t/--token -> 识别为 Komari"
    echo "3. 两个都要可直接连续粘贴两行"
    echo "4. 首行等待 ${TIMEOUT} 秒，后续行空行或 1 秒无输入自动结束"
    echo "----------------------------------------------------"
    printf "请输入探针命令 > "

    if ! IFS= read -r -t "$TIMEOUT" line; then
        echo ""
        echo ">>> [探针] 未输入任何命令，将尝试使用预设或本地配置"
        return
    fi

    echo ""
    while true; do
        if [ -n "$line" ]; then
            if is_nezha_command "$line"; then
                NEZHA_CMD_SOURCE="$line"
                echo ">>> [探针] 第 ${line_index} 条已识别为哪吒命令"
            elif is_komari_command "$line"; then
                KOMARI_CMD_SOURCE="$line"
                echo ">>> [探针] 第 ${line_index} 条已识别为 Komari 命令"
            else
                echo ">>> [探针] 第 ${line_index} 条未识别，已忽略"
            fi
            line_index=$((line_index + 1))
        else
            break
        fi

        if ! IFS= read -r -t 1 line; then
            break
        fi
    done
}

# ==========================================
# 3. 哪吒探针
# ==========================================
start_nezha() {
    local cmd_str="$1"
    local bin_file="nezha-agent"
    local config_file="nezha.yml"
    local server=""
    local secret=""
    local tls=""
    local arch_code=""

    if [ -z "$cmd_str" ]; then
        if [ -f "$config_file" ]; then
            echo ">>> [哪吒] 检测到本地配置，直接启动 Nezha Agent..."
            "./$bin_file" -c "$config_file" &
        else
            echo ">>> [哪吒] 未提供命令且无本地配置，跳过启动"
        fi
        return
    fi

    echo ""
    echo ">>> [哪吒] 正在解析命令并更新配置..."

    server="$(echo "$cmd_str" | grep -o 'NZ_SERVER=[^ ]*' | head -n 1 | cut -d= -f2 | sed 's/["'\'']//g')"
    secret="$(echo "$cmd_str" | grep -o 'NZ_CLIENT_SECRET=[^ ]*' | head -n 1 | cut -d= -f2 | sed 's/["'\'']//g')"
    tls="$(echo "$cmd_str" | grep -o 'NZ_TLS=[^ ]*' | head -n 1 | cut -d= -f2 | sed 's/["'\'']//g')"

    if [ -z "$tls" ]; then
        tls="false"
    fi

    if [ -z "$server" ] || [ -z "$secret" ]; then
        echo ">>> [哪吒] 无法解析 NZ_SERVER 或 NZ_CLIENT_SECRET，请检查输入命令"
        return
    fi

    arch_code="$(get_arch_code)"
    if [ -z "$arch_code" ]; then
        echo ">>> [哪吒] 不支持当前架构: $(uname -m)"
        return
    fi

    if [ ! -f "$bin_file" ]; then
        echo ">>> [哪吒] 正在下载探针 (${arch_code})..."
        curl -L -o nezha.zip "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch_code}.zip"
        unzip -o nezha.zip
        chmod +x "$bin_file"
        rm -f nezha.zip
    fi

    cat > "$config_file" <<EOF
server: $server
client_secret: $secret
tls: $tls
EOF

    echo ">>> [哪吒] 已生成配置文件: $config_file"
    echo ">>> [哪吒] 正在启动 Nezha Agent..."
    "./$bin_file" -c "$config_file" &
}

# ==========================================
# 4. Komari 探针
# ==========================================
normalize_komari_args() {
    local raw_cmd="$1"
    local args="$raw_cmd"

    if echo "$raw_cmd" | grep -q 'bash -s --'; then
        args="$(echo "$raw_cmd" | sed 's/.*bash -s --[[:space:]]*//')"
    elif echo "$raw_cmd" | grep -q 'install\.sh'; then
        args="$(echo "$raw_cmd" | sed 's/.*install\.sh[[:space:]]*//')"
    fi

    echo "$args" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

extract_komari_value() {
    local args="$1"
    local short_key="$2"
    local long_key="$3"
    local value=""

    value="$(echo "$args" | sed -n "s/.*${long_key}[= ][[:space:]]*\\([^ ]*\\).*/\\1/p" | head -n 1 | sed "s/[\"']//g")"
    if [ -z "$value" ]; then
        value="$(echo "$args" | sed -n "s/.*${short_key}[[:space:]]\\([^ ]*\\).*/\\1/p" | head -n 1 | sed "s/[\"']//g")"
    fi

    echo "$value"
}

start_komari() {
    local cmd_str="$1"
    local args_file="komari-agent.args"
    local bin_file="$KOMARI_BINARY_NAME"
    local final_args=""
    local endpoint=""
    local token=""
    local arch_code=""
    local download_url=""

    if [ -z "$cmd_str" ]; then
        if [ -f "$args_file" ]; then
            final_args="$(cat "$args_file")"
            echo ">>> [Komari] 检测到本地配置，准备按已保存参数安装/启动"
        else
            echo ">>> [Komari] 未提供命令且无本地配置，跳过启动"
            return
        fi
    else
        final_args="$(normalize_komari_args "$cmd_str")"
        endpoint="$(extract_komari_value "$final_args" "-e" "--endpoint")"
        token="$(extract_komari_value "$final_args" "-t" "--token")"

        if [ -z "$endpoint" ]; then
            echo ">>> [Komari] 无法解析 --endpoint/-e，请检查命令"
            return
        fi

        if [ -z "$token" ] && ! echo "$final_args" | grep -q -- '--auto-discovery'; then
            echo ">>> [Komari] 缺少 --token/-t，或未提供 --auto-discovery"
            return
        fi

        printf '%s\n' "$final_args" > "$args_file"
        echo ">>> [Komari] 已保存参数到: $args_file"
    fi

    arch_code="$(get_arch_code)"
    if [ -z "$arch_code" ]; then
        echo ">>> [Komari] 不支持当前架构: $(uname -m)"
        return
    fi

    download_url="https://github.com/komari-monitor/komari-agent/releases/latest/download/komari-agent-linux-${arch_code}"

    if [ ! -f "$bin_file" ]; then
        echo ">>> [Komari] 正在下载 Komari Agent (${arch_code})..."
        if ! curl -fL -o "$bin_file" "$download_url"; then
            echo ">>> [Komari] 下载 Komari Agent 失败"
            return
        fi
        chmod +x "$bin_file"
    fi

    echo ">>> [Komari] 正在后台启动 Komari Agent..."
    sh -c "\"$PWD/$bin_file\" $final_args" &
}

# ==========================================
# 5. Argosbx 主业务
# ==========================================
start_argosbx() {
    echo ""
    echo "===================================================="
    echo ">>> [主程序] 准备启动 Argosbx 业务"
    echo "===================================================="

    echo ">>> [透传] 正在加载并运行 Argosbx，所有环境变量将自动继承..."

    local script_name="argosbx.sh"
    local script_url="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

    if [ ! -f "$script_name" ]; then
        echo ">>> [下载] 本地未找到 Argosbx，正在下载..."
        curl -L -o "$script_name" "$script_url"
        chmod +x "$script_name"
    fi

    echo ">>> [执行] 正在运行 Argosbx (模式: rep)..."
    bash "$script_name" rep
}

# ==========================================
# 6. 脚本入口
# ==========================================
clear
echo "===================================================="
echo "                  Container-Script                  "
echo "===================================================="

setup_persistence

TIMEOUT=20
NEZHA_CMD_SOURCE=""
KOMARI_CMD_SOURCE=""

if [ -n "$NZ_CMD" ]; then
    echo ">>> [配置] 检测到外部传入的哪吒命令 (NZ_CMD)，将优先使用"
    NEZHA_CMD_SOURCE="$NZ_CMD"
fi

if [ -n "$KOMARI_CMD" ]; then
    echo ">>> [配置] 检测到外部传入的 Komari 命令 (KOMARI_CMD)，将优先使用"
    KOMARI_CMD_SOURCE="$KOMARI_CMD"
fi

if [ -f "nezha.yml" ]; then
    echo ">>> [备份] 检测到本地哪吒配置 nezha.yml"
    NEZHA_FILE_EXISTS=true
else
    NEZHA_FILE_EXISTS=false
fi

if [ -f "komari-agent.args" ]; then
    echo ">>> [备份] 检测到本地 Komari 配置 komari-agent.args"
    KOMARI_FILE_EXISTS=true
else
    KOMARI_FILE_EXISTS=false
fi

if [ -z "$NZ_CMD" ] && [ -z "$KOMARI_CMD" ]; then
    collect_probe_commands
fi

echo "----------------------------------------------------"
echo "                    探针配置结果                    "
echo "----------------------------------------------------"

if [ -n "$NEZHA_CMD_SOURCE" ]; then
    echo ">>> [哪吒] 使用已识别到的新命令"
elif [ -n "$PRESET_NEZHA_COMMAND" ]; then
    NEZHA_CMD_SOURCE="$PRESET_NEZHA_COMMAND"
    echo ">>> [哪吒] 使用脚本预设配置"
elif [ "$NEZHA_FILE_EXISTS" = true ]; then
    echo ">>> [哪吒] 使用本地已有配置启动"
else
    echo ">>> [哪吒] 未检测到任何可用配置，将跳过启动"
fi

if [ -n "$KOMARI_CMD_SOURCE" ]; then
    echo ">>> [Komari] 使用已识别到的新命令"
elif [ -n "$PRESET_KOMARI_COMMAND" ]; then
    KOMARI_CMD_SOURCE="$PRESET_KOMARI_COMMAND"
    echo ">>> [Komari] 使用脚本预设配置"
elif [ "$KOMARI_FILE_EXISTS" = true ]; then
    echo ">>> [Komari] 使用本地已有配置启动"
else
    echo ">>> [Komari] 未检测到任何可用配置，将跳过启动"
fi

start_nezha "$NEZHA_CMD_SOURCE"
start_komari "$KOMARI_CMD_SOURCE"
start_argosbx

echo ""
echo ">>> [保活] 正在启动后台保活进程 (Keep-Alive)..."
nohup sh -c 'while true; do sleep 3600; done' >/dev/null 2>&1 &

echo ">>> [完成] 所有任务已触发，脚本执行完毕"
