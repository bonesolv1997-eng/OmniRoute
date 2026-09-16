# KIT-VERSION: 2026.09.16.5 (ASCII)
<#
    medir-velocidade.ps1 - teste de velocidade com validacao e teste multi-stream.

    O que faz:
      1. mostra por onde sai o trafego (rota preferida) e a latencia base;
      2. mede 6 fontes (HTTP 200 + >=20 MB) e marca as INVALIDAS com o motivo;
      3. mede tambem transferencias PARCIAIS (>= X Mbps) - informativas;
      4. faz um teste com N streams em paralelo (por omissao 4) para distinguir
         "limite por conexao" de "limite do caminho" (router/ISP/NIC);
      5. mede a latencia com a linha saturada (bufferbloat);
      6. da um veredito com o proximo passo recomendado.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1
        powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1 -MB 200
        powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1 -Paralelo 6
        powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1 -SemParalelo

    Notas desta versao (v3):
      - user-agent de browser: corrige HTTP 403 em CDNs que bloqueiam o curl;
      - numeros lidos em InvariantCulture: o curl escreve decimais com ponto e a
        leitura com cultura pt-PT falhava (aparecia "100 MB em 0 s");
      - fontes mortas removidas (Leaseweb 404) e parciais reportadas como tais.
#>

[CmdletBinding()]
param(
    [int]$MB = 100,
    [int]$Paralelo = 4,
    [switch]$SemParalelo
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

function Linha { Write-Host ("  " + ("-" * 72)) -ForegroundColor DarkGray }
function Ok($t) { Write-Host ("  [OK]      " + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ("  [ATENCAO] " + $t) -ForegroundColor Yellow }
function Info($t) { Write-Host ("  [i]       " + $t) -ForegroundColor DarkCyan }
function Erro($t) { Write-Host ("  [FALHA]   " + $t) -ForegroundColor Red }
function Det($t) { Write-Host ("            " + $t) -ForegroundColor Gray }

$MIN_BYTES_VALIDO = 20MB
$MAX_SEGUNDOS = 18
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'

$Fontes = @(
    @{ Nome = 'Cloudflare'; Url = 'https://speed.cloudflare.com/__down?bytes=' + ($MB * 1000000) },
    @{ Nome = 'Cachefly'; Url = 'http://cachefly.cachefly.net/100mb.test' },
    @{ Nome = 'OVH (Franca)'; Url = 'https://proof.ovh.net/files/100Mb.dat' },
    @{ Nome = 'Tele2 (HTTP)'; Url = 'http://speedtest.tele2.net/100MB.zip' },
    @{ Nome = 'ThinkBB (UK)'; Url = 'https://ipv4.download.thinkbroadband.com/100MB.zip' },
    @{ Nome = 'Hetzner (FS)'; Url = 'https://fsn1-speed.hetzner.com/100MB.bin' }
)

# Converte texto em numero aceitando ponto OU virgula como separador decimal
# (o curl escreve com ponto; o Windows pode estar em pt-PT).
function ConvertTo-Numero([string]$texto) {
    if (-not $texto) { return $null }
    $t = $texto.Trim()
    $n = [double]0
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $estilo = [System.Globalization.NumberStyles]::Float
    if ([double]::TryParse($t, $estilo, $inv, [ref]$n)) { return $n }
    $t2 = $t -replace ',', '.'
    if ([double]::TryParse($t2, $estilo, $inv, [ref]$n)) { return $n }
    return $null
}

function Invoke-Leitura([string]$url, [int]$maxSeg = $MAX_SEGUNDOS, [string]$destino = 'NUL') {
    # Uma transferencia. Devolve objeto com http/bytes/seg/bruto + motivo se falhar.
    $fmt = '%{http_code}|%{size_download}|%{speed_download}|%{time_total}'
    $bruto = & $script:Curl -s -L -A $UA -o $destino --connect-timeout 8 --max-time $maxSeg -w $fmt $url 2>$null
    $txt = (($bruto | Out-String)).Trim()
    $p = $txt -split '\|'
    $res = [pscustomobject]@{
        Http = 0; Bytes = [int64]0; Bps = [double]0; Seg = [double]0
        Bruto = $txt; Motivo = ''
    }
    if ($p.Count -lt 4) { $res.Motivo = 'sem resposta do curl'; return $res }
    $httpN = ConvertTo-Numero $p[0]
    $bytesN = ConvertTo-Numero $p[1]
    $bpsN = ConvertTo-Numero $p[2]
    $segN = ConvertTo-Numero $p[3]
    if ($httpN) { $res.Http = [int]$httpN }
    if ($bytesN) { $res.Bytes = [int64]$bytesN }
    if ($bpsN) { $res.Bps = [double]$bpsN }
    if ($segN) { $res.Seg = [double]$segN }
    if ($res.Seg -le 0 -and $res.Bytes -gt 0) {
        # fallback: se o tempo veio ilegivel, nao ha como calcular a velocidade
        $res.Motivo = 'tempo de transferencia ilegivel'
    }
    return $res
}

function Medir-Fonte($fonte) {
    $r = Invoke-Leitura $fonte.Url
    $mb = [math]::Round($r.Bytes / 1MB, 1)
    $parcial = ($r.Seg -ge ($MAX_SEGUNDOS - 0.7))

    if ($r.Http -ne 200) {
        return [pscustomobject]@{ Nome = $fonte.Nome; Classe = 'invalida'; Mbps = 0; MB = $mb; Seg = $r.Seg
            Motivo = ('HTTP ' + $r.Http); Bruto = $r.Bruto }
    }
    if ($r.Bytes -le 0) {
        return [pscustomobject]@{ Nome = $fonte.Nome; Classe = 'invalida'; Mbps = 0; MB = $mb; Seg = $r.Seg
            Motivo = 'zero bytes'; Bruto = $r.Bruto }
    }
    $mbps = if ($r.Bps -gt 0) { $r.Bps * 8.0 / 1000000.0 } else { ($r.Bytes * 8.0) / $r.Seg / 1000000.0 }

    if ($r.Bytes -ge $MIN_BYTES_VALIDO -and $r.Seg -gt 0) {
        return [pscustomobject]@{ Nome = $fonte.Nome; Classe = 'valida'; Mbps = $mbps; MB = $mb; Seg = $r.Seg; Motivo = ''; Bruto = $r.Bruto }
    }
    if ($parcial -and $mbps -gt 0) {
        return [pscustomobject]@{ Nome = $fonte.Nome; Classe = 'parcial'; Mbps = $mbps; MB = $mb; Seg = $r.Seg
            Motivo = ('so ' + $mb + ' MB em ' + [math]::Round($r.Seg,0) + ' s (limite de tempo)'); Bruto = $r.Bruto }
    }
    return [pscustomobject]@{ Nome = $fonte.Nome; Classe = 'invalida'; Mbps = 0; MB = $mb; Seg = $r.Seg
        Motivo = ('so ' + $mb + ' MB'); Bruto = $r.Bruto }
}

function Test-Paralelo([string]$nome, [string]$url, [int]$n, [int]$seg) {
    # N transferencias em simultaneo; soma os bytes e divide pelo tempo de parede.
    $saidas = @(); $procs = @()
    for ($i = 0; $i -lt $n; $i++) {
        $out = Join-Path $env:TEMP ('ork_' + [guid]::NewGuid().ToString('N') + '.txt')
        $saidas += $out
        $procs += Start-Process -FilePath $script:Curl -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -ArgumentList @(
            '-s','-L','-A',$UA,'-o','NUL','--connect-timeout','8','--max-time',"$seg",'-w','%{http_code}|%{size_download}',$url
        )
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($p in $procs) { try { $p.WaitForExit() } catch { } }
    $sw.Stop()
    $total = [int64]0; $ok = 0
    foreach ($o in $saidas) {
        if (Test-Path $o) {
            $linha = (Get-Content -LiteralPath $o -Raw -ErrorAction SilentlyContinue)
            Remove-Item -LiteralPath $o -Force -ErrorAction SilentlyContinue
            if ($linha) {
                $pp = ($linha.Trim() -split '\|')
                if ($pp.Count -ge 2) {
                    $httpN = ConvertTo-Numero $pp[0]; $bytesN = ConvertTo-Numero $pp[1]
                    if ($httpN -and [int]$httpN -eq 200 -and $bytesN) { $total += [int64]$bytesN; $ok++ }
                }
            }
        }
    }
    $segReal = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
    $mbps = ($total * 8.0) / $segReal / 1000000.0
    return [pscustomobject]@{ Nome = $nome; Streams = $n; Ok = $ok; MB = [math]::Round($total / 1MB, 1); Seg = $segReal; Mbps = $mbps }
}

# ---------------------------------------------------------------- inicio
$script:Curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source

Write-Host ""
Write-Host ("  TESTE DE VELOCIDADE (v3) - " + (Get-Date -Format 'HH:mm:ss')) -ForegroundColor White
if (-not $script:Curl) { Erro "curl.exe nao encontrado (Windows 10 1803+ traz em C:\Windows\System32)."; return }
Linha

# 1) interfaces
$rotaWifi = $false
try {
    $ifs = @(Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.ConnectionState -eq 'Connected' } | Sort-Object InterfaceMetric)
    foreach ($i in $ifs) {
        $ad = Get-NetAdapter -InterfaceIndex $i.ifIndex -ErrorAction SilentlyContinue
        $marca = if ($ifs.Count -gt 0 -and $ifs[0].ifIndex -eq $i.ifIndex) { "   <-- rota preferida" } else { "" }
        Write-Host ("  - " + $i.InterfaceAlias.PadRight(14) + " metric=" + ([string]$i.InterfaceMetric).PadRight(6) + " link=" + ([string]$ad.LinkSpeed).PadRight(12) + " [" + $ad.InterfaceDescription + "]" + $marca) -ForegroundColor $(if ($marca) { 'Yellow' } else { 'Gray' })
    }
    if ($ifs.Count -gt 0) {
        $pref = Get-NetAdapter -InterfaceIndex $ifs[0].ifIndex -ErrorAction SilentlyContinue
        if ($pref -and ($pref.PhysicalMediaType -match '802\.11' -or $pref.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN')) {
            $rotaWifi = $true
            Warn "O trafego esta a sair pela Wi-Fi - para testar a LINHA usa cabo (ou corre teste-ab-wifi.ps1)."
        }
    }
} catch { }

# 2) latencia base
$base = $null
try {
    $p = Test-Connection -ComputerName '8.8.8.8' -Count 6 -ErrorAction SilentlyContinue
    if ($p) {
        $t = @($p | ForEach-Object { [int]$_.ResponseTime })
        $base = [int](($t | Measure-Object -Average).Average)
        Write-Host ("  Latencia para 8.8.8.8: " + ($t | Measure-Object -Minimum).Minimum + "/" + $base + "/" + ($t | Measure-Object -Maximum).Maximum + " ms (min/med/max)") -ForegroundColor Gray
        if ($base -gt 60) { Warn ("Latencia base alta (" + $base + " ms) - Wi-Fi longe, ou rota do ISP com voltas.") }
    }
} catch { }

# 3) medicoes sequenciais
Linha
$res = @()
foreach ($f in $Fontes) {
    $r = Medir-Fonte $f
    $res += $r
    switch ($r.Classe) {
        'valida' {
            $cor = 'Green'; if ($r.Mbps -lt 300) { $cor = 'Yellow' }; if ($r.Mbps -lt 100) { $cor = 'Red' }
            Write-Host ("  - " + $r.Nome.PadRight(16) + " " + ([math]::Round($r.Mbps,1)).ToString().PadLeft(7) + " Mbps   (" + $r.MB + " MB em " + [math]::Round($r.Seg,1) + " s)") -ForegroundColor $cor
        }
        'parcial' {
            Write-Host ("  - " + $r.Nome.PadRight(16) + " >= " + ([math]::Round($r.Mbps,1)).ToString().PadLeft(6) + " Mbps   PARCIAL: " + $r.Motivo) -ForegroundColor DarkYellow
        }
        default {
            Write-Host ("  - " + $r.Nome.PadRight(16) + " INVALIDO: " + $r.Motivo) -ForegroundColor DarkYellow
        }
    }
}
$validas = @($res | Where-Object { $_.Classe -eq 'valida' })
$melhor = $validas | Sort-Object Mbps -Descending | Select-Object -First 1

# 4) multi-stream (deteta limite por conexao)
$par = $null
if (-not $SemParalelo -and $Paralelo -gt 1 -and $validas.Count -gt 0) {
    Linha
    $fonteEscolhida = ($validas | Sort-Object Mbps -Descending | Select-Object -First 1).Nome
    $url = ($Fontes | Where-Object { $_.Nome -eq $fonteEscolhida } | Select-Object -First 1).Url
    Info ("Teste multi-stream: " + $Paralelo + " transferencias em paralelo de '" + $fonteEscolhida + "' (15 s)...")
    $par = Test-Paralelo $fonteEscolhida $url $Paralelo 15
    Write-Host ("  - " + $par.Streams + " streams   " + ([math]::Round($par.Mbps,1)).ToString().PadLeft(7) + " Mbps no total   (" + $par.MB + " MB em " + [math]::Round($par.Seg,1) + " s, " + $par.Ok + "/" + $par.Streams + " ok)") -ForegroundColor Cyan
}

# 5) latencia sob carga
if ($base -and $melhor) {
    $proc = Start-Process -FilePath $script:Curl -WindowStyle Hidden -PassThru -ArgumentList @(
        '-s','-L','-A',$UA,'-o','NUL','--connect-timeout','8','--max-time','20','https://speed.cloudflare.com/__down?bytes=400000000')
    Start-Sleep -Seconds 3
    try {
        $p2 = Test-Connection -ComputerName '8.8.8.8' -Count 8 -ErrorAction SilentlyContinue
        if ($p2) {
            $t2 = @($p2 | ForEach-Object { [int]$_.ResponseTime })
            $m2 = [int](($t2 | Measure-Object -Average).Average)
            $delta = $m2 - $base
            $cor = 'Green'; if ($delta -gt 80) { $cor = 'Yellow' }; if ($delta -gt 200) { $cor = 'Red' }
            Write-Host ("  Em carga: media " + $m2 + " ms  (+" + $delta + " ms vs repouso)") -ForegroundColor $cor
            if ($delta -gt 200) { Det "Bufferbloat grave: ativa SQM/QoS no router ou limita o download a ~90% da linha." }
            elseif ($delta -gt 80) { Det "Bufferbloat moderado: a casa fica lenta com downloads grandes." }
            else { Det "Sem bufferbloat - a latencia aguenta-se com a linha ocupada." }
        }
    } finally {
        if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
}

# 6) veredito
Linha
if (-not $melhor) {
    Warn "INCONCLUSIVO: nenhuma fonte deu medicao valida (>=20 MB com HTTP 200)."
    Det "Nao significa 'linha lenta' - significa que os testes falharam."
    Det "Ve o que falhou acima (HTTP 403/404 = servidor; parcial = linha lenta)."
    Det "Confirma a mao: curl.exe -v -o NUL --max-time 15 `"https://speed.cloudflare.com/__down?bytes=20000000`""
    Det "Se aparecer 'SSL certificate problem'/'schannel', ha inspecao HTTPS ativa (antivirus ou Traffic Inspector)."
    return
}

Write-Host ("  MELHOR MEDICAO VALIDA: " + [math]::Round($melhor.Mbps,1) + " Mbps (" + $melhor.Nome + ", " + $melhor.MB + " MB)") -ForegroundColor White
$linhaMbps = $melhor.Mbps
if ($par -and $par.Mbps -gt $linhaMbps) { $linhaMbps = $par.Mbps }
if ($par) {
    Write-Host ("  MELHOR AGREGADO (" + $par.Streams + " streams): " + [math]::Round($par.Mbps,1) + " Mbps") -ForegroundColor White
    $ganho = $par.Mbps / [math]::Max($melhor.Mbps, 0.001)
    if ($ganho -ge 1.5) {
        Warn ("Multi-stream e " + [math]::Round($ganho,1) + "x mais rapido que um so stream -> o limite e POR CONEXAO, nao do caminho.")
        Det "Causas tipicas: 1 core a 100%, antivirus/inspecao HTTPS, autotuning TCP, MTU, ou um stream so a passar por caminho apertado."
        Det "O Steam/BF6 usa varios streams - por isso pode chegar a valores entre estes dois."
    } elseif ($ganho -le 1.2) {
        Info ("Multi-stream quase igual ao single (" + [math]::Round($ganho,1) + "x) -> o teto e do CAMINHO: router/QoS/ISP ou a porta/NIC.")
    }
}

Write-Host ""
if ($linhaMbps -lt 100) {
    Erro ("Abaixo de 100 Mbps (" + [math]::Round($linhaMbps,1) + " Mbps). Muito longe do plano de 1 Gbps.")
    Det "1) Realtek: 'Gigabit Lite' e 'Green Ethernet' -> Disabled; driver do fabricante da board."
    Det "2) Troca cabo + porta do router. 3) Ve QoS/limites no router. 4) Testa outro PC/telemovel."
} elseif ($linhaMbps -lt 300) {
    Warn ("Entre 100 e 300 Mbps (" + [math]::Round($linhaMbps,1) + " Mbps). Este e o padrao de link a 100 Mbps (cabo/porta/NIC) ou QoS ativo.")
    Det "Confirma: Get-NetAdapter | Format-Table Name, LinkSpeed, DriverVersion"
} elseif ($linhaMbps -lt 700) {
    Warn ("Entre 300 e 700 Mbps (" + [math]::Round($linhaMbps,1) + " Mbps) numa linha de 1 Gbps. Falta ~" + [math]::Round(1000 - $linhaMbps,0) + " Mbps.")
    Det "1) Realtek: 'Gigabit Lite'/'Green Ethernet' -> Disabled + driver recente (secao 4b-bis do guia)."
    Det "2) Router: desliga QoS/game boost/firewall extra e repete; compara com o speedtest do proprio ISP."
    Det "3) Confirma com outro equipamento (telemovel por Wi-Fi 5 GHz junto ao router)."
    Det "4) Se o multi-stream for muito maior que o single, o problema nao e da linha (ve acima)."
} elseif ($linhaMbps -lt 900) {
    Info ("Entre 700 e 900 Mbps (" + [math]::Round($linhaMbps,1) + " Mbps): perto do esperado, com alguma margem.")
} else {
    Ok ("Linha saudavel: " + [math]::Round($linhaMbps,1) + " Mbps. O gargalo do Steam nao esta na rede.")
    Det "Foca-te no limite de downloads do Steam (secao 3 do guia) e no disco (secao 7)."
}
if ($rotaWifi) { Warn "Nota: este teste correu pela Wi-Fi - repete com cabo para avaliar a linha." }
Write-Host ""
