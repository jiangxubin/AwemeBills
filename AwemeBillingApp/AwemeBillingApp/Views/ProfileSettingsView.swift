import SwiftData
import SwiftUI
import UserNotifications

struct ProfileSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query(sort: \ExpenseCategoryProfile.sortOrder) private var categoryProfiles: [ExpenseCategoryProfile]
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("advancedAnalysisControlsEnabled") private var advancedAnalysisControlsEnabled = false
    @State private var ocrStatistics = OCRRecognitionStatistics.snapshot()
    @State private var ocrConfigurations = OCRProviderConfigurationDiagnostics.snapshot()

    var body: some View {
        NavigationStack {
            Form {
                Section("账号设置") {
                    SettingsInfoRow(
                        title: "本机账本",
                        systemImage: "person.crop.circle",
                        text: "消费记录保存在这台设备和 App 数据容器内。"
                    )
                }

                Section("外观设置") {
                    Picker("显示模式", selection: $appearanceMode) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                }

                Section("通用设置") {
                    NavigationLink {
                        CategoryManagementView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("消费类型管理")
                            Text("\(enabledCategoryCount) 个启用，可新增自定义类型并控制明细筛选显示。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("消费类型管理")

                    Toggle(isOn: $advancedAnalysisControlsEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("高级分析设置")
                            Text("打开后，总览消费分析会显示空心/实心饼图、横向/竖向柱状图等细分样式。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("高级分析设置")

                    NavigationLink {
                        ExpenseRecordPushSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("消费记录推送设置")
                            Text(scheduleSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("关于") {
                    paymentAutomationInfo

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("识别链路配置")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(ocrConfigurations) { item in
                                OCRProviderConfigurationRow(snapshot: item)
                            }

                            Divider()

                            if ocrStatistics.allSatisfy({ $0.attempts == 0 }) {
                                Text("暂无截图识别调用记录。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(ocrStatistics) { item in
                                    OCRRecognitionStatisticRow(snapshot: item)
                                }
                            }

                            Text("统计保存在本机，用于观察识别链路稳定性；不会上传消费内容。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("识别结果统计")
                            Text("\(ocrConfigurationSummary) · \(ocrStatisticsSummary)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("版本", value: appVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                ExpenseCategoryCatalog.ensureDefaults(profiles: categoryProfiles, context: modelContext)
                try? modelContext.save()
                ocrStatistics = OCRRecognitionStatistics.snapshot()
                ocrConfigurations = OCRProviderConfigurationDiagnostics.snapshot()
            }
        }
    }

    private var enabledCategoryCount: Int {
        let names = ExpenseCategoryCatalog.visibleNames(from: categoryProfiles)
        return names.count
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

    private var ocrStatisticsSummary: String {
        let attempts = ocrStatistics.reduce(0) { $0 + $1.attempts }
        let parsed = ocrStatistics.reduce(0) { $0 + $1.parsedSuccesses }
        guard attempts > 0 else { return "暂无调用记录" }
        return "调用 \(attempts) 次 · 解析成功 \(parsed) 次"
    }

    private var ocrConfigurationSummary: String {
        let configured = ocrConfigurations.filter(\.isConfigured).map(\.provider.rawValue)
        guard !configured.isEmpty else { return "仅本机兜底" }
        return configured.joined(separator: " / ")
    }

    private var paymentAutomationInfo: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("推荐用短信或邮件作为触发源：银行、信用卡、支付宝账单邮件、微信支付账单邮件都可以。快捷指令收到后，把正文传给“消费管家 - 自动记录消费文本”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsInfoRow(
                    title: "短信自动化",
                    systemImage: "message.fill",
                    text: "快捷指令 > 自动化 > 收到信息；发件人填银行或支付服务号，内容包含“消费、支出、付款、交易”等关键词。"
                )

                SettingsInfoRow(
                    title: "邮件自动化",
                    systemImage: "envelope.fill",
                    text: "快捷指令 > 自动化 > 收到邮件；按发件人或主题筛选账单邮件，再把邮件正文传给消费管家。"
                )

                SettingsInfoRow(
                    title: "自动入账规则",
                    systemImage: "checkmark.seal.fill",
                    text: "能明确识别金额、商户和分类的记录会直接入账；低置信度记录会留在导入复核里。"
                )
            }
            .padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("支付通知自动入账")
                Text("短信 / 邮件 / 快捷指令")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

}

struct ExpenseRecordPushSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ArchiveSchedule.periodRaw) private var schedules: [ArchiveSchedule]
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @State private var statusMessage = ""
    @State private var notificationStatusText = "检查中"
    @State private var nextPushText = "尚未排程"

    var body: some View {
        Form {
            Section {
                Text("这些时间用于生成每日、每周、每月、每季度和每年的消费总结推送。系统会在 App 启动、导入和手动保存时刷新排程。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SettingsInfoRow(
                    title: "当前状态",
                    systemImage: "bell",
                    text: "\(notificationStatusText) · 下一次：\(nextPushText)"
                )
            }

            Section("推送时间") {
                ForEach(SummaryPeriod.allCases) { period in
                    if let schedule = schedules.first(where: { $0.period == period }) {
                        ScheduleRow(schedule: schedule)
                    }
                }
            }

            Section {
                Button {
                    Task { await scheduleNotifications() }
                } label: {
                    Label("保存并更新推送", systemImage: "bell.badge")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("消费记录推送设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refreshNotificationStatus()
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

private struct OCRProviderConfigurationRow: View {
    let snapshot: OCRProviderConfigurationSnapshot

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: snapshot.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(snapshot.isConfigured ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.provider.rawValue)
                    .font(.caption.weight(.semibold))
                Text(snapshot.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct OCRRecognitionStatisticRow: View {
    let snapshot: OCRRecognitionProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.provider.rawValue)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("调用 \(snapshot.attempts)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                statisticPill(title: "识别", value: snapshot.recognitionSuccesses)
                statisticPill(title: "解析", value: snapshot.parsedSuccesses)
                statisticPill(title: "失败", value: snapshot.failures)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statisticPill(title: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text("\(value)")
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseCategoryProfile.sortOrder) private var categoryProfiles: [ExpenseCategoryProfile]
    @Query private var records: [ExpenseRecord]
    @Query private var candidates: [ParsedPaymentCandidate]
    @Query private var rules: [PaymentRule]
    @Query private var budgets: [BudgetPlan]
    @State private var newCategoryName = ""
    @State private var editingProfile: ExpenseCategoryProfile?
    @State private var statusMessage = ""

    private var sortedProfiles: [ExpenseCategoryProfile] {
        categoryProfiles.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.createdAt < $1.createdAt
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var body: some View {
        Form {
            Section("新增类型") {
                HStack(spacing: 10) {
                    TextField("例如 咖啡、宠物、运动", text: $newCategoryName)
                        .textInputAutocapitalization(.never)

                    Button("添加") {
                        addCategory()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ExpenseCategoryCatalog.canCreate(newCategoryName, in: categoryProfiles))
                }

                Text("新增类型会出现在手动入账、导入复核和明细筛选里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(sortedProfiles) { profile in
                    CategoryManagementRow(
                        profile: profile,
                        onToggle: { isEnabled in
                            profile.isEnabled = isEnabled
                            save()
                        },
                        onRename: {
                            editingProfile = profile
                        },
                        onDelete: {
                            delete(profile)
                        }
                    )
                }
                .onMove(perform: moveCategories)
            } header: {
                Text("类型列表")
            } footer: {
                Text("内置类型保留自动识别语义，也支持重命名和隐藏；自定义类型支持重命名和删除。隐藏不会修改已存在的历史记录。")
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("消费类型管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .task {
            ExpenseCategoryCatalog.ensureDefaults(profiles: categoryProfiles, context: modelContext)
            save()
        }
        .sheet(item: $editingProfile) { profile in
            CategoryRenameSheet(
                originalName: profile.name,
                existingNames: categoryProfiles.map(\.name)
            ) { newName in
                rename(profile, to: newName)
            }
        }
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ExpenseCategoryCatalog.canCreate(name, in: categoryProfiles) else {
            statusMessage = "这个类型已经存在。"
            return
        }

        let nextOrder = (categoryProfiles.map(\.sortOrder).max() ?? -1) + 1
        let profile = ExpenseCategoryProfile(
            name: name,
            systemImage: ExpenseCategoryCatalog.systemImage(for: name),
            isBuiltIn: false,
            sortOrder: nextOrder
        )
        modelContext.insert(profile)
        newCategoryName = ""
        statusMessage = "已添加 \(name)。"
        save()
    }

    private func rename(_ profile: ExpenseCategoryProfile, to rawName: String) {
        let newName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            statusMessage = "类型名称不能为空。"
            return
        }

        let oldName = profile.name
        guard ExpenseCategoryCatalog.canRename(profile, to: newName, in: categoryProfiles) else {
            statusMessage = "这个类型已经存在。"
            return
        }

        profile.name = newName
        profile.systemImage = ExpenseCategoryCatalog.systemImage(for: newName)
        updateCategoryReferences(from: oldName, to: newName)
        statusMessage = "已重命名为 \(newName)。"
        save()
    }

    private func delete(_ profile: ExpenseCategoryProfile) {
        guard !profile.isBuiltIn else { return }
        updateCategoryReferences(from: profile.name, to: ExpenseCategory.other.rawValue)
        modelContext.delete(profile)
        statusMessage = "已删除 \(profile.name)，关联记录已改为其他。"
        save()
    }

    private func moveCategories(from source: IndexSet, to destination: Int) {
        var reordered = sortedProfiles
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, profile) in reordered.enumerated() {
            profile.sortOrder = index
        }
        save()
    }

    private func updateCategoryReferences(from oldName: String, to newName: String) {
        for record in records where ExpenseCategoryCatalog.normalized(record.categoryRaw) == ExpenseCategoryCatalog.normalized(oldName) {
            record.categoryRaw = newName
            if record.scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || ExpenseCategoryCatalog.normalized(record.scene) == ExpenseCategoryCatalog.normalized(oldName) {
                record.scene = newName
            }
        }

        for candidate in candidates where ExpenseCategoryCatalog.normalized(candidate.categoryRaw) == ExpenseCategoryCatalog.normalized(oldName) {
            candidate.categoryRaw = newName
            if candidate.scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || ExpenseCategoryCatalog.normalized(candidate.scene) == ExpenseCategoryCatalog.normalized(oldName) {
                candidate.scene = newName
            }
        }

        for rule in rules where ExpenseCategoryCatalog.normalized(rule.categoryRaw) == ExpenseCategoryCatalog.normalized(oldName) {
            rule.categoryRaw = newName
        }

        for budget in budgets where ExpenseCategoryCatalog.normalized(budget.categoryRaw) == ExpenseCategoryCatalog.normalized(oldName) {
            budget.categoryRaw = newName
        }
    }

    private func save() {
        try? modelContext.save()
    }
}

private struct CategoryManagementRow: View {
    let profile: ExpenseCategoryProfile
    var onToggle: (Bool) -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34, height: 34)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                Text(profile.isBuiltIn ? "内置类型 · 可重命名" : "自定义类型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("启用", isOn: Binding(
                get: { profile.isEnabled },
                set: onToggle
            ))
            .labelsHidden()

            Menu {
                Button("重命名", systemImage: "pencil", action: onRename)
                if !profile.isBuiltIn {
                    Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
                } else {
                    Button("内置类型不可删除") {}
                        .disabled(true)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
            .accessibilityLabel("\(profile.name) 操作")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(profile.name)，\(profile.isEnabled ? "已启用" : "已隐藏")")
    }
}

private struct CategoryRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let originalName: String
    let existingNames: [String]
    var onSave: (String) -> Void
    @State private var name: String
    @State private var message = ""

    init(
        originalName: String,
        existingNames: [String],
        onSave: @escaping (String) -> Void
    ) {
        self.originalName = originalName
        self.existingNames = existingNames
        self.onSave = onSave
        _name = State(initialValue: originalName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("类型名称", text: $name)
                        .textInputAutocapitalization(.never)
                }

                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("重命名类型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "名称不能为空。"
            return
        }
        let duplicate = existingNames.contains {
            ExpenseCategoryCatalog.normalized($0) == ExpenseCategoryCatalog.normalized(trimmed)
                && ExpenseCategoryCatalog.normalized($0) != ExpenseCategoryCatalog.normalized(originalName)
        }
        guard !duplicate else {
            message = "这个类型已经存在。"
            return
        }

        onSave(trimmed)
        dismiss()
    }
}
