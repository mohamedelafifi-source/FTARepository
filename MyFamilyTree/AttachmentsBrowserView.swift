//
//  AttachmentsBrowserView.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 2/6/26.
//
//  Browse all attachments from the Attachments folder
//

import SwiftUI
import QuickLook

struct AttachmentsBrowserView: View {
    let folderBookmark: Data
    
    @State private var folderURL: URL?
    @State private var attachments: [AttachmentFile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var previewItem: AttachmentPreviewItem?
    @State private var searchText = ""
    @State private var groupBy: GroupingOption = .member
    @Environment(\.dismiss) private var dismiss
    
    enum GroupingOption: String, CaseIterable {
        case member = "By Person"
        case all = "All Files"
    }
    
    // Grid layout
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
    ]
    
    var filteredAttachments: [AttachmentFile] {
        if searchText.isEmpty {
            return attachments
        }
        return attachments.filter { attachment in
            attachment.memberName.localizedCaseInsensitiveContains(searchText) ||
            attachment.fileName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var groupedAttachments: [(String, [AttachmentFile])] {
        if groupBy == .all {
            return [("All", filteredAttachments)]
        }
        
        let grouped = Dictionary(grouping: filteredAttachments) { $0.memberName }
        return grouped.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading attachments...")
                } else if let error = errorMessage {
                    errorView(error)
                } else if attachments.isEmpty {
                    emptyStateView
                } else if filteredAttachments.isEmpty {
                    noResultsView
                } else {
                    contentView
                }
            }
            .navigationTitle("All Attachments (\(filteredAttachments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search by person or filename")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !attachments.isEmpty {
                        Menu {
                            Picker("Group By", selection: $groupBy) {
                                ForEach(GroupingOption.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.inline)
                            
                            Divider()
                            
                            Button {
                                attachments.sort { $0.memberName < $1.memberName }
                            } label: {
                                Label("Sort by Person", systemImage: "person")
                            }
                            Button {
                                attachments.sort { $0.fileName < $1.fileName }
                            } label: {
                                Label("Sort by Filename", systemImage: "doc")
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }
            .onAppear {
                loadAttachments()
            }
            .sheet(item: $previewItem) { item in
                AttachmentFullPreview(url: item.url, memberName: item.memberName)
            }
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groupedAttachments, id: \.0) { groupName, files in
                    VStack(alignment: .leading, spacing: 12) {
                        if groupBy == .member {
                            HStack {
                                Text(groupName)
                                    .font(.headline)
                                Text("(\(files.count))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(files) { file in
                                AttachmentThumbnailCard(file: file, folderURL: folderURL)
                                    .onTapGesture {
                                        guard let folderURL = folderURL else { return }
                                        let attachmentsFolder = folderURL.appendingPathComponent("Attachments", isDirectory: true)
                                        let fileURL = attachmentsFolder.appendingPathComponent(file.fileName)
                                        previewItem = AttachmentPreviewItem(url: fileURL, memberName: file.memberName)
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Empty States
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            Text("Error Loading Attachments")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "paperclip")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Attachments Yet")
                .font(.headline)
            Text("Add attachments through the Family Tree by selecting a member in focused view")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Results")
                .font(.headline)
            Text("No attachments match '\(searchText)'")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadAttachments() {
        isLoading = true
        errorMessage = nil
        
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: folderBookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Failed to access storage folder. Please reselect it."
                isLoading = false
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            folderURL = url
            
            // Get the Attachments subfolder
            let attachmentsFolder = url.appendingPathComponent("Attachments", isDirectory: true)
            
            guard FileManager.default.fileExists(atPath: attachmentsFolder.path) else {
                errorMessage = "Attachments folder not found. Add attachments to create it."
                isLoading = false
                return
            }
            
            // List all files in the Attachments folder
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: attachmentsFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            // Parse filenames to extract member names
            // Format: MemberName-1.jpg, MemberName-2.pdf, etc.
            var parsedAttachments: [AttachmentFile] = []
            
            for fileURL in fileURLs {
                let fileName = fileURL.lastPathComponent
                
                // Extract member name from filename (everything before the last hyphen)
                if let lastHyphenRange = fileName.range(of: "-", options: .backwards) {
                    let memberName = String(fileName[..<lastHyphenRange.lowerBound])
                    let cleanedName = memberName.replacingOccurrences(of: "-", with: " ")
                    
                    parsedAttachments.append(
                        AttachmentFile(
                            fileName: fileName,
                            memberName: cleanedName,
                            fileURL: fileURL
                        )
                    )
                }
            }
            
            attachments = parsedAttachments.sorted { $0.memberName < $1.memberName }
            isLoading = false
            
        } catch {
            errorMessage = "Failed to load attachments: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

// MARK: - Supporting Types

struct AttachmentFile: Identifiable {
    let id = UUID()
    let fileName: String
    let memberName: String
    let fileURL: URL
    
    var fileExtension: String {
        fileURL.pathExtension.lowercased()
    }
    
    var isImage: Bool {
        ["jpg", "jpeg", "png", "heic", "gif", "tiff", "bmp", "webp"].contains(fileExtension)
    }
    
    var isPDF: Bool {
        fileExtension == "pdf"
    }
    
    var iconName: String {
        if isImage {
            return "photo"
        } else if isPDF {
            return "doc.richtext"
        } else {
            return "doc"
        }
    }
}

struct AttachmentPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let memberName: String
}

// MARK: - Attachment Thumbnail Card

struct AttachmentThumbnailCard: View {
    let file: AttachmentFile
    let folderURL: URL?
    
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if file.isImage {
                    if isLoading {
                        ProgressView()
                            .frame(width: 100, height: 100)
                    } else if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipped()
                            .cornerRadius(8)
                    } else {
                        placeholderView
                    }
                } else {
                    // PDF or other file type
                    VStack(spacing: 8) {
                        Image(systemName: file.iconName)
                            .font(.system(size: 40))
                            .foregroundColor(.accentColor)
                        Text(file.fileExtension.uppercased())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 100, height: 100)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            Text(file.memberName)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: 100)
            
            Text(file.fileName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 100)
        }
        .onAppear {
            if file.isImage {
                loadThumbnail()
            }
        }
    }
    
    private var placeholderView: some View {
        Image(systemName: "photo")
            .font(.system(size: 40))
            .foregroundColor(.secondary)
            .frame(width: 100, height: 100)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
    }
    
    private func loadThumbnail() {
        guard FileManager.default.fileExists(atPath: file.fileURL.path) else {
            isLoading = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = UIImage(contentsOfFile: file.fileURL.path) {
                let size = CGSize(width: 200, height: 200)
                UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
                image.draw(in: CGRect(origin: .zero, size: size))
                let thumbnailImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                DispatchQueue.main.async {
                    self.thumbnail = thumbnailImage
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Full Preview

struct AttachmentFullPreview: View {
    let url: URL
    let memberName: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    
    var body: some View {
        NavigationView {
            Group {
                if url.pathExtension.lowercased() == "pdf" {
                    // Use QuickLook for PDFs
                    PDFPreviewController(url: url)
                } else if let image = image {
                    // Show image with zoom
                    ZoomableImagePreview(image: image)
                } else {
                    ProgressView("Loading...")
                        .onAppear {
                            loadImage()
                        }
                }
            }
            .navigationTitle(memberName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let loadedImage = UIImage(contentsOfFile: url.path) {
                DispatchQueue.main.async {
                    self.image = loadedImage
                }
            }
        }
    }
}

struct ZoomableImagePreview: View {
    let image: UIImage
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * scale)
                    .offset(offset)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        scale *= delta
                        scale = min(max(scale, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
    }
}

struct PDFPreviewController: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        uiViewController.reloadData()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        
        init(url: URL) {
            self.url = url
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
