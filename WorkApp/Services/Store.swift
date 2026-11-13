import Foundation
import CloudKit

protocol DataStore {
    /// `match` filters on one of the record's `indexFields`.
    func fetch<T: Record>(_ type: T.Type, match: (field: String, value: String)?) async throws -> [T]
    func save<T: Record>(_ item: T, photo: Data?) async throws
    func delete<T: Record>(_ type: T.Type, id: String) async throws
    func photo<T: Record>(_ type: T.Type, id: String) async throws -> Data?
}
extension DataStore {
    func fetchAll<T: Record>(_ type: T.Type) async throws -> [T] { try await fetch(type, match: nil) }
}

// MARK: - Local (single device, for trying the app without iCloud)

actor LocalStore: DataStore {
    private let dir: URL
    init() {
        dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    private func file(_ type: String) -> URL { dir.appendingPathComponent("\(type).json") }
    private func photoURL(_ type: String, _ id: String) -> URL { dir.appendingPathComponent("\(type)-\(id).jpg") }
    private func load<T: Record>(_ t: T.Type) -> [String: T] {
        guard let d = try? Data(contentsOf: file(T.recordType)) else { return [:] }
        return (try? JSONDecoder.store.decode([String: T].self, from: d)) ?? [:]
    }
    private func write<T: Record>(_ items: [String: T]) throws {
        try JSONEncoder.store.encode(items).write(to: file(T.recordType), options: .atomic)
    }

    func fetch<T: Record>(_ type: T.Type, match: (field: String, value: String)?) async throws -> [T] {
        let all = Array(load(type).values)
        guard let match else { return all }
        return all.filter { $0.indexFields[match.field] == match.value }
    }
    func save<T: Record>(_ item: T, photo: Data?) async throws {
        var all = load(T.self); all[item.id] = item; try write(all)
        if let photo { try photo.write(to: photoURL(T.recordType, item.id), options: .atomic) }
    }
    func delete<T: Record>(_ type: T.Type, id: String) async throws {
        var all = load(type); all[id] = nil; try write(all)
        try? FileManager.default.removeItem(at: photoURL(T.recordType, id))
    }
    func photo<T: Record>(_ type: T.Type, id: String) async throws -> Data? {
        try? Data(contentsOf: photoURL(T.recordType, id))
    }
}

// MARK: - CloudKit (shared across every phone/iPad in the store)

final class CloudKitStore: DataStore {
    private let container: CKContainer
    private var db: CKDatabase { container.publicCloudDatabase }
    init(containerID: String) { container = CKContainer(identifier: containerID) }

    func fetch<T: Record>(_ type: T.Type, match: (field: String, value: String)?) async throws -> [T] {
        let predicate = match.map { NSPredicate(format: "%K == %@", $0.field, $0.value) } ?? NSPredicate(value: true)
        let query = CKQuery(recordType: T.recordType, predicate: predicate)
        var out: [T] = []
        var page = try await db.records(matching: query, desiredKeys: ["data"])
        while true {
            for (_, result) in page.matchResults {
                if let rec = try? result.get(), let data = rec["data"] as? Data,
                   let item = try? JSONDecoder.store.decode(T.self, from: data) { out.append(item) }
            }
            guard let cursor = page.queryCursor else { break }
            page = try await db.records(continuingMatchFrom: cursor, desiredKeys: ["data"])
        }
        return out
    }

    func save<T: Record>(_ item: T, photo: Data?) async throws {
        let id = CKRecord.ID(recordName: item.id)
        let record: CKRecord
        do { record = try await db.record(for: id) }
        catch let e as CKError where e.code == .unknownItem { record = CKRecord(recordType: T.recordType, recordID: id) }

        record["data"] = try JSONEncoder.store.encode(item) as NSData
        for (k, v) in item.indexFields { record[k] = v as NSString }
        var tempURL: URL?
        if let photo {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try photo.write(to: url)
            record["photo"] = CKAsset(fileURL: url)
            tempURL = url
        }
        defer { if let tempURL { try? FileManager.default.removeItem(at: tempURL) } }
        _ = try await db.save(record)
    }

    func delete<T: Record>(_ type: T.Type, id: String) async throws {
        do { _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: id)) }
        catch let e as CKError where e.code == .unknownItem {}
    }

    func photo<T: Record>(_ type: T.Type, id: String) async throws -> Data? {
        let rid = CKRecord.ID(recordName: id)
        let results = try await db.records(for: [rid], desiredKeys: ["photo"])
        guard let rec = try results[rid]?.get(), let asset = rec["photo"] as? CKAsset,
              let url = asset.fileURL else { return nil }
        return try Data(contentsOf: url)
    }

    /// Push to managers whenever a new photo is waiting for review.
    func subscribeToPendingSubmissions() async {
        let sub = CKQuerySubscription(recordType: ClosingSubmission.recordType,
                                      predicate: NSPredicate(format: "status == %@", ReviewStatus.pending.rawValue),
                                      subscriptionID: "pending-closing-photos",
                                      options: [.firesOnRecordCreation, .firesOnRecordUpdate])
        let info = CKSubscription.NotificationInfo()
        info.title = "Closing check"
        info.alertBody = "A crew member sent a closing photo to review."
        info.soundName = "default"
        sub.notificationInfo = info
        _ = try? await db.save(sub)
    }
}
