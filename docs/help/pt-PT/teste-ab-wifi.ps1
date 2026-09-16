<#
    teste-ab-wifi.ps1 - compara a velocidade COM Wi-Fi e SEM Wi-Fi (por cabo),
                         na mesma sessão, sem tu teres de mexer em nada.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\teste-ab-wifi.ps1
        powershell -ExecutionPolicy Bypass -File .\teste-ab-wifi.ps1 -MB 150

    Requisitos: precisa de TER O CABO LIGADO (ou o script recusa e não desliga nada).
    No fim, volta a ligar a Wi-Fi automaticamente (mesmo se algo falhar a meio).

    O que faz:
      1. mostra as interfaces e a rota preferida;
      2. mede a velocidade (3 CDNs) com a Wi-Fi ligada;
      3. desliga a Wi-Fi, espera que a rota passe para o cabo e mede outra vez;
      4. volta a ligar a Wi-Fi e apresenta os dois resultados lado a lado.

    Precisa de administrador (para desligar/ligar o adaptador). O script eleva-se sozinho.
#>

[CmdletBinding()]
param([int]$MB = 100)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Linha { Write-Host ("  " + ("-" * 72)) -ForegroundColor DarkGray }
function Titulo($t) { Write-Host ""; Write-Host ("  " + $t) -ForegroundColor Cyan; Linha }
function Ok($t) { Write-Host ("  [OK]      " + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ("  [ATENÇÃO] " + $t) -ForegroundColor Yellow }
function Info($t) { Write-Host ("  [i]       " + $t) -ForegroundColor DarkCyan }
function Erro($t) { Write-Host ("  [FALHA]   " + $t) -ForegroundColor Red }

if (-not $ehAdmin) {
    Write-Host ""
    Info "Preciso de Administrador para desligar/ligar a Wi-Fi. Vou abrir uma janela elevada..."
    $eu = $PSCommandPath
    if (-not $eu) { $eu = $MyInvocation.MyCommand.Path }
    if ($eu) {
        Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File', ('"' + $eu + '"'), '-MB', "$MB") | Out-Null
    } else {
        Erro "Nao consegui determinar o caminho do proprio script. Abre o PowerShell como administrador e volta a correr."
    }
    return
}

Write-Host ""
Write-Host "  TESTE A/B: WI-FI vs CABO" -ForegroundColor White
Write-Host ("  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray

# -- Estado das interfaces ---------------------------------------------------
function Mostrar-Interfaces {
    $ifs = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ConnectionState -eq 'Connected' } | Sort-Object InterfaceMetric)
    if ($ifs.Count -eq 0) { Warn "Nenhuma interface IPv4 ligada."; return $null }
    foreach ($i in $ifs) {
        $ad = Get-NetAdapter -InterfaceIndex $i.ifIndex -ErrorAction SilentlyContinue
        $marca = if ($ifs[0].ifIndex -eq $i.ifIndex) { "   <-- rota preferida" } else { "" }
        Write-Host ("  - " + $i.InterfaceAlias.PadRight(14) + " metric=" + ([string]$i.InterfaceMetric).PadRight(6) + " link=" + ([string]$ad.LinkSpeed).PadRight(10) + " [" + $ad.InterfaceDescription + "]" + $marca) -ForegroundColor $(if ($marca) { 'Yellow' } else { 'Gray' })
    }
    return $ifs[0]
}

# -- Motor de medição com VALIDAÇÃO -----------------------------------------
#  Uma medição só conta se: HTTP 200 E pelo menos 20 MB transferidos.
#  Ficheiros pequenos (o SteamSetup.exe tem ~2,3 MB) davam números falsos.
$MIN_BYTES_VALIDO = 20MB
$MAX_SEGUNDOS = 15
$Fontes = @(
    @{ Nome = 'Cloudflare'; Url = 'https://speed.cloudflare.com/__down?bytes=' + ($MB * 1000000) },
    @{ Nome = 'OVH (Franca)'; Url = 'https://proof.ovh.net/files/100Mb.dat' },
    @{ Nome = 'Tele2 (HTTP)'; Url = 'http://speedtest.tele2.net/100MB.zip' },
    @{ Nome = 'Cachefly (HTTP)'; Url = 'http://cachefly.cachefly.net/100mb.test' },
    @{ Nome = 'Leaseweb (NL)'; Url = 'https://mirror.leaseweb.com/speedtest/100mb.bin' }
)

function Invoke-FonteSpeed([string]$nome, [string]$url, [string]$curl, [int]$maxSeg = $MAX_SEGUNDOS) {
    if (-not $curl) {
        $bytes = 0; $seg = 0.0; $http = 0
        try {
            $req = [System.Net.HttpWebRequest]::Create($url); $req.Timeout = 15000; $req.ReadWriteTimeout = 15000
            $resp = $req.GetResponse(); $http = [int]$resp.StatusCode
            $stream = $resp.GetResponseStream()
            $buf = New-Object byte[] 65536
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 12) {
                $n = $stream.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $bytes += $n
            }
            $sw.Stop(); $seg = $sw.Elapsed.TotalSeconds
            $stream.Close(); $resp.Close()
        } catch { $bytes = 0 }
        if ($http -eq 200 -and $bytes -ge $MIN_BYTES_VALIDO) {
            return [pscustomobject]@{ Nome = $nome; Valido = $true; Motivo = ''; Mbps = (($bytes * 8.0) / 1000000.0 / [math]::Max($seg, 0.001)); MB = [math]::Round($bytes / 1MB, 1); Seg = $seg }
        }
        $motivo = if ($http -ne 200) { "HTTP $http" } else { "so " + [math]::Round($bytes / 1MB, 1) + " MB" }
        return [pscustomobject]@{ Nome = $nome; Valido = $false; Motivo = $motivo; Mbps = 0; MB = [math]::Round($bytes / 1MB, 1); Seg = $seg }
    }

    $raw = & $curl -s -L -o NUL --connect-timeout 8 --max-time $maxSeg -w '%{http_code}|%{size_download}|%{speed_download}|%{time_total}' $url 2>$null
    $partes = (($raw | Out-String).Trim()) -split '\|'
    if ($partes.Count -lt 4) {
        return [pscustomobject]@{ Nome = $nome; Valido = $false; Motivo = 'sem resposta do curl'; Mbps = 0; MB = 0; Seg = 0 }
    }
    $http = 0; $bytes = 0L; $bps = 0.0; $seg = 0.0
    [void][int]::TryParse($partes[0].Trim(), [ref]$http)
    [void][int64]::TryParse($partes[1].Trim(), [ref]$bytes)
    [void][double]::TryParse($partes[2].Trim(), [ref]$bps)
    [void][double]::TryParse($partes[3].Trim(), [ref]$seg)
    $mb = [math]::Round($bytes / 1MB, 1)
    if ($http -ne 200) { return [pscustomobject]@{ Nome = $nome; Valido = $false; Motivo = ('HTTP ' + $http); Mbps = 0; MB = $mb; Seg = $seg } }
    if ($bytes -lt $MIN_BYTES_VALIDO) { return [pscustomobject]@{ Nome = $nome; Valido = $false; Motivo = ('so ' + $mb + ' MB (curto para medir)'); Mbps = 0; MB = $mb; Seg = $seg } }
    return [pscustomobject]@{ Nome = $nome; Valido = $true; Motivo = ''; Mbps = ($bps * 8.0 / 1000000.0); MB = $mb; Seg = $seg }
}

function Invoke-TodasAsFontes([string]$curl) {
    $lista = @()
    foreach ($f in $Fontes) { $lista += (Invoke-FonteSpeed $f.Nome $f.Url $curl) }
    return $lista
}

function Medir-Velocidade($rotulo) {
    Write-Host ""
    Write-Host ("  " + $rotulo) -ForegroundColor White
    $curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
    $lista = Invoke-TodasAsFontes $curl
    $melhor = Mostrar-Resultados $lista
    if ($melhor) { return [pscustomobject]@{ Mbps = $melhor.Mbps; Nome = $melhor.Nome } }
    return [pscustomobject]@{ Mbps = 0; Nome = 'inconclusivo' }
}

function Mostrar-Resultados($lista) {
    foreach ($r in $lista) {
        if ($r.Valido) {
            $cor = 'Green'; if ($r.Mbps -lt 300) { $cor = 'Yellow' }; if ($r.Mbps -lt 100) { $cor = 'Red' }
            Write-Host ("    - " + $r.Nome.PadRight(16) + " " + ([math]::Round($r.Mbps,1)).ToString().PadLeft(7) + " Mbps   (" + $r.MB + " MB em " + [math]::Round($r.Seg,1) + " s)") -ForegroundColor $cor
        } else {
            Write-Host ("    - " + $r.Nome.PadRight(16) + " INVALIDO: " + $r.Motivo) -ForegroundColor DarkYellow
        }
    }
    $validos = @($lista | Where-Object { $_.Valido })
    if ($validos.Count -eq 0) {
        Warn "Nenhuma fonte deu medicao valida (>=20 MB). Isto NAO quer dizer 'linha lenta': os testes falharam."
        Write-Host "        Confirma a mao e ve o erro: curl.exe -v -o NUL --max-time 15 `"https://speed.cloudflare.com/__down?bytes=20000000`"" -ForegroundColor Gray
        return $null
    }
    return ($validos | Sort-Object Mbps -Descending | Select-Object -First 1)
}

# -- Que adaptadores temos? -------------------------------------------------
Titulo "1. Interfaces (antes do teste)"
$preferida = Mostrar-Interfaces

$adapta = @(Get-NetAdapter -ErrorAction SilentlyContinue)
$wifi = @($adapta | Where-Object { $_.Status -eq 'Up' -and ($_.PhysicalMediaType -match '802\.11' -or $_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN') })
$caboUp = @($adapta | Where-Object { $_.Status -eq 'Up' -and $_.PhysicalMediaType -match '802\.3' -and $_.InterfaceDescription -notmatch 'Wi-Fi|Wireless|WLAN' })

if ($wifi.Count -eq 0) {
    Warn "Não vejo nenhum adaptador Wi-Fi ligado. Só posso medir o cabo."
}
if ($caboUp.Count -eq 0) {
    Erro "NÃO tens cabo ligado (nenhuma interface Ethernet ativa)."
    Write-Host "        Este teste desliga a Wi-Fi - sem cabo ficarias sem rede. Nada foi alterado." -ForegroundColor Yellow
    Write-Host "        Liga o cabo ao PC e ao router, confirma que fica 'Up', e volta a correr este script." -ForegroundColor Yellow
    Write-Host "        Se o cabo estiver ligado e continuar 'Down', o problema pode ser o próprio cabo/porta." -ForegroundColor Yellow
    return
}
Info ("Cabo ativo: " + ($caboUp.Name -join ', ') + "   |   Wi-Fi ativa: " + ($wifi.Name -join ', '))

# -- 2) Com Wi-Fi -----------------------------------------------------------
Titulo "2. Medição COM Wi-Fi ligada"
$comWifi = Medir-Velocidade "Resultados (Wi-Fi ligada):"

# -- 3) Sem Wi-Fi (cabo) ----------------------------------------------------
Titulo "3. Medição SEM Wi-Fi (só cabo)"
$resultadoCabo = $null
$wifiDesligada = $false
try {
    foreach ($w in $wifi) {
        try {
            Disable-NetAdapter -Name $w.Name -Confirm:$false -ErrorAction Stop
            Ok ("Wi-Fi desligada: " + $w.Name)
            $wifiDesligada = $true
        } catch {
            Warn ("Não consegui desligar " + $w.Name + ": " + $_.Exception.Message)
        }
    }
    if ($wifiDesligada) {
        Info "A aguardar que a rota passe para o cabo..."
        Start-Sleep -Seconds 5
        $null = Mostrar-Interfaces
        $resultadoCabo = Medir-Velocidade "Resultados (só cabo):"
    }
} finally {
    # Rede de segurança: voltar a ligar a Wi-Fi SEMPRE, mesmo com erro a meio
    if ($wifiDesligada) {
        Titulo "4. A voltar a ligar a Wi-Fi"
        foreach ($w in $wifi) {
            try { Enable-NetAdapter -Name $w.Name -Confirm:$false -ErrorAction Stop } catch { Warn ("Não consegui religar " + $w.Name) }
        }
        $esperou = 0
        while ($esperou -lt 30) {
            Start-Sleep -Seconds 2; $esperou += 2
            $estado = @(Get-NetAdapter -Name ($wifi | Select-Object -ExpandProperty Name) -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })
            if ($estado.Count -eq $wifi.Count) { break }
        }
        foreach ($w in $wifi) {
            $ad = Get-NetAdapter -Name $w.Name -ErrorAction SilentlyContinue
            if ($ad -and $ad.Status -eq 'Up') { Ok ($w.Name + " ligada outra vez.") } else { Warn ($w.Name + " ainda não voltou - liga-a em Definições > Rede (ou na tecla do teclado).") }
        }
    }
}

# -- Resumo -----------------------------------------------------------------
Titulo "RESUMO DO TESTE A/B"
if ($comWifi) { Write-Host ("  Com Wi-Fi :  " + ([math]::Round($comWifi.Mbps,1)).ToString().PadLeft(7) + " Mbps   (" + $comWifi.Nome + ")") -ForegroundColor Gray }
if ($resultadoCabo) { Write-Host ("  Só cabo   :  " + ([math]::Round($resultadoCabo.Mbps,1)).ToString().PadLeft(7) + " Mbps   (" + $resultadoCabo.Nome + ")") -ForegroundColor Gray }

if ($comWifi -and $resultadoCabo -and $comWifi.Mbps -gt 0 -and $resultadoCabo.Mbps -gt 0) {
    $delta = $resultadoCabo.Mbps - $comWifi.Mbps
    $razao = [math]::Round($comWifi.Mbps / $resultadoCabo.Mbps, 2)
    Write-Host ""
    Write-Host ("  Diferença: " + $(if ($delta -ge 0) { "+" } else { "" }) + [math]::Round($delta,1) + " Mbps no cabo (Wi-Fi = " + [math]::Round($razao*100,0) + "% do cabo)") -ForegroundColor White
    if ($resultadoCabo.Mbps -lt 300) {
        Erro "O CABO também está lento (<300 Mbps numa linha de 1 Gbps). Não é problema de Wi-Fi: verifica cabo/porta do router, Green Ethernet/Gigabit Lite na NIC Ethernet, e o router (QoS)."
    } elseif ($razao -lt 0.5) {
        Warn "A Wi-Fi entrega menos de metade do cabo - o Wi-Fi (AX200) está a limitar. Vê a secção 4e do guia: driver 24.20.2.1, canal/160MHz, antenas, autotuning TCP."
    } elseif ($razao -gt 0.8) {
        Ok "A Wi-Fi está próxima do cabo - o Wi-Fi não é o problema. Se o Steam continua lento, é limite do Steam/QoS/disco (secções 3, 4b e 7)."
    } else {
        Info "A Wi-Fi entrega entre 50% e 80% do cabo - dentro do normal. Não é aqui que está o teu gargalo."
    }
    Write-Host ""
    Info "Guarda este resultado: repete depois de atualizar o driver do AX200 para 24.20.2.1 e compara."
} else {
    Warn "Não consegui medir os dois cenários (falta cabo, rede bloqueada, ou o adaptador não voltou)."
    Info "O que interessa: o valor do CABO. Se ele estiver em ~940 Mbps, a linha e o PC estão bem e o problema é do Steam/Wi-Fi."
}
Write-Host ""
