<#
    diagnostico-net-lenta.ps1  —  "a minha net ficou má" : uma passagem de diagnóstico
    ----------------------------------------------------------------------------------
    Corres isto quando algo está lento a transferir (Steam, Epic, downloads) e queres
    saber rapidamente ONDE está o gargalo: linha/ISP, Wi-Fi/cabo, router, PC, disco,
    ou um proxy/DNS que ficou preso à frente do tráfego (ex.: Traffic Inspector do
    OmniRoute).

    COMO CORRER (não precisa de admin para 95% dos testes):
        powershell -ExecutionPolicy Bypass -File .\diagnostico-net-lenta.ps1

    Opções:
        -SemDisco          salta o teste de escrita em disco (rápido)
        -MBDisco 1024      tamanho do ficheiro de teste (por omissão 512 MB)

    O que faz (por esta ordem):
        1. Identidade da ligação (interface, velocidade de link, Wi-Fi vs cabo)
        2. Proxies presos (WinHTTP, WinINET, variáveis de ambiente)  <-- suspeito nº1
        3. DNS (servidores configurados + tempo de resolução)
        4. Latência / perda / jitter  e teste de BUFFERBLOAT (ping com a linha ocupada)
        5. MTU / fragmentação (PPPoE, VPN, túneis)
        6. Velocidade real de download contra 3 CDNs independentes
        7. Ficheiros hosts + certificados raiz suspeitos (interceção TLS)
        8. Estado do Steam (limites de download, pastas de biblioteca)
        9. Escrita em disco nos discos onde o Steam instala (o suspeito "invisível")

    NÃO altera nada no sistema. Só lê e mede. Podes partilhar o .txt gerado.
#>

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

# ── Saída também para ficheiro, para poderes colar num ticket/fórum ──────────
$raiz = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$logFicheiro = Join-Path $raiz ("diagnostico-rede-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + ".txt")
try { Start-Transcript -Path $logFicheiro -Force | Out-Null } catch { }

function Titulo($texto) {
    Write-Host ""
    Write-Host ("═" * 78) -ForegroundColor DarkGray
    Write-Host ("  " + $texto) -ForegroundColor Cyan
    Write-Host ("═" * 78) -ForegroundColor DarkGray
}
function Sub($texto) { Write-Host ("  · " + $texto) -ForegroundColor Gray }
function Ok($texto)  { Write-Host ("  [OK]    " + $texto) -ForegroundColor Green }
function Warn($texto) {
    Write-Host ("  [ATENÇÃO] " + $texto) -ForegroundColor Yellow
    [void]$script:Alertas.Add($texto)
}
function Erro($texto) {
    Write-Host ("  [FALHA] " + $texto) -ForegroundColor Red
    [void]$script:Falhas.Add($texto)
}
function Info($texto) { Write-Host ("  [i]     " + $texto) -ForegroundColor DarkCyan }

Write-Host ""
Write-Host "  DIAGNÓSTICO DE REDE — iniciado $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "  Máquina: $env:COMPUTERNAME   Utilizador: $env:USERNAME" -ForegroundColor DarkGray

# ────────────────────────────────────────────────────────────────────────────
# 0. Contexto do sistema
# ────────────────────────────────────────────────────────────────────────────
Titulo "0. Contexto do sistema"
Sub ("SO: " + (Get-CimInstance Win32_OperatingSystem).Caption + " build " + [System.Environment]::OSVersion.Version)
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
Sub ("CPU: " + $cpu.Name + "  (" + $cpu.NumberOfCores + " núcleos / " + $cpu.NumberOfLogicalProcessors + " threads)")
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Sub ("RAM: " + $ramGB + " GB")
$uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Sub ("Uptime: " + [int]$uptime.TotalHours + " h " + $uptime.Minutes + " min")

# Processos que costumam "comer" a linha / interceção de tráfego
$suspeitos = @('omniroute', 'mitmproxy', 'mitm', 'fiddler', 'charles', 'burp', 'clash', 'v2ray', 'xray', 'sing-box', 'wireguard', 'openvpn', 'qbittorrent', 'utorrent', 'qbittorrent', 'steam')
$correndo = Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $n = $_.ProcessName.ToLowerInvariant()
    ($suspeitos | Where-Object { $n -like ("*" + $_ + "*") }) -ne $null
} | Select-Object -ExpandProperty ProcessName -Unique
if ($correndo) {
    Info ("Processos relevantes em execução: " + ($correndo -join ", "))
    foreach ($p in $correndo) {
        if ($p -match 'omniroute|mitm|fiddler|charles|burp|clash|v2ray|xray|sing-box') {
            Warn ("'" + $p + "' está em execução — qualquer proxy/interceção ativa pode estar a limitar TODO o tráfego.")
        }
        if ($p -match 'qbittorrent|utorrent') {
            Warn ("'" + $p + "' está em execução — clientes de torrent saturam a linha e a tabela NAT do router.")
        }
    }
} else {
    Ok "Nenhum proxy/cliente de torrent conhecido em execução (por nome de processo)."
}
# Segunda passagem: por linha de comando, para apanhar proxies a correr dentro de
# node.exe / bun.exe / python.exe (é assim que o OmniRoute e o mitmproxy arrancam).
try {
    $porCmd = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -and
            $_.CommandLine -match 'omniroute|mitmproxy|mitmdump|traffic-inspector|fiddler|charles' -and
            $_.CommandLine -notmatch 'docs[\\/]help[\\/]pt-PT'
        } | Select-Object -First 6
    foreach ($c in $porCmd) {
        Warn ("Processo de proxy/interceção detetado pela linha de comando: " + $c.Name + " (pid " + $c.ProcessId + "). Se não o estás a usar agora, fecha-o — pode estar a limitar/atrasar todo o tráfego.")
    }
} catch { }

# ────────────────────────────────────────────────────────────────────────────
# 1. Ligação e camada física
# ────────────────────────────────────────────────────────────────────────────
Titulo "1. Interface de rede e camada física"
try {
    $adaptadores = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    if (-not $adaptadores) { Erro "Nenhum adaptador de rede ativo!" }
    foreach ($a in $adaptadores) {
        $tipo = if ($a.PhysicalMediaType) { $a.PhysicalMediaType } else { $a.MediaType }
        Sub ($a.Name + "  [" + $a.InterfaceDescription + "]")
        Sub ("    Tipo: " + $tipo + "   |   Velocidade negociada: " + $a.LinkSpeed + "   |   Duplex: " + $a.FullDuplex)
        if ($a.LinkSpeed -match '^(\d+)') {
            $mbps = [int]$matches[1]
        } else { $mbps = 0 }
        if ($mbps -lt 1000 -and $tipo -notmatch 'Wireless|802\.11|Wi-Fi') {
            Warn ("A porta de rede negociou apenas " + $a.LinkSpeed + ". Numa ligação de 1 Gbps isto é o teto: cabo CAT5e/6 danificado, porta de router 100M, ou switch/managed mal configurado.")
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
                $rx = [regex]::Match($netsh, '(?im)^\s*(Taxa de receção|Receive rate)\s*:\s*([\d\.]+)').Groups[2].Value
                Sub ("Wi-Fi: SSID='" + $ssid + "'  canal=" + $canal + "  sinal=" + $sinal + "%  banda=" + $banda + "  rx=" + $rx + " Mbps")
                if ($sinal -and [int]$sinal -lt 60) { Warn ("Sinal Wi-Fi fraco (" + $sinal + "%). Ligação a 1 Gbps por Wi-Fi nestas condições dá 10-80 Mbps reais.") }
                if ($banda -match '2,4|2\.4') { Warn "Estás ligado a Wi-Fi 2,4 GHz — o teto prático ronda os 100-150 Mbps mesmo com bom sinal. Usa 5/6 GHz ou cabo." }
                if ($canal -and [int]$canal -le 14) { Warn "Canal em 2,4 GHz (muito congestionado em zonas residenciais)." }
            } catch { }
        }
        Warn "Estás em Wi-Fi. Para testar a linha a sério (e para descarregar o BF6), usa cabo Ethernet."
    } else {
        Ok "Ligação por cabo (não há Wi-Fi ativo)."
    }
} catch {
    Warn ("Não foi possível enumerar adaptadores: " + $_.Exception.Message)
}

# Porta do router / gateway
try {
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
    if ($gw) {
        Sub ("Gateway/router: " + $gw)
        $pingGw = Test-Connection -ComputerName $gw -Count 5 -ErrorAction SilentlyContinue
        if ($pingGw) {
            $media = ($pingGw | Measure-Object -Property ResponseTime -Average).Average
            Sub ("Latência até ao router: " + [int]$media + " ms")
            if ($media -gt 5) {
                Warn ("Latência até ao router é alta (" + [int]$media + " ms). Em Wi-Fi o normal é 1-5 ms; valores acima disto indicam sinal fraco, canal saturado ou router sobrecarregado.")
            }
        }
    }
} catch { }

# ────────────────────────────────────────────────────────────────────────────
# 2. PROXIES PRESOS  — suspeito nº1 quando "a net ficou má de repente"
# ────────────────────────────────────────────────────────────────────────────
Titulo "2. Proxies e interceção ativa (suspeito nº 1)"
$proxyEncontrado = $false

# 2.1 WinHTTP (netsh) — é isto que o OmniRoute/Traffic Inspector usa no Windows
try {
    $winhttp = (netsh winhttp show proxy) -join "`n"
    Sub "netsh winhttp show proxy:"
    ($winhttp -split "`n") | Where-Object { $_.Trim() } | ForEach-Object { Sub ("    " + $_.Trim()) }
    if ($winhttp -match '127\.0\.0\.1|localhost|::1') {
        $proxyEncontrado = $true
        Warn "PROXY WinHTTP ativo a apontar para a tua própria máquina! Se o processo que o criou (ex.: Traffic Inspector do OmniRoute, Fiddler, mitmproxy) já não está a correr, o tráfego fica pendurado ou a passar por um salto extra. Corre: netsh winhttp reset proxy"
    }
} catch { }

# 2.2 Proxy de utilizador/Internet Options (WinINET) — afeta Edge, Steam(parcialmente), updaters
try {
    $reg = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($reg) {
        Sub ("WinINET: ProxyEnable=" + $reg.ProxyEnable + "  ProxyServer='" + $reg.ProxyServer + "'  AutoConfigURL='" + $reg.AutoConfigURL + "'")
        if ($reg.ProxyEnable -eq 1 -and $reg.ProxyServer -match '127\.0\.0\.1|localhost') {
            $proxyEncontrado = $true
            Warn ("Proxy de sistema (WinINET) ligado para " + $reg.ProxyServer + ". Desliga em Definições > Rede e Internet > Proxy, ou no painel do OmniRoute em Traffic Inspector > 'Restore system proxy'.")
        }
        if ($reg.AutoConfigURL) { Warn ("PAC/AutoConfigURL definido (" + $reg.AutoConfigURL + ") — cada pedido passa por uma resolução de script; atrasa muito downloads.") }
    }
    $regPc = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($regPc -and ($regPc.ProxyEnable -eq 1)) { Warn ("Proxy ao nível da máquina (HKLM) ativo: " + $regPc.ProxyServer) }
} catch { }

# 2.3 Variáveis de ambiente (afetam curl, npm, git, python, muitos updaters)
foreach ($v in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY','http_proxy','https_proxy','all_proxy')) {
    $val = [System.Environment]::GetEnvironmentVariable($v, 'User')
    if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($v, 'Machine') }
    if ($val) {
        Sub ($v + " = " + $val)
        if ($val -match '127\.0\.0\.1|localhost') { $proxyEncontrado = $true; Warn ($v + " aponta para localhost — se o proxy morreu, tudo o que use esta variável falha ou arrasta.") }
    }
}

# 2.4 Portas locais ouvindo em proxy (8080/8888/3128/9090/7890) sem dono claro
try {
    $escuta = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in 8080, 8888, 9090, 3128, 8118, 7890, 1080 } |
        Select-Object -Unique LocalAddress, LocalPort, OwningProcess
    foreach ($e in $escuta) {
        $proc = (Get-Process -Id $e.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        Sub ("Porta proxy à escuta: " + $e.LocalAddress + ":" + $e.LocalPort + "  ->  " + $proc)
    }
} catch { }

if (-not $proxyEncontrado) { Ok "Nenhum proxy preso detetado (WinHTTP, WinINET e variáveis de ambiente limpas)." }

# ────────────────────────────────────────────────────────────────────────────
# 3. DNS
# ────────────────────────────────────────────────────────────────────────────
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
            if ($ms -gt 300) { Warn ("Resolução DNS lenta para " + $host_ + " (" + $ms + " ms). Muda para DNS de operador com cache próxima ou 1.1.1.1/9.9.9.9/8.8.8.8.") }
        } catch {
            $sw.Stop()
            Warn ("Não consegui resolver " + $host_ + ": " + $_.Exception.Message)
        }
    }
} catch { Warn ("Falha na análise de DNS: " + $_.Exception.Message) }

# ────────────────────────────────────────────────────────────────────────────
# 4. Latência, perda, jitter  +  BUFFERBLOAT
# ────────────────────────────────────────────────────────────────────────────
Titulo "4. Latência, perda de pacotes e bufferbloat"

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
        Warn ("Sem resposta de " + $f.Nome + " (ICMP bloqueado pela rede/ISP ou alvo inacessível) — sem medição de latência/perda aqui.")
        continue
    }
    Sub ($f.Nome.PadRight(30) + " min " + $s.Min + " ms | média " + $s.Media + " ms | max " + $s.Max + " ms | jitter " + $s.Jitter + " ms | perda " + $s.Perda + "%")
    if ($f.Alvo -eq '1.1.1.1') {
        $bufBase = $s; $bufAlvo = $f.Alvo
    } elseif (-not $bufBase -and $f.Alvo -eq '8.8.8.8') {
        # 1.1.1.1 não responde a ICMP em muitas redes; usa o Google como referência.
        $bufBase = $s; $bufAlvo = $f.Alvo
    }
    if ($s.Perda -gt 1) { Warn ("Perda de pacotes de " + $s.Perda + "% em " + $f.Nome + " — ligação instável (cabo/Wi-Fi/router/ISP).") }
    if ($s.Jitter -gt 30) { Warn ("Jitter alto (" + $s.Jitter + " ms) em " + $f.Nome + " — mau para jogos e para o próprio TCP (descarregamentos aos soluços).") }
}

# Bufferbloat: mede a latência ENQUANTO a linha está saturada.
# É este teste que explica "a net é boa quando ninguém está a usar nada".
$curlExe = $null
$c = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($c) { $curlExe = $c.Source }

if ($curlExe -and $bufBase -and -not $SemDisco) {
    Sub ("A saturar a linha durante ~10 s para medir o bufferbloat (referência: " + $bufAlvo + ")...")
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
            Sub ("Em carga: média " + $bufCarregado.Media + " ms  (repouso " + $bufBase.Media + " ms  →  +" + $delta + " ms)")
            if ($bufCarregado.Perda -gt 3) { Warn ("Com a linha ocupada perdes " + $bufCarregado.Perda + "% dos pacotes — o router está a encher a fila e a descartar. Ativa SQM/QoS (fq_codel) no router.") }
            if ($delta -gt 200) {
                Warn ("BUFFERBLOAT grave: +" + $delta + " ms quando a linha enche. Um download a 10 Mbit/s pode deixar a casa toda sem net utilizável. Solução: SQM/QoS/QoS adaptativo no router, ou limitar a velocidade de download a ~90% da linha.")
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
    Info "curl.exe não encontrado — salto o teste de bufferbloat (o Windows 10 1803+ traz curl.exe em C:\Windows\System32)."
}

# ────────────────────────────────────────────────────────────────────────────
# 5. MTU / fragmentação
# ────────────────────────────────────────────────────────────────────────────
Titulo "5. MTU (fragmentação de pacotes)"
$mtuOk = $false
foreach ($tam in @(1472, 1464, 1452, 1400, 1300, 1272, 548)) {
    $null = ping -n 1 -f -l $tam -w 1500 1.1.1.1 2>$null
    if ($LASTEXITCODE -eq 0) {
        $mtu = $tam + 28
        Sub ("Payload de " + $tam + " bytes sem fragmentar passou -> MTU da linha = " + $mtu)
        if ($mtu -lt 1500) { Warn ("MTU reduzido (" + $mtu + " em vez de 1500, típico de PPPoE/VPN/túneis). Handshakes TLS e uploads sofrem; confirma no router.") }
        else { Ok "MTU em 1500 (ideal)." }
        $mtuOk = $true
        break
    }
}
if (-not $mtuOk) { Warn "Não passou nenhum payload, mesmo pequeno — a resposta ICMP com DF está a ser bloqueada ou a linha tem problemas." }

# ────────────────────────────────────────────────────────────────────────────
# 6. Velocidade real de download
# ────────────────────────────────────────────────────────────────────────────
Titulo "6. Velocidade real de download (4 fontes independentes)"
Info "O plano é 1000 Mbps / 100 Mbps de upload. O teto prático é ~90-95% disso com tudo limpo."

$resultados = @()
if ($curlExe) {
    $testes = @(
        @{ Nome = 'Cloudflare (100 MB)'; Url = 'https://speed.cloudflare.com/__down?bytes=100000000' },
        @{ Nome = 'Hetzner Alemanha (100 MB)'; Url = 'https://speed.hetzner.de/100MB.bin' },
        @{ Nome = 'Steam CDN (Akamai)'; Url = 'https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe' },
        @{ Nome = 'Steam CDN (Cloudflare)'; Url = 'https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe' }
    )
    foreach ($t in $testes) {
        $segundos = 10
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $out = & $curlExe -s -L -o NUL --connect-timeout 8 --max-time $segundos -w '%{size_download}' $t.Url 2>$null
        $sw.Stop()
        $bytes = 0
        [void][int64]::TryParse((($out | Out-String).Trim()), [ref]$bytes)
        $segs = $sw.Elapsed.TotalSeconds
        if ($bytes -le 0) {
            Erro ($t.Nome + ": não recebi dados (bloqueado, offline ou URL indisponível).")
            continue
        }
        $mbps = if ($segs -gt 0) { ($bytes * 8.0) / 1000000.0 / $segs } else { 0 }
        $resultados += [pscustomobject]@{ Nome = $t.Nome; Mbps = $mbps; MB = [math]::Round($bytes / 1MB, 1) }
        $cor = 'Green'; if ($mbps -lt 100) { $cor = 'Yellow' }; if ($mbps -lt 25) { $cor = 'Red' }
        Write-Host ("  · " + $t.Nome.PadRight(30) + " " + ([math]::Round($mbps,1)).ToString().PadLeft(7) + " Mbps  (" + [math]::Round($bytes/1MB,1) + " MB em " + [math]::Round($segs,1) + " s)") -ForegroundColor $cor
    }
} else {
    # Fallback .NET (respeita o proxy do sistema, por isso também serve de deteção)
    foreach ($u in @('https://speed.cloudflare.com/__down?bytes=100000000')) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($u)
            $req.Timeout = 15000; $req.ReadWriteTimeout = 15000
            $resp = $req.GetResponse()
            $stream = $resp.GetResponseStream()
            $buf = New-Object byte[] 65536
            $total = 0; $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 10) {
                $n = $stream.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                $total += $n
            }
            $stream.Close(); $resp.Close(); $sw.Stop()
            $mbps = ($total * 8.0) / 1000000.0 / $sw.Elapsed.TotalSeconds
            $resultados += [pscustomobject]@{ Nome = 'Cloudflare (.NET)'; Mbps = $mbps; MB = [math]::Round($total/1MB,1) }
            Sub ("Cloudflare (.NET): " + [math]::Round($mbps,1) + " Mbps")
        } catch { Erro ("Teste .NET falhou: " + $_.Exception.Message) }
    }
}

if ($resultados.Count -gt 0) {
    $melhor = ($resultados | Sort-Object Mbps -Descending | Select-Object -First 1)
    Sub ("Melhor resultado: " + $melhor.Nome + " = " + [math]::Round($melhor.Mbps,1) + " Mbps (" + [math]::Round($melhor.Mbps/8,1) + " MB/s)")
    [void]$script:Veredito.Add([pscustomobject]@{ Chave = 'download'; Valor = $melhor.Mbps })
    if ($melhor.Mbps -lt 50) {
        Erro "Nenhuma fonte passou dos 50 Mbps. A ligação real está longe do plano — o problema NÃO é do Steam."
    } elseif ($melhor.Mbps -lt 300) {
        Warn ("Máximo de " + [math]::Round($melhor.Mbps,1) + " Mbps. Numa linha de 1 Gbps isto aponta para Wi-Fi, porta/cabo a 100M, ou router sobrecarregado.")
    } else {
        Ok ("Ligação a " + [math]::Round($melhor.Mbps,1) + " Mbps — linha saudável. Se o Steam continua lento, o gargalo é do lado do Steam ou do disco.")
    }
    # Diferença entre CDNs diz muito: uma fonte má = peering; todas más = linha/PC.
    if ($resultados.Count -ge 2) {
        $pior = ($resultados | Sort-Object Mbps | Select-Object -First 1)
        if ($melhor.Mbps -gt 200 -and $pior.Mbps -lt ($melhor.Mbps / 4)) {
            Warn ("Diferença enorme entre CDNs (" + $pior.Nome + " a " + [math]::Round($pior.Mbps,1) + " Mbps vs " + $melhor.Nome + " a " + [math]::Round($melhor.Mbps,1) + " Mbps). Isto é típico de peering/rota do ISP para essa rede. Testa mudar o DNS para 1.1.1.1 e volta a medir.")
        }
    }
}
Info "Nota: o Steam instala com centenas de ficheiros pequenos — a velocidade 'útil' é sempre bem menor que o teste de 100 MB, e o disco/CPU contam."

# ────────────────────────────────────────────────────────────────────────────
# 7. Interceção TLS: ficheiros hosts e certificados
# ────────────────────────────────────────────────────────────────────────────
Titulo "7. Interceção TLS (hosts + certificados raiz)"
$hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
try {
    $linhas = Get-Content -LiteralPath $hostsPath -ErrorAction Stop |
        Where-Object { $_.Trim() -ne '' -and $_.Trim() -notmatch '^#' }
    if ($linhas) {
        Sub ("Entradas ativas em " + $hostsPath + ":")
        foreach ($l in $linhas) { Sub ("    " + $l.Trim()) }
        $perigosas = $linhas | Where-Object { $_ -match 'anthropic|openai|chatgpt|claude|gemini|googleapis|cloudcode|copilot|antigravity|zed|cursor|omniroute|steam|akamai|cloudflare' }
        if ($perigosas) {
            Warn ("Há hosts de serviços/agentes/CDN redirecionados no ficheiro hosts (interceção ativa ou restos dela). Se o OmniRoute/AgentBridge já não está a correr, isto parte esses serviços. Limpa estas linhas ou usa o botão 'Repair' do OmniRoute.")
        }
    } else {
        Ok "Ficheiro hosts limpo (sem entradas ativas)."
    }
} catch { Warn ("Não consegui ler o ficheiro hosts: " + $_.Exception.Message) }

try {
    $certs = Get-ChildItem -Path Cert:\CurrentUser\Root, Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -match 'OmniRoute|mitmproxy|mitm|Fiddler|Charles|intercept' -or $_.Issuer -match 'OmniRoute|mitmproxy|Fiddler|Charles' } |
        Select-Object Subject, Thumbprint, NotAfter, NotBefore
    if ($certs) {
        foreach ($cert in $certs) {
            Warn ("Certificado raiz de interceção instalado: " + $cert.Subject + "  (válido até " + $cert.NotAfter.ToString('yyyy-MM-dd') + ", thumbprint " + $cert.Thumbprint.Substring(0,16) + "…)")
        }
        Sub "Remover (PowerShell como admin): Get-ChildItem Cert:\CurrentUser\Root | Where-Object { `$_.Subject -match 'OmniRoute' } | Remove-Item"
    } else {
        Ok "Nenhum certificado raiz de interceção (OmniRoute/mitmproxy/Fiddler) instalado."
    }
} catch { }

# ────────────────────────────────────────────────────────────────────────────
# 8. Steam
# ────────────────────────────────────────────────────────────────────────────
Titulo "8. Configuração do Steam"
try {
    $steamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if (-not $steamPath) { $steamPath = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -Name InstallPath -ErrorAction SilentlyContinue).InstallPath }
    if ($steamPath) {
        $steamPath = $steamPath -replace '/', '\'
        Sub ("Instalação: " + $steamPath)
        # Limites de download
        $cfg = Join-Path $steamPath 'config\config.vdf'
        if (Test-Path $cfg) {
            $interessantes = Select-String -Path $cfg -Pattern '"?Rate"?\s+"?(\d+)"?|"?Throttle"?\s+"?(\d+)"?|DownloadThrottle|LimitDownload' -ErrorAction SilentlyContinue
            if ($interessantes) {
                Sub "Limites encontrados em config.vdf:"
                foreach ($i in $interessantes) { Sub ("    " + $i.Line.Trim()) }
                Warn "O Steam guarda aqui o limite de largura de banda. Se estiver em 10-15 Mbps (~1,3 MB/s) é exatamente o que estás a ver. Desliga em: Steam > Definições > Downloads > 'Limitar largura de banda de descarga' / Throttle."
            } else {
                Ok "Sem limite de largura de banda configurado no Steam (config.vdf)."
            }
        }
        # Região de download
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
            Sub "Pastas de biblioteca (onde o BF6 está/fica):"
            foreach ($l in ($libs | Select-Object -Unique)) { Sub ("    " + $l) }
            $script:SteamLibs = ($libs | Select-Object -Unique)
        }
        # Processos do Steam a consumir rede agora
        $uso = Get-Process -Name 'steam','steamwebhelper','steamservice' -ErrorAction SilentlyContinue
        if ($uso) { Sub ("Steam em execução (" + ($uso | Measure-Object).Count + " processos).") }
    } else {
        Info "Steam não encontrado no registo (ou não instalado). Salto esta secção."
    }
    $bf = Get-Process -Name 'bf6','battlefield6','Battlefield*' -ErrorAction SilentlyContinue
    if ($bf) { Info ("Processo do Battlefield em execução: " + (($bf | Select-Object -ExpandProperty ProcessName) -join ", ")) }
} catch { Warn ("Análise do Steam falhou: " + $_.Exception.Message) }

# ────────────────────────────────────────────────────────────────────────────
# 9. Disco — o suspeito invisível dos downloads grandes
# ────────────────────────────────────────────────────────────────────────────
Titulo "9. Escrita em disco (onde os jogos instalam)"
if ($SemDisco) {
    Info "Teste de disco saltado (-SemDisco)."
} else {
    Info ("A criar ficheiros temporários de " + $MBDisco + " MB e a apagá-los logo a seguir...")

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
            Warn ("Disco " + $pasta + " não existe/inacessível — se o Steam aponta para lá, é mais um problema em cima.")
            continue
        }
        try {
            $vol = Get-Volume -DriveLetter $letra[0] -ErrorAction SilentlyContinue
            if ($vol) { Sub ("Disco " + $pasta + " (" + $vol.FileSystemType + ") livre: " + [math]::Round($vol.SizeRemaining/1GB,1) + " GB de " + [math]::Round($vol.Size/1GB,1) + " GB") }
            $r = Test-EscritaDisco $pasta $MBDisco
            if (-not $r.OK) {
                Erro ("Não consegui escrever em " + $pasta + ": " + $r.Erro + " (disco cheio, protegido ou avariado?)")
                continue
            }
            $mbpsDisco = $r.MBs
            $cor = 'Green'; if ($mbpsDisco -lt 120) { $cor = 'Yellow' }; if ($mbpsDisco -lt 60) { $cor = 'Red' }
            Write-Host ("  · Escrita em " + $pasta.PadRight(6) + " " + [math]::Round($mbpsDisco,0).ToString().PadLeft(6) + " MB/s  (" + [math]::Round($mbpsDisco*8/1000,2) + " Gbps)") -ForegroundColor $cor
            if ($mbpsDisco -lt 60) {
                Warn ("Disco " + $pasta + " escreve a " + [math]::Round($mbpsDisco,0) + " MB/s. Isto limita QUALQUER download a ~" + [math]::Round($mbpsDisco*8/1000,1) + " Gbps (>1 Gbps é o esperado num NVMe). HDD ou disco quase cheio?")
            }
        } catch { Warn ("Teste de disco em " + $pasta + " falhou: " + $_.Exception.Message) }
    }

    # SMART: erros de leitura/escrita que arrastam downloads
    try {
        $smart = Get-WmiObject -Namespace 'root\wmi' -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        foreach ($s in $smart) {
            if ($s.PredictFailure) { Warn ("SMART do disco " + $s.InstanceName + " prevê falha — backup já, e verifica com CrystalDiskInfo.") }
        }
    } catch { }
}

# ────────────────────────────────────────────────────────────────────────────
# RESUMO
# ────────────────────────────────────────────────────────────────────────────
Titulo "RESUMO"
if ($script:Falhas.Count -eq 0 -and $script:Alertas.Count -eq 0) {
    Ok "Nenhum problema detetado nesta passagem. Guarda o relatório e repete o teste a meio de um download lento."
} else {
    if ($script:Falhas.Count -gt 0) {
        Write-Host "  FALHAS (" + $script:Falhas.Count + "):" -ForegroundColor Red
        foreach ($f in $script:Falhas) { Write-Host ("   ✗ " + $f) -ForegroundColor Red }
    }
    if ($script:Alertas.Count -gt 0) {
        Write-Host "  ATENÇÃO (" + $script:Alertas.Count + "):" -ForegroundColor Yellow
        foreach ($a in $script:Alertas) { Write-Host ("   ! " + $a) -ForegroundColor Yellow }
    }
}

Write-Host ""
$dl = ($script:Veredito | Where-Object { $_.Chave -eq 'download' } | Select-Object -First 1)
if (-not $dl) {
    Write-Host "  VEREDITO: não consegui medir a velocidade de download (sem curl, sem rede ou tudo bloqueado)." -ForegroundColor Yellow
    Write-Host "            Confirma primeiro que esta máquina navega; depois volta a correr o diagnóstico." -ForegroundColor Yellow
}
if ($dl) {
    if ($dl.Valor -lt 50) {
        Write-Host "  VEREDITO: a linha/PC está a entregar menos de 50 Mbps. O problema é de rede/PC, não do Steam nem do BF6." -ForegroundColor Red
        Write-Host "            Ordem de ataque: cabo em vez de Wi-Fi -> reiniciar router -> testar com outro PC -> chamar o ISP." -ForegroundColor Red
    } elseif ($dl.Valor -lt 300) {
        Write-Host "  VEREDITO: entre 50 e 300 Mbps. Ligação utilizável mas abaixo do plano de 1 Gbps — foca-te em Wi-Fi/cabo/router/QoS." -ForegroundColor Yellow
    } else {
        Write-Host "  VEREDITO: a linha entrega bem (>300 Mbps). Se o Steam continua a 10 Mbit/s, o gargalo é do Steam ou do disco." -ForegroundColor Green
        Write-Host "            Verifica: limite de downloads do Steam, região de download, disco saturado/HDD, e ficheiros pequenos (instalação)." -ForegroundColor Green
    }
}
Write-Host ""
Write-Host ("  Relatório guardado em: " + $logFicheiro) -ForegroundColor DarkGray
Write-Host "  Segue as ações do ficheiro LEIA-ME do kit (docs/help/pt-PT/README.md)." -ForegroundColor DarkGray
Write-Host ""

try { Stop-Transcript | Out-Null } catch { }
