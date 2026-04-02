#!/usr/bin/env node

/**
 * ==========================================
 * 🟢 Container-Script Node.js 完整版 (终极修复版)
 * ==========================================
 * 说明：修复了输入流被截断导致的直接跳过问题，
 * 取消了首次输入环境变量的超时限制，会无限等待用户配置。
 */

const fs = require('fs');           // 引入文件系统模块，用来读写文件
const path = require('path');       // 引入路径处理模块
const { execSync, spawn } = require('child_process'); // 引入执行外部系统命令的模块
const https = require('https');     // 引入网络请求模块，用来下载文件
const os = require('os');           // 引入系统信息模块
const readline = require('readline'); // 引入读取用户输入的交互模块

// ==========================================
// 🟢 配置区域
// ==========================================
const SELF_URL = "https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.js";
const LOCAL_SCRIPT = path.join(os.homedir(), "start.js");
const PRESET_NEZHA_COMMAND = "";
const CUSTOM_VARIABLES = {};

// ==========================================
// 🛠️ 工具函数库
// ==========================================
const log = {
    info: (msg) => console.log(`\x1b[32m>>> [系统] ${msg}\x1b[0m`), 
    warn: (msg) => console.log(`\x1b[33m>>> [警告] ${msg}\x1b[0m`), 
    err: (msg) => console.log(`\x1b[31m>>> [错误] ${msg}\x1b[0m`),  
    step: (msg) => console.log(`\x1b[36m>>> [步骤] ${msg}\x1b[0m`), 
};

function commandExists(cmd) {
    try {
        execSync(`command -v ${cmd}`, { stdio: 'ignore' });
        return true;
    } catch (e) {
        return false;
    }
}

function downloadFileSilent(url, dest) {
    return new Promise((resolve, reject) => {
        const file = fs.createWriteStream(dest);
        https.get(url, (response) => {
            if (response.statusCode === 302 || response.statusCode === 301) {
                downloadFileSilent(response.headers.location, dest).then(resolve).catch(reject);
                return;
            }
            response.pipe(file);
            file.on('finish', () => file.close(() => resolve(dest)));
        }).on('error', (err) => fs.unlink(dest, () => reject(err)));
    });
}

function runCommand(command, args, detach = false) {
    const options = { stdio: 'inherit' };
    if (detach) options.detached = true; 
    const child = spawn(command, args, options);
    if (detach) child.unref(); 
    return child;
}

// 【新增核心修复】：更安全的输入交互方法，彻底解决终端输入框乱跳或被截断的问题
function askQuestion(query, timeoutMs = 0) {
    return new Promise((resolve) => {
        const rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout
        });

        let timer;
        // 只有在明确设置了超时时间（大于0）时，才启动倒计时
        if (timeoutMs > 0) {
            timer = setTimeout(() => {
                rl.close(); // 时间到了关闭当前交互
                resolve(""); // 返回空值
            }, timeoutMs);
        }

        // 等待用户键盘输入
        rl.question(query, (answer) => {
            if (timer) clearTimeout(timer); // 一旦检测到用户输入了，立马取消倒计时炸弹
            rl.close(); // 完成输入后平稳关闭交互通道
            resolve(answer.trim()); // 返回用户输入的内容（去掉首尾多余的空格）
        });
    });
}

// ==========================================
// 🟢 模块 0：环境自检 
// ==========================================
function checkDependencies() {
    log.info("正在检查环境依赖...");
    process.env.PATH = `${process.env.PATH}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`;
    if (commandExists('unzip')) {
        log.info("✅ 系统已有 unzip。");
        return 'unzip'; 
    } 
    if (commandExists('jar')) {
        log.info("✅ 检测到 Java，将使用 jar 代替 unzip。");
        return 'jar';
    }
    return null;
}

function unzipFile(zipFile, mode) {
    if (mode === 'unzip') execSync(`unzip -o "${zipFile}"`, { stdio: 'inherit' });
    else if (mode === 'jar') execSync(`jar xf "${zipFile}"`, { stdio: 'inherit' });
}

// ==========================================
// 0. 🔌 自我安装与开机自启模块
// ==========================================
async function setupPersistence() {
    log.step("正在检查脚本完整性与开机自启...");
    try {
        await downloadFileSilent(SELF_URL, LOCAL_SCRIPT);
        fs.chmodSync(LOCAL_SCRIPT, '755'); 
    } catch (e) {}

    if (!commandExists('crontab')) {
        log.warn("⚠️ 当前环境未安装 crontab，跳过开机自启。");
        return; 
    }

    const cronCmd = `@reboot ${process.execPath} "${LOCAL_SCRIPT}" >/dev/null 2>&1 &`;
    try {
        let currentCron = "";
        try { currentCron = execSync('crontab -l', { stdio: ['pipe', 'pipe', 'ignore'] }).toString(); } catch (e) {}

        if (!currentCron.includes(LOCAL_SCRIPT)) {
            const child = spawn('crontab', ['-']);
            child.on('error', () => log.warn("⚠️ 设置 crontab 出错，跳过。"));
            child.stdin.write(`${currentCron}\n${cronCmd}\n`);
            child.stdin.end();
            log.info("✅ 成功添加开机自启任务！");
        }
    } catch (e) {}
}

// ==========================================
// 1. 🛡️ 哪吒探针逻辑模块
// ==========================================
async function startNezha(cmdStr, unzipMode) {
    const binFile = "nezha-agent";
    const configFile = "nezha.yml";

    if (!cmdStr) {
        if (fs.existsSync(configFile)) {
            log.info("✅ 使用本地已有配置文件启动探针...");
            runCommand(`./${binFile}`, ['-c', configFile], true);
            return;
        } else {
            log.warn("⚠️ 跳过哪吒探针启动。");
            return;
        }
    }

    log.step("正在解析指令并重新配置探针...");
    const server = (cmdStr.match(/NZ_SERVER=([^ ]+)/) || [])[1] || "";
    const secret = (cmdStr.match(/NZ_CLIENT_SECRET=([^ ]+)/) || [])[1] || "";
    const tls = (cmdStr.match(/NZ_TLS=([^ ]+)/) || [])[1] || "false";

    if (!server || !secret) {
        log.err("无法解析 Server 或 Secret，跳过配置。");
        return;
    }

    if (!fs.existsSync(binFile)) {
        let archCode = (os.arch() === 'arm64' || os.arch() === 'aarch64') ? "arm64" : "amd64";
        log.info(`>>> [下载] 正在下载适配 ${archCode} 的探针...`);
        try {
            execSync(`curl -L -o nezha.zip https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${archCode}.zip`, { stdio: 'inherit' });
            unzipFile('nezha.zip', unzipMode);
            fs.chmodSync(binFile, '755');
            fs.unlinkSync('nezha.zip'); 
        } catch (e) {
            log.err(`探针下载失败: ${e.message}`);
            return;
        }
    }

    fs.writeFileSync(configFile, `server: ${server}\nclient_secret: ${secret}\ntls: ${tls}\n`);
    log.info("✅ 配置文件 nezha.yml 已写入。");
    
    log.step("🚀 拉起 Nezha Agent...");
    runCommand(`./${binFile}`, ['-c', configFile], true);
}

// ==========================================
// 2. 🚀 主业务逻辑 (Argosbx)
// ==========================================
async function startArgosbx() {
    console.log("\n====================================================");
    log.step("准备启动 Argosbx 业务");
    console.log("====================================================");

    const envFile = "argosbx_env.txt";
    let userEnv = "";

    // 检查本地是否已经有“记忆卡” (保存过的环境变量文件)
    if (fs.existsSync(envFile)) {
        userEnv = fs.readFileSync(envFile, 'utf8').trim();
        log.info(`✅ 读取到已保存的 Argosbx 环境变量配置: ${userEnv}`);
    } else {
        // 如果没有记忆卡，说明是第一次运行
        let skipInput = process.env.hypt || process.env.AUTO_RUN === 'true';
        if (!skipInput) {
            console.log("\n💡 [提示] 首次运行，请输入 Argosbx 环境变量。如hypt=123);
            
            // 【重点优化】：这里没有传超时时间，所以程序会在这里死等，直到你输入完按下回车！
            userEnv = await askQuestion("请输入 Argosbx 环境变量 (如 hypt=\"123\") > ");

            if (userEnv) {
                fs.writeFileSync(envFile, userEnv);
                log.info("✅ 环境变量已永久保存到本地，下次开机将自动读取，无需重复输入！");
            } else {
                log.warn("⚠️ 警告：你没有输入任何变量！直接按了回车。脚本稍后可能会报错💣。");
            }
        }
    }

    // 将环境变量注入当前系统
    if (userEnv) {
        userEnv.replace(/export /g, '').split(' ').forEach(kv => {
            const [key, val] = kv.split('=');
            if (key && val) process.env[key] = val.replace(/["']/g, ''); 
        });
    }

    const scriptName = "argosbx.sh";
    if (!fs.existsSync(scriptName)) {
        log.info(`>>> [下载] 正在从 GitHub 下载 ${scriptName} ...`);
        try {
            execSync(`curl -L -o ${scriptName} https://raw.githubusercontent.com/yonggekkk/argosbx/refs/heads/main/argosbx.sh`, { stdio: 'inherit' });
            fs.chmodSync(scriptName, '755');
        } catch (e) {}
    }

    log.step(`正在运行 Argosbx (${scriptName})...`);
    runCommand('bash', [`./${scriptName}`]);
}

// ==========================================
// 🏁 主函数 (Main)
// ==========================================
async function main() {
    console.clear();
    console.log("====================================================");
    console.log("                 Container-Script (Node.js)         ");
    console.log("====================================================");

    for (const [key, value] of Object.entries(CUSTOM_VARIABLES)) {
        process.env[key] = value; 
    }

    const unzipMode = checkDependencies();
    await setupPersistence();

    let nezhaCmdSource = process.env.NZ_CMD || "";

    // 【优化】：如果本地已经有探针配置（nezha.yml），就不要弹出 15 秒倒计时去烦人了
    if (!nezhaCmdSource && !PRESET_NEZHA_COMMAND) {
        if (fs.existsSync("nezha.yml")) {
            log.info("✅ 检测到现有的哪吒配置 (nezha.yml)，直接跳过重新输入步骤...");
        } else {
            console.log("----------------------------------------------------");
            console.log("请选择操作 (15秒倒计时):");
            console.log("1. [输入] 粘贴新哪吒指令并回车 (将覆盖旧配置)");
            console.log("2. [回车] 直接按回车跳过等待");
            console.log("----------------------------------------------------");
            // 这里传了 15000，意味着它最多等你 15 秒
            nezhaCmdSource = await askQuestion("请输入 > ", 15000);
            if (!nezhaCmdSource) console.log("\n>>> [系统] 时间到或直接跳过，继续执行...");
        }
    }

    await startNezha(nezhaCmdSource, unzipMode);
    await startArgosbx();

    console.log("");
    log.step("正在启动后台保活进程 (Keep-Alive)...");
    setInterval(() => {}, 3600 * 1000); 
}

main().catch(err => console.error("运行出错:", err));
