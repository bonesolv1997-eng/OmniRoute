#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# 3b/5b (extrato para o kit PT-PT) — chip de rede, driver e limites de software
#   Uso:  bash checar-nic-macos-linux.sh       (nao precisa de sudo)
#
#   3b. macOS: modelo da NIC, driver kext, e a armadilha especifica dos Apple
#       Silicon — com um adaptador USB de 2,5G o macOS faz bridging com a
#       interface Wi-Fi e o trafego de rede passa a TCP sobre Wi-Fi, limitando
#       o download. Verifica-se com pktap/interfaces em modo bridge.
#   5b. Linux: driver, modelo, EEE/Green Ethernet (ethtool), erros de descarte,
#       MTU e estado do link.
# ---------------------------------------------------------------------------

OS="$(uname -s)"
tem() { command -v "$1" >/dev/null 2>&1; }

echo
if [ "$OS" = "Darwin" ]; then
  echo "══════════════════════════════════════════════════════════════════════════════"
  echo "  3b. Placa de rede (macOS)"
  echo "══════════════════════════════════════════════════════════════════════════════"
  # Interfaces ativas (exceto loopback)
  for i in $(ifconfig -l); do
    [ "$i" = "lo0" ] && continue
    info=$(ifconfig "$i" 2>/dev/null | grep 'status: active')
    [ -n "$info" ] || continue
    media=$(ifconfig "$i" 2>/dev/null | sed -n 's/.*media: \(.*\)/\1/p' | head -1)
    mtu=$(ifconfig "$i" 2>/dev/null | sed -n 's/.*mtu \([0-9]*\).*/\1/p' | head -1)
    tipo="desconhecido"
    case "$i" in
      en*) tipo="Ethernet/Thunderbolt ou adaptador USB" ;;
      utun*|ipsec*|ppp*|tun*|tap*) tipo="túnel/VPN" ;;
      bridge*) tipo="bridge (pode ser o bridge do Wi-Fi)" ;;
      awdl*|llw*|anpi*) tipo="Wi-Fi interno (Apple)" ;;
    esac
    echo "  · $i  $tipo  media=\"$media\"  mtu=$mtu"
    if [ -n "$mtu" ] && [ "$mtu" -lt 1500 ] 2>/dev/null; then
      echo "      [ATENÇÃO] MTU $mtu nesta interface — se não é VPN, algo está a reduzir MTU."
    fi
    if [ -n "$media" ]; then
      case "$media" in
        *100baseTX*|*10baseT*|*100baseT*)
          echo "      [ATENÇÃO] A interface negociou 100 Mbps — teto de ~94 Mbps de download."
          ;;
        *2500baseT*|*5000baseT*|*10GbaseT*)
          echo "      [i] Intervalo de 2,5G/5G/10G ativo."
          ;;
      esac
    fi
  done

  # Armadilha dos Apple Silicon: adaptador USB + Wi-Fi -> TCP sobre Wi-Fi
  if [ "$(uname -m)" = "arm64" ]; then
    bridge_wifi=$(netstat -rn 2>/dev/null | awk '/^default/{print $NF; exit}')
    wifi_if=""
    for i in $(ifconfig -l); do
      case "$i" in en*|bridge*) if ifconfig "$i" 2>/dev/null | grep -q 'status: active' && networksetup -listallhardwareports 2>/dev/null | grep -A2 "$i" | grep -qi 'wi-fi'; then wifi_if="$i"; fi ;; esac
    done
    if [ -n "$wifi_if" ]; then
      echo "  [i] Wi-Fi ativo ($wifi_if). Em Apple Silicon, se usas um adaptador USB/Thunderbolt de 2,5G, o macOS cria um bridge com o Wi-Fi e o tráfego TCP passa a 'andar por cima' do Wi-Fi — a velocidade do cabo fica limitada pela ligação sem fios."
      echo "      Confirma: Preferências > Rede (ordem dos serviços), ou desliga o Wi-Fi e volta a medir."
    fi
    if [ -n "$bridge_wifi" ]; then
      echo "  [i] Rota por omissão via $bridge_wifi — confirma se não é um bridge que inclui o Wi-Fi."
    fi
  fi

  # Drivers: kexts de NIC de terceiros (Killer/Intel/Realtek instalados como kext)
  echo
  echo "  · Kexts de rede instalados (terceiros):"
  kextstat 2>/dev/null | awk '{print $6}' | grep -iE 'intel|realtek|killer|aquantia|aquantia|marvell|broadcom' | sort -u | sed 's/^/      /' || true
  for caminho in /Library/Extensions /System/Library/Extensions; do
    [ -d "$caminho" ] || continue
    find "$caminho" -maxdepth 1 -iname '*Intel*.kext' -o -maxdepth 1 -iname '*Killer*.kext' -o -maxdepth 1 -iname '*Realtek*.kext' 2>/dev/null | sed 's/^/      /'
  done

  echo
  echo "  · Se usas adaptador USB de 2,5G (Realtek RTL8156, Aquantia, etc.):"
  echo "      - confirma que o adaptador não está a negociar 100 Mbps (linha acima);"
  echo "      - desliga o Wi-Fi para testar a velocidade real do cabo;"
  echo "      - adaptadores USB baratos partilham o bus USB com discos/câmaras — tira-os do mesmo hub."
else
  echo "══════════════════════════════════════════════════════════════════════════════"
  echo "  5b. Placa de rede (Linux)"
  echo "══════════════════════════════════════════════════════════════════════════════"
  tem ethtool || echo "  [i] ethtool não instalado (apt install ethtool) — análise de driver/EEE limitada."
  for i in /sys/class/net/*; do
    dev=$(basename "$i")
    [ "$dev" = "lo" ] && continue
    driver=$(basename "$(readlink -f "$i/device/driver" 2>/dev/null)" 2>/dev/null)
    [ -n "$driver" ] || driver="(virtual)"
    vendor=$(cat "$i/device/vendor" 2>/dev/null)
    modelo=""
    if [ -n "$vendor" ]; then
      case "$vendor" in
        0x8086) modelo="Intel" ;;
        0x10ec) modelo="Realtek" ;;
        0x1969|0x196a) modelo="Atheros/Qualcomm" ;;
        0x14e4) modelo="Broadcom" ;;
        0x1d6a) modelo="Aquantia/Marvell" ;;
      esac
    fi
    echo "  · $dev  [$modelo $vendor]  driver=$driver"
    if [ -d "$i/wireless" ]; then
      echo "      [i] interface sem fios"
      if tem iw; then
        iw dev "$dev" link 2>/dev/null | sed -e 's/^/      /' -e '/^      $/d'
      fi
    fi
    if tem ethtool; then
      sup=$(ethtool "$dev" 2>/dev/null | sed -n 's/.*Supported link modes: *//p')
      neg=$(ethtool "$dev" 2>/dev/null | sed -n 's/.*Speed: *//p' | head -1)
      [ -n "$sup" ] && echo "      Modos suportados: $sup"
      [ -n "$neg" ] && echo "      Negociado agora: $neg"
      case "$neg" in
        100Mb/s*|10Mb/s*)
          echo "      [ATENÇÃO] Link a $neg — teto de ~94 Mbps. Cabo CAT5, porta 100M do router, ou driver."
          ;;
      esac
      for eee in 'Energy-Efficient Ethernet' 'EEE' 'Green Ethernet' 'Low Power Idle'; do
        linha=$(ethtool "$dev" 2>/dev/null | grep -i "$eee")
        if [ -n "$linha" ]; then
          echo "      $linha"
          case "$linha" in
            *enabled*|*Enabled*|*on) echo "      [ATENÇÃO] '$eee' LIGADO em $dev — em NICs Intel (I225/I226/I219) causa quedas de link e velocidade errática. Desliga: sudo ethtool --set-eee $dev eee off  (ou regra udev/NetworkManager)." ;;
          esac
        fi
      done
      mtu=$(cat "$i/mtu" 2>/dev/null)
      [ -n "$mtu" ] && echo "      MTU: $mtu"
    fi
    rx_err=$(cat "$i/statistics/rx_errors" 2>/dev/null)
    rx_drop=$(cat "$i/statistics/rx_dropped" 2>/dev/null)
    tx_drop=$(cat "$i/statistics/tx_dropped" 2>/dev/null)
    soma=$(( ${rx_err:-0} + ${rx_drop:-0} + ${tx_drop:-0} ))
    if [ "$soma" -gt 0 ]; then
      echo "      [ATENÇÃO] rx_errors=$rx_err rx_dropped=$rx_drop tx_dropped=$tx_drop — cabo/porta com problemas ou link saturado."
    fi
    # Filtros de tráfego (traffic control) que limitam largura de banda
    if [ "$dev" != "lo" ]; then
      if tem tc; then
        qdisc=$(tc qdisc show dev "$dev" 2>/dev/null | head -3)
        case "$qdisc" in
          *tbf*|*htb*|*netem*|*cake*|*fq_codel*) echo "      [i] qdisc de shaping ativo: $(printf '%s' "$qdisc" | tr '\n' ' ')" ;;
        esac
        case "$qdisc" in
          *tbf*|*htb*|*netem*) echo "      [ATENÇÃO] Há shaping (tbf/htb/netem) em $dev — confirma que não tem rate limit antigo (exporta 'tc qdisc show dev $dev' e 'tc class show dev $dev')." ;;
        esac
      fi
    fi
  done
  if tem nmcli; then
    echo
    echo "  · Ligações com limites de velocidade configurados (networkmanager):"
    encontrou=0
    for c in $(nmcli -t -f NAME connection show 2>/dev/null); do
      lim=$(nmcli -t -f 802-11-wireless.band,ipv4.dns connection show "$c" 2>/dev/null)
      lim2=$(nmcli -t connection show "$c" 2>/dev/null | grep -iE 'rate|bandwidth|limit|tx-rate|rx-rate' || true)
      if [ -n "$lim2" ]; then echo "      $c: $lim2"; encontrou=1; fi
    done
    [ "$encontrou" = "0" ] && echo "      (nada encontrado)"
  fi
fi
echo
echo "  Corre agora o kit principal (diagnostico-net-lenta.sh) para a medição completa."
echo
