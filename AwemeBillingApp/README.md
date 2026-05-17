# 消费管家 iPhone App

一个 SwiftUI + SwiftData 的个人消费管理 iPhone App 原型。

## 已实现

- 年、月、周、日、季度消费总览
- 消费明细列表、分类筛选、新增、删除、滑动归档
- 按消费场景和支付渠道聚合分析
- 历史消费归档状态管理
- 每日、每周、每月、每季度、每年总结推送时间配置
- 本地通知排程，默认均为下一个周期开始日 09:00
- 支付宝、微信支付、云闪付通知或账单文本解析并归档

## iOS 权限边界

iOS 普通 App 不能实时读取其他 App 内部流水、后台数据或通知内容。因此“支付宝、微信、银联云闪付动账实时监听”在当前系统权限下不能做成跨 App 静默监听。

当前可落地方案是：

- 用户手动新增消费
- 粘贴支付通知或账单文本自动解析
- 后续增加分享扩展，从支付 App 或文件 App 分享账单到本 App
- 后续增加 CSV / Excel / 邮箱账单导入
- 后续接入银行或支付机构提供的开放 API

## 构建

```sh
xcodebuild -project AwemeBillingApp.xcodeproj -scheme AwemeBillingApp -destination 'platform=iOS Simulator,name=iPhone 17' build
```

项目最低支持 iOS 17。
