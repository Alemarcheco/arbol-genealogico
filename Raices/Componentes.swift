import SwiftUI
import UIKit

enum Tema {
    static let verde = Color(red: 0.16, green: 0.47, blue: 0.36)
    static let verdeClaro = Color(red: 0.55, green: 0.76, blue: 0.55)
    static let tierra = Color(red: 0.55, green: 0.38, blue: 0.24)
    static let hombre = Color(red: 0.30, green: 0.52, blue: 0.80)
    static let mujer = Color(red: 0.86, green: 0.42, blue: 0.56)
    static let neutro = Color.gray

    static func color(_ s: Sexo) -> Color {
        switch s {
        case .hombre: return hombre
        case .mujer: return mujer
        case .desconocido: return neutro
        }
    }
}

/// Muestra la foto de un medio (local o remota).
struct ImagenMedio: View {
    @Environment(ArbolStore.self) private var arbol
    let medio: Medio
    var ajuste: ContentMode = .fill

    var body: some View {
        if let img = arbol.imagen(medio) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: ajuste)
        } else if let url = medio.urlRemota {
            AsyncImage(url: url) { fase in
                switch fase {
                case .success(let i): i.resizable().aspectRatio(contentMode: ajuste)
                case .failure: Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
                default: ProgressView()
                }
            }
        } else {
            Image(systemName: "photo").font(.title).foregroundStyle(.secondary)
        }
    }
}

struct Avatar: View {
    let persona: Persona
    var tam: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Tema.color(persona.sexo).opacity(0.18))
            if let f = persona.fotoPrincipal {
                ImagenMedio(medio: f).frame(width: tam, height: tam).clipShape(Circle())
            } else {
                Image(systemName: persona.sexo == .mujer ? "person.crop.circle.fill" : "person.crop.circle.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(Tema.color(persona.sexo).opacity(0.75))
                    .padding(tam * 0.06)
            }
        }
        .frame(width: tam, height: tam)
        .overlay(Circle().stroke(Tema.color(persona.sexo), lineWidth: max(1.5, tam / 30)))
    }
}

struct FilaPersona: View {
    let persona: Persona
    var detalle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Avatar(persona: persona, tam: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(persona.nombreCompleto).font(.body.weight(.medium)).lineLimit(1)
                let sub = [detalle, persona.rangoVida.isEmpty ? nil : persona.rangoVida,
                           persona.nacimiento?.lugar.isEmpty == false ? persona.nacimiento?.lugar : nil]
                    .compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
        }
    }
}

/// Hoja para compartir archivos (Guardar en Archivos, AirDrop, WhatsApp, correo...).
struct HojaCompartir: UIViewControllerRepresentable {
    let elementos: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: elementos, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct ArchivoCompartible: Identifiable {
    let id = UUID()
    let url: URL
}

/// Selector de persona con búsqueda.
struct SelectorPersona: View {
    @Environment(ArbolStore.self) private var arbol
    @Environment(\.dismiss) private var cerrar
    var titulo = "Elegir persona"
    var excluir: Set<String> = []
    let elegir: (String) -> Void
    @State private var texto = ""

    var body: some View {
        NavigationStack {
            List(filtradas) { p in
                Button {
                    elegir(p.id)
                    cerrar()
                } label: { FilaPersona(persona: p) }
                .buttonStyle(.plain)
            }
            .searchable(text: $texto, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar por nombre o lugar")
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
        }
    }

    var filtradas: [Persona] {
        let l = arbol.personasOrdenadas.filter { !excluir.contains($0.id) }
        let t = texto.sinAcentos.recortado
        if t.isEmpty { return l }
        let partes = t.split(separator: " ").map(String.init)
        return l.filter { p in let s = p.textoBusqueda; return partes.allSatisfy { s.contains($0) } }
    }
}
