<#
    baixar-kit.ps1 — descarrega TODOS os scripts deste kit para uma pasta e deixa tudo pronto.

    Uso (não precisa de administrador):
        powershell -ExecutionPolicy Bypass -File .\baixar-kit.ps1
        powershell -ExecutionPolicy Bypass -File .\baixar-kit.ps1 -Destino 'C:\Temp\kit'

    Por omissão, a pasta é:  Downloads\omniroute-net-kit
    No fim, o script imprime os comandos exatos para cada ferramenta — a partir da pasta
    onde os ficheiros ficam, os comandos funcionam sempre.
#>

[CmdletBinding()]
param([string]$Destino)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$BASE = 'https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT'
$ficheiros = @(
    'kit.ps1',
    'kit.cmd',
    'diagnostico-net-lenta.ps1',
    'medir-velocidade.ps1',
    'teste-ab-wifi.ps1',
    'desligar-poupanca-wifi.ps1',
    'correr-diagnostico.cmd',
    'README.md',
    'diagnostico-net-lenta.sh',
    'checar-nic-macos-linux.sh'
)

if (-not $Destino) {
    $base = Join-Path $env:USERPROFILE 'Downloads'
    if (-not (Test-Path $base)) { $base = $env:USERPROFILE }
    $Destino = Join-Path $base 'omniroute-net-kit'
}

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

Write-Host ""
Write-Host "  DESCARREGAR O KIT DE DIAGNOSTICO DE REDE" -ForegroundColor White
Write-Host ("  Destino: " + $Destino) -ForegroundColor DarkGray
Write-Host ""

try {
    if (-not (Test-Path $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }
} catch {
    Write-Host ("  [FALHA] Nao consegui criar a pasta " + $Destino + ": " + $_.Exception.Message) -ForegroundColor Red
    Write-Host "          Tenta com -Destino 'C:\Temp\kit'" -ForegroundColor Yellow
    return
}

$ok = 0; $falhou = @()
foreach ($f in $ficheiros) {
    $url = $BASE + '/' + $f
    $alvo = Join-Path $Destino $f
    Write-Host ("  · " + $f.PadRight(32)) -NoNewline
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $alvo -TimeoutSec 30 -ErrorAction Stop
        Unblock-File -LiteralPath $alvo -ErrorAction SilentlyContinue
        Write-Host "OK" -ForegroundColor Green
        $ok++
    } catch {
        Write-Host "FALHOU" -ForegroundColor Red
        $falhou += $f
    }
}

Write-Host ""
Write-Host ("  " + $ok + " de " + $ficheiros.Count + " ficheiros descarregados.") -ForegroundColor $(if ($falhou.Count -eq 0) { 'Green' } else { 'Yellow' })

if ($falhou.Count -gt 0) {
    Write-Host "  Falharam: " -ForegroundColor Yellow
    foreach ($f in $falhou) { Write-Host ("    - " + $f) -ForegroundColor Gray }
    Write-Host "  (Confirma a Internet. Se o problema for o GitHub, podes descarregar a pasta em ZIP:" -ForegroundColor Gray
    Write-Host "   https://github.com/bonesolv1997-eng/OmniRoute/tree/arena/01a0aae0-omniroute/docs/help/pt-PT )" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  COMANDOS (copia, cola e Enter):" -ForegroundColor Cyan
Write-Host ""
Write-Host "    cd `"$Destino`"" -ForegroundColor White
Write-Host "    powershell -ExecutionPolicy Bypass -File .\diagnostico-net-lenta.ps1      # relatorio completo" -ForegroundColor Gray
Write-Host "    powershell -ExecutionPolicy Bypass -File .\medir-velocidade.ps1           # teste A/B de 30 s" -ForegroundColor Gray
Write-Host "    powershell -ExecutionPolicy Bypass -File .\desligar-poupanca-wifi.ps1    # so diagnostico (nao altera nada)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Para APLICAR as alteracoes de Wi-Fi (precisa de Administrador):" -ForegroundColor Cyan
Write-Host "    1. Menu Iniciar > escreve 'PowerShell' > botao direito > Executar como administrador" -ForegroundColor Gray
Write-Host ("    2. cd `"$Destino`"") -ForegroundColor Gray
Write-Host "    3. powershell -ExecutionPolicy Bypass -File .\desligar-poupanca-wifi.ps1 -Aplicar" -ForegroundColor Gray
Write-Host ""
Write-Host "  Duplo clique: correr-diagnostico.cmd  (descarrega a versao mais recente e corre)" -ForegroundColor DarkGray
Write-Host "  Leitura:      README.md  (guia PT-PT com as secoes 4b a 4e)" -ForegroundColor DarkGray
Write-Host ""
