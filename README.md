# qs-repo

quick-setup 组件仓库。当前根 recipe 默认用于安装和验证 Docker 环境。

## Docker 环境

本仓库根目录 `recipe.yaml` 会按顺序执行：

1. `docker/install_docker.sh`：通过 Docker apt 源安装 Docker Engine、Buildx 和 Compose plugin。
2. `docker/configure_docker_daemon.sh`：写入 `/etc/docker/daemon.json`，配置日志轮转、`live-restore` 和可选 registry mirror。
3. `docker/install_docker_compose.sh`：确认 Compose v2 plugin 可用，并可创建 `docker-compose` 兼容 wrapper。
4. `docker/verify_docker.sh`：输出 Docker、daemon 和 Compose 验证信息。

每个 template 都通过 `# @platform`、`# @shell`、`# @requires`、`# @effects` 和 `# @network` 注释声明适配边界。Agent 应优先通过 `qs inspect template --json` 或 `qs list templates --json` 读取这些元数据，而不是依赖组件目录内的说明文件。

生成并审查脚本：

```sh
qs explain ./recipe.yaml
qs render ./recipe.yaml -o ./quick-setup-docker.sh
```

确认脚本后在目标服务器执行：

```sh
bash ./quick-setup-docker.sh
```

常用覆盖示例：

```yaml
repo/docker/install_docker.sh:
  apt_mirror: https://mirrors.aliyun.com/docker-ce/linux/ubuntu
  docker_users: auto

repo/docker/configure_docker_daemon.sh:
  registry_mirrors: https://mirror.example.com

repo/docker/verify_docker.sh:
  run_hello_world: "true"
```

## 本次 Ubuntu 24.04 验证记录

- 原 Docker 脚本依赖未定义变量或函数：`WORK_PATH`、`GH_PROXY`、`printLine`。现在 template 不再依赖外部运行目录和隐式代理变量。
- 原 Docker 脚本使用 `curl -fsSL https://get.docker.com | bash`，审查和复现边界不清晰。现在改为显式 apt keyring、apt source 和包安装步骤。
- Ubuntu 24.04 VM 中 `download.docker.com` 的 GPG 下载曾出现 `Connection reset by peer`。现在 GPG 下载带重试，并支持 `apt_mirror_fallbacks` 自动切换镜像源。
- Docker Compose 不再下载固定版本独立二进制，默认安装 Docker 官方 Compose v2 plugin，并按需提供 `docker-compose` 兼容 wrapper。
- `hello-world` 拉取测试容易受 Docker Hub 网络影响，因此默认只验证 daemon 和 Compose；需要端到端镜像拉取时再把 `run_hello_world` 设为 `"true"`。
- 已在 Vagrant Ubuntu 24.04.3 LTS 中验证通过：Docker Engine `29.5.2`、Docker Compose plugin `v5.1.4`、`docker` 组权限、`docker-compose` wrapper 和 `/etc/docker/daemon.json`。
