<#
    desligar-poupanca-wifi.ps1 — Wi-Fi: ver o chip/driver, e desligar a poupança de energia
    --------------------------------------------------------------------------------------
    Sem argumentos  -> só MOSTRA o estado e o que faria (não altera nada).
    -Aplicar        -> aplica: desliga a gestão de energia do adaptador, põe as
                       propriedades avançadas de poupança a "desempenho máximo" e
                       define a política de energia do plano atual para máximo desempenho.
                       Precisa de PowerShell como Administrador.
    -Reverter       -> volta a ligar a gestão de energia do adaptador e a poupança do plano.

    Uso:
        powershell -ExecutionPolicy Bypass -File .\desligar-poupanca-wifi.ps1
        powershell -ExecutionPolicy Bypass -File .\desligar-poupanca-wifi.ps1 -Aplicar   (como admin)

    Nota: depois de aplicar, o Wi-Fi reinicia (~5 s sem ligação). É normal.
#>

[CmdletBinding()]
param([switch]$Aplicar, [switch]$Reverter)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$ehAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Titulo($t) { Write-Host ""; Write-Host ("  " + $t) -ForegroundColor Cyan; Write-Host ("  " + ("-" * 74)) -ForegroundColor DarkGray }
function Ok($t) { Write-Host ("  [OK]      " + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ("  [ATENÇÃO] " + $t) -ForegroundColor Yellow }
function Info($t) { Write-Host ("  [i]       " + $t) -ForegroundColor DarkCyan }
function Erro($t) { Write-Host ("  [FALHA]   " + $t) -ForegroundColor Red }
function Det($t) { Write-Host ("        " + $t) -ForegroundColor Gray }

Write-Host ""
Write-Host "  WI-FI: CHIP, DRIVER E POUPANÇA DE ENERGIA" -ForegroundColor White
Write-Host ("  Modo: " + $(if ($Aplicar) { "APLICAR (altera o sistema)" } elseif ($Reverter) { "REVERTER" } else { "só diagnóstico (não altera nada)" }) + "   |   Administrador: " + $ehAdmin) -ForegroundColor DarkGray

# ────────────────────────────────────────────────────────────────────────────
Titulo "1. Adaptadores Wi-Fi"

$adapta = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    $_.PhysicalMediaType -match '802\.11' -or $_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN|802\.11'
})

if ($adapta.Count -eq 0) {
    Warn "Não encontrei nenhum adaptador Wi-Fi. Se usas um dongle USB, confirma que está ligado (ele aparece aqui)."
    return
}

$fabricante = $null
foreach ($a in $adapta) {
    $dd = ""
    try { if ($a.DriverDate) { $dd = ([datetime]$a.DriverDate).ToString('yyyy-MM-dd') } } catch { }
    Write-Host ""
    Write-Host ("  · " + $a.Name + "  [" + $a.InterfaceDescription + "]") -ForegroundColor White
    Det ("Estado: " + $a.Status + "   |   Link: " + $a.LinkSpeed + "   |   Driver: " + $a.DriverProvider + " " + $a.DriverVersion + "   (" + $dd + ")")

    # Identificar o chip -> onde se atualiza
    $desc = $a.InterfaceDescription
    $onde = ""
    if ($desc -match 'Intel|Killer') {
        $fabricante = 'Intel'
        if ($desc -match 'BE2\d\d|AX2\d\d|AX411|AX211|AX210|AX203|AX201|AX200|AX101|9[0-9]{3}|Wireless-AC') {
            $onde = "Intel DSA (recomendado) ou o pacote oficial 'Intel Wireless Wi-Fi Drivers' (versão atual 24.70.0, 08/09/2026). O DSA escolhe sozinho o pacote certo para o teu modelo."
        }
        if ($desc -match 'Killer') {
            $onde += " Este é um modelo 'Killer': usa o Intel Killer Performance Suite em vez do pacote genérico."
        }
    } elseif ($desc -match 'MediaTek|RZ608|RZ616|MT79\d\d') {
        $fabricante = 'MediaTek'
        $onde = "Adaptador MediaTek (muito comum em placas AMD — o RZ608/RZ616 são MediaTek MT7921/MT7922 com nome AMD). O Intel DSA NÃO o deteta: atualiza pelo site do fabricante da placa-mãe (modelo exato) ou pelo pacote da MediaTek/AMD."
    } elseif ($desc -match 'Realtek|RTL88') {
        $fabricante = 'Realtek'
        $onde = "Adaptador Realtek. O Intel DSA não serve: usa o site do fabricante da placa-mãe (ou do dongle, se for USB)."
    } elseif ($desc -match 'Qualcomm|QCA|Atheros') {
        $fabricante = 'Qualcomm'
        $onde = "Adaptador Qualcomm/Atheros: driver pelo fabricante da placa-mãe ou do dongle."
    } elseif ($desc -match 'Broadcom|BCM') {
        $fabricante = 'Broadcom'
        $onde = "Adaptador Broadcom: driver pelo fabricante do portátil/placa."
    } else {
        $fabricante = 'desconhecido'
        $onde = "Não reconheci o chip. Atualiza pelo site do fabricante da placa-mãe/portátil, pelo modelo exato do adaptador."
    }

    if ($onde) { Info "Onde atualizar: $onde" }

    try {
        if ($a.DriverDate -and ([datetime]$a.DriverDate) -lt (Get-Date).AddYears(-3)) {
            Warn ("O driver de " + $a.Name + " é de " + $dd + " — tem mais de 3 anos. Num adaptador Intel, saltar de 2021 para a série 24.x traz melhorias grandes de estabilidade e de consumo; em MediaTek/Realtek a diferença também é notória.")
        }
    } catch { }

    # Gestão de energia atual
    Write-Host ""
    Write-Host "  Gestão de energia do adaptador:" -ForegroundColor White
    try {
        $pm = Get-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop
        Det ("Permitir que o Windows desligue este dispositivo: " + $pm.AllowComputerToTurnOffDevice)
        if ($pm.AllowComputerToTurnOffDevice -match 'Enabled') {
            Warn "Está LIGADO — é isto que faz o Wi-Fi adormecer e a velocidade cair/parar a meio dos downloads."
        } else {
            Ok "Já está desligado (ou o driver não suporta essa poupança)."
        }
    } catch {
        Info "Este driver não expõe a gestão de energia via PowerShell (não é erro)."
    }

    # Propriedades avançadas relevantes
    Write-Host ""
    Write-Host "  Propriedades avançadas de poupança:" -ForegroundColor White
    $adv = @()
    try { $adv = @(Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction Stop) } catch { }
    $alvos = @(
        @{ Nome = 'Power Saving Mode';       Pref = @('Maximum Performance','Desempenho máximo','5. Highest','Highest') },
        @{ Nome = 'Modo de economia de energia'; Pref = @('Maximum Performance','Desempenho máximo','Highest') },
        @{ Nome = 'U-APSD';                  Pref = @('Disabled','Desativado') },
        @{ Nome = 'MIMO Power Save';         Pref = @('No SMPS','Disabled','Desativado') },
        @{ Nome = 'Sleep on WoWLAN';         Pref = @('Disabled','Desativado') },
        @{ Nome = 'Extreme Power Saver';     Pref = @('Disabled','Desativado') },
        @{ Nome = 'Packet Coalescing';       Pref = @('Disabled','Desativado') },
        @{ Nome = 'Power Save';              Pref = @('Disabled','Desativado') },
        @{ Nome = 'Transmit Power';          Pref = @('5. Highest','Highest','Maximum','Máximo') }
    )
    $mudar = @()
    if ($adv.Count -gt 0) {
        foreach ($alvo in $alvos) {
            $prop = $adv | Where-Object { $_.DisplayName -like ("*" + $alvo.Nome + "*") } | Select-Object -First 1
            if (-not $prop) { continue }
            $atual = $prop.DisplayValue
            $escolhido = $null
            foreach ($p in $alvo.Pref) {
                $val = $prop.ValidDisplayValues | Where-Object { $_ -eq $p } | Select-Object -First 1
                if ($val) { $escolhido = $val; break }
            }
            Det ($prop.DisplayName.TrimEnd() + " = '" + $atual + "'" + $(if ($escolhido) { "   -> sugerido: '" + $escolhido + "'" } else { "   (valores possíveis: " + (($prop.ValidDisplayValues | Select-Object -Unique) -join " / ") + ")" }))
            if ($escolhido -and $atual -ne $escolhido) { $mudar += [pscustomobject]@{ Adaptador = $a.Name; Propriedade = $prop.DisplayName.TrimEnd(); De = $atual; Para = $escolhido } }
        }
    }
    if ($mudar.Count -eq 0) { Ok "Nada a mudar aqui (ou o driver não expõe estas propriedades)." }
}

# ────────────────────────────────────────────────────────────────────────────
Titulo "2. Política de energia do plano ativo (Wi-Fi)"

$saida = powercfg /query SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 2>&1
$leitura = ($saida | Select-String -Pattern 'Current AC Power Setting Index|Índice de definição de energia de CA atual|0x') | Select-Object -First 2
if ($leitura) {
    foreach ($l in $leitura) { Det ($l.Line.Trim()) }
    Det "0x0 = Máximo desempenho | 0x1 = Baixa | 0x2 = Média | 0x3 = Máxima poupança"
} else {
    Info "Não consegui ler a política de energia do Wi-Fi via powercfg (não é erro)."
}

# ────────────────────────────────────────────────────────────────────────────
Titulo "3. O que fazer"

if ($Aplicar -or $Reverter) {
    if (-not $ehAdmin) {
        Erro "Precisas de PowerShell como Administrador para aplicar alterações."
        Write-Host "        Abre: Menu Iniciar > escreve 'PowerShell' > botão direito > Executar como administrador." -ForegroundColor Yellow
        Write-Host "        Depois:  powershell -ExecutionPolicy Bypass -File .\desligar-poupanca-wifi.ps1 -Aplicar" -ForegroundColor Yellow
        return
    }

    foreach ($a in $adapta) {
        if ($Reverter) {
            try { Enable-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop; Ok ("Gestão de energia religada em " + $a.Name) }
            catch { Info ("Não consegui religar a gestão de energia em " + $a.Name + " (o driver pode não suportar).") }
        } else {
            try { Disable-NetAdapterPowerManagement -Name $a.Name -ErrorAction Stop; Ok ("Gestão de energia DESLIGADA em " + $a.Name) }
            catch { Warn ("Não consegui desligar a gestão de energia em " + $a.Name + " — faz manualmente em Gestor de Dispositivos > adaptador > Propriedades > Gestão de energia.") }
        }
    }

    # Política de energia do plano ativo (CA e bateria)
    $valor = if ($Reverter) { 2 } else { 0 }   # 0 = máximo desempenho, 2 = média (equilibrado)
    $r1 = powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a $valor 2>&1
    $r2 = powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a $valor 2>&1
    $r3 = powercfg /setactive SCHEME_CURRENT 2>&1
    if ($LASTEXITCODE -eq 0) {
        Ok ("Política de energia do Wi-Fi definida para " + $(if ($Reverter) { "Equilibrado (média)" } else { "Máximo desempenho" }) + " no plano ativo.")
    } else {
        Warn "powercfg não aceitou a alteração — faz pela interface: Painel de Controlo > Opções de Energia > Alterar definições do plano > Alterar definições avançadas > Definições do adaptador sem fios > Modo de poupança de energia > Máximo desempenho."
    }

    if (-not $Reverter) {
        foreach ($m in $mudar) {
            try {
                Set-NetAdapterAdvancedProperty -Name $m.Adaptador -DisplayName $m.Propriedade -DisplayValue $m.Para -ErrorAction Stop
                Ok ($m.Propriedade + ": '" + $m.De + "' -> '" + $m.Para + "'")
            } catch {
                Warn ("Não consegui mudar '" + $m.Propriedade + "' — muda manualmente: Gestor de Dispositivos > adaptador > Propriedades > Avançadas.")
            }
        }
        Write-Host ""
        Info "A reiniciar o(s) adaptador(es) Wi-Fi para aplicar (a ligação cai ~5 segundos)..."
        foreach ($a in $adapta) {
            try { Restart-NetAdapter -Name $a.Name -ErrorAction Stop; Ok ("Reiniciado: " + $a.Name) } catch { Info ("Não reiniciei " + $a.Name + " automaticamente.") }
        }
    }
} else {
    Write-Host "  Nada foi alterado (modo diagnóstico). Para aplicar:" -ForegroundColor White
    Write-Host "    1. Menu Iniciar > PowerShell > botão direito > Executar como administrador" -ForegroundColor Gray
    Write-Host "    2. powershell -ExecutionPolicy Bypass -File .\desligar-poupanca-wifi.ps1 -Aplicar" -ForegroundColor Gray
    if ($mudar.Count -gt 0) {
        Write-Host ""
        Write-Host "  Vai mudar:" -ForegroundColor White
        foreach ($m in $mudar) { Write-Host ("    · " + $m.Propriedade + ": '" + $m.De + "' -> '" + $m.Para + "'") -ForegroundColor Gray }
    }
}

# ────────────────────────────────────────────────────────────────────────────
Titulo "4. Atualizar o driver (o que fazer à mão, passo a passo)"

if ($fabricante -eq 'Intel') {
    Write-Host "  Opção A — Intel DSA (recomendada, deteta sozinho):" -ForegroundColor White
    Write-Host "    1. Abre https://www.intel.com/content/www/us/en/support/detect.html" -ForegroundColor Gray
    Write-Host "    2. Clica 'Download now', corre o instalador (UAC: Sim) e deixa instalar." -ForegroundColor Gray
    Write-Host "    3. O DSA abre no browser; autoriza o scan (botão 'Allow')." -ForegroundColor Gray
    Write-Host "    4. Em 'Wi-Fi' clica Download e depois Install; reinicia se ele pedir." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Opção B — pacote oficial do driver Wi-Fi (manual):" -ForegroundColor White
    Write-Host "    Página: https://www.intel.com/content/www/us/en/download/19351/intel-wireless-wi-fi-drivers-for-windows-10-and-windows-11.html" -ForegroundColor Gray
    Write-Host "    Versão atual: 24.70.0 (08/09/2026) — ficheiro WiFi-24.70.0-Driver64-Win10-Win11.exe" -ForegroundColor Gray
    Write-Host "    Cobre Wi-Fi 7 (BE200/BE201/BE202/BE211/BE213), Wi-Fi 6E (AX411/AX211/AX210)," -ForegroundColor Gray
    Write-Host "    Wi-Fi 6 (AX231/AX203/AX201/AX200/AX101) e 9000 (9560/9260/9462/9461)." -ForegroundColor Gray
    Write-Host "    Nota: o AX200 e alguns 8xxx têm pacote próprio — o DSA escolhe o certo por ti." -ForegroundColor Gray
} else {
    Write-Host "  Como o adaptador não é Intel, o DSA não serve. Atualiza assim:" -ForegroundColor White
    Write-Host "    1. Descobre o modelo da placa-mãe:  wmic baseboard get product,manufacturer" -ForegroundColor Gray
    Write-Host "       (ou: Get-CimInstance Win32_BaseBoard | Format-List Manufacturer,Product)" -ForegroundColor Gray
    Write-Host "    2. Vai ao site do fabricante (MSI/ASUS/Gigabyte/ASRock) > Suporte > modelo exato > Drivers > LAN/Wireless." -ForegroundColor Gray
    Write-Host "    3. Se for um dongle USB, o driver é do fabricante do dongle (o modelo está na caixa/estampado)." -ForegroundColor Gray
    Write-Host "    4. Alternativa: Definições > Windows Update > Opções avançadas > Atualizações opcionais > Atualizações de controladores." -ForegroundColor Gray
}

Write-Host ""
Info "Depois de atualizar o driver, corre o medir-velocidade.ps1 com a Wi-Fi ligada e desligada — só assim vês o ganho real."
Write-Host ""
