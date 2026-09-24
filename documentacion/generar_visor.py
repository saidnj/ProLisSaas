#!/usr/bin/env python3
"""
Genera `documentacion.html`: el visor con todos los documentos dentro.

Por que existe. `visor.html` necesita un servidor local porque el navegador no
deja que una pagina abierta con doble clic lea archivos del disco. Eso funciona
hasta que algo del servidor se tuerce -- un puerto ocupado, OneDrive tardando en
materializar un archivo, un cortafuegos -- y entonces la pagina se queda en
"conectando..." sin decir por que, porque `http.server` de Python atiende una
peticion a la vez y una que se atasca bloquea las demas.

`documentacion.html` no tiene ese problema: lleva los documentos incrustados.
Se abre con doble clic y funciona siempre. Y si ademas hay servidor, los lee de
disco y se actualiza sola como el otro -- con un limite de tres segundos, de
modo que un servidor atascado ya no deja la pagina colgada: cae a la copia
incrustada y lo dice.

    python3 generar_visor.py

Se regenera cada vez que cambian los documentos.
"""

import json
import pathlib
import datetime

AQUI = pathlib.Path(__file__).parent
PLANTILLA = AQUI / 'visor.html'
SALIDA = AQUI / 'documentacion.html'


def main():
    html = PLANTILLA.read_text(encoding='utf-8')
    indice = json.loads((AQUI / 'indice.json').read_text(encoding='utf-8'))

    datos = {'indice.json': (AQUI / 'indice.json').read_text(encoding='utf-8')}
    for grupo in indice['grupos']:
        for doc in grupo['docs']:
            ruta = AQUI / doc['ruta']
            if ruta.exists():
                datos[doc['ruta']] = ruta.read_text(encoding='utf-8')

    sello = datetime.datetime.now().strftime('%d/%m/%Y %H:%M')

    # Los documentos van escapados para que ningun `</script>` de su contenido
    # cierre la etiqueta antes de tiempo.
    blob = json.dumps(datos, ensure_ascii=False).replace('<', '\\u003c')

    prelude = """
<script>
/* ---------------------------------------------------------------------
   Copia incrustada. Este archivo se genera con generar_visor.py y lleva
   los documentos dentro, asi que abrirlo con doble clic funciona.

   Lo que sigue envuelve fetch: intenta leer del disco durante tres
   segundos y, si no hay servidor o se atasca, devuelve la copia de aqui.
   El resto del visor no se entera y funciona igual.
   --------------------------------------------------------------------- */
const EMBEBIDO = %BLOB%;
const SELLO = "%SELLO%";
let MODO = 'incrustado';

// Abierto con doble clic no hay disco que leer: el navegador bloquea `fetch`
// sobre `file://` por origen cruzado. Intentarlo igual solo servia para tirar
// veinte errores rojos a la consola cada dos segundos, para siempre.
const SIN_RED = location.protocol === 'file:';

const _fetch = window.fetch ? window.fetch.bind(window) : null;
window.fetch = async function(url, opts){
  const ruta = String(url).split('?')[0].replace(/^\\.?\\//, '');
  if(_fetch && !SIN_RED){
    try{
      const ctrl = new AbortController();
      const corte = setTimeout(()=>ctrl.abort(), 3000);
      const r = await _fetch(url, Object.assign({}, opts, {signal: ctrl.signal}));
      clearTimeout(corte);
      if(r.ok){ MODO = 'vivo'; return r; }
    }catch(e){ /* sin servidor, atascado, o abierto con file:// */ }
  }
  if(Object.prototype.hasOwnProperty.call(EMBEBIDO, ruta)){
    MODO = 'incrustado';
    return new Response(EMBEBIDO[ruta], {status:200, headers:{'Content-Type':'text/plain'}});
  }
  throw new Error('no encontrado: ' + ruta);
};
</script>
"""
    prelude = prelude.replace('%BLOB%', blob).replace('%SELLO%', sello)

    # Y despues del script principal, decir en que modo esta.
    epilogo = """
<script>
/* ---------------------------------------------------------------------
   Pintar primero, red despues.

   Antes esto dependia de que una llamada asincrona terminara. Si el
   servidor se atascaba o fetch no resolvia, la pagina se quedaba en
   "conectando..." con la lista vacia y sin decir nada. Ahora se pinta de
   entrada con la copia incrustada -- sin red, sin await, sin nada que
   pueda colgarse -- y solo despues se intenta leer del disco.

   Consecuencia: esta pagina no puede quedarse en blanco.
   --------------------------------------------------------------------- */
(function(){
  const decir = (msg, ok) => {
    try{
      document.getElementById('estado').textContent = msg;
      document.getElementById('dot').className = 'dot' + (ok ? '' : ' off');
    }catch(e){}
  };

  // 1 · de entrada, lo incrustado
  try{
    indice = JSON.parse(EMBEBIDO['indice.json']);
    for(const r in EMBEBIDO){ if(r !== 'indice.json') cache.set(r, EMBEBIDO[r]); }
    if(!actual){
      actual = decodeURIComponent((location.hash || '').slice(1))
               || indice.grupos[0].docs[0].ruta;
      if(!cache.has(actual)) actual = indice.grupos[0].docs[0].ruta;
    }
    pintarNav();
    pintarDoc();
    decir('copia del ' + SELLO, true);
  }catch(e){
    document.getElementById('cont').innerHTML =
      '<div class="aviso"><h2>El visor no pudo pintarse</h2><p><code>'
      + String(e && e.message || e) + '</code></p>'
      + '<p>Origen: <code>' + location.protocol + '</code> · Documentos incrustados: <code>'
      + (typeof EMBEBIDO === 'object' ? Object.keys(EMBEBIDO).length : 'ninguno')
      + '</code></p><p><code>' + navigator.userAgent + '</code></p></div>';
    decir('error al pintar', false);
    return;
  }

  // 2 · y solo despues, el disco. Si no hay o tarda, no pasa nada:
  //     lo de arriba ya esta en pantalla.
  window.marcarEstado = function(ok, msg){
    decir(MODO === 'vivo' ? msg + ' · leyendo del disco'
                          : 'copia del ' + SELLO, true);
  };
  if(SIN_RED){
    // Sin servidor no hay nada que volver a leer: se apaga el ciclo de los dos
    // segundos. La pagina queda quieta con lo que ya pinto.
    try{ clearInterval(CICLO); }catch(e){}
    return;
  }
  if(typeof refrescar === 'function'){
    setTimeout(()=>{ try{ refrescar(false); }catch(e){} }, 300);
  }
})();
</script>
"""

    html = html.replace('<script>', prelude + '<script>', 1)
    html = html.replace('</body>', epilogo + '</body>', 1)

    SALIDA.write_text(html, encoding='utf-8')
    kb = SALIDA.stat().st_size / 1024
    print(f'{SALIDA.name} · {len(datos)} documentos · {kb:.0f} KB · {sello}')


if __name__ == '__main__':
    main()
