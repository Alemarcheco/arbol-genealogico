import SwiftUI

// MARK: - Campo de fecha

struct CampoFecha: View {
    let titulo: String
    @Binding var fecha: String
    @State private var editando = false

    var body: some View {
        Button { editando = true } label: {
            HStack {
                Text(titulo).foregroundStyle(.primary)
                Spacer()
                Text(fecha.isEmpty ? "Añadir fecha" : FechaGedcom.legible(fecha))
                    .foregroundStyle(fecha.isEmpty ? Color.secondary : Tema.verde)
            }
        }
        .sheet(isPresented: $editando) {
            EditorFecha(titulo: titulo, fecha: $fecha)
                .presentationDetents([.medium, .large])
        }
    }
}

struct EditorFecha: View {
    let titulo: String
    @Binding var fecha: String
    @Environment(\.dismiss) private var cerrar
    @State private var partes = FechaGedcom.Partes()
    @State private var textoAnio = ""
    @State private var libre = false
    @State private var textoLibre = ""

    var body: some View {
        NavigationStack {
            Form {
                if libre {
                    Section {
                        TextField("p. ej. BET 1900 AND 1910", text: $textoLibre)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        if !textoLibre.isEmpty { Text(FechaGedcom.legible(textoLibre)).foregroundStyle(.secondary) }
                    } header: { Text("Fecha en formato GEDCOM") } footer: {
                        Text("Admite rangos: BET 1900 AND 1910 (entre), FROM 1940 TO 1950 (desde/hasta), ABT (hacia), BEF (antes), AFT (después).")
                    }
                } else {
                    Section {
                        Picker("Precisión", selection: $partes.modificador) {
                            ForEach(FechaGedcom.Modificador.allCases) { Text($0.nombre).tag($0) }
                        }
                        Picker("Día", selection: $partes.dia) {
                            Text("—").tag(Int?.none)
                            ForEach(1...31, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                        }
                        Picker("Mes", selection: $partes.mes) {
                            Text("—").tag(Int?.none)
                            ForEach(1...12, id: \.self) { Text(FechaGedcom.mesesLargos[$0 - 1].capitalized).tag(Int?.some($0)) }
                        }
                        HStack {
                            Text("Año")
                            TextField("p. ej. 1952", text: $textoAnio)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                        }
                    } footer: {
                        let g = actual
                        Text(g.isEmpty ? "Puedes poner solo el año si no sabes el día exacto." : "Se guardará como: \(FechaGedcom.legible(g))")
                    }
                }
                Section {
                    Button(libre ? "Usar selector sencillo" : "Escribir fecha avanzada (rangos)") {
                        if libre {
                            if let p = FechaGedcom.partes(textoLibre) { cargar(p) }
                        } else { textoLibre = actual }
                        libre.toggle()
                    }
                    if !fecha.isEmpty {
                        Button("Borrar fecha", role: .destructive) { fecha = ""; cerrar() }
                    }
                }
            }
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { fecha = actual; cerrar() }
                }
            }
            .onAppear {
                if let p = FechaGedcom.partes(fecha) { cargar(p) } else { libre = true; textoLibre = fecha }
            }
        }
    }

    func cargar(_ p: FechaGedcom.Partes) {
        partes = p
        textoAnio = p.anio.map(String.init) ?? ""
    }

    var actual: String {
        if libre { return textoLibre.recortado.uppercased() }
        var p = partes
        p.anio = Int(textoAnio.filter(\.isNumber))
        return p.gedcom
    }
}

// MARK: - Editar persona

struct EditarPersonaView: View {
    @Environment(ArbolStore.self) private var arbol
    @Environment(\.dismiss) private var cerrar
    let original: Persona
    @State private var p: Persona
    @State private var nacFecha = ""
    @State private var nacLugar = ""
    @State private var fallecido = false
    @State private var defFecha = ""
    @State private var defLugar = ""
    @State private var eventoEditado: Evento? = nil

    init(original: Persona) {
        self.original = original
        _p = State(initialValue: original)
        let n = original.evento("BIRT")
        _nacFecha = State(initialValue: n?.fecha ?? "")
        _nacLugar = State(initialValue: n?.lugar ?? "")
        let d = original.evento("DEAT")
        _fallecido = State(initialValue: original.fallecido)
        _defFecha = State(initialValue: d?.fecha ?? "")
        _defLugar = State(initialValue: d?.lugar ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre") {
                    TextField("Nombre(s)", text: $p.nombre)
                    TextField("Apellidos", text: $p.apellido)
                    TextField("Apellido de casada", text: $p.apellidoCasada)
                    TextField("Apodo", text: $p.apodo)
                    DisclosureGroup("Más") {
                        TextField("Título o prefijo (Dr., Sr.)", text: $p.prefijo)
                        TextField("Sufijo (Jr., III)", text: $p.sufijo)
                    }
                }
                Section {
                    Picker("Sexo", selection: $p.sexo) {
                        ForEach(Sexo.allCases) { Text($0.nombre).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Nacimiento") {
                    CampoFecha(titulo: "Fecha", fecha: $nacFecha)
                    TextField("Lugar", text: $nacLugar)
                }
                Section {
                    Toggle("Ha fallecido", isOn: $fallecido)
                    if fallecido {
                        CampoFecha(titulo: "Fecha de defunción", fecha: $defFecha)
                        TextField("Lugar de defunción", text: $defLugar)
                    }
                }
                Section("Otros hechos y eventos") {
                    ForEach(p.eventos.filter { $0.tipo != "BIRT" && $0.tipo != "DEAT" }) { e in
                        Button { eventoEditado = e } label: {
                            HStack {
                                Image(systemName: e.info.icono).frame(width: 24).foregroundStyle(Tema.verde)
                                VStack(alignment: .leading) {
                                    Text(e.titulo).foregroundStyle(.primary)
                                    let t = [e.valor, FechaGedcom.legible(e.fecha), e.lugar].filter { !$0.isEmpty }.joined(separator: " · ")
                                    if !t.isEmpty { Text(t).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        let visibles = p.eventos.filter { $0.tipo != "BIRT" && $0.tipo != "DEAT" }
                        let ids = Set(idx.map { visibles[$0].id })
                        p.eventos.removeAll { ids.contains($0.id) }
                    }
                    Button { eventoEditado = Evento(tipo: "RESI") } label: { Label("Añadir evento", systemImage: "plus") }
                }
                Section("Contacto y notas") {
                    TextField("Correo electrónico", text: $p.correo)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("Notas, biografía, recuerdos…", text: $p.notas, axis: .vertical)
                        .lineLimit(4...12)
                }
            }
            .navigationTitle("Editar perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { guardar(); cerrar() } }
            }
            .sheet(item: $eventoEditado) { e in
                EditarEventoView(evento: e, deFamilia: false, nuevo: !p.eventos.contains(where: { $0.id == e.id })) { nuevo in
                    if let i = p.eventos.firstIndex(where: { $0.id == nuevo.id }) { p.eventos[i] = nuevo } else { p.eventos.append(nuevo) }
                } borrar: {
                    p.eventos.removeAll { $0.id == e.id }
                }
            }
        }
    }

    func guardar() {
        var q = p
        q.nombre = q.nombre.recortado
        q.apellido = q.apellido.recortado
        Self.fijar(&q, tipo: "BIRT", fecha: nacFecha, lugar: nacLugar.recortado, activo: true)
        Self.fijar(&q, tipo: "DEAT", fecha: defFecha, lugar: defLugar.recortado, activo: fallecido)
        if !fallecido { q.eventos.removeAll { $0.tipo == "BURI" || $0.tipo == "CREM" } }
        arbol.guardar(q)
    }

    static func fijar(_ q: inout Persona, tipo: String, fecha: String, lugar: String, activo: Bool) {
        if let i = q.eventos.firstIndex(where: { $0.tipo == tipo }) {
            if !activo { q.eventos.remove(at: i); return }
            q.eventos[i].fecha = fecha
            q.eventos[i].lugar = lugar
        } else if activo && (!fecha.isEmpty || !lugar.isEmpty || tipo == "DEAT") {
            let e = Evento(tipo: tipo, fecha: fecha, lugar: lugar)
            if tipo == "BIRT" { q.eventos.insert(e, at: 0) } else { q.eventos.append(e) }
        }
    }
}

// MARK: - Editar evento

struct EditarEventoView: View {
    @Environment(\.dismiss) private var cerrar
    @State var evento: Evento
    let deFamilia: Bool
    let nuevo: Bool
    let guardar: (Evento) -> Void
    let borrar: () -> Void

    var tipos: [TipoEvento] {
        var l = deFamilia ? TipoEvento.familiares : (TipoEvento.individuales + TipoEvento.otros)
        if !l.contains(where: { $0.tag == evento.tipo }) { l.append(TipoEvento.de(evento.tipo)) }
        return l
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $evento.tipo) {
                        ForEach(tipos) { t in Label(t.nombre, systemImage: t.icono).tag(t.tag) }
                    }
                    if evento.tipo == "EVEN" || evento.tipo == "FACT" {
                        TextField("¿Qué evento? (p. ej. Viaje a España)", text: $evento.subtipo)
                    }
                    if evento.info.conValor || !evento.valor.isEmpty {
                        TextField(evento.tipo == "OCCU" ? "Profesión u oficio" : "Descripción", text: $evento.valor)
                    }
                }
                Section {
                    CampoFecha(titulo: "Fecha", fecha: $evento.fecha)
                    TextField("Lugar (ciudad, provincia, país)", text: $evento.lugar)
                }
                Section("Notas") {
                    TextField("Detalles", text: $evento.notas, axis: .vertical).lineLimit(3...10)
                }
                if !evento.extra.isEmpty {
                    Section("Datos adicionales del archivo") {
                        ForEach(Array(evento.extra.enumerated()), id: \.offset) { _, n in NodoCrudoView(nodo: n) }
                    }
                }
                if !nuevo {
                    Section {
                        Button("Eliminar evento", role: .destructive) { borrar(); cerrar() }
                    }
                }
            }
            .navigationTitle(nuevo ? "Nuevo evento" : evento.titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        var e = evento
                        e.lugar = e.lugar.recortado
                        guardar(e)
                        cerrar()
                    }
                }
            }
        }
    }
}

// MARK: - Nuevo familiar

struct NuevoFamiliarView: View {
    @Environment(ArbolStore.self) private var arbol
    @Environment(\.dismiss) private var cerrar
    let relacion: Relacion?
    let de: String?

    @State private var nombre = ""
    @State private var apellido = ""
    @State private var sexo: Sexo = .desconocido
    @State private var nacFecha = ""
    @State private var nacLugar = ""
    @State private var fallecido = false
    @State private var defFecha = ""
    @State private var familiaHijo: String? = nil
    @State private var elegirExistente = false
    @State private var preparado = false

    var persona: Persona? { arbol.persona(de) }
    var esHijo: Bool { relacion == .hijo || relacion == .hija }

    var body: some View {
        NavigationStack {
            Form {
                if let r = relacion, let p = persona {
                    Section {
                        Button { elegirExistente = true } label: {
                            Label("Elegir a alguien que ya está en el árbol", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    } footer: {
                        Text("\(r.titulo.replacingOccurrences(of: "Añadir ", with: "").capitalized) de \(p.nombreCompleto)")
                    }
                }
                Section("Nombre") {
                    TextField("Nombre(s)", text: $nombre)
                    TextField("Apellidos", text: $apellido)
                    Picker("Sexo", selection: $sexo) {
                        ForEach(Sexo.allCases) { Text($0.nombre).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if esHijo, let p = persona, arbol.parejas(de: p.id).count > 1 {
                    Section("Otro progenitor") {
                        Picker("Con", selection: $familiaHijo) {
                            ForEach(arbol.parejas(de: p.id), id: \.familia.id) { item in
                                Text(item.pareja?.nombreCompleto ?? "Sin pareja registrada").tag(String?.some(item.familia.id))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
                Section("Nacimiento") {
                    CampoFecha(titulo: "Fecha", fecha: $nacFecha)
                    TextField("Lugar", text: $nacLugar)
                }
                Section {
                    Toggle("Ha fallecido", isOn: $fallecido)
                    if fallecido { CampoFecha(titulo: "Fecha de defunción", fecha: $defFecha) }
                }
            }
            .navigationTitle(relacion?.titulo ?? "Nueva persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar(); cerrar() }
                        .disabled(nombre.recortado.isEmpty && apellido.recortado.isEmpty)
                }
            }
            .sheet(isPresented: $elegirExistente) {
                SelectorPersona(titulo: relacion?.titulo ?? "Elegir", excluir: [de ?? ""]) { id in
                    if let r = relacion, let d = de {
                        arbol.agregar(r, a: d, nueva: nil, existente: id, familia: familiaHijo)
                    }
                    cerrar()
                }
            }
            .onAppear(perform: preparar)
        }
    }

    func preparar() {
        guard !preparado else { return }
        preparado = true
        guard let r = relacion else { return }
        sexo = r.sexo
        guard let p = persona else { return }
        let apellidos = p.apellido.split(separator: " ").map(String.init)
        switch r {
        case .padre: apellido = apellidos.first ?? ""
        case .madre: apellido = apellidos.count > 1 ? apellidos[1] : ""
        case .hermano, .hermana: apellido = p.apellido
        case .hijo, .hija:
            let fams = arbol.parejas(de: p.id)
            familiaHijo = fams.first?.familia.id
            // Apellido paterno + materno (costumbre hispana).
            let pareja = fams.first?.pareja
            let (padre, madre) = p.sexo == .mujer ? (pareja, Optional(p)) : (Optional(p), pareja)
            let a = padre?.apellido.split(separator: " ").first.map(String.init) ?? ""
            let b = madre?.apellido.split(separator: " ").first.map(String.init) ?? ""
            apellido = [a, b].filter { !$0.isEmpty }.joined(separator: " ")
        case .pareja:
            sexo = p.sexo == .hombre ? .mujer : p.sexo == .mujer ? .hombre : .desconocido
        }
    }

    func guardar() {
        var p = Persona(id: "", nombre: nombre.recortado, apellido: apellido.recortado, sexo: sexo)
        if !nacFecha.isEmpty || !nacLugar.recortado.isEmpty {
            p.eventos.append(Evento(tipo: "BIRT", fecha: nacFecha, lugar: nacLugar.recortado))
        }
        if fallecido { p.eventos.append(Evento(tipo: "DEAT", fecha: defFecha)) }
        if let r = relacion, let d = de {
            arbol.agregar(r, a: d, nueva: p, familia: familiaHijo)
        } else {
            let id = arbol.crearPersona(p)
            arbol.foco = id
            if arbol.datos.raiz == nil { arbol.datos.raiz = id }
        }
    }
}

// MARK: - Editar relación (familia)

struct EditarFamiliaView: View {
    @Environment(ArbolStore.self) private var arbol
    @Environment(\.dismiss) private var cerrar
    let familiaID: String
    let desde: String
    @State private var eventoEditado: EventoEditable? = nil
    @State private var notas = ""
    @State private var confirmar = false

    var body: some View {
        NavigationStack {
            if let f = arbol.familia(familiaID) {
                Form {
                    Section("Pareja") {
                        ForEach(f.parejas.compactMap { arbol.persona($0) }) { FilaPersona(persona: $0) }
                    }
                    Section("Eventos de la pareja") {
                        ForEach(f.eventos) { e in
                            Button { eventoEditado = EventoEditable(evento: e, familia: f.id, nuevo: false) } label: {
                                HStack {
                                    Image(systemName: e.info.icono).foregroundStyle(Tema.mujer).frame(width: 24)
                                    VStack(alignment: .leading) {
                                        Text(e.titulo).foregroundStyle(.primary)
                                        let t = [FechaGedcom.legible(e.fecha), e.lugar].filter { !$0.isEmpty }.joined(separator: " · ")
                                        if !t.isEmpty { Text(t).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                        if !f.eventos.contains(where: { $0.tipo == "MARR" }) {
                            Button { eventoEditado = EventoEditable(evento: Evento(tipo: "MARR"), familia: f.id, nuevo: true) } label: {
                                Label("Añadir matrimonio", systemImage: "heart.fill")
                            }
                        }
                        Button { eventoEditado = EventoEditable(evento: Evento(tipo: "DIV"), familia: f.id, nuevo: true) } label: {
                            Label("Añadir otro evento (divorcio, compromiso…)", systemImage: "plus")
                        }
                    }
                    Section("Notas") {
                        TextField("Notas de la pareja", text: $notas, axis: .vertical).lineLimit(2...8)
                    }
                    Section {
                        Button("Quitar \(arbol.persona(desde)?.nombreCorto ?? "") de esta relación", role: .destructive) { confirmar = true }
                    } footer: {
                        Text("Las personas no se borran; solo se deshace el vínculo.")
                    }
                }
                .navigationTitle("Relación")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") {
                            if var g = arbol.familia(familiaID), g.notas != notas { g.notas = notas; arbol.guardar(g) }
                            cerrar()
                        }
                    }
                }
                .onAppear { notas = f.notas }
                .sheet(item: $eventoEditado) { ev in
                    EditarEventoView(evento: ev.evento, deFamilia: true, nuevo: ev.nuevo) { e in
                        guard var g = arbol.familia(familiaID) else { return }
                        if let i = g.eventos.firstIndex(where: { $0.id == e.id }) { g.eventos[i] = e } else { g.eventos.append(e) }
                        arbol.guardar(g)
                    } borrar: {
                        guard var g = arbol.familia(familiaID) else { return }
                        g.eventos.removeAll { $0.id == ev.evento.id }
                        arbol.guardar(g)
                    }
                }
                .confirmationDialog("¿Deshacer este vínculo?", isPresented: $confirmar, titleVisibility: .visible) {
                    Button("Quitar vínculo", role: .destructive) {
                        arbol.desvincular(desde, de: familiaID)
                        cerrar()
                    }
                }
            } else {
                ContentUnavailableView("Relación eliminada", systemImage: "heart.slash")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { cerrar() } } }
            }
        }
    }
}
