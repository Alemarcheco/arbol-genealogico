import Foundation

/// Nodo GEDCOM genérico. Se usa para leer/escribir el archivo y para conservar
/// etiquetas que la app no entiende (p. ej. las propias de MyHeritage como
/// _UPD, _UID, RIN, _PHOTO_RIN...), de modo que al exportar no se pierdan.
struct NodoGedcom: Codable, Hashable {
    var tag: String
    var valor: String = ""
    var xref: String? = nil
    var hijos: [NodoGedcom] = []

    func primero(_ t: String) -> NodoGedcom? { hijos.first { $0.tag == t } }
    func valorDe(_ t: String) -> String? { primero(t)?.valor }
    func todos(_ t: String) -> [NodoGedcom] { hijos.filter { $0.tag == t } }
}

enum Sexo: String, Codable, CaseIterable, Identifiable {
    case hombre = "M", mujer = "F", desconocido = "U"
    var id: String { rawValue }
    var nombre: String {
        switch self {
        case .hombre: return "Hombre"
        case .mujer: return "Mujer"
        case .desconocido: return "Desconocido"
        }
    }
}

struct Evento: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Etiqueta GEDCOM: BIRT, DEAT, MARR, OCCU, RESI, EVEN...
    var tipo: String
    /// Valor del evento (p. ej. el texto de OCCU "Ingeniero").
    var valor: String = ""
    /// Subtipo (TYPE), usado sobre todo con EVEN / FACT.
    var subtipo: String = ""
    /// Fecha en formato GEDCOM ("12 MAR 1950", "ABT 1900", "BET 1900 AND 1910").
    var fecha: String = ""
    var lugar: String = ""
    var notas: String = ""
    /// Subnodos no reconocidos (fuentes, coordenadas, etiquetas propias...).
    var extra: [NodoGedcom] = []

    var info: TipoEvento { TipoEvento.de(tipo) }
    var titulo: String {
        if (tipo == "EVEN" || tipo == "FACT"), !subtipo.isEmpty { return subtipo }
        return info.nombre
    }
}

struct Medio: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Nombre de archivo local dentro de la carpeta "fotos" del árbol.
    var archivoLocal: String? = nil
    /// Ruta o URL original del GEDCOM (MyHeritage exporta URLs de sus servidores).
    var referencia: String = ""
    var formato: String = ""
    var titulo: String = ""
    var fecha: String = ""
    var principal: Bool = false
    var extra: [NodoGedcom] = []

    var urlRemota: URL? {
        guard referencia.lowercased().hasPrefix("http") else { return nil }
        return URL(string: referencia)
    }
}

struct Persona: Identifiable, Codable, Hashable {
    var id: String
    var nombre: String = ""
    var apellido: String = ""
    var apellidoCasada: String = ""
    var apodo: String = ""
    var prefijo: String = ""
    var sufijo: String = ""
    var sexo: Sexo = .desconocido
    var eventos: [Evento] = []
    var notas: String = ""
    var fotos: [Medio] = []
    var familiasComoHijo: [String] = []
    var familiasComoPareja: [String] = []
    var correo: String = ""
    /// Nodos no reconocidos (se reescriben tal cual al exportar).
    var extra: [NodoGedcom] = []
    /// Nodos extra dentro de NAME.
    var extraNombre: [NodoGedcom] = []
    /// Nombres alternativos (otros NAME).
    var otrosNombres: [NodoGedcom] = []
    var modificado: Date = Date()

    var nombreCompleto: String {
        let n = [prefijo, nombre, apellido, sufijo].filter { !$0.isEmpty }.joined(separator: " ")
        return n.isEmpty ? "Sin nombre" : n
    }
    var nombreCorto: String {
        let n = [nombre.split(separator: " ").first.map(String.init) ?? "", apellido]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return n.isEmpty ? "Sin nombre" : n
    }
    var iniciales: String {
        let a = nombre.first.map { String($0) } ?? ""
        let b = apellido.first.map { String($0) } ?? ""
        let r = (a + b).uppercased()
        return r.isEmpty ? "?" : r
    }

    func evento(_ tipos: String...) -> Evento? {
        for t in tipos { if let e = eventos.first(where: { $0.tipo == t }) { return e } }
        return nil
    }
    var nacimiento: Evento? { evento("BIRT", "CHR", "BAPM") }
    var defuncion: Evento? { evento("DEAT", "BURI", "CREM") }
    var fallecido: Bool { eventos.contains { ["DEAT", "BURI", "CREM"].contains($0.tipo) } }
    var anioNacimiento: Int? { nacimiento.flatMap { FechaGedcom.anio($0.fecha) } }
    var anioDefuncion: Int? { defuncion.flatMap { FechaGedcom.anio($0.fecha) } }

    /// "1920 – 1998", "n. 1950", etc.
    var rangoVida: String {
        let n = anioNacimiento.map(String.init)
        let d = anioDefuncion.map(String.init)
        switch (n, d) {
        case let (n?, d?): return "\(n) – \(d)"
        case let (n?, nil): return fallecido ? "\(n) – †" : "n. \(n)"
        case let (nil, d?): return "† \(d)"
        default: return fallecido ? "Fallecido/a" : ""
        }
    }

    var fotoPrincipal: Medio? { fotos.first(where: { $0.principal }) ?? fotos.first }

    var textoBusqueda: String {
        var t = [nombre, apellido, apellidoCasada, apodo].joined(separator: " ")
        for e in eventos { t += " " + e.lugar + " " + e.valor }
        return t.sinAcentos
    }
}

struct Familia: Identifiable, Codable, Hashable {
    var id: String
    /// HUSB en GEDCOM
    var pareja1: String? = nil
    /// WIFE en GEDCOM
    var pareja2: String? = nil
    var hijos: [String] = []
    var eventos: [Evento] = []
    var notas: String = ""
    var extra: [NodoGedcom] = []
    /// Nodos extra junto a cada CHIL (p. ej. _FREL/_MREL adopción), por id de hijo.
    var extraHijos: [String: [NodoGedcom]] = [:]

    var parejas: [String] { [pareja1, pareja2].compactMap { $0 } }
    func otro(de id: String) -> String? {
        if pareja1 == id { return pareja2 }
        if pareja2 == id { return pareja1 }
        return nil
    }
    var divorciados: Bool { eventos.contains { $0.tipo == "DIV" } }
}

struct DatosArbol: Codable {
    var id = UUID()
    var nombre: String
    var personas: [String: Persona] = [:]
    var familias: [String: Familia] = [:]
    /// Persona raíz / "yo".
    var raiz: String? = nil
    /// Registros de nivel 0 no gestionados (SOUR, REPO, NOTE, OBJE, _ALBUM...).
    var otrosRegistros: [NodoGedcom] = []
    /// Origen del archivo importado (MYHERITAGE, FTM, etc.).
    var origen: String = ""
    var creado = Date()
    var modificado = Date()
    var siguienteNumero = 1
}

struct TipoEvento: Identifiable, Hashable {
    let tag: String
    let nombre: String
    let icono: String
    let deFamilia: Bool
    let conValor: Bool
    var id: String { tag }

    static let individuales: [TipoEvento] = [
        .init(tag: "BIRT", nombre: "Nacimiento", icono: "sparkles", deFamilia: false, conValor: false),
        .init(tag: "CHR", nombre: "Bautizo", icono: "drop", deFamilia: false, conValor: false),
        .init(tag: "BAPM", nombre: "Bautismo", icono: "drop.fill", deFamilia: false, conValor: false),
        .init(tag: "CONF", nombre: "Confirmación", icono: "hands.sparkles", deFamilia: false, conValor: false),
        .init(tag: "FCOM", nombre: "Primera comunión", icono: "hands.sparkles", deFamilia: false, conValor: false),
        .init(tag: "BARM", nombre: "Bar mitzvá", icono: "star", deFamilia: false, conValor: false),
        .init(tag: "BASM", nombre: "Bat mitzvá", icono: "star", deFamilia: false, conValor: false),
        .init(tag: "EDUC", nombre: "Estudios", icono: "graduationcap", deFamilia: false, conValor: true),
        .init(tag: "GRAD", nombre: "Graduación", icono: "graduationcap.fill", deFamilia: false, conValor: false),
        .init(tag: "OCCU", nombre: "Ocupación", icono: "briefcase", deFamilia: false, conValor: true),
        .init(tag: "RESI", nombre: "Residencia", icono: "house", deFamilia: false, conValor: false),
        .init(tag: "EMIG", nombre: "Emigración", icono: "airplane.departure", deFamilia: false, conValor: false),
        .init(tag: "IMMI", nombre: "Inmigración", icono: "airplane.arrival", deFamilia: false, conValor: false),
        .init(tag: "NATU", nombre: "Naturalización", icono: "flag", deFamilia: false, conValor: false),
        .init(tag: "CENS", nombre: "Censo", icono: "list.clipboard", deFamilia: false, conValor: false),
        .init(tag: "MILI", nombre: "Servicio militar", icono: "shield", deFamilia: false, conValor: false),
        .init(tag: "RELI", nombre: "Religión", icono: "book.closed", deFamilia: false, conValor: true),
        .init(tag: "NATI", nombre: "Nacionalidad", icono: "globe", deFamilia: false, conValor: true),
        .init(tag: "DSCR", nombre: "Descripción física", icono: "person.text.rectangle", deFamilia: false, conValor: true),
        .init(tag: "RETI", nombre: "Jubilación", icono: "sun.max", deFamilia: false, conValor: false),
        .init(tag: "WILL", nombre: "Testamento", icono: "doc.text", deFamilia: false, conValor: false),
        .init(tag: "DEAT", nombre: "Defunción", icono: "leaf", deFamilia: false, conValor: false),
        .init(tag: "BURI", nombre: "Entierro", icono: "mountain.2", deFamilia: false, conValor: false),
        .init(tag: "CREM", nombre: "Cremación", icono: "flame", deFamilia: false, conValor: false),
        .init(tag: "EVEN", nombre: "Otro evento", icono: "calendar", deFamilia: false, conValor: false),
    ]
    static let familiares: [TipoEvento] = [
        .init(tag: "ENGA", nombre: "Compromiso", icono: "heart", deFamilia: true, conValor: false),
        .init(tag: "MARR", nombre: "Matrimonio", icono: "heart.fill", deFamilia: true, conValor: false),
        .init(tag: "DIV", nombre: "Divorcio", icono: "heart.slash", deFamilia: true, conValor: false),
        .init(tag: "ANUL", nombre: "Anulación", icono: "heart.slash", deFamilia: true, conValor: false),
        .init(tag: "MARS", nombre: "Capitulaciones", icono: "doc.text", deFamilia: true, conValor: false),
        .init(tag: "EVEN", nombre: "Otro evento", icono: "calendar", deFamilia: true, conValor: false),
    ]
    static let otros: [TipoEvento] = [
        .init(tag: "FACT", nombre: "Dato", icono: "info.circle", deFamilia: false, conValor: true),
        .init(tag: "TITL", nombre: "Título", icono: "crown", deFamilia: false, conValor: true),
        .init(tag: "SSN", nombre: "Documento de identidad", icono: "person.text.rectangle", deFamilia: false, conValor: true),
        .init(tag: "IDNO", nombre: "Número de identificación", icono: "number", deFamilia: false, conValor: true),
        .init(tag: "PROP", nombre: "Propiedades", icono: "building.2", deFamilia: false, conValor: true),
        .init(tag: "ADOP", nombre: "Adopción", icono: "figure.and.child.holdinghands", deFamilia: false, conValor: false),
        .init(tag: "PROB", nombre: "Sucesión", icono: "doc.text", deFamilia: false, conValor: false),
        .init(tag: "ORDN", nombre: "Ordenación", icono: "book", deFamilia: false, conValor: false),
        .init(tag: "_MILT", nombre: "Servicio militar", icono: "shield", deFamilia: false, conValor: false),
        .init(tag: "_DEG", nombre: "Título académico", icono: "graduationcap", deFamilia: false, conValor: true),
        .init(tag: "_ELEC", nombre: "Elección", icono: "checkmark.seal", deFamilia: false, conValor: false),
        .init(tag: "_EMPLOY", nombre: "Empleo", icono: "briefcase", deFamilia: false, conValor: true),
        .init(tag: "_MDCL", nombre: "Información médica", icono: "cross.case", deFamilia: false, conValor: true),
        .init(tag: "_HEIG", nombre: "Estatura", icono: "ruler", deFamilia: false, conValor: true),
        .init(tag: "_WEIG", nombre: "Peso", icono: "scalemass", deFamilia: false, conValor: true),
    ]

    static let todasLasEtiquetas: Set<String> = Set((individuales + familiares + otros).map { $0.tag })

    static func de(_ tag: String) -> TipoEvento {
        (individuales + familiares + otros).first { $0.tag == tag }
            ?? .init(tag: tag, nombre: tag, icono: "calendar", deFamilia: false, conValor: true)
    }

    /// Orden para la línea de vida.
    static func orden(_ tag: String) -> Int {
        switch tag {
        case "BIRT": return 0
        case "CHR", "BAPM": return 1
        case "DEAT": return 90
        case "BURI", "CREM": return 91
        case "PROB", "WILL": return 92
        default: return 50
        }
    }
}

extension String {
    var sinAcentos: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
    }
    var recortado: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
