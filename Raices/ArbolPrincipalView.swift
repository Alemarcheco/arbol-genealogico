import SwiftUI

struct ArbolPrincipalView: View {
    @Environment(ArbolStore.self) private var arbol
    @State private var rutaArbol = NavigationPath()
    @State private var rutaPersonas = NavigationPath()
    @State private var rutaParentesco = NavigationPath()
    @State private var rutaMas = NavigationPath()
    @State private var pestana = 0

    var body: some View {
        TabView(selection: $pestana) {
            NavigationStack(path: $rutaArbol) {
                DiagramaView(ruta: $rutaArbol)
                    .navigationDestination(for: String.self) { PerfilView(id: $0, ruta: $rutaArbol, irAlArbol: irAlArbol) }
            }
            .tabItem { Label("Árbol", systemImage: "tree") }
            .tag(0)

            NavigationStack(path: $rutaPersonas) {
                ListaPersonasView()
                    .navigationDestination(for: String.self) { PerfilView(id: $0, ruta: $rutaPersonas, irAlArbol: irAlArbol) }
            }
            .tabItem { Label("Personas", systemImage: "person.3") }
            .tag(1)

            NavigationStack(path: $rutaParentesco) {
                ParentescoView()
                    .navigationDestination(for: String.self) { PerfilView(id: $0, ruta: $rutaParentesco, irAlArbol: irAlArbol) }
            }
            .tabItem { Label("Parentesco", systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(2)

            NavigationStack(path: $rutaMas) {
                MasView()
                    .navigationDestination(for: String.self) { PerfilView(id: $0, ruta: $rutaMas, irAlArbol: irAlArbol) }
            }
            .tabItem { Label("Más", systemImage: "ellipsis.circle") }
            .tag(3)
        }
    }

    func irAlArbol(_ id: String) {
        arbol.foco = id
        rutaArbol = NavigationPath()
        pestana = 0
    }
}
