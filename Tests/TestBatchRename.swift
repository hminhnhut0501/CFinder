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
    rule.enableNumbering = false
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
    rule.enableNumbering = false
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
    rule.enableNumbering = false
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

// 7. Clear Original Name (Reset toàn bộ ký tự tên cũ)
testCase("Xóa sạch ký tự tên cũ (clearOriginalName) và đánh số mới") {
    let f1 = tempDir.appendingPathComponent("Complex_Messy_Name_123.jpg")
    let f2 = tempDir.appendingPathComponent("Another_Messy_File_456.jpg")
    try "img1".write(to: f1, atomically: true, encoding: .utf8)
    try "img2".write(to: f2, atomically: true, encoding: .utf8)
    
    // A. Xóa sạch tên, chỉ lấy số thứ tự
    var rule1 = RenameRule()
    rule1.clearOriginalName = true
    rule1.enableNumbering = true
    rule1.numberingFormat = .twoDigits
    let prev1 = BatchRenameEngine.shared.generatePreview(urls: [f1, f2], rule: rule1)
    assert(prev1[0].newName == "01.jpg")
    assert(prev1[1].newName == "02.jpg")
    print("  ✓ Xóa sạch ký tự tên cũ -> chỉ lấy số: '01.jpg', '02.jpg'")
    
    // B. Xóa sạch tên cũ và đặt tên mới
    var rule2 = RenameRule()
    rule2.clearOriginalName = true
    rule2.customBaseName = "Photo"
    rule2.enableNumbering = true
    rule2.numberingFormat = .twoDigits
    let prev2 = BatchRenameEngine.shared.generatePreview(urls: [f1, f2], rule: rule2)
    assert(prev2[0].newName == "Photo_01.jpg")
    assert(prev2[1].newName == "Photo_02.jpg")
    print("  ✓ Xóa sạch tên cũ và đặt tên mới + số: 'Photo_01.jpg', 'Photo_02.jpg'")
}

// 8. Delete X Characters Front / Back (Xóa x ký tự phía trước / phía sau)
testCase("Xóa x ký tự phía trước và phía sau (deleteFirstN & deleteLastN)") {
    let f1 = tempDir.appendingPathComponent("IMG_Sunset_RAW_backup.jpg")
    let f2 = tempDir.appendingPathComponent("[SubTeam] Tập 01 [1080p].mp4")
    let f3 = tempDir.appendingPathComponent("abc.txt")
    try "data1".write(to: f1, atomically: true, encoding: .utf8)
    try "data2".write(to: f2, atomically: true, encoding: .utf8)
    try "data3".write(to: f3, atomically: true, encoding: .utf8)
    
    // A. Xóa 4 ký tự phía trước ("IMG_")
    var ruleA = RenameRule()
    ruleA.enableNumbering = false
    ruleA.deleteFirstN = 4
    let prevA = BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleA)
    assert(prevA[0].newName == "Sunset_RAW_backup.jpg")
    print("  ✓ Xóa 4 ký tự đầu: 'IMG_Sunset_RAW_backup.jpg' -> '\(prevA[0].newName)'")
    
    // B. Xóa 7 ký tự phía sau ("_backup")
    var ruleB = RenameRule()
    ruleB.enableNumbering = false
    ruleB.deleteLastN = 7
    let prevB = BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleB)
    assert(prevB[0].newName == "IMG_Sunset_RAW.jpg")
    print("  ✓ Xóa 7 ký tự cuối: 'IMG_Sunset_RAW_backup.jpg' -> '\(prevB[0].newName)'")
    
    // C. Xóa cả phía trước lẫn phía sau (Xóa 4 đầu "IMG_", 7 cuối "_backup")
    var ruleC = RenameRule()
    ruleC.enableNumbering = false
    ruleC.deleteFirstN = 4
    ruleC.deleteLastN = 7
    let prevC = BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleC)
    assert(prevC[0].newName == "Sunset_RAW.jpg")
    print("  ✓ Xóa đồng thời 4 ký tự đầu và 7 ký tự cuối: -> '\(prevC[0].newName)'")
    
    // D. Xóa tiền tố fan-sub và hậu tố chất lượng video
    var ruleD = RenameRule()
    ruleD.enableNumbering = false
    ruleD.deleteFirstN = 10 // "[SubTeam] "
    ruleD.deleteLastN = 8  // " [1080p]"
    let prevD = BatchRenameEngine.shared.generatePreview(urls: [f2], rule: ruleD)
    assert(prevD[0].newName == "Tập 01.mp4")
    print("  ✓ Cắt tag đầu và đuôi: '[SubTeam] Tập 01 [1080p].mp4' -> '\(prevD[0].newName)'")
    
    // E. Xóa nhiều hơn hoặc bằng độ dài chuỗi (an toàn, không crash, fallback về tên gốc)
    var ruleE = RenameRule()
    ruleE.enableNumbering = false
    ruleE.deleteFirstN = 100
    let prevE = BatchRenameEngine.shared.generatePreview(urls: [f3], rule: ruleE)
    assert(prevE[0].newName == "abc.txt")
    print("  ✓ Xóa vượt quá độ dài ký tự: an toàn, không crash, fallback chuẩn xác")
    
    // F. Xóa x ký tự kết hợp thêm tiền tố mới và đánh số thứ tự
    var ruleF = RenameRule()
    ruleF.deleteFirstN = 4 // Bỏ "IMG_"
    ruleF.deleteLastN = 7  // Bỏ "_backup"
    ruleF.prefix = "Vacation_"
    ruleF.enableNumbering = true
    ruleF.numberingFormat = .twoDigits
    let prevF = BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleF)
    assert(prevF[0].newName == "Vacation_Sunset_RAW_01.jpg")
    print("  ✓ Kết hợp xóa đầu/cuối + thêm tiền tố + đánh số: -> '\(prevF[0].newName)'")
}

// 9. Date Prefix (Thêm ngày định dạng YYMMDD_ trước tiên)
testCase("Thêm ngày định dạng YYMMDD_ trước tiên (Tự động lấy hôm nay)") {
    let f1 = tempDir.appendingPathComponent("MG_1480.MOV")
    let f2 = tempDir.appendingPathComponent("IMG_1483.MOV")
    try "mov1".write(to: f1, atomically: true, encoding: .utf8)
    try "mov2".write(to: f2, atomically: true, encoding: .utf8)
    
    // Fixed test date: 2026-11-19 12:00:00 UTC -> YYMMDD = 261119
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 19
    let testDate = Calendar(identifier: .gregorian).date(from: components)!
    
    // A. Cơ bản: Thêm ngày YYMMDD_ vào tệp gốc
    var ruleA = RenameRule()
    ruleA.enableNumbering = false
    ruleA.enableDatePrefix = true
    ruleA.datePrefixFormat = .yyMMdd_
    let prevA = BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleA, referenceDate: testDate)
    assert(prevA[0].newName == "261119_MG_1480.MOV")
    print("  ✓ Thêm ngày YYMMDD_: 'MG_1480.MOV' -> '\(prevA[0].newName)'")
    
    // B. Đúng theo trường hợp của người dùng:
    // Xóa tên cũ + Đánh số (01, 02) + Tiền tố "TG@daocuVIP_" + Hậu tố "_GMD" + Thêm ngày YYMMDD_ trước tiên
    var ruleB = RenameRule()
    ruleB.clearOriginalName = true
    ruleB.enableNumbering = true
    ruleB.numberingFormat = .twoDigits
    ruleB.numberingPosition = .prefix
    ruleB.prefix = "TG@daocuVIP_"
    ruleB.suffix = "_GMD"
    ruleB.enableDatePrefix = true
    ruleB.datePrefixFormat = .yyMMdd_
    
    let prevB = BatchRenameEngine.shared.generatePreview(urls: [f1, f2], rule: ruleB, referenceDate: testDate)
    assert(prevB[0].newName == "261119_TG@daocuVIP_01_GMD.MOV")
    assert(prevB[1].newName == "261119_TG@daocuVIP_02_GMD.MOV")
    print("  ✓ Kịch bản Studio của người dùng:")
    print("    - Tệp 1: 'MG_1480.MOV' -> '\(prevB[0].newName)'")
    print("    - Tệp 2: 'IMG_1483.MOV' -> '\(prevB[1].newName)'")
    
    // C. Khi tắt enableDatePrefix = false thì không thêm ngày
    ruleB.enableDatePrefix = false
    let prevC = BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleB, referenceDate: testDate)
    assert(prevC[0].newName == "TG@daocuVIP_01_GMD.MOV")
    print("  ✓ Khi tắt enableDatePrefix: '\(prevC[0].newName)' (không có ngày)")
    
    // D. Kiểm tra các định dạng khác
    ruleA.datePrefixFormat = .yyyyMMdd_
    assert(BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleA, referenceDate: testDate)[0].newName == "20261119_MG_1480.MOV")
    ruleA.datePrefixFormat = .yy_MM_dd_
    assert(BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleA, referenceDate: testDate)[0].newName == "26_11_19_MG_1480.MOV")
    ruleA.datePrefixFormat = .yyyy_MM_dd_
    assert(BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleA, referenceDate: testDate)[0].newName == "2026_11_19_MG_1480.MOV")
    ruleA.datePrefixFormat = .yyMMdd
    assert(BatchRenameEngine.shared.generatePreview(urls: [f1], rule: ruleA, referenceDate: testDate)[0].newName == "261119MG_1480.MOV")
    print("  ✓ Toàn bộ 5 định dạng ngày tháng đều hoạt động chính xác 100%")
}

print("\n================================================================================")
print("🎉 TOÀN BỘ 9/9 BỘ KIỂM THỬ ĐẠT 100% HOÀN HẢO!")
print("================================================================================")
