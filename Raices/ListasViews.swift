import SwiftUI
import MapKit

// MARK: - Personas

struct ListaPersonasView: View {
    @Environment(ArbolStore.self) private var arbol
    @State private var texto = ""
    @State private var filtro = 0 // 0 todos, 1 vivos, 2 fallecidos, 3 sin padres
    @State private var orden = 0  // 0 apellido, 1 nombre, 2 nacimiento
    @State private var nueva = false

    var body: some View {
        let lista = filtradas
        List {
            Section {
                Picker("Mostrar", selection: $filtro) {
                    Text("Todos").tag(0); Text("Vivos").tag(1); Text("Fallecidos").tag(2); Text("Sin padres").tag(3)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(lista) { p in
                    NavigationLink(value: p.id) { FilaPersona(persona: p) }
                }
            } header: {
                Text("\(lista.count) personas")
            }
        }
        .searchable(text: $texto, prompt: "Nombre, apellido, lugar o año")
        .navigationTitle("Personas")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Ordenar", selection: $orden) {
                        Text("Por apellido").tag(0); Text("Por nombre").tag(1); Text("Por año de nacimiento").tag(2)
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { nueva = true } label: { Image(systemName: "person.badge.plus") }
            }
        }
        .sheet(isPresented: $nueva) { NuevoFamiliarView(relacion: nil, de: nil) }
    }

    var filtradas: [Persona] {
        var l = Array(arbol.datos.personas.values)
        switch filtro {
        case 1: l = l.filter { !$0.fallecido }
        case 2: l = l.filter { $0.fallecido }
        case 3: l = l.filter { arbol.todosLosPadres(de: $0.id).isEmpty }
        default: break
        }
        let t = texto.sinAcentos.recortado
        if !t.isEmpty {
            let partes = t.split(separator: " ").map(String.init)
            l = l.filter { p in
                let s = p.textoBusqueda + " " + (p.anioNacimiento.map(String.init) ?? "") + " " + (p.anioDefuncion.map(String.init) ?? "")
                return partes.allSatisfy { s.contains($0) }
            }
        }
        switch orden {
        case 1: return l.sorted { ($0.nombre.sinAcentos, $0.apellido.sinAcentos) < ($1.nombre.sinAcentos, $1.apellido.sinAcentos) }
        case 2: return l.sorted { ($0.anioNacimiento ?? 9999, $0.apellido) < ($1.anioNacimiento ?? 9999, $1.apellido) }
        default: return l.sorted { ($0.apellido.sinAcentos, $0.nombre.sinAcentos) < ($1.apellido.sinAcentos, $1.nombre.sinAcentos) }
        }
    }
}

// MARK: - Parentesco

struct ParentescoView: View {
    @Environment(ArbolStore.self) private var arbol
    @State private var a: String? = nil
    @State private var b: String? = nil
    @State private var eligiendo: Int? = nil

    var body: some View {
        List {
            Section {
                botonPersona(a, rotulo: "Primera persona") { eligiendo = 0 }
                botonPersona(b, rotulo: "Segunda persona") { eligiendo = 1 }
                if a != nil || b != nil {
                    Button { let t = a; a = b; b = t } label: { Label("Intercambiar", systemImage: "arrow.up.arrow.down") }
                }
            } footer: {
                Text("Descubre cómo están emparentadas dos personas de tu árbol.")
            }
            if let a, let b, let r = Parentesco.calcular(desde: a, hasta: b, en: arbol) {
                Section("Resultado") {
                    Text(r.texto).font(.title3.weight(.semibold)).foregroundStyle(Tema.verde)
                        .padding(.vertical, 4)
                }
                if r.camino.count > 1 {
                    Section("Cómo se conectan") {
                        ForEach(Array(r.camino.enumerated()), id: \.element.id) { i, paso in
                            NavigationLink(value: paso.persona.id) {
                                HStack {
                                    Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                                        .frame(width: 22, height: 22).background(Circle().fill(Tema.verde))
                                    FilaPersona(persona: paso.persona, detalle: i == 0 ? "Inicio" : paso.relacion.capitalized + " de \(r.camino[i - 1].persona.nombreCorto)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Parentesco")
        .onAppear { if a == nil { a = arbol.datos.raiz } }
        .sheet(item: Binding(get: { eligiendo.map { IDTexto(id: String($0)) } }, set: { eligiendo = $0.flatMap { Int($0.id) } })) { e in
            SelectorPersona(titulo: e.id == "0" ? "Primera persona" : "Segunda persona") { id in
                if e.id == "0" { a = id } else { b = id }
            }
        }
    }

    func botonPersona(_ id: String?, rotulo: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            if let p = arbol.persona(id) {
                FilaPersona(persona: p, detalle: rotulo)
            } else {
                Label("Elegir \(rotulo.lowercased())", systemImage: "person.crop.circle.badge.plus")
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Más

struct MasView: View {
    @Environment(ArbolStore.self) private var arbol
    @Environment(Biblioteca.self) private var biblioteca
    @State private var compartir: ArchivoCompartible? = nil
    @State private var error: String? = nil
    @State private var descargando = false
    @State private var progreso = (0, 0)
    @State private var renombrar = false
    @State private var nombre = ""

    var body: some View {
        List {
            Section("Descubrir") {
                NavigationLink { EstadisticasView() } label: { Label("Estadísticas del árbol", systemImage: "chart.bar") }
                NavigationLink { AniversariosView() } label: { Label("Cumpleaños y aniversarios", systemImage: "gift") }
                NavigationLink { LugaresView() } label: { Label("Lugares y mapa", systemImage: "map") }
                NavigationLink { ApellidosView() } label: { Label("Apellidos", systemImage: "textformat") }
            }
            Section {
                Button { exportar(zip: false) } label: { Label("Exportar GEDCOM (.ged)", systemImage: "square.and.arrow.up") }
                Button { exportar(zip: true) } label: { Label("Exportar .zip con GEDCOM y fotos", systemImage: "doc.zipper") }
            } header: { Text("Exportar") } footer: {
                Text("El .ged es compatible con MyHeritage, FamilySearch, Ancestry, Geni y Gramps. Las fotos de MyHeritage se exportan con su enlace original.")
            }
            Section {
                let pendientes = arbol.fotosRemotasPendientes
                Button {
                    descargando = true
                    Task {
                        let n = await arbol.descargarFotosRemotas { h, t in progreso = (h, t) }
                        descargando = false
                        error = n > 0 ? "Se guardaron \(n) fotos en el teléfono." : "No se pudo descargar ninguna foto. Revisa la conexión."
                    }
                } label: {
                    HStack {
                        Label("Descargar fotos de MyHeritage", systemImage: "icloud.and.arrow.down")
                        Spacer()
                        if descargando { Text("\(progreso.0)/\(progreso.1)").foregroundStyle(.secondary).monospacedDigit() }
                        else { Text("\(pendientes)").foregroundStyle(.secondary) }
                    }
                }
                .disabled(pendientes == 0 || descargando)
            } header: { Text("Fotos") } footer: {
                Text("Las fotos importadas desde MyHeritage se cargan desde internet. Descárgalas para verlas sin conexión y no perderlas si caducan los enlaces.")
            }
            Section("Árbol") {
                Button { nombre = arbol.datos.nombre; renombrar = true } label: { Label("Cambiar nombre del árbol", systemImage: "pencil") }
                Button { biblioteca.abierto = nil; biblioteca.cargar() } label: { Label("Ver todos mis árboles", systemImage: "rectangle.stack") }
            }
            Section {
                LabeledContent("Personas", value: "\(arbol.datos.personas.count)")
                LabeledContent("Familias", value: "\(arbol.datos.familias.count)")
                if !arbol.datos.origen.isEmpty { LabeledContent("Importado de", value: arbol.datos.origen.capitalized) }
                LabeledContent("Versión", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            }
        }
        .navigationTitle("Más")
        .sheet(item: $compartir) { a in HojaCompartir(elementos: [a.url]).ignoresSafeArea() }
        .alert("Raíces", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Aceptar", role: .cancel) {}
        } message: { Text(error ?? "") }
        .alert("Nombre del árbol", isPresented: $renombrar) {
            TextField("Nombre", text: $nombre)
            Button("Guardar") { arbol.datos.nombre = nombre; arbol.guardarAhora(); biblioteca.cargar() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    func exportar(zip: Bool) {
        do {
            let url = zip ? try arbol.archivoZip() : try arbol.archivoGedcom()
            compartir = ArchivoCompartible(url: url)
        } catch {
            self.error = "No se pudo exportar: \(error.localizedDescription)"
        }
    }
}

// MARK: - Estadísticas

struct EstadisticasView: View {
    @Environment(ArbolStore.self) private var arbol

    var body: some View {
        let personas = Array(arbol.datos.personas.values)
        let hombres = personas.filter { $0.sexo == .hombre }.count
        let mujeres = personas.filter { $0.sexo == .mujer }.count
        let vivos = personas.filter { !$0.fallecido }.count
        let edades = personas.compactMap { p -> (Persona, Int)? in
            guard p.fallecido, let n = p.nacimiento?.fecha, let d = p.defuncion?.fecha,
                  let e = FechaGedcom.edad(desde: n, hasta: d) else { return nil }
            return (p, e)
        }
        let media = edades.isEmpty ? 0 : edades.map(\.1).reduce(0, +) / edades.count
        let longevos = edades.sorted { $0.1 > $1.1 }.prefix(5)
        let nombres = contar(personas.compactMap { $0.nombre.split(separator: " ").first.map(String.init) })
        let anios = personas.compactMap(\.anioNacimiento)

        List {
            Section("Resumen") {
                LabeledContent("Personas", value: "\(personas.count)")
                LabeledContent("Familias", value: "\(arbol.datos.familias.count)")
                LabeledContent("Hombres / mujeres", value: "\(hombres) / \(mujeres)")
                LabeledContent("Vivos / fallecidos", value: "\(vivos) / \(personas.count - vivos)")
                LabeledContent("Fotos", value: "\(personas.reduce(0) { $0 + $1.fotos.count })")
                if let a = anios.min(), let b = anios.max() { LabeledContent("Nacimientos", value: "\(a) – \(b)") }
                if let r = arbol.datos.raiz { LabeledContent("Generaciones de antepasados", value: "\(generaciones(r))") }
            }
            if !edades.isEmpty {
                Section("Longevidad") {
                    LabeledContent("Edad media al fallecer", value: "\(media) años")
                    ForEach(Array(longevos.enumerated()), id: \.offset) { _, x in
                        NavigationLink(value: x.0.id) { FilaPersona(persona: x.0, detalle: "\(x.1) años") }
                    }
                }
            }
            if !nombres.isEmpty {
                Section("Nombres más comunes") {
                    ForEach(nombres.prefix(8), id: \.0) { n, c in LabeledContent(n, value: "\(c)") }
                }
            }
            if !anios.isEmpty {
                Section("Nacimientos por siglo") {
                    ForEach(contar(anios.map { "Siglo \(romano(($0 - 1) / 100 + 1))" }).sorted { $0.0 < $1.0 }, id: \.0) { s, c in
                        HStack {
                            Text(s).frame(width: 90, alignment: .leading)
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 4).fill(Tema.verde.opacity(0.7))
                                    .frame(width: max(4, g.size.width * CGFloat(c) / CGFloat(max(1, anios.count))))
                            }
                            .frame(height: 14)
                            Text("\(c)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Estadísticas")
    }

    func generaciones(_ id: String) -> Int {
        var nivel = [id], g = 0, vistos: Set<String> = [id]
        while !nivel.isEmpty && g < 60 {
            let sig = nivel.flatMap { arbol.todosLosPadres(de: $0).map(\.id) }.filter { vistos.insert($0).inserted }
            if sig.isEmpty { break }
            g += 1
            nivel = sig
        }
        return g
    }

    func romano(_ n: Int) -> String {
        let v = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var n = n, r = ""
        for (k, s) in v { while n >= k { r += s; n -= k } }
        return r
    }
}

func contar(_ l: [String]) -> [(String, Int)] {
    var d: [String: Int] = [:]
    for x in l where !x.isEmpty { d[x, default: 0] += 1 }
    return d.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { ($0.key, $0.value) }
}

// MARK: - Apellidos

struct ApellidosView: View {
    @Environment(ArbolStore.self) private var arbol

    var body: some View {
        let lista = contar(arbol.datos.personas.values.compactMap { $0.apellido.split(separator: " ").first.map(String.init) })
        List(lista, id: \.0) { a, c in
            NavigationLink {
                List(arbol.personasOrdenadas.filter { $0.apellido.hasPrefix(a) }) { p in
                    NavigationLink(value: p.id) { FilaPersona(persona: p) }
                }
                .navigationTitle(a)
            } label: { LabeledContent(a, value: "\(c)") }
        }
        .navigationTitle("Apellidos")
    }
}

// MARK: - Aniversarios

struct AniversariosView: View {
    @Environment(ArbolStore.self) private var arbol
    @State private var mes = Calendar.current.component(.month, from: Date())

    struct Fila: Identifiable {
        let id = UUID()
        let persona: Persona
        let dia: Int
        let texto: String
    }

    var body: some View {
        let filas = calcular()
        List {
            Section {
                Picker("Mes", selection: $mes) {
                    ForEach(1...12, id: \.self) { Text(FechaGedcom.mesesLargos[$0 - 1].capitalized).tag($0) }
                }
            }
            if filas.isEmpty {
                Text("No hay fechas completas registradas en este mes.").foregroundStyle(.secondary)
            }
            ForEach(filas) { f in
                NavigationLink(value: f.persona.id) {
                    HStack(spacing: 12) {
                        Text("\(f.dia)").font(.title3.bold()).foregroundStyle(Tema.verde).frame(width: 34)
                        FilaPersona(persona: f.persona, detalle: f.texto)
                    }
                }
            }
        }
        .navigationTitle("Aniversarios")
    }

    func calcular() -> [Fila] {
        let anioActual = Calendar.current.component(.year, from: Date())
        var r: [Fila] = []
        for p in arbol.datos.personas.values {
            if let n = p.evento("BIRT"), let md = FechaGedcom.mesYDia(n.fecha), md.mes == mes {
                let anios = FechaGedcom.anio(n.fecha).map { anioActual - $0 }
                let t = p.fallecido ? "Nació" + (anios.map { " hace \($0) años" } ?? "") : "Cumpleaños" + (anios.map { " · cumple \($0)" } ?? "")
                r.append(Fila(persona: p, dia: md.dia, texto: t))
            }
            if let d = p.evento("DEAT"), let md = FechaGedcom.mesYDia(d.fecha), md.mes == mes {
                r.append(Fila(persona: p, dia: md.dia, texto: "Aniversario de fallecimiento"))
            }
        }
        for f in arbol.datos.familias.values {
            guard let m = f.eventos.first(where: { $0.tipo == "MARR" }), let md = FechaGedcom.mesYDia(m.fecha), md.mes == mes,
                  let p = arbol.persona(f.pareja1) ?? arbol.persona(f.pareja2) else { continue }
            let otro = arbol.persona(f.otro(de: p.id))
            let anios = FechaGedcom.anio(m.fecha).map { anioActual - $0 }
            r.append(Fila(persona: p, dia: md.dia, texto: "Boda" + (otro.map { " con \($0.nombreCorto)" } ?? "") + (anios.map { " · \($0) años" } ?? "")))
        }
        return r.sorted { $0.dia < $1.dia }
    }
}

// MARK: - Lugares

struct LugaresView: View {
    @Environment(ArbolStore.self) private var arbol

    struct Punto: Identifiable {
        let id: String
        let nombre: String
        let coord: CLLocationCoordinate2D
        let cantidad: Int
    }

    var body: some View {
        let datos = calcular()
        let lugares = datos.0
        let puntos = datos.1
        List {
            if !puntos.isEmpty {
                Section {
                    Map {
                        ForEach(puntos) { p in
                            Marker("\(p.nombre) (\(p.cantidad))", systemImage: "mappin", coordinate: p.coord)
                                .tint(Tema.verde)
                        }
                    }
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("En el mapa aparecen los lugares que tienen coordenadas en el archivo (MyHeritage suele incluirlas).")
                }
            }
            Section("\(lugares.count) lugares") {
                ForEach(lugares, id: \.0) { l, c in
                    NavigationLink {
                        PersonasDeLugarView(lugar: l)
                    } label: { LabeledContent(l, value: "\(c)") }
                }
            }
        }
        .navigationTitle("Lugares")
    }

    func calcular() -> ([(String, Int)], [Punto]) {
        var todos: [String] = []
        var coords: [String: (CLLocationCoordinate2D, Int)] = [:]
        func ver(_ e: Evento) {
            guard !e.lugar.isEmpty else { return }
            todos.append(e.lugar)
            if let plac = e.extra.first(where: { $0.tag == "PLAC" }), let map = plac.primero("MAP"),
               let la = coordenada(map.valorDe("LATI")), let lo = coordenada(map.valorDe("LONG")) {
                let c = coords[e.lugar]?.1 ?? 0
                coords[e.lugar] = (CLLocationCoordinate2D(latitude: la, longitude: lo), c + 1)
            }
        }
        for p in arbol.datos.personas.values { p.eventos.forEach(ver) }
        for f in arbol.datos.familias.values { f.eventos.forEach(ver) }
        let puntos = coords.map { Punto(id: $0.key, nombre: $0.key, coord: $0.value.0, cantidad: $0.value.1) }
        return (contar(todos), puntos)
    }

    func coordenada(_ s: String?) -> Double? {
        guard var t = s?.recortado.uppercased(), !t.isEmpty else { return nil }
        var signo = 1.0
        if let f = t.first, "NSEW".contains(f) {
            if f == "S" || f == "W" { signo = -1 }
            t.removeFirst()
        }
        return Double(t.replacingOccurrences(of: ",", with: ".")).map { $0 * signo }
    }
}

struct PersonasDeLugarView: View {
    @Environment(ArbolStore.self) private var arbol
    let lugar: String

    var body: some View {
        List {
            ForEach(arbol.personasOrdenadas.filter { p in p.eventos.contains { $0.lugar == lugar } }) { p in
                NavigationLink(value: p.id) {
                    FilaPersona(persona: p, detalle: p.eventos.filter { $0.lugar == lugar }.map(\.titulo).joined(separator: ", "))
                }
            }
        }
        .navigationTitle(lugar)
    }
}
