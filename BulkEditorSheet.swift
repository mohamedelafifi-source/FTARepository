import SwiftUI

struct BulkEditorSheet: View {
    @Binding var isPresented: Bool
    @Binding var bulkText: String
    @Binding var showConfirmation: Bool
    @Binding var showSuccess: Bool
    @Binding var successMessage: String

    @FocusState private var bulkEditorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Paste Bulk Data")
                    .font(.headline)

                TextEditor(text: $bulkText)
                    .focused($bulkEditorFocused)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .frame(minHeight: 220)
            }
            .padding()
            .onAppear { bulkEditorFocused = false }
            .navigationTitle("Bulk Editor")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Parse") { showConfirmation = true }
                    Button("Done") {
                        bulkText = ""
                        isPresented = false
                    }
                }
            }
            .alert("Parse Bulk Data?", isPresented: $showConfirmation) {
                Button("Parse", role: .destructive) {
                    FamilyDataInputView.parseBulkInput(bulkText)
                    successMessage = "Bulk data parsed."
                    showSuccess = true
                    bulkText = ""
                }
            } message: {
                Text("This will process the pasted text.")
            }
        }
    }
}
