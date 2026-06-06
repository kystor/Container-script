# Container-script

容器启动脚本，内置以下能力：

- 哪吒探针安装与启动
- Komari 探针安装与启动
- Argosbx 主脚本拉起
- 自动探测容器端口
- 环境变量透传到 `argosbx.sh`

## 远程安装

如果服务器有 `curl`，直接执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

如果服务器没有 `curl`，可以用：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## 启动前传参

你可以把环境变量直接写在远程命令前面。

例如：

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

这些变量会：

- 当前这次执行立即生效
- 继续透传给内部启动的 `argosbx.sh`
- 自动保存到 `$HOME/.container-script.env`
- 在重启后由自启任务重新加载

## Argosbx 透传说明

现在脚本支持你要的这种方式：

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

脚本内部会继续执行：

```bash
bash argosbx.sh rep
```

因为子进程会继承当前环境变量，所以 `hypt`、`tupt` 这类变量会自动传给 `argosbx.sh`。

## 容器端口检测

脚本会优先从下面这些环境变量里寻找容器端口：

- `SERVER_PORT`
- `PORT`
- `PANEL_PORT`
- `LISTEN_PORT`
- `APP_PORT`
- `WEB_PORT`
- `CONTAINER_PORT`
- `INTERNAL_PORT`

如果检测到有效端口，会自动导出：

- `SERVER_PORT`
- `PORT`
- `CONTAINER_PORT`
- `INTERNAL_PORT`
- `PANEL_PORT`

如果你没有手动传入 `hypt`，脚本还会把检测到的容器端口默认赋给 `hypt`。

## 哪吒用法

支持下面几种方式：

1. 运行脚本后手动粘贴哪吒官方命令
2. 通过 `NZ_CMD` 直接传入
3. 本地已有 `nezha.yml` 时直接复用

示例：

```bash
NZ_CMD='NZ_SERVER=example.com:5555 NZ_CLIENT_SECRET=your-secret NZ_TLS=false' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## Komari 用法

支持下面几种方式：

1. 运行脚本后手动粘贴 Komari 官方安装命令
2. 只传参数，比如 `-e https://example.com -t your-token`
3. 通过 `KOMARI_CMD` 直接传入
4. 本地已有 `komari-agent.args` 时直接复用

示例：

```bash
KOMARI_CMD='-e https://example.com -t your-token' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## 常用组合示例

只传 Argosbx 协议变量：

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

同时传 Argosbx 变量和 Komari 参数：

```bash
hypt="1" tupt="2" KOMARI_CMD='-e https://example.com -t your-token' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

同时传 Argosbx 变量和哪吒参数：

```bash
hypt="1" tupt="2" NZ_CMD='NZ_SERVER=example.com:5555 NZ_CLIENT_SECRET=your-secret NZ_TLS=false' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## 持久化行为

脚本会自动执行这些动作：

- 把远程 `start.sh` 同步到 `$HOME/start.sh`
- 把当前环境变量保存到 `$HOME/.container-script.env`
- 如果系统有 `crontab`，自动写入 `@reboot` 自启任务

这样服务器重启后，之前传进去的环境变量还能继续恢复并再次执行脚本。
