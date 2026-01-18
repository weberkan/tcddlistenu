@echo off
title TCDD Bilet Izleyici Server
color 0A
echo =================================================
echo   TCDD Bilet Izleyici - Backend Baslatiliyor
echo =================================================
echo.
echo Lutfen bu pencereyi KAPATMAYIN. 
echo Arka planda calismaya devam etmesi gerekiyor.
echo.

cd /d "%~dp0"

REM Eger python path'te degilse asagiya tam yolu yazabilirsiniz
python api_server.py

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Bir hata olustu! Program kapaniyor...
    pause
)
