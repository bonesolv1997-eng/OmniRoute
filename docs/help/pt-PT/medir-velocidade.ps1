<#
    medir-velocidade.ps1 - teste de velocidade (30 s) com validação de medições.

    Correção importante (v2): só aceita uma medição se tiver transferido pelo menos
    20 MB. Ficheiros pequenos (como o SteamSetup.exe, ~2,3 MB) davam números falsos.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1
        powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1 -MB 200

    Como lê o resultado:
        VÁLIDO    = transferiu >=20 MB e HTTP 200 -> o número é a velocidade real
        INVÁLIDO  = HTTP != 200, transferência curta, ou ligação falhada
        O resumo só usa medições VÁLIDAS. Se nenhuma for válida, diz INCONCLUSIVO
        (não inventa um veredito).
#>

[CmdletBinding()]
param([int]$MB = 100)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Linha { Write-Host ("  " + ("-" * 72)) -ForegroundColor DarkGray }
function Ok($t) { Write-Host ("  [OK]      " + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ("  [ATENÇÃO] " + $t) -ForegroundColor Yellow }
function Info($t) { Write-Host ("  [i]       " + $t) -ForegroundColor DarkCyan }
function Erro($t) { Write-Host ("  [FALHA]   " + $t) -ForegroundColor Red }

$MIN_BYTES_VALIDO = 20MB
$MAX_SEGUNDOS = 15

# Fontes: todas com ficheiros de ~100 MB ou download de tamanho controlado.
# (O Hetzner foi removido - falha em muitas redes. O Steam CDN deixou de ser usado
#  para velocidade: o SteamSetup.exe tem ~2 MB e não mede nada.)
$Fontes = @(
    @{ Nome = 'Cloudflare'; Url = 'https://speed.cloudflare.com/__down?bytes=' + ($MB * 1000000) },
    @{ Nome = 'OVH (Franca)'; Url = 'https://proof.ovh.net/files/100Mb.dat' },
    @{ Nome = 'Tele2 (HTTP)'; Url = 'http://speedtest.tele2.net/100MB.zip' },
    @{ Nome = 'Cachefly (HTTP)'; Url = 'http://cachefly.cachefly.net/100mb.test' },
    @{ Nome = 'Leaseweb (NL)'; Url = 'https://mirror.leaseweb.com/speedtest/100mb.bin' }
)

$curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source

Write-Host ""
Write-Host "  TESTE DE VELOCIDADE - $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White
Linha

# -- Por onde sai o tráfego -------------------------------------------------
try {
    $ifs = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ConnectionState -eq 'Connected' } | Sort-Object InterfaceMetric)
    foreach ($i in $ifs) {
        $ad = Get-NetAdapter -InterfaceIndex $i.ifIndex -ErrorAction SilentlyContinue
        $marca = ""
        if ($ifs[0].ifIndex -eq $i.ifIndex) { $marca = "   <-- rota preferida" }
        Write-Host ("  - " + $i.InterfaceAlias.PadRight(14) + " metric=" + ([string]$i.InterfaceMetric).PadRight(6) + " link=" + ([string]$ad.LinkSpeed).PadRight(10) + " [" + $ad.InterfaceDescription + "]" + $marca) -ForegroundColor $(if ($marca) { 'Yellow' } else { 'Gray' })
    }
    if ($ifs.Count -gt 0) {
        $pref = Get-NetAdapter -InterfaceIndex $ifs[0].ifIndex -ErrorAction SilentlyContinue
        if ($pref -and ($pref.PhysicalMediaType -match '802\.11' -or $pref.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN')) {
            Warn "O trafego esta a sair pela Wi-Fi. Para um teste limpo, desliga a Wi-Fi (ou usa o teste-ab-wifi.ps1)."
        }
    }
} catch { Write-Host "  (nao consegui ler as interfaces)" -ForegroundColor DarkGray }

# -- Latência base ----------------------------------------------------------
$base = $null
try {
    $p = Test-Connection -ComputerName '8.8.8.8' -Count 6 -ErrorAction SilentlyContinue
    if ($p) {
        $t = @($p | ForEach-Object { [int]$_.ResponseTime })
        $base = [int](($t | Measure-Object -Average).Average)
        Write-Host ("  Latencia para 8.8.8.8: " + ($t | Measure-Object -Minimum).Minimum + "/" + $base + "/" + ($t | Measure-Object -Maximum).Maximum + " ms (min/med/max)") -ForegroundColor Gray
    }
} catch { }

# -- Medições ---------------------------------------------------------------
Linha
if (-not $curl) {
    Warn "curl.exe nao encontrado - a tentar com .NET (menos preciso)."
}

$resultados = @()
foreach ($f in $Fontes) {
    if (-not $curl) {
        # Fallback .NET: lê durante 12 s e mede o que passou
        $bytes = 0; $seg = 0.0; $http = 0
        try {
            $req = [System.Net.HttpWebRequest]::Create($f.Url); $req.Timeout = 15000; $req.ReadWriteTimeout = 15000
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
            $mbps = ($bytes * 8.0) / 1000000.0 / [math]::Max($seg, 0.001)
            $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $true; Motivo = ''; Mbps = $mbps; MB = [math]::Round($bytes / 1MB, 1); Seg = $seg }
        } else {
            $motivo = if ($http -ne 200) { "HTTP $http" } else { "transferiu so " + [math]::Round($bytes / 1MB, 1) + " MB" }
            $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $false; Motivo = $motivo; Mbps = 0; MB = [math]::Round($bytes / 1MB, 1); Seg = $seg }
        }
        continue
    }

    $raw = & $curl -s -L -o NUL --connect-timeout 8 --max-time $MAX_SEGUNDOS -w '%{http_code}|%{size_download}|%{speed_download}|%{time_total}' $f.Url 2>$null
    $partes = (($raw | Out-String).Trim()) -split '\|'
    $http = 0; $bytes = 0L; $bps = 0.0; $seg = 0.0
    if ($partes.Count -ge 4) {
        [void][int]::TryParse($partes[0].Trim(), [ref]$http)
        [void][int64]::TryParse($partes[1].Trim(), [ref]$bytes)
        [void][double]::TryParse($partes[2].Trim(), [ref]$bps)
        [void][double]::TryParse($partes[3].Trim(), [ref]$seg)
    }
    $mb = [math]::Round($bytes / 1MB, 1)

    if ($partes.Count -lt 4) {
        $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $false; Motivo = 'sem resposta do curl'; Mbps = 0; MB = 0; Seg = 0 }
    } elseif ($http -ne 200) {
        $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $false; Motivo = ('HTTP ' + $http); Mbps = 0; MB = $mb; Seg = $seg }
    } elseif ($bytes -lt $MIN_BYTES_VALIDO) {
        $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $false; Motivo = ('so ' + $mb + ' MB (curto para medir)'); Mbps = 0; MB = $mb; Seg = $seg }
    } else {
        $resultados += [pscustomobject]@{ Nome = $f.Nome; Valido = $true; Motivo = ''; Mbps = ($bps * 8.0 / 1000000.0); MB = $mb; Seg = $seg }
    }
}

foreach ($r in $resultados) {
    if ($r.Valido) {
        $cor = 'Green'; if ($r.Mbps -lt 300) { $cor = 'Yellow' }; if ($r.Mbps -lt 100) { $cor = 'Red' }
        Write-Host ("  - " + $r.Nome.PadRight(16) + " " + ([math]::Round($r.Mbps,1)).ToString().PadLeft(7) + " Mbps   (" + $r.MB + " MB em " + [math]::Round($r.Seg,1) + " s)") -ForegroundColor $cor
    } else {
        Write-Host ("  - " + $r.Nome.PadRight(16) + " INVALIDO: " + $r.Motivo) -ForegroundColor DarkYellow
    }
}

# -- Latência sob carga -----------------------------------------------------
$validos = @($resultados | Where-Object { $_.Valido })
$melhor = $validos | Sort-Object Mbps -Descending | Select-Object -First 1

if ($curl -and $base -and $melhor) {
    $proc = Start-Process -FilePath $curl -ArgumentList @('-s','-L','-o','NUL','--connect-timeout','8','--max-time','20','https://speed.cloudflare.com/__down?bytes=400000000') -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3
    try {
        $p2 = Test-Connection -ComputerName '8.8.8.8' -Count 8 -ErrorAction SilentlyContinue
        if ($p2) {
            $t2 = @($p2 | ForEach-Object { [int]$_.ResponseTime })
            $m2 = [int](($t2 | Measure-Object -Average).Average)
            $delta = $m2 - $base
            $cor = 'Green'; if ($delta -gt 80) { $cor = 'Yellow' }; if ($delta -gt 200) { $cor = 'Red' }
            Write-Host ("  Em carga: media " + $m2 + " ms  (+" + $delta + " ms vs repouso)") -ForegroundColor $cor
            if ($delta -gt 200) { Write-Host "  !! Bufferbloat grave: ativa SQM/QoS no router ou limita o download a ~90% da linha." -ForegroundColor Red }
            elseif ($delta -gt 80) { Write-Host "  ! Bufferbloat moderado: a casa fica lenta com downloads grandes." -ForegroundColor Yellow }
        }
    } finally {
        if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
}

# -- Resumo -----------------------------------------------------------------
Linha
if ($melhor) {
    Write-Host ("  MELHOR MEDICAO VALIDA: " + [math]::Round($melhor.Mbps,1) + " Mbps (" + $melhor.Nome + ", " + $melhor.MB + " MB)") -ForegroundColor White
    if ($melhor.Mbps -lt 100) {
        Erro ("Abaixo de 100 Mbps (" + [math]::Round($melhor.Mbps,1) + " Mbps). Muito longe do plano de 1 Gbps - verifica cabo/porta, a NIC (Realtek?), drivers e QoS do router.")
    } elseif ($melhor.Mbps -lt 300) {
        Warn ("Entre 100 e 300 Mbps (" + [math]::Round($melhor.Mbps,1) + " Mbps). Abaixo do plano - cheira a link a 100 Mbps, QoS, ou Wi-Fi.")
    } elseif ($melhor.Mbps -lt 700) {
        Info ("Entre 300 e 700 Mbps (" + [math]::Round($melhor.Mbps,1) + " Mbps). Bom, mas ainda há margem numa linha de 1 Gbps.")
    } else {
        Ok ("Linha saudavel: " + [math]::Round($melhor.Mbps,1) + " Mbps. O gargalo do Steam nao esta na rede.")
    }
} else {
    Warn "INCONCLUSIVO: nenhuma fonte deu uma medicao valida (>=20 MB transferidos)."
    Write-Host "       Isto NAO significa 'linha lenta' - significa que os testes falharam. Possiveis causas:" -ForegroundColor Yellow
    Write-Host "         - inspetor HTTPS/antivirus a bloquear os downloads (ve o passo abaixo);" -ForegroundColor Gray
    Write-Host "         - rede com filtro de URLs/CGNAT do operador;" -ForegroundColor Gray
    Write-Host "         - DNS a devolver resultados errados." -ForegroundColor Gray
    Write-Host ""
    Write-Host "       Confirma a mao (mostra o erro exato):" -ForegroundColor White
    Write-Host "         curl.exe -v -o NUL --max-time 15 `"https://speed.cloudflare.com/__down?bytes=20000000`"" -ForegroundColor Gray
    Write-Host "       Se aparecer 'SSL certificate problem' / 'schannel', há inspeção HTTPS ativa" -ForegroundColor Gray
    Write-Host "       (antivírus com inspeção TLS, ou o Traffic Inspector do OmniRoute). Ver secção 8 do guia." -ForegroundColor Gray
}
Write-Host ""
