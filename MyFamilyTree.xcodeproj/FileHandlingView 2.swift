import SwiftUI

struct FileHandlingView: View {
    let command: FileHandlingCommand?

    var body: some View {
        VStack(spacing: 16) {
            Text("File Handling")
                .font(.title3)
            if let command = command {
                switch command {
                case .importAppend:
                    Text("Command: Append from a Tree File")
                        .foregroundStyle(.secondary)
                case .importLoad:
                    Text("Command: Load from a Tree File")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No command specified")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}

#Preview {
    FileHandlingView(command: .importAppend)
}
