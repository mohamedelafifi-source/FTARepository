import SwiftUI

struct LocationPathLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(minWidth: 320, alignment: .leading)
    }
}
