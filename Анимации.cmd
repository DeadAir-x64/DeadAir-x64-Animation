@echo off
setlocal
rem ============================================================================
rem  Dead Air x64 - модуль анимаций. Установка одним файлом.
rem
rem  Ничего никуда раскладывать не нужно: этот файл можно запускать откуда
rem  угодно, хоть из Загрузок. Он сам скачает установщик и сам найдёт игру.
rem
rem  Установщик качается КАЖДЫЙ раз, а не хранится рядом: так у человека
rem  всегда свежая версия, и починенная ошибка доезжает до него сама.
rem ============================================================================
title Dead Air x64 - модуль анимаций
cd /d "%~dp0"

set "PS1=%TEMP%\da_anim_install.ps1"
set "URL=https://raw.githubusercontent.com/DeadAir-x64/DeadAir-x64-Animation/main/anim_install.ps1"
set "API=https://api.github.com/repos/DeadAir-x64/DeadAir-x64-Animation/contents/anim_install.ps1?ref=main"

echo.
echo   Скачиваю установщик...

rem  Скачиваем с ЖЁСТКИМ ограничением по времени и запасным адресом.
rem  Раньше здесь стоял WebClient.DownloadFile, которому таймаут задать нечем:
rem  когда провайдер режет raw.githubusercontent по DPI, соединение не
rem  отвергается, а виснет, и ярлык замирал навсегда ещё до установщика.
rem  Запасной адрес - api.github.com: его режут заметно реже.
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072; foreach($x in @('%URL%','%API%')){ try { $r=[Net.HttpWebRequest]::Create($x); $r.UserAgent='DeadAir-x64-Animation'; if($x -like '*api.github*'){$r.Accept='application/vnd.github.raw'}; $r.Timeout=15000; $r.ReadWriteTimeout=15000; $p=$r.GetResponse(); $s=$p.GetResponseStream(); $b=New-Object byte[] 65536; $m=New-Object IO.MemoryStream; while(($n=$s.Read($b,0,$b.Length)) -gt 0){$m.Write($b,0,$n)}; $p.Close(); if($m.Length -lt 1000){continue}; [IO.File]::WriteAllBytes('%PS1%',$m.ToArray()); exit 0 } catch { } }; exit 1"

if errorlevel 1 (
  echo.
  echo   Не удалось скачать установщик.
  echo   Проверьте подключение к сети, либо скачайте архив вручную:
  echo   https://github.com/DeadAir-x64/DeadAir-x64-Animation/releases/latest
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
del "%PS1%" >nul 2>&1
endlocal
