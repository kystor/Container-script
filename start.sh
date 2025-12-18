#!/bin/bash

# ==========================================
# 🟢 模块 0：环境自检 (保持你的精简版配置)
# ==========================================
check_dependencies() {
    # [优化] 这里的输出符合你的要求，保持简洁，不输出繁杂的系统检查日志
    echo ">>> [系统] 正在检查环境依赖..."

    export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    # 检测 unzip
    if ! command -v unzip >/dev/null 2>&1; then
        echo ">>> [依赖] 系统未安装 unzip。"
        
        # Java (jar) 兜底策略
        if command -v jar >/dev/null 2>&1; then
            echo ">>> [依赖] ✅ 检测到 Java，将使用 jar 命令代替 unzip。"
            
            # [注解] 定义函数拦截 unzip 命令，利用 jar 解压
            function unzip() {
                local zip_file=""
                for arg in "$@"; do
                    if [[ "$arg" == *.zip ]]; then zip_file="$arg"; break; fi
                done
                
                if [ -n "$zip_file" ]; then
                    echo " -> [Java] 正在使用 jar 解压: $zip_file"
                    jar xf "$zip_file"
                else
                    echo " -> [错误] Java 模式未找到 zip 文件参数。"
                fi
            }
            export -f unzip 
        else
            echo ">>> [警告] ❌ 未找到 unzip 且未找到 Java，后续解压步骤可能失败！"
            echo ">>> [提示] 如果报错，请在容器外部手动安装 unzip。"
        fi
    else
        echo ">>> [依赖] ✅ 系统已有 unzip。"
    fi
}

check_dependencies

# ==========================================
# 🟢 脚本说明与配置区
# ==========================================
# [更新记录]
# 2025-12-18: 支持外部环境变量注入 (a="1" bash ...)，智能跳过等待时间。

# 🟢 【配置 1】：哪吒指令预设区 (优先级 No.2)
# 如果外部有传入 NZ_CMD 变量，也可以在这里被识别
PRESET_NEZHA_COMMAND=""

# 🟢 【配置 2】：自定义环境变量
# [重要修改] 这里去掉了 'hypt=""' 的硬编码。
# 原因：如果你在命令行用了 hypt="123" bash ...，这里的 hypt="" 会把你的输入覆盖为空。
# 改为保留为空，或者只定义非冲突的变量。
CUSTOM_VARIABLES='' 

# 🟢 【核心】：脚本自身的远程下载地址
SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh"
LOCAL_SCRIPT="$HOME/start.sh"

# ==========================================
# 📦 基础环境与变量加载
# ==========================================

cd "$HOME" || exit
echo ">>> [初始化] 工作目录已锁定至: $HOME"

# [逻辑优化] 优先加载外部传入的环境变量，然后再尝试加载脚本内部预设
if [ -n "$CUSTOM_VARIABLES" ]; then
    echo ">>> [环境] 正在加载脚本内部预设变量..."
    eval "export $CUSTOM_VARIABLES"
fi

# ==========================================
# 0. 🔌 自我安装与开机自启模块
# ==========================================
setup_persistence() {
    echo ""
    echo ">>> [系统] 正在检查脚本完整性与开机自启..."

    curl -L -s -o "$LOCAL_SCRIPT" "$SELF_URL"
    chmod +x "$LOCAL_SCRIPT"

    # [逻辑优化] 在 Crontab 命令中，我们需要保留当前的环境变量
    # 如果你在外部传入了 hypt="123"，我们需要想办法把它也写入 crontab，否则重启后变量会丢失。
    # 这里做一个简单的变量捕获：将当前的 hypt 写入 crontab (如果存在)
    
    CRON_VAR_STRING=""
    if [ -n "$hypt" ]; then CRON_VAR_STRING="export hypt=\"$hypt\";"; fi
    # 如果有其他变量(如 a, b)，可以在这里追加，或者使用更通用的方式

    if [ -n "$CUSTOM_VARIABLES" ]; then
        CRON_CMD="@reboot eval \"export $CUSTOM_VARIABLES\"; $CRON_VAR_STRING /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    else
        CRON_CMD="@reboot $CRON_VAR_STRING /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    fi

    if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q "$LOCAL_SCRIPT"; then
        echo ">>> [自启] ✅ 开机自启任务已存在，跳过。"
    else
        if command -v crontab >/dev/null 2>&1; then
            (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
            if [ $? -eq 0 ]; then
                echo ">>> [自启] ✅ 成功添加开机自启任务！"
            else
                echo ">>> [自启] ❌ 添加失败 (可能是权限受限)。"
            fi
        else
            echo ">>> [自启] ⚠️ 未找到 crontab 工具，跳过自启设置。"
        fi
    fi
}

# ==========================================
# 1. 🛡️ 哪吒探针逻辑模块
# ==========================================
start_nezha() {
    local cmd_str="$1"
    local bin_file="nezha-agent"
    local config_file="nezha.yml"

    # [逻辑] 如果指令为空，尝试读取本地配置
    if [ -z "$cmd_str" ]; then
        if [ -f "$config_file" ]; then
            echo ">>> [探针] ✅ 检测到现有的配置文件，直接启动..."
            ./"$bin_file" -c "$config_file" >/dev/null 2>&1 &  
            return
        else
            echo ">>> [探针] ⚠️ 未提供配置且无本地配置文件，跳过启动。"
            return
        fi
    fi

    echo ""
    echo ">>> [探针] 正在解析指令并更新配置..."

    # 解析参数
    local server=$(echo "$cmd_str" | grep -o 'NZ_SERVER=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local secret=$(echo "$cmd_str" | grep -o 'NZ_CLIENT_SECRET=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local tls=$(echo "$cmd_str" | grep -o 'NZ_TLS=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    
    if [ -z "$tls" ]; then tls="false"; fi

    if [ -z "$server" ] || [ -z "$secret" ]; then
        echo ">>> [错误] 无法解析 Server 或 Secret，请检查指令格式。"
        return
    fi

    # 架构判断与下载
    local arch=$(uname -m)
    local arch_code="amd64"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then arch_code="arm64"; fi
    
    if [ ! -f "$bin_file" ]; then
        echo ">>> [下载] 正在下载哪吒探针 (${arch_code})..."
        curl -L -o nezha.zip "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch_code}.zip"
        unzip -o nezha.zip > /dev/null
        chmod +x "$bin_file"
        rm -f nezha.zip
    fi

    cat > "$config_file" <<EOF
server: $server
client_secret: $secret
tls: $tls
EOF
    echo ">>> [配置] 配置文件 nezha.yml 已重新生成。"

    echo ">>> [启动] 拉起 Nezha Agent..."
    ./"$bin_file" -c "$config_file" >/dev/null 2>&1 &  
}

# ==========================================
# 2. 🚀 主业务逻辑 (Argosbx)
# ==========================================
start_argosbx() {
    echo ""
    echo "===================================================="
    echo ">>> [主程序] 准备启动 Argosbx 业务"
    echo "===================================================="
    
    # [新功能] 智能环境变量检测
    # 逻辑：如果检测到 hypt 变量已经存在（通过 a="1" 这种方式传入），则跳过输入。
    # 或者，如果用户设置了 AUTO_RUN=true，也跳过输入。
    
    local skip_input=false

    # 检测 hypt 是否有值
    if [ -n "$hypt" ]; then
        echo ">>> [环境] ✅ 检测到外部变量 hypt = $hypt"
        skip_input=true
    fi

    # 检测是否有通用的自动运行标记
    if [ "$AUTO_RUN" == "true" ]; then
        echo ">>> [环境] ✅ 检测到 AUTO_RUN 标记，跳过手动输入。"
        skip_input=true
    fi

    if [ "$skip_input" = true ]; then
        echo ">>> [提示] 使用现有环境变量，直接启动业务脚本..."
        # 这里不需要 eval，因为环境变量已经存在于当前 shell 中
    else
        # 只有在没有外部变量时，才要求用户手动输入
        echo "请输入 Argosbx 需要的环境变量 (例如: hypt=\"1234\")"
        echo "提示：如果有多个变量，请用空格隔开；直接回车则跳过。"
        read -t 20 -p "请输入变量 > " USER_ENV_INPUT

        if [ -n "$USER_ENV_INPUT" ]; then
            echo ">>> [环境] 检测到手动输入变量，正在应用..."
            eval "export $USER_ENV_INPUT"
        else
            echo ">>> [环境] 未检测到输入或超时，使用默认环境。"
        fi
    fi

    echo ">>> [主程序] 正在下载并运行脚本..."
    
    local script_name="argosbx.sh"
    local script_url="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

    if [ ! -f "$script_name" ]; then
        curl -L -o "$script_name" "$script_url"
        chmod +x "$script_name"
    fi

    # 直接运行，子脚本会自动继承当前 shell 的所有环境变量 (包括 hypt, a, b 等)
    ./"$script_name"
}

# ==========================================
# 🏁 脚本入口 (Main Function)
# ==========================================
clear
echo "===================================================="
echo "                  Container-Script                  "
echo "===================================================="

setup_persistence

# [新功能] 哪吒指令的外部注入支持
# 允许使用 NZ_CMD="xxx" bash start.sh 这种方式传入哪吒指令
if [ -n "$NZ_CMD" ]; then
    echo ">>> [配置] 检测到外部传入的哪吒指令 (NZ_CMD)，将优先使用。"
    NEZHA_CMD_SOURCE="$NZ_CMD"
    # 如果外部传了指令，我们将超时时间设得非常短，实现近乎无感启动
    TIMEOUT=1
else
    TIMEOUT=20
    NEZHA_CMD_SOURCE="" 
fi

CONFIG_FILE="nezha.yml"
if [ -f "$CONFIG_FILE" ]; then 
    FILE_EXISTS=true
    echo ">>> [备份] 检测到本地已存在哪吒配置。"
else
    FILE_EXISTS=false
fi

# 只有在没有外部注入指令时，才显示冗长的菜单
if [ -z "$NZ_CMD" ]; then
    echo "----------------------------------------------------"
    echo "请配置【哪吒探针】($TIMEOUT 秒倒计时):"
    echo "1. [输入] 粘贴新指令并回车 -> 覆盖 nezha.yml"
    echo "2. [回车] 直接按回车        -> 使用现有 nezha.yml"
    echo "----------------------------------------------------"
fi

# 读取输入 (如果 TIMEOUT 是 1，这里几乎会瞬间跳过)
read -t $TIMEOUT -p "请输入哪吒指令 > " USER_INPUT
echo ""

# 优先级逻辑：
# 1. 用户当前手动输入 (USER_INPUT)
# 2. 外部环境变量注入 (NZ_CMD -> 也就是上面的 NEZHA_CMD_SOURCE)
# 3. 脚本内部预设 (PRESET_NEZHA_COMMAND)
# 4. 本地文件

if [ -n "$USER_INPUT" ]; then
    NEZHA_CMD_SOURCE="$USER_INPUT"
    echo ">>> [配置] 使用手动输入更新配置。"

elif [ -n "$NEZHA_CMD_SOURCE" ]; then
    # 这里对应外部注入的情况 (NZ_CMD)
    echo ">>> [配置] 使用外部注入指令更新配置。"

elif [ -n "$PRESET_NEZHA_COMMAND" ]; then
    NEZHA_CMD_SOURCE="$PRESET_NEZHA_COMMAND"
    echo ">>> [配置] 使用脚本预设更新配置。"

elif [ "$FILE_EXISTS" = true ]; then
    NEZHA_CMD_SOURCE="" 
    echo ">>> [配置] 使用本地备份配置启动。"

else
    echo ">>> [提示] 未检测到任何配置，哪吒探针将不会启动。"
fi

# 4. 启动服务
start_nezha "$NEZHA_CMD_SOURCE"
start_argosbx

# 5. 保活逻辑
echo ""
echo ">>> [保活] 正在启动后台保活进程 (Keep-Alive)..."
nohup sh -c 'while true; do sleep 3600; done' >/dev/null 2>&1 &

echo ">>> [完成] 所有任务已触发，脚本执行完毕。"
