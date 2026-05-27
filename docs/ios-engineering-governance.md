# 消费管家 iOS 工程治理说明

日期：2026-05-28
状态：工程结构基线
适用范围：不改变功能行为的工程整理、质量门禁、构建入口、仓库卫生

## 1. 工程边界

主工程固定为：

```sh
AwemeBillingApp/AwemeBillingApp.xcodeproj
```

主 scheme 固定为：

```sh
AwemeBillingApp
```

仓库内可能存在腾讯 OCR SDK 的 demo Xcode project，它只作为本地参考包存在，不作为消费管家的构建入口。任何脚本、文档和 CI 配置都应显式指向主工程，避免误扫 vendor demo。

## 2. 核心链路

后续工程调整优先保护这条链路：

```text
截图/文本/分享/快捷指令 -> ImportPipeline -> 候选复核 -> ExpenseMutationService -> ExpenseRecord -> 报告/提醒/统计刷新
```

非功能性改动不能绕过复核队列、不能改变去重策略、不能改变报告与通知的触发语义。

## 3. 仓库卫生

应提交：

- App、Share Extension、Tests 的源码和资源。
- `AwemeBillingApp.xcodeproj/project.pbxproj`。
- 共享 scheme：`AwemeBillingApp.xcodeproj/xcshareddata/xcschemes/AwemeBillingApp.xcscheme`。
- 产品、技术、版本和工程治理文档。
- 可复用脚本和快捷指令交付物。

不应提交：

- `DerivedData*`、`Build*`、`.module-cache/`、`.build/`。
- `xcuserdata/`、`project.xcworkspace/`、`*.xcuserstate`。
- 本地调试截图、模拟器截图、临时 OCR 样本。
- 真实 API key、Secret、个人签名状态。

## 4. Secret 管理

真实 Secret 只能来自本地环境变量、未追踪的 `LocalSecrets.xcconfig` 或 Xcode 本机配置。`Info.plist` 和 project build settings 只允许保留 `$(TENCENT_OCR_SECRET_ID)`、`$(TENCENT_OCR_SECRET_KEY)` 这类占位符。

提交前应确认：

```sh
rg -n "AKID[[:alnum:]]{16,}|sk-proj-[[:alnum:]_-]{20,}|AIza[[:alnum:]_-]{20,}|K[0-9]{10,}|JROA[[:alnum:]]{16,}" . --glob '!OCR_iOS_SDK_v*/**' --glob '!DerivedData*/**' --glob '!.module-cache/**' --glob '!.git/**'
```

命中真实 Secret 时必须先移除并重写相关提交历史，再 push。

## 5. 质量门禁

本地提交前建议运行：

```sh
scripts/quality_gate.sh
```

脚本覆盖：

- git tracked 文件类型检查。
- 真实 Secret 关键词扫描。
- `git diff --check`。
- 主工程 `build-for-testing`。

脚本默认把 Xcode 产物写入仓库内的 `DerivedData-quality-gate/`，避免依赖用户级 DerivedData 路径。该目录已被 `.gitignore` 的 `DerivedData*/` 规则覆盖。

如果后续新增 UI 测试或脱敏 OCR fixture，应把稳定、非网络依赖的测试加入该门禁。

## 6. 变更约束

- 只做工程整理时，不修改业务逻辑、数据模型、解析规则和 UI 文案。
- 需要改业务逻辑时，优先补单元测试覆盖导入、去重、报告边界和通知调度。
- 新增入口前先检查是否会和现有 tab 或快捷入口重复。
- 任何自动化导入入口只生成候选，不直接静默入账。
