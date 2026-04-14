import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranslationRecord.timestamp, order: .reverse) private var records: [TranslationRecord]
    @State private var searchText: String = ""

    private var filteredRecords: [TranslationRecord] {
        guard !searchText.isEmpty else { return records }
        let query = searchText.lowercased()
        return records.filter {
            $0.sourceText.lowercased().contains(query)
                || $0.targetText.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Search history…"), text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if filteredRecords.isEmpty {
                ContentUnavailableView {
                    Label(
                        searchText.isEmpty
                            ? String(localized: "No History")
                            : String(localized: "No Results"),
                        systemImage: searchText.isEmpty ? "clock" : "magnifyingglass"
                    )
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRecords) { record in
                            HistoryRow(record: record)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    fillFromRecord(record)
                                }
                                .contextMenu {
                                    Button(String(localized: "Delete"), role: .destructive) {
                                        modelContext.delete(record)
                                    }
                                }

                            if record.id != filteredRecords.last?.id {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
            }

            Divider()

            // Bottom bar
            HStack {
                Text("\(records.count) records")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !records.isEmpty {
                    Button(String(localized: "Clear All")) {
                        clearAllRecords()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func fillFromRecord(_ record: TranslationRecord) {
        appState.inputText = record.sourceText
        appState.outputText = record.targetText
        appState.currentEngineType = record.engine
        appState.activeTab = .translate
    }

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredRecords[index])
        }
    }

    private func clearAllRecords() {
        for record in records {
            modelContext.delete(record)
        }
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    let record: TranslationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.sourceText)
                .font(.callout)
                .lineLimit(2)

            Text(record.targetText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Image(systemName: record.engine.iconName)
                    .font(.caption2)
                Text(record.engine.displayName)
                    .font(.caption2)
                Spacer()
                Text(record.timestamp, style: .relative)
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
