import SwiftUI

struct ProviderPopoverView: View {
    let providers: ProviderStore
    let openProviders: () -> Void

    var body: some View {
        PopoverView(providers: providers, openProviders: openProviders)
    }
}
