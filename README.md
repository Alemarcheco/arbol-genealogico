# Raíces — árbol genealógico para iPhone

App nativa (SwiftUI, iOS 17+) para crear y explorar tu árbol familiar, compatible con los archivos GEDCOM que exporta MyHeritage.

## Funciones
- Árbol visual: antepasados arriba (1–5 generaciones), hermanos y parejas al lado, hijos abajo. Toca una tarjeta para centrarla; toca la central para abrir su perfil. Zoom con pellizco.
- Perfil de cada persona: fotos, línea de vida (nacimiento, bautizo, estudios, ocupación, residencias, matrimonio, defunción…), familia inmediata, notas.
- Añadir padre, madre, pareja, hijos y hermanos, o vincular a alguien que ya está en el árbol.
- Buscador por nombre, apellido, lugar o año; filtros vivos/fallecidos.
- Calculadora de parentesco (primo segundo, tío abuelo, cuñado, suegra, consuegro…) con el camino entre ambas personas.
- Estadísticas, apellidos, cumpleaños y aniversarios del mes, lugares con mapa.
- Varios árboles en el mismo teléfono.

## GEDCOM y MyHeritage
- Importa `.ged` (UTF-8, UTF-16 o Windows-1252) y `.zip` que contenga un `.ged` y fotos.
- Lee nombres (GIVN/SURN/_MARNM/NICK), eventos con fecha, lugar, notas y coordenadas, familias, fotos (OBJE con URL de MyHeritage, `_PRIM` = foto principal).
- Las etiquetas que la app no edita (`_UID`, `_UPD`, `RIN`, `_PHOTO_RIN`, fuentes, citas, álbumes…) se guardan y se vuelven a escribir al exportar.
- Exporta GEDCOM 5.5.1 en UTF-8, o un `.zip` con el `.ged` y las fotos guardadas en el teléfono.

## Compilar
Cada push a `main` ejecuta `.github/workflows/ios.yml` (macOS, XcodeGen) y publica `Raices.ipa` sin firmar en Releases. Se instala con Sideloadly y un Apple ID.
