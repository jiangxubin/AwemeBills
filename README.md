# 消费管家

消费管家是一个本地优先的个人消费管理 iPhone App。主工程位于 `AwemeBillingApp/AwemeBillingApp.xcodeproj`，包含 iPhone App、Share Extension、SwiftData 数据模型、导入解析管线、归档/报告通知和核心单元测试。

## 工程入口

- 主 App：`AwemeBillingApp/AwemeBillingApp`
- 分享扩展：`AwemeBillingApp/AwemeBillingShareExtension`
- 单元测试：`AwemeBillingApp/AwemeBillingTests`
- 产品与技术文档：`docs/`
- Landing page：`landing/`
- 快捷指令文件：`Shortcuts/`

`OCR_iOS_SDK_v1.1.0.32/` 是本地腾讯 OCR SDK 参考包和 demo，不是主 App 的 Xcode 入口。构建和测试脚本都显式指向 `AwemeBillingApp/AwemeBillingApp.xcodeproj`。

## 本地验证

推荐先跑项目质量门禁：

```sh
scripts/quality_gate.sh
```

常用 Xcode 命令：

```sh
xcodebuild -project AwemeBillingApp/AwemeBillingApp.xcodeproj -scheme AwemeBillingApp -destination 'generic/platform=iOS Simulator' build-for-testing
xcodebuild -project AwemeBillingApp/AwemeBillingApp.xcodeproj -scheme AwemeBillingApp -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath DerivedData-device-install -allowProvisioningUpdates build
```

## 本地配置

OCR Secret 不应写入 git。需要真机或本地云 OCR 时，在本地 `.xcconfig` 或 Xcode Scheme 环境变量中提供：

```sh
TENCENT_OCR_SECRET_ID=...
TENCENT_OCR_SECRET_KEY=...
```

仓库已忽略 `LocalSecrets.xcconfig`、`DerivedData*`、`.module-cache/`、Xcode 用户状态和本地调试截图。
