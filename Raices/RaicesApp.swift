import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let gedcom = UTType(importedAs: "com.alemarcheco.raices.gedcom")
}

@main
struct RaicesApp: App {
    @State private var biblioteca = Biblioteca()

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(biblioteca)
                .tint(Tema.verde)
                .onOpenURL { url in
                    // "Abrir con Raíces" desde Archivos, Mail, WhatsApp...
                    biblioteca.importar(url: url)
                }
        }
    }
}

struct RaizView: View {
    @Environment(Biblioteca.self) private var biblioteca

    var body: some View {
        @Bindable var b = biblioteca
        Group {
            if let store = biblioteca.abierto {
                ArbolPrincipalView()
                    .environment(store)
                    .id(store.datos.id)
            } else {
                InicioView()
            }
        }
        .overlay {
            if biblioteca.importando {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Importando árbol…").font(.headline)
                    }
                    .padding(28)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }
            }
        }
        .alert("Raíces", isPresented: Binding(get: { b.mensaje != nil }, set: { if !$0 { b.mensaje = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(biblioteca.mensaje ?? "")
        }
    }
}
