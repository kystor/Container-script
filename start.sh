#!/bin/bash

# ==========================================
# 🟢 模块 0：环境自检
# ==========================================
check_dependencies() {
    # [保持] 仅输出简洁的提示
    echo ">>> [系统] 正在检查环境依赖..."

    export PATH="$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    # 检测 unzip
    if ! command -v unzip >/dev/null 2>&1; then
        echo ">>> [依赖] 系统未安装 unzip。"
        
        # Java (jar) 兜底策略
        if command -v jar >/dev/null 2>&1; then
            echo ">>> [依赖] ✅ 检测到 Java，将使用 jar 命令代替 unzip。"
            
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
# 2025-12-21: 移除 Argosbx 的交互询问，实现变量无感透传。

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

    curl -L -s -o "$LOCAL_SCRIPT" "$SELF_URL"
    chmod +x "$LOCAL_SCRIPT"

    # [注解] 仅保留原有的 hypt 兼容，不额外添加新变量，保持脚本简洁
    CRON_VAR_STRING=""
    if [ -n "$hypt" ]; then CRON_VAR_STRING="export hypt=\"$hypt\";"; fi

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

    # 逻辑分支 A：使用本地现有文件
    if [ -z "$cmd_str" ]; then
        if [ -f "$config_file" ]; then
            echo ">>> [探针] ✅ 检测到现有的配置文件，直接启动..."
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
    
    # [修改说明]
    # 这里移除了所有的 if/else 判断和 read 交互。
    # 脚本不再试图“理解”你的变量，也不再拦截你。
    # 无论你传了 vmpt, argo, uuid 还是什么，系统环境变量里只要有，
    # 下面的 argosbx.sh 就能直接读到。
    
    echo ">>> [透传] 正在加载并运行 Argosbx，所有环境变量已自动继承..."

    local script_name="argosbx.sh"
    local script_url="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

    # 判断文件是否存在
    if [ -f "$script_name" ]; then
        :
    else
        echo ">>> [下载] 本地未找到脚本，正在下载 Argosbx..."
        curl -L -o "$script_name" "$script_url"
        chmod +x "$script_name"
    fi

    echo ">>> [执行] 正在运行 Argosbx (模式: rep)..."
    
    # 直接运行，argosbx.sh 会自己处理一切变量
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
# [注解] 只有检测到 NZ_CMD 才会触发快速配置，否则走普通倒计时逻辑
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
nohup sh -c 'while true; do sleep 3600; done' >/dev/null 2>&1 &

echo ">>> [完成] 所有任务已触发，脚本执行完毕。"
