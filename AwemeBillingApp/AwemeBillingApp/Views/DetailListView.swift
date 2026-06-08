import SwiftData
import SwiftUI

struct DetailListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ExpenseRecord.occurredAt, order: .reverse) private var records: [ExpenseRecord]
    @Query(sort: \ExpenseCategoryProfile.sortOrder) private var categoryProfiles: [ExpenseCategoryProfile]
    @State private var editorRoute: ExpenseEditorRoute?
    @State private var selectedMonthID = ExpenseMonthFilter.timelineID
    @State private var selectedCategoryRaw: String?
    @State private var selectedScene: String?
    @State private var selectedChannelRaw: String?
    @State private var pendingDeletion: DetailDeletionRequest?
    @State private var isSelectingRecords = false
    @State private var selectedRecordIDs: Set<PersistentIdentifier> = []

    private var monthFilters: [ExpenseMonthFilter] {
        ExpenseMonthFilter.filters(from: records, including: selectedMonthID)
    }

    private var selectedMonthFilter: ExpenseMonthFilter {
        monthFilters.first { $0.id == selectedMonthID } ?? monthFilters.first ?? .current()
    }

    private var scopedRecords: [ExpenseRecord] {
        selectedMonthFilter.records(from: records)
    }

    private var filteredRecords: [ExpenseRecord] {
        scopedRecords.filter { record in
            let matchesCategory = selectedCategoryRaw.map {
                ExpenseCategoryCatalog.normalized(record.categoryRaw) == ExpenseCategoryCatalog.normalized($0)
            } ?? true
            let matchesScene = selectedScene.map { sceneFilterKey(record.scene) == sceneFilterKey($0) } ?? true
            let matchesChannel = selectedChannelRaw.map { record.channelRaw == $0 } ?? true
            return matchesCategory && matchesScene && matchesChannel
        }
    }

    private var activeFilterCount: Int {
        [selectedCategoryRaw, selectedScene, selectedChannelRaw].compactMap { $0 }.count
    }

    var body: some View {
        NavigationStack {
            List {
                recordListContent
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .safeAreaInset(edge: .top, spacing: 0) {
                controlPanel
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .background(AppTheme.background)
            }
            .navigationTitle("明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !filteredRecords.isEmpty {
                        Button(isSelectingRecords ? "完成" : "选择") {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                isSelectingRecords.toggle()
                                if !isSelectingRecords {
                                    selectedRecordIDs.removeAll()
                                }
                            }
                        }
                        .accessibilityLabel(isSelectingRecords ? "完成选择" : "选择多条记录")
                        .accessibilityIdentifier(isSelectingRecords ? "完成选择" : "选择多条记录")
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    if isSelectingRecords {
                        Button(selectedRecordIDs.count == filteredRecords.count ? "清空" : "全选") {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                toggleSelectAll()
                            }
                        }
                        .accessibilityLabel(selectedRecordIDs.count == filteredRecords.count ? "清空选择" : "全选记录")
                        .accessibilityIdentifier(selectedRecordIDs.count == filteredRecords.count ? "清空选择" : "全选记录")
                    }
                }
            }
            .sheet(item: $editorRoute) { route in
                switch route {
                case .edit(let record):
                    ExpenseEditorView(record: record)
                }
            }
            .onChange(of: selectedMonthID) { _, _ in
                selectedCategoryRaw = nil
                selectedScene = nil
                selectedChannelRaw = nil
            }
            .alert(item: $pendingDeletion) { request in
                Alert(
                    title: Text(request.title),
                    message: Text(request.message),
                    primaryButton: .destructive(Text("删除")) {
                        Task { await deleteRecords(request.recordIDs) }
                    },
                    secondaryButton: .cancel(Text("取消")) {
                        pendingDeletion = nil
                    }
                )
            }
            .safeAreaInset(edge: .bottom) {
                if isSelectingRecords {
                    batchSelectionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private var batchSelectionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选择 \(selectedRecordIDs.count) 笔")
                    .font(.subheadline.weight(.semibold))
                Text("删除后会刷新总览和历史总结")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                requestDeleteSelectedRecords()
            } label: {
                Label("删除", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedRecordIDs.isEmpty)
            .accessibilityLabel("批量删除")
            .accessibilityIdentifier("批量删除")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: selectedCategoryRaw ?? selectedScene ?? selectedChannelRaw ?? "全部明细",
                subtitle: "\(filteredRecords.count) 笔 / \(BillingAnalytics.currency(BillingAnalytics.total(filteredRecords)))"
            )

            HStack(spacing: 10) {
                monthFilterMenu
                filterMenu
            }
        }
        .padding(16)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 8))
    }

    private var monthFilterMenu: some View {
        Menu {
            ForEach(monthFilters) { filter in
                Button {
                    selectedMonthID = filter.id
                } label: {
                    if filter.id == selectedMonthID {
                        Label(filter.title, systemImage: "checkmark")
                    } else {
                        Text(filter.title)
                    }
                }
            }
        } label: {
            filterControlLabel(
                title: selectedMonthFilter.title,
                systemImage: "calendar"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("月份筛选")
    }

    private var filterMenu: some View {
        Menu {
            Section("消费类型") {
                filterMenuButton(title: "全部类型", isSelected: selectedCategoryRaw == nil) {
                    selectedCategoryRaw = nil
                }
                ForEach(categoryFilterNames, id: \.self) { category in
                    filterMenuButton(title: category, isSelected: selectedCategoryRaw == category) {
                        selectedCategoryRaw = category
                    }
                }
            }

            Section("来源场景") {
                filterMenuButton(title: "全部场景", isSelected: selectedScene == nil) {
                    selectedScene = nil
                }
                ForEach(sceneFilterNames, id: \.self) { scene in
                    filterMenuButton(title: scene, isSelected: selectedScene == scene) {
                        selectedScene = scene
                    }
                }
            }

            Section("支付渠道") {
                filterMenuButton(title: "全部渠道", isSelected: selectedChannelRaw == nil) {
                    selectedChannelRaw = nil
                }
                ForEach(channelFilterNames, id: \.self) { channel in
                    filterMenuButton(title: channel, isSelected: selectedChannelRaw == channel) {
                        selectedChannelRaw = channel
                    }
                }
            }

            if activeFilterCount > 0 {
                Section {
                    Button("清除筛选") {
                        selectedCategoryRaw = nil
                        selectedScene = nil
                        selectedChannelRaw = nil
                    }
                }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                filterControlLabel(
                    title: "筛选",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(AppTheme.accent, in: Circle())
                        .offset(x: 4, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("筛选")
    }

    private func filterControlLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 8))
    }

    private func filterMenuButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private var categoryFilterNames: [String] {
        let recordCategories = Set(scopedRecords.map(\.categoryRaw))
        let configured = ExpenseCategoryCatalog.visibleNames(from: categoryProfiles, including: selectedCategoryRaw)
        return (configured + recordCategories)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .reduce(into: [String]()) { result, name in
                if !result.contains(where: { ExpenseCategoryCatalog.normalized($0) == ExpenseCategoryCatalog.normalized(name) }) {
                    result.append(name)
                }
            }
    }

    private var sceneFilterNames: [String] {
        uniqueFilterNames(scopedRecords.map { sceneFilterTitle($0.scene) })
    }

    private var channelFilterNames: [String] {
        uniqueFilterNames(scopedRecords.map(\.channelRaw))
    }

    private func uniqueFilterNames(_ names: [String]) -> [String] {
        names
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .reduce(into: [String]()) { result, name in
                if !result.contains(where: { ExpenseCategoryCatalog.normalized($0) == ExpenseCategoryCatalog.normalized(name) }) {
                    result.append(name)
                }
            }
    }

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.vertical, 2)
        }
    }

    private func filterGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            chipRow {
                content()
            }
        }
    }

    @ViewBuilder
    private var recordListContent: some View {
        if filteredRecords.isEmpty {
            Section {
                EmptyStateView(title: "没有符合筛选的消费", systemImage: "tray")
                    .listRowBackground(AppTheme.card)
            }
        } else {
            ForEach(BillingAnalytics.dateGroupedRecords(filteredRecords), id: \.0) { date, dayRecords in
                Section {
                    ForEach(dayRecords) { record in
                        if isSelectingRecords {
                            selectableRecordRow(record)
                        } else {
                            Button {
                                editorRoute = .edit(record)
                            } label: {
                                ExpenseRow(record: record, showsCreatedAt: true)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    requestDelete(record)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    Task { await toggleArchived(record) }
                                } label: {
                                    Label(record.isArchived ? "取消归档" : "归档", systemImage: "archivebox")
                                }
                                .tint(.teal)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text(date, format: .dateTime.year().month().day().weekday())
                        Spacer()
                        Text("\(dayRecords.count) 笔")
                    }
                }
            }
        }
    }

    private func selectableRecordRow(_ record: ExpenseRecord) -> some View {
        Button {
            toggleSelection(for: record)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedRecordIDs.contains(record.persistentModelID) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selectedRecordIDs.contains(record.persistentModelID) ? AppTheme.accent : .secondary)
                    .frame(width: 28)

                ExpenseRow(record: record, showsCreatedAt: true)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.merchant)，\(selectedRecordIDs.contains(record.persistentModelID) ? "已选择" : "未选择")")
    }

    private func requestDelete(_ record: ExpenseRecord) {
        pendingDeletion = DetailDeletionRequest(recordIDs: [record.persistentModelID])
    }

    @MainActor
    private func deleteRecords(_ recordIDs: Set<PersistentIdentifier>) async {
        let targets = records.filter { recordIDs.contains($0.persistentModelID) }
        for record in targets {
            modelContext.delete(record)
        }
        try? modelContext.save()
        await ExpenseMutationService.refreshReportsAndNotifications(context: modelContext)
        pendingDeletion = nil
        selectedRecordIDs.subtract(recordIDs)
        if selectedRecordIDs.isEmpty {
            isSelectingRecords = false
        }
    }

    @MainActor
    private func toggleArchived(_ record: ExpenseRecord) async {
        record.isArchived.toggle()
        try? modelContext.save()
        await ExpenseMutationService.refreshReportsAndNotifications(context: modelContext)
    }

    private func toggleSelection(for record: ExpenseRecord) {
        let id = record.persistentModelID
        if selectedRecordIDs.contains(id) {
            selectedRecordIDs.remove(id)
        } else {
            selectedRecordIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        let visibleIDs = Set(filteredRecords.map(\.persistentModelID))
        if selectedRecordIDs.count == filteredRecords.count {
            selectedRecordIDs.removeAll()
        } else {
            selectedRecordIDs = visibleIDs
        }
    }

    private func requestDeleteSelectedRecords() {
        guard !selectedRecordIDs.isEmpty else { return }
        pendingDeletion = DetailDeletionRequest(recordIDs: selectedRecordIDs)
    }
}

private enum ExpenseEditorRoute: Identifiable {
    case edit(ExpenseRecord)

    var id: String {
        switch self {
        case .edit(let record):
            "edit-\(ObjectIdentifier(record).hashValue)"
        }
    }
}

private struct DetailDeletionRequest: Identifiable {
    let id = UUID()
    let recordIDs: Set<PersistentIdentifier>

    var title: String {
        recordIDs.count > 1 ? "删除 \(recordIDs.count) 笔消费？" : "删除这笔消费？"
    }

    var message: String {
        recordIDs.count > 1
            ? "这些记录会从明细中移除，并同步刷新总览和历史总结。"
            : "删除后会同步刷新总览和历史总结。"
    }
}

private struct ExpenseMonthFilter: Identifiable, Equatable {
    let id: String
    let title: String
    let interval: DateInterval?

    static let timelineID = "timeline"
    static let timeline = ExpenseMonthFilter(id: timelineID, title: Self.monthTitle(containing: .now), interval: nil)

    static func timeline(title: String) -> ExpenseMonthFilter {
        ExpenseMonthFilter(id: timelineID, title: title, interval: nil)
    }

    static func current(now: Date = .now) -> ExpenseMonthFilter {
        month(containing: now)
    }

    static func filters(from records: [ExpenseRecord], including selectedID: String?) -> [ExpenseMonthFilter] {
        let latestDate = records.map(\.occurredAt).max() ?? .now
        var filters = [timeline(title: monthTitle(containing: latestDate))]
        let calendar = Calendar.current
        let months = Dictionary(grouping: records) { record in
            calendar.dateInterval(of: .month, for: record.occurredAt)?.start ?? calendar.startOfDay(for: record.occurredAt)
        }
            .keys
            .sorted(by: >)
            .map { month(containing: $0) }

        for filter in months where !filters.contains(where: { $0.id == filter.id }) {
            filters.append(filter)
        }

        let current = current()
        if selectedID == current.id && !filters.contains(where: { $0.id == current.id }) {
            filters.insert(current, at: 1)
        }

        return filters
    }

    func records(from records: [ExpenseRecord]) -> [ExpenseRecord] {
        guard let interval else { return records }
        return records.filter { $0.occurredAt >= interval.start && $0.occurredAt < interval.end }
    }

    private static func month(containing date: Date, titleOverride: String? = nil) -> ExpenseMonthFilter {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .month, for: date)
        let start = interval?.start ?? date
        let components = calendar.dateComponents([.year, .month], from: start)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let id = "\(year)-\(String(format: "%02d", month))"
        return ExpenseMonthFilter(
            id: id,
            title: titleOverride ?? monthTitle(year: year, month: month),
            interval: interval
        )
    }

    private static func monthTitle(containing date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        return monthTitle(year: components.year ?? 0, month: components.month ?? 1)
    }

    private static func monthTitle(year: Int, month: Int) -> String {
        "\(year)年\(month)月"
    }
}

private func sceneFilterTitle(_ scene: String) -> String {
    let trimmed = scene.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "未标记场景" : trimmed
}

private func sceneFilterKey(_ scene: String) -> String {
    ExpenseCategoryCatalog.normalized(sceneFilterTitle(scene))
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(isSelected ? AppTheme.accent : Color.secondary.opacity(0.10), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
