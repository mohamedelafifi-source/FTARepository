import SwiftUI

struct LocationMenu: View {
    @Binding var showFolderPicker: Bool
    let folderPathDisplay: String
    let isFolderSelected: Bool

    var body: some View {
        Menu {
            Button("Select Storage Folder…") {
                showFolderPicker = true
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
