# qs-repo

quick-setup 组件仓库。当前根 recipe 默认用于安装和验证 Docker 环境。

## Docker 环境

本仓库根目录 `recipe.yaml` 会按顺序执行：

1. `docker/install_docker.sh`：通过 Docker apt 源安装 Docker Engine、Buildx 和 Compose plugin。
2. `docker/configure_docker_daemon.sh`：合并更新 `/etc/docker/daemon.json`，配置日志轮转、`live-restore`，并实时测速 Docker Hub mirror 后写入最快可用源；失败自动回滚。
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
  registry_mirrors: auto
  mirror_verify_image: hello-world

repo/docker/verify_docker.sh:
  run_hello_world: "true"
```

### Docker Hub mirror 自动测速

国内服务器拉取 Docker Hub image 时，固定写死某个 mirror 不可靠：公开列表只能作为候选池，某个源是否可用、是否快，必须以目标主机当时的实时测试为准。`docker/configure_docker_daemon.sh` 在 `registry_mirrors: auto` 时会先测试 Docker Hub 直连，再测试候选源的 `/v2/` 和 `library/<test-image>:latest` manifest，按多轮请求耗时中位数排序。只有直连失败，或 mirror 至少比直连快 `20%`（可通过 `--min-speedup-percent` 调整）时，才把最快 Top N 写入 `registry-mirrors`；否则移除该字段，保持 Docker Hub 直连。

脚本安全边界：

- 只合并更新 `/etc/docker/daemon.json` 的日志、`live-restore` 和 `registry-mirrors` 相关字段，保留其他 JSON 字段。
- 写入前校验原文件 JSON；非法 JSON 不覆盖。
- 旧文件备份到 `/etc/docker/daemon-backup/daemon.json.YYYYmmdd-HHMMSS.bak`。
- 写入后执行 `systemctl daemon-reload`、`systemctl restart docker`、`docker info` 和 `docker pull <verify-image>`。
- 重启、`docker info` 或 pull 验证失败时，自动恢复最近备份并重启 Docker。
- 内置候选源只是 fallback；复杂排查时可通过脚本 CLI 传入 `--candidate-file`、`--remote-url` 或位置参数追加候选源。
- QS 暴露的 template 参数保持精简；`--top`、`--rounds`、`--min-speedup-percent`、`--connect-timeout`、`--max-time` 和 `--test-image` 只作为脚本 CLI 诊断参数，不进入默认 recipe。

单独 dry-run 测速：

```sh
sudo ./docker/configure_docker_daemon.sh --dry-run
```

真实应用：

```sh
sudo ./docker/configure_docker_daemon.sh --yes
sudo ./docker/configure_docker_daemon.sh \
  --candidate-file ./mirror_candidates.txt \
  --top 3 \
  --rounds 3 \
  --min-speedup-percent 20 \
  --test-image alpine \
  --verify-image hello-world \
  --yes
```

回滚方式：

```sh
sudo cp /etc/docker/daemon-backup/daemon.json.YYYYmmdd-HHMMSS.bak /etc/docker/daemon.json
sudo systemctl daemon-reload
sudo systemctl restart docker
```

限制：脚本不会静默安装缺失依赖；目标机需要已有 `bash`、`curl`、`python3`、`docker` 和 `systemctl`。`--dry-run` 不修改系统。

## 本次 Ubuntu 24.04 验证记录

- 原 Docker 脚本依赖未定义变量或函数：`WORK_PATH`、`GH_PROXY`、`printLine`。现在 template 不再依赖外部运行目录和隐式代理变量。
- 原 Docker 脚本使用 `curl -fsSL https://get.docker.com | bash`，审查和复现边界不清晰。现在改为显式 apt keyring、apt source 和包安装步骤。
- Ubuntu 24.04 VM 中 `download.docker.com` 的 GPG 下载曾出现 `Connection reset by peer`。现在 GPG 下载带重试，并支持 `apt_mirror_fallbacks` 自动切换镜像源。
- Docker Hub 拉取在国内网络下不稳定。现在 `docker/configure_docker_daemon.sh` 会以目标主机实时测速结果写入最快可用 mirror，并在验证失败时自动回滚。
- Docker Compose 不再下载固定版本独立二进制，默认安装 Docker 官方 Compose v2 plugin，并按需提供 `docker-compose` 兼容 wrapper。
- `hello-world` 拉取测试容易受 Docker Hub 网络影响，因此默认只验证 daemon 和 Compose；需要端到端镜像拉取时再把 `run_hello_world` 设为 `"true"`。
- 已在 Vagrant Ubuntu 24.04.3 LTS 中验证通过：Docker Engine `29.5.2`、Docker Compose plugin `v5.1.4`、`docker` 组权限、`docker-compose` wrapper 和 `/etc/docker/daemon.json`。
