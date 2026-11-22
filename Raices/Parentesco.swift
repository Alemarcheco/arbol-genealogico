import Foundation

/// Calcula el parentesco entre dos personas y lo describe en español.
@MainActor
enum Parentesco {
    struct Paso: Identifiable {
        let id = UUID()
        let persona: Persona
        /// Cómo se llega a esta persona desde la anterior ("padre de", "hija de"...)
        let relacion: String
    }

    struct Resultado {
        let texto: String
        let camino: [Paso]
    }

    private static func g(_ s: Sexo, _ m: String, _ f: String, _ n: String? = nil) -> String {
        switch s {
        case .hombre: return m
        case .mujer: return f
        case .desconocido: return n ?? "\(m)/\(f.split(separator: " ").first.map(String.init) ?? f)"
        }
    }

    private static let ordinales = ["", "hermano", "segundo", "tercero", "cuarto", "quinto", "sexto", "séptimo", "octavo", "noveno", "décimo"]
    private static let ordinalesF = ["", "hermana", "segunda", "tercera", "cuarta", "quinta", "sexta", "séptima", "octava", "novena", "décima"]

    private static func ordinal(_ n: Int, _ s: Sexo) -> String {
        let l = s == .mujer ? ordinalesF : ordinales
        return n < l.count ? l[n] : "de grado \(n)"
    }

    /// Antepasados con su distancia en generaciones.
    private static func ancestros(_ id: String, _ a: ArbolStore) -> [String: Int] {
        var r: [String: Int] = [id: 0]
        var cola = [id]
        while !cola.isEmpty {
            let x = cola.removeFirst()
            let d = r[x]!
            if d > 40 { continue }
            for p in a.todosLosPadres(de: x) where r[p.id] == nil {
                r[p.id] = d + 1
                cola.append(p.id)
            }
        }
        return r
    }

    /// Nombre del parentesco consanguíneo: "B es el/la ___ de A".
    static func consanguineo(_ aID: String, _ bID: String, _ arbol: ArbolStore) -> String? {
        guard let b = arbol.persona(bID) else { return nil }
        let ancA = ancestros(aID, arbol), ancB = ancestros(bID, arbol)
        var mejor: (Int, Int)? = nil
        var comunes: [String] = []
        for (x, da) in ancA {
            guard let db = ancB[x] else { continue }
            if mejor == nil || da + db < mejor!.0 + mejor!.1 { mejor = (da, db); comunes = [x] }
            else if da + db == mejor!.0 + mejor!.1, (da, db) == mejor! { comunes.append(x) }
        }
        guard let m = mejor else { return nil }
        let ga = m.0, gb = m.1
        let s = b.sexo
        switch (ga, gb) {
        case (0, 0): return "la misma persona"
        case (0, _):
            let n = [1: g(s, "hijo", "hija"), 2: g(s, "nieto", "nieta"), 3: g(s, "bisnieto", "bisnieta"),
                     4: g(s, "tataranieto", "tataranieta"), 5: g(s, "trastataranieto", "trastataranieta")]
            return n[gb] ?? g(s, "descendiente", "descendiente", "descendiente") + " (\(gb) generaciones)"
        case (_, 0):
            let n = [1: g(s, "padre", "madre", "progenitor"), 2: g(s, "abuelo", "abuela"), 3: g(s, "bisabuelo", "bisabuela"),
                     4: g(s, "tatarabuelo", "tatarabuela"), 5: g(s, "trastatarabuelo", "trastatarabuela")]
            return n[ga] ?? g(s, "antepasado", "antepasada") + " (\(ga) generaciones)"
        case (1, 1):
            let medio = comunes.count < 2 && arbol.todosLosPadres(de: aID).count >= 2 && arbol.todosLosPadres(de: bID).count >= 2
            return medio ? g(s, "medio hermano", "media hermana") : g(s, "hermano", "hermana")
        case (1, _):
            let n = [2: g(s, "sobrino", "sobrina"), 3: g(s, "sobrino nieto", "sobrina nieta"),
                     4: g(s, "sobrino bisnieto", "sobrina bisnieta")]
            return n[gb] ?? g(s, "descendiente de un hermano", "descendiente de un hermano")
        case (_, 1):
            let n = [2: g(s, "tío", "tía"), 3: g(s, "tío abuelo", "tía abuela"), 4: g(s, "tío bisabuelo", "tía bisabuela")]
            return n[ga] ?? g(s, "hermano de un antepasado", "hermana de un antepasado")
        default:
            if ga == gb { return g(s, "primo", "prima") + " " + ordinal(ga - 1, s) }
            if gb == ga + 1 { return g(s, "sobrino", "sobrina") + " " + (ga == 1 ? "" : ordinal(ga, s).replacingOccurrences(of: "hermano", with: "segundo")) }
            if ga == gb + 1 { return g(s, "tío", "tía") + " " + ordinal(gb, s).replacingOccurrences(of: "hermano", with: "segundo") }
            return g(s, "pariente", "pariente") + " consanguíneo (primos con \(abs(ga - gb)) generaciones de diferencia)"
        }
    }

    static func calcular(desde aID: String, hasta bID: String, en arbol: ArbolStore) -> Resultado? {
        guard let a = arbol.persona(aID), let b = arbol.persona(bID) else { return nil }
        let camino = caminoMasCorto(aID, bID, arbol)
        let nombreB = b.nombreCorto, nombreA = a.nombreCorto
        let art = b.sexo == .mujer ? "la" : "el"

        if aID == bID { return Resultado(texto: "Es la misma persona.", camino: camino) }

        if let r = consanguineo(aID, bID, arbol) {
            return Resultado(texto: "\(nombreB) es \(art) \(r) de \(nombreA).", camino: camino)
        }

        // Pareja directa
        for (pareja, f) in arbol.parejas(de: aID) where pareja?.id == bID {
            let t = f.divorciados ? g(b.sexo, "exesposo", "exesposa", "expareja") : g(b.sexo, "esposo", "esposa", "pareja")
            return Resultado(texto: "\(nombreB) es \(art) \(t) de \(nombreA).", camino: camino)
        }

        // B es pareja de un pariente de A
        for (pareja, _) in arbol.parejas(de: bID) {
            guard let pr = pareja, let r = consanguineo(aID, pr.id, arbol) else { continue }
            let base = r.split(separator: " ").first.map(String.init) ?? r
            let t: String
            switch base {
            case "padre", "madre", "progenitor": t = g(b.sexo, "padrastro", "madrastra")
            case "hijo", "hija": t = g(b.sexo, "yerno", "nuera")
            case "hermano", "hermana", "medio": t = g(b.sexo, "cuñado", "cuñada")
            case "tío", "tía": t = g(b.sexo, "tío político", "tía política")
            case "sobrino", "sobrina": t = g(b.sexo, "sobrino político", "sobrina política")
            case "primo", "prima": t = g(b.sexo, "primo político", "prima política")
            case "nieto", "nieta": t = g(b.sexo, "nieto político", "nieta política")
            case "abuelo", "abuela": t = g(b.sexo, "abuelastro", "abuelastra")
            default: t = g(b.sexo, "esposo", "esposa", "pareja") + " de su \(r)"
            }
            return Resultado(texto: "\(nombreB) es \(art) \(t) de \(nombreA).", camino: camino)
        }

        // B es pariente de la pareja de A
        for (pareja, _) in arbol.parejas(de: aID) {
            guard let pr = pareja, let r = consanguineo(pr.id, bID, arbol) else { continue }
            let base = r.split(separator: " ").first.map(String.init) ?? r
            let t: String
            switch base {
            case "padre", "madre", "progenitor": t = g(b.sexo, "suegro", "suegra")
            case "hijo", "hija": t = g(b.sexo, "hijastro", "hijastra")
            case "hermano", "hermana", "medio": t = g(b.sexo, "cuñado", "cuñada")
            case "abuelo", "abuela": t = g(b.sexo, "abuelo político", "abuela política")
            case "tío", "tía": t = g(b.sexo, "tío político", "tía política")
            case "sobrino", "sobrina": t = g(b.sexo, "sobrino político", "sobrina política")
            case "primo", "prima": t = g(b.sexo, "primo político", "prima política")
            case "nieto", "nieta": t = g(b.sexo, "nieto político", "nieta política")
            default: t = "\(r) de su pareja"
            }
            return Resultado(texto: "\(nombreB) es \(art) \(t) de \(nombreA).", camino: camino)
        }

        // Concuñados / consuegros
        for (pareja, _) in arbol.parejas(de: aID) {
            guard let pa = pareja else { continue }
            for (pb, _) in arbol.parejas(de: bID) {
                guard let pb else { continue }
                if let r = consanguineo(pa.id, pb.id, arbol), r.hasPrefix("herman") {
                    return Resultado(texto: "\(nombreB) es \(art) \(g(b.sexo, "concuñado", "concuñada")) de \(nombreA).", camino: camino)
                }
            }
        }
        let hijosA = Set(arbol.hijos(de: aID).map(\.id))
        for h in arbol.hijos(de: bID) {
            for (pareja, _) in arbol.parejas(de: h.id) where pareja.map({ hijosA.contains($0.id) }) == true {
                return Resultado(texto: "\(nombreB) es \(art) \(g(b.sexo, "consuegro", "consuegra")) de \(nombreA).", camino: camino)
            }
        }

        if camino.count > 1 {
            return Resultado(texto: "\(nombreB) y \(nombreA) están relacionados por matrimonio (\(camino.count - 1) pasos).", camino: camino)
        }
        return Resultado(texto: "No se encontró ninguna relación entre \(nombreA) y \(nombreB) en este árbol.", camino: [])
    }

    /// Camino más corto entre dos personas por vínculos de padres, hijos y parejas.
    static func caminoMasCorto(_ a: String, _ b: String, _ arbol: ArbolStore) -> [Paso] {
        guard let pa = arbol.persona(a) else { return [] }
        if a == b { return [Paso(persona: pa, relacion: "")] }
        var previo: [String: (String, String)] = [a: ("", "")]
        var cola = [a]
        var i = 0
        while i < cola.count {
            let x = cola[i]; i += 1
            if x == b { break }
            var vecinos: [(String, String)] = []
            for p in arbol.todosLosPadres(de: x) { vecinos.append((p.id, g(p.sexo, "padre", "madre", "progenitor"))) }
            for h in arbol.hijos(de: x) { vecinos.append((h.id, g(h.sexo, "hijo", "hija"))) }
            for (pr, _) in arbol.parejas(de: x) { if let pr { vecinos.append((pr.id, g(pr.sexo, "esposo", "esposa", "pareja"))) } }
            for (v, rel) in vecinos where previo[v] == nil {
                previo[v] = (x, rel)
                cola.append(v)
            }
        }
        guard previo[b] != nil else { return [] }
        var pasos: [Paso] = []
        var actual = b
        while actual != a {
            guard let prev = previo[actual], let p = arbol.persona(actual) else { break }
            let ant = prev.0, rel = prev.1
            pasos.append(Paso(persona: p, relacion: rel))
            actual = ant
        }
        pasos.append(Paso(persona: pa, relacion: ""))
        return pasos.reversed()
    }
}
