import SwiftUI

struct NamePromptSheet: View {
    @Binding var isPresented: Bool
    @Binding var tempNameInput: String
    let onConfirm: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select the photo owner")
                    .font(.headline)
                TextField("Person's name", text: $tempNameInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                HStack {
                    Button("Cancel", role: .cancel) { isPresented = false }
                    Spacer()
                    Button("Import") {
                        let trimmed = tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        onConfirm(trimmed)
                        isPresented = false
                    }
                    .disabled(tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Name for Photo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        let trimmed = tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        onConfirm(trimmed)
                        isPresented = false
                    }
                    .disabled(tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
