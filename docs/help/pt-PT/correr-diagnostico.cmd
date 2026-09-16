@echo off
setlocal EnableExtensions
title Diagnostico de rede - OmniRoute (PT-PT)
cd /d "%~dp0"

echo.
echo  ============================================================
echo   DIAGNOSTICO DE REDE  -  OmniRoute (help PT-PT)
echo  ============================================================
echo.

set "BASE=https://raw.githubusercontent.com/bonesolv1997-eng/OmniRoute/arena/01a0aae0-omniroute/docs/help/pt-PT"
set "LOCAL=%~dp0diagnostico-net-lenta.ps1"
set "PS1=%TEMP%\diagnostico-net-lenta.ps1"

where powershell >nul 2>&1
if errorlevel 1 (
  echo  [ERRO] Nao encontrei o "powershell" nesta maquina.
  goto :fim
)

echo  [i] A obter a versao mais recente dos scripts...
set "FALHOU=0"
for %%F in (diagnostico-net-lenta.ps1 medir-velocidade.ps1 desligar-poupanca-wifi.ps1) do (
  echo   - %%F
  powershell -NoProfile -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $d = $env:TEMP + '\' + '%%F'; Invoke-WebRequest -UseBasicParsing -Uri '%BASE%/%%F?cb=%RANDOM%%RANDOM%' -OutFile $d -TimeoutSec 25; Unblock-File -LiteralPath $d -ErrorAction SilentlyContinue; exit 0 } catch { exit 1 }"
  if errorlevel 1 set "FALHOU=1"
)

if "%FALHOU%"=="1" (
  echo  [i] Nao consegui descarregar tudo ^(sem Internet?^). A usar copias locais, se existirem...
  if exist "%LOCAL%" (
    set "PS1=%LOCAL%"
  ) else (
    echo.
    echo  [ERRO] Nao ha copia local nem Internet. Abre esta pagina, guarda os ficheiros na
    echo         mesma pasta que este .cmd e volta a correr:
    echo         https://github.com/bonesolv1997-eng/OmniRoute/tree/arena/01a0aae0-omniroute/docs/help/pt-PT
    goto :fim
  )
)

echo.
echo  [i] Ficheiro: %PS1%
echo  [i] A correr o diagnostico completo...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%PS1%' -ErrorAction SilentlyContinue; & '%PS1%'"

echo.
echo  ============================================================
echo   Fim. Scripts disponiveis em %%TEMP%%:
echo     medir-velocidade.ps1        (teste de 30 s)
echo     desligar-poupanca-wifi.ps1  (Wi-Fi: diagnostico; -Aplicar altera)
echo   O relatorio .txt ficou na pasta de onde o script correu.
echo  ============================================================

:fim
echo.
pause
endlocal
