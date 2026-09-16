@echo off
setlocal EnableExtensions
title Diagnostico de rede - OmniRoute (PT-PT)
cd /d "%~dp0"

echo.
echo  ============================================================
echo   DIAGNOSTICO DE REDE  -  OmniRoute (help PT-PT)
echo  ============================================================
echo.

set "LOCAL=%~dp0diagnostico-net-lenta.ps1"
set "PS1=%TEMP%\diagnostico-net-lenta.ps1"
set "URL=https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT/diagnostico-net-lenta.ps1"

where powershell >nul 2>&1
if errorlevel 1 (
  echo  [ERRO] Nao encontrei o "powershell" nesta maquina.
  goto :fim
)

echo  [i] A obter sempre a versao mais recente do script...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile \"$env:TEMP\diagnostico-net-lenta.ps1\" -TimeoutSec 25; exit 0 } catch { exit 1 }"
if errorlevel 1 (
  echo  [i] Nao consegui descarregar ^(sem Internet^). A usar a copia local, se existir...
  if exist "%LOCAL%" (
    set "PS1=%LOCAL%"
  ) else (
    echo.
    echo  [ERRO] Nao ha copia local nem Internet. Abre esta pagina, guarda o ficheiro
    echo         na mesma pasta que este .cmd e volta a correr:
    echo         https://github.com/bonesolv1997-eng/OmniRoute/blob/arena/01a0aae0-omniroute/docs/help/pt-PT/diagnostico-net-lenta.ps1
    goto :fim
  )
)

echo  [i] Ficheiro: %PS1%
echo  [i] A desbloquear e a correr...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%PS1%' -ErrorAction SilentlyContinue; & '%PS1%'"
echo.
echo  ============================================================
echo   Fim. O relatorio .txt ficou na pasta de onde o script correu
echo   (normalmente %%TEMP%%).
echo  ============================================================

:fim
echo.
pause
endlocal
