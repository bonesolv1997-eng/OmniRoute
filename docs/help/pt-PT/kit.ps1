<#
    kit.ps1 — ponto de entrada ÚNICO do kit de diagnóstico de rede (PT-PT).

    A ideia: nunca mais escreves o nome de um ficheiro. Este script descarrega os
    outros três sozinho e corre-os por caminho absoluto, por isso o erro
    "The argument '.\\nome.ps1' to the -File parameter does not exist" deixa de
    poder acontecer.

    Uso — sem guardar nada no disco (o mais simples, copia as 2 linhas):
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        iex (iwr 'https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT/kit.ps1' -UseBasicParsing).Content

    Uso — guardado em disco (menu igual):
        powershell -ExecutionPolicy Bypass -File .\kit.ps1

    Uso — direto, sem menu (útil para automatizar):
        -Tarefa diagnostico | velocidade | wifi | wifi-aplicar | wifi-reverter | baixar | ler

    Notas:
      · a opção 4 (aplicar) precisa de administrador — o script abre ele próprio a
        janela elevada, não tens de fazer nada;
      · não altera nada do sistema nas opções 1, 2, 3, 6 e 7.
#>

[CmdletBinding()]
param(
    [ValidateSet('menu', 'diagnostico', 'velocidade', 'wifi', 'wifi-aplicar', 'wifi-reverter', 'baixar', 'ler')]
    [string]$Tarefa = 'menu'
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$BASE = 'https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT'
$SCRIPTS = @('diagnostico-net-lenta.ps1', 'medir-velocidade.ps1', 'desligar-poupanca-wifi.ps1', 'baixar-kit.ps1', 'correr-diagnostico.cmd', 'README.md')

# Quando corrido via iex, $PSScriptRoot vem vazio: usamos uma pasta fixa em %TEMP%.
$raiz = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:TEMP 'omniroute-kit' }
if (-not (Test-Path $raiz)) { New-Item -ItemType Directory -Path $raiz -Force | Out-Null }

function Escreve-Titulo {
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host "   KIT DE DIAGNOSTICO DE REDE  -  OmniRoute (PT-PT)" -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor DarkCyan
    Write-Host ("   Pasta de trabalho: " + $raiz) -ForegroundColor DarkGray
    Write-Host ""
}

function Obter-Ficheiro([string]$nome) {
    $alvo = Join-Path $raiz $nome
    if (Test-Path $alvo) { return $alvo }
    Write-Host ("  [i] A descarregar " + $nome + "...") -ForegroundColor DarkCyan
    try {
        Invoke-WebRequest -UseBasicParsing -Uri ($BASE + '/' + $nome) -OutFile $alvo -TimeoutSec 30 -ErrorAction Stop
        Unblock-File -LiteralPath $alvo -ErrorAction SilentlyContinue
        return $alvo
    } catch {
        Write-Host ("  [FALHA] Nao consegui descarregar " + $nome) -ForegroundColor Red
        Write-Host ("          Verifica a Internet. URL manual: " + $BASE + '/' + $nome) -ForegroundColor Yellow
        return $null
    }
}

function Baixar-Tudo {
    $ok = 0; $falhas = @()
    foreach ($f in $SCRIPTS) {
        $destino = Join-Path $raiz $f
        Write-Host ("  · " + $f.PadRight(30)) -NoNewline
        try {
            Invoke-WebRequest -UseBasicParsing -Uri ($BASE + '/' + $f) -OutFile $destino -TimeoutSec 30 -ErrorAction Stop
            Unblock-File -LiteralPath $destino -ErrorAction SilentlyContinue
            Write-Host "OK" -ForegroundColor Green
            $ok++
        } catch {
            Write-Host "FALHOU" -ForegroundColor Red
            $falhas += $f
        }
    }
    Write-Host ""
    Write-Host ("  " + $ok + " de " + $SCRIPTS.Count + " ficheiros atualizados em " + $raiz) -ForegroundColor $(if ($falhas.Count -eq 0) { 'Green' } else { 'Yellow' })
    if ($falhas.Count -gt 0) { Write-Host ("  Sem rede para: " + ($falhas -join ', ')) -ForegroundColor Yellow }
}

function Eh-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Correr-Script([string]$nome, [string[]]$argumentos = @()) {
    $p = Obter-Ficheiro $nome
    if (-not $p) { return }
    Write-Host ""
    Write-Host ("  > " + $nome + " " + ($argumentos -join ' ')) -ForegroundColor DarkGray
    Write-Host ""
    try {
        & $p @argumentos
    } catch {
        Write-Host ("  [FALHA] O script terminou com erro: " + $_.Exception.Message) -ForegroundColor Red
        Write-Host ("          Podes correr a mao: powershell -ExecutionPolicy Bypass -File `"" + $p + "`"") -ForegroundColor Yellow
    }
}

function Correr-Elevado([string]$nome, [string[]]$argumentos = @()) {
    $p = Obter-Ficheiro $nome
    if (-not $p) { return }
    if (Eh-Admin) {
        Correr-Script $nome $argumentos
        return
    }
    Write-Host "  [i] Esta tarefa precisa de Administrador. Vou abrir uma janela elevada..." -ForegroundColor Yellow
    $lista = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', ('"' + $p + '"')) + $argumentos
    try {
        Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList $lista -ErrorAction Stop
        Write-Host "  [OK] Janela elevada aberta. Segue as instrucoes nessa janela (fica aberta no fim)." -ForegroundColor Green
    } catch {
        Write-Host "  [FALHA] Nao consegui abrir a janela elevada (cancelaste o UAC?)." -ForegroundColor Red
        Write-Host ("          Abre o PowerShell como administrador e corre: & `"" + $p + "`" " + ($argumentos -join ' ')) -ForegroundColor Yellow
    }
}

function Abrir-Guia {
    $p = Obter-Ficheiro 'README.md'
    if (-not $p) { return }
    Write-Host ("  [i] Guia: " + $p) -ForegroundColor DarkCyan
    try { Invoke-Item -LiteralPath $p } catch { Write-Host "  [i] Abre esse ficheiro manualmente para o ler." -ForegroundColor Yellow }
}

function Pausa {
    try { Write-Host ""; Read-Host "  Enter para voltar ao menu" | Out-Null } catch { }
}

Escreve-Titulo

if ($Tarefa -eq 'diagnostico') { Correr-Script 'diagnostico-net-lenta.ps1'; return }
if ($Tarefa -eq 'velocidade') { Correr-Script 'medir-velocidade.ps1'; return }
if ($Tarefa -eq 'wifi') { Correr-Script 'desligar-poupanca-wifi.ps1'; return }
if ($Tarefa -eq 'wifi-aplicar') { Correr-Elevado 'desligar-poupanca-wifi.ps1' @('-Aplicar'); return }
if ($Tarefa -eq 'wifi-reverter') { Correr-Elevado 'desligar-poupanca-wifi.ps1' @('-Reverter'); return }
if ($Tarefa -eq 'baixar') { Baixar-Tudo; return }
if ($Tarefa -eq 'ler') { Abrir-Guia; return }

# ── Menu ───────────────────────────────────────────────────────────────────
while ($true) {
    Write-Host "  O que queres fazer?" -ForegroundColor White
    Write-Host ""
    Write-Host "   1) Diagnostico completo da rede            (nao altera nada)" -ForegroundColor Gray
    Write-Host "   2) Teste de velocidade rapido (30 s)        (nao altera nada)" -ForegroundColor Gray
    Write-Host "   3) Wi-Fi: ver chip, driver e poupanca       (nao altera nada)" -ForegroundColor Gray
    Write-Host "   4) Wi-Fi: APLICAR correcoes                 (abre janela admin)" -ForegroundColor Gray
    Write-Host "   5) Wi-Fi: reverter alteracoes               (abre janela admin)" -ForegroundColor Gray
    Write-Host "   6) Descarregar/atualizar todos os ficheiros" -ForegroundColor Gray
    Write-Host "   7) Abrir o guia (README.md)" -ForegroundColor Gray
    Write-Host "   0) Sair" -ForegroundColor Gray
    Write-Host ""

    $escolha = ''
    try { $escolha = (Read-Host "  Escolhe (0-7)").Trim() } catch {
        Write-Host "  (sem entrada interativa — usa -Tarefa, ex: -Tarefa diagnostico)" -ForegroundColor Yellow
        return
    }

    switch ($escolha) {
        '1' { Correr-Script 'diagnostico-net-lenta.ps1' }
        '2' { Correr-Script 'medir-velocidade.ps1' }
        '3' { Correr-Script 'desligar-poupanca-wifi.ps1' }
        '4' { Correr-Elevado 'desligar-poupanca-wifi.ps1' @('-Aplicar') }
        '5' { Correr-Elevado 'desligar-poupanca-wifi.ps1' @('-Reverter') }
        '6' { Baixar-Tudo }
        '7' { Abrir-Guia }
        '0' { Write-Host ""; Write-Host "  Ate ja. Relatorios ficam na pasta acima." -ForegroundColor DarkCyan; Write-Host ""; return }
        default { Write-Host "  Escolhe um numero de 0 a 7." -ForegroundColor Yellow; continue }
    }
    Pausa
    Escreve-Titulo
}
