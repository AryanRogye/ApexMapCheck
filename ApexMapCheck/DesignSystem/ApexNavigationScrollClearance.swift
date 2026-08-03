import SwiftUI

extension View {
    func apexNavigationScrollClearance() -> some View {
        contentMargins(.bottom, 96, for: .scrollContent)
    }
}
