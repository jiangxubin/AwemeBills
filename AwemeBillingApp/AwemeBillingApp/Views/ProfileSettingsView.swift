import SwiftData
import SwiftUI
import UserNotifications

struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("detailDefaultPeriod") private var detailDefaultPeriod = "month"
    @State private var statusMessage = ""
    @State private var notificationStatusText = "检查中"
    @State private var nextPushText = "尚未排程"

    var body: some View {
        NavigationStack {
            Form {
                Section("账号设置") {
                    SettingsInfoRow(
                        title: "本机账本",
                        systemImage: "person.crop.circle",
                        text: "消费记录保存在这台设备和 App 数据容器内。"
                    )
                    LabeledContent("同步状态", value: "本地优先")
                    LabeledContent("隐私边界", value: "不后台读取其他 App")
                }

                Section("外观设置") {
                    Picker("显示模式", selection: $appearanceMode) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }

                    Picker("明细默认周期", selection: $detailDefaultPeriod) {
                        Text("本月").tag("month")
                        Text("本周").tag("week")
                        Text("今天").tag("day")
                    }
                }

                Section("通用设置") {
                    SettingsInfoRow(
                        title: "截图识别",
                        systemImage: "text.viewfinder",
                        text: "选择账单截图后自动识别，识别结果会先进入复核，可修改后再入账。"
                    )

                    DisclosureGroup {
                        Text("这些时间用于生成每日、每周、每月、每季度和每年的消费总结推送。系统会在 App 启动、导入和手动保存时刷新排程。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)

                        SettingsInfoRow(
                            title: "当前状态",
                            systemImage: "bell",
                            text: "\(notificationStatusText) · 下一次：\(nextPushText)"
                        )

                        VStack(spacing: 0) {
                            ForEach(SummaryPeriod.allCases) { period in
                                if let schedule = schedules.first(where: { $0.period == period }) {
                                    ScheduleRow(schedule: schedule)
                                        .padding(.vertical, 10)
                                    if period != SummaryPeriod.allCases.last {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        Button {
                            Task { await scheduleNotifications() }
                        } label: {
                            Label("保存并更新推送", systemImage: "bell.badge")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("消费记录推送设置")
                            Text(scheduleSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsInfoRow(
                        title: "重复导入保护",
                        systemImage: "doc.on.doc",
                        text: "截图和文本导入会按商户、金额、时间、来源生成指纹，命中已有记录时不会重复入账。"
                    )

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("App 开发信息") {
                    SettingsInfoRow(
                        title: "可以自动化的部分",
                        systemImage: "checkmark.seal.fill",
                        text: "通过分享扩展、快捷指令和 URL Scheme，把用户选择的截图送进消费管家。"
                    )
                    SettingsInfoRow(
                        title: "iOS 的边界",
                        systemImage: "lock.shield.fill",
                        text: "普通 App 不能后台读取其他支付 App 的通知或私有流水，只能处理你主动交给它的截图、文本或文件。"
                    )
                    LabeledContent("版本", value: appVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await refreshNotificationStatus()
            }
        }
    }

    private var scheduleSummary: String {
        let enabledCount = schedules.filter(\.isEnabled).count
        guard let daySchedule = schedules.first(where: { $0.period == .day }) else {
            return "默认每日 09:00，其他周期按下个周期首日 09:00"
        }
        return "\(enabledCount) 个启用 · 每日 \(String(format: "%02d:%02d", daySchedule.hour, daySchedule.minute))"
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func scheduleNotifications() async {
        let granted = await ArchiveNotificationService.requestAuthorization()
        guard granted else {
            statusMessage = "通知权限未开启，无法推送消费总结。"
            return
        }

        do {
            for schedule in schedules {
                try await ArchiveNotificationService.schedule(schedule, records: records)
            }
            try? modelContext.save()
            await refreshNotificationStatus()
            statusMessage = "已保存并更新 \(schedules.filter(\.isEnabled).count) 个消费总结推送。"
        } catch {
            statusMessage = "排程失败：\(error.localizedDescription)"
        }
    }

    private func refreshNotificationStatus() async {
        let status = await ArchiveNotificationService.authorizationStatus()
        notificationStatusText = notificationStatusDescription(for: status)
        if let date = await ArchiveNotificationService.nextScheduledFireDate() {
            nextPushText = date.formatted(.dateTime.month().day().hour().minute())
        } else {
            nextPushText = "尚未排程"
        }
    }

    private func notificationStatusDescription(for status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return "通知已开启"
        case .denied:
            return "通知权限已关闭"
        case .notDetermined:
            return "等待授权"
        @unknown default:
            return "状态未知"
        }
    }
}

struct SettingsInfoRow: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
