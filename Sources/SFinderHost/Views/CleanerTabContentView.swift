import SwiftUI
import AppKit
import AudioToolbox
import SFinderCore

// MARK: - Cleaner & App Uninstaller Tab (CleanMyMac & AppCleaner Replacement)

public struct CleanerTabContentView: View {
    @ObservedObject private var cleaner = SystemCleanerManager.shared
    @State private var dropTargetHovered: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            subTabBar
            
            Group {
                switch cleaner.selectedSection {
                case 1:
                    appUninstallerSection
                case 2:
                    largeFilesSection
                default:
                    junkCleanerSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .onAppear {
            if cleaner.junkCategories.first?.sizeBytes == 0 && !cleaner.isScanningJunk {
                cleaner.scanJunk()
            }
            if cleaner.installedApps.isEmpty && !cleaner.isScanningApps {
                cleaner.scanInstalledApps()
            }
        }
        .onDisappear {
            cleaner.releaseScanCache()
        }
    }

    // MARK: - Sub Tab Bar

    private var subTabBar: some View {
        HStack(spacing: 6) {
            subTabButton(index: 0, title: "Dọn dẹp rác hệ thống", icon: "sparkles")
            subTabButton(index: 1, title: "Gỡ ứng dụng tận gốc", icon: "trash.fill")
            subTabButton(index: 2, title: "Tệp tin dung lượng lớn", icon: "doc.badge.gearshape")
            Spacer()
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func subTabButton(index: Int, title: String, icon: String) -> some View {
        let isSelected = (cleaner.selectedSection == index)
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                cleaner.selectedSection = index
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color(hex: "06B6D4") : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 1. Junk Cleaner Section (CleanMyMac Replacement)

    private var junkCleanerSection: some View {
        VStack(spacing: 14) {
            // Hero banner
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "06B6D4").opacity(0.18))
                        .frame(width: 54, height: 54)
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color(hex: "22D3EE"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Tổng rác hệ thống phát hiện:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text(CleanerByteFormatter.format(cleaner.totalJunkBytes))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button(action: { cleaner.scanJunk() }) {
                        HStack(spacing: 5) {
                            if cleaner.isScanningJunk {
                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(cleaner.isScanningJunk ? "Đang quét..." : "Quét lại")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .disabled(cleaner.isScanningJunk || cleaner.isCleaningJunk)

                    Button(action: {
                        cleaner.cleanSelectedJunk()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            AudioServicesPlaySystemSound(1001)
                            FloatingHUDController.shared.showToast(
                                icon: "sparkles",
                                iconColor: Color(hex: "22D3EE"),
                                title: "Dọn dẹp rác thành công",
                                subtitle: "Đã làm sạch dữ liệu đệm và rác hệ thống"
                            )
                        }
                    }) {
                        HStack(spacing: 5) {
                            if cleaner.isCleaningJunk {
                                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "trash.fill")
                            }
                            Text(cleaner.isCleaningJunk ? "Đang dọn dẹp..." : "Dọn dẹp an toàn")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "22D3EE")))
                    }
                    .buttonStyle(.plain)
                    .disabled(cleaner.totalJunkBytes == 0 || cleaner.isCleaningJunk)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 0.8))

            // Categories list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach($cleaner.junkCategories) { $cat in
                        junkCategoryRow(category: $cat)
                    }
                }
            }
        }
    }

    private func junkCategoryRow(category: Binding<JunkCategoryItem>) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: category.isSelected)
                .toggleStyle(CheckboxToggleStyle())
                .labelsHidden()

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: category.wrappedValue.iconColorHex).opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: category.wrappedValue.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: category.wrappedValue.iconColorHex))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.wrappedValue.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(category.wrappedValue.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(category.wrappedValue.sizeFormatted)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(category.wrappedValue.sizeBytes > 0 ? .white : .white.opacity(0.4))
                Text("\(category.wrappedValue.fileCount) tệp")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.07), lineWidth: 0.5))
    }

    // MARK: - 2. App Uninstaller Section (AppCleaner Replacement)

    private var appUninstallerSection: some View {
        HStack(spacing: 14) {
            // Left list of installed apps
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                    TextField("Tìm kiếm ứng dụng...", text: $cleaner.appSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !cleaner.appSearchQuery.isEmpty {
                        Button(action: { cleaner.appSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.4))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 4) {
                        let filtered = cleaner.installedApps.filter {
                            cleaner.appSearchQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(cleaner.appSearchQuery)
                        }

                        ForEach(filtered) { app in
                            installedAppRow(app: app)
                        }
                    }
                }
            }
            .frame(width: 320)

            Divider().background(Color.white.opacity(0.10))

            // Right inspector or Drag & Drop zone
            VStack {
                if let selected = cleaner.selectedApp {
                    appLeftoverInspector(app: selected)
                } else {
                    dragDropPlaceholderView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func installedAppRow(app: InstalledAppItem) -> some View {
        let isSelected = (cleaner.selectedApp?.id == app.id)
        return Button(action: {
            cleaner.inspectApp(app)
        }) {
            HStack(spacing: 10) {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(app.appSizeFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? Color(hex: "06B6D4") : .white.opacity(0.2))
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.white.opacity(0.10) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func appLeftoverInspector(app: InstalledAppItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // App Header
            HStack(spacing: 14) {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Text(app.bundleIdentifier)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Tổng giải phóng:")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.5))
                    Text(app.totalSizeFormatted)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "EF4444"))
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

            Text("Các tệp thừa & dữ liệu liên quan phát hiện:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))

            // Leftovers list
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 6) {
                    // Main .app file
                    HStack(spacing: 10) {
                        Image(systemName: "app.gift.fill")
                            .foregroundColor(Color(hex: "0EA5E9"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Ứng dụng chính (.app)")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white)
                            Text(app.bundleURL.path)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(app.appSizeFormatted)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))

                    ForEach(app.leftovers) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(Color(hex: "F59E0B"))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.categoryName)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.white)
                                Text(item.url.path)
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(item.sizeFormatted)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.03)))
                    }
                }
            }

            Spacer()

            // Uninstall Action Button
            HStack {
                Button("Hủy chọn") {
                    cleaner.selectedApp = nil
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.6))
                .font(.system(size: 12))

                Spacer()

                Button(action: {
                    let appName = cleaner.selectedApp?.name ?? "Ứng dụng"
                    cleaner.uninstallSelectedApp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        AudioServicesPlaySystemSound(1001)
                        FloatingHUDController.shared.showToast(
                            icon: "trash.fill",
                            iconColor: Color(hex: "EF4444"),
                            title: "Gỡ ứng dụng thành công",
                            subtitle: "Đã chuyển \(appName) và toàn bộ tệp thừa vào Thùng rác"
                        )
                    }
                }) {
                    HStack(spacing: 6) {
                        if cleaner.isUninstalling {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text(cleaner.isUninstalling ? "Đang gỡ bỏ..." : "Gỡ cài đặt tận gốc")
                    }
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "EF4444")))
                }
                .buttonStyle(.plain)
                .disabled(cleaner.isUninstalling)
            }
        }
    }

    private var dragDropPlaceholderView: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "06B6D4").opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(Color(hex: "06B6D4"))
            }

            Text("Gỡ Cài Đặt Ứng Dụng Tận Gốc")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            Text("Chọn một ứng dụng từ danh sách bên trái hoặc kéo thả tệp .app từ Finder vào đây để quét và xóa sạch các tệp thừa.")
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    Color.white.opacity(dropTargetHovered ? 0.3 : 0.08),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargetHovered) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let fileURL = url, fileURL.pathExtension == "app" {
                    Task { @MainActor in
                        self.cleaner.inspectExternalApp(at: fileURL)
                    }
                }
            }
            return true
        }
    }

    // MARK: - 3. Large Files Section

    private var largeFilesSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Quét các tệp tin lớn (> 150MB) trong Downloads, Documents, Movies:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Button(action: { cleaner.scanLargeFiles(minSizeMB: 150) }) {
                    HStack(spacing: 5) {
                        if cleaner.isScanningLargeFiles {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(cleaner.isScanningLargeFiles ? "Đang quét..." : "Quét tệp lớn")
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }

            if cleaner.largeFiles.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.badge.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.2))
                    Text("Bấm 'Quét tệp lớn' để phát hiện các video, file nén nặng đang chiếm ổ cứng.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(cleaner.largeFiles) { item in
                            HStack(spacing: 10) {
                                Text(item.fileExtension)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color(hex: "06B6D4").opacity(0.3))
                                    .cornerRadius(4)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(item.url.path)
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.white.opacity(0.4))
                                        .lineLimit(1)
                                }

                                Spacer()

                                Text(item.sizeFormatted)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)

                                Button(action: {
                                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                }) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .help("Hiện trong Finder")

                                Button(action: {
                                    cleaner.recycleLargeFile(item)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "EF4444"))
                                }
                                .buttonStyle(.plain)
                                .help("Chuyển vào Thùng rác")
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                        }
                    }
                }
            }
        }
    }
}
