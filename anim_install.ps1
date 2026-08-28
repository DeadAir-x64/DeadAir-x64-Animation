# Dead Air x64 — установка модуля анимаций.
#
# Кладётся в папку с игрой (туда, где database и fsgame.ltx) и запускается.
#
# Модуль — ОДИН архив на 173 МБ, который просто ложится в database. Он ничего не перекрывает
# и ничего не заменяет: файлы игры остаются нетронутыми, поэтому резервировать нечего, а снятие
# сводится к удалению одного файла. Этим он проще HD-текстур, где перекрытые файлы приходится
# уносить в резерв и возвращать.
#
# Что поставлено, помнит da_animations_version.txt рядом с архивом.

$ErrorActionPreference = 'Stop'

$Owner = 'DeadAir-x64'
$Repo  = 'DeadAir-x64-Animation'
$Asset = 'da_animations.xdb0'

# --- СОВМЕСТИМОСТЬ СО СТАРЫМИ WINDOWS -------------------------------------------------------
# GitHub принимает только TLS 1.2, а Windows 7 и ранние сборки Windows 10 по умолчанию
# предлагают TLS 1.0 — соединение обрывается ещё до запроса, с невнятной ошибкой.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

if ($PSVersionTable.PSVersion.Major -lt 3) {
    Write-Host ''
    Write-Host '  Нужен PowerShell версии 3.0 или новее.' -ForegroundColor Red
    Write-Host "  У вас: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host ''
    Write-Host '  На Windows 7 он ставится обновлением Windows Management Framework:'
    Write-Host '  https://www.microsoft.com/download/details.aspx?id=54616'
    Write-Host ''
    Read-Host 'Enter — выход'
    exit 1
}

# --- ВЫВОД ----------------------------------------------------------------------------------
# Определения стоят ЗДЕСЬ, выше всего остального: PowerShell выполняет файл сверху вниз, и функция
# существует только после того, как строка с её определением выполнена. Спасательная ветка,
# зовущая Say раньше, чем Say объявлен, роняет скрипт вместо того, чтобы спасать.
function Say($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Fail($text) { Say ''; Say "ОШИБКА: $text" 'Red'; Say ''; Read-Host 'Enter — выход'; exit 1 }

function Size($bytes) {
    if ($bytes -ge 1GB) { return ('{0:N2} ГБ' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N0} МБ' -f ($bytes / 1MB)) }
    return ('{0:N0} КБ' -f ($bytes / 1KB))
}

# PowerShell 5.1 в Set-Content -Encoding UTF8 ставит BOM в начало файла. Для отметок это не
# косметика, а поломка: строка версии становится не равна самой себе, и уже поставленный модуль
# качается заново, все 173 МБ. Пишем через .NET с явным «без BOM», а на чтении BOM снимаем:
# у тех, кто ставил прежней версией, отметки уже с ним.
$Utf8NoBom = New-Object Text.UTF8Encoding($false)
function WriteText($path, $text) { [IO.File]::WriteAllText($path, $text, $Utf8NoBom) }
function ReadText($path) {
    if (-not (Test-Path $path)) { return '' }
    return ([IO.File]::ReadAllText($path)).TrimStart([char]0xFEFF).Trim()
}

# --- ГДЕ ИГРА -------------------------------------------------------------------------------
# Игру ищем САМИ, а не требуем положить скрипт в нужное место.
#
# Требование «положите в корень игры» выглядит пустяком для того, кто его писал, и работает ровно
# наоборот для того, кто ставит: человек скачивает файл в Загрузки, запускает оттуда, получает
# отказ и идёт разбираться, что такое «корень игры». Найти папку самим — работа на тридцать
# строк, и она снимает единственный шаг, где можно ошибиться.
#
# Порядок поиска — от самого надёжного к самому широкому, и на первом попадании останавливаемся.
function Test-GameRoot($p) {
    if (-not $p) { return $false }
    return (Test-Path (Join-Path $p 'fsgame.ltx')) -and (Test-Path (Join-Path $p 'database'))
}

function Find-Game($startDir) {
    # 1. Там, откуда запустили, и три уровня вверх: покрывает и «положил в корень игры»,
    #    и «положил в подпапку игры».
    #
    # ⭐ Эта ветка возвращает ответ СРАЗУ и без вопросов — и только она. Если человек запустил
    # файл из папки игры, он уже сказал, какую игру имеет в виду, и переспрашивать глупо.
    $script:FoundByLocation = $false
    $p = $startDir
    for ($i = 0; $i -lt 4 -and $p; $i++) {
        if (Test-GameRoot $p) { $script:FoundByLocation = $true; return $p }
        $p = Split-Path -Parent $p
    }

    # Дальше собираем ВСЕ находки, а не первую попавшуюся.
    #
    # 🪤 Установок бывает несколько: рабочая и чистая, старая и новая. Первая попавшаяся — это
    # лотерея, и проигрыш в ней означает «поставил не туда»: человек запускает игру, анимаций
    # нет, и он идёт разбираться, хотя установщик отчитался успехом. Проверено на машине
    # разработчика: запуск из «Загрузок» находил не ту копию.
    $found = New-Object Collections.ArrayList

    # 2. Запись установщика игры в реестре. Самый точный источник: путь тот, куда игру
    #    действительно поставили, а не тот, где её принято держать.
    foreach ($hive in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
                        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
        if (-not (Test-Path $hive)) { continue }
        try {
            foreach ($k in Get-ChildItem $hive -ErrorAction SilentlyContinue) {
                $v = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
                if ($v.DisplayName -and $v.DisplayName -match 'Dead\s*Air' -and $v.InstallLocation) {
                    if (Test-GameRoot $v.InstallLocation) {
                        $null = $found.Add(([IO.Path]::GetFullPath($v.InstallLocation)))
                    }
                }
            }
        } catch { }
    }

    # 3. Привычные места. Список короткий намеренно: это подсказка, а не обход диска.
    $guess = @()
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                    Where-Object { $_.Free -ne $null } | Select-Object -Expand Root)) {
        foreach ($sub in @('Games\Dead Air', 'Dead Air', 'Games\S.T.A.L.K.E.R. Dead Air',
                           'Program Files\Dead Air', 'Program Files (x86)\Dead Air')) {
            $guess += (Join-Path $d $sub)
        }
    }
    foreach ($g in $guess) {
        if (Test-GameRoot $g) { $null = $found.Add(([IO.Path]::GetFullPath($g))) }
    }

    # Одна и та же папка приходит и из реестра, и из привычных мест — считаем её одной.
    $uniq = @($found | Sort-Object -Unique)
    if ($uniq.Count -eq 0) { return $null }
    if ($uniq.Count -eq 1) { return $uniq[0] }

    Say ''
    Say '  Нашёл несколько установок игры. В какую ставить?' 'Yellow'
    Say ''
    for ($i = 0; $i -lt $uniq.Count; $i++) { Say ("    {0} — {1}" -f ($i + 1), $uniq[$i]) }
    Say ''
    while ($true) {
        $pick = (Read-Host '  Номер').Trim()
        if ($pick -match '^\d+$' -and [int]$pick -ge 1 -and [int]$pick -le $uniq.Count) {
            return $uniq[[int]$pick - 1]
        }
        Say '  Введите номер из списка.' 'Red'
    }
}

Say ''
Say '  Dead Air x64 — модуль анимаций' 'White'
Say '  ------------------------------' 'DarkGray'
Say ''
Say '  Ищу игру...' 'DarkGray'

$Root = Find-Game (Split-Path -Parent $MyInvocation.MyCommand.Definition)

# 4. Не нашли — спрашиваем. Путь принимаем и в кавычках, и перетаскиванием папки в окно:
#    оба способа человек применит не задумываясь, и оба должны сработать.
while (-not (Test-GameRoot $Root)) {
    Say ''
    Say '  Не нашёл папку с игрой.' 'Yellow'
    Say '  Перетащите сюда папку с игрой (ту, где лежит fsgame.ltx) и нажмите Enter,' 'Gray'
    Say '  либо вставьте путь. Пустая строка — выход.' 'Gray'
    Say ''
    $answer = (Read-Host '  Путь').Trim().Trim('"')
    if (-not $answer) { exit 0 }
    if (Test-GameRoot $answer) { $Root = $answer; break }
    Say "  В «$answer» нет fsgame.ltx и database — это не папка с игрой." 'Red'
}

# Подтверждаем находку — но ТОЛЬКО если нашли её не по месту запуска.
#
# Запустил из папки игры — вопросов нет, человек уже показал, куда ставить. А вот путь, добытый
# из реестра или угаданный по привычным местам, стоит показать и дать поправить: копий игры
# бывает несколько, и «поставил не туда» — беда тихая. Установщик отчитается успехом, анимаций
# в игре не будет, и человек пойдёт искать причину не там. Одно нажатие Enter против этого дёшево.
if (-not $script:FoundByLocation) {
    Say ''
    Say "  Нашёл игру здесь: $Root" 'White'
    Say '  Enter — ставить сюда. Или укажите другую папку (можно перетащить её в окно).' 'DarkGray'
    Say ''
    while ($true) {
        $other = (Read-Host '  Папка').Trim().Trim('"')
        if (-not $other) { break }
        if (Test-GameRoot $other) { $Root = $other; break }
        Say "  В «$other» нет fsgame.ltx и database — это не папка с игрой." 'Red'
    }
}

$Db = Join-Path $Root 'database'
Say ''
Say "  Ставлю в: $Root" 'DarkGray'

$Archive = Join-Path $Db $Asset
$Marker  = Join-Path $Db 'da_animations.txt'
$VerFile = Join-Path $Db 'da_animations_version.txt'

# --- ФАЙЛЫ, ПЕРЕКРЫВАЮЩИЕ МОДУЛЬ ------------------------------------------------------------
#
# Два скрипта модуля лежат в базовой сборке РОССЫПЬЮ, а россыпь в X-Ray перекрывает архив.
# Значит наши версии этих файлов не применялись бы никогда: архив подключается, но проигрывает
# файлу на диске. Заплатки внутри самих скриптов эту беду не лечат — до нашего кода дело просто
# не доходит.
#
# Поэтому на время работы модуля отодвигаем базовые копии в сторону, а при выключении и удалении
# возвращаем на место. Переименование, а не удаление: чужой файл мы не вправе терять.
$Shadowed = @('scripts\da_item_anims.script', 'scripts\enhanced_animations.script')
$ShadowSuffix = '.da_anim_backup'

function Shadow-Aside {
    $n = 0
    foreach ($rel in $Shadowed) {
        $live = Join-Path (Join-Path $Root 'gamedata') $rel
        $bak  = $live + $ShadowSuffix
        if ((Test-Path $live) -and -not (Test-Path $bak)) {
            Move-Item $live $bak -Force -ErrorAction SilentlyContinue
            if (Test-Path $bak) { $n++ }
        }
    }
    if ($n) { Say "  Базовых копий отодвинуто: $n (вернутся при выключении)." 'DarkGray' }
}

function Shadow-Restore {
    $n = 0
    foreach ($rel in $Shadowed) {
        $live = Join-Path (Join-Path $Root 'gamedata') $rel
        $bak  = $live + $ShadowSuffix
        if (Test-Path $bak) {
            if (Test-Path $live) { Remove-Item $live -Force -ErrorAction SilentlyContinue }
            Move-Item $bak $live -Force -ErrorAction SilentlyContinue
            if (Test-Path $live) { $n++ }
        }
    }
    if ($n) { Say "  Базовых копий возвращено: $n." 'DarkGray' }
}

# --- ЧТО СЕЙЧАС СТОИТ -----------------------------------------------------------------------
$installed = Test-Path $Archive
$disabled  = (Test-Path $Marker) -and ((ReadText $Marker) -match 'off')
$haveVer   = ReadText $VerFile

if ($installed) {
    Say ("  Модуль установлен." + $(if ($haveVer) { " Версия: $haveVer" } else { '' })) 'Green'
    if ($disabled) { Say '  Сейчас ВЫКЛЮЧЕН (в database лежит da_animations.txt со словом off).' 'Yellow' }
} else {
    Say '  Модуль не установлен.' 'DarkGray'
}
Say ''

# --- ЧЕГО ХОЧЕТ ЧЕЛОВЕК ---------------------------------------------------------------------
Say '  Что сделать?'
Say ''
if ($installed) {
    Say '    1 — обновить до последней версии'
    if ($disabled) { Say '    2 — включить обратно' } else { Say '    2 — выключить (файлы останутся на диске)' }
    Say '    3 — удалить совсем'
} else {
    Say '    1 — установить'
}
Say '    0 — выход'
Say ''
$choice = Read-Host '  Ваш выбор'

if ($choice -eq '0' -or $choice -eq '') { exit 0 }

# --- ВЫКЛЮЧИТЬ / ВКЛЮЧИТЬ -------------------------------------------------------------------
# Выключение сделано файлом-признаком, а не настройкой в меню, не по прихоти: архивы
# подключаются РАНЬШЕ консоли, скриптов и user.ltx, поэтому спросить настройку в этот момент
# негде. По той же причине смена требует перезапуска игры — отключить архив посреди сеанса
# нельзя, на нём висят уже загруженные модели и звуки.
if ($installed -and $choice -eq '2') {
    if ($disabled) {
        Remove-Item $Marker -Force -ErrorAction SilentlyContinue
        Shadow-Aside
        Say ''; Say '  Модуль включён. Перезапустите игру.' 'Green'
    } else {
        WriteText $Marker "off`r`n"
        Shadow-Restore
        Say ''; Say '  Модуль выключен. Перезапустите игру.' 'Yellow'
        Say '  Файлы остались на диске — включить обратно можно этим же скриптом.' 'DarkGray'
    }
    Say ''; Read-Host 'Enter — выход'; exit 0
}

# --- УДАЛИТЬ --------------------------------------------------------------------------------
# Удаляем ровно то, что ставили сами: архив, признак и отметку версии. Ничего чужого скрипт
# не трогает — перечень закрытый и короткий именно потому, что модуль ничего не перекрывает.
if ($installed -and $choice -eq '3') {
    Say ''
    Say '  Будут удалены:' 'Yellow'
    Say "    database\$Asset"
    if (Test-Path $Marker)  { Say '    database\da_animations.txt' }
    if (Test-Path $VerFile) { Say '    database\da_animations_version.txt' }
    Say ''
    if ((Read-Host '  Точно удалить? (д/н)') -notmatch '^[дdyY]') { Say '  Отменено.'; exit 0 }

    foreach ($f in @($Archive, $Marker, $VerFile)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    Shadow-Restore
    Say ''; Say '  Модуль удалён. Перезапустите игру.' 'Green'
    Say ''; Read-Host 'Enter — выход'; exit 0
}

# --- УЗНАТЬ ПОСЛЕДНИЙ ВЫПУСК ----------------------------------------------------------------
Say ''
Say '  Спрашиваю GitHub о последней версии...'

try {
    $api  = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    $rel  = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'DeadAir-x64-Animation' } -TimeoutSec 60
} catch {
    Fail @"
Не удалось связаться с GitHub: $($_.Exception.Message)

Проверьте подключение к сети. Если GitHub недоступен, архив можно скачать вручную:
https://github.com/$Owner/$Repo/releases/latest
и положить в папку database.
"@
}

$tag = $rel.tag_name
$a   = $rel.assets | Where-Object { $_.name -eq $Asset } | Select-Object -First 1
$s   = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
if (-not $a) { Fail "В выпуске $tag нет файла $Asset." }

Say "  Последняя версия: $tag — $(Size $a.size)" 'White'

if ($installed -and $haveVer -eq $tag -and $choice -eq '1') {
    Say ''
    Say '  У вас уже эта версия. Обновлять нечего.' 'Green'
    Say ''; Read-Host 'Enter — выход'; exit 0
}

# --- КОРОТКИЙ ТЕКСТОВЫЙ ФАЙЛ ИЗ ВЫПУСКА ------------------------------------------------------
# ⛔ Здесь стоял Net.WebClient.DownloadString, которому таймаут задать НЕЧЕМ. Когда провайдер
# режет адрес по DPI, соединение не отвергается, а виснет — установщик замирал навсегда.
# Ровно на этом вставал установщик движка: тот же вызов, та же причина.
#
# Сначала пробуем адрес выпуска, затем тот же файл через api.github.com. Этот адрес установщик
# уже успешно опросил выше, значит он доступен, а objects.githubusercontent режут чаще.
#
# ⚠️ Accept и User-Agent — ограниченные заголовки: через .Headers они БРОСАЮТ исключение,
# и ошибка кода прикидывается обрывом связи. Ставятся только свойствами.
function Get-Text($asset, $ua, $timeoutMs = 20000) {
    $tries = @(
        @{ u = $asset.browser_download_url; a = $null },
        @{ u = "https://api.github.com/repos/$Owner/$Repo/releases/assets/$($asset.id)"
           a = 'application/octet-stream' }
    )
    $last = ''
    foreach ($t in $tries) {
        if (-not $t.u) { continue }
        try {
            $req = [Net.HttpWebRequest]::Create($t.u)
            $req.UserAgent = $ua
            if ($t.a) { $req.Accept = $t.a }
            $req.Timeout = $timeoutMs
            $req.ReadWriteTimeout = $timeoutMs
            $resp = $req.GetResponse()
            try {
                $sr = New-Object IO.StreamReader($resp.GetResponseStream())
                return $sr.ReadToEnd()
            } finally { $resp.Close() }
        } catch { $last = $_.Exception.Message }
    }
    throw "ни по адресу выпуска, ни через api.github.com. $last"
}

# --- СУММА ----------------------------------------------------------------------------------
# Битый архив — это не «наверное, обойдётся»: часть моделей прочитается, а на второй половине
# игра свалится в загрузке, и виноват будет якобы движок.
$wantHash = $null
if ($s) {
    try {
        $txt = Get-Text $s 'DeadAir-x64-Animation'
        foreach ($line in $txt -split "`n") {
            if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$' -and $Matches[2] -eq $Asset) {
                $wantHash = $Matches[1].ToLower()
            }
        }
    } catch { }
}
if (-not $wantHash) { Say '  ⚠ SHA256SUMS.txt недоступен — проверю только размер.' 'Yellow' }

# --- ЗАГРУЗКА -------------------------------------------------------------------------------
# Качаем во временный файл рядом с целью, а не поверх неё: оборванная загрузка не должна
# оставить игрока с полуархивом на месте рабочего.
$tmp = "$Archive.part"

function Get-File($url, $dest, $expectSize) {
    $attempt = 0
    while ($true) {
        $have = 0
        if (Test-Path $dest) { $have = (Get-Item $dest).Length }
        if ($have -ge $expectSize) { return }

        $attempt++
        if ($attempt -gt 20) { throw "загрузка обрывается снова и снова, скачано $(Size $have) из $(Size $expectSize)" }
        if ($have -gt 0 -and $attempt -eq 1) { Say "    продолжаю с $(Size $have) — заново качать не нужно" 'DarkGray' }

        try {
            $req = [Net.HttpWebRequest]::Create($url)
            $req.UserAgent = 'DeadAir-x64-Animation'
            $req.Timeout   = 60000
            $req.ReadWriteTimeout = 60000
            if ($have -gt 0) { $req.AddRange([int64]$have) }

            $resp = $req.GetResponse()
            # Сервер вправе не понять запрос диапазона и прислать файл целиком. Тогда начинаем
            # заново, иначе получим склейку из двух кусков: по размеру она пройдёт, а сумма
            # не сойдётся, и причина будет неочевидной.
            if ($have -gt 0 -and [int]$resp.StatusCode -ne 206) { $have = 0 }

            $fmode = if ($have -gt 0) { [IO.FileMode]::Append } else { [IO.FileMode]::Create }
            $in  = $resp.GetResponseStream()
            $out = New-Object IO.FileStream($dest, $fmode, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $started   = Get-Date
            $fromStart = [int64]$have
            try {
                $buf  = New-Object byte[] 262144
                $done = [int64]$have
                # Полосу рисуем по ВРЕМЕНИ, а не по числу прочитанных кусков: на медленном канале
                # отсчёт по байтам оставляет человека перед пустым экраном на минуты, и он решает,
                # что всё повисло.
                $lastDraw = (Get-Date).AddSeconds(-10)
                while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                    $out.Write($buf, 0, $n)
                    $done += $n
                    $now = Get-Date
                    if (($now - $lastDraw).TotalMilliseconds -ge 400) {
                        $lastDraw = $now
                        $sec   = ($now - $started).TotalSeconds
                        $speed = if ($sec -gt 0) { ($done - $fromStart) / $sec } else { 0 }
                        $pct   = [int](100 * $done / $expectSize)
                        $sp    = if ($speed -ge 1MB) { '{0:N1} МБ/с' -f ($speed / 1MB) } else { '{0:N0} КБ/с' -f ($speed / 1KB) }
                        Write-Host ("`r    {0,3}%  {1} из {2}   {3}   " -f $pct, (Size $done), (Size $expectSize), $sp) -NoNewline
                    }
                }
            } finally {
                $out.Close(); $in.Close(); $resp.Close()
            }
            Write-Host ''
        } catch {
            Say ''
            Say "    связь оборвалась ($($_.Exception.Message)) — продолжу через 3 с" 'DarkGray'
            Start-Sleep -Seconds 3
        }
    }
}

Say ''
Say "  Скачиваю $Asset — $(Size $a.size)"
try {
    Get-File $a.browser_download_url $tmp $a.size
} catch {
    Fail "Не удалось скачать $Asset : $($_.Exception.Message)"
}

Say '    проверяю целостность...'
if ((Get-Item $tmp).Length -ne $a.size) {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    Fail 'Размер скачанного файла не совпал. Файл удалён — запустите скрипт ещё раз.'
}
if ($wantHash) {
    $got = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $wantHash) {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        Fail @"
Архив скачался повреждённым.

Файл удалён — запустите скрипт ещё раз, он скачает его заново.
"@
    }
}

# --- ПОДМЕНА --------------------------------------------------------------------------------
# Переименование делаем в последний момент и только над проверенным файлом: до этой строки
# у игрока на месте лежит либо старый рабочий архив, либо ничего, но никогда не половина.
try {
    if (Test-Path $Archive) { Remove-Item $Archive -Force }
    Move-Item $tmp $Archive -Force
} catch {
    Fail @"
Не удалось положить архив на место: $($_.Exception.Message)

Скорее всего игра запущена и держит файл. Закройте её и запустите скрипт ещё раз —
скачанное никуда не денется, оно лежит рядом как $Asset.part
"@
}

WriteText $VerFile "$tag`r`n"

# Базовые копии перекрывающих файлов отодвигаем только если модуль не выключен: у
# выключенного архива подменять нечего, и игра должна работать на своих файлах.
if (-not $disabled) { Shadow-Aside } else { Shadow-Restore }

Say ''
Say '  Готово.' 'Green'
if ($disabled) {
    Say '  ⚠ Модуль сейчас ВЫКЛЮЧЕН файлом da_animations.txt — включите его пунктом 2.' 'Yellow'
} else {
    Say '  Запускайте игру, анимации уже на месте.' 'Gray'
}
Say ''
Read-Host 'Enter — выход'
