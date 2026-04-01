#!/usr/bin/env node

/**
 * ==========================================
 * 🟢 Container-Script Node.js 完整版 (完美交互版)
 * ==========================================
 */

const fs = require('fs');           
const path = require('path');       
const { execSync, spawn } = require('child_process'); 
const https = require('https');     
const os = require('os');           
const readline = require('readline'); 

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
    const options = { stdio: 'inherit', shell: true };
    if (detach) options.detached = true; 
    const child = spawn(command, args, options);
    if (detach) child.unref(); 
    return child;
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

    // 【修改点】：如果用户没输入新指令，但有旧配置，使用旧配置启动
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

    let skipInput = process.env.hypt || process.env.AUTO_RUN === 'true';

    if (!skipInput) {
        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        const userEnv = await new Promise((resolve) => {
            const timer = setTimeout(() => { log.info("超时，使用默认环境。"); rl.close(); resolve(""); }, 15000); 
            rl.question("请输入 Argosbx 环境变量 (如 hypt=\"123\") > ", (answer) => {
                clearTimeout(timer); rl.close(); resolve(answer);
            });
        });

        if (userEnv) {
            userEnv.replace(/export /g, '').split(' ').forEach(kv => {
                const [key, val] = kv.split('=');
                if (key && val) process.env[key] = val.replace(/["']/g, ''); 
            });
        }
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

    // 【核心交互修改】：始终显示菜单，除非环境变量中强行指定了
    let nezhaCmdSource = process.env.NZ_CMD || "";

    if (!nezhaCmdSource && !PRESET_NEZHA_COMMAND) {
        console.log("----------------------------------------------------");
        if (fs.existsSync("nezha.yml")) {
            console.log("💡 [提示] 本地已存在哪吒配置备份 (nezha.yml)");
        }
        console.log("请选择操作 (15秒倒计时):");
        console.log("1. [输入] 粘贴新哪吒指令并回车 (将覆盖旧配置)");
        console.log("2. [回车] 直接按回车跳过等待 (自动使用已有配置)");
        console.log("----------------------------------------------------");

        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        nezhaCmdSource = await new Promise((resolve) => {
            const timer = setTimeout(() => {
                rl.close();
                console.log("\n>>> 倒计时结束，自动继续...");
                resolve("");
            }, 15000);

            rl.question("请输入 > ", (ans) => {
                clearTimeout(timer);
                rl.close();
                resolve(ans);
            });
        });
    }

    await startNezha(nezhaCmdSource, unzipMode);
    await startArgosbx();

    console.log("");
    log.step("正在启动后台保活进程 (Keep-Alive)...");
    setInterval(() => {}, 3600 * 1000); 
}

main().catch(err => console.error("运行出错:", err));
