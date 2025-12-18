#!/bin/bash

# ==========================================
# 🟢 模块 0：环境自检与依赖修复 (新增功能)
# ==========================================
# 这一部分会在脚本最开始运行，确保后续命令都有工具可用
check_dependencies() {
    echo ">>> [系统] 正在检查环境依赖..."

    # 1. 设置用户级 bin 目录 (解决无 Root 权限无法安装软件的问题)
    export PATH="$HOME/bin:$PATH"
    mkdir -p "$HOME/bin"

    # 2. 检测并修复 unzip (解压工具)
    if ! command -v unzip >/dev/null 2>&1; then
        echo ">>> [依赖] 未检测到 unzip，正在尝试修复..."
        
        # 方案 A: 尝试下载 Busybox (免安装版工具包)
        # 这里的链接是一个静态编译的二进制文件，包含 unzip 功能
        curl -L -s -o "$HOME/bin/unzip" https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-x86_64
        
        if [ -s "$HOME/bin/unzip" ]; then
            chmod +x "$HOME/bin/unzip"
            echo ">>> [依赖] ✅ 已下载免安装版 unzip。"
        else
            # 方案 B: Java (jar) 兜底策略
            # 如果无法下载 busybox，但系统里有 Java，利用 jar 命令解压
            if command -v jar >/dev/null 2>&1; then
                echo ">>> [依赖] ⚠️ 下载失败，切换为 Java (jar) 兼容模式。"
                
                # 定义一个名为 unzip 的函数，拦截脚本后续的 unzip 调用
                function unzip() {
                    # 遍历参数，找到 .zip 结尾的文件名 (因为 jar 不需要 -o -q 等参数)
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
                export -f unzip # 导出函数使其全局生效
            else
                echo ">>> [错误] ❌ 无法下载 unzip 且未找到 Java，解压可能会失败！"
            fi
        fi
    else
        echo ">>> [依赖] ✅ 系统已有 unzip。"
    fi

    # 3. 简单的 Cron 检测 (如果缺失，尝试下载 busybox 补充，但通常受限于权限)
    if ! command -v crontab >/dev/null 2>&1; then
        if [ -f "$HOME/bin/unzip" ]; then # 如果刚才下载了 busybox (也就是那个 unzip 文件)
            ln -s "$HOME/bin/unzip" "$HOME/bin/crontab" 2>/dev/null
        fi
    fi
}

# 立即执行依赖检查
check_dependencies

# ==========================================
# 🟢 脚本说明与配置区
# ==========================================
# 这是一个集成了哪吒探针和 Argosbx 业务的自动化脚本。
# 修改记录：
# 1. [2025-12-18] 优化配置逻辑：直接读取 nezha.yml。
# 2. 修正优先级逻辑：输入 > 预设 > 本地文件。
# 3. 新增依赖自动修复 (Unzip/Java Fallback)。

# 🟢 【配置 1】：哪吒指令预设区 (优先级 No.2)
# 如果这里填了内容，且你运行时没手动输入，它将强制覆盖本地的 nezha.yml
PRESET_NEZHA_COMMAND=""

# 🟢 【配置 2】：自定义环境变量 (脚本内部默认的，优先级低于手动输入)
CUSTOM_VARIABLES='hypt=""'

# 🟢 【核心】：脚本自身的远程下载地址 (用于自启更新)
SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh"
LOCAL_SCRIPT="$HOME/start.sh"

# ==========================================
# 📦 基础环境与变量加载
# ==========================================

cd "$HOME" || exit
# 切换到用户主目录，确保操作路径一致

echo ">>> [初始化] 工作目录已锁定至: $HOME"

# 加载脚本头部定义的默认变量
if [ -n "$CUSTOM_VARIABLES" ]; then
    echo ">>> [环境] 检测到预设变量字符串，正在加载..."
    eval "export $CUSTOM_VARIABLES"
fi

# ==========================================
# 0. 🔌 自我安装与开机自启模块
# ==========================================
setup_persistence() {
    echo ""
    echo ">>> [系统] 正在检查脚本完整性与开机自启..."

    # 下载最新版脚本覆盖当前文件 (保持脚本最新)
    # 注意：这里也依赖 curl，通常容器都有，若无则需在 check_dependencies 添加 curl 检测
    curl -L -s -o "$LOCAL_SCRIPT" "$SELF_URL"
    chmod +x "$LOCAL_SCRIPT"

    # 构建 Crontab 任务命令
    if [ -n "$CUSTOM_VARIABLES" ]; then
        # 如果有变量，需要在自启命令中也带上
        CRON_CMD="@reboot eval \"export $CUSTOM_VARIABLES\"; /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    else
        CRON_CMD="@reboot /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    fi

    # 检查是否已经添加过任务
    # 使用 2>/dev/null 屏蔽 crontab 可能产生的 "command not found" 报错
    if command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q "$LOCAL_SCRIPT"; then
        echo ">>> [自启] ✅ 开机自启任务已存在，跳过。"
    else
        # 添加任务到 crontab
        if command -v crontab >/dev/null 2>&1; then
            (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
            if [ $? -eq 0 ]; then
                echo ">>> [自启] ✅ 成功添加开机自启任务！"
            else
                echo ">>> [自启] ❌ 添加失败 (可能是权限受限，容器内常见)。"
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

    # 🟢 逻辑分支 A：使用本地现有文件
    # 条件：传入的指令字符串为空 (cmd_str 为空)
    if [ -z "$cmd_str" ]; then
        if [ -f "$config_file" ]; then
            echo ">>> [探针] ✅ 检测到现有的配置文件 ($config_file)，直接启动..."
            # 直接运行，不覆盖文件
            ./"$bin_file" -c "$config_file" >/dev/null 2>&1 &  
            return
        else
            echo ">>> [探针] ⚠️ 未提供配置且无本地配置文件，跳过哪吒探针启动。"
            return
        fi
    fi

    # 🟢 逻辑分支 B：根据指令生成/覆盖配置文件
    # 条件：传入了指令字符串 (来自用户输入 或 脚本预设)
    echo ""
    echo ">>> [探针] 正在解析指令并更新配置..."

    # 提取关键参数
    local server=$(echo "$cmd_str" | grep -o 'NZ_SERVER=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local secret=$(echo "$cmd_str" | grep -o 'NZ_CLIENT_SECRET=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local tls=$(echo "$cmd_str" | grep -o 'NZ_TLS=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    
    if [ -z "$tls" ]; then tls="false"; fi

    if [ -z "$server" ] || [ -z "$secret" ]; then
        echo ">>> [错误] 无法解析 Server 或 Secret，请检查指令格式。"
        return
    fi

    # 架构判断
    local arch=$(uname -m)
    local arch_code="amd64"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then arch_code="arm64"; fi
    
    # 下载探针
    if [ ! -f "$bin_file" ]; then
        echo ">>> [下载] 正在下载哪吒探针 (${arch_code})..."
        curl -L -o nezha.zip "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch_code}.zip"
        
        # 🟢 调用 unzip (此时它可能是系统自带的，也可能是我们要的 busybox，或者是 Java 函数)
        unzip -o nezha.zip > /dev/null
        
        chmod +x "$bin_file"
        rm -f nezha.zip
    fi

    # 生成配置 (这会覆盖旧的 nezha.yml)
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
    
    echo "请输入 Argosbx 需要的环境变量 (例如: hypt="1234")"
    echo "提示：如果有多个变量，请用空格隔开；直接回车则跳过。"
    read -t 20 -p "请输入变量 > " USER_ENV_INPUT

    if [ -n "$USER_ENV_INPUT" ]; then
        echo ">>> [环境] 检测到手动输入变量，正在应用..."
        eval "export $USER_ENV_INPUT"
    else
        echo ">>> [环境] 未检测到输入或超时，使用默认环境。"
    fi

    echo ">>> [主程序] 正在下载并运行脚本..."
    
    local script_name="argosbx.sh"
    local script_url="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

    if [ ! -f "$script_name" ]; then
        curl -L -o "$script_name" "$script_url"
        chmod +x "$script_name"
    fi

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

TIMEOUT=10
CONFIG_FILE="nezha.yml"
NEZHA_CMD_SOURCE="" 

# 检查本地文件是否存在 (仅用于提示，不决定逻辑)
if [ -f "$CONFIG_FILE" ]; then 
    echo ">>> [备份] 检测到本地已存在哪吒配置 (nezha.yml)。"
    FILE_EXISTS=true
else
    FILE_EXISTS=false
fi

echo "----------------------------------------------------"
echo "请配置【哪吒探针】($TIMEOUT 秒倒计时):"
echo "1. [输入] 粘贴新指令并回车 -> 覆盖 nezha.yml 并启动"
echo "2. [回车] 直接按回车        -> 使用现有 nezha.yml 启动"
echo "3. [等待] 什么都不做        -> 不使用 哪吒探针 启动"
echo "----------------------------------------------------"

read -t $TIMEOUT -p "请输入哪吒指令 > " USER_INPUT
echo ""

# 🟢 【逻辑修正区域】：严格遵循你的三级优先级
# 1. 输入 > 2. 预设 > 3. 本地文件

if [ -n "$USER_INPUT" ]; then
    # 【优先级 1】用户输入了内容
    # 动作：传递给函数，解析并覆盖 nezha.yml
    NEZHA_CMD_SOURCE="$USER_INPUT"
    echo ">>> [配置] 收到手动输入，准备更新配置..."
    
elif [ -n "$PRESET_NEZHA_COMMAND" ]; then
    # 【优先级 2】用户没输入，但脚本有预设
    # 动作：传递给函数，解析并覆盖 nezha.yml (不管本地有没有文件，预设优先)
    NEZHA_CMD_SOURCE="$PRESET_NEZHA_COMMAND"
    echo ">>> [配置] 未检测到输入，使用脚本内置预设 (覆盖本地配置)。"

elif [ "$FILE_EXISTS" = true ]; then
    # 【优先级 3】用户没输入，也没预设，但本地有文件
    # 动作：传空值给函数。函数检测到空值，会直接读取文件启动，不进行覆盖。
    NEZHA_CMD_SOURCE="" 
    echo ">>> [配置] 无输入且无预设，使用本地备份配置启动。"

else
    # 【无配置】啥都没有
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
