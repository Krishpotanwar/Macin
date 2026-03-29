// AddURLSheet.swift — URL paste sheet with basic validation feedback
import SwiftUI

struct AddURLSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (String) -> Void

    @State private var urlText = ""
    @State private var showValidationError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Download")
                .font(.title2.weight(.semibold))
                .foregroundColor(.white)

            TextField("https://", text: $urlText)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.2))
                )
                .onChange(of: urlText) { showValidationError = false }

            if showValidationError {
                Text("Enter a valid http(s) URL")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Button("Add") {
                    let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let parsed = URL(string: trimmed),
                          let scheme = parsed.scheme?.lowercased(),
                          scheme == "http" || scheme == "https",
                          parsed.host != nil else {
                        showValidationError = true
                        return
                    }
                    onAdd(parsed.absoluteString)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlText.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(VisualEffectBlur(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
    }
}
