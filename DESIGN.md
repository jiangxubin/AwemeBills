# 消费管家设计与工程方案

状态：与当前代码同步  
最低系统：iOS 17  
实现：SwiftUI + SwiftData + App Intents + Share Extension

## 1. 本轮审计结论

### 已发现的问题

1. 文档和版本漂移：旧文档仍围绕 0.2.x/0.3，工程已是 1.0.1。
2. 信息架构断链：报告页面已有实现却没有入口；场景分析页面没有入口却仍参与编译。
3. 总览职责过重：预算、柱图、饼图、方向和样式设置混在一个 1156 行页面中。
4. 导入主次倒置：新增导入位于待复核队列之前，用户导入后仍需向下寻找结果。
5. 明细缺少搜索：已有多种筛选，但无法直接按商户或备注定位。
6. 设置暴露实现：识别供应商和配置状态直接面向普通用户。
7. 视觉噪声：卡片阴影和渐变没有承载状态含义，降低账本信息的扫描效率。
8. 工程配置冗余：纯 Swift 工程仍设置 C++20；测试 target 使用手工 `OTHER_LDFLAGS` 链接 App 调试动态库。
9. 模拟器架构不明确：Xcode destination 同时报告 arm64/x86_64 候选，质量门禁没有校验实际产物。
10. 文件体量偏大：两个解析器、核心测试和部分页面仍超过千行，后续修改风险较高。

### 本轮已处理

- 总览重写为本月状态、预算、最近记录和记一笔。
- 报告恢复为主 tab，分析只保留在报告。
- 待复核队列前置，明细增加原生搜索。
- 我的页改成用户语言的隐私说明，并增加版本历史。
- 删除未使用的场景分析页面、复杂总览图表和高级图表设置。
- 卡片改为无阴影实体表面，进度与徽标使用纯色。
- 模拟器 target 固定 arm64，删除 C++20 与手工 linker override。

## 2. 交互设计

### 2.1 总览

目标：五秒内回答“本月花了多少、预算怎样、最近记了什么”。

```text
总览
  本月支出
  金额 / 记录数 / 主要分类
  [记一笔]

  预算
  日  已花 / 预算 / 进度
  周  已花 / 预算 / 进度
  月  已花 / 预算 / 进度

  最近记录
  商户 / 分类与渠道 / 金额与时间
```

- 加号和“记一笔”进入同一手动录入流程。
- 预算行整行可点，未设置时显示“设置”，不伪装成已启用预算。
- 不出现图表类型、方向、空心/实心等展示偏好。

### 2.2 明细

- 搜索使用系统 `.searchable`，覆盖商户、分类、场景、渠道和备注。
- 搜索可以和月份、分类、场景、渠道同时生效。
- 多选模式只在有记录时出现，批量删除必须二次确认。
- 金额使用等宽数字；商户标识、主信息和时间保持稳定列宽。

### 2.3 导入

- 页面顺序固定为“待复核 -> 新增导入”。
- 待复核摘要始终显示真实数量、最近来源和时间。
- 当前批次与全部待复核只有在确实存在差异时才显示切换控件。
- 截图、文本和手动是三种输入方式，共用同一个结果队列。
- 临时提示只作为队列补充，不替代候选内容。

### 2.4 报告

- 周期使用分段控件；日、周、月、季、年保持同一结构。
- 洞察只回答变化、集中项、待整理和预算风险。
- 历史总结与当前总览分离，刷新报告是明确命令。
- 下一阶段为报告增加详情、生成依据和明细回跳。

### 2.5 我的

- 设置按账号/本机、外观、通用、隐私与自动化、版本分组。
- 默认不显示供应商名称、Secret 状态或解析实现。
- 版本号读取 Bundle，变化简介来自 `AppReleaseNotes`，两者发布前必须同步。

## 3. 视觉系统

- 使用系统字体和 Dynamic Type，不引入手写或品牌展示字体。
- 背景使用系统分组背景，数据表面使用系统次级分组背景。
- 蓝色只用于主操作；绿色表示正常，橙色表示临界，红色表示超限或破坏性操作。
- 卡片圆角固定 8pt、1px 弱边框、无装饰性阴影。
- 不使用装饰渐变；进度条、图标背景和商户徽标使用纯色。
- 正文优先系统语义色，颜色不作为唯一状态提示。
- 控件最小点击区域 44pt；图标按钮必须有无障碍标签。
- 金额使用 `monospacedDigit()`，长金额允许缩放但不得截断。

## 4. 技术架构

```text
App / Share Extension / App Intent
                |
                v
       ImportPipeline
       batch -> candidate -> review
                |
                v
       ExpenseMutationService
                |
                v
 SwiftData: ExpenseRecord / BudgetPlan / ArchiveReport / Rule
                |
                v
 BillingAnalytics / ArchiveReportService / NotificationService
```

### 分层职责

- View：展示、局部交互状态、路由，不直接实现解析规则。
- Import：接收截图或文本，生成批次和候选，执行去重和复核状态迁移。
- Mutation：负责新增、编辑、删除后的保存与依赖刷新；当前仍需继续收口。
- Domain：金额、周期、分类、渠道、预算和报告模型。
- Service：解析、分析、报告、通知和深链。

### 状态与导航

- 每个 tab 自己拥有 `NavigationStack`，切换 tab 不混用导航历史。
- 模态内容使用 item 驱动的 sheet route，避免多个互斥布尔值。
- App 级状态只保留 tab、导入方式、深链 request id 和外观偏好。
- SwiftData `ModelContainer` 在 App 根部安装，View 用 `@Query` 读取。

### 仍需拆分的技术债

- `PaymentTextParser.swift` 和 `ReceiptImageParser.swift` 应按结构化解析、账单行识别、供应商 client、logo 裁剪拆成独立文件。
- `AwemeBillingCoreTests.swift` 应按 Parser、Import、Report、Model 分组。
- `ArchiveReportService.rebuildReports` 后续改为周期唯一键 upsert。
- 所有写入入口最终统一进入 `ExpenseMutationService`，避免刷新副作用分散。

## 5. arm64 与链接策略

- 工程不包含 C/C++/Objective-C++ 源码，因此不设置 `CLANG_CXX_LANGUAGE_STANDARD`，也不手工链接 `libc++`。
- 单元测试使用标准 `TEST_HOST` + `BUNDLE_LOADER`，不通过 `OTHER_LDFLAGS` 直接链接 App 调试动态库。
- `ARCHS[sdk=iphonesimulator*]` 固定为 `arm64`，适配当前 Apple Silicon 开发环境。
- 质量门禁显式传入 `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`，并用 `lipo -archs` 校验 App 产物只含 arm64。
- 真机构建仍使用标准 `generic/platform=iOS`，不受模拟器设置影响。

## 6. 测试过程

### 6.1 静态门禁

1. 检查生成物、用户态 Xcode 文件和本地截图没有进入 git。
2. 扫描常见 Secret 模式。
3. 执行 `git diff --check`。
4. 检查 project 文件没有 x86、C++ 标准、手工 linker flag 或 libc++。

### 6.2 单元与集成测试

- Parser：微信、支付宝、银行卡、结构化 JSON、汇总页、关闭订单、异常金额和日期边界。
- Import：批次创建、待复核、接受一次、忽略、重复标记、logo 数据透传。
- OCR：在线识别优先级、本机兜底、失败解释、账单行与 logo 对齐。
- Domain：周期边界、预算、分类映射、去重和报告生成。
- Mutation：新增、编辑、删除后报告与通知数据一致。

### 6.3 UI 测试

- 总览记一笔可进入手动编辑。
- 总览存在本月、预算和最近记录，不存在图表样式控制。
- 明细搜索可定位商户，并保留月份与快捷筛选。
- 导入页待复核位于新增导入之前，三种输入方式可达。
- 报告 tab 可达并支持周期切换。
- 我的页可进入类型、推送和版本历史；深色模式仍可访问。

### 6.4 执行命令

完整 arm64 门禁与测试：

```sh
SIMULATOR_ID=739F8670-9175-417E-B501-0FB91A83F034 scripts/quality_gate.sh
```

只构建测试产物：

```sh
scripts/quality_gate.sh
```

真机构建：

```sh
xcodebuild -project AwemeBillingApp/AwemeBillingApp.xcodeproj \
  -scheme AwemeBillingApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData-device-install \
  -allowProvisioningUpdates build
```

## 7. 发布验收

- arm64 build-for-testing 成功，产物架构校验通过。
- 核心单元测试和 UI 测试全部通过。
- 分享扩展、深链和 App 内导入都进入同一复核队列。
- 总览、明细、导入、报告、我的五个 tab 无重复主职责。
- 浅色与深色模式文字对比、金额截断和点击区域通过检查。
- App 和 Share Extension 版本一致；我的页变化简介已更新且没有 `v` 前缀。
