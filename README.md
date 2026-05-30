# QS config hierarchy fixture

这是一个 orphan 分支上的 QS 测试组件库，用于验证 `recipe.yaml` 默认入口名和多级 `config.yaml` 参数覆盖规则。

## 覆盖场景

- 根目录 `recipe.yaml` 是默认 recipe，根目录 `config.yaml` 只是参数默认文件。
- `config.yaml` 从 repo 根目录开始逐级合并，子目录覆盖父目录。
- template 中 `# @arg` 的默认值覆盖目录 `config.yaml`。
- recipe 中的 repo 级、目录级、template 级参数覆盖前面所有默认值。
- `qs.templates` 同时覆盖完整 ID、多级相对 ID、两段 ID 和一段复用上下文 ID。
- 旧式 `arg` / `arg/<template>` config 仍可被读取。
- 隐藏目录、隐藏文件、目录内 `recipe.yaml` 和 `config.yaml` 不应被 `qs list templates` 当成 template。

## 验证命令

```sh
qs explain ./recipe.yaml --json
qs list templates ./recipe.yaml --json
qs render ./recipe.yaml -o ./_tmp-fixture.sh
```

也可以验证目录默认入口：

```sh
qs explain . --json
```

关键预期：

- `fixture/apps/backend/install.sh` 的 `shared` 默认值来自 template，不来自 `apps/backend/config.yaml`。
- `fixture/apps/backend/install.sh` 的 `recipe_override` 最终值来自 template 级 recipe 覆盖。
- `fixture/apps/backend/report.sh` 通过一段写法复用 `apps/backend` 目录上下文。
- `fixture/apps/frontend/build.sh` 通过多级相对写法解析到 `fixture/apps/frontend/build.sh`。
- `fixture/legacy/legacy.sh` 同时读取旧式 `arg` 和 `arg/legacy.sh`。
