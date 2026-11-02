import Foundation

public final class RenameUndoJournal: Sendable {
    public static let shared = RenameUndoJournal()
    
    private var fileManager: FileManager { FileManager.default }
    
    private var journalDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SFinder/Journal", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    private init() {}
    
    public func record(entries: [RenameOperationEntry], summary: String) throws -> RenameTransactionRecord {
        let record = RenameTransactionRecord(entries: entries, summary: summary)
        let fileURL = journalDirectoryURL.appendingPathComponent("tx_\(record.timestamp.timeIntervalSince1970)_\(record.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: .atomic)
        return record
    }
    
    public func listTransactions() -> [RenameTransactionRecord] {
        guard let files = try? fileManager.contentsOfDirectory(at: journalDirectoryURL, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return []
        }
        
        let jsonFiles = files.filter { $0.pathExtension == "json" }.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return d1 > d2
        }
        
        var records: [RenameTransactionRecord] = []
        let decoder = JSONDecoder()
        
        for file in jsonFiles {
            if let data = try? Data(contentsOf: file),
               let rec = try? decoder.decode(RenameTransactionRecord.self, from: data) {
                records.append(rec)
            }
        }
        return records
    }
    
    public func undoLast() throws -> [RenameOperationEntry]? {
        guard let files = try? fileManager.contentsOfDirectory(at: journalDirectoryURL, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
            return nil
        }
        
        let jsonFiles = files.filter { $0.pathExtension == "json" }.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return d1 > d2
        }
        
        guard let latestFile = jsonFiles.first,
              let data = try? Data(contentsOf: latestFile),
              let record = try? JSONDecoder().decode(RenameTransactionRecord.self, from: data) else {
            return nil
        }
        
        var revertedEntries: [RenameOperationEntry] = []
        
        // Reverse operations: rename current (newPath) back to originalPath
        for entry in record.entries.reversed() {
            let currentURL = URL(fileURLWithPath: entry.newPath)
            let originalURL = URL(fileURLWithPath: entry.originalPath)
            
            if fileManager.fileExists(atPath: currentURL.path) && !fileManager.fileExists(atPath: originalURL.path) {
                try fileManager.moveItem(at: currentURL, to: originalURL)
                revertedEntries.append(entry)
            }
        }
        
        try? fileManager.removeItem(at: latestFile)
        return revertedEntries
    }
}
