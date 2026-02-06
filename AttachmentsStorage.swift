import Foundation
import UniformTypeIdentifiers

/// Helper struct to manage Attachments folder and files.
public struct AttachmentsStorage {
    
    /// Creates (if needed) and returns the Attachments subfolder URL inside the given folder.
    /// - Parameter folder: The base folder URL.
    /// - Throws: FileManager errors if folder creation fails.
    /// - Returns: URL of the Attachments subfolder.
    public static func ensureAttachmentsFolder(in folder: URL) throws -> URL {
        let attachmentsFolder = folder.appendingPathComponent("Attachments", isDirectory: true)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: attachmentsFolder.path, isDirectory: &isDir) || !isDir.boolValue {
            try fm.createDirectory(at: attachmentsFolder, withIntermediateDirectories: true, attributes: nil)
        }
        return attachmentsFolder
    }
    
    /// Returns a sanitized prefix by replacing "/" and ":" with "-" and trimming whitespace.
    /// It also collapses multiple hyphens into one, trims hyphens from ends,
    /// and returns an empty string if nothing remains after sanitization.
    /// - Parameter name: The original name.
    /// - Returns: Sanitized string.
    public static func sanitizedPrefix(for name: String) -> String {
        var sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "/", with: "-")
        sanitized = sanitized.replacingOccurrences(of: ":", with: "-")
        
        // Collapse multiple hyphens to one
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }
        
        // Trim hyphens from start and end
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        
        if sanitized.isEmpty {
            return ""
        }
        return sanitized
    }
    
    /// Lists attachment files for a memberName in the attachments folder inside folder.
    /// Only files whose lastPathComponent starts with "<sanitizedPrefix>-".
    /// - Parameters:
    ///   - memberName: The member name.
    ///   - folder: The base folder URL.
    /// - Returns: Array of file URLs matching the prefix.
    public static func listAttachments(for memberName: String, in folder: URL) -> [URL] {
        let prefix = sanitizedPrefix(for: memberName)
        if prefix.isEmpty {
            return []
        }
        do {
            let attachmentsFolder = try ensureAttachmentsFolder(in: folder)
            let searchPrefix = prefix + "-"
            let contents = try FileManager.default.contentsOfDirectory(at: attachmentsFolder, includingPropertiesForKeys: nil, options: [])
            return contents.filter { $0.lastPathComponent.hasPrefix(searchPrefix) }
        } catch {
            return []
        }
    }
    
    /// Returns the next available attachment URL for a memberName with the given original extension.
    /// It scans existing files with prefix and picks max numeric suffix + 1.
    /// - Parameters:
    ///   - memberName: The member name.
    ///   - originalExtension: The original extension (with or without dot).
    ///   - folder: The base folder URL.
    /// - Returns: URL for the next attachment file.
    public static func nextAttachmentURL(for memberName: String, originalExtension: String, in folder: URL) -> URL {
        let prefix = sanitizedPrefix(for: memberName)
        let safePrefix = prefix.isEmpty ? "untitled" : prefix
        
        let attachmentsFolder: URL
        do {
            attachmentsFolder = try ensureAttachmentsFolder(in: folder)
        } catch {
            // If folder creation fails, fallback to base folder
            let ext = originalExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            return folder.appendingPathComponent("\(safePrefix)-1.\(ext)")
        }
        
        let prefixWithHyphen = safePrefix + "-"
        let ext = originalExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        
        let fm = FileManager.default
        var maxIndex = 0
        
        if let files = try? fm.contentsOfDirectory(at: attachmentsFolder, includingPropertiesForKeys: nil, options: []) {
            for file in files where file.lastPathComponent.hasPrefix(prefixWithHyphen) {
                let filename = file.deletingPathExtension().lastPathComponent
                // filename is expected to be "<prefix>-<index>"
                guard let lastHyphenRange = filename.range(of: "-", options: .backwards) else {
                    continue
                }
                let indexString = filename.suffix(from: lastHyphenRange.upperBound)
                if let index = Int(indexString), index > maxIndex {
                    maxIndex = index
                }
            }
        }
        
        let nextIndex = maxIndex + 1
        let newFilename = "\(safePrefix)-\(nextIndex).\(ext)"
        return attachmentsFolder.appendingPathComponent(newFilename)
    }
    
    /// Copies the file from sourceURL to destinationURL, overwriting if exists.
    /// - Parameters:
    ///   - sourceURL: Source file URL.
    ///   - destinationURL: Destination file URL.
    /// - Throws: FileManager errors if copy fails.
    public static func savePickedFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.copyItem(at: sourceURL, to: destinationURL)
    }
    
    /// Deletes the attachment file at the given URL.
    /// - Parameter url: File URL to delete.
    /// - Throws: FileManager errors if deletion fails.
    public static func deleteAttachment(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
