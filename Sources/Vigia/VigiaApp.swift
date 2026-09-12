import SwiftUI

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Um app de vigilância se vê no escuro: a imagem da câmera é o
        // conteúdo, e moldura clara em volta de vídeo cansa e falseia o brilho
        // da cena. Fixo em vez de seguir o sistema, por isso.
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct VigiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Vigia", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 620)
        }
    }
}
