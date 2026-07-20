# PQM双项目目录与RTL清理实施计划

**目标：** 完成`backup_pl/project`目录分离，并让`project`只保留PS架构所需代码。

**方法：** 先保存旧工作树，再根据默认PS综合日志删除未使用RTL，提取必要IP和
约束，最后重新执行完整构建。

## 任务1：验证目录和Git工作树

- [x] 检查`backup_pl`为`main`分支。
- [x] 检查`project`为`codex/ps-freertos-migration`分支。
- [x] 检查LVGL子模块状态。

## 任务2：提取新工程IP和约束

- [x] 创建`FPGA/ip`。
- [x] 保留四个已进入默认PS网表的XCI配置。
- [x] 将`PQM.xdc`移到`FPGA/data/PQM.xdc`。
- [x] 修改`create_pqm_soc_project.tcl`使用新路径。

## 任务3：删除PL兼容显示链

- [x] 将`pqm_legacy_core`整理并重命名为`pqm_pl_core`。
- [x] 删除`LEGACY_PL_DISPLAY`参数和生成分支。
- [x] 删除PL LCD、触摸、UART、GraphicsLoad及显示专用辅助模块。
- [x] 删除双模式综合脚本。

## 任务4：删除旧Vivado工程副本

- [x] 从`project`删除`FPGA/prj`。
- [x] 确认`backup_pl/FPGA/prj/PQM.xpr`仍存在。

## 任务5：同步中文文档

- [x] 更新`project_progress_summary.md`。
- [x] 更新`rtl_file_overview.md`。
- [x] 更新`ps_pl_interface.md`、ARM说明和代码总览。
- [x] 删除仅描述已移除PL显示/UART的文档。

## 任务6：重新验证

- [x] 运行`FPGA/scripts/run_xsim.ps1 -All`。
- [x] 运行`ARM/tests/run_tests.ps1`。
- [x] 重新创建并构建Vivado SoC工程。
- [x] 运行时序和资源门限检查。
- [x] 重新生成FreeRTOS ELF、FSBL和`BOOT.bin`。
- [x] 执行`git diff --check`和路径一致性检查。
