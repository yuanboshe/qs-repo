# QS remote fixture repo

这是 `yuanboshe/qs-repo@test-repo` 的远程契约测试分支。它不是生产组件库，而是给 QS 验证 GitHub tree/repo/blob/raw、`git+`、repo cache、file cache、recipe 重写、template inspect、render 和 search 的稳定夹具。

## 覆盖场景

- 根目录 `recipe.yaml` 是默认 recipe，根目录 `config.yaml` 是全 repo template 默认上下文。
- `config.yaml` 从 repo 根目录开始逐级合并，子目录覆盖父目录。
- `metadata.description`、`platform`、`shell`、`requires`、`effects` 和 `network` 覆盖规则可通过 `apps/backend/config_metadata.sh` 检查。
- `metadata.network: []` 用于验证子目录可以清空父级列表型 metadata。
- template 必须在头部声明 `# @qs template`，只有带该标识的脚本进入 inspect/search 输出。
- framework 脚本在头部声明 `# @qs framework`，可被 recipe 使用但不应进入 template index。
- template 中 `# @description`、`# @step`、`# @arg` 和 metadata 标记进入 inspect/search 输出。
- `# @arg` 覆盖目录默认值，空字符串默认值、自引用参数、引号和无引号赋值都保留。
- recipe 中的 repo 级、目录级、template 级参数覆盖前面所有默认值。
- `qs.templates` 覆盖完整 ID、多级相对 ID、两段 ID、一段复用上下文 ID 和多 repo 上下文复用。
- `tools/install.sh` 和 `apps/backend/install.sh` 共享 basename，用于验证 `qs inspect <repo> install.sh` 的歧义错误。
- `fixtures/secondary-repo/` 用于 `recipe-cases/multi-repo/recipe.yaml` 验证单个 recipe 选择多个 repo root。
- `network/fetch.sh` 用于验证 `# @network`、下载参数和风险信息被 inspect/search 捕获；它不会执行真实网络 IO。
- `platforms/alpine/install.sh` 用于验证 `qs inspect --platform` 和 `--shell` 过滤。
- `helpers/internal.sh` 是非隐藏但未声明 `# @qs template` 的普通脚本，不应被 repo inspect/search 收录。
- `frameworks/strict.sh` 是子目录 framework，不应被 repo inspect/search 收录。
- `registry.yaml`、`registries/*.yaml` 和 `.qs/index.json` 用于验证 `qs search` 的远程 registry 和 index-first 读取。
- `registry-with-warning.yaml` 用于验证 registry 中 repo-file source 会产生 warning 且不阻断其他 repo。
- GitHub repo/tree 输入应下载 repo snapshot，并在 `render` / `run` 中默认读取根目录 `recipe.yaml`。
- GitHub blob/raw recipe 输入在需要 repo 上下文时应下载 repo snapshot，并让 `repos[].path: .` 指向 snapshot 根目录。
- `git+https://github.com/yuanboshe/qs-repo.git@test-repo` 应默认读取根目录 `recipe.yaml`。
- `recipes/context.yaml` 验证子目录 recipe 依赖 repo 上下文。
- `recipes/remote-repo.yaml` 验证单文件 recipe 显式声明 GitHub tree repo source。
- `recipe-cases/*/recipe.yaml` 放新增远程 recipe 场景，文件名固定为 `recipe.yaml`，避免被 repo inspect 当成 template。
- `recipe-cases/remote-git-repo/recipe.yaml` 验证单文件 recipe 显式声明 `git+` repo source。
- `recipes/remote-framework.yaml` 验证单文件 recipe 使用 GitHub raw framework file source。
- `recipe-cases/git-framework/recipe.yaml` 验证单文件 recipe 使用 `git+...//framework.sh` framework source。
- `recipe-cases/repo-framework/recipe.yaml` 验证 recipe 可以使用 repo 内 `frameworks/strict.sh` framework。
- `recipe-cases/unmarked-template/recipe.yaml` 是负例：未声明 `# @qs template` 的 helper 不应被当作 template。
- `recipe-cases/framework-as-template/recipe.yaml` 是负例：声明 `# @qs framework` 的文件不应被当作 template。
- `apps/backend/recipe.yaml` 是可直接寻址的子目录 recipe，同时不应被 repo inspect 当成 template。
- 隐藏目录、隐藏文件、目录内 `recipe.yaml`、目录内 `config.yaml`、未标记普通脚本、framework 脚本和 `.qs/index.json` 不应被 `qs inspect` 当成 template。

## 本地验证

从 quick-setup 工程根目录执行：

```sh
go run . inspect ./_tmp/qs-repo-test-repo --json
go run . inspect ./_tmp/qs-repo-test-repo ./apps/backend/config_metadata.sh --json
go run . inspect ./_tmp/qs-repo-test-repo install.sh
go run . render ./_tmp/qs-repo-test-repo -o ./_tmp/qs-repo-test-repo/_tmp-fixture.sh
go run . inspect ./_tmp/qs-repo-test-repo --json -o
```

`install.sh` 的单段 inspect 应返回歧义错误；这是预期场景。

## 真实远程验证

推送 `test-repo` 后执行：

```sh
qs inspect https://github.com/yuanboshe/qs-repo/tree/test-repo --json
qs inspect https://github.com/yuanboshe/qs-repo/tree/test-repo qs-repo/apps/backend/install.sh --json
qs inspect https://github.com/yuanboshe/qs-repo/tree/test-repo install.sh
qs inspect https://github.com/yuanboshe/qs-repo/tree/test-repo --platform linux/alpine --json
qs inspect https://github.com/yuanboshe/qs-repo/tree/test-repo --shell sh --json
qs render https://github.com/yuanboshe/qs-repo/tree/test-repo
qs render https://github.com/yuanboshe/qs-repo/blob/test-repo/recipe.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipe.yaml
qs render https://github.com/yuanboshe/qs-repo/blob/test-repo/recipes/context.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipes/remote-repo.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipe-cases/remote-git-repo/recipe.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipes/remote-framework.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipe-cases/git-framework/recipe.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipe-cases/repo-framework/recipe.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipe-cases/network/recipe.yaml
qs render git+https://github.com/yuanboshe/qs-repo.git@test-repo
qs render git+https://github.com/yuanboshe/qs-repo.git@test-repo//recipe.yaml
```

Search 验证示例：

```sh
mkdir -p _tmp/qs-home-search
printf 'registries:\n  - source: https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/registry.yaml\n' > _tmp/qs-home-search/config.yaml
QS_HOME=_tmp/qs-home-search qs search network --json
printf 'registries:\n  - source: https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/registries/stable.yaml\n' > _tmp/qs-home-search/config.yaml
QS_HOME=_tmp/qs-home-search qs search backend --json
```

关键预期：

- `fixture/apps/backend/install.sh` 的 `shared` 默认值来自 template，不来自 `apps/backend/config.yaml`。
- `fixture/apps/backend/install.sh` 的 `recipe_override` 最终值来自 template 级 recipe 覆盖。
- `fixture/apps/backend/report.sh` 通过一段写法复用 `apps/backend` 目录上下文。
- `fixture/apps/frontend/build.sh` 通过多级相对写法解析到 `fixture/apps/frontend/build.sh`。
- `fixture/tools/install.sh` 的 `empty_value` 渲染为空字符串，`self_reference_value` 可被 recipe 覆盖。
- `fixture/apps/backend/config_metadata.sh` 的说明来自 `apps/backend/config.yaml.metadata.description`。
- `fixture/legacy/legacy.sh` 读取 `legacy/config.yaml.args`，并允许 recipe 覆盖隐式自引用参数。
- `qs search network --json` 应命中 `network/fetch.sh`，并优先使用远程 `.qs/index.json`。
- `qs inspect <repo> --json` 不应包含 `helpers/internal.sh`、`frameworks/strict.sh` 或 `recipes/*.yaml`。
- `recipe-cases/unmarked-template/recipe.yaml` 和 `recipe-cases/framework-as-template/recipe.yaml` 应返回 template 类型校验错误。
