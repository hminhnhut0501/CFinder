import Foundation
import AppKit
import Vision
import AudioToolbox
import Carbon

public struct OCRHotKeyPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let displayShortcut: String
    
    public init(id: String, title: String, keyCode: UInt32, modifiers: UInt32, displayShortcut: String) {
        self.id = id
        self.title = title
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayShortcut = displayShortcut
    }
}

public struct OCRHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public let timestamp: Date
    public var isURL: Bool
    public var isTable: Bool
    public var isBarcode: Bool
    
    public init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        isURL: Bool = false,
        isTable: Bool = false,
        isBarcode: Bool = false
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.isURL = isURL
        self.isTable = isTable
        self.isBarcode = isBarcode
    }
}

public final class ScreenOCREngine: @unchecked Sendable {
    public static let shared = ScreenOCREngine()
    
    private let defaults = UserDefaults.standard
    private let historyKey = "com.sfinder.ocr.recentHistory"
    private let fullHistoryKey = "com.sfinder.ocr.fullHistoryEntries"
    private let ignoreLineBreaksKey = "com.sfinder.ocr.ignoreLineBreaks"
    private let soundKey = "com.sfinder.ocr.playSound"
    private let hotKeyPresetKey = "com.sfinder.ocr.hotKeyPresetID"
    private let tableDetectionKey = "com.sfinder.ocr.tableDetection"
    private let autoOpenURLKey = "com.sfinder.ocr.autoOpenURL"
    private let detectQRKey = "com.sfinder.ocr.detectQR"
    
    // Custom shortcut storage
    private let customKeyCodeKey = "com.sfinder.ocr.customKeyCode"
    private let customModifiersKey = "com.sfinder.ocr.customModifiers"
    private let customDisplayKey = "com.sfinder.ocr.customDisplay"
    private let isCustomShortcutKey = "com.sfinder.ocr.isCustomShortcut"
    
    public static let ocrCompletedNotification = Notification.Name("com.sfinder.ocr.completed")
    public static let ocrFailedNotification = Notification.Name("com.sfinder.ocr.failed")
    public static let hotKeyChangedNotification = Notification.Name("com.sfinder.ocr.hotkeyChanged")
    public static let historyUpdatedNotification = Notification.Name("com.sfinder.ocr.historyUpdated")
    
    public static let availablePresets: [OCRHotKeyPreset] = [
        OCRHotKeyPreset(id: "opt_c", title: "Option + C (Mặc định)", keyCode: 8, modifiers: UInt32(optionKey), displayShortcut: "⌥C"),
        OCRHotKeyPreset(id: "opt_shift_c", title: "Option + Shift + C", keyCode: 8, modifiers: UInt32(optionKey | shiftKey), displayShortcut: "⌥⇧C"),
        OCRHotKeyPreset(id: "cmd_shift_c", title: "Command + Shift + C", keyCode: 8, modifiers: UInt32(cmdKey | shiftKey), displayShortcut: "⌘⇧C"),
        OCRHotKeyPreset(id: "ctrl_opt_c", title: "Control + Option + C", keyCode: 8, modifiers: UInt32(controlKey | optionKey), displayShortcut: "⌃⌥C"),
        OCRHotKeyPreset(id: "opt_x", title: "Option + X", keyCode: 7, modifiers: UInt32(optionKey), displayShortcut: "⌥X"),
        OCRHotKeyPreset(id: "opt_s", title: "Option + S", keyCode: 1, modifiers: UInt32(optionKey), displayShortcut: "⌥S"),
    ]
    
    // MARK: - Shortcut Management
    
    public var isCustomShortcut: Bool {
        get { defaults.bool(forKey: isCustomShortcutKey) }
        set { defaults.set(newValue, forKey: isCustomShortcutKey) }
    }
    
    public var currentPreset: OCRHotKeyPreset {
        if isCustomShortcut {
            let code = UInt32(defaults.integer(forKey: customKeyCodeKey))
            let mods = UInt32(defaults.integer(forKey: customModifiersKey))
            let display = defaults.string(forKey: customDisplayKey) ?? "⌥C"
            return OCRHotKeyPreset(id: "custom", title: "Phím tuỳ chỉnh", keyCode: code, modifiers: mods, displayShortcut: display)
        }
        let savedID = defaults.string(forKey: hotKeyPresetKey) ?? "opt_c"
        return Self.availablePresets.first(where: { $0.id == savedID }) ?? Self.availablePresets[0]
    }
    
    public func setPreset(id: String) {
        if let preset = Self.availablePresets.first(where: { $0.id == id }) {
            isCustomShortcut = false
            defaults.set(preset.id, forKey: hotKeyPresetKey)
            NotificationCenter.default.post(name: Self.hotKeyChangedNotification, object: preset)
        }
    }
    
    public func setCustomHotKey(keyCode: UInt32, modifiers: UInt32, display: String) {
        defaults.set(Int(keyCode), forKey: customKeyCodeKey)
        defaults.set(Int(modifiers), forKey: customModifiersKey)
        defaults.set(display, forKey: customDisplayKey)
        isCustomShortcut = true
        let customPreset = OCRHotKeyPreset(id: "custom", title: "Phím tuỳ chỉnh", keyCode: keyCode, modifiers: modifiers, displayShortcut: display)
        NotificationCenter.default.post(name: Self.hotKeyChangedNotification, object: customPreset)
    }
    
    public func resetToDefaultHotKey() {
        setPreset(id: "opt_c")
    }
    
    // MARK: - Configuration Properties
    
    public var ignoreLineBreaks: Bool {
        get { defaults.bool(forKey: ignoreLineBreaksKey) }
        set { defaults.set(newValue, forKey: ignoreLineBreaksKey) }
    }
    
    public var tableDetection: Bool {
        get { defaults.bool(forKey: tableDetectionKey) }
        set { defaults.set(newValue, forKey: tableDetectionKey) }
    }
    
    public var autoOpenURL: Bool {
        get { defaults.bool(forKey: autoOpenURLKey) }
        set { defaults.set(newValue, forKey: autoOpenURLKey) }
    }
    
    public var detectQR: Bool {
        get {
            if defaults.object(forKey: detectQRKey) == nil { return true }
            return defaults.bool(forKey: detectQRKey)
        }
        set { defaults.set(newValue, forKey: detectQRKey) }
    }
    
    public var playSound: Bool {
        get {
            if defaults.object(forKey: soundKey) == nil { return true }
            return defaults.bool(forKey: soundKey)
        }
        set { defaults.set(newValue, forKey: soundKey) }
    }
    
    // MARK: - History Management
    
    public var recentHistory: [String] {
        get { defaults.stringArray(forKey: historyKey) ?? [] }
        set {
            let trimmed = Array(newValue.prefix(15))
            defaults.set(trimmed, forKey: historyKey)
        }
    }
    
    public var fullHistory: [OCRHistoryEntry] {
        get {
            guard let data = defaults.data(forKey: fullHistoryKey),
                  let entries = try? JSONDecoder().decode([OCRHistoryEntry].self, from: data) else {
                return []
            }
            return entries
        }
        set {
            let trimmed = Array(newValue.prefix(100))
            if let data = try? JSONEncoder().encode(trimmed) {
                defaults.set(data, forKey: fullHistoryKey)
                NotificationCenter.default.post(name: Self.historyUpdatedNotification, object: nil)
            }
        }
    }
    
    public func deleteHistoryEntry(id: UUID) {
        var current = fullHistory
        current.removeAll(where: { $0.id == id })
        fullHistory = current
    }
    
    public func clearHistory() {
        recentHistory = []
        fullHistory = []
    }
    
    private init() {}
    
    // MARK: - Core Recognition Engine
    
    public func recognize(image: CGImage) async throws -> String {
        // 1. Check for Barcodes / QR Code if enabled
        if detectQR {
            if let barcodeResult = try? await recognizeBarcodes(image: image), !barcodeResult.isEmpty {
                return barcodeResult
            }
        }
        
        // 2. Perform OCR Text Recognition with Apple Vision
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { [weak self] request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                guard let self = self else {
                    continuation.resume(returning: "")
                    return
                }
                
                if observations.isEmpty {
                    continuation.resume(returning: "")
                    return
                }
                
                // Mode A: Table Detection (Format as Tab-Separated TSV for Excel/Sheets)
                if self.tableDetection {
                    let formattedTable = self.formatObservationsAsTable(observations)
                    continuation.resume(returning: formattedTable)
                    return
                }
                
                // Mode B: Standard Reading Order (Top-Down, Left-to-Right)
                let sorted = observations.sorted { obs1, obs2 in
                    let y1 = obs1.boundingBox.origin.y
                    let y2 = obs2.boundingBox.origin.y
                    if abs(y1 - y2) < 0.025 {
                        return obs1.boundingBox.origin.x < obs2.boundingBox.origin.x
                    }
                    return y1 > y2
                }
                
                let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
                let recognizedText: String
                if self.ignoreLineBreaks {
                    recognizedText = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    recognizedText = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                continuation.resume(returning: recognizedText)
            }
            
            // Maximum accuracy with dedicated Vietnamese language model
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["vi-VN", "en-US", "vi"]
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Barcode & QR Code Recognition
    
    private func recognizeBarcodes(image: CGImage) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                guard let results = request.results as? [VNBarcodeObservation], !results.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let payloads = results.compactMap { $0.payloadStringValue }
                if let first = payloads.first, !first.isEmpty {
                    continuation.resume(returning: first)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Table Detection Formatting
    
    private func formatObservationsAsTable(_ observations: [VNRecognizedTextObservation]) -> String {
        // Group observations into rows based on vertical proximity (y threshold ~ 0.03)
        var rows: [[VNRecognizedTextObservation]] = []
        
        let sortedByY = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
        
        for obs in sortedByY {
            var added = false
            for i in 0..<rows.count {
                if let representative = rows[i].first {
                    if abs(representative.boundingBox.origin.y - obs.boundingBox.origin.y) < 0.035 {
                        rows[i].append(obs)
                        added = true
                        break
                    }
                }
            }
            if !added {
                rows.append([obs])
            }
        }
        
        // For each row, sort columns from left to right (x ascending) and join with Tab
        var resultRows: [String] = []
        for row in rows {
            let sortedCols = row.sorted { $0.boundingBox.origin.x < $1.boundingBox.origin.x }
            let colStrings = sortedCols.compactMap { $0.topCandidates(1).first?.string }
            resultRows.append(colStrings.joined(separator: "\t"))
        }
        
        return resultRows.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Interactive Screen Capture (Single Region)
    
    public func captureScreenInteractively() async throws -> String {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sfinder_ocr_\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tempURL.path]
        
        try process.run()
        process.waitUntilExit()
        
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            return ""
        }
        
        guard let imageSource = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return ""
        }
        
        let recognizedText = try await recognize(image: cgImage)
        
        if !recognizedText.isEmpty {
            handleSuccessfulOCR(text: recognizedText)
        } else {
            notifyNoTextFound()
        }
        
        return recognizedText
    }
    
    // MARK: - Multi-Region Capture (TRex Capture Multi-Region Style)
    
    public func captureMultiRegionInteractively() async throws -> String {
        var accumulatedTexts: [String] = []
        
        for regionIndex in 1...10 {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sfinder_multi_\(regionIndex)_\(UUID().uuidString).png")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", tempURL.path]
            
            try process.run()
            process.waitUntilExit()
            
            // If user pressed Esc, finish multi-region session
            guard FileManager.default.fileExists(atPath: tempURL.path) else {
                try? FileManager.default.removeItem(at: tempURL)
                break
            }
            
            if let imageSource = CGImageSourceCreateWithURL(tempURL as CFURL, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
                let piece = try await recognize(image: cgImage)
                if !piece.isEmpty {
                    accumulatedTexts.append(piece)
                    if playSound {
                        AudioServicesPlaySystemSound(1108)
                    }
                }
            }
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        guard !accumulatedTexts.isEmpty else {
            notifyNoTextFound()
            return ""
        }
        
        let separator = ignoreLineBreaks ? " " : "\n\n"
        let fullMergedText = accumulatedTexts.joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
        
        handleSuccessfulOCR(text: fullMergedText, multiRegionCount: accumulatedTexts.count)
        return fullMergedText
    }
    
    // MARK: - Clipboard OCR
    
    public func recognizeFromClipboard() async throws -> String {
        let pasteboard = NSPasteboard.general
        var targetImage: CGImage?
        
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let first = images.first {
            targetImage = extractCGImage(from: first)
        } else if let tiff = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
                  let rep = NSBitmapImageRep(data: tiff) {
            targetImage = rep.cgImage
        }
        
        guard let cgImage = targetImage else {
            notifyFailure(message: "Không tìm thấy hình ảnh nào trong Clipboard.")
            return ""
        }
        
        let text = try await recognize(image: cgImage)
        if !text.isEmpty {
            handleSuccessfulOCR(text: text)
        } else {
            notifyNoTextFound()
        }
        return text
    }
    
    private func extractCGImage(from image: NSImage) -> CGImage? {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first, let cg = rep.cgImage {
            return cg
        }
        var rect = NSRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.cgImage
    }
    
    // MARK: - Post-OCR Handlers & Smart Automation
    
    private func handleSuccessfulOCR(text: String, multiRegionCount: Int = 1) {
        copyToClipboard(text: text)
        
        let isURL = isWebURL(text)
        let isTable = tableDetection || text.contains("\t")
        
        // Save to recent string array
        addToHistory(text)
        
        // Save to full entry history
        let newEntry = OCRHistoryEntry(
            text: text,
            timestamp: Date(),
            isURL: isURL,
            isTable: isTable,
            isBarcode: text.hasPrefix("http") && detectQR
        )
        var all = fullHistory
        all.insert(newEntry, at: 0)
        fullHistory = all
        
        if playSound {
            AudioServicesPlaySystemSound(1108) // Shutter click
        }
        
        // Smart Automation: Auto-open URL if enabled
        if isURL && autoOpenURL, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            NSWorkspace.shared.open(url)
        }
        
        notifyResult(text: text, isURL: isURL, isTable: isTable, multiRegionCount: multiRegionCount)
    }
    
    public func isWebURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://") {
            return URL(string: trimmed) != nil
        }
        return false
    }
    
    public func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    private func addToHistory(_ text: String) {
        var current = recentHistory
        current.removeAll(where: { $0 == text })
        current.insert(text, at: 0)
        recentHistory = current
    }
    
    private func notifyResult(text: String, isURL: Bool, isTable: Bool, multiRegionCount: Int) {
        let count = text.count
        let preview = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: "  ")
        let shortPreview = preview.count > 80 ? String(preview.prefix(80)) + "..." : preview
        
        let titleSuffix = multiRegionCount > 1 ? " (Gộp \(multiRegionCount) vùng)" : ""
        let title = "CFinder OCR — Đã sao chép\(titleSuffix)"
        
        postNotification(
            title: title,
            message: "✓ Đã nhận diện \(count) ký tự: \"\(shortPreview)\""
        )
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.ocrCompletedNotification,
                object: self,
                userInfo: [
                    "text": text,
                    "count": count,
                    "preview": shortPreview,
                    "isURL": isURL,
                    "isTable": isTable,
                    "multiRegionCount": multiRegionCount
                ]
            )
        }
    }
    
    private func notifyNoTextFound() {
        postNotification(
            title: "CFinder OCR",
            message: "Không phát hiện văn bản nào trong vùng bạn vừa quét."
        )
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.ocrFailedNotification,
                object: self,
                userInfo: ["message": "Không phát hiện văn bản nào trong vùng bạn vừa quét."]
            )
        }
    }
    
    private func notifyFailure(message: String) {
        postNotification(
            title: "CFinder OCR — Thông báo",
            message: message
        )
        
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.ocrFailedNotification,
                object: self,
                userInfo: ["message": message]
            )
        }
    }
    
    private func postNotification(title: String, message: String) {
        let center = NSUserNotificationCenter.default
        let notif = NSUserNotification()
        notif.title = title
        notif.informativeText = message
        center.deliver(notif)
    }
}
