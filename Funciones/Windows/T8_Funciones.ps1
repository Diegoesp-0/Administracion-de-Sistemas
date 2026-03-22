# VARIABLES GLOBALES
$script:DOMINIO       = "empresa.local"
$script:DC_PATH       = "DC=empresa,DC=local"
$script:RUTA_PERFILES = "C:\Perfiles"
$script:SHARE_NAME    = "HomeUsers"
$script:UTC_OFFSET    = -7

function Print-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green  }
function Print-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan   }
function Print-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Print-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red    }

function inicializarEntorno {
    Print-Info "Instalando roles: AD DS, FSRM, GPMC..."

    Install-WindowsFeature AD-Domain-Services, FS-Resource-Manager, GPMC `
        -IncludeManagementTools -ErrorAction Stop

    Print-Ok "Roles instalados."
    Print-Info "Promoviendo servidor a Controlador de Dominio..."

    $safePwd = ConvertTo-SecureString "SafeModeP@ss123!" -AsPlainText -Force

    Install-ADDSForest `
        -DomainName                    $script:DOMINIO `
        -DomainNetBiosName             "EMPRESA" `
        -InstallDns `
        -SafeModeAdministratorPassword $safePwd `
        -Force

    Print-Warn "El servidor se reiniciara. Ejecuta el script de nuevo despues."
}

function crearEstructuraAD {

    if (-not (Test-Path $script:RUTA_PERFILES)) {
        New-Item -Path $script:RUTA_PERFILES -ItemType Directory -Force | Out-Null
        Print-Ok "Carpeta creada: $($script:RUTA_PERFILES)"
    }

    Print-Info "Creando Unidades Organizativas..."
    foreach ($ou in @("Cuates", "NoCuates")) {
        try {
            New-ADOrganizationalUnit -Name $ou -Path $script:DC_PATH `
                -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
            Print-Ok "OU creada: $ou"
        } catch {
            Print-Warn "OU ya existe: $ou"
        }
    }

    Print-Info "Creando grupos de seguridad..."
    foreach ($grupo in @("Cuates", "NoCuates")) {
        try {
            New-ADGroup -Name $grupo `
                -GroupScope    Global `
                -GroupCategory Security `
                -Path          "OU=$grupo,$($script:DC_PATH)" `
                -ErrorAction   Stop
            Print-Ok "Grupo creado: $grupo"
        } catch {
            Print-Warn "Grupo ya existe: $grupo"
        }
    }

    Print-Info "Leyendo CSV: $($script:RUTA_CSV)"

    if (-not (Test-Path $script:RUTA_CSV)) {
        Print-Err "CSV no encontrado en: $($script:RUTA_CSV)"
        Print-Err "Asegurate de que usuarios.csv este en la misma carpeta que tarea8.ps1"
        return
    }

    $usuarios = Import-Csv $script:RUTA_CSV

    foreach ($u in $usuarios) {
        $grupoInterno = if ($u.Departamento.Trim() -eq "Cuates") { "Cuates" } else { "NoCuates" }
        $ouPath       = "OU=$grupoInterno,$($script:DC_PATH)"
        $pass         = ConvertTo-SecureString $u.Password -AsPlainText -Force

        try {
            New-ADUser `
                -Name              $u.Nombre `
                -SamAccountName    $u.Nombre `
                -UserPrincipalName "$($u.Nombre)@$($script:DOMINIO)" `
                -AccountPassword   $pass `
                -Path              $ouPath `
                -Enabled           $true `
                -ChangePasswordAtLogon $false `
                -PasswordNeverExpires  $true `
                -ErrorAction       Stop
            Print-Ok "Usuario creado: $($u.Nombre) -> $grupoInterno"
        } catch {
            Print-Warn "Usuario ya existe o error: $($u.Nombre)"
        }

        try {
            Add-ADGroupMember -Identity $grupoInterno -Members $u.Nombre -ErrorAction Stop
        } catch {
            Print-Warn "$($u.Nombre) ya esta en grupo $grupoInterno"
        }

        $rutaUser = "$($script:RUTA_PERFILES)\$($u.Nombre)"
        if (-not (Test-Path $rutaUser)) {
            New-Item -Path $rutaUser -ItemType Directory -Force | Out-Null
        }
    }

    Print-Info "Configurando recurso compartido SMB..."
    if (-not (Get-SmbShare -Name $script:SHARE_NAME -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $script:SHARE_NAME `
                     -Path $script:RUTA_PERFILES `
                     -FullAccess "Administradores" `
                     -ChangeAccess "Usuarios del dominio" `
                     -Description "Carpetas personales"
        Print-Ok "Recurso compartido \\$env:COMPUTERNAME\$($script:SHARE_NAME) creado."
    } else {
        Print-Warn "Recurso compartido ya existe."
    }

    Print-Ok "Estructura AD completa."
}

function asignarHorarios {
    param(
        [string]$Grupo,
        [int[]]$HorasLocales
    )

    $horasUTC = $HorasLocales | ForEach-Object {
        (($_ - $script:UTC_OFFSET) % 24 + 24) % 24
    }

    Print-Info "Horario '$Grupo': local=[$($HorasLocales -join ',')] -> UTC=[$($horasUTC -join ',')]"

    $bytes = [byte[]](,0x00 * 21)

    for ($dia = 0; $dia -lt 7; $dia++) {
        foreach ($hora in $horasUTC) {
            $bit     = ($dia * 24) + $hora
            $byteIdx = [Math]::Floor($bit / 8)
            $bitIdx  = $bit % 8
            $bytes[$byteIdx] = $bytes[$byteIdx] -bor (1 -shl $bitIdx)
        }
    }

    Get-ADGroupMember -Identity $Grupo |
        Where-Object { $_.objectClass -eq "user" } |
        ForEach-Object {
            Set-ADUser -Identity $_.SamAccountName -Replace @{ logonHours = $bytes }
            Print-Ok "  Horario -> $($_.SamAccountName)"
        }
}

function configurarHorarios {
    Print-Info "=== CONFIGURANDO HORARIOS ==="

    asignarHorarios -Grupo "Cuates" -HorasLocales (8..14)

    asignarHorarios -Grupo "NoCuates" -HorasLocales @(15,16,17,18,19,20,21,22,23,0,1)

    Print-Info "Creando GPO de logoff forzado..."

    $nombreGPO = "GPO-Forzar-Logoff"

    if (-not (Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue)) {
        New-GPO -Name $nombreGPO | Out-Null
        Print-Ok "GPO creada: $nombreGPO"
    } else {
        Print-Warn "GPO ya existe: $nombreGPO"
    }

    try {
        New-GPLink -Name $nombreGPO -Target $script:DC_PATH -LinkEnabled Yes -ErrorAction Stop
        Print-Ok "GPO vinculada al dominio."
    } catch {
        Print-Warn "Vinculo GPO ya existe."
    }

    Set-GPRegistryValue -Name $nombreGPO `
        -Key       "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" `
        -ValueName "EnableForcedLogOff" `
        -Type      DWord `
        -Value     1

    Print-Ok "Horarios y GPO de logoff configurados."
}

function configurarFSRM {
    Print-Info "=== CONFIGURANDO FSRM ==="

    Import-Module FileServerResourceManager -ErrorAction Stop

    $accionAviso = New-FsrmAction -Type Event -EventType Warning `
        -Body "FSRM: [Source Io Owner] alcanzo 85%% de cuota en [Quota Path]."

    $accionLimite = New-FsrmAction -Type Event -EventType Warning `
        -Body "FSRM: [Source Io Owner] supero cuota en [Quota Path]. Archivo: [Source File Path]."

    $umbral85  = New-FsrmQuotaThreshold -Percentage 85  -Action $accionAviso
    $umbral100 = New-FsrmQuotaThreshold -Percentage 100 -Action $accionLimite

    Print-Info "Creando plantillas de cuota..."
    Remove-FsrmQuotaTemplate -Name "Cuota-Cuates"   -Confirm:$false -ErrorAction SilentlyContinue
    Remove-FsrmQuotaTemplate -Name "Cuota-NoCuates"  -Confirm:$false -ErrorAction SilentlyContinue

    New-FsrmQuotaTemplate -Name "Cuota-Cuates"   -Size (10MB) -Threshold @($umbral85, $umbral100)
    Print-Ok "Plantilla: Cuota-Cuates (10 MB)"

    New-FsrmQuotaTemplate -Name "Cuota-NoCuates" -Size (5MB)  -Threshold @($umbral85, $umbral100)
    Print-Ok "Plantilla: Cuota-NoCuates (5 MB)"

    Print-Info "Aplicando cuotas por usuario..."

    Get-ADGroupMember -Identity "Cuates" | ForEach-Object {
        $ruta = "$($script:RUTA_PERFILES)\$($_.SamAccountName)"
        if (-not (Test-Path $ruta)) { New-Item -Path $ruta -ItemType Directory -Force | Out-Null }
        Remove-FsrmQuota -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmQuota -Path $ruta -Template "Cuota-Cuates"
        Print-Ok "  10MB -> $($_.SamAccountName)"
    }

    Get-ADGroupMember -Identity "NoCuates" | ForEach-Object {
        $ruta = "$($script:RUTA_PERFILES)\$($_.SamAccountName)"
        if (-not (Test-Path $ruta)) { New-Item -Path $ruta -ItemType Directory -Force | Out-Null }
        Remove-FsrmQuota -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
        New-FsrmQuota -Path $ruta -Template "Cuota-NoCuates"
        Print-Ok "  5MB -> $($_.SamAccountName)"
    }

    Print-Info "Configurando apantallamiento de archivos..."

    $accionBloqueo = New-FsrmAction -Type Event -EventType Warning `
        -Body "FSRM BLOQUEO: [Source Io Owner] intento guardar [Source File Path] en [File Screen Path]."

    Remove-FsrmFileGroup          -Name "Archivos-Prohibidos" -Confirm:$false -ErrorAction SilentlyContinue
    Remove-FsrmFileScreenTemplate -Name "Pantalla-Prohibidos" -Confirm:$false -ErrorAction SilentlyContinue

    New-FsrmFileGroup -Name "Archivos-Prohibidos" `
        -IncludePattern @("*.mp3","*.mp4","*.avi","*.mkv","*.wmv","*.exe","*.msi","*.bat","*.cmd")
    Print-Ok "Grupo de archivos prohibidos creado."

    New-FsrmFileScreenTemplate -Name "Pantalla-Prohibidos" `
        -Active `
        -IncludeGroup @("Archivos-Prohibidos") `
        -Notification $accionBloqueo
    Print-Ok "Plantilla de apantallamiento activo creada."

    foreach ($grupo in @("Cuates","NoCuates")) {
        Get-ADGroupMember -Identity $grupo | ForEach-Object {
            $ruta = "$($script:RUTA_PERFILES)\$($_.SamAccountName)"
            if (Test-Path $ruta) {
                Remove-FsrmFileScreen -Path $ruta -Confirm:$false -ErrorAction SilentlyContinue
                New-FsrmFileScreen -Path $ruta -Template "Pantalla-Prohibidos"
                Print-Ok "  Pantalla -> $($_.SamAccountName)"
            }
        }
    }

    Print-Ok "FSRM configurado."
}

function configurarAppLocker {
    Print-Info "=== CONFIGURANDO APPLOCKER ==="

    $rutaNotepad = "$env:SystemRoot\System32\notepad.exe"

    if (-not (Test-Path $rutaNotepad)) {
        Print-Err "notepad.exe no encontrado en $rutaNotepad"
        return
    }

    Print-Info "Calculando hash de notepad.exe..."
    $info   = Get-AppLockerFileInformation -Path $rutaNotepad
    $hash   = $info.Hash[0].HashDataString
    $tamano = (Get-Item $rutaNotepad).Length
    Print-Info "Hash: $hash | Tamano: $tamano bytes"

    $sidCuates   = (Get-ADGroup -Identity "Cuates").SID.Value
    $sidNoCuates = (Get-ADGroup -Identity "NoCuates").SID.Value
    $sidAdmins   = "S-1-5-32-544"
    $sidTodos    = "S-1-1-0"

    $g1 = [System.Guid]::NewGuid().ToString()
    $g2 = [System.Guid]::NewGuid().ToString()
    $g3 = [System.Guid]::NewGuid().ToString()
    $g4 = [System.Guid]::NewGuid().ToString()
    $g5 = [System.Guid]::NewGuid().ToString()

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="$g1" Name="Admins - todo permitido" Description="" UserOrGroupSid="$sidAdmins" Action="Allow">
      <Conditions><FilePathCondition Path="*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="$g5" Name="Everyone - Windows base" Description="" UserOrGroupSid="$sidTodos" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*"/></Conditions>
    </FilePathRule>
    <FilePathRule Id="$g2" Name="Cuates - notepad permitido" Description="" UserOrGroupSid="$sidCuates" Action="Allow">
      <Conditions><FilePathCondition Path="%SYSTEM32%\notepad.exe"/></Conditions>
    </FilePathRule>
    <FileHashRule Id="$g3" Name="NoCuates - notepad bloqueado por hash" Description="" UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="$hash" SourceFileName="notepad.exe" SourceFileLength="$tamano"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>
    <FilePathRule Id="$g4" Name="NoCuates - permitir Windows" Description="" UserOrGroupSid="$sidNoCuates" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*"/></Conditions>
    </FilePathRule>
  </RuleCollection>
  <RuleCollection Type="Script" EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Msi"    EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Dll"    EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Appx"   EnforcementMode="NotConfigured"/>
</AppLockerPolicy>
"@

    $rutaXML = "C:\applocker-policy.xml"
    $xml | Out-File $rutaXML -Encoding UTF8
    Print-Ok "XML guardado: $rutaXML"

    $nombreGPO = "GPO-AppLocker"

    if (-not (Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue)) {
        New-GPO -Name $nombreGPO | Out-Null
        Print-Ok "GPO creada: $nombreGPO"
    } else {
        Print-Warn "GPO ya existe: $nombreGPO"
    }

    try {
        New-GPLink -Name $nombreGPO -Target $script:DC_PATH -LinkEnabled Yes -ErrorAction Stop
        Print-Ok "GPO vinculada."
    } catch {
        Print-Warn "Vinculo GPO ya existe."
    }

    Set-GPRegistryValue -Name $nombreGPO `
        -Key "HKLM\SYSTEM\CurrentControlSet\Services\AppIDSvc" `
        -ValueName "Start" -Type DWord -Value 2

    $gpoObj   = Get-GPO -Name $nombreGPO
    $gpoId    = $gpoObj.Id.ToString().ToUpper()
    $ldapPath = "LDAP://CN={$gpoId},CN=Policies,CN=System,$($script:DC_PATH)"

    Print-Info "Aplicando politica al GPO via LDAP..."
    Set-AppLockerPolicy -XMLPolicy $rutaXML -Ldap $ldapPath -Merge
    Print-Ok "Politica AppLocker aplicada al GPO."

    Set-Service -Name AppIDSvc -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    Invoke-GPUpdate -Force -ErrorAction SilentlyContinue

    Print-Ok "AppLocker configurado. Renombrar notepad NO evita el bloqueo."
}

function unirClienteWindows {
    Print-Info "=== UNIR CLIENTE WINDOWS AL DOMINIO ==="
    Print-Warn "Ejecuta esto SOLO en el cliente Windows, NO en el servidor."

    $ipDC = Read-Host "IP del servidor DC"

    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $ipDC
    Print-Ok "DNS -> $ipDC"

    $cred = Get-Credential -Message "Credenciales de EMPRESA\Administrador"
    Add-Computer -DomainName $script:DOMINIO -Credential $cred -Restart -Force

    Print-Warn "El equipo se reiniciara."
}

function verificar {
    Write-Host ""
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host "          VERIFICACION DEL ENTORNO           " -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Yellow

    # OUs
    Print-Info "--- OUs ---"
    foreach ($ou in @("Cuates","NoCuates")) {
        $found = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue
        if ($found) { Print-Ok "OU: $ou" } else { Print-Err "OU falta: $ou" }
    }

    Print-Info "--- Grupos ---"
    foreach ($g in @("Cuates","NoCuates")) {
        $m = Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue
        if ($m) { Print-Ok "$g -> $($m.Count) miembros: $(($m | Select-Object -Expand SamAccountName) -join ', ')" }
        else    { Print-Err "$g vacio o no existe" }
    }

    Print-Info "--- SMB ---"
    if (Get-SmbShare -Name $script:SHARE_NAME -ErrorAction SilentlyContinue) {
        Print-Ok "Share '$($script:SHARE_NAME)' activo."
    } else { Print-Err "Share no encontrado." }

    Print-Info "--- Cuotas FSRM ---"
    $cuotas = Get-FsrmQuota -ErrorAction SilentlyContinue |
              Where-Object { $_.Path -like "$($script:RUTA_PERFILES)\*" }
    if ($cuotas) {
        Print-Ok "$($cuotas.Count) cuotas activas"
        foreach ($c in $cuotas) {
            $usado  = [math]::Round($c.Usage / 1MB, 2)
            $limite = [math]::Round($c.Size  / 1MB, 0)
            Print-Info "  $($c.Path) -> $usado MB / $limite MB"
        }
    } else { Print-Err "Sin cuotas." }

    Print-Info "--- Apantallamientos ---"
    $screens = Get-FsrmFileScreen -ErrorAction SilentlyContinue |
               Where-Object { $_.Path -like "$($script:RUTA_PERFILES)\*" }
    Print-Info "Apantallamientos activos: $($screens.Count)"

    Print-Info "--- Prueba de cuota (6 MB en NoCuates) ---"
    $testUser = (Get-ADGroupMember -Identity "NoCuates" | Select-Object -First 1).SamAccountName
    if ($testUser) {
        $testFile = "$($script:RUTA_PERFILES)\$testUser\test_6mb.bin"
        try {
            [System.IO.File]::WriteAllBytes($testFile, [byte[]](,0xFF * (6 * 1MB)))
            Print-Warn "ALERTA: 6 MB se escribio, cuota NO funciona para $testUser."
            Remove-Item $testFile -Force -ErrorAction SilentlyContinue
        } catch {
            Print-Ok "Cuota FUNCIONA: 6 MB BLOQUEADO en carpeta de $testUser."
        }
    }

    Print-Info "--- AppLocker ---"
    $pol = Get-AppLockerPolicy -Effective -ErrorAction SilentlyContinue
    if ($pol) { Print-Ok "Politica AppLocker cargada." }
    else      { Print-Err "Sin politica AppLocker." }

    $svc = Get-Service AppIDSvc -ErrorAction SilentlyContinue
    if ($svc.Status -eq "Running") { Print-Ok "AppIDSvc corriendo." }
    else { Print-Warn "AppIDSvc: $($svc.Status)" }

    Print-Info "--- GPOs ---"
    foreach ($gpo in @("GPO-Forzar-Logoff","GPO-AppLocker")) {
        if (Get-GPO -Name $gpo -ErrorAction SilentlyContinue) { Print-Ok "GPO: $gpo" }
        else { Print-Err "GPO falta: $gpo" }
    }

    Print-Info "--- Horarios ---"
    $utc   = [DateTime]::UtcNow
    $local = $utc.AddHours($script:UTC_OFFSET)
    Print-Info "UTC: $($utc.ToString('HH:mm')) | Sinaloa: $($local.ToString('HH:mm'))"
    Print-Info "Cuates:   08:00-15:00 local"
    Print-Info "NoCuates: 15:00-02:00 local"

    Print-Info "--- Eventos FSRM (ultima hora) ---"
    $eventos = Get-WinEvent -LogName Application -ErrorAction SilentlyContinue |
               Where-Object { $_.ProviderName -eq "SRMSVC" -and $_.TimeCreated -gt (Get-Date).AddMinutes(-60) }
    if ($eventos) {
        $eventos | Select-Object -First 10 | ForEach-Object {
            Print-Info "  [$($_.TimeCreated.ToString('HH:mm:ss'))] $($_.Message.Substring(0,[Math]::Min(120,$_.Message.Length)))"
        }
    } else { Print-Warn "Sin eventos FSRM recientes." }

    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host ""
}