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

# macOS / Linux — só a parte da placa de rede (driver, EEE, limites de software)
bash checar-nic-macos-linux.sh
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

## 1b. Se o script "não der" — os 6 motivos habituais

**Caminho mais fácil (Windows):** em vez de escreveres o comando, descarrega a pasta inteira
`docs/help/pt-PT` do branch `arena/01a0aae0-omniroute` e **faz duplo clique em
`correr-diagnostico.cmd`**. Esse lançador: muda para a pasta correta, desbloqueia o ficheiro
(se vier da Internet fica bloqueado), descarrega-o sozinho se não estiver lá, corre com
`-NoProfile` e `-ExecutionPolicy Bypass`, e **não fecha a janela no fim**.

| O que vês | Porquê | Solução |
|---|---|---|
| `O termo '.\diagnostico-net-lenta.ps1' não é reconhecido...` / `não pode ser encontrado` | **Não estás na pasta do ficheiro** (estás em `C:\Users\<tu>`), ou o ficheiro não foi descarregado, ou o browser chamou-lhe `diagnostico-net-lenta.ps1.txt` | `cd` para a pasta onde o guardaste, confirma com `dir *.ps1` e volta a correr. Ou usa o `correr-diagnostico.cmd`. |
| `A execução de scripts foi desativada neste sistema` | Política de execução (`Restricted`/`AllSigned`) | `powershell -ExecutionPolicy Bypass -File .\diagnostico-net-lenta.ps1` (é o que já está na linha de comando) ou, na sessão atual: `Set-ExecutionPolicy -Scope Process Bypass -Force` |
| `Este ficheiro veio de outro computador e está bloqueado` / `não está assinado digitalmente` | *Mark of the Web* (descarregaste pela Internet) | `Unblock-File .\diagnostico-net-lenta.ps1` — ou duplo clique no `correr-diagnostico.cmd`, que o faz por ti |
| `Não é possível carregar o ficheiro ... porque está numa unidade de rede/OneDrive` | PowerShell bloqueia scripts em algumas localizações sincronizadas | Copia a pasta para `C:\Temp` e corre a partir daí |
| Erros de sintaxe ou acentos trocados (`Ã©`, `â€”`) | Ficheiro guardado noutra codificação | Usa a versão do repositório (**já está gravada com BOM UTF-8**, que o PowerShell 5.1 lê bem). Se editaste o ficheiro, guarda como *UTF-8 com BOM*. |
| `powershell : O termo 'powershell' não é reconhecido` | A correr dentro do próprio PowerShell ou num CMD sem PATH | `Get-Command powershell` para confirmar; no PowerShell basta `.\diagnostico-net-lenta.ps1` (sem a palavra `powershell` à frente) |

**Copiaste o comando com as crases (` ``` `) do chat?** Isso dá exatamente "não é reconhecido".
Copia **só** a linha: `powershell -ExecutionPolicy Bypass -File .\diagnostico-net-lenta.ps1`

**Descarregar e correr sem sair do PowerShell** (repositório é público, funciona na hora):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$u = 'https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT/diagnostico-net-lenta.ps1'
$f = "$env:TEMP\diagnostico-net-lenta.ps1"
Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $f
Unblock-File $f
& $f
```

Se mesmo isto falhar, o problema é de rede e não do script — e o erro que aparece é
exatamente o primeiro dado do diagnóstico. Copia-me o texto vermelho que aparecer.

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
| Preço/velocidade estranhos, chip Intel I225/I226 | Driver antigo + EEE ligado | Secção 4b |
| Placa "Killer" com perfil de prioridade configurado | Killer Control Center a limitar por app | Secção 4b |
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

## 4b. Placa de rede Intel (I219 / I225 / I226 / Killer / X5xx)

Motherboard AMD + NIC Intel é uma combinação perfeitamente normal — **o chipset AMD não
limita largura de banda** (o "AMD Chipset Software" não tem traffic shaping). O que existe,
e é específico do teu caso, é o ecossistema Intel à volta da placa de rede. Diagnóstico em
30 segundos no PowerShell:

```powershell
Get-NetAdapter | Format-Table Name, InterfaceDescription, LinkSpeed, DriverVersion, DriverDate, MacAddress
```

Interpreta assim:

| Chip (aparece em `InterfaceDescription`) | Máx. teórico | O que costuma correr mal |
|---|---|---|
| Intel **I217/I218/I219** (LM/V) | 1 Gbps | Teto real ~940 Mbps. "Gigabit Lite" e EEE ligados podem fazer o link cair ou ficar errático. |
| Intel **I210/I211/I350** | 1 Gbps | Server-grade, praticamente sem surpresas. |
| Intel **I225-V / I226-V** | 2,5 Gbps | **Defeito conhecido**: o link cai para 100 Mbps ou 1 Gbps, ou perde-se, com *Energy Efficient Ethernet* ligado, driver antigo (2020-2021) ou certos routers/switches. Driver/firmware recentes corrigem — é o caso mais comum de "a net piorou sem razão". |
| Intel **X520/X540/X550/X710** | 10 Gbps | Se o router é 1G, o link negocia 1G. Cabo CAT6/CAT6a obrigatório. |
| **Killer** E2x00/E3x00 e "Killer Wi-Fi 6/6E/7" | 1/2,5 Gbps | Hoje é marca Intel. O **Killer Control Center / Intel Connectivity Performance Suite limita largura de banda POR APLICAÇÃO** — é um dos poucos sítios onde 10 Mbit/s aparece escrito a todas as letras. |

**Propriedades avançadas a rever** (Gestor de Dispositivos → adaptador de rede → Propriedades
→ Avançadas). O script do kit lê-as todas e avisa; a lista do que importa:

| Propriedade | Valor correto | Porquê |
|---|---|---|
| Speed & Duplex | **Auto Negotiation** | Se estiver forçado a 100 Mbps, esse passa a ser o teto de toda a linha. |
| Energy Efficient Ethernet / Green Ethernet / Gigabit Lite | **Disabled** | Fonte clássica de quedas de link e velocidade baixa nos I219/I225/I226. |
| Reduce Speed On Power Down / Ultra Low Power Mode | **Disabled** | Poupança de energia que estrangula o link. |
| Gestão de energia → "permitir desligar o dispositivo" | **Desligado** | Evita o adaptador adormecer/cair. |
| Jumbo Packet | Disabled (1500) | Jumbo só ajuda em link direto 10G; fora disso causa problemas. |
| RSS / Interrupt Moderation | Enabled | Manter por omissão (mexer só se souberes o que fazes). |

**Driver**: usa o **Intel Driver & Support Assistant (DSA)** ou a página de downloads da
Intel pelo **modelo exato** (I225-V ≠ I226-V em algumas versões). O driver que vem pelo
Windows Update costuma ter 3-5 anos e é a causa nº 1 destes sintomas em placas Intel.

**Software de fabricante** — aqui o que interessa não é AMD vs Intel, é a **marca da
motherboard**, que é quem empacota o utilitário de rede: **MSI LAN Manager** (limite de
largura de banda por aplicação, típico em placas MSI com NIC **Intel** — dos suspeitos nº 1
para "exatamente 10 Mbps"), **ASUS GameFirst / Armoury Crate**, **Gigabyte Dragon**,
**Killer Control Center** e **Intel Connectivity Performance Suite**, **cFosSpeed**,
**NetLimiter**, **GlassWire**, "Turbo LAN", "Network Accelerator". Todos têm (ou já tiveram)
perfis com limite de download — o script lista os que encontrar instalados e avisa.

> Se adicionaste recentemente um **adaptador USB de 2,5G** (Realtek RTL8156, Aquantia) à
> placa Intel, não é só "mais uma porta": confirma qual delas está a ser usada
> (`Get-NetRoute -DestinationPrefix 0.0.0.0/0` → `InterfaceAlias`) — é comum a rota continuar
> a passar pela Wi-Fi ou pela porta de 1G.

### 4c. macOS / Apple Silicon (se for o teu caso)

Em Apple Silicon, ligar um adaptador USB/Thunderbolt de 2,5G cria por vezes um **bridge com o
Wi-Fi** e o tráfego TCP passa a "andar por cima" da interface sem fios — a velocidade do cabo
fica então limitada pelo Wi-Fi. Verifica com `ifconfig bridge0` / Preferências → Rede, e testa
com o Wi-Fi desligado. O ficheiro `checar-nic-macos-linux.sh` deste kit faz esta verificação
(3b) e o equivalente Linux de driver/EEE/erros de descarte (5b).

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
7. [ ] **Chip de rede (Intel?)**: driver atualizado, `Speed & Duplex = Auto`, EEE desligado,
   e sem **Killer Control Center / GameFirst / Intel Connectivity Performance Suite** com
   perfil de limite de banda (secção 4b).
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
| Intel Driver & Support Assistant (DSA) | Deteta e atualiza driver da NIC Intel |
| `ethtool -S eth0` / `ethtool --show-eee eth0` | Erros de descarte e estado do EEE (Linux) |
| WiFi Analyzer / `netsh wlan show interfaces` | Canal, banda e sinal Wi-Fi |

---

### Resumo numa linha

Com uma linha de 1 Gbps, **4,7 GB em uma hora significa ~10 Mbit/s**: procura um **limite**
(Steam, QoS do router, software de fabricante) ou um **proxy/disco a estrangular** antes de
culpares o operador — e usa o cabo como referência. O script deste kit diz-te em qual dos
casos estás.

> Este guia foi escrito para este incidente; os detalhes sobre o OmniRoute foram verificados
> diretamente no código deste repositório (caminhos indicados na secção 8).
