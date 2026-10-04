import SwiftUI
import ChatGPTAuth

struct ChatGPTManagementPage: View {
    @Bindable var connection: ChatGPTConnection
    var body: some View {
        List { ChatGPTConnectionView(connection: connection) }
            .modifier(UtilityListStyle()).navigationTitle("Manage ChatGPT")
    }
}
