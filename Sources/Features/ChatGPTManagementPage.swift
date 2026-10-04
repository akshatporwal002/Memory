import SwiftUI
import ChatGPTAuth

struct ChatGPTManagementPage: View {
    let model: EngramModel
    var body: some View {
        List { ChatGPTConnectionView(connection: model.chatGPT, signOutAction: {
            if model.cloud.localProfileID != nil { await model.cloud.signOut(model: model) }
            else { await model.assistant.stopAndWait(); model.voice.stop(); model.pdfLearning.cancel(); await model.chatGPT.signOut() }
        }) }
            .modifier(UtilityListStyle()).navigationTitle("Manage ChatGPT")
    }
}
