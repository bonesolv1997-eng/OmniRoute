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
3. **Corre o diagnóstico deste kit** (não altera nada, só mede). Se ainda não tens os
   ficheiros no PC, começa por descarregar o kit inteiro com o `baixar-kit.ps1` (secção 1b):

```powershell
# Windows (na pasta deste ficheiro)
powershell -ExecutionPolicy Bypass -File .\diagnostico-net-lenta.ps1
```

```powershell
# Windows — teste rápido de 30 s (interface + latência + velocidade real)
powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1

# Windows — ver chip/driver do Wi-Fi e desligar a poupança de energia (ver secção 4d)
powershell -ExecutionPolicy Bypass -File .\desligar-poupanca-wifi.ps1
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
| `The argument '.\desligar-poupanca-wifi.ps1' to the -File parameter does not exist` | Esse **ficheiro ainda não existe no teu PC** (só descarregaste o `diagnostico-net-lenta.ps1`), ou estás noutra pasta | Descarrega o kit completo (bloco abaixo) ou o ficheiro: troca o nome no URL do `raw.githubusercontent.com` e volta a correr |

**Descarregar o kit completo (7 ficheiros, um comando)** — deixa tudo na pasta
`Downloads\omniroute-net-kit`, já desbloqueado, e imprime os comandos exatos:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$b = "$env:TEMP\baixar-kit.ps1"
Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT/baixar-kit.ps1' -OutFile $b
Unblock-File $b
& $b
```

Depois disso, **os três scripts estão todos na mesma pasta** e os comandos desta
documentação funcionam tal e qual (depois de um `cd` para essa pasta):

```powershell
cd "$env:USERPROFILE\Downloads\omniroute-net-kit"
powershell -ExecutionPolicy Bypass -File .\diagnostico-net-lenta.ps1
powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1
powershell -ExecutionPolicy Bypass -File .\desligar-poupanca-wifi.ps1
```

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

## 4c. macOS / Apple Silicon (se for o teu caso)

Em Apple Silicon, ligar um adaptador USB/Thunderbolt de 2,5G cria por vezes um **bridge com o
Wi-Fi** e o tráfego TCP passa a "andar por cima" da interface sem fios — a velocidade do cabo
fica então limitada pelo Wi-Fi. Verifica com `ifconfig bridge0` / Preferências → Rede, e testa
com o Wi-Fi desligado. O ficheiro `checar-nic-macos-linux.sh` deste kit faz esta verificação
(3b) e o equivalente Linux de driver/EEE/erros de descarte (5b).

---

## 4d. Atualizar o driver do Wi-Fi e desligar a poupança de energia (passo a passo)

> Há um script que faz isto por ti, com modo de teste: `desligar-poupanca-wifi.ps1`
> (sem argumentos = só mostra; `-Aplicar` como administrador = aplica). Abaixo está o
> equivalente à mão, para fazeres no interface.

### Passo 0 — Saber que chip tens (decide tudo o resto)

```powershell
Get-NetAdapter | Where-Object { $_.PhysicalMediaType -match '802.11' } |
  Format-List Name, InterfaceDescription, DriverProvider, DriverVersion, DriverDate
```

| Se a `InterfaceDescription` disser... | Onde se atualiza |
|---|---|
| **Intel Wi-Fi 6/6E/7** (AX201, AX210, AX211, BE200...), **9000** (9560, 9260) | **Intel DSA** (deteta sozinho) ou pacote oficial **24.70.0** (08/09/2026) |
| **Intel Wi-Fi 6 AX200 / Killer AX1650** | Pacote **proprio** e **em fim de vida**: **24.20.2.1** — o 24.70.0 **nao** cobre este chip (seccao 4e) |
| **Killer** (AX1650, Wi-Fi 6/7 Killer) | **Intel Killer Performance Suite** (não o pacote genérico) |
| **MediaTek / RZ608 / RZ616 / MT79xx** (muito comum em placas AMD) | Site do **fabricante da placa-mãe** — o DSA **não** deteta estes |
| **Realtek (RTL88xx)**, **Qualcomm/Atheros**, **Broadcom** | Fabricante da placa-mãe (ou do dongle USB) |

### Passo 1 — Atualizar o driver (Intel: 2 minutos)

**Via Intel DSA (recomendado, é ele que escolhe o pacote certo):**

1. Abre <https://www.intel.com/content/www/us/en/support/detect.html>
2. `Download now` → corre o instalador → **Sim** no UAC → deixa instalar
3. O DSA abre **no browser** → clica **Allow** para autorizar o scan
4. Na lista de *Wi-Fi*, `Download` → `Install` → reinicia se ele pedir

A versão atual do pacote Wi-Fi é a **24.70.0** (08/09/2026, ficheiro
`WiFi-24.70.0-Driver64-Win10-Win11.exe`), que cobre Wi-Fi 7 (BE200/BE201/BE202/BE211/BE213),
Wi-Fi 6E (AX411/AX211/AX210), Wi-Fi 6 (AX231/AX203/AX201) e 9000 (9560/9260/9462/9461)
[4](https://www.intel.com/content/www/us/en/support/products/130293/wireless/intel-wi-fi-6-products/intel-wi-fi-6-series/intel-wi-fi-6-ax201-gig.html).

**Se tens um AX200 (ou Killer AX1650): para.** Este chip tem pacote proprio e esta em fim de
vida — o instalador generico 24.70.0 **nao** o cobre e ainda bloqueia o correto. Salta para a
seccao **4e** e segue os links de la.

**Sem DSA (manual, para os chips não-AX200):** pagina oficial
<https://www.intel.com/content/www/us/en/download/19351/intel-wireless-wi-fi-drivers-for-windows-10-and-windows-11.html>
→ aceitar a licença → descarregar → correr → reiniciar. Alguns 8xxx têm pacote próprio.

**Alternativas sem instalar nada:** Definições → Windows Update → Opções avançadas →
**Atualizações opcionais → Atualizações de controladores** (menos recentes que o DSA), ou o
site do fabricante da placa-mãe (obrigatório para MediaTek/Realtek).

### Passo 2 — Desligar "permitir que o computador desligue este dispositivo"

**No interface (o mais fiável, funciona com todos os drivers):**

1. `Win+X` → **Gestor de Dispositivos**
2. Abre **Adaptadores de rede**
3. Botão direito no adaptador de **Wi-Fi** → **Propriedades**
4. Separador **Gestão de energia** → desmarca
   **"Permitir que o computador desligue este dispositivo para poupar energia"**
5. Separador **Avançadas** → põe estes no valor indicado (os nomes variam com o driver):

   | Propriedade | Valor |
   |---|---|
   | Power Saving Mode / Modo de economia de energia | **Maximum Performance** / *Desempenho máximo* |
   | U-APSD support | **Disabled** |
   | MIMO Power Save Mode | **No SMPS** (ou Disabled) |
   | Sleep on WoWLAN | Disabled |
   | Packet Coalescing | Disabled (opcional, baixa latência) |

6. `OK`. O adaptador reinicia sozinho (~5 s sem ligação).

**Pela linha de comando (PowerShell como Administrador):**

```powershell
# Ver o estado
Get-NetAdapterPowerManagement -Name 'Wi-Fi' | Select-Object Name, AllowComputerToTurnOffDevice

# Desligar a gestão de energia (equivale a desmarcar a caixa acima)
Disable-NetAdapterPowerManagement -Name 'Wi-Fi'

# Ver o que o driver expõe e o que está escolhido (nomes localizados — vê os DisplayName)
Get-NetAdapterAdvancedProperty -Name 'Wi-Fi' | Where-Object DisplayName -match 'Power|WLAN|MIMO|APSD|Coalesc' |
  Select-Object DisplayName, DisplayValue, ValidDisplayValues

# Aplicar (usa o DisplayName EXATO que viste acima)
Set-NetAdapterAdvancedProperty -Name 'Wi-Fi' -DisplayName 'U-APSD support' -DisplayValue 'Disabled'
```

### Passo 3 — Tirar a poupança do *plano de energia* (o sítio que quase todos esquecem)

Painel de Controlo → **Opções de Energia** → **Alterar definições do plano** → **Alterar
definições avançadas** → **Definições do adaptador sem fios → Modo de poupança de energia →
Máximo desempenho** (no perfil *Equilibrado* está em *Média* por omissão, o que já reduz o
débito).

Ou numa linha (administrador; aplica ao plano ativo, corrente alternada + bateria):

```powershell
powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0
powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0
powercfg /setactive SCHEME_CURRENT
```

### Passo 4 — Confirmar que valeu a pena

```powershell
Get-NetAdapter -Physical | Format-Table Name, InterfaceDescription, DriverVersion, DriverDate
powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1
```

Compara **Wi-Fi ligada** com **Wi-Fi desligada** (cabo): o `medir-velocidade.ps1` mostra qual é
a rota preferida e a velocidade de cada cenário. Se a diferença não aparecer, o gargalo não
estava aqui — e isso também é uma resposta útil.

### O que **não** faz diferença

- Desativar IPv6, "otimizadores" de registo, `netsh int tcp` sem critério — mito, ou pior.
- Desligar o Bluetooth (partilha antena em chips combo, efeito marginal).
- Trocar o canal da Wi-Fi: só ajuda quando são **outras** redes a interferir.

---

## 4e. Intel Wi-Fi 6 AX200 160MHz (o teu adaptador)

### O essencial

| | |
|---|---|
| **Wi-Fi** | Pacote **próprio**: `WiFi-24.20.2-Driver64-Win10-Win11.exe` — driver final **24.20.2.1** |
| **Bluetooth** | Pacote **próprio**: `BT-24.10.0-64UWD-Win10-Win11.exe` — driver final **24.10.0.4** |
| **Estado** | **End of Life**: 24.20.2.1 é a última versão que existirá para este chip |
| **Página oficial** | <https://www.intel.com/content/www/us/en/download/915475/intel-wireless-wi-fi-drivers-for-intel-wi-fi-6-ax200.html> |

> ⚠️ **Não instales o pacote genérico 24.60/24.70** (o de "Wi-Fi 7/6E/6/9000"). **O AX200 não
> está incluído** nesse pacote: ele não instala nada no teu adaptador, mas **regista-se** como
> versão mais recente e a partir daí o instalador correto (24.20.2) falha com
> *"A newer product version is already installed"*. Há relatos disto na comunidade Intel.
> Se isso te acontecer, a solução é remover o registo do pacote errado:
>
> ```powershell
> # 1) procura o cache do pacote instalado por engano
> Get-ChildItem 'C:\ProgramData\Package Cache' -Recurse -Filter 'WirelessSetup.exe' -ErrorAction SilentlyContinue |
>   Select-Object FullName, LastWriteTime
>
> # 2) no PowerShell como ADMINISTRADOR, corre o desinstalador que está no cache (substitui o caminho)
> & "C:\ProgramData\Package Cache\{GUID}\WirelessSetup.exe" /uninstall UninstallEnabled=1
> ```
>
> Instalar por cima (substituindo o adaptador no Gestor de Dispositivos ou com `pnputil`) **não**
> limpa esse registo — só o passo 2 acima resolve.

### Como atualizar (passo a passo, só para o teu chip)

1. **Antes de tudo, aponta a versão atual** (para saberes se valeu a pena):
   ```powershell
   Get-NetAdapter -Physical | Where-Object { $_.InterfaceDescription -match 'AX200' } |
     Format-List Name, DriverVersion, DriverDate
   ```
   Se estiver em `22.x`/`23.x` (o teu é de **2021-08-19**), há mesmo um salto grande a fazer.
2. Abre a página: <https://www.intel.com/content/www/us/en/download/915475/intel-wireless-wi-fi-drivers-for-intel-wi-fi-6-ax200.html>
3. Em *Available Downloads*, aceita a licença e descarrega **`WiFi-24.20.2-Driver64-Win10-Win11.exe`** (≈44 MB).
4. **Fecha o jogo/Steam** e corre o `.exe` → *Install* → **reinicia** quando ele pedir.
5. Confirma: `Get-NetAdapter -Physical | Where-Object { $_.InterfaceDescription -match 'AX200' } | Format-List DriverVersion, DriverDate` → deve dar **24.20.2.1**.
6. O Bluetooth é **outro** pacote (`BT-24.10.0-64UWD-Win10-Win11.exe`, página
   <https://www.intel.com/content/www/us/en/download/874349/intel-wireless-bluetooth-driver-for-intel-wi-fi-6-ax200.html>).
   Só faz sentido se tiveres problemas de Bluetooth — para velocidade de rede é indiferente.
7. Guarda o `.exe` numa pasta: como o chip está em EOL, esta é a última versão que vais instalar
   e é útil tê-la à mão para reinstalações.

**E o Intel DSA?** Para o AX200 é fraco: como o produto está em EOL, o DSA pode não oferecer
nada, ou oferecer o pacote genérico (o que dá no erro descrito acima). Neste chip, usa os links
diretos desta secção.

### Se o AX200 estiver lento apesar de tudo (checklist conhecido)

O AX200 tem um conjunto de problemas documentados pela comunidade — todos reversíveis, e o
`desligar-poupanca-wifi.ps1 -Aplicar` cobre os primeiros quatro:

1. **Autotuning do TCP desligado** — o mais citado: em muitas máquinas o Windows tem-no em
   `disabled`/`restricted` e o AX200 não passa dos 50-100 Mbps. Ver e corrigir:
   ```powershell
   netsh int tcp show global                 # procura "Receive Window Auto-Tuning Level"
   netsh int tcp set global autotuninglevel=normal   # (administrador)
   ```
   Se estava em `disabled`, repete o teste de velocidade antes/depois.
2. **Poupança de energia** no adaptador (Gestão de energia) e no plano (*Máximo desempenho*),
   `Power Saving Mode = Maximum Performance`, `U-APSD = Disabled`, `MIMO Power Save Mode = No SMPS`.
3. **Offloads de WoWLAN** — desliga e testa (são os que mais aparecem nas queixas do AX200):
   `ARP Offload for WoWLAN`, `NS Offload for WoWLAN`, `Sleep on WoWLAN`, `Packet Coalescing`.
4. **`Large Send Offload (LSO)`** — em algumas máquinas Windows 11 com Hyper-V/VirtualBox, o
   LSO na interface virtual limita o Wi-Fi. Testa `Disabled` **na interface virtual**, não na
   Wi-Fi, e mede.
5. **160 MHz vs 80 MHz** — o "160MHz" no nome é capacidade, não garantia: em canais DFS
   (5250-5725 MHz) uma deteção de radar faz o router recuar para 80/40 MHz. Se vês
   `netsh wlan show interfaces` com *Channel Width* a 80 ou 40 MHz e débito de 300-500 Mbps,
   o limite é o router/canal, não o adaptador. Testa **80 MHz fixo** no router: em muitos casos
   é mais estável e mais rápido na prática do que 160 MHz a oscilar.
6. **Antenas** — é uma placa M.2: se o cabo da antena estiver mal ligado ou as antenas
   encostadas à caixa, perdes 10-20 dB. Testa trocar a ordem dos conectores (já resolveu casos
   reais) e afasta as antenas do chão/metal.
7. **Software do fabricante** — vários relatos de AX200 lentos em placas MSI/ASUS AMD acabaram
   com a remoção dos utilitários de rede do fabricante (MSI LAN Manager / Dragon / GameFirst)
   e das extensões de "aceleração" (cFosSpeed). Isto cruza com o que está na secção 4b.

### O que esperar (para calibrar o teu caso)

| Cenário | Velocidade realista de download |
|---|---|
| Cabo (I219/I225 a 1 Gbps, router Gigabit) | **900-940 Mbps** |
| Wi-Fi 6, 5 GHz, 80 MHz, a 2-3 m do router | **400-700 Mbps** |
| Wi-Fi 6, 5 GHz, **160 MHz**, a 1-2 m, canal limpo | **700-1200 Mbps** |
| Wi-Fi a 10-15 m ou com paredes | **100-400 Mbps** |
| **Aqui está o teu problema se estiver a dar ~10 Mbps** | Não é "Wi-Fi lento": é **throttle** (Steam/router/software) — ver secções 3, 4b e 8 |

> Para descarregar o BF6, o cabo ganha sempre ao AX200: 940 Mbps estáveis contra 400-1200 Mbps
> que oscilam com o canal. Usa o Wi-Fi para o dia-a-dia e o **cabo para os downloads grandes** —
> e desliga a Wi-Fi nos testes, para não haver dúvidas sobre por onde sai o tráfego (secção 1c
> do script).

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
7b. [ ] **Wi-Fi (AX200)**: driver **24.20.2.1** pelo link proprio (nao pelo 24.70.0 — seccao
   4e), poupanca desligada no adaptador **e** no plano de energia (4d, passos 2 e 3),
   `netsh int tcp set global autotuninglevel=normal`, e medir **com a Wi-Fi desligada**, por cabo.
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
| `medir-velocidade.ps1` (deste kit) | A/B rápido: interface + latência + velocidade em 30 s |
| CrystalDiskInfo / `smartctl` | Saúde e velocidade do disco |
| Intel Driver & Support Assistant (DSA) | Deteta e atualiza driver da NIC Intel |
| `ethtool -S eth0` / `ethtool --show-eee eth0` | Erros de descarte e estado do EEE (Linux) |
| WiFi Analyzer / `netsh wlan show interfaces` | Canal, banda e sinal Wi-Fi |

---

## Apêndice — caso real em que este kit foi usado (2026-09)

Placa-mãe AMD, NIC Intel (Ethernet) + Wi-Fi, linha 1000/100 Mbps, BF6 na Steam a
4,7 GB/hora. O relatório do kit dizia:

| Observação do relatório | Leitura | Ação |
|---|---|---|
| "A porta de rede negociou apenas 1 Gbps" | **Falso positivo do script** (o Windows devolve `LinkSpeed = "1 Gbps"` localizado) — corrigido: 1 Gbps = 1000 Mbps = link perfeito | (nada a fazer — o cabo/porta estão bons) |
| "O Steam guarda aqui o limite de largura de banda" | **O Steam tem limite de downloads configurado** | Steam → Definições → Downloads → tirar o limite |
| "Máximo de 54,3 Mbps" (Cloudflare + Steam CDN; Hetzner falhou) | A linha/PC entrega **~6 % do plano** | Ver interface: Wi-Fi ou cabo? |
| Wi-Fi **E** cabo ligados ao mesmo tempo; Wi-Fi com driver de **2021** e poupança de energia ligada | Rota pode estar a sair pela Wi-Fi | Desligar Wi-Fi, medir outra vez com `medir-velocidade.ps1` |
| `Green Ethernet` + `Gigabit Lite` **ligados** na Intel | Causa clássica de link errático/velocidade baixa em I219/I225/I226 | Desligar nas Propriedades Avançadas |
| `Speed & Duplex` forçado a `1.0 Gbps Full Duplex` | Não limita (a placa é 1G), mas Auto é mais seguro | Pôr em Auto Negotiation |
| 3703 pacotes descartados | Cabo/porta ou link saturado | Trocar cabo e porta do router, repetir |

Sequência de resolução (o que fazer por esta ordem): **limite do Steam → desligar a Wi-Fi e
medir por cabo → Green Ethernet/Gigabit Lite off + driver Wi-Fi atualizado → trocar cabo/porta
→ se continuar a ~54 Mbps com cabo, testar direto no ONT e abrir ticket no ISP** com o `.txt`
do relatório.

> Lição do kit: `LinkSpeed`, `DisplayValue` e afins vêm **localizados** ("1 Gbps", "1,0 Gbps")
> — qualquer leitura de velocidade tem de distinguir Gbps de Mbps (o `ConvertTo-Mbps` do
> script faz isso) e os contadores são **cumulativos desde o arranque**, não "agora".

---

### Resumo numa linha

Com uma linha de 1 Gbps, **4,7 GB em uma hora significa ~10 Mbit/s**: procura um **limite**
(Steam, QoS do router, software de fabricante) ou um **proxy/disco a estrangular** antes de
culpares o operador — e usa o cabo como referência. O script deste kit diz-te em qual dos
casos estás.

> Este guia foi escrito para este incidente; os detalhes sobre o OmniRoute foram verificados
> diretamente no código deste repositório (caminhos indicados na secção 8).
