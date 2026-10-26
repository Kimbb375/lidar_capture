import SwiftUI
import ARKit

struct PreviewView: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView()
        v.session = session
        v.automaticallyUpdatesLighting = false
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var rec = Recorder()

    var body: some View {
        ZStack(alignment: .bottom) {
            PreviewView(session: rec.session).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(rec.status)
                    .font(.footnote.monospaced())
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                Button(action: { rec.toggle() }) {
                    Text(rec.recording ? "Stop" : "Record")
                        .font(.title2.bold())
                        .frame(width: 160, height: 56)
                        .background(rec.recording ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(28)
                }
            }
            .padding(.bottom, 30)
        }
    }
}
