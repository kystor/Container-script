#!/bin/bash

# ==========================================
# 🟢 模块 0：环境自检
# ==========================================
check_dependencies() {
    # [保持] 仅输出简洁的提示，不输出繁琐的 apk/apt 安装日志
    echo ">>> [系统] 正在检查环境依赖..."

    export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    # 检测 unzip (逻辑检查，保持静默)
    if ! command -v unzip >/dev/null 2>&1; then
        echo ">>> [依赖] 系统未安装 unzip。"
        
        # Java (jar) 兜底策略
        if command -v jar >/dev/null 2>&1; then
            echo ">>> [依赖] ✅ 检测到 Java，将使用 jar 命令代替 unzip。"
            
            # [注解] 定义函数拦截 unzip 命令
            function unzip() {
                local zip_file=""
                for arg in "$@"; do
                    if [[ "$arg" == *.zip ]]; then zip_file="$arg"; break; fi
                done
                
                if [ -n "$zip_file" ]; then
                    echo " -> [Java] 正在使用 jar 解压: $zip_file"
                    # [修改] 移除 >/dev/null，保留 jar 的输出（如有）
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
# 2025-12-18: 修复 argosbx 调用参数缺失导致的输出不全问题；优化静默下载逻辑。

# 🟢 【配置 1】：哪吒指令预设区
PRESET_NEZHA_COMMAND=""

# 🟢 【配置 2】：自定义环境变量
CUSTOM_VARIABLES='' 

# 🟢 【核心】：脚本自身的远程下载地址
SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh"
LOCAL_SCRIPT="$HOME/start.sh"

# ==========================================
# 📦 基础环境与变量加载
# ==========================================

cd "$HOME" || exit
echo ">>> [初始化] 工作目录已锁定至: $HOME"

# 加载外部或内部变量
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

    # [修改] curl 去掉 -s (silent) 可能会太吵，这里保留 -s 但去掉 >/dev/null 如果你想看错误
    # 这里保持 -s (静默下载) 以免进度条刷屏，但如果有错误会显示
    curl -L -s -o "$LOCAL_SCRIPT" "$SELF_URL"
    chmod +x "$LOCAL_SCRIPT"

    CRON_VAR_STRING=""
    if [ -n "$hypt" ]; then CRON_VAR_STRING="export hypt=\"$hypt\";"; fi

    if [ -n "$CUSTOM_VARIABLES" ]; then
        CRON_CMD="@reboot eval \"export $CUSTOM_VARIABLES\"; $CRON_VAR_STRING /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    else
        CRON_CMD="@reboot $CRON_VAR_STRING /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    fi

    # 这里的 >/dev/null 是为了屏蔽 grep 的输出，不是屏蔽子进程，保持原样
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

    # 逻辑分支 A：使用本地现有文件
    if [ -z "$cmd_str" ]; then
        if [ -f "$config_file" ]; then
            echo ">>> [探针] ✅ 检测到现有的配置文件，直接启动..."
            # [修改] 移除 >/dev/null 2>&1，保留 & (后台运行)
            # 这样你可以看到 Agent 的连接日志
            ./"$bin_file" -c "$config_file" &  
            return
        else
            echo ">>> [探针] ⚠️ 未提供配置且无本地配置文件，跳过启动。"
            return
        fi
    fi

    echo ""
    echo ">>> [探针] 正在解析指令并更新配置..."

    local server=$(echo "$cmd_str" | grep -o 'NZ_SERVER=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local secret=$(echo "$cmd_str" | grep -o 'NZ_CLIENT_SECRET=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local tls=$(echo "$cmd_str" | grep -o 'NZ_TLS=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    
    if [ -z "$tls" ]; then tls="false"; fi

    if [ -z "$server" ] || [ -z "$secret" ]; then
        echo ">>> [错误] 无法解析 Server 或 Secret，请检查指令格式。"
        return
    fi

    local arch=$(uname -m)
    local arch_code="amd64"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then arch_code="arm64"; fi
    
    if [ ! -f "$bin_file" ]; then
        echo ">>> [下载] 正在下载哪吒探针 (${arch_code})..."
        curl -L -o nezha.zip "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch_code}.zip"
        
        # [修改] 移除 >/dev/null，显示解压信息
        unzip -o nezha.zip
        
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
    # [修改] 关键修改：移除输出屏蔽，保留 & 后台运行
    ./"$bin_file" -c "$config_file" &  
}

# ==========================================
# 2. 🚀 主业务逻辑 (Argosbx)
# ==========================================
start_argosbx() {
    echo ""
    echo "===================================================="
    echo ">>> [主程序] 准备启动 Argosbx 业务"
    echo "===================================================="
    
    local skip_input=false

    # 智能跳过逻辑
    if [ -n "$hypt" ]; then
        echo ">>> [环境] ✅ 检测到外部变量 hypt = $hypt"
        skip_input=true
    fi

    if [ "$AUTO_RUN" == "true" ]; then
        echo ">>> [环境] ✅ 检测到 AUTO_RUN 标记，跳过手动输入。"
        skip_input=true
    fi

    if [ "$skip_input" = true ]; then
        echo ">>> [提示] 使用现有环境变量，直接启动业务脚本..."
    else
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

    # [修改逻辑] 下载逻辑优化
    local script_name="argosbx.sh"
    local script_url="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

    # 判断文件是否存在
    if [ -f "$script_name" ]; then
        # 如果存在，什么都不做，完全静默
        :
    else
        # 如果不存在，才输出提示并下载
        echo ">>> [下载] 本地未找到脚本，正在下载 Argosbx..."
        curl -L -o "$script_name" "$script_url"
        chmod +x "$script_name"
    fi

    echo ">>> [执行] 正在运行 Argosbx (模式: rep)..."
    
    # [关键修复]
    # 添加 'rep' 参数。
    # 作用：强制脚本进入 "Repair/Reset" 模式。
    # 效果：即使本地已安装，也会重新生成/输出详细的节点信息（UUID、链接等）。
    # 如果不加 'rep'，已安装的脚本只会显示简单的 "运行中" 状态。
    bash "$script_name" rep
}

# ==========================================
# 🏁 脚本入口 (Main Function)
# ==========================================
clear
echo "===================================================="
echo "                  Container-Script                  "
echo "===================================================="

setup_persistence

# 外部哪吒指令支持
if [ -n "$NZ_CMD" ]; then
    echo ">>> [配置] 检测到外部传入的哪吒指令 (NZ_CMD)，将优先使用。"
    NEZHA_CMD_SOURCE="$NZ_CMD"
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

if [ -z "$NZ_CMD" ]; then
    echo "----------------------------------------------------"
    echo "请配置【哪吒探针】($TIMEOUT 秒倒计时):"
    echo "1. [输入] 粘贴新指令并回车  ->  覆盖 nezha.yml"
    echo "2. [回车] 直接按回车        -> 使用现有 nezha.yml"
    echo "3. [等待] 什么也不做        -> 取消使用 哪吒 探针"
    echo "----------------------------------------------------"
fi

read -t $TIMEOUT -p "请输入哪吒指令 > " USER_INPUT
echo ""

if [ -n "$USER_INPUT" ]; then
    NEZHA_CMD_SOURCE="$USER_INPUT"
    echo ">>> [配置] 使用手动输入更新配置。"

elif [ -n "$NEZHA_CMD_SOURCE" ]; then
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
# 注意：这里的 /dev/null 是为了屏蔽 sleep 命令的输出，它本身没有输出，所以没关系
nohup sh -c 'while true; do sleep 3600; done' >/dev/null 2>&1 &

echo ">>> [完成] 所有任务已触发，脚本执行完毕。"
