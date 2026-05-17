import SwiftData
import SwiftUI

struct ArchiveScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SummaryPeriod.allCases) { period in
                        if let schedule = schedules.first(where: { $0.period == period }) {
                            ScheduleRow(schedule: schedule)
                        }
                    }
                } header: {
                    Text("总结推送")
                } footer: {
                    Text("默认按每日、每周、每月、每季度、每年在下一个周期开始后的指定时间推送消费总结。")
                }

                Section("归档状态") {
                    LabeledContent("已归档", value: "\(records.filter(\.isArchived).count) 笔")
                    LabeledContent("未归档", value: "\(records.filter { !$0.isArchived }.count) 笔")
                    Button {
                        records.forEach { $0.isArchived = true }
                    } label: {
                        Label("归档当前全部历史消费", systemImage: "archivebox.fill")
                    }
                }

                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("历史归档")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await scheduleNotifications() }
                    } label: {
                        Image(systemName: "bell.badge")
                    }
                    .accessibilityLabel("排程推送")
                }
            }
        }
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
            statusMessage = "已更新 \(schedules.filter(\.isEnabled).count) 个总结推送。"
        } catch {
            statusMessage = "排程失败：\(error.localizedDescription)"
        }
    }
}

struct ScheduleRow: View {
    @Bindable var schedule: ArchiveSchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(schedule.period.rawValue, systemImage: schedule.period.iconName)
                    .font(.headline)
                Spacer()
                Toggle("启用", isOn: $schedule.isEnabled)
                    .labelsHidden()
            }

            HStack {
                Stepper(value: $schedule.hour, in: 0...23) {
                    Text("时 \(schedule.hour)")
                }
                Stepper(value: $schedule.minute, in: 0...59, step: 5) {
                    Text("分 \(schedule.minute)")
                }
            }
            .font(.subheadline)

            Text("默认：\(schedule.period.defaultDescription)。下一次：\(BillingAnalytics.nextFireDate(for: schedule), format: .dateTime.year().month().day().hour().minute())")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
