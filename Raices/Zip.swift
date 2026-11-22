import Foundation
import Compression

/// ZIP mínimo: lectura (sin comprimir y "deflate") y escritura sin compresión.
enum Zip {
    struct Entrada {
        let nombre: String
        let datos: Data
    }

    enum Fallo: LocalizedError {
        case formato
        var errorDescription: String? { "El archivo ZIP no se pudo leer." }
    }

    private static func u16(_ d: [UInt8], _ i: Int) -> Int { Int(d[i]) | Int(d[i + 1]) << 8 }
    private static func u32(_ d: [UInt8], _ i: Int) -> Int {
        Int(d[i]) | Int(d[i + 1]) << 8 | Int(d[i + 2]) << 16 | Int(d[i + 3]) << 24
    }

    static func esZip(_ datos: Data) -> Bool {
        let b = [UInt8](datos.prefix(4))
        return b.count == 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04
    }

    /// Lee las entradas cuyo nombre cumpla el filtro.
    static func leer(_ datos: Data, filtro: (String) -> Bool = { _ in true }) throws -> [Entrada] {
        let d = [UInt8](datos)
        guard d.count > 22 else { throw Fallo.formato }
        var fin = -1
        var i = d.count - 22
        let limite = max(0, d.count - 22 - 65_535)
        while i >= limite {
            if d[i] == 0x50, d[i + 1] == 0x4B, d[i + 2] == 0x05, d[i + 3] == 0x06 { fin = i; break }
            i -= 1
        }
        guard fin >= 0 else { throw Fallo.formato }
        let total = u16(d, fin + 10)
        var p = u32(d, fin + 16)
        var res: [Entrada] = []
        for _ in 0..<total {
            guard p + 46 <= d.count, u32(d, p) == 0x02014B50 else { throw Fallo.formato }
            let metodo = u16(d, p + 10)
            let tamComp = u32(d, p + 20)
            let tamReal = u32(d, p + 24)
            let ln = u16(d, p + 28), le = u16(d, p + 30), lc = u16(d, p + 32)
            let local = u32(d, p + 42)
            guard p + 46 + ln <= d.count else { throw Fallo.formato }
            let nombre = String(decoding: d[(p + 46)..<(p + 46 + ln)], as: UTF8.self)
            p += 46 + ln + le + lc
            if nombre.hasSuffix("/") || !filtro(nombre) { continue }
            guard local + 30 <= d.count, u32(d, local) == 0x04034B50 else { continue }
            let inicio = local + 30 + u16(d, local + 26) + u16(d, local + 28)
            guard inicio + tamComp <= d.count else { continue }
            let comp = Data(d[inicio..<(inicio + tamComp)])
            switch metodo {
            case 0: res.append(Entrada(nombre: nombre, datos: comp))
            case 8:
                if let r = inflar(comp, tamano: tamReal) { res.append(Entrada(nombre: nombre, datos: r)) }
            default: continue
            }
        }
        return res
    }

    private static func inflar(_ comp: Data, tamano: Int) -> Data? {
        let capacidad = max(tamano, 64)
        var salida = Data(count: capacidad)
        let n = salida.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            comp.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacidad,
                    src.bindMemory(to: UInt8.self).baseAddress!, comp.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        return salida.prefix(n)
    }

    // MARK: escritura

    private static let tablaCRC: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in d { c = tablaCRC[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    static func crear(_ entradas: [Entrada]) -> Data {
        var salida = Data()
        var central = Data()
        func a16(_ v: Int, _ d: inout Data) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func a32(_ v: UInt32, _ d: inout Data) { for k in 0..<4 { d.append(UInt8((v >> (8 * UInt32(k))) & 0xFF)) } }

        for e in entradas {
            let nombre = Data(e.nombre.utf8)
            let crc = crc32(e.datos)
            let desplazamiento = UInt32(salida.count)
            // Cabecera local
            a32(0x04034B50, &salida); a16(20, &salida); a16(0x0800, &salida); a16(0, &salida)
            a16(0, &salida); a16(0x21, &salida)
            a32(crc, &salida); a32(UInt32(e.datos.count), &salida); a32(UInt32(e.datos.count), &salida)
            a16(nombre.count, &salida); a16(0, &salida)
            salida.append(nombre); salida.append(e.datos)
            // Directorio central
            a32(0x02014B50, &central); a16(20, &central); a16(20, &central); a16(0x0800, &central); a16(0, &central)
            a16(0, &central); a16(0x21, &central)
            a32(crc, &central); a32(UInt32(e.datos.count), &central); a32(UInt32(e.datos.count), &central)
            a16(nombre.count, &central); a16(0, &central); a16(0, &central); a16(0, &central); a16(0, &central)
            a32(0, &central); a32(desplazamiento, &central)
            central.append(nombre)
        }
        let inicioCentral = UInt32(salida.count)
        salida.append(central)
        a32(0x06054B50, &salida); a16(0, &salida); a16(0, &salida)
        a16(entradas.count, &salida); a16(entradas.count, &salida)
        a32(UInt32(central.count), &salida); a32(inicioCentral, &salida); a16(0, &salida)
        return salida
    }
}
