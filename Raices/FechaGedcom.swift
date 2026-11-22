import Foundation

/// Utilidades para fechas en formato GEDCOM 5.5.1.
enum FechaGedcom {
    static let meses = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let mesesEs = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    static let mesesLargos = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                              "agosto", "septiembre", "octubre", "noviembre", "diciembre"]

    enum Modificador: String, CaseIterable, Identifiable {
        case exacta = "", aprox = "ABT", antes = "BEF", despues = "AFT", calculada = "CAL", estimada = "EST"
        var id: String { rawValue }
        var nombre: String {
            switch self {
            case .exacta: return "Exacta"
            case .aprox: return "Aproximada"
            case .antes: return "Antes de"
            case .despues: return "Después de"
            case .calculada: return "Calculada"
            case .estimada: return "Estimada"
            }
        }
    }

    struct Partes: Equatable {
        var modificador: Modificador = .exacta
        var dia: Int? = nil
        var mes: Int? = nil // 1...12
        var anio: Int? = nil

        var gedcom: String {
            guard let anio else {
                if let mes, mes >= 1, mes <= 12 {
                    return [modificador.rawValue, dia.map(String.init) ?? "", meses[mes - 1]]
                        .filter { !$0.isEmpty }.joined(separator: " ")
                }
                return ""
            }
            var p: [String] = []
            if !modificador.rawValue.isEmpty { p.append(modificador.rawValue) }
            if let mes, mes >= 1, mes <= 12 {
                if let dia { p.append(String(dia)) }
                p.append(meses[mes - 1])
            }
            p.append(String(anio))
            return p.joined(separator: " ")
        }
    }

    /// Descompone una fecha sencilla. Devuelve nil si es un rango u otro formato complejo.
    static func partes(_ texto: String) -> Partes? {
        var tokens = texto.uppercased().split(separator: " ").map(String.init)
        var p = Partes()
        if tokens.isEmpty { return p }
        if let m = Modificador(rawValue: tokens[0]), m != .exacta {
            p.modificador = m
            tokens.removeFirst()
        }
        if tokens.contains(where: { ["BET", "AND", "FROM", "TO", "INT"].contains($0) }) { return nil }
        for t in tokens {
            if let i = meses.firstIndex(of: t) { p.mes = i + 1 }
            else if let n = Int(t) {
                if n > 31 || p.mes != nil { p.anio = n } else { p.dia = n }
            } else if t.hasPrefix("(") || t.hasPrefix("@") { return nil }
            else { return nil }
        }
        if p.anio == nil, let d = p.dia, p.mes == nil { p.anio = d; p.dia = nil }
        return p
    }

    /// Primer año que aparezca en la fecha (sirve para ordenar y calcular edades).
    static func anio(_ texto: String) -> Int? {
        for t in texto.split(whereSeparator: { !$0.isNumber }) {
            if t.count >= 3, let n = Int(t), n > 0, n < 3000 { return n }
        }
        return nil
    }

    static func mesYDia(_ texto: String) -> (mes: Int, dia: Int)? {
        guard let p = partes(texto), let m = p.mes, let d = p.dia, p.modificador == .exacta else { return nil }
        return (m, d)
    }

    static func fecha(_ texto: String) -> Date? {
        guard let p = partes(texto), let a = p.anio else { return nil }
        var c = DateComponents()
        c.year = a; c.month = p.mes ?? 1; c.day = p.dia ?? 1
        return Calendar(identifier: .gregorian).date(from: c)
    }

    /// Convierte "ABT 12 MAR 1950" en "hacia 12 mar 1950".
    static func legible(_ texto: String) -> String {
        let t = texto.recortado
        if t.isEmpty { return "" }
        var salida: [String] = []
        for tok in t.split(separator: " ").map(String.init) {
            let u = tok.uppercased()
            if let i = meses.firstIndex(of: u) { salida.append(mesesEs[i]); continue }
            switch u {
            case "ABT": salida.append("hacia")
            case "CAL": salida.append("calculado")
            case "EST": salida.append("estimado")
            case "BEF": salida.append("antes de")
            case "AFT": salida.append("después de")
            case "BET": salida.append("entre")
            case "AND": salida.append("y")
            case "FROM": salida.append("desde")
            case "TO": salida.append("hasta")
            case "INT": salida.append("")
            case "@#DJULIAN@": salida.append("(juliano)")
            case "@#DGREGORIAN@": break
            case "BC", "B.C.": salida.append("a. C.")
            default: salida.append(tok)
            }
        }
        return salida.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func hoyGedcom() -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.day, .month, .year], from: Date())
        return "\(c.day ?? 1) \(meses[(c.month ?? 1) - 1]) \(c.year ?? 2000)"
    }

    /// Edad en años entre dos fechas GEDCOM (aprox. si faltan datos).
    static func edad(desde: String, hasta: String?) -> Int? {
        guard let a = anio(desde) else { return nil }
        let fin: Date
        if let hasta, !hasta.isEmpty {
            guard let f = fecha(hasta) ?? anio(hasta).flatMap({ fecha(String($0)) }) else { return nil }
            fin = f
        } else { fin = Date() }
        guard let ini = fecha(desde) ?? fecha(String(a)) else { return nil }
        let e = Calendar(identifier: .gregorian).dateComponents([.year], from: ini, to: fin).year
        return e.flatMap { $0 >= 0 && $0 < 130 ? $0 : nil }
    }
}
