import Foundation
import AppKit

public final class BatchRenameEngine: Sendable {
    public static let shared = BatchRenameEngine()
    
    private init() {}
    
    // MARK: - Vietnamese Diacritics Removal
    
    public func removeVietnameseDiacritics(from text: String) -> String {
        var str = text
        str = str.replacingOccurrences(of: "đ", with: "d")
        str = str.replacingOccurrences(of: "Đ", with: "D")
        
        let mutableString = NSMutableString(string: str) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformStripCombiningMarks, false)
        return mutableString as String
    }
    
    // MARK: - Case Transformation
    
    public func transformCase(_ text: String, to style: CaseTransform) -> String {
        switch style {
        case .none:
            return text
        case .lower:
            return text.lowercased()
        case .upper:
            return text.uppercased()
        case .title:
            return text.capitalized
        case .sentence:
            guard !text.isEmpty else { return "" }
            let first = text.prefix(1).uppercased()
            let rest = text.dropFirst().lowercased()
            return first + rest
        case .camelCase:
            let words = text.split { !$0.isLetter && !$0.isNumber }
            guard !words.isEmpty else { return text }
            let firstWord = words[0].lowercased()
            let restWords = words.dropFirst().map { $0.capitalized }
            return ([firstWord] + restWords).joined()
        case .snakeCase:
            let words = text.split { !$0.isLetter && !$0.isNumber }
            return words.map { $0.lowercased() }.joined(separator: "_")
        case .kebabCase:
            let words = text.split { !$0.isLetter && !$0.isNumber }
            return words.map { $0.lowercased() }.joined(separator: "-")
        }
    }
    
    // MARK: - Numbering Formatter
    
    public func formatNumber(_ number: Int, format: NumberingFormat) -> String {
        switch format {
        case .plain:
            return "\(number)"
        case .twoDigits:
            return String(format: "%02d", number)
        case .threeDigits:
            return String(format: "%03d", number)
        case .fourDigits:
            return String(format: "%04d", number)
        case .parentheses:
            return "(\(number))"
        case .brackets:
            return "[\(number)]"
        }
    }
    
    // MARK: - Generate Previews
    
    public func generatePreview(urls: [URL], rule: RenameRule) -> [RenamePreviewItem] {
        var items: [RenamePreviewItem] = []
        var plannedNewPaths: [String: Int] = [:] // Path -> Count (for detecting internal collisions)
        
        for (index, url) in urls.enumerated() {
            let originalName = url.lastPathComponent
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let fileSize = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            
            let ext = isDirectory ? "" : url.pathExtension
            let baseName = isDirectory ? originalName : url.deletingPathExtension().lastPathComponent
            
            var workingName = baseName
            
            // 0. Reset / Xóa sạch ký tự tên gốc
            if rule.clearOriginalName || rule.numberingPosition == .replace {
                workingName = rule.customBaseName
            }
            
            // 1. Find & Replace
            if rule.enableFindReplace && !rule.findText.isEmpty {
                if rule.isRegex {
                    if let regex = try? NSRegularExpression(pattern: rule.findText, options: rule.matchCase ? [] : [.caseInsensitive]) {
                        let range = NSRange(location: 0, length: workingName.utf16.count)
                        workingName = regex.stringByReplacingMatches(in: workingName, options: [], range: range, withTemplate: rule.replaceText)
                    }
                } else {
                    let options: NSString.CompareOptions = rule.matchCase ? [] : [.caseInsensitive]
                    workingName = workingName.replacingOccurrences(of: rule.findText, with: rule.replaceText, options: options)
                }
            }
            
            // 2. Diacritics Removal
            if rule.removeAccents {
                workingName = removeVietnameseDiacritics(from: workingName)
            }
            
            // 3. Case Transformation
            if rule.caseTransform != .none {
                workingName = transformCase(workingName, to: rule.caseTransform)
            }
            
            // 4. Sequence Numbering
            if rule.enableNumbering {
                let currentNum = rule.startNumber + (index * rule.step)
                let numStr = formatNumber(currentNum, format: rule.numberingFormat)
                
                if rule.clearOriginalName || rule.numberingPosition == .replace {
                    if workingName.isEmpty {
                        workingName = numStr
                    } else {
                        workingName = "\(workingName)\(rule.numberingSeparator)\(numStr)"
                    }
                } else {
                    switch rule.numberingPosition {
                    case .prefix:
                        workingName = "\(numStr)\(rule.numberingSeparator)\(workingName)"
                    case .suffix:
                        workingName = "\(workingName)\(rule.numberingSeparator)\(numStr)"
                    case .replace:
                        workingName = workingName.isEmpty ? numStr : "\(workingName)\(rule.numberingSeparator)\(numStr)"
                    }
                }
            }
            
            // 5. Prefix & Suffix (Thêm text trước / sau)
            if rule.enablePrefixSuffix || !rule.prefix.isEmpty || !rule.suffix.isEmpty {
                if !rule.prefix.isEmpty {
                    workingName = "\(rule.prefix)\(workingName)"
                }
                if !rule.suffix.isEmpty {
                    workingName = "\(workingName)\(rule.suffix)"
                }
            }
            
            // 6. Space formatting
            if rule.replaceSpacesWithDash {
                workingName = workingName.replacingOccurrences(of: " ", with: "-")
            } else if rule.replaceSpacesWithUnderscore {
                workingName = workingName.replacingOccurrences(of: " ", with: "_")
            }
            
            if rule.trimSpaces {
                workingName = workingName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Prevent empty file name
            if workingName.isEmpty {
                if rule.clearOriginalName || rule.numberingPosition == .replace {
                    let currentNum = rule.startNumber + (index * rule.step)
                    workingName = formatNumber(currentNum, format: rule.numberingFormat)
                } else {
                    workingName = baseName
                }
            }
            
            // 7. Extension formatting
            var finalExt = ext
            switch rule.extensionTransform {
            case .keep:
                break
            case .lowercase:
                finalExt = ext.lowercased()
            case .uppercase:
                finalExt = ext.uppercased()
            case .custom:
                if !rule.customExtension.isEmpty {
                    finalExt = rule.customExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                }
            }
            
            let finalFullName = finalExt.isEmpty ? workingName : "\(workingName).\(finalExt)"
            let parentDir = url.deletingLastPathComponent()
            let newURL = parentDir.appendingPathComponent(finalFullName)
            
            let isChanged = finalFullName != originalName
            
            // Collision detection
            plannedNewPaths[newURL.path, default: 0] += 1
            
            items.append(RenamePreviewItem(
                originalURL: url,
                originalName: originalName,
                originalBaseName: baseName,
                originalExtension: ext,
                newName: finalFullName,
                targetURL: newURL,
                isChanged: isChanged,
                hasCollision: false,
                collisionReason: nil,
                fileSize: fileSize,
                isDirectory: isDirectory
            ))
        }
        
        // Second pass: Mark collisions accurately
        for i in 0..<items.count {
            let item = items[i]
            guard item.isChanged else { continue }
            
            // A. Duplicate within batch?
            if let count = plannedNewPaths[item.targetURL.path], count > 1 {
                items[i].hasCollision = true
                items[i].collisionReason = "Trùng tên với tệp khác trong danh sách đổi tên"
                continue
            }
            
            // B. Already exists on disk (and is not one of the items in our batch)?
            if FileManager.default.fileExists(atPath: item.targetURL.path) {
                let isPartOfBatch = urls.contains { $0.path.lowercased() == item.targetURL.path.lowercased() }
                if !isPartOfBatch {
                    items[i].hasCollision = true
                    items[i].collisionReason = "Tệp tên này đã tồn tại sẵn trong thư mục"
                }
            }
        }
        
        return items
    }
    
    // MARK: - Execute Batch Rename with Safe Temporary Staging
    
    public func applyRename(items: [RenamePreviewItem]) throws -> RenameTransactionRecord {
        let validItems = items.filter { $0.isChanged && !$0.hasCollision }
        guard !validItems.isEmpty else {
            throw NSError(domain: "SFinderRename", code: 400, userInfo: [NSLocalizedDescriptionKey: "Không có tệp nào cần đổi tên hoặc các tệp đang bị trùng tên."])
        }
        
        let fileManager = FileManager.default
        var executedEntries: [RenameOperationEntry] = []
        
        // Stage 1: If any target path conflicts with an existing file in the batch (e.g. swap or cycle),
        // we use temporary intermediate files.
        var tempMappings: [(tempURL: URL, finalURL: URL, originalEntry: RenameOperationEntry)] = []
        
        for item in validItems {
            let tempName = ".sfinder_tmp_\(UUID().uuidString)_\(item.newName)"
            let tempURL = item.targetURL.deletingLastPathComponent().appendingPathComponent(tempName)
            
            // Move original to temp
            try fileManager.moveItem(at: item.originalURL, to: tempURL)
            let entry = RenameOperationEntry(originalPath: item.originalURL.path, newPath: item.targetURL.path)
            tempMappings.append((tempURL: tempURL, finalURL: item.targetURL, originalEntry: entry))
        }
        
        // Stage 2: Move from temp to final destination
        for mapping in tempMappings {
            try fileManager.moveItem(at: mapping.tempURL, to: mapping.finalURL)
            executedEntries.append(mapping.originalEntry)
        }
        
        // Record to Undo Journal
        let summary = "Đổi tên \(executedEntries.count) tệp"
        let record = try RenameUndoJournal.shared.record(entries: executedEntries, summary: summary)
        return record
    }
}
