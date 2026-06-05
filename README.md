# QS config hierarchy fixture

这是一个 orphan 分支上的 QS 远程测试组件库，用于验证真实 GitHub repo/tree/blob/raw/git+ 输入、`recipe.yaml` 默认入口名、多级 `config.yaml` 参数覆盖规则和 repo cache 行为。

## 覆盖场景

- 根目录 `recipe.yaml` 是默认 recipe，根目录 `config.yaml` 只是参数默认文件。
- `config.yaml` 从 repo 根目录开始逐级合并，子目录覆盖父目录。
- template 中 `# @arg` 的默认值覆盖目录 `config.yaml`。
- recipe 中的 repo 级、目录级、template 级参数覆盖前面所有默认值。
- `qs.templates` 同时覆盖完整 ID、多级相对 ID、两段 ID 和一段复用上下文 ID。
- GitHub repo/tree 输入应下载 repo snapshot，并在 `render` / `run` 中默认读取根目录 `recipe.yaml`。
- GitHub blob/raw `recipe.yaml` 输入在需要 repo 上下文时应下载 repo snapshot，并让 `repos[].path: .` 指向 snapshot 根目录。
- `git+https://github.com/yuanboshe/qs-repo.git@test-repo` 应默认读取根目录 `recipe.yaml`。
- `recipes/context.yaml` 用于验证子目录 recipe 依赖 repo 上下文时，`repos[].path: .` 指向 snapshot 根目录。
- `recipes/remote-repo.yaml` 用于验证单文件 recipe 显式声明远程 repo。
- `recipes/remote-framework.yaml` 用于验证单文件 recipe 使用远程 framework file source。
- 隐藏目录、隐藏文件、目录内 `recipe.yaml` 和 `config.yaml` 不应被 `qs inspect` 当成 template。

## 手动验证命令

本地 fixture 验证：

```sh
qs inspect . --json
qs inspect ./recipe.yaml --json
qs render . -o ./_tmp-fixture.sh
```

真实远程验证：

```sh
qs inspect https://github.com/yuanboshe/qs-repo/tree/test-repo --json
qs render https://github.com/yuanboshe/qs-repo/tree/test-repo
qs render https://github.com/yuanboshe/qs-repo/blob/test-repo/recipe.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipe.yaml
qs render https://github.com/yuanboshe/qs-repo/blob/test-repo/recipes/context.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipes/remote-repo.yaml
qs render https://raw.githubusercontent.com/yuanboshe/qs-repo/test-repo/recipes/remote-framework.yaml
qs render git+https://github.com/yuanboshe/qs-repo.git@test-repo
qs render git+https://github.com/yuanboshe/qs-repo.git@test-repo//recipe.yaml
```

关键预期：

- `fixture/apps/backend/install.sh` 的 `shared` 默认值来自 template，不来自 `apps/backend/config.yaml`。
- `fixture/apps/backend/install.sh` 的 `recipe_override` 最终值来自 template 级 recipe 覆盖。
- `fixture/apps/backend/report.sh` 通过一段写法复用 `apps/backend` 目录上下文。
- `fixture/apps/frontend/build.sh` 通过多级相对写法解析到 `fixture/apps/frontend/build.sh`。
- `fixture/legacy/legacy.sh` 读取 `legacy/config.yaml.args`，并允许 recipe 覆盖 template 声明参数。
