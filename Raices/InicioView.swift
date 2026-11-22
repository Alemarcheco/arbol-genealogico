import SwiftUI
import UniformTypeIdentifiers

struct InicioView: View {
    @Environment(Biblioteca.self) private var biblioteca
    @State private var importar = false
    @State private var nuevo = false
    @State private var ayuda = false
    @State private var renombrando: ResumenArbol? = nil
    @State private var nombreNuevo = ""
    @State private var borrando: ResumenArbol? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "tree.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(LinearGradient(colors: [Tema.verdeClaro, Tema.verde], startPoint: .top, endPoint: .bottom))
                        Text("Raíces").font(.largeTitle.bold())
                        Text("Tu historia familiar, en tu iPhone").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button { nuevo = true } label: {
                        Label("Crear un árbol nuevo", systemImage: "plus.circle.fill")
                    }
                    Button { importar = true } label: {
                        Label("Importar GEDCOM (.ged o .zip)", systemImage: "square.and.arrow.down.fill")
                    }
                    Button { ayuda = true } label: {
                        Label("Cómo traer mi árbol de MyHeritage", systemImage: "questionmark.circle")
                    }
                }

                if !biblioteca.arboles.isEmpty {
                    Section("Mis árboles") {
                        ForEach(biblioteca.arboles) { a in
                            Button { biblioteca.abrir(a.id) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "tree")
                                        .font(.title2).foregroundStyle(Tema.verde)
                                        .frame(width: 44, height: 44)
                                        .background(Tema.verde.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.nombre).font(.headline).foregroundStyle(.primary)
                                        Text("\(a.personas) personas · \(a.modificado.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { borrando = a } label: { Label("Borrar", systemImage: "trash") }
                                Button { nombreNuevo = a.nombre; renombrando = a } label: { Label("Renombrar", systemImage: "pencil") }
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importar, allowedContentTypes: tiposImportables) { r in
                if case .success(let url) = r { biblioteca.importar(url: url) }
            }
            .sheet(isPresented: $nuevo) { NuevoArbolView() }
            .sheet(isPresented: $ayuda) { AyudaMyHeritageView() }
            .alert("Renombrar árbol", isPresented: Binding(get: { renombrando != nil }, set: { if !$0 { renombrando = nil } })) {
                TextField("Nombre", text: $nombreNuevo)
                Button("Guardar") { if let a = renombrando { biblioteca.renombrar(a.id, a: nombreNuevo) } }
                Button("Cancelar", role: .cancel) {}
            }
            .confirmationDialog("¿Borrar el árbol \"\(borrando?.nombre ?? "")\"? Esta acción no se puede deshacer.",
                                isPresented: Binding(get: { borrando != nil }, set: { if !$0 { borrando = nil } }),
                                titleVisibility: .visible) {
                Button("Borrar árbol", role: .destructive) { if let a = borrando { biblioteca.eliminar(a.id) } }
            }
        }
    }

    var tiposImportables: [UTType] {
        var t: [UTType] = [.gedcom, .zip]
        if let g = UTType(filenameExtension: "ged") { t.append(g) }
        t.append(.data)
        return t
    }
}

struct NuevoArbolView: View {
    @Environment(Biblioteca.self) private var biblioteca
    @Environment(\.dismiss) private var cerrar
    @State private var nombreArbol = ""
    @State private var nombre = ""
    @State private var apellido = ""
    @State private var sexo: Sexo = .hombre
    @State private var nacimiento = ""
    @State private var lugar = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Árbol") {
                    TextField("Nombre del árbol (p. ej. Familia Feitó)", text: $nombreArbol)
                }
                Section {
                    TextField("Nombre(s)", text: $nombre)
                    TextField("Apellidos", text: $apellido)
                    Picker("Sexo", selection: $sexo) {
                        ForEach(Sexo.allCases) { Text($0.nombre).tag($0) }
                    }
                    CampoFecha(titulo: "Nacimiento", fecha: $nacimiento)
                    TextField("Lugar de nacimiento", text: $lugar)
                } header: {
                    Text("Empieza contigo")
                } footer: {
                    Text("Después podrás añadir a tus padres, pareja, hijos y hermanos desde el árbol.")
                }
            }
            .navigationTitle("Nuevo árbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        var p = Persona(id: "I1", nombre: nombre.recortado, apellido: apellido.recortado, sexo: sexo)
                        if !nacimiento.isEmpty || !lugar.isEmpty {
                            p.eventos.append(Evento(tipo: "BIRT", fecha: nacimiento, lugar: lugar.recortado))
                        }
                        let tienePersona = !(nombre.recortado.isEmpty && apellido.recortado.isEmpty)
                        let titulo = nombreArbol.recortado.isEmpty
                            ? (apellido.recortado.isEmpty ? "Mi árbol" : "Familia \(apellido.recortado)")
                            : nombreArbol.recortado
                        _ = biblioteca.crear(nombre: titulo, primera: tienePersona ? p : nil)
                        cerrar()
                    }
                }
            }
        }
    }
}

struct AyudaMyHeritageView: View {
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            List {
                Section("1. Exportar desde MyHeritage") {
                    Label("Entra en myheritage.es desde el navegador (Safari o el ordenador).", systemImage: "globe")
                    Label("Menú Árbol genealógico → Administrar árboles.", systemImage: "list.bullet")
                    Label("En tu árbol, pulsa Exportar a GEDCOM. Puedes incluir las fotos.", systemImage: "square.and.arrow.up")
                    Label("MyHeritage te envía un correo con el enlace para descargar el archivo .ged (a veces dentro de un .zip).", systemImage: "envelope")
                }
                Section("2. Abrirlo en Raíces") {
                    Label("Descarga el archivo en el iPhone (se guarda en Archivos → Descargas).", systemImage: "arrow.down.circle")
                    Label("En Raíces pulsa Importar GEDCOM y elige el archivo, o tócalo en Archivos y elige Compartir → Raíces.", systemImage: "square.and.arrow.down")
                    Label("Las fotos de MyHeritage se ven con internet. En Más → Descargar fotos las guardas en el teléfono.", systemImage: "photo.on.rectangle")
                }
                Section("3. Devolverlo a MyHeritage u otra app") {
                    Label("En Más → Exportar GEDCOM obtienes un .ged estándar (5.5.1, UTF-8) que MyHeritage, FamilySearch, Ancestry y Gramps pueden importar.", systemImage: "arrow.triangle.2.circlepath")
                    Label("Los datos propios de MyHeritage (identificadores, fechas de actualización, datos de las fotos…) se conservan al exportar.", systemImage: "checkmark.seal")
                }
            }
            .navigationTitle("MyHeritage y GEDCOM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
    }
}
