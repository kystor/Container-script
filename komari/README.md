# Container-script

容器启动脚本，当前集成了以下能力：

- 哪吒探针安装与启动
- Komari 探针安装与启动
- Argosbx 主业务脚本启动
- 自动探测容器平台分配端口
- 环境变量透传给 `argosbx.sh`

## 远程安装

如果服务器有 `curl`，直接执行：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

如果服务器没有 `curl`，可以使用：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## 启动前传入环境变量

你可以把环境变量直接写在远程命令前面。

例如：

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

这些变量会：

- 当前执行立即生效
- 被 `start.sh` 继续传给内部启动的 `argosbx.sh`
- 参与脚本后续流程，例如协议变量判断

## 末尾参数透传给 Argosbx

`start.sh` 不需要自己识别 `rep`、`del`、`list`、`res`、`upx`、`ups` 这些具体命令。

它现在的规则很简单：

- 如果你在命令末尾带了参数，就原样透传给 `argosbx.sh`
- 如果你没有带参数，就默认执行 `rep`

也就是说：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) ups
```

内部实际等价于：

```bash
bash argosbx.sh ups
```

而下面这条：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) list
```

内部实际等价于：

```bash
bash argosbx.sh list
```

如果末尾不写参数：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

就会默认执行：

```bash
bash argosbx.sh rep
```

所以下面两种写法等价：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) rep
```

## 常用命令示例

调整变量并使用默认 `rep`：

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

调整变量并显式执行 `rep`：

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) rep
```

查看节点信息：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) list
```

卸载：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) del
```

重启：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) res
```

升级 Xray 内核：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) upx
```

升级 Singbox 内核：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) ups
```

## 容器端口检测

脚本会优先从下面这些环境变量中寻找容器端口：

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
2. 通过环境变量 `NZ_CMD` 直接传入
3. 本地已有 `nezha.yml` 时直接复用

示例：

```bash
NZ_CMD='NZ_SERVER=example.com:5555 NZ_CLIENT_SECRET=your-secret NZ_TLS=false' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## Komari 用法

支持下面几种方式：

1. 运行脚本后手动粘贴 Komari 官方安装命令
2. 只传参数，例如 `-e https://example.com -t your-token`
3. 通过环境变量 `KOMARI_CMD` 直接传入
4. 本地已有 `komari-agent.args` 时直接复用

示例：

```bash
KOMARI_CMD='-e https://example.com -t your-token' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## 持久化说明

当前脚本会自动做这些事情：

- 把远程 `start.sh` 同步到 `$HOME/start.sh`
- 尝试设置开机自启
- 继续复用当前环境变量和已有本地配置
```
