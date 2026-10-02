import SwiftUI

struct ReviewCompletionView: View {
    let count: Int
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark").font(.title).foregroundStyle(Theme.accent)
                .frame(width: 72, height: 72).background(Theme.accent.opacity(0.1), in: Circle())
            Text("A little more\npart of you.").font(Theme.title).multilineTextAlignment(.center)
            Text("\(count) words practiced.\nCome back when you’re ready.")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(5)
        }.frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

#Preview { ReviewCompletionView(count: 8).background(Theme.paper) }
