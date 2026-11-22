import Foundation
import Observation
import UIKit

struct ResumenArbol: Identifiable, Codable, Hashable {
    var id: UUID
    var nombre: String
    var personas: Int
    var modificado: Date
    var origen: String
}

// MARK: - Biblioteca de árboles

@MainActor
@Observable
final class Biblioteca {
    var arboles: [ResumenArbol] = []
    var abierto: ArbolStore? = nil
    var importando = false
    var mensaje: String? = nil

    static var carpetaBase: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let c = d.appendingPathComponent("Arboles", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }

    static func carpeta(_ id: UUID) -> URL { carpetaBase.appendingPathComponent(id.uuidString, isDirectory: true) }

    init() { cargar() }

    func cargar() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Self.carpetaBase, includingPropertiesForKeys: nil)) ?? []
        var lista: [ResumenArbol] = []
        for d in dirs {
            let meta = d.appendingPathComponent("resumen.json")
            if let data = try? Data(contentsOf: meta), let r = try? JSONDecoder().decode(ResumenArbol.self, from: data) {
                lista.append(r)
            }
        }
        arboles = lista.sorted { $0.modificado > $1.modificado }
    }

    func crear(nombre: String, primera: Persona?) -> ArbolStore {
        var datos = DatosArbol(nombre: nombre.isEmpty ? "Mi árbol" : nombre)
        if var p = primera {
            p.id = "I1"
            datos.personas[p.id] = p
            datos.raiz = p.id
            datos.siguienteNumero = 2
        }
        let store = ArbolStore(datos: datos)
        store.guardarAhora()
        cargar()
        abierto = store
        return store
    }

    func abrir(_ id: UUID) {
        if let s = ArbolStore.cargar(id: id) { abierto = s } else { mensaje = "No se pudo abrir el árbol." }
    }

    func eliminar(_ id: UUID) {
        try? FileManager.default.removeItem(at: Self.carpeta(id))
        if abierto?.datos.id == id { abierto = nil }
        cargar()
    }

    func renombrar(_ id: UUID, a nombre: String) {
        guard let s = (abierto?.datos.id == id ? abierto : ArbolStore.cargar(id: id)) else { return }
        s.datos.nombre = nombre
        s.guardarAhora()
        cargar()
    }

    /// Importa un .ged (o .zip con .ged y fotos) desde una URL de archivo.
    func importar(url: URL) {
        let acceso = url.startAccessingSecurityScopedResource()
        defer { if acceso { url.stopAccessingSecurityScopedResource() } }
        guard let datos = try? Data(contentsOf: url) else {
            mensaje = "No se pudo leer el archivo."
            return
        }
        let nombre = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
        importando = true
        Task {
            do {
                let (resultado, archivos) = try await Task.detached(priority: .userInitiated) {
                    try Self.procesar(datos: datos, nombre: nombre)
                }.value
                let store = ArbolStore(datos: resultado.datos)
                var fotosZip = 0
                if !archivos.isEmpty { fotosZip = store.integrarFotosDeZip(archivos) }
                store.guardarAhora()
                self.cargar()
                self.abierto = store
                var texto = "Importadas \(resultado.personas) personas y \(resultado.familias) familias"
                if resultado.fotos > 0 { texto += ", \(resultado.fotos) fotos" }
                if fotosZip > 0 { texto += " (\(fotosZip) incluidas en el ZIP)" }
                if !resultado.datos.origen.isEmpty { texto += ". Origen: \(resultado.datos.origen.capitalized)" }
                self.mensaje = texto + "."
            } catch {
                self.mensaje = error.localizedDescription
            }
            self.importando = false
        }
    }

    nonisolated static func procesar(datos: Data, nombre: String) throws -> (ImportadorGedcom.Resultado, [Zip.Entrada]) {
        if Zip.esZip(datos) {
            let entradas = try Zip.leer(datos) { n in
                let e = (n as NSString).pathExtension.lowercased()
                return !n.hasPrefix("__MACOSX") && ["ged", "jpg", "jpeg", "png", "gif", "heic", "bmp", "tif", "tiff", "webp"].contains(e)
            }
            guard let ged = entradas.first(where: { $0.nombre.lowercased().hasSuffix(".ged") }) else {
                throw ImportadorGedcom.Fallo.vacio
            }
            let nom = ((ged.nombre as NSString).lastPathComponent as NSString).deletingPathExtension
            let r = try ImportadorGedcom.importar(datos: ged.datos, nombre: nom.isEmpty ? nombre : nom)
            return (r, entradas.filter { !$0.nombre.lowercased().hasSuffix(".ged") })
        }
        return (try ImportadorGedcom.importar(datos: datos, nombre: nombre), [])
    }
}

// MARK: - Árbol abierto

enum Relacion: String, Identifiable, CaseIterable {
    case padre, madre, pareja, hijo, hija, hermano, hermana
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .padre: return "Añadir padre"
        case .madre: return "Añadir madre"
        case .pareja: return "Añadir pareja"
        case .hijo: return "Añadir hijo"
        case .hija: return "Añadir hija"
        case .hermano: return "Añadir hermano"
        case .hermana: return "Añadir hermana"
        }
    }
    var sexo: Sexo {
        switch self {
        case .padre, .hijo, .hermano: return .hombre
        case .madre, .hija, .hermana: return .mujer
        case .pareja: return .desconocido
        }
    }
    var icono: String {
        switch self {
        case .padre, .madre: return "arrow.up.circle"
        case .pareja: return "heart.circle"
        case .hijo, .hija: return "arrow.down.circle"
        case .hermano, .hermana: return "arrow.left.and.right.circle"
        }
    }
}

@MainActor
@Observable
final class ArbolStore {
    var datos: DatosArbol
    var foco: String? = nil
    @ObservationIgnored private var tareaGuardado: Task<Void, Never>? = nil
    @ObservationIgnored private var cacheImagenes = NSCache<NSString, UIImage>()

    init(datos: DatosArbol) {
        self.datos = datos
        self.foco = datos.raiz ?? datos.personas.keys.sorted().first
    }

    var carpeta: URL { Biblioteca.carpeta(datos.id) }
    var carpetaFotos: URL {
        let c = carpeta.appendingPathComponent("fotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }

    static func cargar(id: UUID) -> ArbolStore? {
        let url = Biblioteca.carpeta(id).appendingPathComponent("arbol.json")
        guard let data = try? Data(contentsOf: url),
              let datos = try? JSONDecoder().decode(DatosArbol.self, from: data) else { return nil }
        return ArbolStore(datos: datos)
    }

    // MARK: guardado

    func cambiado() {
        datos.modificado = Date()
        tareaGuardado?.cancel()
        tareaGuardado = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.guardarAhora()
        }
    }

    func guardarAhora() {
        let fm = FileManager.default
        try? fm.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        if let d = try? enc.encode(datos) {
            try? d.write(to: carpeta.appendingPathComponent("arbol.json"), options: .atomic)
        }
        let r = ResumenArbol(id: datos.id, nombre: datos.nombre, personas: datos.personas.count,
                             modificado: datos.modificado, origen: datos.origen)
        if let d = try? enc.encode(r) {
            try? d.write(to: carpeta.appendingPathComponent("resumen.json"), options: .atomic)
        }
    }

    // MARK: consultas

    func persona(_ id: String?) -> Persona? { id.flatMap { datos.personas[$0] } }
    func familia(_ id: String?) -> Familia? { id.flatMap { datos.familias[$0] } }

    var personasOrdenadas: [Persona] {
        datos.personas.values.sorted {
            let a = ($0.apellido.sinAcentos, $0.nombre.sinAcentos), b = ($1.apellido.sinAcentos, $1.nombre.sinAcentos)
            return a < b
        }
    }

    func familiaDePadres(de id: String) -> Familia? {
        guard let p = persona(id) else { return nil }
        return p.familiasComoHijo.compactMap { familia($0) }.first
    }

    func padres(de id: String) -> (padre: Persona?, madre: Persona?) {
        guard let f = familiaDePadres(de: id) else { return (nil, nil) }
        let a = persona(f.pareja1), b = persona(f.pareja2)
        // Si los sexos están invertidos, se ordenan para mostrar padre a la izquierda.
        if a?.sexo == .mujer || b?.sexo == .hombre { return (b, a) }
        return (a, b)
    }

    func todosLosPadres(de id: String) -> [Persona] {
        guard let p = persona(id) else { return [] }
        var r: [Persona] = []
        for fid in p.familiasComoHijo { if let f = familia(fid) { r += f.parejas.compactMap { persona($0) } } }
        return r
    }

    func familiasComoPareja(de id: String) -> [Familia] {
        persona(id)?.familiasComoPareja.compactMap { familia($0) } ?? []
    }

    func parejas(de id: String) -> [(pareja: Persona?, familia: Familia)] {
        familiasComoPareja(de: id).map { (persona($0.otro(de: id)), $0) }
    }

    func hijos(de id: String) -> [Persona] {
        var vistos = Set<String>()
        var r: [Persona] = []
        for f in familiasComoPareja(de: id) {
            for c in f.hijos where !vistos.contains(c) {
                vistos.insert(c)
                if let p = persona(c) { r.append(p) }
            }
        }
        return ordenarPorNacimiento(r)
    }

    func hijos(familia f: Familia) -> [Persona] { ordenarPorNacimiento(f.hijos.compactMap { persona($0) }) }

    func hermanos(de id: String) -> [Persona] {
        guard let p = persona(id) else { return [] }
        var vistos: Set<String> = [id]
        var r: [Persona] = []
        for fid in p.familiasComoHijo {
            for c in familia(fid)?.hijos ?? [] where !vistos.contains(c) {
                vistos.insert(c)
                if let h = persona(c) { r.append(h) }
            }
        }
        return ordenarPorNacimiento(r)
    }

    func ordenarPorNacimiento(_ l: [Persona]) -> [Persona] {
        l.enumerated().sorted { a, b in
            switch (a.element.anioNacimiento, b.element.anioNacimiento) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Texto de una nota compartida (NOTE @N1@) guardada en los registros de nivel 0.
    func notaCompartida(_ ref: String) -> String? {
        let x = ref.trimmingCharacters(in: CharacterSet(charactersIn: "@ "))
        return datos.otrosRegistros.first { $0.tag == "NOTE" && $0.xref == x }?.valor
    }

    func notasVinculadas(_ p: Persona) -> [String] {
        p.extra.filter { $0.tag == "NOTE" && $0.valor.hasPrefix("@") }.compactMap { notaCompartida($0.valor) }
    }

    // MARK: modificaciones

    private func nuevoID(_ prefijo: String) -> String {
        var n = datos.siguienteNumero
        while datos.personas["\(prefijo)\(n)"] != nil || datos.familias["\(prefijo)\(n)"] != nil { n += 1 }
        datos.siguienteNumero = n + 1
        return "\(prefijo)\(n)"
    }

    func guardar(_ p: Persona) {
        var p = p
        p.modificado = Date()
        datos.personas[p.id] = p
        cambiado()
    }

    func guardar(_ f: Familia) {
        datos.familias[f.id] = f
        cambiado()
    }

    @discardableResult
    func crearPersona(_ base: Persona) -> String {
        var p = base
        p.id = nuevoID("I")
        p.familiasComoHijo = []
        p.familiasComoPareja = []
        datos.personas[p.id] = p
        if datos.raiz == nil { datos.raiz = p.id }
        if foco == nil { foco = p.id }
        cambiado()
        return p.id
    }

    private func crearFamilia(pareja1: String? = nil, pareja2: String? = nil) -> String {
        let id = nuevoID("F")
        var f = Familia(id: id)
        f.pareja1 = pareja1
        f.pareja2 = pareja2
        datos.familias[id] = f
        for x in [pareja1, pareja2].compactMap({ $0 }) { datos.personas[x]?.familiasComoPareja.append(id) }
        return id
    }

    private func ponerHijo(_ hijo: String, en fid: String) {
        if datos.familias[fid]?.hijos.contains(hijo) == false { datos.familias[fid]?.hijos.append(hijo) }
        if datos.personas[hijo]?.familiasComoHijo.contains(fid) == false { datos.personas[hijo]?.familiasComoHijo.append(fid) }
    }

    private func ponerPareja(_ pid: String, en fid: String) {
        guard var f = datos.familias[fid], !f.parejas.contains(pid) else { return }
        let sexo = datos.personas[pid]?.sexo ?? .desconocido
        if sexo == .mujer {
            if f.pareja2 == nil { f.pareja2 = pid } else if f.pareja1 == nil { f.pareja1 = pid } else { return }
        } else {
            if f.pareja1 == nil { f.pareja1 = pid } else if f.pareja2 == nil { f.pareja2 = pid } else { return }
        }
        datos.familias[fid] = f
        if datos.personas[pid]?.familiasComoPareja.contains(fid) == false { datos.personas[pid]?.familiasComoPareja.append(fid) }
    }

    /// ¿Se puede añadir esta relación? (p. ej. no si ya tiene padre y madre).
    func puede(_ r: Relacion, a id: String) -> Bool {
        switch r {
        case .padre, .madre:
            guard let f = familiaDePadres(de: id) else { return true }
            let (pa, ma) = padres(de: id)
            if f.parejas.count >= 2 { return false }
            return r == .padre ? pa == nil || pa?.sexo != .hombre : ma == nil || ma?.sexo != .mujer
        default: return true
        }
    }

    /// Añade un familiar nuevo (o vincula uno existente) a la persona `id`.
    @discardableResult
    func agregar(_ r: Relacion, a id: String, nueva: Persona?, existente: String? = nil, familia fid: String? = nil) -> String? {
        let otro: String
        if let existente { otro = existente } else if let nueva { otro = crearPersona(nueva) } else { return nil }
        guard otro != id else { return nil }

        switch r {
        case .padre, .madre:
            if let f = familiaDePadres(de: id) {
                ponerPareja(otro, en: f.id)
            } else {
                let f = crearFamilia()
                ponerPareja(otro, en: f)
                ponerHijo(id, en: f)
            }
        case .pareja:
            // Reutiliza una familia sin pareja si existe (p. ej. hijos ya registrados).
            if let f = familiasComoPareja(de: id).first(where: { $0.parejas.count < 2 }) {
                ponerPareja(otro, en: f.id)
            } else {
                let f = crearFamilia()
                ponerPareja(id, en: f)
                ponerPareja(otro, en: f)
            }
        case .hijo, .hija:
            let destino: String
            if let fid, datos.familias[fid] != nil { destino = fid }
            else if let f = familiasComoPareja(de: id).first { destino = f.id }
            else { let f = crearFamilia(); ponerPareja(id, en: f); destino = f }
            ponerHijo(otro, en: destino)
        case .hermano, .hermana:
            let destino: String
            if let f = familiaDePadres(de: id) { destino = f.id }
            else { let f = crearFamilia(); ponerHijo(id, en: f); destino = f }
            ponerHijo(otro, en: destino)
        }
        cambiado()
        return otro
    }

    /// Quita a la persona de una familia (como hijo o como pareja).
    func desvincular(_ pid: String, de fid: String) {
        guard var f = datos.familias[fid] else { return }
        if f.pareja1 == pid { f.pareja1 = nil }
        if f.pareja2 == pid { f.pareja2 = nil }
        f.hijos.removeAll { $0 == pid }
        f.extraHijos[pid] = nil
        datos.familias[fid] = f
        datos.personas[pid]?.familiasComoHijo.removeAll { $0 == fid }
        datos.personas[pid]?.familiasComoPareja.removeAll { $0 == fid }
        datos.personas[pid]?.extra.removeAll { ($0.tag == "FAMC" || $0.tag == "FAMS") && $0.valor == "@\(fid)@" }
        limpiarFamilia(fid)
        cambiado()
    }

    private func limpiarFamilia(_ fid: String) {
        guard let f = datos.familias[fid] else { return }
        if f.parejas.count + f.hijos.count <= 1 && f.eventos.isEmpty {
            for x in f.parejas + f.hijos {
                datos.personas[x]?.familiasComoHijo.removeAll { $0 == fid }
                datos.personas[x]?.familiasComoPareja.removeAll { $0 == fid }
            }
            datos.familias[fid] = nil
        }
    }

    func eliminar(_ pid: String) {
        guard let p = datos.personas[pid] else { return }
        for fid in p.familiasComoHijo + p.familiasComoPareja {
            guard var f = datos.familias[fid] else { continue }
            if f.pareja1 == pid { f.pareja1 = nil }
            if f.pareja2 == pid { f.pareja2 = nil }
            f.hijos.removeAll { $0 == pid }
            datos.familias[fid] = f
        }
        for m in p.fotos { if let a = m.archivoLocal { try? FileManager.default.removeItem(at: carpetaFotos.appendingPathComponent(a)) } }
        datos.personas[pid] = nil
        for fid in p.familiasComoHijo + p.familiasComoPareja { limpiarFamilia(fid) }
        if datos.raiz == pid { datos.raiz = datos.personas.keys.sorted().first }
        if foco == pid { foco = datos.raiz }
        cambiado()
    }

    // MARK: fotos

    func urlLocal(_ m: Medio) -> URL? {
        m.archivoLocal.map { carpetaFotos.appendingPathComponent($0) }
    }

    func imagen(_ m: Medio) -> UIImage? {
        guard let a = m.archivoLocal else { return nil }
        if let c = cacheImagenes.object(forKey: a as NSString) { return c }
        guard let img = UIImage(contentsOfFile: carpetaFotos.appendingPathComponent(a).path) else { return nil }
        cacheImagenes.setObject(img, forKey: a as NSString)
        return img
    }

    /// Guarda una imagen en la carpeta del árbol y la añade a la persona.
    func agregarFoto(_ data: Data, a pid: String, titulo: String = "") {
        guard let img = UIImage(data: data), let jpg = Self.reducir(img).jpegData(compressionQuality: 0.85) else { return }
        let nombre = UUID().uuidString + ".jpg"
        do { try jpg.write(to: carpetaFotos.appendingPathComponent(nombre)) } catch { return }
        var m = Medio()
        m.archivoLocal = nombre
        m.formato = "jpg"
        m.titulo = titulo
        guard var p = datos.personas[pid] else { return }
        if p.fotos.isEmpty { m.principal = true }
        p.fotos.append(m)
        guardar(p)
    }

    func quitarFoto(_ mid: UUID, de pid: String) {
        guard var p = datos.personas[pid], let i = p.fotos.firstIndex(where: { $0.id == mid }) else { return }
        let m = p.fotos.remove(at: i)
        if let a = m.archivoLocal { try? FileManager.default.removeItem(at: carpetaFotos.appendingPathComponent(a)) }
        if m.principal, !p.fotos.isEmpty { p.fotos[0].principal = true }
        guardar(p)
    }

    func hacerPrincipal(_ mid: UUID, de pid: String) {
        guard var p = datos.personas[pid] else { return }
        for i in p.fotos.indices { p.fotos[i].principal = p.fotos[i].id == mid }
        guardar(p)
    }

    nonisolated static func reducir(_ img: UIImage, maximo: CGFloat = 1800) -> UIImage {
        let lado = max(img.size.width, img.size.height)
        guard lado > maximo else { return img }
        let f = maximo / lado
        let tam = CGSize(width: img.size.width * f, height: img.size.height * f)
        let r = UIGraphicsImageRenderer(size: tam)
        return r.image { _ in img.draw(in: CGRect(origin: .zero, size: tam)) }
    }

    var fotosRemotasPendientes: Int {
        datos.personas.values.reduce(0) { $0 + $1.fotos.filter { $0.archivoLocal == nil && $0.urlRemota != nil }.count }
    }

    /// Descarga las fotos con URL (p. ej. de MyHeritage) para tenerlas sin conexión.
    func descargarFotosRemotas(progreso: @escaping (Int, Int) -> Void) async -> Int {
        var pendientes: [(String, UUID, URL)] = []
        for p in datos.personas.values {
            for m in p.fotos where m.archivoLocal == nil { if let u = m.urlRemota { pendientes.append((p.id, m.id, u)) } }
        }
        var hechas = 0
        for (i, (pid, mid, url)) in pendientes.enumerated() {
            progreso(i, pendientes.count)
            guard let r = try? await URLSession.shared.data(from: url),
                  ((r.1 as? HTTPURLResponse)?.statusCode ?? 200) < 400,
                  let img = UIImage(data: r.0) else { continue }
            let nombre = UUID().uuidString + ".jpg"
            guard let jpg = Self.reducir(img).jpegData(compressionQuality: 0.85),
                  (try? jpg.write(to: carpetaFotos.appendingPathComponent(nombre))) != nil else { continue }
            if let j = datos.personas[pid]?.fotos.firstIndex(where: { $0.id == mid }) {
                datos.personas[pid]?.fotos[j].archivoLocal = nombre
                hechas += 1
            }
        }
        progreso(pendientes.count, pendientes.count)
        cambiado()
        return hechas
    }

    /// Asocia las imágenes de un ZIP importado con los OBJE FILE del GEDCOM.
    func integrarFotosDeZip(_ archivos: [Zip.Entrada]) -> Int {
        var porNombre: [String: Zip.Entrada] = [:]
        for a in archivos {
            porNombre[a.nombre.lowercased()] = a
            porNombre[(a.nombre as NSString).lastPathComponent.lowercased()] = a
        }
        var n = 0
        for (pid, p) in datos.personas {
            for (j, m) in p.fotos.enumerated() where m.archivoLocal == nil {
                let ref = m.referencia.replacingOccurrences(of: "\\", with: "/")
                let clave = ref.lowercased()
                guard let e = porNombre[clave] ?? porNombre[(ref as NSString).lastPathComponent.lowercased()] else { continue }
                let ext = (e.nombre as NSString).pathExtension.lowercased()
                let nombre = UUID().uuidString + "." + (ext.isEmpty ? "jpg" : ext)
                guard (try? e.datos.write(to: carpetaFotos.appendingPathComponent(nombre))) != nil else { continue }
                datos.personas[pid]?.fotos[j].archivoLocal = nombre
                n += 1
            }
        }
        return n
    }

    // MARK: exportar

    func archivoGedcom() throws -> URL {
        let texto = ExportadorGedcom.exportar(datos)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(ExportadorGedcom.nombreArchivo(datos.nombre))
        try Data(texto.utf8).write(to: url, options: .atomic)
        return url
    }

    /// ZIP con el .ged y las fotos guardadas en el teléfono (carpeta fotos/).
    func archivoZip() throws -> URL {
        var copia = datos
        // En el ZIP, las fotos locales se referencian por su ruta relativa.
        for (pid, p) in copia.personas {
            for (j, m) in p.fotos.enumerated() where m.archivoLocal != nil {
                if m.urlRemota != nil {
                    copia.personas[pid]?.fotos[j].extra.append(NodoGedcom(tag: "_URL", valor: m.referencia))
                }
                copia.personas[pid]?.fotos[j].referencia = "fotos/\(m.archivoLocal!)"
            }
        }
        let nombreGed = ExportadorGedcom.nombreArchivo(datos.nombre)
        var entradas = [Zip.Entrada(nombre: nombreGed, datos: Data(ExportadorGedcom.exportar(copia).utf8))]
        for p in datos.personas.values {
            for m in p.fotos {
                if let a = m.archivoLocal, let d = try? Data(contentsOf: carpetaFotos.appendingPathComponent(a)) {
                    entradas.append(Zip.Entrada(nombre: "fotos/\(a)", datos: d))
                }
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent((nombreGed as NSString).deletingPathExtension + ".zip")
        try Zip.crear(entradas).write(to: url, options: .atomic)
        return url
    }
}
