import SwiftUI

struct LocationMenu: View {
    @Binding var showFolderPicker: Bool
    let folderPathDisplay: String
    let isFolderSelected: Bool
    @ObservedObject var globals = GlobalVariables.shared
    var onSelectFolderTapped: (() -> Void)? = nil
    
    var body: some View {
        Menu {
            Button("Select Storage Folder…") {
                showFolderPicker = true
                onSelectFolderTapped?()
            }
            LocationPathLine(text: folderPathDisplay)
            
            Button("Copy Path") {
                UIPasteboard.general.string = folderPathDisplay
            }
            .disabled(!isFolderSelected)
        } label: {
            Text("Location")
        }
        .font(.footnote)
    }
}
