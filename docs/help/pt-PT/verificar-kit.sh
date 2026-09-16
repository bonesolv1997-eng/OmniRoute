#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# verificar-kit.sh — verifica a integridade dos ficheiros do kit PT-PT.
#
#   Uso:  bash verificar-kit.sh          (corre a partir da pasta do kit)
#
# Porquê: um .ps1 com acentos ou caracteres decorativos depende do BOM UTF-8 para
# ser lido correctamente pelo Windows PowerShell 5.1. Sem BOM (ou com uma copia
# antiga vinda de cache), esses caracteres viram aspas tipograficas e o ficheiro
# deixa de fazer parse. Solucao adoptada: .ps1 em ASCII puro.
#
# Verifica:
#   1. todos os .ps1 são ASCII PURO (fazem parse com/sem BOM, em UTF-8 ou CP1252)
#      e levam um marcador KIT-VERSION;
#   2. nenhum .ps1 contém caracteres decorativos de risco em CP1252;
#   3. os .cmd são ASCII puro (ignorando CR/LF/TAB) com linhas CRLF;
#   4. os .sh passam o `bash -n`;
#   5. chavetas/parênteses/plêxises equilibrados em cada .ps1, ignorando o
#      conteúdo de strings e comentários (um contador ingénuo dá falsos erros).
# Sai com código 1 se algo falhar (util para pre-commit / CI).
# ---------------------------------------------------------------------------
set -u

AQUI="$(cd "$(dirname "$0")" && pwd)"
cd "$AQUI"

python3 - "$AQUI" <<'PYEOF'
import io, os, subprocess, sys

BASE = sys.argv[1]
falhas = 0
print()
print('  VERIFICAR KIT — ' + BASE)
print('  ' + '-' * 74)

PERIGOSOS = {0x2500, 0x2550, 0x2502, 0x00B7, 0x2014, 0x2013, 0x2022, 0x2026,
             0x20AC, 0x2192, 0x2190, 0x2713, 0x2717, 0x00A0, 0x202F}

def balanco(src):
    """Conta {}, () e [] ignorando strings ('...', \"...\") e comentarios."""
    out = []; i = 0; n = len(src); ins = ind = inb = False
    while i < n:
        c = src[i]
        if inb:
            if src.startswith('#>', i): inb = False; i += 2; continue
            i += 1; continue
        if ins:
            if c == "'":
                if i + 1 < n and src[i+1] == "'": out.append(' '); i += 2; continue
                ins = False
            i += 1; continue
        if ind:
            if c == '`': i += 2; continue
            if c == '"':
                if i + 1 < n and src[i+1] == '"': i += 2; continue
                ind = False
            i += 1; continue
        if src.startswith('<#', i): inb = True; i += 2; continue
        if c == "'": ins = True; i += 1; continue
        if c == '"': ind = True; i += 1; continue
        if c == '#':
            while i < n and src[i] != '\n': i += 1
            continue
        out.append(c); i += 1
    s = ''.join(out)
    probs = []
    for a, b in [('{', '}'), ('(', ')'), ('[', ']')]:
        if s.count(a) != s.count(b):
            probs.append('%s%s %d/%d' % (a, b, s.count(a), s.count(b)))
    prof = 0
    for ln, l in enumerate(s.split('\n'), 1):
        prof += l.count('{') - l.count('}')
        if prof < 0:
            probs.append('profundidade negativa linha %d' % ln); prof = 0
    if prof != 0: probs.append('profundidade final %d' % prof)
    if ins or ind or inb: probs.append('strings nao fechadas')
    return probs

def verifica_ps(f):
    raw = io.open(f, 'rb').read()
    probs = []
    # Regra de ouro deste kit: os .ps1 sao ASCII PURO. Assim fazem parse com BOM,
    # sem BOM, em UTF-8 ou em CP1252 - nenhuma cache/CDN/copiar-colar os parte.
    nao_ascii = sorted({b for b in raw if b > 127})
    if nao_ascii:
        probs.append('tem bytes nao-ASCII (%s)' % ' '.join('%02X' % b for b in nao_ascii[:8]))
    txt = raw.decode('utf-8-sig', errors='replace')
    if 'KIT-VERSION:' not in txt:
        probs.append('sem marcador KIT-VERSION')
    probs += balanco(txt)
    return probs

def verifica_cmd(f):
    raw = io.open(f, 'rb').read()
    probs = []
    permitidos = {7, 9, 10, 13}
    if any((b > 127 or (b < 32 and b not in permitidos)) for b in raw):
        probs.append('tem bytes nao-ASCII/nao-imprimiveis')
    if raw.count(b'\n') != raw.count(b'\r\n'):
        probs.append('tem LF sem CR (precisa de CRLF)')
    return probs

grupos = [('*.ps1', verifica_ps), ('*.cmd', verifica_cmd)]
for padrao, fn in grupos:
    for nome in sorted(x for x in os.listdir(BASE) if x.endswith(padrao[1:])):
        probs = fn(os.path.join(BASE, nome))
        if probs:
            falhas += 1
            print('  [FALHA] %-32s %s' % (nome, '; '.join(probs)))
        else:
            print('  [OK]    %s' % nome)

for nome in sorted(x for x in os.listdir(BASE) if x.endswith('.sh')):
    r = subprocess.run(['bash', '-n', os.path.join(BASE, nome)],
                       capture_output=True)
    if r.returncode == 0:
        print('  [OK]    %-32s bash -n' % nome)
    else:
        falhas += 1
        print('  [FALHA] %-32s erro de sintaxe' % nome)

print('  ' + '-' * 74)
if falhas == 0:
    print('  RESULTADO: tudo OK.')
else:
    print('  RESULTADO: %d problema(s). Corrige antes de publicar.' % falhas)
print()
sys.exit(1 if falhas else 0)
PYEOF
