#Глобальные переменные
[string]$Global:Disk = "E:"					    #Диск для бэкапа
[int]$Global:minSpace = 2				      	#минимальный объем свободного места на диске, в зависимости от того, сколько занимает места бэкап, в Гб
[string]$Global:folderName = "1Cbackup"	#имя папки, куда будет литься бэкап, в ней же будут чиститься предыдущие бэкапы. 
[string]$Global:logName = ""				    #Объявление переменной имени лога
[string]$Global:logOutput = ""				  #логирование в эту строку
$Global:maxTime = 2700			 			      #Максимальное время ожидания окончания процесса 1С, в секундах

#Команды и параметры запуска к ним
[string]$Global:backupApp = "C:\Program Files (x86)\1cv8\common\1cestart.exe"
[string]$Global:param01 = 'ENTERPRISE /F"C:\dBase" /N"Name" /P"pass" /CЗавершитьРаботуПользователей'
[string]$Global:param02 = 'DESIGNER /F"C:\dBase" /N"Name" /P"pass" /DumpIBname_dt /UC"КодРазрешения"'
[string]$Global:param03 = 'ENTERPRISE  /F"C:\dBase" /N"Name" /P"pass" /CРазрешитьРаботуПользователей /UC"КодРазрешения"'

function getTime
{
    [string]$curTime = Get-Date -Format u
    $curTime = $curTime.TrimEnd("Z")
    return $curTime
}

function writeLog([string]$inputStr)
{
    #пишем в Global потому-что иначе писать будет в переменную ВНУТРИ ф-ии
    $Global:logOutput += getTime
    $Global:logOutput += "`t$inputStr`r`n"
    $Global:logOutput | Out-File $logName
    Write-Host "$inputStr`r`n"
}

function isFreeSpace
{
    $get_disk_info = Get-WMIObject Win32_LogicalDisk | ?{$_.deviceid -eq $Disk}
    [int]$freeSp =  [math]::Truncate($get_disk_info.FreeSpace/1gb)
    if ($freeSp -gt $minSpace) { return $true }
    elseif ($freeSp -le $minSpace) { return $false }
    else 
    {
            writeLog "Возникла непредвиденная ошибка в ф-ии isFreeSpace:`r`n`t`t`tget_disk_info=$get_disk_info`r`n`t`t`tfreeSp=$freeSp`r`n`t`t`t`minSpace=$minSpace"
            exit 
    }
}

function procStart ($prog, $param)
{
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $prog
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $param
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    writeLog "Имя запускаемого файла: $prog"
    #writeLog "Строка параметров: $param"				#отключено, чтобы не "палить" учетные данные в логе
    $p.Start() | Out-Null
    $p.WaitForExit()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    Write-Host $stdout
    Write-Host $stderr
    [string]$exitCode=$p.ExitCode
    [boolean]$isRunning = $True
    [int]$tickTime = 0
    while ($isRunning) 
    {
        if (get-process 1cv8 -ErrorAction SilentlyContinue) 
        { 
            $isRunning = $True 
            Start-Sleep -s 10
            $tickTime += 10
            if ($tickTime -ge $Global:maxTime) 
            {
                writeLog "Время ожидания окончания истекло"
                Stop-Process -processname 1cv8
                exit 
            } 
        }
        else { $isRunning = $False }
    }
	writeLog "Выполнение завершено с кодом: $exitCode`r`n"
}

#Блок архивирования. 
function justDoIt					
{
    $fullPath = $Disk + "\" + $folderName
    #Проверка/очистка свободного места
    [boolean]$isFreeSpaceVal = isFreeSpace
    $isRemoved = $True
    while (-not $isFreeSpaceVal -and $isRemoved)
    {
        $oldChild = Get-ChildItem $fullPath | Sort-Object -property CreationTime | select-object -first 1 | SELECT Name
        [string]$pathToRemove = $fullPath + "\" + $oldChild.Name
        writeLog "Удаляется папка $pathToRemove"
        Remove-Item $pathToRemove -Recurse
        $isRemoved = test-path $pathToRemove				#Проверяем, было ли произведено удаление
        $isFreeSpaceVal = isFreeSpace
        if (-not $isRemoved) {
            writeLog "Не удалось осободить место"
            exit }
    }
    $fileOutName = getTime
    $fileOutName = $fileOutName.Replace(":","-")
    $fileOutName = $fileOutName.Replace(" ","_")
    $fileOutName += ".dt"
    $tmp = $Disk + "\" + $folderName + "\"
    $fileOutName = $fileOutName.Insert(0, $tmp)
    writeLog "Название создаваемого архива: $fileOutName`r`n"
    
    $Global:param02=$Global:param02.Replace("name_dt",$fileOutName)	#меняем название бэкапа на текущую дату и время
    procStart $Global:backupApp $Global:param01 
    procStart $Global:backupApp $Global:param02
    procStart $Global:backupApp $Global:param03
}

#Создание имени лог-файла
[string]$tmp = Get-Location
$tmp += "\"
$logName = getTime
$logName = $logName.Replace(":","-")
$logName = $logName.Replace(" ","_")
$logName += ".log"
$logName = $logName.Insert(0, $tmp)
#Немного информации в лог
writeLog "Начало работы скрипта`r`n"
writeLog "Disk = $Disk"
writeLog "minSpace = $minSpace"
writeLog "folderName = $folderName"
writeLog "Лог-файл = $logName`r`n"
[boolean]$findApp = Test-Path $backupApp
if (-not $findApp) 
{
    writeLog "Приложение на найдено: $backupApp"
    exit 
}

[boolean]$findDrive=test-path $Disk
if (-not $findDrive) 
{
    writeLog "Скрипт остановлен: отсутствует диск $Disk"
    exit 
}

#проверяем свободное место, если его нет, чистим старые бэкапы
[boolean]$isFreeSpaceVal = isFreeSpace
[boolean]$isRemoved = $True
$fullPath = $Disk + "\" + $folderName
#Проверяем/создаем папку для бэкапа
writeLog "Проверяем, есть ли папка $folderName"
[boolean]$findFolder = Test-Path $fullPath
if (-not $findFolder) 
{
    writeLog "Папка не найдена. Создание..."
    mkdir $fullPath
    $findFolder = Test-Path $fullPath
    if (-not $findFolder)
    {
        writeLog "Папка не была создана. Скрипт остановлен."
        exit 
    }
    elseif ($findFolder) 
    {
        writeLog "Папка $fullPath присутствует."
        writeLog "Выполнение команды резервного копирования."
        justDoIt 
    }
    else 
    {
            writeLog "Случилось что-то непредвиденное на этапе проверки папки для архивирования. Скрипт остановлен"
            exit 
    }
}
elseif ($findFolder) 
{
    writeLog "Папка $fullPath присутствует."
    writeLog "Выполнение команды резервного копирования."
    justDoIt 
}
else 
{
        writeLog "Случилось что-то непредвиденное на этапе проверки папки для архивирования. Скрипт остановлен"
        exit 
}
writeLog "Скрипт достиг конца."
exit
