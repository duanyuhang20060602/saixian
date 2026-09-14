# 三人 Git 协作约定

## 仓库与分支

- 仓库根目录：`qiansai`
- 长期分支：`main`
- `main` 只接收经过检查的合并，不直接开发。
- 每项工作从最新 `main` 建独立分支：
  - `fpga/<功能>`：FPGA HDL、时序和管脚约束
  - `hmi/<功能>`：陶晶驰界面与串口协议
  - `docs/<主题>`：文档、接线和测试记录
  - `fix/<问题>`：缺陷修复

示例：

```powershell
git switch main
git pull --ff-only
git switch -c fpga/uart-control
```

## 日常提交

一次提交只解决一个问题；提交前先检查：

```powershell
git status
git diff --check
git diff
```

提交信息使用简短动作描述，例如：

```text
fpga: add UART command receiver
hmi: add match control page
docs: document 5V level shifting
```

## 同步与合并

开发期间定期同步 `main`：

```powershell
git fetch origin
git rebase origin/main
```

推送自己的分支并创建 Pull Request，由另外一人检查后合并。不要在共享分支上使用强制推送，不要提交 TD 自动生成的数据库、日志、安装包和视频。

## 文件所有权建议

- FPGA 开发者主要维护 `saixian_fpga/lab_ex5_i2s/src/user_source/`。
- HMI 开发者主要维护 `saixian_fpga/lab_ex5_i2s/doc/hmi_ui/` 及串口协议文档。
- 集成/测试开发者维护测试、构建脚本、上板记录与合并验证。
- 修改公共顶层模块或管脚约束前先在群里说明，避免两个人同时修改同一文件。

## 构建产物

`.bit`、`.tft` 和测试视频不进入日常 Git 历史。需要交付时使用托管平台的 Release/附件，并标注对应提交号、TD/HMI 软件版本及验证硬件。

