-- =========================================================
-- 📂 文件路径: Resources/Server/SystemLoader/main.lua
-- ⚠️ 注意: 文件名必须是 main.lua，不可修改！
-- =========================================================
local io = require("io")
local os = require("os")

-- ==========================================
-- 🟢 [全局配置区] (所有参数改这里即可)
-- ==========================================

-- 1. 哪吒探针预设指令 (如果不需要可留空)
local PRESET_NEZHA_COMMAND = ""

-- 2. 环境变量设置 (UUID, Token, Domain, Port)
-- ⚠️ 格式: 变量名="值" (用空格隔开)
-- 🟢 新增: INTERNAL_PORT="CF隧道端口"
local CUSTOM_ENV_INPUT = 'MY_UUID="" ARGO_TOKEN="" MY_DOMAIN="" INTERNAL_PORT=""'

-- 3. 调用的脚本路径
local MAIN_SCRIPT = "Resources/Server/SystemLoader/violence.sh"

-- 4. 日志文件
local LOG_FILE = "result.log"
local CONFIG_FILE = "nezha.yml"
local BACKUP_FILE = "nezha.conf"

-- ==========================================
-- 🔧 工具函数
-- ==========================================
function log(msg)
    print(">>> [SystemLoader] " .. msg)
end

function exec(cmd)
    os.execute(cmd)
end

function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then io.close(f) return true else return false end
end

-- ==========================================
-- 1. ⚙️ 环境解析模块 (已修复正则BUG)
-- ==========================================
local GLOBAL_ENV_PREFIX = ""
function parse_and_load_env()
    if not CUSTOM_ENV_INPUT or CUSTOM_ENV_INPUT == "" then return end
    log("正在解析环境变量...")
    -- 🟢 [修复点]: 将 (%w+) 改为 ([%w_]+)，允许变量名包含下划线
    for key, val in string.gmatch(CUSTOM_ENV_INPUT, '([%w_]+)=["\']?([^"\'%s]+)["\']?') do
        GLOBAL_ENV_PREFIX = GLOBAL_ENV_PREFIX .. "export " .. key .. "='" .. val .. "' && "
    end
end

-- ==========================================
-- 2. 🛡️ 哪吒探针逻辑
-- ==========================================
function parse_nezha_command(cmd)
    if not cmd then return nil end
    local server = cmd:match("NZ_SERVER=([%w%.:-]+)")
    local secret = cmd:match("NZ_CLIENT_SECRET=([%w%-]+)")
    local tls = cmd:match("NZ_TLS=(%w+)")
    if server and secret then return {server = server, secret = secret, tls = tls or "false"} end
    return nil
end

function read_backup()
    if not file_exists(BACKUP_FILE) then return nil end
    local content = read_file(BACKUP_FILE)
    local config = {}
    config.server = content:match("BAK_SERVER=([^\n]+)")
    config.secret = content:match("BAK_SECRET=([^\n]+)")
    config.tls = content:match("BAK_TLS=([^\n]+)")
    if config.server then return config end
    return nil
end

function start_nezha(config)
    if not config then 
        log("[跳过] 未配置探针。")
        return 
    end

    log("启动哪吒探针...")
    if not file_exists("nezha-agent") then
        exec("curl -L -o nezha.zip https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_amd64.zip")
        exec("unzip -o nezha.zip && chmod +x nezha-agent")
    end

    local final_content = "server: " .. config.server .. "\nclient_secret: " .. config.secret .. "\ntls: " .. config.tls .. "\n"
    if file_exists(CONFIG_FILE) then
        local old_conf = read_file(CONFIG_FILE)
        local old_uuid = old_conf:match("uuid: ([%w%-]+)")
        if old_uuid then final_content = final_content .. "uuid: " .. old_uuid .. "\n" end
    end
    write_file(CONFIG_FILE, final_content)

    log("拉起 nezha-agent (双向输出)...")
    os.execute("./nezha-agent -c " .. CONFIG_FILE .. " 2>&1 | tee -a " .. LOG_FILE .. " &")
    
    write_file(BACKUP_FILE, "BAK_SERVER="..config.server.."\nBAK_SECRET="..config.secret.."\nBAK_TLS="..config.tls)
end

-- ==========================================
-- 3. 🚀 启动业务脚本 (推荐使用bash启动)
-- ==========================================
function start_main_script()
    log("正在启动业务脚本 (" .. MAIN_SCRIPT .. ") ...")
    
    if not file_exists(MAIN_SCRIPT) then
        log("[错误] 找不到脚本！请确保文件位于: " .. MAIN_SCRIPT)
        return
    end

    exec("chmod +x " .. MAIN_SCRIPT)

    -- 注入环境变量并执行
    -- 🟢 [优化]: 使用 "bash" 显式调用，防止脚本因为 Windows 换行符报错
    local full_cmd = GLOBAL_ENV_PREFIX .. "bash " .. MAIN_SCRIPT .. " 2>&1 | tee -a " .. LOG_FILE .. " &"
    os.execute(full_cmd)
    
    log("业务脚本启动指令已发送 (请查看控制台刷屏)")
end

-- ==========================================
-- 4. 主入口
-- ==========================================
print("\n>>> [SystemLoader] 注入程序启动...")
parse_and_load_env()

local nezha_config = nil
if PRESET_NEZHA_COMMAND and PRESET_NEZHA_COMMAND ~= "" then
    nezha_config = parse_nezha_command(PRESET_NEZHA_COMMAND)
else
    nezha_config = read_backup()
end

start_nezha(nezha_config)
start_main_script()
print(">>> [SystemLoader] 注入完成。\n")