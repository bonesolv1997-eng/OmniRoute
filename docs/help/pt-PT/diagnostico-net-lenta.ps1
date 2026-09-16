<#
    diagnostico-net-lenta.ps1  -  "a minha net ficou ma" : uma passagem de diagnostico
    ----------------------------------------------------------------------------------
    Corres isto quando algo esta lento a transferir (Steam, Epic, downloads) e queres
    saber rapidamente ONDE esta o gargalo: linha/ISP, Wi-Fi/cabo, router, PC, disco,
    ou um proxy/DNS que ficou preso a frente do trafego (ex.: Traffic Inspector do
    OmniRoute).

    COMO CORRER (nao precisa de admin para 95% dos testes):
        powershell -ExecutionPolicy Bypass -File .\diagnostico-net-lenta.ps1

    Opcoes:
        -SemDisco          salta o teste de escrita em disco (rapido)
        -MBDisco 1024      tamanho do ficheiro de teste (por omissao 512 MB)

    O que faz (por esta ordem):
        1. Identidade da ligacao (interface, velocidade de link, Wi-Fi vs cabo)
        2. Proxies presos (WinHTTP, WinINET, variaveis de ambiente)  <-- suspeito no1
        3. DNS (servidores configurados + tempo de resolucao)
        4. Latencia / perda / jitter  e teste de BUFFERBLOAT (ping com a linha ocupada)
        5. MTU / fragmentacao (PPPoE, VPN, tuneis)
        6. Velocidade real de download contra 3 CDNs independentes
        7. Ficheiros hosts + certificados raiz suspeitos (intercecao TLS)
        8. Estado do Steam (limites de download, pastas de biblioteca)
        9. Escrita em disco nos discos onde o Steam instala (o suspeito "invisivel")

    NAO altera nada no sistema. So le e mede. Podes partilhar o .txt gerado.
#>
# KIT-VERSION: 2026.09.16.4 (ASCII)

[CmdletBinding()]
param(
    [switch]$SemDisco,
    [int]$MBDisco = 512
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$script:Falhas = New-Object System.Collections.ArrayList
$script:Alertas = New-Object System.Collections.ArrayList
$script:Veredito = New-Object System.Collections.ArrayList

# -- Saida tambem para ficheiro, para poderes colar num ticket/forum ----------
$raiz = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$logFicheiro = Join-Path $raiz ("diagnostico-rede-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".txt")
try { Start-Transcript -Path $logFicheiro -Force | Out-Null } catch { }

function Titulo($texto) {
    Write-Host ""
    Write-Host ("=" * 78) -ForegroundColor DarkGray
    Write-Host ("  " + $texto) -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor DarkGray
}
function Sub($texto) { Write-Host ("  - " + $texto) -ForegroundColor Gray }
function Ok($texto)  { Write-Host ("  [OK]    " + $texto) -ForegroundColor Green }
function Warn($texto) {
    Write-Host ("  [ATENCAO] " + $texto) -ForegroundColor Yellow
    [void]$script:Alertas.Add($texto)
}
function Erro($texto) {
    Write-Host ("  [FALHA] " + $texto) -ForegroundColor Red
    [void]$script:Falhas.Add($texto)
}
function Info($texto) { Write-Host ("  [i]     " + $texto) -ForegroundColor DarkCyan }

function ConvertTo-Mbps($texto) {
    # "1 Gbps" -> 1000 | "2,5 Gbps"/"2.5 Gbps" -> 2500 | "100 Mbps" -> 100 | "Auto" -> 0
    # (LinkSpeed e DisplayValue vem localizados: "1 Gbps" nao pode ser lido como 1 Mbps.)
    if (-not $texto) { return 0 }
    $t = ($texto -replace '\s', '')
    $fator = 1
    if ($t -match '(?i)gbps') { $fator = 1000 }
    elseif ($t -match '(?i)kbps') { $fator = 0.001 }
    elseif ($t -match '(?i)mbps') { $fator = 1 }
    if (-not ($t -match '([\d\.,]+)')) { return 0 }
    $numStr = $matches[1] -replace ',', '.'
    try { $num = [double]::Parse($numStr, [System.Globalization.CultureInfo]::InvariantCulture) } catch { return 0 }
    return [int][math]::Round($num * $fator)
}

Write-Host ""
Write-Host "  DIAGN-STICO DE REDE - iniciado $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "  Maquina: $env:COMPUTERNAME   Utilizador: $env:USERNAME" -ForegroundColor DarkGray

# ----------------------------------------------------------------------------
# 0. Contexto do sistema
# ----------------------------------------------------------------------------
Titulo "0. Contexto do sistema"
Sub ("SO: " + (Get-CimInstance Win32_OperatingSystem).Caption + " build " + [System.Environment]::OSVersion.Version)
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Sub ("CPU: " + $cpu.Name + "  (" + $cpu.NumberOfCores + " nucleos / " + $cpu.NumberOfLogicalProcessors + " threads)")
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Sub ("RAM: " + $ramGB + " GB")
$uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Sub ("Uptime: " + [int]$uptime.TotalHours + " h " + $uptime.Minutes + " min")

# Processos que costumam "comer" a linha / intercecao de trafego
$suspeitos = @('omniroute', 'mitmproxy', 'mitm', 'fiddler', 'charles', 'burp', 'clash', 'v2ray', 'xray', 'sing-box', 'wireguard', 'openvpn', 'qbittorrent', 'utorrent', 'qbittorrent', 'steam')
$correndo = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $n = $_.ProcessName.ToLowerInvariant()
    ($suspeitos | Where-Object { $n -like ("*" + $_ + "*") }) -ne $null
} | Select-Object -ExpandProperty ProcessName -Unique
if ($correndo) {
    Info ("Processos relevantes em execucao: " + ($correndo -join ", "))
    foreach ($p in $correndo) {
        if ($p -match 'omniroute|mitm|fiddler|charles|burp|clash|v2ray|xray|sing-box') {
            Warn ("'" + $p + "' esta em execucao - qualquer proxy/intercecao ativa pode estar a limitar TODO o trafego.")
        }
        if ($p -match 'qbittorrent|utorrent') {
            Warn ("'" + $p + "' esta em execucao - clientes de torrent saturam a linha e a tabela NAT do router.")
        }
    }
} else {
    Ok "Nenhum proxy/cliente de torrent conhecido em execucao (por nome de processo)."
}
# Segunda passagem: por linha de comando, para apanhar proxies a correr dentro de
# node.exe / bun.exe / python.exe (e assim que o OmniRoute e o mitmproxy arrancam).
try {
    $porCmd = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -and
            $_.CommandLine -match 'omniroute|mitmproxy|mitmdump|traffic-inspector|fiddler|charles' -and
            $_.CommandLine -notmatch 'docs[\\/]help[\\/]pt-PT'
        } | Select-Object -First 6
    foreach ($c in $porCmd) {
        Warn ("Processo de proxy/intercecao detetado pela linha de comando: " + $c.Name + " (pid " + $c.ProcessId + "). Se nao o estas a usar agora, fecha-o - pode estar a limitar/atrasar todo o trafego.")
    }
} catch { }

# ----------------------------------------------------------------------------
# 1. Ligacao e camada fisica
# ----------------------------------------------------------------------------
Titulo "1. Interface de rede e camada fisica"
try {
    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    if (-not $adaptadores) { Erro "Nenhum adaptador de rede ativo!" }
    foreach ($a in $adaptadores) {
        $tipo = if ($a.PhysicalMediaType) { $a.PhysicalMediaType } else { $a.MediaType }
        Sub ($a.Name + "  [" + $a.InterfaceDescription + "]")
        Sub ("    Tipo: " + $tipo + "   |   Velocidade negociada: " + $a.LinkSpeed + "   |   Duplex: " + $a.FullDuplex)
        $mbps = ConvertTo-Mbps $a.LinkSpeed
        if ($mbps -gt 0 -and $mbps -lt 1000 -and $tipo -notmatch 'Wireless|802\.11|Wi-Fi') {
            Warn ("A porta de rede negociou apenas " + $a.LinkSpeed + " (" + $mbps + " Mbps). Numa ligacao de 1 Gbps isto e o teto: cabo CAT5e/6 danificado, porta de router a 100 Mbps, ou switch mal configurado.")
        }
    }
    # Wi-Fi
    $wifi = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and ($_.InterfaceDescription -match 'Wireless|Wi-Fi|802\.11|Intel\(R\) Wi-Fi|Killer|MediaTek|Realtek 88') }
    if ($wifi) {
        foreach ($w in $wifi) {
            try {
                $netsh = (netsh wlan show interfaces) -join "`n"
                $ssid = [regex]::Match($netsh, '(?im)^\s*SSID\s*:\s*(.+)$').Groups[1].Value.Trim()
                $bssid = [regex]::Match($netsh, '(?im)^\s*BSSID\s*:\s*(.+)$').Groups[1].Value.Trim()
                $canal = [regex]::Match($netsh, '(?im)^\s*Canal\s*:\s*(\d+)').Groups[1].Value
                if (-not $canal) { $canal = [regex]::Match($netsh, '(?im)^\s*Channel\s*:\s*(\d+)').Groups[1].Value }
                $sinal = [regex]::Match($netsh, '(?im)^\s*Sinal\s*:\s*(\d+)%').Groups[1].Value
                if (-not $sinal) { $sinal = [regex]::Match($netsh, '(?im)^\s*Signal\s*:\s*(\d+)%').Groups[1].Value }
                $banda = [regex]::Match($netsh, '(?im)^\s*(Banda|Band)\s*:\s*(.+)$').Groups[2].Value.Trim()
                $rx = [regex]::Match($netsh, '(?im)^\s*(Taxa de rececao|Receive rate)\s*:\s*([\d\.]+)').Groups[2].Value
                Sub ("Wi-Fi: SSID='" + $ssid + "'  canal=" + $canal + "  sinal=" + $sinal + "%  banda=" + $banda + "  rx=" + $rx + " Mbps")
                if ($sinal -and [int]$sinal -lt 60) { Warn ("Sinal Wi-Fi fraco (" + $sinal + "%). Ligacao a 1 Gbps por Wi-Fi nestas condicoes da 10-80 Mbps reais.") }
                if ($banda -match '2,4|2\.4') { Warn "Estas ligado a Wi-Fi 2,4 GHz - o teto pratico ronda os 100-150 Mbps mesmo com bom sinal. Usa 5/6 GHz ou cabo." }
                if ($canal -and [int]$canal -le 14) { Warn "Canal em 2,4 GHz (muito congestionado em zonas residenciais)." }
            } catch { }
        }
        Warn "Estas em Wi-Fi. Para testar a linha a serio (e para descarregar o BF6), usa cabo Ethernet."
    } else {
        Ok "Ligacao por cabo (nao ha Wi-Fi ativo)."
    }
} catch {
    Warn ("Nao foi possivel enumerar adaptadores: " + $_.Exception.Message)
}

# Porta do router / gateway
try {
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw) {
        Sub ("Gateway/router: " + $gw)
        $pingGw = Test-Connection -ComputerName $gw -Count 5 -ErrorAction SilentlyContinue
        if ($pingGw) {
            $media = ($pingGw | Measure-Object -Property ResponseTime -Average).Average
            Sub ("Latencia ate ao router: " + [int]$media + " ms")
            if ($media -gt 5) {
                Warn ("Latencia ate ao router e alta (" + [int]$media + " ms). Em Wi-Fi o normal e 1-5 ms; valores acima disto indicam sinal fraco, canal saturado ou router sobrecarregado.")
            }
        }
    }
} catch { }

# ----------------------------------------------------------------------------
# 1b. Chip de rede, driver e propriedades que estrangulam
#     (Intel I219 = 1 Gbps; I225/I226 = 2,5 Gbps com defeitos conhecidos de
#      negociacao; "Killer" = marca Intel com limite de banda por aplicacao)
# ----------------------------------------------------------------------------
# 1b. Chip de rede, driver e propriedades que estrangulam
#     (Intel I217/I218/I219 = 1 Gbps; I225/I226 = 2,5 Gbps com defeitos
#      conhecidos de negociacao; "Killer" = marca Intel com limite por app)
# ----------------------------------------------------------------------------
Titulo "1b. Chip de rede, driver e propriedades que estrangulam"
try {
    $nics = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Not Present' }
    foreach ($n in $nics) {
        Sub ($n.Name + "  [" + $n.InterfaceDescription + "]   estado=" + $n.Status + "   link=" + $n.LinkSpeed)
        $dd = ""
        try { if ($n.DriverDate) { $dd = ([datetime]$n.DriverDate).ToString('yyyy-MM-dd') } } catch { }
        Sub ("    Driver: " + $n.DriverProvider + " " + $n.DriverVersion + "   (" + $dd + ")")
        try {
            if ($n.DriverDate -and ([datetime]$n.DriverDate) -lt (Get-Date).AddYears(-3)) {
                Warn ("O driver de " + $n.Name + " e de " + $dd + " (mais de 3 anos). Em NICs Intel isto explica quedas de link e velocidade erratica - atualiza com o Intel Driver & Support Assistant (DSA).")
            }
        } catch { }

        # Notas por modelo (Intel e "Killer", que hoje e Intel)
        if ($n.InterfaceDescription -match 'Intel|Killer') {
            if ($n.InterfaceDescription -match 'I225|I226') {
                Warn ("Intel I225/I226 (2,5 Gbps) detetada. Casos conhecidos: o link cai para 100 Mbps ou 1 Gbps com 'Energy Efficient Ethernet' ligado, driver antigo, ou certos routers/switches. Atualiza o driver e desliga EEE/Green Ethernet.")
            } elseif ($n.InterfaceDescription -match 'I219|I218|I217') {
                Sub "    Nota: I219/I218 e uma NIC de 1 Gbps - o teto pratico e ~940 Mbps."
            } elseif ($n.InterfaceDescription -match 'I210|I211|I350') {
                Sub "    Nota: I210/I211/I350 e uma NIC de 1 Gbps (server-grade)."
            } elseif ($n.InterfaceDescription -match 'X520|X540|X550|X710') {
                Sub "    Nota: serie X5xx/X7xx = 10 Gbps - confirma que o router/switch tambem e 10G ou 2,5G."
            }
            if ($n.InterfaceDescription -match 'Killer|Connectivity Performance') {
                Warn "Esta placa e 'Killer' (marca Intel). O Killer Control Center / Intel Connectivity Performance Suite tem controlo de largura de banda POR APLICACAO - abre-o e confirma que nao ha limite de download (o classico e 10 Mbps)."
            }
        }

        # Propriedades avancadas: Speed & Duplex e poupancas de energia
        $adv = @()
        try { $adv = @(Get-NetAdapterAdvancedProperty -Name $n.Name -ErrorAction Stop) } catch { }
        if ($adv.Count -gt 0) {
            $sd = $adv | Where-Object { $_.DisplayName -match 'Speed|Duplex|Velocidade' } | Select-Object -First 1
            if ($sd) {
                Sub ("    " + $sd.DisplayName + " = " + $sd.DisplayValue)
                $maxMbps = 0
                foreach ($v in ($sd.ValidDisplayValues | Select-Object -Unique)) {
                    $m = ConvertTo-Mbps $v
                    if ($m -gt $maxMbps) { $maxMbps = $m }
                }
                if ($maxMbps -gt 0) { Sub ("    Velocidade maxima suportada pela placa: " + $maxMbps + " Mbps") }
                if ($sd.DisplayValue -notmatch 'Auto|Autom') {
                    $forcado = ConvertTo-Mbps $sd.DisplayValue
                    if ($maxMbps -gt 0 -and $forcado -gt 0 -and $forcado -lt $maxMbps) {
                        Warn ("'" + $sd.DisplayName + "' esta FORCADO a '" + $sd.DisplayValue + "' mas a placa suporta " + $maxMbps + " Mbps. Estas a estrangular o link a " + $forcado + " Mbps - poe em Auto Negotiation.")
                    } else {
                        Sub ("    Nota: '" + $sd.DisplayName + "' esta forcado a '" + $sd.DisplayValue + "'. Nao te esta a limitar (a placa suporta o mesmo ou mais), mas Auto Negotiation e mais seguro - se o link andar instavel, volta a Auto.")
                    }
                }
            }
            $eco = $adv | Where-Object { $_.DisplayName -match 'Energy Efficient|Green Ethernet|Eco|Gigabit Lite|Reduce Speed|Reduce Link|Power Saving|Ultra Low Power|Low Power|Power Management' }
            foreach ($e in $eco) {
                Sub ("    " + $e.DisplayName + " = " + $e.DisplayValue)
                if ($e.DisplayValue.Trim() -match '^(Enabled|On|Ativado|Habilitado|Yes|Ligado|Sim)$') {
                    Warn ("'" + $e.DisplayName + "' esta LIGADO em " + $n.Name + ". Em NICs Intel (sobretudo I225/I226 e I219) isto provoca quedas de link e velocidade baixa/erratica. Desliga em: Gestor de Dispositivos > adaptador > Propriedades > Avancadas.")
                }
            }
            # Offloads de WoWLAN: causa conhecida de Wi-Fi lento em alguns chips Intel
            # (sobretudo AX200/AX201). Sao inocuos de desligar - testa um de cada vez.
            $off = $adv | Where-Object { $_.DisplayName -match 'Offload for WoWLAN|WoWLAN|Packet Coalescing|ARP Offload|NS Offload' }
            $ligados = @($off | Where-Object { $_.DisplayValue.Trim() -match '^(Enabled|On|Ativado|Habilitado|Yes|Ligado|Sim)$' })
            if ($ligados.Count -gt 0) {
                foreach ($e in $ligados) { Sub ("    " + $e.DisplayName + " = " + $e.DisplayValue) }
                Warn ("Ha " + $ligados.Count + " offload(s) de WoWLAN ligados em " + $n.Name + " ('" + $ligados[0].DisplayName + "', ...). Em chips Intel AX200/AX201 ha relatos de Wi-Fi lento com estes offloads ligados: desliga-os UM de cada vez e mede com medir-velocidade.ps1 (Gestor de Dispositivos > adaptador > Propriedades > Avancadas).")
            }
        }

        # Gestao de energia do adaptador
        try {
            $pm = Get-NetAdapterPowerManagement -Name $n.Name -ErrorAction Stop
            if ($pm.AllowComputerToTurnOffDevice -and $pm.AllowComputerToTurnOffDevice -ne 'Unsupported') {
                if ($pm.AllowComputerToTurnOffDevice -match 'Enabled') {
                    Warn ("Gestao de energia de " + $n.Name + ": 'Permitir que o computador desligue este dispositivo para poupar energia' esta ligado. Desliga em Gestor de Dispositivos > adaptador > Propriedades > Gestao de energia.")
                }
            }
        } catch { }
    }
} catch { Warn ("Analise das placas de rede falhou: " + $_.Exception.Message) }

# Software de fabricante / terceiros que pode limitar largura de banda
try {
    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $padrao = 'Killer|GameFirst|Turbo ?LAN|LAN ?Manager|NetLimiter|cFosSpeed|GlassWire|Traffic ?Shaper|Bandwidth ?(Manager|Control)|Connectivity Performance|Intel.{0,3}(PROSet|Connectivity|Driver)|Dragon|Speedify|WTFast|ExitLag|NetBalancer|SoftPerfect|Optimizer|Optimizador|Booster|TCP.?Optimi'
    $progs = Get-ItemProperty -Path $chaves -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and $_.DisplayName -match $padrao } |
        Select-Object DisplayName, DisplayVersion -Unique
    if ($progs) {
        Sub "Software de gestao/aceleracao de rede instalado (candidato a limite de banda):"
        foreach ($pr in $progs) { Sub ("    " + $pr.DisplayName + "  " + $pr.DisplayVersion) }
        Warn "Existe software de gestao de rede instalado. Abre-o e confirma que nao ha um PERFIL com limite de download (o valor tipico destes bloqueios e 10 Mbps). Se nao usas, desinstala - varios instalam filtros de rede proprios."
    } else {
        Ok "Sem software de gestao/limitacao de banda instalado (Killer/GameFirst/Turbo LAN/LAN Manager/NetLimiter/cFosSpeed/...)."
    }
    $svcs = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Killer|GameFirst|TurboLAN|NetLimiter|cFos|Speedify|WTFast|ExitLag|icps|IntelConnectivity|Dragon|NetBalanc' }
    foreach ($sv in $svcs) { Sub ("Servico relacionado: " + $sv.Name + " (" + $sv.Status + ")") }
} catch { }

# ----------------------------------------------------------------------------
# 1c. POR ONDE ESTA A SAIR O TRAFEGO  - a pergunta que decide tudo quando ha
#     Wi-Fi e cabo ligados ao mesmo tempo (o Windows escolhe pela metrica).
# ----------------------------------------------------------------------------
Titulo "1c. Interface que transporta o trafego (metricas de rota)"
try {
    $ifs = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ConnectionState -eq 'Connected' } |
        Sort-Object InterfaceMetric
    foreach ($i in $ifs) {
        $ad = Get-NetAdapter -InterfaceIndex $i.ifIndex -ErrorAction SilentlyContinue
        Sub ("Interface " + $i.InterfaceAlias + "  metric=" + $i.InterfaceMetric + "  link=" + $ad.LinkSpeed + "  [" + $ad.InterfaceDescription + "]")
    }
    $preferida = $ifs | Select-Object -First 1
    if ($preferida) {
        $adPref = Get-NetAdapter -InterfaceIndex $preferida.ifIndex -ErrorAction SilentlyContinue
        Sub ("Rota preferida (menor metrica): " + $preferida.InterfaceAlias + " [" + $adPref.InterfaceDescription + "]")
        $ehWifi = ($adPref.InterfaceDescription -match 'Wireless|Wi-Fi|802\.11|Wi-Fi') -or ($adPref.PhysicalMediaType -match '802\.11')
        if ($ehWifi) {
            Warn "O TRAFEGO ESTA A SAIR PELA WI-FI, nao pelo cabo! Se tens o cabo ligado, desliga a Wi-Fi (ou baixa a metrica do Ethernet) e volta a medir - e a diferenca entre ~10-80 Mbps e ~940 Mbps."
        }
    }
    $rotas = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric
    foreach ($r in $rotas) {
        $ad = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
        Sub ("Rota por omissao: via " + $r.InterfaceAlias + " -> " + $r.NextHop + "  (metrica " + $r.RouteMetric + ", " + $ad.InterfaceDescription + ")")
    }
    $ativas = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
    $temWifi = $ativas | Where-Object { $_.PhysicalMediaType -match '802\.11' -or $_.InterfaceDescription -match 'Wireless|Wi-Fi' }
    $temCabo = $ativas | Where-Object { $_.PhysicalMediaType -match '802\.3' -and $_.InterfaceDescription -notmatch 'Wireless|Wi-Fi' }
    if ($temWifi -and $temCabo) {
        Warn "Ha Wi-Fi E cabo ligados ao mesmo tempo. Para um teste limpo e para descarregar o BF6: desativa a Wi-Fi (ou poe a metrica da Wi-Fi bem mais alta) e confirma em '1c' que a rota preferida e o cabo."
    }
} catch { Warn ("Analise de rotas falhou: " + $_.Exception.Message) }

# Estado do link, MTU e descartes
try {
    foreach ($n in (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $st = Get-NetAdapterStatistics -Name $n.Name -ErrorAction SilentlyContinue
        $descartes = 0; $pct = 0
        if ($st) {
            $descartes = [int64]$st.ReceivedDiscardedPackets + [int64]$st.OutboundDiscardedPackets
            $rec = [int64]$st.ReceivedPackets
            if ($rec -gt 0) { $pct = [math]::Round(100.0 * $descartes / $rec, 3) }
        }
        Sub ($n.Name + ": link=" + $n.LinkSpeed + " | full duplex=" + $n.FullDuplex + " | MTU=" + $n.MtuSize + " | MAC=" + $n.MacAddress + " | descartes desde o arranque=" + $descartes + " (" + $pct + "%)")
        if ($descartes -gt 1000 -and $pct -gt 0.05) {
            Warn ("Descartes significativos em " + $n.Name + ": " + $descartes + " pacotes (" + $pct + "% do recebido). Cabo/porta com problemas ou link saturado - troca o cabo e a porta do router, e repete.")
        }
    }
} catch { }

# ----------------------------------------------------------------------------
# 2. PROXIES PRESOS  - suspeito no1 quando "a net ficou ma de repente"
# ----------------------------------------------------------------------------
Titulo "2. Proxies e intercecao ativa (suspeito no 1)"
$proxyEncontrado = $false

# 2.1 WinHTTP (netsh) - e isto que o OmniRoute/Traffic Inspector usa no Windows
try {
    $winhttp = (netsh winhttp show proxy) -join "`n"
    Sub "netsh winhttp show proxy:"
    ($winhttp -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { Sub ("    " + $_.Trim()) }
    if ($winhttp -match '127\.0\.0\.1|localhost|::1') {
        $proxyEncontrado = $true
        Warn "PROXY WinHTTP ativo a apontar para a tua propria maquina! Se o processo que o criou (ex.: Traffic Inspector do OmniRoute, Fiddler, mitmproxy) ja nao esta a correr, o trafego fica pendurado ou a passar por um salto extra. Corre: netsh winhttp reset proxy"
    }
} catch { }

# 2.2 Proxy de utilizador/Internet Options (WinINET) - afeta Edge, Steam(parcialmente), updaters
try {
    $reg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($reg) {
        Sub ("WinINET: ProxyEnable=" + $reg.ProxyEnable + "  ProxyServer='" + $reg.ProxyServer + "'  AutoConfigURL='" + $reg.AutoConfigURL + "'")
        if ($reg.ProxyEnable -eq 1 -and $reg.ProxyServer -match '127\.0\.0\.1|localhost') {
            $proxyEncontrado = $true
            Warn ("Proxy de sistema (WinINET) ligado para " + $reg.ProxyServer + ". Desliga em Definicoes > Rede e Internet > Proxy, ou no painel do OmniRoute em Traffic Inspector > 'Restore system proxy'.")
        }
        if ($reg.AutoConfigURL) { Warn ("PAC/AutoConfigURL definido (" + $reg.AutoConfigURL + ") - cada pedido passa por uma resolucao de script; atrasa muito downloads.") }
    }
    $regPc = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($regPc -and ($regPc.ProxyEnable -eq 1)) { Warn ("Proxy ao nivel da maquina (HKLM) ativo: " + $regPc.ProxyServer) }
} catch { }

# 2.3 Variaveis de ambiente (afetam curl, npm, git, python, muitos updaters)
foreach ($v in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','http_proxy','https_proxy','all_proxy')) {
    $val = [System.Environment]::GetEnvironmentVariable($v, 'User')
    if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($v, 'Machine') }
    if ($val) {
        Sub ($v + " = " + $val)
        if ($val -match '127\.0\.0\.1|localhost') { $proxyEncontrado = $true; Warn ($v + " aponta para localhost - se o proxy morreu, tudo o que use esta variavel falha ou arrasta.") }
    }
}

# 2.4 Portas locais ouvindo em proxy (8080/8888/3128/9090/7890) sem dono claro
try {
    $escuta = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in 8080, 8888, 9090, 3128, 8118, 7890, 1080 } |
        Select-Object -Unique LocalAddress, LocalPort, OwningProcess
    foreach ($e in $escuta) {
        $proc = (Get-Process -Id $e.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Sub ("Porta proxy a escuta: " + $e.LocalAddress + ":" + $e.LocalPort + "  ->  " + $proc)
    }
} catch { }

if (-not $proxyEncontrado) { Ok "Nenhum proxy preso detetado (WinHTTP, WinINET e variaveis de ambiente limpas)." }

# ----------------------------------------------------------------------------
# 3. DNS
# ----------------------------------------------------------------------------
Titulo "3. DNS"
try {
    $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object -First 3
    foreach ($d in $dns) { Sub ($d.InterfaceAlias + " -> " + ($d.ServerAddresses -join ", ")) }
    foreach ($host_ in @('speed.cloudflare.com','store.steampowered.com','cdn.akamai.steamstatic.com')) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $r = Resolve-DnsName -Name $host_ -Type A -DnsOnly -ErrorAction Stop | Where-Object { $_.IPAddress } | Select-Object -First 1
            $sw.Stop()
            $ms = [int]$sw.ElapsedMilliseconds
            Sub ("Resolve " + $host_ + " -> " + $r.IPAddress + "  (" + $ms + " ms)")
            if ($ms -gt 300) { Warn ("Resolucao DNS lenta para " + $host_ + " (" + $ms + " ms). Muda para DNS de operador com cache proxima ou 1.1.1.1/9.9.9.9/8.8.8.8.") }
        } catch {
            $sw.Stop()
            Warn ("Nao consegui resolver " + $host_ + ": " + $_.Exception.Message)
        }
    }
} catch { Warn ("Falha na analise de DNS: " + $_.Exception.Message) }

# ----------------------------------------------------------------------------
# 4. Latencia, perda, jitter  +  BUFFERBLOAT
# ----------------------------------------------------------------------------
Titulo "4. Latencia, perda de pacotes e bufferbloat"

function Get-PingStats($alvo, $contagem) {
    $res = Test-Connection -ComputerName $alvo -Count $contagem -ErrorAction SilentlyContinue
    if (-not $res) { return $null }
    $tempos = @($res | Where-Object { $_.StatusCode -eq 0 -and $null -ne $_.ResponseTime } | ForEach-Object { [int]$_.ResponseTime })
    if ($tempos.Count -eq 0) { return @{ Perda = 100; Min = 0; Media = 0; Max = 0; Jitter = 0 } }
    $perda = [math]::Round(100.0 * ($contagem - $tempos.Count) / $contagem, 1)
    $jitters = @()
    for ($i = 1; $i -lt $tempos.Count; $i++) { $jitters += [math]::Abs($tempos[$i] - $tempos[$i - 1]) }
    $j = if ($jitters.Count) { [int](($jitters | Measure-Object -Average).Average) } else { 0 }
    return @{
        Perda  = $perda
        Min    = ($tempos | Measure-Object -Minimum).Minimum
        Media  = [int](($tempos | Measure-Object -Average).Average)
        Max    = ($tempos | Measure-Object -Maximum).Maximum
        Jitter = $j
    }
}

$fontes = @(
    @{ Nome = 'Cloudflare (1.1.1.1)'; Alvo = '1.1.1.1' },
    @{ Nome = 'Google DNS (8.8.8.8)'; Alvo = '8.8.8.8' },
    @{ Nome = 'Google (google.com)';  Alvo = 'google.com' },
    @{ Nome = 'Steam CDN (steampowered.com)'; Alvo = 'store.steampowered.com' }
)
$reps = 15
$bufBase = $null
$bufAlvo = $null
foreach ($f in $fontes) {
    $s = Get-PingStats $f.Alvo $reps
    if (-not $s) { Warn ("Sem resposta de " + $f.Nome); continue }
    if ($s.Perda -ge 100 -and $s.Media -eq 0) {
        Warn ("Sem resposta de " + $f.Nome + " (ICMP bloqueado pela rede/ISP ou alvo inacessivel) - sem medicao de latencia/perda aqui.")
        continue
    }
    Sub ($f.Nome.PadRight(30) + " min " + $s.Min + " ms | media " + $s.Media + " ms | max " + $s.Max + " ms | jitter " + $s.Jitter + " ms | perda " + $s.Perda + "%")
    if ($f.Alvo -eq '1.1.1.1') {
        $bufBase = $s; $bufAlvo = $f.Alvo
    } elseif (-not $bufBase -and $f.Alvo -eq '8.8.8.8') {
        # 1.1.1.1 nao responde a ICMP em muitas redes; usa o Google como referencia.
        $bufBase = $s; $bufAlvo = $f.Alvo
    }
    if ($s.Perda -gt 1) { Warn ("Perda de pacotes de " + $s.Perda + "% em " + $f.Nome + " - ligacao instavel (cabo/Wi-Fi/router/ISP).") }
    if ($s.Jitter -gt 30) { Warn ("Jitter alto (" + $s.Jitter + " ms) em " + $f.Nome + " - mau para jogos e para o proprio TCP (descarregamentos aos solucos).") }
}

# Bufferbloat: mede a latencia ENQUANTO a linha esta saturada.
# E este teste que explica "a net e boa quando ninguem esta a usar nada".
$curlExe = $null
$c = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($c) { $curlExe = $c.Source }

if ($curlExe -and $bufBase -and -not $SemDisco) {
    Sub ("A saturar a linha durante ~10 s para medir o bufferbloat (referencia: " + $bufAlvo + ")...")
    $proc = $null
    try {
        $proc = Start-Process -FilePath $curlExe -ArgumentList @(
            '-s','-L','-o','NUL','--connect-timeout','8','--max-time','25',
            'https://speed.cloudflare.com/__down?bytes=400000000'
        ) -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 3
        $bufCarregado = Get-PingStats $bufAlvo 12
        if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        if ($bufCarregado) {
            $delta = $bufCarregado.Media - $bufBase.Media
            Sub ("Em carga: media " + $bufCarregado.Media + " ms  (repouso " + $bufBase.Media + " ms  ->  +" + $delta + " ms)")
            if ($bufCarregado.Perda -gt 3) { Warn ("Com a linha ocupada perdes " + $bufCarregado.Perda + "% dos pacotes - o router esta a encher a fila e a descartar. Ativa SQM/QoS (fq_codel) no router.") }
            if ($delta -gt 200) {
                Warn ("BUFFERBLOAT grave: +" + $delta + " ms quando a linha enche. Um download a 10 Mbit/s pode deixar a casa toda sem net utilizavel. Solucao: SQM/QoS/QoS adaptativo no router, ou limitar a velocidade de download a ~90% da linha.")
            } elseif ($delta -gt 80) {
                Warn ("Bufferbloat moderado: +" + $delta + " ms sob carga. Limita a velocidade de download (ex.: 90% da linha) para manter a net responsiva.")
            } else {
                Ok ("Bufferbloat controlado (+" + $delta + " ms sob carga).")
            }
        }
    } catch {
        Warn ("Teste de bufferbloat falhou: " + $_.Exception.Message)
        if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
} elseif (-not $curlExe) {
    Info "curl.exe nao encontrado - salto o teste de bufferbloat (o Windows 10 1803+ traz curl.exe em C:\Windows\System32)."
}

# ----------------------------------------------------------------------------
# 5. MTU / fragmentacao
# ----------------------------------------------------------------------------
Titulo "5. MTU (fragmentacao de pacotes)"
$mtuOk = $false
foreach ($tam in @(1472, 1464, 1452, 1400, 1300, 1272, 548)) {
    $null = ping -n 1 -f -l $tam -w 1500 1.1.1.1 2>$null
    if ($LASTEXITCODE -eq 0) {
        $mtu = $tam + 28
        Sub ("Payload de " + $tam + " bytes sem fragmentar passou -> MTU da linha = " + $mtu)
        if ($mtu -lt 1500) { Warn ("MTU reduzido (" + $mtu + " em vez de 1500, tipico de PPPoE/VPN/tuneis). Handshakes TLS e uploads sofrem; confirma no router.") }
        else { Ok "MTU em 1500 (ideal)." }
        $mtuOk = $true
        break
    }
}
if (-not $mtuOk) { Warn "Nao passou nenhum payload, mesmo pequeno - a resposta ICMP com DF esta a ser bloqueada ou a linha tem problemas." }

# ----------------------------------------------------------------------------
# 6. Velocidade real de download
# ----------------------------------------------------------------------------
Titulo "6. Velocidade real de download (so medicoes validas)"
Info "O plano e 1000 Mbps / 100 Mbps. O teto pratico e ~90-95% disso com tudo limpo."
Info "Uma medicao so conta se transferir >=20 MB (ficheiros pequenos dao numeros falsos)."

$curlSpeed = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
$resultados = @()
$minBytes = 20MB
$fontesVel = @(
    @{ Nome = 'Cloudflare'; Url = 'https://speed.cloudflare.com/__down?bytes=100000000' },
    @{ Nome = 'OVH (Franca)'; Url = 'https://proof.ovh.net/files/100Mb.dat' },
    @{ Nome = 'Tele2 (HTTP)'; Url = 'http://speedtest.tele2.net/100MB.zip' },
    @{ Nome = 'Cachefly (HTTP)'; Url = 'http://cachefly.cachefly.net/100mb.test' },
    @{ Nome = 'Leaseweb (NL)'; Url = 'https://mirror.leaseweb.com/speedtest/100mb.bin' }
)
foreach ($f in $fontesVel) {
    if ($curlSpeed) {
        $raw = & $curlSpeed -s -L -o NUL --connect-timeout 8 --max-time 15 -w '%{http_code}|%{size_download}|%{speed_download}|%{time_total}' $f.Url 2>$null
        $p = (($raw | Out-String).Trim()) -split '\|'
        $http = 0; $bytes = 0L; $bps = 0.0; $seg = 0.0
        if ($p.Count -ge 4) {
            [void][int]::TryParse($p[0].Trim(), [ref]$http)
            [void][int64]::TryParse($p[1].Trim(), [ref]$bytes)
            [void][double]::TryParse($p[2].Trim(), [ref]$bps)
            [void][double]::TryParse($p[3].Trim(), [ref]$seg)
        }
        $mb = [math]::Round($bytes / 1MB, 1)
        if ($http -eq 200 -and $bytes -ge $minBytes) {
            $mbps = $bps * 8.0 / 1000000.0
            $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $true; Motivo = ''; Mbps = $mbps; MB = $mb; Seg = $seg }
            $cor = 'Green'; if ($mbps -lt 300) { $cor = 'Yellow' }; if ($mbps -lt 100) { $cor = 'Red' }
            Write-Host ("  - " + $f.Nome.PadRight(16) + " " + ([math]::Round($mbps,1)).ToString().PadLeft(7) + " Mbps   (" + $mb + " MB em " + [math]::Round($seg,1) + " s)") -ForegroundColor $cor
        } else {
            $motivo = if ($http -ne 200) { "HTTP $http" } elseif ($bytes -lt $minBytes) { "so $mb MB (curto para medir)" } else { 'sem resposta' }
            $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $false; Motivo = $motivo; Mbps = 0; MB = $mb; Seg = $seg }
            Write-Host ("  - " + $f.Nome.PadRight(16) + " INVALIDO: " + $motivo) -ForegroundColor DarkYellow
        }
    } else {
        try {
            $req = [System.Net.HttpWebRequest]::Create($f.Url); $req.Timeout = 15000
            $resp = $req.GetResponse(); $stream = $resp.GetResponseStream()
            $buf = New-Object byte[] 65536; $total = 0
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 10) { $n = $stream.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $total += $n }
            $stream.Close(); $resp.Close(); $sw.Stop()
            if ($total -ge $minBytes) {
                $mbps = ($total * 8.0) / 1000000.0 / $sw.Elapsed.TotalSeconds
                $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $true; Motivo = ''; Mbps = $mbps; MB = [math]::Round($total/1MB,1); Seg = $sw.Elapsed.TotalSeconds }
                Write-Host ("  - " + $f.Nome.PadRight(16) + " " + ([math]::Round($mbps,1)).ToString().PadLeft(7) + " Mbps") -ForegroundColor Green
            }
        } catch { }
    }
}

# Steam: so confirma o ACESSO (o ficheiro do instalador tem ~2 MB - nao mede velocidade)
try {
    if ($curlSpeed) {
        $st = & $curlSpeed -s -o NUL -w '%{http_code}' --max-time 10 'https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe' 2>$null
        if (($st | Out-String).Trim() -eq '200') { Ok "Steam CDN acessivel (HTTP 200) - nao usada para velocidade (ficheiro pequeno)." }
        else { Warn ("Steam CDN devolveu HTTP " + ($st | Out-String).Trim() + " - pode estar bloqueada ou filtrada.") }
    }
} catch { }

$validosVel = @($resultados | Where-Object { $_.Valido })
if ($validosVel.Count -gt 0) {
    $melhor = $validosVel | Sort-Object Mbps -Descending | Select-Object -First 1
    Sub ("Melhor resultado: " + $melhor.Nome + " = " + [math]::Round($melhor.Mbps,1) + " Mbps (" + [math]::Round($melhor.Mbps/8,1) + " MB/s)")
    [void]$script:Veredito.Add([pscustomobject]@{ Chave = 'download'; Valor = $melhor.Mbps })
    if ($melhor.Mbps -lt 50) {
        Erro "Nenhuma fonte passou dos 50 Mbps. A ligacao real esta longe do plano - o problema NAO e do Steam."
    } elseif ($melhor.Mbps -lt 300) {
        Warn ("Maximo de " + [math]::Round($melhor.Mbps,1) + " Mbps. Numa linha de 1 Gbps isto aponta para link a 100 Mbps (cabo/porta/NIC), QoS do router, ou Wi-Fi.")
    } else {
        Ok ("Ligacao a " + [math]::Round($melhor.Mbps,1) + " Mbps - linha saudavel. Se o Steam continua lento, o gargalo e do Steam ou do disco.")
    }
    if ($validosVel.Count -ge 2) {
        $pior = $validosVel | Sort-Object Mbps | Select-Object -First 1
        if ($melhor.Mbps -gt 200 -and $pior.Mbps -lt ($melhor.Mbps / 4)) {
            Warn ("Diferenca enorme entre CDNs (" + $pior.Nome + ": " + [math]::Round($pior.Mbps,1) + " Mbps vs " + $melhor.Nome + ": " + [math]::Round($melhor.Mbps,1) + " Mbps). Tipico de peering/rota do ISP para essa rede - testar DNS 1.1.1.1 e outra hora do dia.")
        }
    }
} else {
    Warn "INCONCLUSIVO: nenhuma fonte deu uma medicao valida (>=20 MB). Isto NAO significa 'linha lenta'."
    Info "Confirma a mao e ve o erro: curl.exe -v -o NUL --max-time 15 `"https://speed.cloudflare.com/__down?bytes=20000000`""
    Info "Se aparecer 'SSL certificate problem' / 'schannel', ha inspecao HTTPS ativa (antivirus ou Traffic Inspector do OmniRoute - seccao 8)."
}
Info "Nota: o Steam instala com centenas de ficheiros pequenos - a velocidade 'util' e sempre bem menor que o teste de 100 MB, e o disco/CPU contam."

# ----------------------------------------------------------------------------
# 6b. Opcoes TCP globais do Windows (autotuning do receive window)
#     Quando isto esta desligado, muitos adaptadores (sobretudo Intel AX200)
#     nao passam dos 50-100 Mbps em downloads grandes. E um classico.
# ----------------------------------------------------------------------------
Titulo "6b. Opcoes TCP globais do Windows"
try {
    $tcp = (netsh int tcp show global) -join "`n"
    foreach ($linha in ($tcp -split "`n")) {
        if ($linha.Trim()) { Sub ($linha.Trim()) }
    }
    $autotune = [regex]::Match($tcp, '(?im)^\s*(Receive Window Auto-Tuning Level|N.vel de ajuste autom.tico da janela de recep..o|Auto-Tuning Level)[^:]*:\s*(\S+)')
    if ($autotune.Success) {
        $nivel = $autotune.Groups[2].Value.Trim().ToLowerInvariant()
        if ($nivel -match '^(disabled|restricted|desativado|restrito|highlyrestricted)') {
            Warn ("O auto-tuning da janela TCP esta em '" + $autotune.Groups[2].Value + "'. Isto trava o debito em ligacoes de alta latencia (e e uma causa citada de AX200 lento). Corrige como administrador: netsh int tcp set global autotuninglevel=normal")
        } else {
            Ok ("Auto-tuning da janela TCP em '" + $autotune.Groups[2].Value + "' (normal).")
        }
    }
    if ($tcp -match '(?im)^\s*(Chimney Offload State|TCP Chimney Offload)[^:]*:\s*(enabled|ativado)') {
        Warn "TCP Chimney Offload esta ligado - em placas Intel antigas ja causou debito baixo. Testa: netsh int tcp set global chimney=disabled"
    }
} catch { Warn ("Nao consegui ler as opcoes TCP globais: " + $_.Exception.Message) }

Titulo "7. Intercecao TLS (hosts + certificados raiz)"
$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
try {
    $linhas = Get-Content -LiteralPath $hostsPath -ErrorAction Stop |
        Where-Object { $_.Trim() -ne '' -and $_.Trim() -notmatch '^#' }
    if ($linhas) {
        Sub ("Entradas ativas em " + $hostsPath + ":")
        foreach ($l in $linhas) { Sub ("    " + $l.Trim()) }
        $perigosas = $linhas | Where-Object { $_ -match 'anthropic|openai|chatgpt|claude|gemini|googleapis|cloudcode|copilot|antigravity|zed|cursor|omniroute|steam|akamai|cloudflare' }
        if ($perigosas) {
            Warn ("Ha hosts de servicos/agentes/CDN redirecionados no ficheiro hosts (intercecao ativa ou restos dela). Se o OmniRoute/AgentBridge ja nao esta a correr, isto parte esses servicos. Limpa estas linhas ou usa o botao 'Repair' do OmniRoute.")
        }
    } else {
        Ok "Ficheiro hosts limpo (sem entradas ativas)."
    }
} catch { Warn ("Nao consegui ler o ficheiro hosts: " + $_.Exception.Message) }

try {
    $certs = Get-ChildItem -Path Cert:\CurrentUser\Root, Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -match 'OmniRoute|mitmproxy|mitm|Fiddler|Charles|intercept' -or $_.Issuer -match 'OmniRoute|mitmproxy|Fiddler|Charles' } |
        Select-Object Subject, Thumbprint, NotAfter, NotBefore
    if ($certs) {
        foreach ($cert in $certs) {
            Warn ("Certificado raiz de intercecao instalado: " + $cert.Subject + "  (valido ate " + $cert.NotAfter.ToString('yyyy-MM-dd') + ", thumbprint " + $cert.Thumbprint.Substring(0,16) + "...)")
        }
        Sub "Remover (PowerShell como admin): Get-ChildItem Cert:\CurrentUser\Root | Where-Object { `$_.Subject -match 'OmniRoute' } | Remove-Item"
    } else {
        Ok "Nenhum certificado raiz de intercecao (OmniRoute/mitmproxy/Fiddler) instalado."
    }
} catch { }

# ----------------------------------------------------------------------------
# 8. Steam
# ----------------------------------------------------------------------------
Titulo "8. Configuracao do Steam"
try {
    $steamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if (-not $steamPath) { $steamPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath -ErrorAction SilentlyContinue).InstallPath }
    if ($steamPath) {
        $steamPath = $steamPath -replace '/', '\'
        Sub ("Instalacao: " + $steamPath)
        # Limites de download
        $cfg = Join-Path $steamPath 'config\config.vdf'
        if (Test-Path $cfg) {
            $interessantes = Select-String -Path $cfg -Pattern '"?Rate"?\s+"?(\d+)"?|"?Throttle"?\s+"?(\d+)"?|DownloadThrottle|LimitDownload' -ErrorAction SilentlyContinue
            if ($interessantes) {
                Sub "Limites encontrados em config.vdf:"
                foreach ($i in $interessantes) { Sub ("    " + $i.Line.Trim()) }
                Warn "O Steam guarda aqui o limite de largura de banda. Se estiver em 10-15 Mbps (~1,3 MB/s) e exatamente o que estas a ver. Desliga em: Steam > Definicoes > Downloads > 'Limitar largura de banda de descarga' / Throttle."
            } else {
                Ok "Sem limite de largura de banda configurado no Steam (config.vdf)."
            }
        }
        # Regiao de download
        $cfgLogin = Join-Path $steamPath 'config\loginusers.vdf'
        # Pastas de biblioteca (onde os jogos instalam -> onde o disco pode ser o gargalo)
        $libs = @()
        foreach ($lf in @((Join-Path $steamPath 'steamapps\libraryfolders.vdf'), (Join-Path $steamPath 'config\libraryfolders.vdf'))) {
            if (Test-Path $lf) {
                $libs += (Select-String -Path $lf -Pattern '"path"\s+"([^"]+)"' -AllMatches).Matches | ForEach-Object { $_.Groups[1].Value -replace '/', '\' }
                break
            }
        }
        if ($libs) {
            Sub "Pastas de biblioteca (onde o BF6 esta/fica):"
            foreach ($l in ($libs | Select-Object -Unique)) { Sub ("    " + $l) }
            $script:SteamLibs = ($libs | Select-Object -Unique)
        }
        # Processos do Steam a consumir rede agora
        $uso = Get-Process -Name 'steam','steamwebhelper','steamservice' -ErrorAction SilentlyContinue
        if ($uso) { Sub ("Steam em execucao (" + ($uso | Measure-Object).Count + " processos).") }
    } else {
        Info "Steam nao encontrado no registo (ou nao instalado). Salto esta seccao."
    }
    $bf = Get-Process -Name 'bf6','battlefield6','Battlefield*' -ErrorAction SilentlyContinue
    if ($bf) { Info ("Processo do Battlefield em execucao: " + (($bf | Select-Object -ExpandProperty ProcessName) -join ", ")) }
} catch { Warn ("Analise do Steam falhou: " + $_.Exception.Message) }

# ----------------------------------------------------------------------------
# 9. Disco - o suspeito invisivel dos downloads grandes
# ----------------------------------------------------------------------------
Titulo "9. Escrita em disco (onde os jogos instalam)"
if ($SemDisco) {
    Info "Teste de disco saltado (-SemDisco)."
} else {
    Info ("A criar ficheiros temporarios de " + $MBDisco + " MB e a apaga-los logo a seguir...")

    function Test-EscritaDisco($pasta, $mb) {
        $alvo = Join-Path $pasta 'omniroute_speedtest.tmp'
        try {
            $bytes = $mb * 1MB
            $buf = New-Object byte[] (4MB)
            (New-Object System.Random).NextBytes($buf)
            $fs = [System.IO.File]::Create($alvo)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $escritos = 0
            while ($escritos -lt $bytes) {
                $fs.Write($buf, 0, $buf.Length)
                $escritos += $buf.Length
            }
            $fs.Flush($true)
            $fs.Close()
            $sw.Stop()
            Remove-Item -LiteralPath $alvo -Force -ErrorAction SilentlyContinue
            return @{ MBs = ($escritos / 1MB) / $sw.Elapsed.TotalSeconds; OK = $true }
        } catch {
            try { if ($fs) { $fs.Close() } } catch { }
            Remove-Item -LiteralPath $alvo -Force -ErrorAction SilentlyContinue
            return @{ MBs = 0; OK = $false; Erro = $_.Exception.Message }
        }
    }

    # Discos onde o Steam instala + o disco do sistema
    $discosTestar = @()
    if ($script:SteamLibs) { $discosTestar += $script:SteamLibs }
    $discosTestar += ($env:SystemDrive + '\')
    $discosTestar = $discosTestar |
        Where-Object { $_ } |
        ForEach-Object { (($_ -replace '/', '\').TrimStart()) } |
        ForEach-Object { if ($_.Length -ge 2) { $_.Substring(0,2).ToUpperInvariant() } else { '' } } |
        Where-Object { $_ -match '^[A-Z]:$' } |
        Select-Object -Unique

    foreach ($letra in $discosTestar) {
        $pasta = $letra + '\'
        if (-not (Test-Path $pasta)) {
            Warn ("Disco " + $pasta + " nao existe/inacessivel - se o Steam aponta para la, e mais um problema em cima.")
            continue
        }
        try {
            $vol = Get-Volume -DriveLetter $letra[0] -ErrorAction SilentlyContinue
            if ($vol) { Sub ("Disco " + $pasta + " (" + $vol.FileSystemType + ") livre: " + [math]::Round($vol.SizeRemaining/1GB,1) + " GB de " + [math]::Round($vol.Size/1GB,1) + " GB") }
            $r = Test-EscritaDisco $pasta $MBDisco
            if (-not $r.OK) {
                Erro ("Nao consegui escrever em " + $pasta + ": " + $r.Erro + " (disco cheio, protegido ou avariado?)")
                continue
            }
            $mbpsDisco = $r.MBs
            $cor = 'Green'; if ($mbpsDisco -lt 120) { $cor = 'Yellow' }; if ($mbpsDisco -lt 60) { $cor = 'Red' }
            Write-Host ("  - Escrita em " + $pasta.PadRight(6) + " " + [math]::Round($mbpsDisco,0).ToString().PadLeft(6) + " MB/s  (" + [math]::Round($mbpsDisco*8/1000,2) + " Gbps)") -ForegroundColor $cor
            if ($mbpsDisco -lt 60) {
                Warn ("Disco " + $pasta + " escreve a " + [math]::Round($mbpsDisco,0) + " MB/s. Isto limita QUALQUER download a ~" + [math]::Round($mbpsDisco*8/1000,1) + " Gbps (>1 Gbps e o esperado num NVMe). HDD ou disco quase cheio?")
            }
        } catch { Warn ("Teste de disco em " + $pasta + " falhou: " + $_.Exception.Message) }
    }

    # SMART: erros de leitura/escrita que arrastam downloads
    try {
        $smart = Get-WmiObject -Namespace 'root\wmi' -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        foreach ($s in $smart) {
            if ($s.PredictFailure) { Warn ("SMART do disco " + $s.InstanceName + " preve falha - backup ja, e verifica com CrystalDiskInfo.") }
        }
    } catch { }
}

# ----------------------------------------------------------------------------
# RESUMO
# ----------------------------------------------------------------------------
Titulo "RESUMO"
if ($script:Falhas.Count -eq 0 -and $script:Alertas.Count -eq 0) {
    Ok "Nenhum problema detetado nesta passagem. Guarda o relatorio e repete o teste a meio de um download lento."
} else {
    if ($script:Falhas.Count -gt 0) {
        Write-Host ("  FALHAS (" + $script:Falhas.Count + "):") -ForegroundColor Red
        foreach ($f in $script:Falhas) { Write-Host ("   x " + $f) -ForegroundColor Red }
    }
    if ($script:Alertas.Count -gt 0) {
        Write-Host ("  ATENCAO (" + $script:Alertas.Count + "):") -ForegroundColor Yellow
        foreach ($a in $script:Alertas) { Write-Host ("   ! " + $a) -ForegroundColor Yellow }
    }
}

Write-Host ""
$dl = ($script:Veredito | Where-Object { $_.Chave -eq 'download' } | Select-Object -First 1)
if (-not $dl) {
    Write-Host "  VEREDITO: nao consegui medir a velocidade de download (sem curl, sem rede ou tudo bloqueado)." -ForegroundColor Yellow
    Write-Host "            Confirma primeiro que esta maquina navega; depois volta a correr o diagnostico." -ForegroundColor Yellow
}
if ($dl) {
    if ($dl.Valor -lt 50) {
        Write-Host "  VEREDITO: a linha/PC esta a entregar menos de 50 Mbps. O problema e de rede/PC, nao do Steam nem do BF6." -ForegroundColor Red
        Write-Host "            Ordem de ataque: cabo em vez de Wi-Fi -> reiniciar router -> testar com outro PC -> chamar o ISP." -ForegroundColor Red
    } elseif ($dl.Valor -lt 300) {
        Write-Host "  VEREDITO: entre 50 e 300 Mbps. Ligacao utilizavel mas abaixo do plano de 1 Gbps - foca-te em Wi-Fi/cabo/router/QoS." -ForegroundColor Yellow
    } else {
        Write-Host "  VEREDITO: a linha entrega bem (>300 Mbps). Se o Steam continua a 10 Mbit/s, o gargalo e do Steam ou do disco." -ForegroundColor Green
        Write-Host "            Verifica: limite de downloads do Steam, regiao de download, disco saturado/HDD, e ficheiros pequenos (instalacao)." -ForegroundColor Green
    }
}
Write-Host ""
Write-Host ("  Relatorio guardado em: " + $logFicheiro) -ForegroundColor DarkGray
Write-Host "  Segue as acoes do ficheiro LEIA-ME do kit (docs/help/pt-PT/README.md)." -ForegroundColor DarkGray
Write-Host ""

try { Stop-Transcript | Out-Null } catch { }
