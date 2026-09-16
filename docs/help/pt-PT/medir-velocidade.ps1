<#
    medir-velocidade.ps1 — teste de velocidade rápido (30 s) com o contexto que importa:
    por que interface está a sair o tráfego, a linha responde bem, e qual a velocidade real.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1
        powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1 -MB 250

    Serve para comparar A/B: corre com a Wi-Fi ligada, desliga a Wi-Fi, corre outra vez.
#>

[CmdletBinding()]
param([int]$MB = 100)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Linha { Write-Host ("─" * 70) -ForegroundColor DarkGray }

Write-Host ""
Write-Host "  TESTE DE VELOCIDADE — $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor White
Linha

# ── Por onde sai o tráfego ─────────────────────────────────────────────────
try {
    $ifs = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ConnectionState -eq 'Connected' } | Sort-Object InterfaceMetric
    foreach ($i in $ifs) {
        $ad = Get-NetAdapter -InterfaceIndex $i.ifIndex -ErrorAction SilentlyContinue
        $marca = ""
        if ($ifs[0].ifIndex -eq $i.ifIndex) { $marca = "   <-- rota preferida" }
        Write-Host ("  · " + $i.InterfaceAlias.PadRight(14) + " metric=" + ([string]$i.InterfaceMetric).PadRight(6) + " link=" + $ad.LinkSpeed.PadRight(10) + " [" + $ad.InterfaceDescription + "]" + $marca) -ForegroundColor $(if ($marca) { 'Yellow' } else { 'Gray' })
    }
    $pref = Get-NetAdapter -InterfaceIndex $ifs[0].ifIndex -ErrorAction SilentlyContinue
    if ($pref -and ($pref.PhysicalMediaType -match '802\.11' -or $pref.InterfaceDescription -match 'Wireless|Wi-Fi')) {
        Write-Host "  !! O trafego esta a sair pela Wi-Fi. Desliga a Wi-Fi e repete para comparar." -ForegroundColor Yellow
    }
} catch { Write-Host "  (nao consegui ler as interfaces)" -ForegroundColor DarkGray }

# ── Latência base ──────────────────────────────────────────────────────────
$base = $null
try {
    $p = Test-Connection -ComputerName '8.8.8.8' -Count 6 -ErrorAction SilentlyContinue
    if ($p) {
        $t = @($p | ForEach-Object { [int]$_.ResponseTime })
        $base = [int](($t | Measure-Object -Average).Average)
        Write-Host ("  Latencia para 8.8.8.8: " + ($t | Measure-Object -Minimum).Minimum + "/" + $base + "/" + ($t | Measure-Object -Maximum).Maximum + " ms (min/med/max)") -ForegroundColor Gray
    }
} catch { }

# ── Downloads ──────────────────────────────────────────────────────────────
$curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
$fontes = @(
    @{ Nome = 'Cloudflare'; Url = 'https://speed.cloudflare.com/__down?bytes=' + ($MB * 1000000) },
    @{ Nome = 'Steam (Cloudflare)'; Url = 'https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe' },
    @{ Nome = 'Hetzner (DE)'; Url = 'https://speed.hetzner.de/100MB.bin' }
)
$melhor = 0; $melhorNome = ""
Linha
foreach ($f in $fontes) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $bytes = 0
    if ($curl) {
        $out = & $curl -s -L -o NUL --connect-timeout 8 --max-time 15 -w '%{size_download}' $f.Url 2>$null
        [void][int64]::TryParse((($out | Out-String).Trim()), [ref]$bytes)
    } else {
        try {
            $req = [System.Net.HttpWebRequest]::Create($f.Url); $req.Timeout = 15000
            $resp = $req.GetResponse(); $stream = $resp.GetResponseStream()
            $buf = New-Object byte[] 65536
            while ($sw.Elapsed.TotalSeconds -lt 12) {
                $n = $stream.Read($buf, 0, $buf.Length); if ($n -le 0) { break }; $bytes += $n
            }
            $stream.Close(); $resp.Close()
        } catch { $bytes = 0 }
    }
    $sw.Stop()
    $seg = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
    if ($bytes -le 0) {
        Write-Host ("  · " + $f.Nome.PadRight(20) + "   sem dados (bloqueado/offline)") -ForegroundColor DarkYellow
        continue
    }
    $mbps = ($bytes * 8.0) / 1000000.0 / $seg
    if ($mbps -gt $melhor) { $melhor = $mbps; $melhorNome = $f.Nome }
    $cor = 'Green'; if ($mbps -lt 300) { $cor = 'Yellow' }; if ($mbps -lt 100) { $cor = 'Red' }
    Write-Host ("  · " + $f.Nome.PadRight(20) + " " + ([math]::Round($mbps,1)).ToString().PadLeft(7) + " Mbps  (" + [math]::Round($bytes/1MB,1) + " MB em " + [math]::Round($seg,1) + " s = " + [math]::Round($mbps/8,1) + " MB/s)") -ForegroundColor $cor
}

# ── Latência sob carga (bufferbloat rápido) ────────────────────────────────
if ($curl -and $base) {
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

Linha
if ($melhor -le 0) {
    Write-Host "  RESULTADO: nenhum teste passou. Confirma a Internet/ligação." -ForegroundColor Red
} elseif ($melhor -lt 100) {
    Write-Host ("  RESULTADO: melhor = " + [math]::Round($melhor,1) + " Mbps (" + $melhorNome + "). Muito abaixo do plano — problema de rede/PC.") -ForegroundColor Red
    Write-Host "  Compara: (a) como esta agora, (b) com a Wi-Fi desligada, (c) com outro cabo/porta do router." -ForegroundColor Red
} elseif ($melhor -lt 300) {
    Write-Host ("  RESULTADO: melhor = " + [math]::Round($melhor,1) + " Mbps (" + $melhorNome + "). Utilizavel, mas abaixo do plano.") -ForegroundColor Yellow
} else {
    Write-Host ("  RESULTADO: melhor = " + [math]::Round($melhor,1) + " Mbps (" + $melhorNome + "). Linha saudavel.") -ForegroundColor Green
}
Write-Host ""
