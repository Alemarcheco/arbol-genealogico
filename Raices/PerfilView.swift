import SwiftUI
import PhotosUI

struct PerfilView: View {
    @Environment(ArbolStore.self) private var arbol
    let id: String
    @Binding var ruta: NavigationPath
    let irAlArbol: (String) -> Void

    @State private var editar = false
    @State private var anadir: AnadirFamiliar? = nil
    @State private var eventoEditado: EventoEditable? = nil
    @State private var familiaEditada: String? = nil
    @State private var fotosElegidas: [PhotosPickerItem] = []
    @State private var visor: Int? = nil
    @State private var confirmarBorrado = false
    @State private var cargandoFotos = false

    var body: some View {
        if let p = arbol.persona(id) {
            contenido(p)
        } else {
            ContentUnavailableView("Persona no encontrada", systemImage: "person.slash")
        }
    }

    func contenido(_ p: Persona) -> some View {
        List {
            cabecera(p)
            eventos(p)
            familia(p)
            fotos(p)
            if !p.notas.isEmpty || !arbol.notasVinculadas(p).isEmpty {
                Section("Notas") {
                    if !p.notas.isEmpty { Text(p.notas).textSelection(.enabled) }
                    ForEach(Array(arbol.notasVinculadas(p).enumerated()), id: \.offset) { Text($0.element).textSelection(.enabled) }
                }
            }
            if !p.correo.isEmpty {
                Section("Contacto") {
                    Link(destination: URL(string: "mailto:\(p.correo)") ?? URL(string: "mailto:")!) {
                        Label(p.correo, systemImage: "envelope")
                    }
                }
            }
            if !p.extra.isEmpty || !p.otrosNombres.isEmpty {
                Section {
                    DisclosureGroup("Datos adicionales del archivo (\(p.extra.count + p.otrosNombres.count))") {
                        ForEach(Array((p.otrosNombres + p.extra).enumerated()), id: \.offset) { _, n in
                            NodoCrudoView(nodo: n)
                        }
                    }
                } footer: {
                    Text("Información del GEDCOM original (p. ej. etiquetas de MyHeritage). Se conserva al exportar.")
                }
            }
            Section {
                if arbol.datos.raiz != p.id {
                    Button { arbol.datos.raiz = p.id; arbol.cambiado() } label: {
                        Label("Usar como persona de inicio del árbol", systemImage: "house")
                    }
                } else {
                    Label("Persona de inicio del árbol", systemImage: "house.fill").foregroundStyle(.secondary)
                }
                Button(role: .destructive) { confirmarBorrado = true } label: {
                    Label("Eliminar persona", systemImage: "trash")
                }
            }
        }
        .navigationTitle(p.nombreCorto)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Editar") { editar = true } }
        }
        .sheet(isPresented: $editar) { EditarPersonaView(original: p) }
        .sheet(item: $anadir) { a in NuevoFamiliarView(relacion: a.relacion, de: a.de) }
        .sheet(item: $eventoEditado) { ev in
            EditarEventoView(evento: ev.evento, deFamilia: ev.familia != nil, nuevo: ev.nuevo) { nuevo in
                guardarEvento(nuevo, en: ev)
            } borrar: {
                borrarEvento(ev)
            }
        }
        .sheet(item: Binding(get: { familiaEditada.map { IDTexto(id: $0) } }, set: { familiaEditada = $0?.id })) { f in
            EditarFamiliaView(familiaID: f.id, desde: p.id)
        }
        .fullScreenCover(item: Binding(get: { visor.map { IDTexto(id: String($0)) } }, set: { visor = $0.flatMap { Int($0.id) } })) { v in
            VisorFotos(personaID: p.id, inicio: Int(v.id) ?? 0)
        }
        .confirmationDialog("¿Eliminar a \(p.nombreCompleto) del árbol?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if !ruta.isEmpty { ruta.removeLast() }
                arbol.eliminar(p.id)
            }
        }
        .onChange(of: fotosElegidas) { _, items in
            guard !items.isEmpty else { return }
            cargandoFotos = true
            Task {
                for item in items {
                    if let d = try? await item.loadTransferable(type: Data.self) { arbol.agregarFoto(d, a: p.id) }
                }
                fotosElegidas = []
                cargandoFotos = false
            }
        }
    }

    // MARK: secciones

    func cabecera(_ p: Persona) -> some View {
        Section {
            VStack(spacing: 10) {
                Button { if !p.fotos.isEmpty { visor = p.fotos.firstIndex(where: { $0.id == p.fotoPrincipal?.id }) ?? 0 } } label: {
                    Avatar(persona: p, tam: 116)
                }
                .buttonStyle(.plain)
                Text(p.nombreCompleto).font(.title2.bold()).multilineTextAlignment(.center)
                if !p.apodo.isEmpty { Text("“\(p.apodo)”").font(.subheadline).foregroundStyle(.secondary) }
                if !p.apellidoCasada.isEmpty { Text("Apellido de casada: \(p.apellidoCasada)").font(.caption).foregroundStyle(.secondary) }
                let edad = textoEdad(p)
                if !p.rangoVida.isEmpty || !edad.isEmpty {
                    Text([p.rangoVida, edad].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    BotonAccion(titulo: "Ver en árbol", icono: "tree") { irAlArbol(p.id) }
                    Menu {
                        ForEach(Relacion.allCases) { r in
                            if arbol.puede(r, a: p.id) {
                                Button { anadir = AnadirFamiliar(relacion: r, de: p.id) } label: { Label(r.titulo, systemImage: r.icono) }
                            }
                        }
                    } label: { EtiquetaAccion(titulo: "Añadir familiar", icono: "person.badge.plus") }
                    BotonAccion(titulo: "Editar", icono: "pencil") { editar = true }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    func textoEdad(_ p: Persona) -> String {
        guard let n = p.nacimiento?.fecha, !n.isEmpty else { return "" }
        if p.fallecido {
            guard let f = p.defuncion?.fecha, !f.isEmpty, let e = FechaGedcom.edad(desde: n, hasta: f) else { return "" }
            return "falleció a los \(e) años"
        }
        guard let e = FechaGedcom.edad(desde: n, hasta: nil), e < 115 else { return "" }
        return "\(e) años"
    }

    struct LineaVida: Identifiable {
        let id = UUID()
        let evento: Evento
        let titulo: String
        let editable: EventoEditable?
        let anio: Int?
    }

    func lineaDeVida(_ p: Persona) -> [LineaVida] {
        var l: [LineaVida] = p.eventos.map {
            LineaVida(evento: $0, titulo: $0.titulo, editable: EventoEditable(evento: $0, familia: nil, nuevo: false), anio: FechaGedcom.anio($0.fecha))
        }
        for (pareja, f) in arbol.parejas(de: p.id) {
            for e in f.eventos {
                let con = pareja.map { " con \($0.nombreCorto)" } ?? ""
                l.append(LineaVida(evento: e, titulo: e.titulo + con, editable: EventoEditable(evento: e, familia: f.id, nuevo: false), anio: FechaGedcom.anio(e.fecha)))
            }
        }
        for h in arbol.hijos(de: p.id) {
            if let n = h.nacimiento, !n.fecha.isEmpty {
                let t = "Nacimiento de \(h.sexo == .mujer ? "su hija" : h.sexo == .hombre ? "su hijo" : "") \(h.nombreCorto)"
                l.append(LineaVida(evento: n, titulo: t, editable: nil, anio: FechaGedcom.anio(n.fecha)))
            }
        }
        return l.sorted { a, b in
            let oa = TipoEvento.orden(a.evento.tipo), ob = TipoEvento.orden(b.evento.tipo)
            if oa == 0 || ob == 0 || oa >= 90 || ob >= 90, oa != ob, a.editable != nil, b.editable != nil, a.editable?.familia == nil, b.editable?.familia == nil {
                return oa < ob
            }
            switch (a.anio, b.anio) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return oa < ob
            }
        }
    }

    func eventos(_ p: Persona) -> some View {
        Section {
            ForEach(lineaDeVida(p)) { item in
                Button {
                    if let e = item.editable { eventoEditado = e }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.evento.info.icono)
                            .foregroundStyle(item.editable == nil ? Color.secondary : Tema.verde)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.titulo).font(.body.weight(.medium)).foregroundStyle(.primary)
                            if !item.evento.valor.isEmpty && item.editable != nil {
                                Text(item.evento.valor).font(.subheadline).foregroundStyle(.primary)
                            }
                            let fl = [FechaGedcom.legible(item.evento.fecha), item.evento.lugar].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !fl.isEmpty { Text(fl).font(.caption).foregroundStyle(.secondary) }
                            if !item.evento.notas.isEmpty && item.editable != nil {
                                Text(item.evento.notas).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Button {
                eventoEditado = EventoEditable(evento: Evento(tipo: "RESI"), familia: nil, nuevo: true)
            } label: { Label("Añadir hecho o evento", systemImage: "plus") }
        } header: { Text("Línea de vida") }
    }

    func familia(_ p: Persona) -> some View {
        let todosPadres = arbol.todosLosPadres(de: p.id)
        let hermanos = arbol.hermanos(de: p.id)
        let parejas = arbol.parejas(de: p.id)
        return Group {
            Section("Padres") {
                ForEach(todosPadres) { pa in
                    NavigationLink(value: pa.id) { FilaPersona(persona: pa, detalle: pa.sexo == .mujer ? "Madre" : pa.sexo == .hombre ? "Padre" : "Progenitor") }
                }
                if arbol.puede(.padre, a: p.id) || arbol.puede(.madre, a: p.id) {
                    Menu {
                        if arbol.puede(.padre, a: p.id) { Button("Añadir padre") { anadir = AnadirFamiliar(relacion: .padre, de: p.id) } }
                        if arbol.puede(.madre, a: p.id) { Button("Añadir madre") { anadir = AnadirFamiliar(relacion: .madre, de: p.id) } }
                    } label: { Label("Añadir padre o madre", systemImage: "plus") }
                }
            }
            if !hermanos.isEmpty {
                Section("Hermanos") {
                    ForEach(hermanos) { h in
                        NavigationLink(value: h.id) { FilaPersona(persona: h) }
                    }
                }
            }
            ForEach(parejas, id: \.familia.id) { item in
                Section {
                    if let pr = item.pareja {
                        NavigationLink(value: pr.id) {
                            FilaPersona(persona: pr, detalle: item.familia.divorciados ? "Expareja" : (pr.sexo == .mujer ? "Esposa" : pr.sexo == .hombre ? "Esposo" : "Pareja"))
                        }
                    }
                    ForEach(arbol.hijos(familia: item.familia)) { h in
                        NavigationLink(value: h.id) { FilaPersona(persona: h, detalle: h.sexo == .mujer ? "Hija" : h.sexo == .hombre ? "Hijo" : "Hijo/a") }
                    }
                    Button { familiaEditada = item.familia.id } label: {
                        Label("Editar esta relación", systemImage: "heart.text.square")
                    }
                } header: {
                    Text(item.pareja.map { "Con \($0.nombreCorto)" } ?? "Hijos")
                } footer: {
                    if let m = item.familia.eventos.first(where: { $0.tipo == "MARR" }) {
                        Text("Matrimonio: " + [FechaGedcom.legible(m.fecha), m.lugar].filter { !$0.isEmpty }.joined(separator: ", "))
                    }
                }
            }
            Section {
                Button { anadir = AnadirFamiliar(relacion: .pareja, de: p.id) } label: { Label("Añadir pareja", systemImage: "heart") }
                Button { anadir = AnadirFamiliar(relacion: .hijo, de: p.id) } label: { Label("Añadir hijo o hija", systemImage: "figure.and.child.holdinghands") }
                Button { anadir = AnadirFamiliar(relacion: .hermano, de: p.id) } label: { Label("Añadir hermano o hermana", systemImage: "person.2") }
            }
        }
    }

    func fotos(_ p: Persona) -> some View {
        Section {
            if !p.fotos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(p.fotos.enumerated()), id: \.element.id) { i, m in
                            Button { visor = i } label: {
                                ImagenMedio(medio: m)
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(alignment: .topTrailing) {
                                        if m.principal {
                                            Image(systemName: "star.circle.fill").foregroundStyle(.yellow, .black.opacity(0.4)).padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            PhotosPicker(selection: $fotosElegidas, maxSelectionCount: 20, matching: .images) {
                HStack {
                    Label("Añadir fotos", systemImage: "photo.badge.plus")
                    if cargandoFotos { Spacer(); ProgressView() }
                }
            }
        } header: { Text("Fotos (\(p.fotos.count))") }
    }

    // MARK: eventos

    func guardarEvento(_ e: Evento, en ev: EventoEditable) {
        if let fid = ev.familia {
            guard var f = arbol.familia(fid) else { return }
            if let i = f.eventos.firstIndex(where: { $0.id == e.id }) { f.eventos[i] = e } else { f.eventos.append(e) }
            arbol.guardar(f)
        } else {
            guard var p = arbol.persona(id) else { return }
            if let i = p.eventos.firstIndex(where: { $0.id == e.id }) { p.eventos[i] = e } else { p.eventos.append(e) }
            arbol.guardar(p)
        }
    }

    func borrarEvento(_ ev: EventoEditable) {
        if let fid = ev.familia {
            guard var f = arbol.familia(fid) else { return }
            f.eventos.removeAll { $0.id == ev.evento.id }
            arbol.guardar(f)
        } else {
            guard var p = arbol.persona(id) else { return }
            p.eventos.removeAll { $0.id == ev.evento.id }
            arbol.guardar(p)
        }
    }
}

struct IDTexto: Identifiable { let id: String }

struct EventoEditable: Identifiable {
    var id: UUID { evento.id }
    let evento: Evento
    let familia: String?
    let nuevo: Bool
}

struct BotonAccion: View {
    let titulo: String
    let icono: String
    let accion: () -> Void
    var body: some View {
        Button(action: accion) { EtiquetaAccion(titulo: titulo, icono: icono) }.buttonStyle(.plain)
    }
}

struct EtiquetaAccion: View {
    let titulo: String
    let icono: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icono).font(.title3)
            Text(titulo).font(.caption2.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Tema.verde)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Tema.verde.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct NodoCrudoView: View {
    let nodo: NodoGedcom
    var nivel = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(nodo.tag).font(.caption.monospaced().weight(.semibold)).foregroundStyle(Tema.verde)
                Text(nodo.valor).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            .padding(.leading, CGFloat(nivel) * 12)
            ForEach(Array(nodo.hijos.enumerated()), id: \.offset) { _, h in
                NodoCrudoView(nodo: h, nivel: nivel + 1)
            }
        }
    }
}

// MARK: - Visor de fotos

struct VisorFotos: View {
    @Environment(ArbolStore.self) private var arbol
    @Environment(\.dismiss) private var cerrar
    let personaID: String
    @State var inicio: Int
    @State private var editandoTitulo = false
    @State private var titulo = ""

    var fotos: [Medio] { arbol.persona(personaID)?.fotos ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if fotos.isEmpty {
                    Color.black.onAppear { cerrar() }
                } else {
                    TabView(selection: $inicio) {
                        ForEach(Array(fotos.enumerated()), id: \.element.id) { i, m in
                            VStack {
                                Spacer()
                                ImagenMedio(medio: m, ajuste: .fit)
                                Spacer()
                                if !m.titulo.isEmpty || !m.fecha.isEmpty {
                                    Text([m.titulo, FechaGedcom.legible(m.fecha)].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.subheadline).foregroundStyle(.white).padding(.bottom, 40)
                                }
                            }
                            .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                }
            }
            .background(Color.black.ignoresSafeArea())
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { cerrar() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if inicio < fotos.count {
                        let m = fotos[inicio]
                        Menu {
                            Button { arbol.hacerPrincipal(m.id, de: personaID) } label: { Label("Usar como foto de perfil", systemImage: "star") }
                            Button { titulo = m.titulo; editandoTitulo = true } label: { Label("Poner título", systemImage: "textformat") }
                            if let u = arbol.urlLocal(m) {
                                ShareLink(item: u) { Label("Compartir", systemImage: "square.and.arrow.up") }
                            } else if let u = m.urlRemota {
                                ShareLink(item: u) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                            }
                            Button(role: .destructive) {
                                arbol.quitarFoto(m.id, de: personaID)
                                inicio = max(0, min(inicio, fotos.count - 1))
                            } label: { Label("Quitar foto", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
            .alert("Título de la foto", isPresented: $editandoTitulo) {
                TextField("Título", text: $titulo)
                Button("Guardar") {
                    guard var p = arbol.persona(personaID), inicio < p.fotos.count else { return }
                    p.fotos[inicio].titulo = titulo
                    arbol.guardar(p)
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }
}
