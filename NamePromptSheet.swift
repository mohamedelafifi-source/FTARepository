import SwiftUI

struct NamePromptSheet: View {
    @Binding var isPresented: Bool
    @Binding var tempNameInput: String
    let onConfirm: (String) -> Void

    let existingNames: Set<String>

    private var trimmedInput: String {
        tempNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        let lowercasedSet = Set(existingNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        return lowercasedSet.contains(trimmedInput.lowercased())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select the photo owner")
                    .font(.headline)
                TextField("Person's name", text: $tempNameInput)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                if !trimmedInput.isEmpty && isDuplicate {
                    Text("That name already exists.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Cancel", role: .cancel) { isPresented = false }
                    Spacer()
                    Button("Import") {
                        let trimmed = trimmedInput
                        guard !trimmed.isEmpty, !isDuplicate else { return }
                        onConfirm(trimmed)
                        isPresented = false
                    }
                    .disabled(trimmedInput.isEmpty || isDuplicate)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Name for Photo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        let trimmed = trimmedInput
                        guard !trimmed.isEmpty, !isDuplicate else { return }
                        onConfirm(trimmed)
                        isPresented = false
                    }
                    .disabled(trimmedInput.isEmpty || isDuplicate)
                }
            }
        }
    }
}
