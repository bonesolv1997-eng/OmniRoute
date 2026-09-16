@echo off
setlocal EnableExtensions
title Diagnostico de rede - OmniRoute (PT-PT)
cd /d "%~dp0"

echo.
echo  ============================================================
echo   DIAGNOSTICO DE REDE  -  OmniRoute (help PT-PT)
echo  ============================================================
echo.

set "PS1=%~dp0diagnostico-net-lenta.ps1"
set "URL=https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT/diagnostico-net-lenta.ps1"

where powershell >nul 2>&1
if errorlevel 1 (
  echo  [ERRO] Nao encontrei o "powershell" nesta maquina.
  echo         Abre o PowerShell e confirma que escreves "powershell -v".
  goto :fim
)

if exist "%PS1%" goto :correr

echo  [i] O ficheiro nao esta nesta pasta - vou descarrega-lo para a pasta temporaria...
set "PS1=%TEMP%\diagnostico-net-lenta.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile \"$env:TEMP\diagnostico-net-lenta.ps1\""
if errorlevel 1 (
  echo.
  echo  [ERRO] Nao consegui descarregar o script.
  echo         - Confirma que tens Internet;
  echo         - ou abre esta pagina e guarda o ficheiro na mesma pasta que este .cmd:
  echo           https://github.com/bonesolv1997-eng/OmniRoute/blob/arena/01a0aae0-omniroute/docs/help/pt-PT/diagnostico-net-lenta.ps1
  goto :fim
)

:correr
echo  [i] Ficheiro: %PS1%
echo  [i] A desbloquear (pode vir com bloqueio da Internet) e a correr...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%PS1%' -ErrorAction SilentlyContinue; & '%PS1%'"
echo.
echo  ============================================================
echo   Fim. O relatorio .txt fica na pasta do script (se foi
echo   descarregado, em %%TEMP%%).
echo  ============================================================

:fim
echo.
pause
endlocal
