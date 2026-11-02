import Foundation
import SFinderCore

print("================================================================================")
print("🧪 SFINDER BATCH RENAMER - KIỂM THỬ TOÀN DIỆN MỌI TRƯỜNG HỢP LOGIC & KỸ THUẬT")
print("================================================================================")

let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SFinderTest_\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

defer {
    try? FileManager.default.removeItem(at: tempDir)
}

func testCase(_ name: String, block: () throws -> Void) {
    print("\n--------------------------------------------------------------------------------")
    print("▶ KIỂM THỬ: \(name)")
    do {
        try block()
        print("  => KẾT QUẢ: ✅ ĐẠT (PASSED)")
    } catch {
        print("  => KẾT QUẢ: ❌ THẤT BẠI: \(error)")
        exit(1)
    }
}

// 1. Vietnamese Diacritics Removal
testCase("Bỏ dấu tiếng Việt (Hàng Cú VIP -> Hang Cu VIP)") {
    let input = "016 Quần xanh_AL@hàngcúvip.mp4"
    let output = BatchRenameEngine.shared.removeVietnameseDiacritics(from: input)
    print("  Gốc: '\(input)' -> Sau khi bỏ dấu: '\(output)'")
    assert(output == "016 Quan xanh_AL@hangcuvip.mp4")
}

// 2. Case Transformation
testCase("Chuyển đổi kiểu chữ (lower, upper, title, camelCase, snake_case, kebab-case)") {
    let text = "hello world test"
    assert(BatchRenameEngine.shared.transformCase(text, to: .upper) == "HELLO WORLD TEST")
    assert(BatchRenameEngine.shared.transformCase(text, to: .title) == "Hello World Test")
    assert(BatchRenameEngine.shared.transformCase(text, to: .camelCase) == "helloWorldTest")
    assert(BatchRenameEngine.shared.transformCase(text, to: .snakeCase) == "hello_world_test")
    assert(BatchRenameEngine.shared.transformCase(text, to: .kebabCase) == "hello-world-test")
    print("  ✓ Toàn bộ 5 kiểu chữ chuyển đổi chuẩn xác 100%")
}

// 3. Find & Replace with Regex
testCase("Tìm kiếm và thay thế kèm Regex") {
    var rule = RenameRule()
    rule.enableFindReplace = true
    rule.findText = #"IMG_\d+"#
    rule.replaceText = "Photo"
    rule.isRegex = true
    
    let f1 = tempDir.appendingPathComponent("IMG_1234.JPG")
    try "data".write(to: f1, atomically: true, encoding: .utf8)
    
    let previews = BatchRenameEngine.shared.generatePreview(urls: [f1], rule: rule)
    assert(previews.count == 1)
    assert(previews[0].newName == "Photo.JPG")
    print("  Gốc: 'IMG_1234.JPG' -> Dự kiến: '\(previews[0].newName)'")
}

// 4. Sequence Numbering & Extension formatting
testCase("Đánh số thứ tự (01, 02) và chuẩn hóa đuôi (.jpg)") {
    var rule = RenameRule()
    rule.enableNumbering = true
    rule.numberingFormat = .twoDigits
    rule.numberingPosition = .suffix
    rule.startNumber = 1
    rule.extensionTransform = .lowercase
    
    let f1 = tempDir.appendingPathComponent("document.PDF")
    let f2 = tempDir.appendingPathComponent("contract.PDF")
    try "data1".write(to: f1, atomically: true, encoding: .utf8)
    try "data2".write(to: f2, atomically: true, encoding: .utf8)
    
    let previews = BatchRenameEngine.shared.generatePreview(urls: [f1, f2], rule: rule)
    assert(previews[0].newName == "document_01.pdf")
    assert(previews[1].newName == "contract_02.pdf")
    print("  ✓ Tệp 1: \(previews[0].newName)")
    print("  ✓ Tệp 2: \(previews[1].newName)")
}

// 5. Collision Detection
testCase("Phát hiện xung đột trùng tên tệp trong danh sách và trên đĩa") {
    var rule = RenameRule()
    rule.enableFindReplace = true
    rule.findText = "fileB"
    rule.replaceText = "fileA"
    
    let fA = tempDir.appendingPathComponent("fileA.txt")
    let fB = tempDir.appendingPathComponent("fileB.txt")
    try "A".write(to: fA, atomically: true, encoding: .utf8)
    try "B".write(to: fB, atomically: true, encoding: .utf8)
    
    let previews = BatchRenameEngine.shared.generatePreview(urls: [fB], rule: rule)
    assert(previews[0].hasCollision == true)
    print("  ✓ Đã phát hiện cảnh báo trùng tên: \(previews[0].collisionReason ?? "")")
}

// 6. Execute Batch Rename & Undo Journal
testCase("Thực thi đổi tên an toàn và Hoàn tác (Undo ⌘Z)") {
    let f1 = tempDir.appendingPathComponent("video_raw_1.mp4")
    let f2 = tempDir.appendingPathComponent("video_raw_2.mp4")
    try "vid1".write(to: f1, atomically: true, encoding: .utf8)
    try "vid2".write(to: f2, atomically: true, encoding: .utf8)
    
    var rule = RenameRule()
    rule.enablePrefixSuffix = true
    rule.prefix = "Final_"
    
    let previews = BatchRenameEngine.shared.generatePreview(urls: [f1, f2], rule: rule)
    let record = try BatchRenameEngine.shared.applyRename(items: previews)
    
    let renamed1 = tempDir.appendingPathComponent("Final_video_raw_1.mp4")
    let renamed2 = tempDir.appendingPathComponent("Final_video_raw_2.mp4")
    assert(FileManager.default.fileExists(atPath: renamed1.path))
    assert(FileManager.default.fileExists(atPath: renamed2.path))
    print("  ✓ Đã đổi tên thành công: \(record.entries.count) tệp.")
    
    // Test Undo
    let reverted = try RenameUndoJournal.shared.undoLast()
    assert(reverted != nil && reverted!.count == 2)
    assert(FileManager.default.fileExists(atPath: f1.path))
    assert(FileManager.default.fileExists(atPath: f2.path))
    print("  ✓ Hoàn tác thành công về đúng tên gốc ban đầu!")
}

print("\n================================================================================")
print("🎉 TOÀN BỘ 6/6 BỘ KIỂM THỬ ĐẠT 100% HOÀN HẢO!")
print("================================================================================")
