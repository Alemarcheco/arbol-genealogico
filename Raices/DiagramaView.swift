import SwiftUI

// MARK: - Cálculo de la disposición del árbol

struct ElementoDiagrama: Identifiable {
    enum Tipo {
        case persona(String)
        case vacio(de: String, relacion: Relacion)
    }
    let id: String
    let tipo: Tipo
    var x: CGFloat
    var y: CGFloat
    var esFoco = false
    /// Indicadores de que hay más familia fuera de la vista.
    var masArriba = false
    var masAbajo = 0
}

struct DisposicionArbol {
    static let anchoTarjeta: CGFloat = 128
    static let altoTarjeta: CGFloat = 150
    static let anchoHueco: CGFloat = 146
    static let altoFila: CGFloat = 205

    var elementos: [ElementoDiagrama] = []
    var lineas: [[CGPoint]] = []
    var lineasPareja: [[CGPoint]] = []
    var tamano: CGSize = .zero

    @MainActor
    init(foco: String, generaciones: Int, arbol: ArbolStore) {
        guard arbol.persona(foco) != nil else { return }
        let W = Self.anchoHueco, H = Self.altoFila, cw = Self.anchoTarjeta, ch = Self.altoTarjeta

        // Antepasados por generación (pedigrí).
        var gens: [[String?]] = [[foco]]
        var profundidad = 0
        for g in 1...max(1, generaciones) {
            var fila: [String?] = Array(repeating: nil, count: 1 << g)
            for (i, hijo) in gens[g - 1].enumerated() {
                guard let hijo else { continue }
                let (pa, ma) = arbol.padres(de: hijo)
                fila[2 * i] = pa?.id
                fila[2 * i + 1] = ma?.id
            }
            gens.append(fila)
            if fila.contains(where: { $0 != nil }) { profundidad = g }
        }
        // Una generación más para mostrar los huecos "Añadir padre/madre".
        let mostrar = min(max(1, generaciones), profundidad + 1)
        let anchoTotal = CGFloat(1 << mostrar) * W

        func xAnc(_ g: Int, _ i: Int) -> CGFloat { (CGFloat(i) + 0.5) * anchoTotal / CGFloat(1 << g) - anchoTotal / 2 }

        var els: [ElementoDiagrama] = []
        var lin: [[CGPoint]] = []
        var linP: [[CGPoint]] = []

        for g in 1...mostrar {
            for i in 0..<(1 << g) {
                guard let hijo = gens[g - 1][i] else { continue }
                let x = xAnc(g, i), y = -CGFloat(g) * H
                if let pid = gens[g][i] {
                    var e = ElementoDiagrama(id: "a\(g)-\(i)", tipo: .persona(pid), x: x, y: y)
                    if g == mostrar { e.masArriba = arbol.familiaDePadres(de: pid).map { !$0.parejas.isEmpty } ?? false }
                    els.append(e)
                } else {
                    let rel: Relacion = i % 2 == 0 ? .padre : .madre
                    if arbol.puede(rel, a: hijo) {
                        els.append(ElementoDiagrama(id: "v\(g)-\(i)", tipo: .vacio(de: hijo, relacion: rel), x: x, y: y))
                    }
                }
            }
            // Líneas de cada pareja de padres hacia su hijo.
            for i in 0..<(1 << (g - 1)) {
                guard gens[g - 1][i] != nil else { continue }
                let pa = gens[g][2 * i], ma = gens[g][2 * i + 1]
                guard pa != nil || ma != nil else { continue }
                let y = -CGFloat(g) * H
                let xp = xAnc(g, 2 * i), xm = xAnc(g, 2 * i + 1), xc = xAnc(g - 1, i)
                let yHijo = -CGFloat(g - 1) * H - ch / 2
                if pa != nil && ma != nil {
                    linP.append([CGPoint(x: xp + cw / 2, y: y), CGPoint(x: xm - cw / 2, y: y)])
                }
                let xInicio = pa != nil && ma != nil ? (xp + xm) / 2 : (pa != nil ? xp : xm)
                let yInicio = pa != nil && ma != nil ? y : y + ch / 2
                let medio = (y + ch / 2 + yHijo) / 2
                if g == 1 { continue } // la generación 1 se dibuja junto a los hermanos
                lin.append([CGPoint(x: xInicio, y: yInicio), CGPoint(x: xInicio, y: medio),
                            CGPoint(x: xc, y: medio), CGPoint(x: xc, y: yHijo)])
            }
        }

        // Fila del foco: hermanos a la izquierda, parejas a la derecha.
        var focoEl = ElementoDiagrama(id: "foco", tipo: .persona(foco), x: 0, y: 0)
        focoEl.esFoco = true
        els.append(focoEl)

        let hermanos = arbol.hermanos(de: foco)
        var xsHermanos: [CGFloat] = [0]
        for (k, h) in hermanos.reversed().enumerated() {
            let x = -CGFloat(k + 1) * W - (hermanos.isEmpty ? 0 : 10)
            var e = ElementoDiagrama(id: "h\(k)", tipo: .persona(h.id), x: x, y: 0)
            e.masAbajo = arbol.hijos(de: h.id).count
            els.append(e)
            xsHermanos.append(x)
        }
        // Líneas desde los padres del foco hasta él y sus hermanos.
        let (pa1, ma1) = arbol.padres(de: foco)
        if pa1 != nil || ma1 != nil {
            let xp = xAnc(1, 0), xm = xAnc(1, 1), y = -H
            let xInicio = pa1 != nil && ma1 != nil ? (xp + xm) / 2 : (pa1 != nil ? xp : xm)
            let yInicio = pa1 != nil && ma1 != nil ? y : y + ch / 2
            let medio = (y + ch / 2 - ch / 2) / 2
            lin.append([CGPoint(x: xInicio, y: yInicio), CGPoint(x: xInicio, y: medio)])
            let minX = min(xsHermanos.min() ?? 0, xInicio), maxX = max(xsHermanos.max() ?? 0, xInicio)
            lin.append([CGPoint(x: minX, y: medio), CGPoint(x: maxX, y: medio)])
            for x in xsHermanos { lin.append([CGPoint(x: x, y: medio), CGPoint(x: x, y: -ch / 2)]) }
        }

        let parejas = arbol.parejas(de: foco)
        var xsParejas: [String: CGFloat] = [:]
        var k = 0
        for (p, f) in parejas {
            guard let p else { continue }
            k += 1
            let x = CGFloat(k) * W + 10
            els.append(ElementoDiagrama(id: "p\(k)", tipo: .persona(p.id), x: x, y: 0))
            xsParejas[f.id] = x
            linP.append([CGPoint(x: cw / 2, y: -ch / 2 + 26 + CGFloat(k - 1) * 8),
                         CGPoint(x: x - cw / 2, y: -ch / 2 + 26 + CGFloat(k - 1) * 8)])
        }
        if k == 0 {
            els.append(ElementoDiagrama(id: "vp", tipo: .vacio(de: foco, relacion: .pareja), x: W + 10, y: 0))
        }

        // Hijos debajo, agrupados por pareja.
        var grupos: [(familia: Familia, hijos: [Persona])] = []
        for (_, f) in parejas {
            let h = arbol.hijos(familia: f)
            if !h.isEmpty { grupos.append((f, h)) }
        }
        let totalHijos = grupos.reduce(0) { $0 + $1.hijos.count }
        if totalHijos == 0 {
            els.append(ElementoDiagrama(id: "vh", tipo: .vacio(de: foco, relacion: .hijo),
                                        x: (xsParejas.values.min() ?? 0) / 2, y: H))
        } else {
            let separacion: CGFloat = 24
            let ancho = CGFloat(totalHijos) * W + CGFloat(grupos.count - 1) * separacion
            let centros = grupos.map { (0 + (xsParejas[$0.familia.id] ?? 0)) / 2 }
            let centro = centros.reduce(0, +) / CGFloat(max(1, centros.count))
            var x = centro - ancho / 2 + W / 2
            for (gi, grupo) in grupos.enumerated() {
                let xPadres = centros[gi]
                let tienePareja = xsParejas[grupo.familia.id] != nil
                let yInicio: CGFloat = tienePareja ? -ch / 2 + 26 + CGFloat(gi) * 8 : ch / 2
                let medio = H / 2 + CGFloat(gi) * 8 - 10
                var xs: [CGFloat] = []
                for (hi, h) in grupo.hijos.enumerated() {
                    var e = ElementoDiagrama(id: "c\(gi)-\(hi)", tipo: .persona(h.id), x: x, y: H)
                    e.masAbajo = arbol.hijos(de: h.id).count
                    els.append(e)
                    xs.append(x)
                    x += W
                }
                x += separacion
                lin.append([CGPoint(x: xPadres, y: yInicio), CGPoint(x: xPadres, y: medio)])
                let a = min(xs.min() ?? xPadres, xPadres), b = max(xs.max() ?? xPadres, xPadres)
                lin.append([CGPoint(x: a, y: medio), CGPoint(x: b, y: medio)])
                for cx in xs { lin.append([CGPoint(x: cx, y: medio), CGPoint(x: cx, y: H - ch / 2)]) }
            }
        }

        // Normalizar coordenadas a positivas con margen.
        let margen: CGFloat = 40
        let minX = (els.map(\.x).min() ?? 0) - cw / 2 - margen
        let maxX = (els.map(\.x).max() ?? 0) + cw / 2 + margen
        let minY = (els.map(\.y).min() ?? 0) - ch / 2 - margen
        let maxY = (els.map(\.y).max() ?? 0) + ch / 2 + margen
        for i in els.indices { els[i].x -= minX; els[i].y -= minY }
        func mover(_ l: [[CGPoint]]) -> [[CGPoint]] { l.map { $0.map { CGPoint(x: $0.x - minX, y: $0.y - minY) } } }
        elementos = els
        lineas = mover(lin)
        lineasPareja = mover(linP)
        tamano = CGSize(width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Vista

struct DiagramaView: View {
    @Environment(ArbolStore.self) private var arbol
    @Environment(Biblioteca.self) private var biblioteca
    @Binding var ruta: NavigationPath
    @AppStorage("generaciones") private var generaciones = 3
    @State private var escala: CGFloat = 1
    @State private var escalaBase: CGFloat = 1
    @State private var buscar = false
    @State private var anadir: AnadirFamiliar? = nil

    var body: some View {
        Group {
            if let foco = arbol.foco, arbol.persona(foco) != nil {
                diagrama(foco)
            } else {
                ContentUnavailableView {
                    Label("Árbol vacío", systemImage: "tree")
                } description: {
                    Text("Añade la primera persona para empezar tu árbol.")
                } actions: {
                    Button("Añadir persona") { anadir = AnadirFamiliar(relacion: nil, de: nil) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(arbol.datos.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { biblioteca.abierto = nil; biblioteca.cargar() } label: {
                    Image(systemName: "chevron.backward.circle")
                }
                .accessibilityLabel("Mis árboles")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { buscar = true } label: { Image(systemName: "magnifyingglass") }
                Button {
                    withAnimation(.snappy) { arbol.foco = arbol.datos.raiz ?? arbol.foco }
                } label: { Image(systemName: "house") }
                Menu {
                    Picker("Generaciones de antepasados", selection: $generaciones) {
                        ForEach(1...5, id: \.self) { Text("\($0) generación\($0 == 1 ? "" : "es")").tag($0) }
                    }
                } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $buscar) {
            SelectorPersona(titulo: "Ir a persona") { id in withAnimation(.snappy) { arbol.foco = id } }
        }
        .sheet(item: $anadir) { a in NuevoFamiliarView(relacion: a.relacion, de: a.de) }
    }

    func diagrama(_ foco: String) -> some View {
        let d = DisposicionArbol(foco: foco, generaciones: generaciones, arbol: arbol)
        let e = escala
        return ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        for l in d.lineas {
                            ctx.stroke(camino(l, e), with: .color(.secondary.opacity(0.55)), lineWidth: 1.6 * e)
                        }
                        for l in d.lineasPareja {
                            ctx.stroke(camino(l, e), with: .color(Tema.mujer.opacity(0.55)), style: StrokeStyle(lineWidth: 1.6 * e, dash: [5 * e, 3 * e]))
                        }
                    }
                    .frame(width: d.tamano.width * e, height: d.tamano.height * e)

                    ForEach(d.elementos) { el in
                        tarjeta(el)
                            .frame(width: DisposicionArbol.anchoTarjeta, height: DisposicionArbol.altoTarjeta)
                            .scaleEffect(e)
                            .frame(width: DisposicionArbol.anchoTarjeta * e, height: DisposicionArbol.altoTarjeta * e)
                            .id(el.id)
                            .position(x: el.x * e, y: el.y * e)
                    }
                }
                .frame(width: d.tamano.width * e, height: d.tamano.height * e, alignment: .topLeading)
            }
            .background(Color(.systemGroupedBackground))
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in escala = min(2.2, max(0.35, escalaBase * v.magnification)) }
                    .onEnded { _ in escalaBase = escala }
            )
            .overlay(alignment: .bottomTrailing) { controlesZoom(proxy) }
            .onAppear { centrar(proxy, animado: false) }
            .onChange(of: arbol.foco) { centrar(proxy, animado: true) }
            .onChange(of: generaciones) { centrar(proxy, animado: true) }
        }
    }

    func camino(_ puntos: [CGPoint], _ e: CGFloat) -> Path {
        var p = Path()
        guard let f = puntos.first else { return p }
        p.move(to: CGPoint(x: f.x * e, y: f.y * e))
        for q in puntos.dropFirst() { p.addLine(to: CGPoint(x: q.x * e, y: q.y * e)) }
        return p
    }

    func centrar(_ proxy: ScrollViewProxy, animado: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animado { withAnimation(.snappy) { proxy.scrollTo("foco", anchor: .center) } }
            else { proxy.scrollTo("foco", anchor: .center) }
        }
    }

    func controlesZoom(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            Button { cambiarEscala(1.25) } label: { Image(systemName: "plus").frame(width: 44, height: 40) }
            Divider().frame(width: 30)
            Button { cambiarEscala(0.8) } label: { Image(systemName: "minus").frame(width: 44, height: 40) }
            Divider().frame(width: 30)
            Button { centrar(proxy, animado: true) } label: { Image(systemName: "scope").frame(width: 44, height: 40) }
        }
        .font(.body.weight(.semibold))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding()
    }

    func cambiarEscala(_ f: CGFloat) {
        withAnimation(.snappy) { escala = min(2.2, max(0.35, escala * f)) }
        escalaBase = escala
    }

    @ViewBuilder
    func tarjeta(_ el: ElementoDiagrama) -> some View {
        switch el.tipo {
        case .persona(let pid):
            if let p = arbol.persona(pid) {
                TarjetaArbol(persona: p, esFoco: el.esFoco, masArriba: el.masArriba, masAbajo: el.masAbajo)
                    .onTapGesture {
                        if el.esFoco { ruta.append(pid) }
                        else { withAnimation(.snappy) { arbol.foco = pid } }
                    }
                    .contextMenu {
                        Button { ruta.append(pid) } label: { Label("Ver perfil", systemImage: "person.text.rectangle") }
                        if !el.esFoco {
                            Button { withAnimation(.snappy) { arbol.foco = pid } } label: { Label("Centrar en el árbol", systemImage: "scope") }
                        }
                        Divider()
                        ForEach(Relacion.allCases) { r in
                            if arbol.puede(r, a: pid) {
                                Button { anadir = AnadirFamiliar(relacion: r, de: pid) } label: { Label(r.titulo, systemImage: r.icono) }
                            }
                        }
                    }
            }
        case .vacio(let de, let rel):
            TarjetaVacia(relacion: rel)
                .onTapGesture { anadir = AnadirFamiliar(relacion: rel, de: de) }
        }
    }
}

struct AnadirFamiliar: Identifiable {
    let id = UUID()
    let relacion: Relacion?
    let de: String?
}

struct TarjetaArbol: View {
    let persona: Persona
    var esFoco = false
    var masArriba = false
    var masAbajo = 0

    var body: some View {
        VStack(spacing: 6) {
            Avatar(persona: persona, tam: 62)
                .padding(.top, 12)
            Text(persona.nombreCorto)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 6)
            Text(persona.rangoVida)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                        .fill(Tema.color(persona.sexo).opacity(0.85))
                        .frame(height: 5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(esFoco ? Tema.verde : Color.black.opacity(0.08), lineWidth: esFoco ? 3 : 1)
        }
        .shadow(color: .black.opacity(esFoco ? 0.18 : 0.08), radius: esFoco ? 8 : 4, y: 2)
        .overlay(alignment: .top) {
            if masArriba {
                Image(systemName: "chevron.up.circle.fill").foregroundStyle(Tema.verde).background(Circle().fill(.background)).offset(y: -10)
            }
        }
        .overlay(alignment: .bottom) {
            if masAbajo > 0 {
                Text("\(masAbajo) \(masAbajo == 1 ? "hijo" : "hijos")")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Tema.verde.opacity(0.9)))
                    .foregroundStyle(.white)
                    .offset(y: 8)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TarjetaVacia: View {
    let relacion: Relacion

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").font(.system(size: 34)).foregroundStyle(Tema.color(relacion.sexo).opacity(0.7))
            Text(relacion.titulo).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundStyle(.secondary.opacity(0.6)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
