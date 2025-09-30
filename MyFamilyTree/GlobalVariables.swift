//
//  GlobalVariables.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import Combine

// MARK: - Global state for exporting
@MainActor
final class GlobalVariables: ObservableObject {
    static let shared = GlobalVariables()
    @Published var showExporter: Bool = false
    // Back-compat fields (still used by some callers)
    @Published var exportText: String = "Hello World!"
    @Published var exportName: String = "HelloFile"
    
    // New: payload-driven export
    @Published var exportPayload: ExportPayload = .none

    // Picked locations/files (ephemeral; not persisted as bookmarks)
    @Published var selectedFolderURL: URL?
    @Published var selectedJSONURL: URL?
    @Published var openedJSONPreview: String = ""
    
    private init() {}
}

// MARK: - Export payloads
enum ExportPayload: Equatable {
    case none
    case text(String, name: String)                 // .txt (or any name you pass)
    case json(String, name: String)                 // JSON as a String
    case image(Data, name: String, type: UTType)    // PNG/JPEG raw data with UTType
}

//Mark : my own button style
struct GrayWhiteButtonStyle : ButtonStyle {
    func makeBody (configuration: Configuration) -> some View {
        configuration.label
            .background(Color.gray)
            .foregroundColor(.white)
            .cornerRadius(8)
            
    }
}

