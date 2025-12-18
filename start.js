const { spawn, execSync } = require('child_process');
const readline = require('readline');
const fs = require('fs');
const path = require('path');

// ==========================================
// 🛠️ 全局配置区
// ==========================================

// [优先级 2] (代码预设) 如果你有哪吒指令需求，请在双引号中输入哪吒指令
const PRESET_NEZHA_COMMAND = ""; 

// 🟢 【修改处】：在这里填入你的环境变量字符串
// 格式要求：变量名="值"，多个变量用空格隔开
const CUSTOM_ENV_INPUT = 'hypt=""'; 

// 🟢 【初始化】：锁定工作目录
// 解释：确保脚本不管在哪里启动，都以当前文件所在目录为工作中心，防止找不到文件
try {
    process.chdir(__dirname);
    console.log(`>>> [初始化] 工作目录已锁定至: ${__dirname}`);
} catch (err) {
    console.error(`>>> [错误] 无法切换工作目录: ${err}`);
}

// 🟢 【环境解析模块】：自动解析上面的 CUSTOM_ENV_INPUT 并注入系统
(function parseAndLoadEnv() {
    if (!CUSTOM_ENV_INPUT) return;
    console.log('\n>>> [环境] 正在加载自定义变量...');
    
    // 正则提取 变量名=值 (支持带双引号或不带引号的值)
    const regex = /(\w+)=(?:"([^"]*)"|(\S+))/g;
    let match;
    
    while ((match = regex.exec(CUSTOM_ENV_INPUT)) !== null) {
        const key = match[1];
        const value = match[2] || match[3];
        process.env[key] = value; 
        console.log(`    + 成功设置: ${key} = ${value}`);
    }
    console.log('>>> [环境] 加载完毕。\n');
})();


const TIMEOUT_SECONDS = 20;       // 倒计时等待时间 (秒)
const CONFIG_FILE_YAML = 'nezha.yml';     // 探针配置文件名
const BACKUP_FILE = 'nezha_config.json';  // 配置备份文件名

// ==========================================
// 0. 🔌 开机自启功能模块
// ==========================================
function addSelfToStartup() {
    console.log('\n>>> [自启] 正在检查开机自启配置...');
    const nodePath = process.execPath;
    const scriptPath = path.resolve(__filename);
    const scriptDir = path.dirname(scriptPath);
    const command = `@reboot cd "${scriptDir}" && "${nodePath}" "${scriptPath}" > /dev/null 2>&1 &`;

    try {
        let currentCrontab = '';
        try {
            currentCrontab = execSync('crontab -l', { encoding: 'utf8' }).trim();
        } catch (e) { currentCrontab = ''; }

        if (currentCrontab.includes(scriptPath)) {
            console.log('>>> [自启] ✅ 检测到已添加过开机自启，跳过写入。');
            return;
        }

        const newCrontab = currentCrontab + '\n' + command + '\n';
        const child = spawn('crontab', ['-']);
        child.stdin.write(newCrontab);
        child.stdin.end();

        child.on('close', (code) => {
            if (code === 0) {
                console.log('>>> [自启] ✅ 成功将脚本加入开机自动启动！');
            } else {
                console.error('>>> [自启] ❌ 添加失败，退出码:', code);
            }
        });

    } catch (err) {
        console.error('>>> [自启] ❌ 设置失败:', err.message);
    }
}

// ==========================================
// 1. 🚀 启动主业务 (Argosbx)
// ==========================================
function startMainScript() {
    console.log('\n====================================================');
    console.log('>>> [主程序] 正在检查主业务脚本 (argosbx.sh) ...');
    console.log('====================================================');
    
    const scriptName = 'argosbx.sh';
    const scriptUrl = 'https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh';

    // 🟢 【新增逻辑】：如果文件不存在，则自动下载
    if (!fs.existsSync(`./${scriptName}`)) {
        console.log(`>>> [警告] 未检测到 ${scriptName} 文件。`);
        console.log(`>>> [下载] 正在从 GitHub 拉取最新版本...`);
        
        try {
            // 使用 curl -L -o 将远程代码保存为本地文件
            execSync(`curl -L -o ${scriptName} ${scriptUrl}`, { stdio: 'inherit' });
            console.log('>>> [下载] ✅ 下载成功！');
        } catch (e) {
            console.error('>>> [错误] ❌ 下载失败！请检查服务器网络连接。');
            console.error('    请尝试手动执行: bash <(curl -Ls ... )');
            return;
        }
    } else {
        console.log(`>>> [检测] ✅ 文件 ${scriptName} 已存在，准备启动。`);
    }

    // 给予脚本执行权限
    try { execSync(`chmod +x ./${scriptName}`); } catch(e) {}

    // 启动 bash 脚本，继承当前的环境变量 (process.env)
    console.log('>>> [启动] 正在执行脚本...');
    const shProcess = spawn('bash', [`./${scriptName}`], {
        stdio: 'inherit', 
        env: process.env  
    });

    shProcess.on('exit', (code) => {
        console.log(`\n[注意] argosbx.sh 已退出 (代码: ${code})`);
        console.log('>>> 脚本进入无限保活模式，防止容器退出...');
    });
}

// ==========================================
// 2. 🛡️ 哪吒探针安装与启动逻辑
// ==========================================
function startNezha(server, secret, tls, forceUUID) {
    if (!server || !secret) {
        console.log('>>> [跳过] 缺少探针参数，不启动哪吒探针。');
        return;
    }

    console.log(`\n>>> [探针] 准备启动哪吒探针...`);
    console.log(`    服务器: ${server}`);
    
    // --- 下载部分 ---
    let archCode = process.arch === 'x64' ? 'amd64' : 'arm64';
    const binFile = 'nezha-agent';
    const downloadUrl = `https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${archCode}.zip`;

    if (!fs.existsSync(binFile)) {
        if (fs.existsSync('nezha.zip')) { try { execSync('rm -rf nezha.zip'); } catch(e){} }
        console.log(`>>> [下载] 正在下载适配 ${archCode} 的探针...`);
        try {
            execSync(`curl -L -o nezha.zip ${downloadUrl}`, { stdio: 'inherit' });
            execSync(`unzip -o nezha.zip`, { stdio: 'inherit' });
            execSync(`chmod +x ${binFile}`);
            console.log('>>> [下载] 完成并已授权！');
        } catch (err) {
            console.error('\n>>> [错误] 下载或解压失败！请检查网络。');
            return;
        }
    }

    // --- 配置部分 ---
    let finalConfigContent = `server: ${server}\nclient_secret: ${secret}\ntls: ${tls}\n`;
    let useOldConfig = false; 

    const cleanStr = (str) => String(str || '').replace(/['"]/g, '').trim();
    const isTrue = (val) => {
        const s = String(val).toLowerCase().replace(/['"]/g, '').trim();
        return s === 'true' || s === '1' || s === 'on';
    };

    if (forceUUID) {
        finalConfigContent += `uuid: ${forceUUID}\n`;
    } 
    else if (fs.existsSync(CONFIG_FILE_YAML)) {
        try {
            const oldContent = fs.readFileSync(CONFIG_FILE_YAML, 'utf8');
            const oldServerMatch = oldContent.match(/(?:^|\n)\s*server:\s*([^#\n\r]+)/i);
            const oldSecretMatch = oldContent.match(/(?:^|\n)\s*client_secret:\s*([^#\n\r]+)/i);
            const oldTlsMatch = oldContent.match(/(?:^|\n)\s*tls:\s*([^#\n\r]+)/i);
            const oldUuidMatch = oldContent.match(/(?:^|\n)\s*uuid:\s*([a-zA-Z0-9-]+)/i);

            if (oldServerMatch && oldSecretMatch && oldTlsMatch && oldUuidMatch) {
                const isServerSame = cleanStr(oldServerMatch[1]) === cleanStr(server);
                const isSecretSame = cleanStr(oldSecretMatch[1]) === cleanStr(secret);
                const isTlsSame = isTrue(oldTlsMatch[1]) === isTrue(tls);

                if (isServerSame && isSecretSame && isTlsSame) {
                    finalConfigContent += `uuid: ${oldUuidMatch[1]}\n`;
                    useOldConfig = true;
                }
            }
        } catch(e) {}
    }

    fs.writeFileSync(CONFIG_FILE_YAML, finalConfigContent);
    
    console.log('>>> [启动] 正在拉起 nezha-agent 进程...');
    
    const agentProcess = spawn(`./${binFile}`, ['-c', CONFIG_FILE_YAML], {
        stdio: 'inherit', 
        env: process.env
    });

    agentProcess.on('exit', (code) => {
        if (code !== 0) console.error(`\n>>> [警告] 哪吒探针异常退出 (代码: ${code})。`);
    });
}

// ==========================================
// 3. ⚙️ 参数解析模块
// ==========================================
function parseCommand(input) {
    if (!input) return null;
    const serverMatch = input.match(/NZ_SERVER=([\w\.:-]+)/);
    const secretMatch = input.match(/NZ_CLIENT_SECRET=([\w-]+)/);
    const tlsMatch = input.match(/NZ_TLS=(true|false)/i); 
    const uuidMatch = input.match(/NZ_UUID=([\w-]+)/);

    if (serverMatch && secretMatch) {
        return {
            server: serverMatch[1],
            secret: secretMatch[1],
            tls: tlsMatch ? tlsMatch[1] : 'false',
            uuid: uuidMatch ? uuidMatch[1] : null 
        };
    }
    return null;
}

// ==========================================
// 4. 🏁 主入口函数
// ==========================================
(async function main() {
    console.clear();
    console.log('====================================================');
    console.log('        多功能启动脚本 (含自启/自动下载)');
    console.log('====================================================');

    // 🟢 检查并设置开机自启
    addSelfToStartup();

    let presetConfig = parseCommand(PRESET_NEZHA_COMMAND);
    let backupConfig = null;
    
    if (fs.existsSync(BACKUP_FILE)) {
        try { backupConfig = JSON.parse(fs.readFileSync(BACKUP_FILE, 'utf8')); } catch (e) {}
    }

    if (presetConfig) console.log(`[提示] 代码预设: ${presetConfig.server}`);
    if (backupConfig) console.log(`[提示] 本地备份: ${backupConfig.server}`);

    console.log('----------------------------------------------------');
    console.log(`请选择操作 (${TIMEOUT_SECONDS}秒倒计时):`);
    console.log(`1. [粘贴] 输入新命令并回车 -> 使用新命令 (优先级最高)`);
    console.log(`2. [回车] 直接按回车         -> 跳过等待，使用预设或备份`);
    console.log(`3. [等待] 倒计时结束         -> 自动使用预设或备份`);
    console.log('----------------------------------------------------');

    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    const getUserInput = () => {
        return new Promise((resolve) => {
            let isResolved = false;
            const timer = setTimeout(() => {
                if (!isResolved) {
                    console.log('\n>>> 倒计时结束，自动继续...');
                    isResolved = true;
                    rl.close();
                    resolve(null);
                }
            }, TIMEOUT_SECONDS * 1000);

            rl.question('请输入 > ', (answer) => {
                if (!isResolved) {
                    clearTimeout(timer); 
                    isResolved = true;
                    rl.close();
                    resolve(answer.trim());
                }
            });
        });
    };

    const input = await getUserInput();
    let finalConfig = null;

    if (input && input.length > 5) {
        const consoleConfig = parseCommand(input);
        if (consoleConfig) {
            console.log('>>> [来源] 使用控制台输入的命令。');
            finalConfig = consoleConfig;
            fs.writeFileSync(BACKUP_FILE, JSON.stringify(finalConfig));
        }
    }

    if (!finalConfig && presetConfig) finalConfig = presetConfig;
    if (!finalConfig && backupConfig) finalConfig = backupConfig;

    if (finalConfig) {
        startNezha(finalConfig.server, finalConfig.secret, finalConfig.tls, finalConfig.uuid);
    } else {
        console.log('>>> [提示] 未找到配置，仅启动主业务。');
    }

    startMainScript();
    
    setInterval(() => {}, 1 << 30);
})();
