#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# diagnostico-net-lenta.sh  —  "a minha net ficou má": uma passagem de diagnóstico
#
#   Uso:  bash diagnostico-net-lenta.sh            (não precisa de sudo)
#         bash diagnostico-net-lenta.sh --sem-disco
#
# Funciona em Linux (rede por NetworkManager/GNOME) e macOS.
# Faz as mesmas verificações da versão PowerShell: interface e velocidade de
# link, proxies presos (gsettings / scutil / variáveis), DNS, latência/perda/
# jitter, bufferbloat, MTU, velocidade real de download, ficheiros hosts,
# certificados de interceção, restos de TPROXY (Linux) e escrita em disco.
#
# NÃO altera nada no sistema. Só lê e mede.
# ---------------------------------------------------------------------------

SEM_DISCO=0
for arg in "$@"; do
  case "$arg" in
    --sem-disco) SEM_DISCO=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
  esac
done

OS="$(uname -s)"
LOG="diagnostico-rede-$(date +%Y%m%d-%H%M%S).txt"
# Duplica a saída para ficheiro (para poderes colar num ticket/fórum)
exec > >(tee "$LOG") 2>&1

FALHAS=()
ALERTAS=()
DL_MBPS=""

titulo() { printf '\n%s\n  %s\n%s\n' "$(printf '═%.0s' {1..78})" "$1" "$(printf '═%.0s' {1..78})"; }
sub()    { printf '  · %s\n' "$1"; }
ok()     { printf '  [OK]      %s\n' "$1"; }
info()   { printf '  [i]       %s\n' "$1"; }
warn()   { printf '  [ATENÇÃO] %s\n' "$1"; ALERTAS+=("$1"); }
erro()   { printf '  [FALHA]   %s\n' "$1"; FALHAS+=("$1"); }

tem() { command -v "$1" >/dev/null 2>&1; }

echo
echo "  DIAGNÓSTICO DE REDE — iniciado $(date '+%Y-%m-%d %H:%M:%S')"
echo "  Máquina: $(hostname)   Sistema: $OS $(uname -r)"

# ───────────────────────────────────────────────────────────────────────────
titulo "0. Contexto do sistema"
if [ "$OS" = "Darwin" ]; then
  sub "macOS $(sw_vers -productVersion 2>/dev/null)"
else
  sub "$( (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME") || echo "Linux") (kernel $(uname -r))"
fi
if [ "$OS" = "Linux" ]; then
  sub "CPU: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')"
  sub "RAM: $(awk '/MemTotal/{printf "%.1f GB", $2/1048576}' /proc/meminfo 2>/dev/null)"
  sub "Uptime: $(uptime -p 2>/dev/null || uptime)"
else
  sub "CPU/RAM: $(sysctl -n machdep.cpu.brand_string 2>/dev/null) / $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 )) GB"
fi

# Nota: comparamos o processo encontrado com o próprio script (e com o comando que
# o invocou) para não nos tomarmos por um proxy só porque o caminho tem "OmniRoute".
for p in omniroute mitmproxy mitmdump mitm fiddler charles burp zap clash v2ray xray sing-box qbittorrent transmission transmission-daemon openvpn wireguard; do
  match=""
  for pid in $(pgrep -i "$p" 2>/dev/null); do
    [ "$pid" = "$$" ] && continue
    cmd="$(ps -p "$pid" -o command= 2>/dev/null)"
    case "$cmd" in
      *diagnostico-net-lenta*) continue ;;
      *"OmniRoute/docs/help"*) continue ;;
    esac
    match="$pid"
    break
  done
  [ -n "$match" ] || continue
  case "$p" in
    qbittorrent|transmission*) warn "'$p' está em execução (pid $match) — clientes de torrent saturam a linha e a tabela NAT do router." ;;
    *) warn "'$p' está em execução (pid $match) — proxy/interceção pode estar a limitar TODO o tráfego." ;;
  esac
done

# ───────────────────────────────────────────────────────────────────────────
titulo "1. Interface de rede e camada física"
if tem ip; then
  sub "Interfaces ativas:"
  ip -br addr show 2>/dev/null | grep -v '^lo' | sed 's/^/      /'
  for i in /sys/class/net/*; do
    nome=$(basename "$i")
    [ "$nome" = "lo" ] && continue
    [ -r "$i/speed" ] || continue
    vel=$(cat "$i/speed" 2>/dev/null)
    case "$vel" in ''|-1|*[!0-9]*) continue ;; esac
    sub "$nome: velocidade de link negociada = ${vel} Mbps"
    if [ "$vel" -lt 1000 ] && [ ! -d "$i/wireless" ]; then
      warn "A porta $nome negociou apenas ${vel} Mbps. Numa linha de 1 Gbps isto é o teto: cabo CAT5e/6 danificado, porta 100M no router, ou switch mal configurado."
    fi
  done
fi
if [ "$OS" = "Darwin" ]; then
  servico=$(networksetup -listnetworkserviceorder 2>/dev/null | awk -F'Device: ' '/Device: /{print $2}' | tr -d ')' | head -1)
  [ -n "$servico" ] && sub "Interface principal: $(networksetup -listallhardwareports 2>/dev/null | grep -A2 "$servico" | head -3 | tr '\n' ' ')"
fi

# Wi-Fi: ligado ou por cabo?
WIFI_ATIVO=0
if [ "$OS" = "Linux" ] && tem nmcli; then
  tipo=$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | awk -F: '$3=="connected" && $2=="wifi"{print $1; exit}')
  if [ -n "$tipo" ]; then
    WIFI_ATIVO=1
    sub "Wi-Fi ligado em $tipo:"
    nmcli -f GENERAL.CONNECTION,GENERAL.STATE,AP.SSID,AP.FREQ,AP.SIGNAL dev show "$tipo" 2>/dev/null | sed 's/^/      /'
    freq=$(nmcli -t -f AP.FREQ dev show "$tipo" 2>/dev/null | cut -d: -f2)
    sinal=$(nmcli -t -f AP.SIGNAL dev show "$tipo" 2>/dev/null | cut -d: -f2)
    case "$freq" in
      2*) warn "Estás em Wi-Fi 2,4 GHz (~$freq MHz). O teto prático é 100-150 Mbps mesmo com bom sinal." ;;
      5*|6*) sub "Banda 5/6 GHz ($freq MHz) — bom." ;;
    esac
    if [ -n "$sinal" ] && [ "$sinal" -lt 60 ] 2>/dev/null; then
      warn "Sinal Wi-Fi fraco ($sinal%). Numa linha de 1 Gbps espera 10-80 Mbps reais."
    fi
  fi
elif [ "$OS" = "Darwin" ]; then
  if tem airport; then
    ap=$(airport -I 2>/dev/null | tr -d ' ')
    if echo "$ap" | grep -q 'state:running'; then
      WIFI_ATIVO=1
      chan=$(echo "$ap" | awk -F: '/channel/{print $2}')
      rssi=$(echo "$ap" | awk -F: '/agrCtlRSSI/{print $2}')
      sub "Wi-Fi: canal=$chan RSSI=$rssi dBm"
      warn "Estás em Wi-Fi. Para descarregar o BF6 e para medir a linha a sério, usa cabo Ethernet."
    fi
  fi
fi
[ "$WIFI_ATIVO" = "1" ] || ok "Sem Wi-Fi ativo detetado (ligação por cabo ou desligado)."

# Latência até ao router
GW=""
if tem ip; then GW=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}'); fi
if [ "$OS" = "Darwin" ]; then GW=$(route -n get default 2>/dev/null | awk '/gateway/{print $2}'); fi
if [ -n "$GW" ]; then
  sub "Gateway/router: $GW"
  if tem ping; then
    m=$(ping -c 5 -W 2 "$GW" 2>/dev/null | awk -F'/' '/rtt|round-trip/{print $5}')
    [ -n "$m" ] && sub "Latência até ao router: ${m} ms"
    if [ -n "$m" ] && [ "${m%%.*}" -gt 5 ] 2>/dev/null; then
      warn "Latência até ao router alta (${m} ms). Em Wi-Fi o normal é 1-5 ms."
    fi
  fi
fi

# ───────────────────────────────────────────────────────────────────────────
titulo "2. Proxies e interceção ativa (suspeito nº 1)"
PROXY=0
if [ "$OS" = "Linux" ] && tem gsettings; then
  modo=$(gsettings get org.gnome.system.proxy mode 2>/dev/null)
  h=$(gsettings get org.gnome.system.proxy.http host 2>/dev/null | tr -d "'")
  p_num=$(gsettings get org.gnome.system.proxy.http port 2>/dev/null)
  sub "gsettings org.gnome.system.proxy mode=$modo  http=$h:$p_num"
  if [ "$modo" = "'manual'" ] && { [ "$h" = "127.0.0.1" ] || [ "$h" = "localhost" ]; }; then
    PROXY=1
    warn "PROXY DE SISTEMA (GNOME) ligado para $h:$p_num. Se o processo que o criou (Traffic Inspector do OmniRoute, mitmproxy, Fiddler, ZAP) já morreu — ou rebootaste — o tráfego fica pendurado. Desliga: gsettings set org.gnome.system.proxy mode 'none'  (ou no painel do OmniRoute: Traffic Inspector > Restore system proxy)."
  fi
fi
if [ "$OS" = "Darwin" ]; then
  sc=$(scutil --proxy 2>/dev/null)
  echo "$sc" | grep -E 'HTTPEnable|HTTPProxy|HTTPPort|HTTPSEnable|HTTPSProxy|HTTPSPort|ProxyAutoConfig' | sed 's/^/      /'
  if echo "$sc" | grep -qE 'HTTPEnable *: *1|HTTPSEnable *: *1'; then
    PROXY=1
    warn "Proxy de sistema (macOS) ativo. Desliga em Preferências do Sistema > Rede > Detalhes > Proxies, ou: networksetup -setwebproxystate Wi-Fi off && networksetup -setsecurewebproxystate Wi-Fi off"
  fi
fi
for v in HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy; do
  val="$(eval echo \$$v)"
  [ -n "$val" ] || continue
  sub "$v = $val"
  case "$val" in *127.0.0.1*|*localhost*) PROXY=1; warn "$v aponta para localhost — se o proxy morreu, tudo o que use esta variável arrasta ou falha." ;; esac
done
[ -s /etc/environment ] && grep -iE 'proxy' /etc/environment | sed 's/^/      /' >/dev/null 2>&1
[ "$PROXY" = "0" ] && ok "Nenhum proxy de sistema detetado (gsettings/scutil/variáveis limpos)."

# Portas de proxy à escuta
if tem ss; then
  escuta=$(ss -ltnpH 2>/dev/null | grep -E ':(8080|8888|9090|3128|8118|7890|1080)\b')
elif tem lsof; then
  escuta=$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -E ':(8080|8888|9090|3128|8118|7890|1080)\b')
fi
[ -n "${escuta:-}" ] && printf '%s\n' "$escuta" | sed 's/^/  · porta proxy à escuta: /'

# ───────────────────────────────────────────────────────────────────────────
titulo "3. DNS"
if [ -r /etc/resolv.conf ]; then grep -vE '^\s*#|^\s*$' /etc/resolv.conf | sed 's/^/      /'; fi
if [ "$OS" = "Darwin" ] && tem scutil; then scutil --dns 2>/dev/null | grep 'nameserver\[' | sort -u | head -5 | sed 's/^/      /'; fi
if tem dig; then
  for alvo in speed.cloudflare.com store.steampowered.com; do
    t=$(dig +time=3 +tries=1 "$alvo" A 2>/dev/null | awk '/Query time/{print $4}')
    ips=$(dig +short +time=3 +tries=1 "$alvo" A 2>/dev/null | head -2 | tr '\n' ' ')
    if [ -n "$t" ]; then
      sub "Resolve $alvo -> ${ips}(${t} ms)"
      [ "$t" -gt 300 ] 2>/dev/null && warn "Resolução DNS lenta para $alvo (${t} ms)."
    else
      warn "Não consegui resolver $alvo via dig."
    fi
  done
else
  info "dig não instalado — verificação de tempo de DNS saltada (apt/dnf install dnsutils, ou brew install bind)."
fi

# ───────────────────────────────────────────────────────────────────────────
titulo "4. Latência, perda de pacotes e bufferbloat"

# args de contagem/espera diferentes entre Linux e macOS
ping_stats() { # $1 = alvo, $2 = nº pacotes, saída: "perda min media max jitter"
  local alvo="$1" n="$2" saida vals perda min media max jit i ant atu d
  if [ "$OS" = "Darwin" ]; then
    saida=$(ping -c "$n" -i 0.3 -W 2000 "$alvo" 2>/dev/null)
  else
    saida=$(ping -c "$n" -i 0.3 -W 2 "$alvo" 2>/dev/null)
  fi
  [ -n "$saida" ] || { echo ""; return; }
  vals=$(printf '%s\n' "$saida" | sed -n 's/.*time=\([0-9.]*\).*/\1/p')
  [ -n "$vals" ] || { echo "100 0 0 0 0"; return; }
  perda=$(printf '%s\n' "$saida" | sed -n 's/.* \([0-9.]*\)% packet loss.*/\1/p' | head -1)
  [ -n "$perda" ] || perda=$(awk -v n="$n" -v r="$(printf '%s\n' "$vals" | wc -l)" 'BEGIN{printf "%.1f", 100*(n-r)/n}')
  min=$(printf '%s\n' "$vals" | sort -n | head -1)
  max=$(printf '%s\n' "$vals" | sort -n | tail -1)
  media=$(printf '%s\n' "$vals" | awk '{s+=$1; c++} END{printf "%.0f", s/c}')
  jit=0; ant="";
  for atu in $vals; do
    if [ -n "$ant" ]; then
      d=$(awk -v a="$ant" -v b="$atu" 'BEGIN{x=a-b; if(x<0)x=-x; print x}')
      jit=$(awk -v j="$jit" -v d="$d" 'BEGIN{print j+d}')
    fi
    ant="$atu"
  done
  jit=$(awk -v j="$jit" -v c="$(printf '%s\n' "$vals" | wc -l)" 'BEGIN{printf "%.0f", j/(c-1+0.0001)}')
  echo "$perda $min $media $max $jit"
}

BASE_MEDIA=""; BASE_ALVO=""
for par in "1.1.1.1|Cloudflare (1.1.1.1)" "8.8.8.8|Google DNS (8.8.8.8)" "store.steampowered.com|Steam (store.steampowered.com)"; do
  alvo="${par%%|*}"; nome="${par##*|}"
  read -r perda min media max jit <<<"$(ping_stats "$alvo" 15)"
  if [ -z "$media" ] || [ "${perda%%.*}" = "100" ]; then
    warn "Sem resposta de $nome (ICMP bloqueado pela rede/ISP, ou alvo inacessível) — não é possível medir latência/perda aqui."
    continue
  fi
  printf '  · %-32s min %s ms | média %s ms | max %s ms | jitter %s ms | perda %s%%\n' "$nome" "$min" "$media" "$max" "$jit" "$perda"
  if [ "$alvo" = "1.1.1.1" ]; then BASE_MEDIA="$media"; BASE_ALVO="$alvo"; fi
  if [ -z "$BASE_MEDIA" ] && [ "$alvo" = "8.8.8.8" ]; then BASE_MEDIA="$media"; BASE_ALVO="$alvo"; fi
  awk -v p="$perda" 'BEGIN{exit !(p>1)}' && warn "Perda de pacotes de ${perda}% em $nome — ligação instável."
  awk -v j="$jit" 'BEGIN{exit !(j>30)}' && warn "Jitter alto (${jit} ms) em $nome — mau para jogos e para o próprio TCP."
done

if tem curl && [ -n "$BASE_MEDIA" ] && [ "$SEM_DISCO" = "0" ]; then
  sub "A saturar a linha durante ~10 s para medir o bufferbloat (referência: $BASE_ALVO)..."
  curl -s -L -o /dev/null --connect-timeout 8 --max-time 25 \
    'https://speed.cloudflare.com/__down?bytes=400000000' &
  CURL_PID=$!
  sleep 3
  read -r perda2 _ media2 _ _ <<<"$(ping_stats "$BASE_ALVO" 12)"
  kill "$CURL_PID" 2>/dev/null
  wait "$CURL_PID" 2>/dev/null
  if [ -n "$media2" ]; then
    delta=$(awk -v a="$media2" -v b="$BASE_MEDIA" 'BEGIN{printf "%.0f", a-b}')
    sub "Em carga: média ${media2} ms (repouso ${BASE_MEDIA} ms → +${delta} ms)"
    if [ "${delta%%.*}" -gt 200 ] 2>/dev/null; then
      warn "BUFFERBLOAT grave: +${delta} ms quando a linha enche. Ativa SQM/QoS (fq_codel/cake) no router ou limita o download a ~90% da linha."
    elif [ "${delta%%.*}" -gt 80 ] 2>/dev/null; then
      warn "Bufferbloat moderado: +${delta} ms sob carga. Limitar a velocidade do download ajuda muito."
    else
      ok "Bufferbloat controlado (+${delta} ms sob carga)."
    fi
  fi
fi

# ───────────────────────────────────────────────────────────────────────────
titulo "5. MTU (fragmentação de pacotes)"
if tem ping; then
  MTU_OK=0
  rc=1
  for tam in 1472 1464 1452 1400 1300 1272 548; do
    if [ "$OS" = "Darwin" ]; then
      ping -c 1 -D -s "$tam" -W 1500 1.1.1.1 >/dev/null 2>&1
      rc=$?
    else
      ping -c 1 -M do -s "$tam" -W 2 1.1.1.1 >/dev/null 2>&1
      rc=$?
    fi
    if [ "$rc" -eq 0 ]; then
      mtu=$((tam + 28))
      sub "Payload de $tam bytes sem fragmentar passou -> MTU = $mtu"
      if [ "$mtu" -lt 1500 ]; then warn "MTU reduzido ($mtu em vez de 1500 — PPPoE/VPN/túnel). Confirma no router."; else ok "MTU em 1500 (ideal)."; fi
      MTU_OK=1; break
    fi
  done
  [ "$MTU_OK" = "0" ] && warn "Nenhum payload passou (mesmo pequeno) — ICMP com DF bloqueado ou linha com problemas."
fi

# ───────────────────────────────────────────────────────────────────────────
titulo "6. Velocidade real de download"
info "Plano declarado: 1000 Mbps de download / 100 Mbps de upload."
if ! tem curl; then
  warn "curl não instalado — não consigo medir velocidade real."
else
  MELHOR=0; MELHOR_NOME=""
  medir() { # $1=nome $2=url
    local nome="$1" url="$2" t b mbps
    # uma única transferência: bytes e tempo vêm da mesma medição
    local raw
    raw=$(curl -s -L -o /dev/null --connect-timeout 8 --max-time 10 -w '%{size_download} %{time_total}' "$url" 2>/dev/null)
    b=${raw%% *}
    t=${raw##* }
    [ -n "$b" ] || b=0
    [ -n "$t" ] || t=0
    if [ "${b%.*}" -le 0 ] 2>/dev/null; then
      erro "$nome: não recebi dados (bloqueado, offline ou URL indisponível)."
      return
    fi
    mbps=$(awk -v b="$b" -v t="$t" 'BEGIN{ if(t<=0) t=0.001; printf "%.1f", b*8/1000000/t }')
    printf '  · %-32s %8s Mbps  (%s MB em %s s)\n' "$nome" "$mbps" "$(awk -v b="$b" 'BEGIN{printf "%.1f", b/1048576}')" "$t"
    if awk -v m="$mbps" -v best="$MELHOR" 'BEGIN{exit !(m>best)}'; then MELHOR="$mbps"; MELHOR_NOME="$nome"; fi
  }
  medir "Cloudflare (100 MB)"        'https://speed.cloudflare.com/__down?bytes=100000000'
  medir "Hetzner Alemanha (100 MB)"  'https://speed.hetzner.de/100MB.bin'
  medir "Steam CDN (Cloudflare)"     'https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe'

  if [ -n "$MELHOR_NOME" ]; then
    DL_MBPS="$MELHOR"
    sub "Melhor resultado: $MELHOR_NOME = $MELHOR Mbps ($(awk -v m="$MELHOR" 'BEGIN{printf "%.1f", m/8}') MB/s)"
    if awk -v m="$MELHOR" 'BEGIN{exit !(m<50)}'; then
      erro "Nenhuma fonte passou dos 50 Mbps. A ligação real está longe do plano — o problema NÃO é do Steam."
    elif awk -v m="$MELHOR" 'BEGIN{exit !(m<300)}'; then
      warn "Máximo de $MELHOR Mbps numa linha de 1 Gbps. Aponta para Wi-Fi, porta/cabo a 100M, ou router sobrecarregado."
    else
      ok "Ligação a $MELHOR Mbps — linha saudável. Se o Steam continua lento, o gargalo é do Steam ou do disco."
    fi
  fi
  info "O Steam instala centenas de ficheiros pequenos: a velocidade útil é sempre menor que este teste."
fi

# ───────────────────────────────────────────────────────────────────────────
titulo "7. Interceção TLS: /etc/hosts, certificados e restos de TPROXY"
if [ -r /etc/hosts ]; then
  ativas=$(grep -vE '^\s*#|^\s*$' /etc/hosts)
  if [ -n "$ativas" ]; then
    sub "Entradas ativas em /etc/hosts:"
    printf '%s\n' "$ativas" | sed 's/^/      /'
    if printf '%s\n' "$ativas" | grep -qiE 'anthropic|openai|chatgpt|claude|gemini|googleapis|cloudcode|copilot|antigravity|zed|cursor|omniroute|steam|akamai'; then
      warn "Há hosts de serviços/agentes/CDN redirecionados no /etc/hosts (interceção ativa ou restos dela). Limpa essas linhas ou usa o botão 'Repair' do OmniRoute."
    fi
  else
    ok "/etc/hosts sem entradas ativas."
  fi
fi
if [ "$OS" = "Darwin" ]; then
  if security find-certificate -a -c "OmniRoute" /Library/Keychains/System.keychain >/dev/null 2>&1; then
    warn "Certificado raiz de interceção (OmniRoute) instalado no keychain do sistema. Remove-o para deixar de intercetar TLS."
  else
    ok "Sem certificado raiz de interceção no keychain."
  fi
else
  achou=0
  for f in /usr/local/share/ca-certificates/*.crt /etc/pki/ca-trust/source/anchors/*.crt; do
    [ -e "$f" ] || continue
    if grep -qiE 'omniroute|mitmproxy|mitm|fiddler|charles' "$f" 2>/dev/null; then warn "Certificado de interceção instalado: $f"; achou=1; fi
  done
  [ "$achou" = "0" ] && ok "Sem certificados de interceção nas pastas de CA do sistema."
fi
if [ "$OS" = "Linux" ]; then
  if tem nft && nft list ruleset 2>/dev/null | grep -qi 'tproxy\|mangle'; then
    warn "há regras nftables com tproxy/mangle ativas — se o Traffic Inspector do OmniRoute já não está a correr, isto pode estar a desviar tráfego. Limpa com o botão 'Repair' do OmniRoute."
  fi
  if tem iptables && iptables -t mangle -S 2>/dev/null | grep -q 'TPROXY'; then
    warn "há regras iptables -t mangle com TPROXY — restos de captura. Corre: iptables -t mangle -S (para ver) e limpa as regras TPROXY."
  fi
fi

# ───────────────────────────────────────────────────────────────────────────
titulo "8. Steam"
STEAM_DIR=""
for c in "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/Library/Application Support/Steam" "$HOME/snap/steam/common/.local/share/Steam"; do
  [ -d "$c" ] && STEAM_DIR="$c" && break
done
if [ -n "$STEAM_DIR" ]; then
  sub "Instalação: $STEAM_DIR"
  cfg="$STEAM_DIR/config/config.vdf"
  if [ -f "$cfg" ]; then
    if grep -qiE '"Rate"|"Throttle"|DownloadThrottle' "$cfg"; then
      sub "Limites encontrados em config.vdf:"
      grep -iE '"Rate"|"Throttle"|DownloadThrottle' "$cfg" | sed 's/^/      /'
      warn "O Steam guarda aqui o limite de largura de banda. Se estiver por volta de 10-15 Mbps (~1,3 MB/s), é exatamente o que estás a ver. Desliga em Steam > Definições > Downloads."
    else
      ok "Sem limite de largura de banda configurado no Steam."
    fi
  fi
  for lf in "$STEAM_DIR/steamapps/libraryfolders.vdf" "$STEAM_DIR/config/libraryfolders.vdf"; do
    [ -f "$lf" ] || continue
    sub "Pastas de biblioteca:"
    grep -oE '"path"\s+"[^"]+"' "$lf" | sed 's/.*"path"\s*//' | tr -d '"' | sed 's/^/      /'
    break
  done
  pgrep -i steam >/dev/null 2>&1 && sub "Steam está em execução agora."
else
  info "Instalação do Steam não encontrada."
fi

# ───────────────────────────────────────────────────────────────────────────
titulo "9. Escrita em disco (onde os jogos instalam)"
if [ "$SEM_DISCO" = "1" ]; then
  info "Teste de disco saltado (--sem-disco)."
elif ! tem dd; then
  info "dd não disponível — teste de disco saltado."
else
  MB=512
  for d in "${STEAM_DIR:-}" "$HOME"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    f="$d/.omniroute_speedtest.tmp"
    res=$(dd if=/dev/zero of="$f" bs=1m count="$MB" 2>&1 | tail -1)
    if [ -f "$f" ]; then
      mbps_d=$(printf '%s\n' "$res" | sed -n 's/.*, \([0-9.]*\) MB\/s.*/\1/p')
      [ -n "$mbps_d" ] || mbps_d=$(printf '%s\n' "$res" | awk '{for(i=1;i<=NF;i++) if($i ~ /MB\/s/) print $(i-1)}')
      rm -f "$f"
      [ -n "$mbps_d" ] && {
        printf '  · Escrita em %-40s %s MB/s\n' "$d" "$mbps_d"
        if awk -v m="$mbps_d" 'BEGIN{exit !(m<60)}'; then
          warn "Disco $d escreve a $mbps_d MB/s — isto limita qualquer download a ~$(awk -v m="$mbps_d" 'BEGIN{printf "%.1f", m*8/1000}') Gbps. HDD, disco quase cheio, ou criptografia pesada?"
        fi
      }
    else
      erro "Não consegui escrever em $d (permissões, disco cheio ou avariado?)."
    fi
  done
fi

# ───────────────────────────────────────────────────────────────────────────
titulo "RESUMO"
if [ ${#FALHAS[@]} -eq 0 ] && [ ${#ALERTAS[@]} -eq 0 ]; then
  ok "Nenhum problema detetado nesta passagem."
else
  if [ ${#FALHAS[@]} -gt 0 ]; then
    echo "  FALHAS (${#FALHAS[@]}):"
    for f in "${FALHAS[@]}"; do echo "   ✗ $f"; done
  fi
  if [ ${#ALERTAS[@]} -gt 0 ]; then
    echo "  ATENÇÃO (${#ALERTAS[@]}):"
    for a in "${ALERTAS[@]}"; do echo "   ! $a"; done
  fi
fi

echo
if [ -z "$DL_MBPS" ]; then
  echo "  VEREDITO: não consegui medir a velocidade de download (sem curl, sem rede ou tudo bloqueado)."
  echo "            Confirma primeiro que esta máquina navega; depois volta a correr o diagnóstico."
fi
if [ -n "$DL_MBPS" ]; then
  if awk -v m="$DL_MBPS" 'BEGIN{exit !(m<50)}'; then
    echo "  VEREDITO: a linha entrega menos de 50 Mbps — o problema é de rede/PC, não do Steam nem do BF6."
    echo "            Ordem de ataque: cabo em vez de Wi-Fi -> reiniciar router -> testar com outro PC -> chamar o ISP."
  elif awk -v m="$DL_MBPS" 'BEGIN{exit !(m<300)}'; then
    echo "  VEREDITO: entre 50 e 300 Mbps. Utilizável, mas abaixo do plano — foca-te em Wi-Fi/cabo/router/QoS."
  else
    echo "  VEREDITO: linha saudável (>300 Mbps). Se o Steam continua a 10 Mbit/s, o gargalo é do Steam ou do disco."
  fi
fi
echo
echo "  Relatório guardado em: $LOG"
echo "  Ações detalhadas: docs/help/pt-PT/README.md"
echo
