import SwiftUI
import UIKit

struct SystemDictionarySheet: UIViewControllerRepresentable {
    let term: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }
    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}

#Preview { SystemDictionarySheet(term: "serendipity") }
