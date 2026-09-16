@echo off
setlocal EnableExtensions
title Kit de rede - OmniRoute (menu)
cd /d "%~dp0"

set "BASE=https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT"
set "KIT=%TEMP%\omniroute-kit\kit.ps1"

echo.
echo  ============================================================
echo   KIT DE DIAGNOSTICO DE REDE  -  OmniRoute (PT-PT)
echo  ============================================================
echo.

where powershell >nul 2>&1
if errorlevel 1 (
  echo  [ERRO] Nao encontrei o "powershell" nesta maquina.
  goto :fim
)

if not exist "%TEMP%\omniroute-kit" mkdir "%TEMP%\omniroute-kit" >nul 2>&1

echo  [i] A obter a versao mais recente do menu...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/kit.ps1' -OutFile \"$env:TEMP\omniroute-kit\kit.ps1\" -TimeoutSec 25; Unblock-File -LiteralPath \"$env:TEMP\omniroute-kit\kit.ps1\" -ErrorAction SilentlyContinue; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  if not exist "%KIT%" (
    echo  [ERRO] Sem Internet e sem copia local do menu.
    echo         Abre esta pagina, guarda o kit.ps1 na pasta deste .cmd e volta a correr:
    echo         %BASE%/kit.ps1
    goto :fim
  )
  echo  [i] Sem Internet - a usar a copia local.
)

echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%KIT%"
echo.
echo  Fim. Podes fechar esta janela.
echo.
pause
endlocal
