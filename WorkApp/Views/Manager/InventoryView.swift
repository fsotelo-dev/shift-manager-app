import SwiftUI

struct InventoryView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: InventoryItem?
    @State private var lowOnly = false
    @State private var search = ""

    private var filtered: [InventoryItem] {
        state.inventory.filter {
            (!lowOnly || $0.needsOrder) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }
    private var groups: [(String, [InventoryItem])] {
        Dictionary(grouping: filtered, by: \.category).sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
    }
    private var orderText: String {
        let low = state.inventory.filter(\.needsOrder).sorted { $0.name < $1.name }
        return "Order list – \(Date().formatted(date: .abbreviated, time: .omitted))\n" +
            low.map { "• \($0.name): \($0.orderQty.formatted()) \($0.unit)" }.joined(separator: "\n")
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $lowOnly) {
                    Text("All items").tag(false)
                    Text("Below par (\(state.inventory.filter(\.needsOrder).count))").tag(true)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            ForEach(groups, id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { item in
                        Button { editing = item } label: { InventoryRow(item: item) }
                    }
                }
            }
            if state.inventory.isEmpty {
                ContentUnavailableCompat(title: "No items yet", message: "Tap + to add what you count.")
            }
        }
        .safeAreaInset(edge: .top) { TimeBlockBanner() }
        .searchable(text: $search)
        .navigationTitle("Inventory")
        .refreshable { await state.refreshAll() }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                ShareLink(item: orderText) { Label("Order list", systemImage: "square.and.arrow.up") }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = InventoryItem(name: "") } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { InventoryEditor(item: $0) }
    }
}

struct InventoryRow: View {
    let item: InventoryItem
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).foregroundStyle(.primary)
                Text(item.lastCountedAt.map { "Counted \($0.formatted(.relative(presentation: .named)))\(item.lastCountedBy.map { " by \($0)" } ?? "")" } ?? "Not counted yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.onHand.formatted()) \(item.unit)").font(.body.monospacedDigit())
                    .foregroundStyle(item.needsOrder ? Theme.alert : .primary)
                Text("par \(item.par.formatted())").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct InventoryEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var item: InventoryItem
    private let isNew: Bool
    init(item: InventoryItem) { _item = State(initialValue: item); isNew = item.name.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Count") {
                    HStack {
                        Text("On hand")
                        Spacer()
                        TextField("0", value: $item.onHand, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Stepper("", value: $item.onHand, in: 0...9999).labelsHidden()
                    }
                    HStack {
                        Text("Par level")
                        Spacer()
                        TextField("0", value: $item.par, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    if item.needsOrder {
                        Label("Order \(item.orderQty.formatted()) \(item.unit)", systemImage: "cart")
                            .foregroundStyle(Theme.alert)
                    }
                }
                Section("Item") {
                    TextField("Name", text: $item.name)
                    TextField("Category (e.g. Proteins, Paper)", text: $item.category)
                    TextField("Unit (case, bag, lb)", text: $item.unit)
                }
                if !isNew {
                    Section {
                        Button("Delete item", role: .destructive) {
                            Task { await state.remove(item, \.inventory); dismiss() }
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New item" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.lastCountedAt = Date()
                        item.lastCountedBy = state.userName
                        Task { await state.upsert(item, \.inventory); dismiss() }
                    }.disabled(item.name.isEmpty)
                }
            }
        }
    }
}

/// Simple empty state that works on iOS 16.
struct ContentUnavailableCompat: View {
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
        .listRowBackground(Color.clear)
    }
}
