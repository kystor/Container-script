#!/usr/bin/env node
const fs = require('fs');           // 引入文件系统模块，用来读写文件
const path = require('path');       // 引入路径处理模块
const { execSync, spawn } = require('child_process'); // 引入执行外部系统命令的模块，用于运行子进程
const https = require('https');     // 引入网络请求模块，用来下载文件
const os = require('os');           // 引入系统信息模块
const readline = require('readline'); // 引入读取用户输入的交互模块

// ==========================================
// 🟢 全局配置区域
// ==========================================
const SELF_URL = "https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.js";
const LOCAL_SCRIPT = path.join(os.homedir(), "start.js");

// 【优先级 2】(代码预设)：如果你有哪吒指令需求，请在双引号中输入哪吒指令
const PRESET_NEZHA_COMMAND = ""; 

// 👇 这里就是为你修改的地方：使用你喜欢的等号格式，将变量写在单引号里的字符串中
// Node.js 会在主函数中自动把这句话“拆解”并翻译成系统能看懂的环境变量
const CUSTOM_VARIABLES_STR = 'hypt=""';

// ==========================================
// 🛠️ 工具函数库
// ==========================================
const log = {
    info: (msg) => console.log(`\x1b[32m>>> [系统] ${msg}\x1b[0m`), 
    warn: (msg) => console.log(`\x1b[33m>>> [警告] ${msg}\x1b[0m`), 
    err: (msg) => console.log(`\x1b[31m>>> [错误] ${msg}\x1b[0m`),  
    step: (msg) => console.log(`\x1b[36m>>> [步骤] ${msg}\x1b[0m`), 
};

// 检查系统内是否存在某个命令
function commandExists(cmd) {
    try {
        execSync(`command -v ${cmd}`, { stdio: 'ignore' });
        return true;
    } catch (e) {
        return false;
    }
}

// 静默下载文件函数
function downloadFileSilent(url, dest) {
    return new Promise((resolve, reject) => {
        const file = fs.createWriteStream(dest);
        https.get(url, (response) => {
            // 如果遇到网页重定向（比如 302 跳转），自动跟随新链接去下载
            if (response.statusCode === 302 || response.statusCode === 301) {
                downloadFileSilent(response.headers.location, dest).then(resolve).catch(reject);
                return;
            }
            response.pipe(file);
            file.on('finish', () => file.close(() => resolve(dest)));
        }).on('error', (err) => fs.unlink(dest, () => reject(err)));
    });
}

// 运行系统命令（保证子进程完全不隐藏输出，继承父进程的控制台输出）
function runCommand(command, args, detach = false) {
    // stdio: 'inherit' 代表子进程的输出将直接打印到你的屏幕上，绝不屏蔽
    const options = { stdio: 'inherit' };
    if (detach) options.detached = true; 
    const child = spawn(command, args, options);
    if (detach) child.unref(); 
    return child;
}

// 更安全的交互输入封装（带倒计时功能）
function askQuestion(query, timeoutMs = 0) {
    return new Promise((resolve) => {
        const rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout
        });

        let timer;
        if (timeoutMs > 0) {
            // 如果设置了超时时间，时间一到就自动结束等待，返回空内容
            timer = setTimeout(() => {
                rl.close(); 
                resolve(""); 
            }, timeoutMs);
        }

        rl.question(query, (answer) => {
            if (timer) clearTimeout(timer); 
            rl.close(); 
            resolve(answer.trim()); 
        });
    });
}

// ==========================================
// 🟢 模块 0：环境自检 
// ==========================================
function checkDependencies() {
    // 已经清理了冗长的依赖检查打印输出，保持界面整洁
    process.env.PATH = `${process.env.PATH}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`;
    if (commandExists('unzip')) {
        return 'unzip'; 
    } 
    if (commandExists('jar')) {
        return 'jar';
    }
    return null;
}

// 解压文件模块
function unzipFile(zipFile, mode) {
    // 解压文件时也保持输出可见 (inherit)
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
        fs.chmodSync(LOCAL_SCRIPT, '755'); // 赋予可执行权限
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
async function startNezha(cmdStr, unzipMode, useOldConfig) {
    const binFile = "nezha-agent";
    const configFile = "nezha.yml";

    // 如果决定使用历史记忆 (优先级 3)
    if (useOldConfig) {
        log.info("✅ 正在使用本地历史配置 (nezha.yml) 启动探针...");
        runCommand(`./${binFile}`, ['-c', configFile], true);
        return;
    }

    // 如果没有任何配置参数，直接跳过
    if (!cmdStr) {
        log.warn("⚠️ 没有提供哪吒参数，跳过哪吒探针启动。");
        return;
    }

    log.step("正在解析新指令并重新配置探针...");
    const server = (cmdStr.match(/NZ_SERVER=([^ ]+)/) || [])[1] || "";
    const secret = (cmdStr.match(/NZ_CLIENT_SECRET=([^ ]+)/) || [])[1] || "";
    const tls = (cmdStr.match(/NZ_TLS=([^ ]+)/) || [])[1] || "false";

    if (!server || !secret) {
        log.err("无法解析 Server 或 Secret，跳过配置。");
        return;
    }

    // 检测探针主程序是否存在，不存在则下载
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

    // 将解析出的配置信息写入到本地文件，留作以后的历史记忆
    fs.writeFileSync(configFile, `server: ${server}\nclient_secret: ${secret}\ntls: ${tls}\n`);
    log.info("✅ 新配置文件 nezha.yml 已保存。");
    
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

    // 尝试读取本地保存的环境变量
    if (fs.existsSync(envFile)) {
        userEnv = fs.readFileSync(envFile, 'utf8').trim();
        log.info(`✅ 读取到已保存的 Argosbx 环境变量配置: ${userEnv}`);
    } else {
        let skipInput = process.env.hypt || process.env.AUTO_RUN === 'true';
        if (!skipInput) {
            console.log('\n💡 [提示] 首次运行，请输入 Argosbx 环境变量。(如 hypt="123")');
            
            userEnv = await askQuestion("请输入 Argosbx 环境变量 > ");

            if (userEnv) {
                fs.writeFileSync(envFile, userEnv);
                log.info("✅ 环境变量已永久保存到本地，下次开机将自动读取，无需重复输入！");
            } else {
                log.warn("⚠️ 警告：你没有输入任何变量！直接按了回车。脚本稍后可能会报错💣。");
            }
        }
    }

    // 解析变量并应用到当前运行环境中
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
// 🏁 主函数 (Main) - 融入三级优先度与自定义变量解析
// ==========================================
async function main() {
    console.clear();
    console.log("====================================================");
    console.log("                 Container-Script (Node.js)         ");
    console.log("====================================================");

    // 【新增核心功能】：自动解析顶部配置的等号格式字符串
    if (CUSTOM_VARIABLES_STR) {
        // 第一步：用空格切开每一个独立的变量
        CUSTOM_VARIABLES_STR.split(' ').forEach(kv => {
            // 第二步：用等号将变量名和变量值拆分开
            const [key, val] = kv.split('=');
            if (key && val) {
                // 第三步：将多余的引号清理掉，然后正式装载到系统的环境池中
                process.env[key] = val.replace(/["']/g, ''); 
            }
        });
    }

    const unzipMode = checkDependencies();
    await setupPersistence();

    // =============== 探针三级优先度判定逻辑 ===============
    let finalNezhaCmd = "";    // 最终决定使用的指令
    let useOldConfig = false;  // 是否使用本地历史记忆文件
    
    // 倒计时设置常量
    const TIMEOUT_SECONDS = 15; 

    console.log("\n----------------------------------------------------");
    if (PRESET_NEZHA_COMMAND) {
        console.log("💡 [提示] 检测到代码预设指令 (优先级 2 准备就绪)");
    }
    if (fs.existsSync("nezha.yml")) {
        console.log("💡 [提示] 检测到本地历史配置 nezha.yml (优先级 3 准备就绪)");
    }
    
    console.log('----------------------------------------------------');
    console.log(`请选择操作 (${TIMEOUT_SECONDS}秒倒计时):`);
    console.log(`1. [粘贴] 输入新命令并回车 -> 使用新命令 (优先级最高)`);
    console.log(`2. [回车] 直接按回车        -> 跳过等待，使用预设或备份`);
    console.log(`3. [等待] 倒计时结束        -> 自动使用预设或备份`);
    console.log('----------------------------------------------------');

    // 交互输入：等待最多 15 秒（15000 毫秒）
    const userInput = await askQuestion("请输入新指令 > ", TIMEOUT_SECONDS * 1000);

    if (userInput && userInput.trim().length > 5) {
        // 【第一优先级】：用户当场手动输入了新指令
        log.info(">>> [来源] 使用控制台输入的指令 (优先级 1)。");
        finalNezhaCmd = userInput;
    } else if (PRESET_NEZHA_COMMAND) {
        // 【第二优先级】：没有输入，但代码顶部写死了预设指令
        console.log("\n>>> 倒计时结束或跳过。");
        log.info(">>> [来源] 使用代码预设指令 PRESET_NEZHA_COMMAND (优先级 2)。");
        finalNezhaCmd = PRESET_NEZHA_COMMAND;
    } else if (fs.existsSync("nezha.yml")) {
        // 【第三优先级】：没有输入，代码也没预设，但本地有以前运行生成的配置
        console.log("\n>>> 倒计时结束或跳过。");
        log.info(">>> [来源] 使用本地历史备份文件 nezha.yml (优先级 3)。");
        useOldConfig = true;
    } else {
        console.log("\n>>> 倒计时结束或跳过。");
        // 什么都没有，直接跳过探针
    }

    // 将裁决结果交给探针启动模块去执行
    await startNezha(finalNezhaCmd, unzipMode, useOldConfig);
    // ====================================================

    // 启动 Argosbx 业务子进程
    await startArgosbx();

    console.log("");
    log.step("正在启动后台保活进程 (Keep-Alive)...");
    // 保持进程不退出，每 3600 秒（1小时）空跑一次
    setInterval(() => {}, 3600 * 1000); 
}

// 捕获并打印全局错误，防止程序崩溃时没有任何提示
main().catch(err => console.error("运行出错:", err));
