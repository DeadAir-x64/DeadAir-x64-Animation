@echo off
rem Установка, обновление и снятие модуля анимаций Dead Air x64.
rem
rem Положите этот файл и anim_install.ps1 в корень установленной игры
rem (туда, где database и fsgame.ltx) и запустите.
rem
rem Архив приезжает одним файлом на 173 МБ. Оборванная загрузка продолжается
rem с того места, где встала.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0anim_install.ps1"
