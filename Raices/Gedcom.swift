import Foundation

// MARK: - Lectura de texto GEDCOM a nodos

enum LectorGedcom {
    private final class Constructor {
        var tag: String
        var valor: String
        var xref: String?
        var hijos: [Constructor] = []
        init(tag: String, valor: String, xref: String?) { self.tag = tag; self.valor = valor; self.xref = xref }
        func nodo() -> NodoGedcom { NodoGedcom(tag: tag, valor: valor, xref: xref, hijos: hijos.map { $0.nodo() }) }
    }

    /// Decodifica los bytes probando UTF-8, UTF-16 y Windows-1252.
    static func texto(de datos: Data) -> String {
        let b = [UInt8](datos.prefix(3))
        if b.count >= 2, (b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF) {
            if let s = String(data: datos, encoding: .utf16) { return s }
        }
        if b.count == 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF {
            if let s = String(data: datos.dropFirst(3), encoding: .utf8) { return s }
        }
        if let s = String(data: datos, encoding: .utf8) { return s }
        if let s = String(data: datos, encoding: .windowsCP1252) { return s }
        return String(decoding: datos, as: UTF8.self)
    }

    static func leer(_ texto: String) -> [NodoGedcom] {
        var raices: [Constructor] = []
        var pila: [(nivel: Int, nodo: Constructor)] = []

        let lineas = texto.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" })
        for lineaSub in lineas {
            var linea = lineaSub
            while let f = linea.first, f == " " || f == "\t" || f == "\u{FEFF}" { linea = linea.dropFirst() }
            if linea.isEmpty { continue }

            // nivel
            guard let espacio = linea.firstIndex(of: " "), let nivel = Int(linea[..<espacio]) else { continue }
            var resto = linea[linea.index(after: espacio)...]
            while resto.first == " " { resto = resto.dropFirst() }

            var xref: String? = nil
            if resto.first == "@" {
                if let fin = resto.dropFirst().firstIndex(of: "@") {
                    xref = String(resto[resto.index(after: resto.startIndex)..<fin])
                    resto = resto[resto.index(after: fin)...]
                    while resto.first == " " { resto = resto.dropFirst() }
                }
            }
            let tag: String
            var valor = ""
            if let e = resto.firstIndex(of: " ") {
                tag = String(resto[..<e]).uppercased()
                valor = String(resto[resto.index(after: e)...])
            } else {
                tag = String(resto).uppercased()
            }
            if valor.contains("@@") { valor = valor.replacingOccurrences(of: "@@", with: "@") }

            while let ultimo = pila.last, ultimo.nivel >= nivel { pila.removeLast() }

            if tag == "CONC" || tag == "CONT", let padre = pila.last {
                padre.nodo.valor += (tag == "CONT" ? "\n" : "") + valor
                continue
            }
            let nodo = Constructor(tag: tag, valor: valor, xref: xref)
            if let padre = pila.last { padre.nodo.hijos.append(nodo) } else { raices.append(nodo) }
            pila.append((nivel, nodo))
        }
        return raices.map { $0.nodo() }
    }
}

// MARK: - Escritura de nodos a texto GEDCOM

enum EscritorGedcom {
    static let maximo = 200

    static func escribir(_ nodos: [NodoGedcom]) -> String {
        var s = ""
        s.reserveCapacity(nodos.count * 200)
        for n in nodos { escribir(n, nivel: 0, en: &s) }
        return s
    }

    static func escribir(_ n: NodoGedcom, nivel: Int, en s: inout String) {
        let partes = n.valor.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var cabecera = "\(nivel)"
        if let x = n.xref { cabecera += " @\(x)@" }
        cabecera += " \(n.tag)"
        for (i, parte) in partes.enumerated() {
            let trozos = cortar(parte)
            for (j, trozo) in trozos.enumerated() {
                if i == 0 && j == 0 {
                    s += cabecera + (trozo.isEmpty ? "" : " " + trozo) + "\r\n"
                } else {
                    let etiqueta = j == 0 ? "CONT" : "CONC"
                    s += "\(nivel + 1) \(etiqueta)" + (trozo.isEmpty ? "" : " " + trozo) + "\r\n"
                }
            }
        }
        for h in n.hijos { escribir(h, nivel: nivel + 1, en: &s) }
    }

    /// Divide un texto largo en trozos para CONC sin cortar junto a un espacio.
    private static func cortar(_ texto: String) -> [String] {
        let c = Array(texto)
        if c.count <= maximo { return [texto] }
        var res: [String] = []
        var inicio = 0
        while c.count - inicio > maximo {
            var corte = inicio + maximo
            while corte > inicio + 20, c[corte] == " " || c[corte - 1] == " " { corte -= 1 }
            res.append(String(c[inicio..<corte]))
            inicio = corte
        }
        res.append(String(c[inicio...]))
        return res
    }
}

// MARK: - Importar GEDCOM a un árbol

enum ImportadorGedcom {
    struct Resultado {
        var datos: DatosArbol
        var personas: Int
        var familias: Int
        var fotos: Int
    }

    enum Fallo: LocalizedError {
        case vacio
        var errorDescription: String? { "El archivo no parece un GEDCOM válido (no tiene personas)." }
    }

    static let etiquetasEventoPersona: Set<String> = Set((TipoEvento.individuales + TipoEvento.otros).map { $0.tag })
    static let etiquetasEventoFamilia: Set<String> = Set(TipoEvento.familiares.map { $0.tag })

    static func importar(datos: Data, nombre: String) throws -> Resultado {
        let nodos = LectorGedcom.leer(LectorGedcom.texto(de: datos))
        var arbol = DatosArbol(nombre: nombre)
        var fotos = 0

        // Cuenta de referencias a cada xref (para decidir si un OBJE de nivel 0 se puede integrar).
        var referencias: [String: Int] = [:]
        func contar(_ n: NodoGedcom) {
            if n.valor.hasPrefix("@"), n.valor.hasSuffix("@"), n.valor.count > 2 {
                referencias[String(n.valor.dropFirst().dropLast()), default: 0] += 1
            }
            n.hijos.forEach(contar)
        }
        nodos.forEach(contar)

        var objetos: [String: NodoGedcom] = [:]
        for n in nodos where n.tag == "OBJE" { if let x = n.xref { objetos[x] = n } }
        var objetosIntegrados: [String: Int] = [:]

        func medio(de n: NodoGedcom) -> Medio {
            var m = Medio()
            for h in n.hijos {
                switch h.tag {
                case "FILE":
                    if m.referencia.isEmpty {
                        m.referencia = h.valor
                        for f in h.hijos {
                            switch f.tag {
                            case "FORM": m.formato = f.valor
                            case "TITL": m.titulo = f.valor
                            default: m.extra.append(f)
                            }
                        }
                    } else { m.extra.append(h) }
                case "FORM": m.formato = h.valor
                case "TITL": m.titulo = h.valor
                case "_PRIM": m.principal = h.valor.uppercased().hasPrefix("Y")
                case "_DATE", "DATE": m.fecha = h.valor
                default: m.extra.append(h)
                }
            }
            return m
        }

        func medioDesdeNodo(_ h: NodoGedcom) -> Medio? {
            if h.valor.hasPrefix("@"), h.valor.hasSuffix("@") {
                let x = String(h.valor.dropFirst().dropLast())
                guard let reg = objetos[x] else { return nil }
                objetosIntegrados[x, default: 0] += 1
                var m = medio(de: reg)
                // Subnodos de la cita (p. ej. _PRIM en la referencia)
                for s in h.hijos where s.tag == "_PRIM" { m.principal = s.valor.uppercased().hasPrefix("Y") }
                return m
            }
            return medio(de: h)
        }

        func evento(de n: NodoGedcom) -> Evento {
            var e = Evento(tipo: n.tag)
            e.valor = n.valor.uppercased() == "Y" ? "" : n.valor
            for h in n.hijos {
                switch h.tag {
                case "TYPE": e.subtipo = h.valor
                case "DATE":
                    e.fecha = h.valor
                    if !h.hijos.isEmpty { e.extra.append(h) }
                case "PLAC":
                    e.lugar = h.valor
                    if !h.hijos.isEmpty { e.extra.append(h) }
                case "NOTE" where !h.valor.hasPrefix("@"):
                    e.notas += (e.notas.isEmpty ? "" : "\n\n") + h.valor
                default: e.extra.append(h)
                }
            }
            return e
        }

        func xref(_ v: String) -> String? {
            let t = v.recortado
            guard t.hasPrefix("@"), t.hasSuffix("@"), t.count > 2 else { return nil }
            return String(t.dropFirst().dropLast())
        }

        for n in nodos {
            switch n.tag {
            case "HEAD":
                arbol.origen = n.valorDe("SOUR") ?? ""
            case "TRLR":
                break
            case "INDI":
                guard let id = n.xref else { continue }
                var p = Persona(id: id)
                var tieneNombre = false
                for h in n.hijos {
                    switch h.tag {
                    case "NAME":
                        if tieneNombre { p.otrosNombres.append(h); continue }
                        tieneNombre = true
                        leerNombre(h, en: &p)
                    case "SEX":
                        p.sexo = Sexo(rawValue: String(h.valor.uppercased().prefix(1))) ?? .desconocido
                    case "FAMC":
                        if let f = xref(h.valor) {
                            if !p.familiasComoHijo.contains(f) { p.familiasComoHijo.append(f) }
                            if !h.hijos.isEmpty { p.extra.append(h) }
                        }
                    case "FAMS":
                        if let f = xref(h.valor) {
                            if !p.familiasComoPareja.contains(f) { p.familiasComoPareja.append(f) }
                            if !h.hijos.isEmpty { p.extra.append(h) }
                        }
                    case "OBJE":
                        if let m = medioDesdeNodo(h) { p.fotos.append(m); fotos += 1 } else { p.extra.append(h) }
                    case "NOTE" where !h.valor.hasPrefix("@"):
                        p.notas += (p.notas.isEmpty ? "" : "\n\n") + h.valor
                    case "EMAIL" where p.correo.isEmpty:
                        p.correo = h.valor
                    default:
                        if etiquetasEventoPersona.contains(h.tag) { p.eventos.append(evento(de: h)) }
                        else { p.extra.append(h) }
                    }
                }
                arbol.personas[id] = p
            case "FAM":
                guard let id = n.xref else { continue }
                var f = Familia(id: id)
                for h in n.hijos {
                    switch h.tag {
                    case "HUSB": f.pareja1 = xref(h.valor); if !h.hijos.isEmpty { f.extra.append(h) }
                    case "WIFE": f.pareja2 = xref(h.valor); if !h.hijos.isEmpty { f.extra.append(h) }
                    case "CHIL":
                        if let c = xref(h.valor) {
                            if !f.hijos.contains(c) { f.hijos.append(c) }
                            if !h.hijos.isEmpty { f.extraHijos[c] = h.hijos }
                        }
                    case "NOTE" where !h.valor.hasPrefix("@"):
                        f.notas += (f.notas.isEmpty ? "" : "\n\n") + h.valor
                    default:
                        if etiquetasEventoFamilia.contains(h.tag) { f.eventos.append(evento(de: h)) }
                        else { f.extra.append(h) }
                    }
                }
                arbol.familias[id] = f
            default:
                arbol.otrosRegistros.append(n)
            }
        }

        // Quitar OBJE de nivel 0 que ya quedaron integrados en las personas.
        arbol.otrosRegistros.removeAll { r in
            guard r.tag == "OBJE", let x = r.xref else { return false }
            return (objetosIntegrados[x] ?? 0) >= (referencias[x] ?? 0)
        }

        reparar(&arbol)
        guard !arbol.personas.isEmpty else { throw Fallo.vacio }
        arbol.raiz = elegirRaiz(arbol)
        return Resultado(datos: arbol, personas: arbol.personas.count, familias: arbol.familias.count, fotos: fotos)
    }

    static func leerNombre(_ h: NodoGedcom, en p: inout Persona) {
        // "Juan Carlos /Pérez García/ Jr."
        let v = h.valor
        if let a = v.firstIndex(of: "/") {
            p.nombre = String(v[..<a]).recortado
            let tras = v[v.index(after: a)...]
            if let b = tras.firstIndex(of: "/") {
                p.apellido = String(tras[..<b]).recortado
                p.sufijo = String(tras[tras.index(after: b)...]).recortado
            } else {
                p.apellido = String(tras).recortado
            }
        } else {
            p.nombre = v.recortado
        }
        for s in h.hijos {
            switch s.tag {
            case "GIVN": if !s.valor.isEmpty { p.nombre = s.valor }
            case "SURN": if !s.valor.isEmpty { p.apellido = s.valor }
            case "NPFX": p.prefijo = s.valor
            case "NSFX": p.sufijo = s.valor
            case "NICK": p.apodo = s.valor
            case "_MARNM", "_MARN": p.apellidoCasada = s.valor
            default: p.extraNombre.append(s)
            }
        }
    }

    /// Garantiza que los vínculos persona↔familia estén en ambos sentidos.
    static func reparar(_ a: inout DatosArbol) {
        for (fid, f) in a.familias {
            for c in f.hijos where a.personas[c] != nil {
                if !(a.personas[c]!.familiasComoHijo.contains(fid)) { a.personas[c]!.familiasComoHijo.append(fid) }
            }
            for p in f.parejas where a.personas[p] != nil {
                if !(a.personas[p]!.familiasComoPareja.contains(fid)) { a.personas[p]!.familiasComoPareja.append(fid) }
            }
        }
        for (pid, p) in a.personas {
            for fid in p.familiasComoHijo {
                if a.familias[fid] == nil { a.personas[pid]!.familiasComoHijo.removeAll { $0 == fid }; continue }
                if !a.familias[fid]!.hijos.contains(pid) { a.familias[fid]!.hijos.append(pid) }
            }
            for fid in p.familiasComoPareja {
                guard let f = a.familias[fid] else { a.personas[pid]!.familiasComoPareja.removeAll { $0 == fid }; continue }
                if !f.parejas.contains(pid) {
                    if f.pareja1 == nil && p.sexo != .mujer { a.familias[fid]!.pareja1 = pid }
                    else if f.pareja2 == nil { a.familias[fid]!.pareja2 = pid }
                    else if f.pareja1 == nil { a.familias[fid]!.pareja1 = pid }
                }
            }
        }
        // Quitar referencias a personas inexistentes.
        for (fid, f) in a.familias {
            if let x = f.pareja1, a.personas[x] == nil { a.familias[fid]!.pareja1 = nil }
            if let x = f.pareja2, a.personas[x] == nil { a.familias[fid]!.pareja2 = nil }
            a.familias[fid]!.hijos.removeAll { a.personas[$0] == nil }
        }
        let numeros = (Array(a.personas.keys) + Array(a.familias.keys)).compactMap { Int($0.filter(\.isNumber)) }
        a.siguienteNumero = (numeros.max() ?? 0) + 1
    }

    /// MyHeritage suele poner al dueño del árbol como I1 / I500001.
    static func elegirRaiz(_ a: DatosArbol) -> String? {
        let ids = a.personas.keys.sorted { (Int($0.filter(\.isNumber)) ?? .max) < (Int($1.filter(\.isNumber)) ?? .max) }
        return ids.first
    }
}

// MARK: - Exportar árbol a GEDCOM

enum ExportadorGedcom {
    static func exportar(_ a: DatosArbol) -> String {
        var nodos: [NodoGedcom] = []
        let subm = a.otrosRegistros.first { $0.tag == "SUBM" }?.xref ?? "SUBM1"

        var cab = NodoGedcom(tag: "HEAD")
        cab.hijos = [
            NodoGedcom(tag: "SOUR", valor: "RAICES", hijos: [
                NodoGedcom(tag: "NAME", valor: "Raíces"),
                NodoGedcom(tag: "VERS", valor: "1.0"),
            ]),
            NodoGedcom(tag: "DATE", valor: FechaGedcom.hoyGedcom()),
            NodoGedcom(tag: "SUBM", valor: "@\(subm)@"),
            NodoGedcom(tag: "FILE", valor: nombreArchivo(a.nombre)),
            NodoGedcom(tag: "GEDC", hijos: [
                NodoGedcom(tag: "VERS", valor: "5.5.1"),
                NodoGedcom(tag: "FORM", valor: "LINEAGE-LINKED"),
            ]),
            NodoGedcom(tag: "CHAR", valor: "UTF-8"),
            NodoGedcom(tag: "LANG", valor: "Spanish"),
        ]
        nodos.append(cab)

        func orden(_ x: String, _ y: String) -> Bool {
            let a = Int(x.filter(\.isNumber)) ?? 0, b = Int(y.filter(\.isNumber)) ?? 0
            return a == b ? x < y : a < b
        }

        for id in a.personas.keys.sorted(by: orden) {
            nodos.append(nodo(persona: a.personas[id]!))
        }
        for id in a.familias.keys.sorted(by: orden) {
            nodos.append(nodo(familia: a.familias[id]!))
        }
        if !a.otrosRegistros.contains(where: { $0.tag == "SUBM" }) {
            nodos.append(NodoGedcom(tag: "SUBM", xref: subm, hijos: [NodoGedcom(tag: "NAME", valor: "Raíces")]))
        }
        nodos.append(contentsOf: a.otrosRegistros)
        nodos.append(NodoGedcom(tag: "TRLR"))
        return EscritorGedcom.escribir(nodos)
    }

    static func nombreArchivo(_ nombre: String) -> String {
        let limpio = nombre.sinAcentos.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return (limpio.isEmpty ? "arbol" : limpio) + ".ged"
    }

    static func nodo(evento e: Evento) -> NodoGedcom {
        var n = NodoGedcom(tag: e.tipo, valor: e.valor)
        if !e.subtipo.isEmpty { n.hijos.append(NodoGedcom(tag: "TYPE", valor: e.subtipo)) }
        let fechaExtra = e.extra.contains { $0.tag == "DATE" }
        let lugarExtra = e.extra.contains { $0.tag == "PLAC" }
        if !e.fecha.isEmpty && !fechaExtra { n.hijos.append(NodoGedcom(tag: "DATE", valor: e.fecha)) }
        if !e.lugar.isEmpty && !lugarExtra { n.hijos.append(NodoGedcom(tag: "PLAC", valor: e.lugar)) }
        for var x in e.extra {
            if x.tag == "DATE" { if e.fecha.isEmpty { continue }; x.valor = e.fecha }
            if x.tag == "PLAC" { if e.lugar.isEmpty { continue }; x.valor = e.lugar }
            n.hijos.append(x)
        }
        if !e.notas.isEmpty { n.hijos.append(NodoGedcom(tag: "NOTE", valor: e.notas)) }
        if n.valor.isEmpty && n.hijos.isEmpty { n.valor = "Y" }
        return n
    }

    static func nodo(medio m: Medio) -> NodoGedcom {
        var n = NodoGedcom(tag: "OBJE")
        var archivo = NodoGedcom(tag: "FILE", valor: m.archivoLocal.map { "fotos/\($0)" } ?? m.referencia)
        if m.archivoLocal != nil, !m.referencia.isEmpty, m.referencia.lowercased().hasPrefix("http") {
            archivo.valor = m.referencia // se conserva la URL original de MyHeritage
        }
        let formato = m.formato.isEmpty ? (archivo.valor as NSString).pathExtension.lowercased() : m.formato
        if !formato.isEmpty { archivo.hijos.append(NodoGedcom(tag: "FORM", valor: formato)) }
        n.hijos.append(archivo)
        if !m.titulo.isEmpty { n.hijos.append(NodoGedcom(tag: "TITL", valor: m.titulo)) }
        if !m.fecha.isEmpty { n.hijos.append(NodoGedcom(tag: "_DATE", valor: m.fecha)) }
        n.hijos.append(contentsOf: m.extra)
        if m.principal { n.hijos.append(NodoGedcom(tag: "_PRIM", valor: "Y")) }
        return n
    }

    static func nodo(persona p: Persona) -> NodoGedcom {
        var n = NodoGedcom(tag: "INDI", xref: p.id)
        let apellidoNAME = p.apellido.isEmpty ? "" : "/\(p.apellido)/"
        var nom = NodoGedcom(tag: "NAME", valor: [p.nombre, apellidoNAME, p.sufijo].filter { !$0.isEmpty }.joined(separator: " "))
        if !p.prefijo.isEmpty { nom.hijos.append(NodoGedcom(tag: "NPFX", valor: p.prefijo)) }
        if !p.nombre.isEmpty { nom.hijos.append(NodoGedcom(tag: "GIVN", valor: p.nombre)) }
        if !p.apellido.isEmpty { nom.hijos.append(NodoGedcom(tag: "SURN", valor: p.apellido)) }
        if !p.sufijo.isEmpty { nom.hijos.append(NodoGedcom(tag: "NSFX", valor: p.sufijo)) }
        if !p.apodo.isEmpty { nom.hijos.append(NodoGedcom(tag: "NICK", valor: p.apodo)) }
        if !p.apellidoCasada.isEmpty { nom.hijos.append(NodoGedcom(tag: "_MARNM", valor: p.apellidoCasada)) }
        nom.hijos.append(contentsOf: p.extraNombre)
        n.hijos.append(nom)
        n.hijos.append(contentsOf: p.otrosNombres)
        n.hijos.append(NodoGedcom(tag: "SEX", valor: p.sexo.rawValue))
        for e in p.eventos { n.hijos.append(nodo(evento: e)) }
        for m in p.fotos { n.hijos.append(nodo(medio: m)) }
        if !p.correo.isEmpty { n.hijos.append(NodoGedcom(tag: "EMAIL", valor: p.correo)) }
        if !p.notas.isEmpty { n.hijos.append(NodoGedcom(tag: "NOTE", valor: p.notas)) }

        // FAMC / FAMS: usar los nodos originales (con PEDI, etc.) si siguen vigentes.
        for f in p.familiasComoHijo {
            n.hijos.append(p.extra.first { $0.tag == "FAMC" && $0.valor == "@\(f)@" } ?? NodoGedcom(tag: "FAMC", valor: "@\(f)@"))
        }
        for f in p.familiasComoPareja {
            n.hijos.append(p.extra.first { $0.tag == "FAMS" && $0.valor == "@\(f)@" } ?? NodoGedcom(tag: "FAMS", valor: "@\(f)@"))
        }
        n.hijos.append(contentsOf: p.extra.filter { $0.tag != "FAMC" && $0.tag != "FAMS" })
        return n
    }

    static func nodo(familia f: Familia) -> NodoGedcom {
        var n = NodoGedcom(tag: "FAM", xref: f.id)
        if let h = f.pareja1 {
            n.hijos.append(f.extra.first { $0.tag == "HUSB" && $0.valor == "@\(h)@" } ?? NodoGedcom(tag: "HUSB", valor: "@\(h)@"))
        }
        if let w = f.pareja2 {
            n.hijos.append(f.extra.first { $0.tag == "WIFE" && $0.valor == "@\(w)@" } ?? NodoGedcom(tag: "WIFE", valor: "@\(w)@"))
        }
        for c in f.hijos { n.hijos.append(NodoGedcom(tag: "CHIL", valor: "@\(c)@", hijos: f.extraHijos[c] ?? [])) }
        for e in f.eventos { n.hijos.append(nodo(evento: e)) }
        if !f.notas.isEmpty { n.hijos.append(NodoGedcom(tag: "NOTE", valor: f.notas)) }
        n.hijos.append(contentsOf: f.extra.filter { $0.tag != "HUSB" && $0.tag != "WIFE" })
        return n
    }
}
