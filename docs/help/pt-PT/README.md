# A minha net ficou má — guia de diagnóstico (PT-PT)

> Caso concreto: **Battlefield 6 a atualizar na Steam, 4,7 GB, 1 hora** numa ligação de
> **1000 Mbps de download / 100 Mbps de upload**.

## O número que importa

| | Valor |
|---|---|
| 4,7 GB em 1 hora | **~10,4 Mbit/s** (≈1,3 MB/s) |
| O que a tua linha de 1 Gbps devia entregar | **~940 Mbit/s** reais (≈118 MB/s) |
| Tempo esperado para 4,7 GB | **~40 segundos** de transferência pura; 1–3 minutos com a descompressão do Steam |
| Quanto do teu plano estás a usar | **~1 %** |

Ou seja: não é "net má", é algo a **estrangular a ~10 Mbit/s**. Um número redondo como este
(10 Mbps) quase nunca é "a Internet a ser lenta" — é quase sempre **um limite configurado
em algum sítio**: limite do Steam, QoS do router, software de fabricante, ou um proxy no meio.

> Nota: o Steam instala jogos com centenas de ficheiros pequenos, portanto a velocidade
> **útil** é sempre bastante menor que um teste de 100 MB seguidos (costuma ser 30–60 % da
> velocidade da linha em CPUs normais). Mesmo assim, 10 % é anormal.

---

## 1. Faz isto primeiro (2 minutos, sem instalar nada)

1. **Passa para cabo Ethernet.** Wi-Fi 2,4 GHz dá 10–80 Mbps reais; é a causa nº 1 de
   "a net ficou má" sem ninguém mexer em nada.
2. **Fecha tudo o que use rede**: BT/torrents, OneDrive/Google Drive, Xbox app, Epic,
   backups, streaming 4K, VPN, clientes de email pesados.
3. **Corre o diagnóstico deste kit** (não altera nada, só mede):

```powershell
# Windows (na pasta deste ficheiro)
powershell -ExecutionPolicy Bypass -File .\diagnostico-net-lenta.ps1
```

```bash
# macOS / Linux
bash diagnostico-net-lenta.sh
```

No fim ficas com um `diagnostico-rede-<data>.txt` com tudo o que foi medido — podes lê-lo
ou partilhá-lo com quem te estiver a ajudar.

4. **Enquanto o Steam está a descarregar**, abre o **Monitor de Recursos** (Win+R →
   `resmon`) e olha para três coisas ao mesmo tempo:
   - **Rede** (bytes/s) → se a rede está baixa mas o disco a 100 %, o gargalo é o disco;
   - **Disco** → "% de tempo ativo" e "maior tempo de resposta";
   - **CPU** → um só núcleo a 100 % pode limitar a descompressão do Steam.

Este passo de 30 segundos identifica a maioria dos casos sozinho.

---

## 2. Como interpretar os resultados

| Sintoma medido | Causa provável | O que fazer |
|---|---|---|
| Download < 50 Mbps em **todos** os CDNs, com cabo | Wi-Fi/porta a 100M, router, ISP | Ver secções 4, 5 e 6 |
| Um CDN rápido e outro lento (ex.: 800 vs 40 Mbps) | Peering do ISP para essa rede | Mudar DNS (1.1.1.1), testar em hora diferente |
| Download bom (>500 Mbps) mas Steam a 10 Mbps | **Steam** ou **disco/CPU** | Secções 3 e 7 |
| Download bom, mas a casa "fica sem net" durante o download | **Bufferbloat** | Secção 5 (QoS/SQM no router) |
| Ping normal, jitter > 30 ms, perda > 1 % | Ligação instável (Wi-Fi/cabo/router/ISP) | Cabo, reiniciar router, ISP |
| Latência até ao **router** > 5 ms | Wi-Fi fraco ou router sobrecarregado | Canal 5 GHz, menos dispositivos, reiniciar |
| MTU < 1500 | PPPoE/VPN/túnel mal configurado | Ajustar MTU no router/PC para 1492 |
| Proxy a apontar para `127.0.0.1` | **Software de captura de tráfego** (ex.: OmniRoute) | Secção 8 |
| Disco < 60 MB/s | HDD, disco cheio, ou porta SATA antiga | Instalar o jogo em NVMe |

---

## 3. Steam: os clássicos (a causa mais comum de "exatamente ~10 Mbit/s")

1. **Limite de largura de banda do Steam**
   Terminal Steam (`steam://open/settings` ou menu) → **Definições → Downloads**:
   - "**Limitar largura de banda de download**" / *Limit bandwidth to* → **desligado / ilimitado**.
   - "Permitir downloads durante o jogo" → ligado ou desligado (não limita a velocidade, mas
     o Steam suspende e retoma constantemente → transferências eternas).
   - **"Throttle downloads while streaming"** → desligado.
2. **Região de download** → escolhe a mais próxima e mede:
   *Portugal/Lisboa/Espanha → se estiver exótico (ex.: Alemanha, EUA) isso explica tudo.*
3. **Verificação de ficheiros**: se o download "anda 2 segundos e para 5", pode estar a fazer
   verify+patch. Nas propriedades do jogo → Ficheiros instalados → **Verificar integridade**;
   deixar acabar uma vez resolve.
4. **Disco de destino**: HD mecânico a 100 % de utilização no resmon = gargalo. Mover a
   biblioteca para um SSD/NVMe (Steam → Definições → Armazenamento → adicionar unidade).
5. **Cache/estado podre do Steam**: fechar Steam → `Steam\steamapps\downloading` e
   `Steam\config\config.vdf` (faz backup antes) → reabrir. Em último caso,
   `Steam → Configurações → Downloads → Limpar cache de download`.
6. **Velocidade do próprio servidor de conteúdo**: em dias de lançamento (BF6) os CDNs
   ficam saturados. Testa à noite/de manhã: se muda drasticamente, não é a tua net.

O script deste kit lê o `config.vdf` e mostra-te **exatamente** os limites configurados.

---

## 4. Wi-Fi, cabo e camada física

- **Wi-Fi**: usa 5/6 GHz, canal limpo (analisa com o WiFi Analyzer), largura 80 MHz.
  Sinal abaixo de 60 % = 10–80 Mbps garantidos. Se o router está longe, **cabo** ou
  adaptador Wi-Fi decente — não há software que resolva isto.
- **Cabo/portas**: a porta de rede negocia a velocidade **em comum**. Um cabo CAT5
  danificado, um keystone mal cravado, um switch de 100 Mbps ou uma porta de router a
  100 Mbps travam tudo em ~94 Mbps. O script mostra a velocidade negociada (`LinkSpeed`).
  **1 Gbps precisa de CAT5e/CAT6 com os 8 fios ligados.**
- **Powerline/PLC/repetidores**: 90 % das vezes degradam a linha (PLC de 1 Gbps na caixa
  = 30–60 Mbps reais). Prefere cabo direto ou Mesh com backhaul dedicado.
- **Porta de 2,5 GbE**: se tens router 2,5G ou 10G, confirma que o PC não está ligado a uma
  porta 1G com cabo mau.

---

## 5. O router e o ISP (onde o "bufferbloat" costuma estar)

- **Bufferbloat** (a latência dispara quando a linha enche): é o que faz "a net ficar má"
  exatamente durante downloads grandes. Mede com o Waveform Bufferbloat Test ou com o
  nosso script. **Solução real**: ativar **SQM/QoS** no router (fq_codel/cake, ou
  "QoS adaptativo") e limitar o download a ~90 % da linha — parece contra-intuitivo, mas a
  casa toda fica utilizável e o download não perde velocidade útil.
- **QoS/Bandwidth control de fabricante**: muitos routers de operador têm perfis de jogo
  que limitam a bandwidth por dispositivo. Se existe um perfil para o teu PC com 10 Mbps,
  **é literalmente o teu sintoma**.
- **Reiniciar o router** (o clássico "desliga da tomada 30 s"): resolve NAT/PPPoE empancado
  e sessões saturadas. Faz isto quando fizeste muitos torrents.
- **Testar a mesma coisa no telemóvel, por Wi-Fi 5 GHz** e por **5G/hotspot**: se o telemóvel
  voa e o PC não, o problema é do PC. Se os dois estão a 10 Mbps, é do router para fora.
- **Hora de ponta**: às 20h–23h, a rede do ISP (e o CDN do Steam) estão saturados. Mede fora
  de ponta para teres um valor de referência.
- **PPPoE**: se o operador usa PPPoE, tem MTU 1492 — o script deteta.
- **Upload de 100 Mbps**: se estiveres a fazer *seeding* de torrents, cloud backup, ou
  streaming, o upload saturado **destrói** o download (os ACKs do TCP ficam na fila). Fecha.

---

## 6. Windows: o que vale a pena mexer (e o que é mito)

**Vale a pena:**
- **Drivers NIC** atualizados (Intel/Realtek), e desligar **Energy Efficient Ethernet** /
  "Eco" nas propriedades do adaptador — em alguns chipsets isto corta velocidade.
- `netsh int tcp set global autotuninglevel=normal` (voltar ao auto-tune após VPN/proxies).
- **Otimização de Entrega do Windows** (Definições → Windows Update → Avançado): desligar
  "Limitar largura de banda" e não deixar um limite de % configurado.
- **Antivírus com inspeção HTTPS/SSL** (Kaspersky, ESET, Avast, Bitdefender, F-Secure)
  desencripta *tudo* — exatamente como um proxy MITM — e limita o débito. Testa com isso
  desligado; a diferença pode ser de centenas de Mbps.
- **Live Patch** do Windows Update a transferir ao mesmo tempo: o Monitor de Recursos mostra.
- **Nagle/TCP offload**: só mexer em último recurso e sempre um parâmetro de cada vez.

**Mitos (não percas tempo):**
- "Reservar 20 % da largura de banda" (`nbst`/Limit reservable bandwidth) — é um mito antigo,
  já não se aplica.
- "O Windows limita o TCP globalmente" — não limita.
- Aplicações "otimizadores de internet"/"game booster" tipo registry-tweakers: o mais comum
  é **piorarem** e várias instalam drivers/proxies próprios.

---

## 7. CPU e disco (o suspeito invisível)

Numa linha de 1 Gbps, 1 Gbps = **125 MB/s** de escrita contínua:

- **Disco**: se o Steam instala num HDD, ou num SSD quase cheio (SLC cache exausta), o teto
  é o disco, não a net. O script mede a escrita real (512 MB) nos discos onde o Steam
  instala. Abaixo de 60 MB/s = está a limitar o download a <0,5 Gbps.
- **CPU**: a 1 Gbps, o Steam faz descompressão/copy em vários passos; APUs e CPUs de 4
  núcleos antigos atingem 300–600 Mbps. Se vês um núcleo a 100 % durante o download, é CPU.
- **RAM**: com <8 GB e o jogo aberto, o Windows anda a fazer swap e o disco fica ocupado.
- **BitLocker** ligado: +carga de CPU/disco; ainda assim raramente abaixo de 300 MB/s.

---

## 8. OmniRoute / proxies de captura de tráfego (verificado no código deste repositório)

Se já usaste o **Traffic Inspector** ou o **AgentBridge** do OmniRoute nesta máquina, isto é
um suspeito de primeira ordem: qualquer proxy HTTP(S) aplicado a nível do sistema põe **todo**
o tráfego a passar por um processo local — e se esse processo morreu, foi reiniciado, ou
está a fazer inspeção TLS, a velocidade real desaba e algumas ligações ficam penduradas.

O que o OmniRoute faz, no código:

| Plataforma | O que é escrito | Ficheiro |
|---|---|---|
| Windows | `netsh winhttp set proxy 127.0.0.1:<porto>` (reverter: `netsh winhttp reset proxy`) | `src/mitm/inspector/systemProxyConfig.ts` |
| macOS | `networksetup -setwebproxy / -setsecurewebproxy` no serviço Wi-Fi | idem |
| Linux | `gsettings org.gnome.system.proxy mode manual` | idem |
| Windows/Linux/macOS | entradas no `hosts` a apontar hosts de agentes para o proxy | `src/mitm/dns/dnsConfig.ts` |
| Windows/Linux/macOS | certificado raiz de interceção TLS instalado no sistema | `src/mitm/cert/install.ts` |
| Linux | regras `iptables -t mangle` / `nft` (TPROXY) | `src/mitm/tproxy/` |

Dois detalhes importantes (estão no código):
- O proxy de sistema é revertido automaticamente ao fim de **30 minutos** por omissão
  (`INSPECTOR_SYSTEM_PROXY_GUARD_MINUTES`), mas esse estado vive **só em memória**
  (`src/lib/inspector/captureState.ts`). Se o processo do OmniRoute morrer ou reiniciares o
  PC com o proxy aplicado, **o proxy fica preso** a apontar para um porto morto.
- O botão de reparação (`POST /api/tools/agent-bridge/repair` → `repairMitm()`) reverte o
  `hosts`, remove o certificado e o proxy, mas a reversão do proxy só funciona **no mesmo
  processo que o aplicou** (o estado anterior perde-se num crash). Ou seja: depois de um
  crash, a limpeza tem de ser manual.

### Como limpar (na tua máquina)

```powershell
# Windows — proxy WinHTTP
netsh winhttp show proxy        # ver (se apontar a 127.0.0.1:8080, é isto)
netsh winhttp reset proxy       # limpar

# Windows — proxy de utilizador (Definições > Rede e Internet > Proxy: desligar)
# ou no painel do OmniRoute: Traffic Inspector -> "Restore system proxy"
```

```bash
# macOS
scutil --proxy
networksetup -setwebproxystate Wi-Fi off
networksetup -setsecurewebproxystate Wi-Fi off

# Linux (GNOME)
gsettings get org.gnome.system.proxy mode
gsettings set org.gnome.system.proxy mode 'none'

# Linux — restos de TPROXY (ver)
iptables -t mangle -S | grep TPROXY
nft list ruleset | grep -i tproxy
```

Depois:
- **`/etc/hosts`** (ou `C:\Windows\System32\drivers\etc\hosts`): remove as linhas que apontam
  hosts de IA/CDN para `127.0.0.1`. O script mostra-as.
- **Certificados**: remove o certificado raiz "OmniRoute"/mitm do armazém do sistema
  (`certmgr.msc` ou `certutil -delstore Root <thumbprint>` no Windows;
  `security delete-certificate -c "OmniRoute"` no macOS).
- **Antivírus com HTTPS inspection** empilha-se com isto (duas interceções = metade da
  velocidade). Não corras os dois ao mesmo tempo.

> Uso correto: liga o Traffic Inspector **quando estás a capturar**, e desliga (ou deixa o
> guard de 30 min expirar) **quando acabas**. Antes de downloads grandes, confirma que está
> desligado.

---

## 9. Checklist final (por ordem de probabilidade, ~20 minutos)

1. [ ] Estás por **cabo**? Se não, liga o cabo e volta a medir.
2. [ ] **Steam → Definições → Downloads**: sem limites, região correta, cache limpa.
3. [ ] `resmon` durante o download: o gargalo é **rede**, **disco** ou **CPU**? Isso decide tudo.
4. [ ] **Proxies** (WinHTTP / WinINET / gsettings) e **certificados de interceção** limpos.
5. [ ] Reiniciar o router (tomada 30 s) e medir outra vez.
6. [ ] Medir no telemóvel por Wi-Fi 5 GHz e por 5G — isola PC vs linha.
7. [ ] Verificar **QoS/GameFirst/Turbo LAN/Killer/NetLimiter** com limites de 10 Mbps por app.
8. [ ] Testar o mesmo ficheiro em hora de ponta e fora dela (peering/CDN).
9. [ ] Se tudo isto falhar: testar diretamente ligado ao ONT/modem do ISP, e só depois
   abrir ticket no ISP com os números do relatório (velocidade, perda, jitter, MTU, horário).

---

## 10. Ferramentas úteis

| Ferramenta | Para quê |
|---|---|
| `resmon` (Monitor de Recursos) | Ver rede vs disco vs CPU em tempo real |
| Speedtest CLI (`speedtest -s <id do servidor>`) | Comparar com o servidor do operador |
| `curl -o NUL https://speed.hetzner.de/100MB.bin` | Teste de 100 MB sem interface web |
| Cloudflare Speed Test / Waveform Bufferbloat | Latência sob carga (bufferbloat) |
| CrystalDiskInfo / `smartctl` | Saúde e velocidade do disco |
| WiFi Analyzer / `netsh wlan show interfaces` | Canal, banda e sinal Wi-Fi |

---

### Resumo numa linha

Com uma linha de 1 Gbps, **4,7 GB em uma hora significa ~10 Mbit/s**: procura um **limite**
(Steam, QoS do router, software de fabricante) ou um **proxy/disco a estrangular** antes de
culpares o operador — e usa o cabo como referência. O script deste kit diz-te em qual dos
casos estás.

> Este guia foi escrito para este incidente; os detalhes sobre o OmniRoute foram verificados
> diretamente no código deste repositório (caminhos indicados na secção 8).
