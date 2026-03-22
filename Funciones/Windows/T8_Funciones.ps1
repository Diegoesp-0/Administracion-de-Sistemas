#  VARIABLES GLOBALES
$global:DOMINIO        = ""
$global:NETBIOS        = ""
$global:PASSWORD_ADMIN = "Milaneza12345@"
$global:RUTA_CSV       = "$PSScriptRoot\..\..\Tarea 8 - Gobernanza, Cuotas y Control de Aplicaciones en Active Directory\Scripts\usuarios.csv"
$global:RUTA_CARPETAS  = "C:\Usuarios"
$global:IP_SERVIDOR    = ""

#  UTILIDADES

function Escribir-Ok {
    param($msg)
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Escribir-Info {
    param($msg)
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Escribir-Error {
    param($msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

function Escribir-Titulo {
    param($msg)
    Write-Host ""
    Write-Host "===== $msg =====" -ForegroundColor Yellow
    Write-Host ""
}

function Pausar {
    Write-Host ""
    Read-Host "Presiona Enter para continuar"
}

function Verificar-Admin {
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Escribir-Error "Ejecutar como Administrador"
        exit 1
    }
}

function Obtener-IP {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notmatch "^127\." -and $_.PrefixOrigin -ne "WellKnown" } |
        Select-Object -First 1).IPAddress
    $global:IP_SERVIDOR = $ip
    return $ip
}

function Validar-Dominio {
    param([string]$dominio)
    if ($dominio -match '^[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$') {
        return $true
    }
    Escribir-Error "Formato invalido, tiene que ser como: tarea8.com"
    return $false
}

function Pedir-Dominio {
    Clear-Host
    Write-Host ""
    Escribir-Info "======== DOMINIO ========"
    Write-Host ""
    while ($true) {
        $entrada = Read-Host "Ingresa el dominio"
        $entrada = $entrada.Trim().ToLower()
        if (Validar-Dominio $entrada) {
            $netbios = ($entrada -split '\.')[0].ToUpper()
            if ($netbios.Length -gt 15) { $netbios = $netbios.Substring(0, 15) }
            $global:DOMINIO = $entrada
            $global:NETBIOS = $netbios
            Escribir-Ok "Dominio : $global:DOMINIO"
            Escribir-Ok "NetBIOS : $global:NETBIOS"
            return
        }
    }
}

function Cargar-Dominio {
    if ([string]::IsNullOrEmpty($global:DOMINIO)) {
        $ad = Get-ADDomain -ErrorAction SilentlyContinue
        if ($ad) {
            $global:DOMINIO = $ad.DNSRoot
            $global:NETBIOS = $ad.NetBIOSName
            Escribir-Info "Dominio cargado: $global:DOMINIO"
        } else {
            Escribir-Error "No se encontro ningun dominio configurado. Ejecuta primero la opcion 1."
            return $false
        }
    }
    return $true
}

#  ACTIVE DIRECTORY

function Instalar-AD {
    Clear-Host
    Escribir-Titulo "Verificando Active Directory"

    $rol = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction SilentlyContinue
    if ($rol.Installed) {
        Escribir-Ok "AD DS ya esta instalado :)"
        return
    }

    Escribir-Info "Instalando rol AD DS..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null

    $rol = Get-WindowsFeature -Name AD-Domain-Services
    if ($rol.Installed) {
        Escribir-Ok "AD DS instalado correctamente :)"
    } else {
        Escribir-Error "No se pudo instalar AD DS"
        exit 1
    }
}

function Configurar-Dominio {
    Clear-Host
    Escribir-Titulo "Configuracion del Dominio"

    $dominioActual = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
    if ($dominioActual) {
        Escribir-Ok "Ya existe un dominio: $dominioActual"
        $global:DOMINIO = $dominioActual
        $global:NETBIOS = (Get-ADDomain).NetBIOSName
        return
    }

    Pedir-Dominio

    Clear-Host
    Escribir-Titulo "Promoviendo Servidor a Domain Controller"
    Escribir-Info "Dominio : $global:DOMINIO"
    Escribir-Info "NetBIOS : $global:NETBIOS"
    Write-Host ""

    $passwordSegura = ConvertTo-SecureString $global:PASSWORD_ADMIN -AsPlainText -Force

    try {
        Install-ADDSForest `
            -DomainName $global:DOMINIO `
            -DomainNetbiosName $global:NETBIOS `
            -SafeModeAdministratorPassword $passwordSegura `
            -InstallDns `
            -Force `
            -NoRebootOnCompletion | Out-Null

        Escribir-Ok "Dominio configurado. El servidor se reiniciara automaticamente."
        Escribir-Info "Vuelve a ejecutar el script despues del reinicio para continuar."
        Start-Sleep -Seconds 5
        Restart-Computer -Force

    } catch {
        Escribir-Error "Error al configurar el dominio: $_"
        exit 1
    }
}

function Crear-OUs {
    Clear-Host
    Escribir-Titulo "Creando Unidades"

    if (-not (Cargar-Dominio)) { return }

    $base = "DC=" + ($global:DOMINIO -replace '\.', ',DC=')

    foreach ($ou in @("Cuates", "No Cuates")) {
        $existe = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue
        if ($existe) {
            Escribir-Info "OU '$ou' ya existe"
        } else {
            New-ADOrganizationalUnit -Name $ou -Path $base -ProtectedFromAccidentalDeletion $false
            Escribir-Ok "OU '$ou' creado"
        }
    }
}

function Crear-Usuarios {
    Clear-Host
    Escribir-Titulo "Creando Usuarios desde CSV"

    if (-not (Cargar-Dominio)) { return }

    if (-not (Test-Path $global:RUTA_CSV)) {
        Escribir-Error "No se encontro el archivo CSV en: $global:RUTA_CSV"
        exit 1
    }

    $base     = "DC=" + ($global:DOMINIO -replace '\.', ',DC=')
    $usuarios = Import-Csv -Path $global:RUTA_CSV

    foreach ($u in $usuarios) {
        $nombre   = $u.Nombre.Trim()
        $password = ConvertTo-SecureString $u.Password -AsPlainText -Force
        $depto    = $u.Departamento.Trim()
        $ouPath   = "OU=$depto,$base"

        $existe = Get-ADUser -Filter "SamAccountName -eq '$nombre'" -ErrorAction SilentlyContinue
        if ($existe) {
            Escribir-Info "Usuario '$nombre' ya existe"
            continue
        }

        try {
            New-ADUser `
                -Name $nombre `
                -SamAccountName $nombre `
                -UserPrincipalName "$nombre@$global:DOMINIO" `
                -Path $ouPath `
                -AccountPassword $password `
                -Department $depto `
                -Enabled $true `
                -PasswordNeverExpires $true

            $carpeta = "$global:RUTA_CARPETAS\$nombre"
            if (-not (Test-Path $carpeta)) {
                New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
            }

            $acl   = Get-Acl $carpeta
            $regla = New-Object System.Security.AccessControl.FileSystemAccessRule(
                "$global:NETBIOS\$nombre", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
            )
            $acl.SetAccessRule($regla)
            Set-Acl -Path $carpeta -AclObject $acl

            Escribir-Ok "Usuario '$nombre' creado en OU '$depto'"
        } catch {
            Escribir-Error "Error creando '$nombre': $_"
        }
    }
}

function Configurar-AD {
    Instalar-AD
    Configurar-Dominio
    Crear-OUs
    Crear-Usuarios
}

#  GPO Y HORARIOS

function Calcular-BytesHorario {
    param(
        [int]$horaInicio,
        [int]$horaFin
    )

    $bytes = New-Object byte[] 21

    for ($hora = 0; $hora -lt 168; $hora++) {
        $horaDia = $hora % 24

        $permitido = $false
        if ($horaFin -gt $horaInicio) {
            $permitido = ($horaDia -ge $horaInicio -and $horaDia -lt $horaFin)
        } else {
            $permitido = ($horaDia -ge $horaInicio -or $horaDia -lt $horaFin)
        }

        if ($permitido) {
            $byteIndex = [math]::Floor($hora / 8)
            $bitIndex  = $hora % 8
            $bytes[$byteIndex] = $bytes[$byteIndex] -bor (1 -shl $bitIndex)
        }
    }

    return $bytes
}

function Configurar-Horarios {
    Clear-Host
    Escribir-Titulo "Configurando Horarios de Acceso"

    if (-not (Cargar-Dominio)) { return }

    $bytesCuates   = Calcular-BytesHorario -horaInicio 8  -horaFin 15
    $bytesNoCuates = Calcular-BytesHorario -horaInicio 15 -horaFin 2

    $usuarios = Import-Csv -Path $global:RUTA_CSV

    foreach ($u in $usuarios) {
        $nombre = $u.Nombre.Trim()
        $depto  = $u.Departamento.Trim()

        $adUser = Get-ADUser -Filter "SamAccountName -eq '$nombre'" -ErrorAction SilentlyContinue
        if (-not $adUser) {
            Escribir-Error "Usuario '$nombre' no encontrado en AD"
            continue
        }

        if ($depto -eq "Cuates") {
            Set-ADUser -Identity $nombre -Replace @{logonHours = $bytesCuates}
            Escribir-Ok "'$nombre' - Horario Cuates (8:00 AM - 3:00 PM)"
        } else {
            Set-ADUser -Identity $nombre -Replace @{logonHours = $bytesNoCuates}
            Escribir-Ok "'$nombre' - Horario No Cuates (3:00 PM - 2:00 AM)"
        }
    }
}

function Configurar-CierreSesion {
    Clear-Host
    Escribir-Titulo "Configurando GPO de Cierre de Sesion"

    if (-not (Cargar-Dominio)) { return }

    $nombreGPO = "T8-CierreSesion"

    $gpo = Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $nombreGPO
        Escribir-Ok "GPO '$nombreGPO' creada"
    } else {
        Escribir-Info "GPO '$nombreGPO' ya existe, actualizando"
    }

    Set-GPRegistryValue `
        -Name $nombreGPO `
        -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" `
        -ValueName "EnableForcedLogOff" `
        -Type DWord `
        -Value 1 | Out-Null

    $base = "DC=" + ($global:DOMINIO -replace '\.', ',DC=')
    try {
        New-GPLink -Name $nombreGPO -Target $base -ErrorAction SilentlyContinue | Out-Null
        Escribir-Ok "GPO vinculada al dominio '$global:DOMINIO'"
    } catch {
        Escribir-Info "El vinculo ya existia o no se pudo crear: $_"
    }

    Invoke-GPUpdate -Force -ErrorAction SilentlyContinue | Out-Null
    Escribir-Ok "Politicas actualizadas"
}

function Configurar-GPO {
    Configurar-Horarios
    Configurar-CierreSesion
}

#  FSRM

function Instalar-FSRM {
    Clear-Host
    Escribir-Titulo "Verificando FSRM"

    $rol = Get-WindowsFeature -Name FS-Resource-Manager -ErrorAction SilentlyContinue
    if ($rol.Installed) {
        Escribir-Ok "FSRM ya esta instalado :)"
        return
    }

    Escribir-Info "Instalando FSRM..."
    Install-WindowsFeature -Name FS-Resource-Manager -IncludeManagementTools | Out-Null

    $rol = Get-WindowsFeature -Name FS-Resource-Manager
    if ($rol.Installed) {
        Escribir-Ok "FSRM instalado correctamente :)"
    } else {
        Escribir-Error "No se pudo instalar FSRM :("
        exit 1
    }
}

function Configurar-Cuotas {
    Clear-Host
    Escribir-Titulo "Configurando Cuotas de Disco"

    Import-Module FileServerResourceManager -ErrorAction SilentlyContinue

    $plantilla5MB  = "T8-Cuota-5MB"
    $plantilla10MB = "T8-Cuota-10MB"

    $existe5 = Get-FsrmQuotaTemplate -Name $plantilla5MB -ErrorAction SilentlyContinue
    if (-not $existe5) {
        New-FsrmQuotaTemplate -Name $plantilla5MB -Size 5MB | Out-Null
        Escribir-Ok "Plantilla '$plantilla5MB' creada"
    } else {
        Escribir-Info "Plantilla '$plantilla5MB' ya existe"
    }

    $existe10 = Get-FsrmQuotaTemplate -Name $plantilla10MB -ErrorAction SilentlyContinue
    if (-not $existe10) {
        New-FsrmQuotaTemplate -Name $plantilla10MB -Size 10MB | Out-Null
        Escribir-Ok "Plantilla '$plantilla10MB' creada"
    } else {
        Escribir-Info "Plantilla '$plantilla10MB' ya existe"
    }

    $usuarios = Import-Csv -Path $global:RUTA_CSV

    foreach ($u in $usuarios) {
        $nombre  = $u.Nombre.Trim()
        $depto   = $u.Departamento.Trim()
        $carpeta = "$global:RUTA_CARPETAS\$nombre"

        if (-not (Test-Path $carpeta)) {
            Escribir-Error "Carpeta '$carpeta' no existe. Crea los usuarios primero"
            continue
        }

        Remove-FsrmQuota -Path $carpeta -Confirm:$false -ErrorAction SilentlyContinue

        if ($depto -eq "Cuates") {
            New-FsrmQuota -Path $carpeta -Template $plantilla10MB | Out-Null
            Escribir-Ok "'$nombre' - Cuota 10 MB (Cuates)"
        } else {
            New-FsrmQuota -Path $carpeta -Template $plantilla5MB | Out-Null
            Escribir-Ok "'$nombre' - Cuota 5 MB (No Cuates)"
        }
    }
}

function Configurar-Apantallamiento {
    Clear-Host
    Escribir-Titulo "Configurando Apantallamiento de Archivos"

    Import-Module FileServerResourceManager -ErrorAction SilentlyContinue

    $nombreGrupo = "T8-ArchivosProhibidos"

    $existeGrupo = Get-FsrmFileGroup -Name $nombreGrupo -ErrorAction SilentlyContinue
    if (-not $existeGrupo) {
        New-FsrmFileGroup `
            -Name $nombreGrupo `
            -IncludePattern @("*.mp3", "*.mp4", "*.exe", "*.msi") | Out-Null
        Escribir-Ok "Grupo '$nombreGrupo' creado con: *.mp3, *.mp4, *.exe, *.msi"
    } else {
        Set-FsrmFileGroup `
            -Name $nombreGrupo `
            -IncludePattern @("*.mp3", "*.mp4", "*.exe", "*.msi") | Out-Null
        Escribir-Info "Grupo '$nombreGrupo' actualizado"
    }

    $usuarios = Import-Csv -Path $global:RUTA_CSV

    foreach ($u in $usuarios) {
        $nombre  = $u.Nombre.Trim()
        $carpeta = "$global:RUTA_CARPETAS\$nombre"

        if (-not (Test-Path $carpeta)) {
            Escribir-Error "Carpeta '$carpeta' no existe. Crea los usuarios primero"
            continue
        }

        Remove-FsrmFileScreen -Path $carpeta -Confirm:$false -ErrorAction SilentlyContinue

        New-FsrmFileScreen `
            -Path $carpeta `
            -IncludeGroup @($nombreGrupo) `
            -Active | Out-Null

        Escribir-Ok "'$nombre' - Apantallamiento activo aplicado"
    }
}

function Configurar-FSRM {
    Instalar-FSRM
    Configurar-Cuotas
    Configurar-Apantallamiento
}

#  APPLOCKER

function Instalar-Dependencias-AppLocker {
    Escribir-Info "Verificando servicio de AppLocker (AppIDSvc)..."
    $svc = Get-Service -Name AppIDSvc -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name AppIDSvc -StartupType Automatic
        Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue
        Escribir-Ok "Servicio AppIDSvc activo"
    } else {
        Escribir-Error "Servicio AppIDSvc no encontrado. AppLocker podria no funcionar"
    }
}

function Obtener-Hash-Notepad {
    $rutaNotepad = "$env:SystemRoot\System32\notepad.exe"
    if (-not (Test-Path $rutaNotepad)) {
        Escribir-Error "No se encontro notepad.exe en $rutaNotepad"
        return $null
    }
    $info = Get-AppLockerFileInformation -Path $rutaNotepad
    return $info
}

function Configurar-AppLocker {
    Clear-Host
    Escribir-Titulo "Configurando AppLocker"

    if (-not (Cargar-Dominio)) { return }

    Instalar-Dependencias-AppLocker

    $infoNotepad = Obtener-Hash-Notepad
    if (-not $infoNotepad) {
        Escribir-Error "No se pudo obtener informacion de notepad.exe"
        return
    }

    $rutaNotepad = "$env:SystemRoot\System32\notepad.exe"
    $hash        = (Get-FileHash -Path $rutaNotepad -Algorithm SHA256).Hash
    $hashFormato = "0x" + $hash

    $sidCuates   = (Get-ADGroup -Filter "Name -eq 'Cuates'"    -ErrorAction SilentlyContinue).SID.Value
    $sidNoCuates = (Get-ADGroup -Filter "Name -eq 'No Cuates'" -ErrorAction SilentlyContinue).SID.Value

    if (-not $sidCuates -or -not $sidNoCuates) {
        Clear-Host
        Escribir-Titulo "Creando Grupos de Seguridad"

        $base = "DC=" + ($global:DOMINIO -replace '\.', ',DC=')

        if (-not (Get-ADGroup -Filter "Name -eq 'Cuates'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name "Cuates" -GroupScope Global -Path "OU=Cuates,$base" | Out-Null
            Escribir-Ok "Grupo 'Cuates' creado"
        }
        if (-not (Get-ADGroup -Filter "Name -eq 'No Cuates'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name "No Cuates" -GroupScope Global -Path "OU=No Cuates,$base" | Out-Null
            Escribir-Ok "Grupo 'No Cuates' creado"
        }

        $usuarios = Import-Csv -Path $global:RUTA_CSV
        foreach ($u in $usuarios) {
            $nombre = $u.Nombre.Trim()
            $depto  = $u.Departamento.Trim()
            Add-ADGroupMember -Identity $depto -Members $nombre -ErrorAction SilentlyContinue
        }
        Escribir-Ok "Usuarios agregados a sus grupos"

        $sidCuates   = (Get-ADGroup -Filter "Name -eq 'Cuates'"    ).SID.Value
        $sidNoCuates = (Get-ADGroup -Filter "Name -eq 'No Cuates'" ).SID.Value
    }

    $xmlPolicy = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <!-- Regla base: administradores pueden ejecutar todo -->
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2"
                  Name="Todos los archivos en Windows"
                  Description="Permite ejecutar archivos del sistema"
                  UserOrGroupSid="S-1-5-32-544"
                  Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*" />
      </Conditions>
    </FilePathRule>

    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20"
                  Name="Todos los archivos en Archivos de programa"
                  Description="Permite ejecutar archivos de programa"
                  UserOrGroupSid="S-1-5-32-544"
                  Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*" />
      </Conditions>
    </FilePathRule>

    <!-- Cuates: PERMITIDO ejecutar Bloc de Notas por ruta -->
    <FilePathRule Id="a61c8b2c-1111-2222-3333-000000000001"
                  Name="Cuates - Permitir Bloc de Notas"
                  Description="El grupo Cuates puede ejecutar notepad.exe"
                  UserOrGroupSid="$sidCuates"
                  Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\System32\notepad.exe" />
      </Conditions>
    </FilePathRule>

    <!-- No Cuates: BLOQUEADO por Hash (no se puede evadir renombrando) -->
    <FileHashRule Id="a61c8b2c-1111-2222-3333-000000000002"
                  Name="No Cuates - Bloquear Bloc de Notas por Hash"
                  Description="Bloquea notepad.exe por su hash SHA256"
                  UserOrGroupSid="$sidNoCuates"
                  Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256"
                    Data="$hashFormato"
                    SourceFileName="notepad.exe"
                    SourceFileLength="0" />
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

  </RuleCollection>
</AppLockerPolicy>
"@

    $rutaXML = "$env:TEMP\T8_AppLocker.xml"
    $xmlPolicy | Out-File -FilePath $rutaXML -Encoding UTF8 -Force

    try {
        Set-AppLockerPolicy -XmlPolicy $rutaXML -Merge
        Escribir-Ok "Politica AppLocker aplicada"
        Escribir-Ok "Cuates    -> Bloc de Notas PERMITIDO"
        Escribir-Ok "No Cuates -> Bloc de Notas BLOQUEADO por hash"
    } catch {
        Escribir-Error "Error al aplicar politica AppLocker: $_"
    }

    gpupdate /force 2>&1 | Out-Null
    Escribir-Ok "Politicas de grupo actualizadas"
}

#  INFORMACION DEL SERVIDOR

function Mostrar-Info {
    Clear-Host
    Escribir-Titulo "Informacion del Servidor"

    $ip = Obtener-IP
    Write-Host "  IP del Servidor   : $ip"

    $dominioActual = (Get-ADDomain -ErrorAction SilentlyContinue).DNSRoot
    if ($dominioActual) {
        Write-Host "  Dominio           : $dominioActual"
        Write-Host "  NetBIOS           : $((Get-ADDomain).NetBIOSName)"
    } else {
        Write-Host "  Dominio           : No configurado"
    }

    Write-Host ""
    Write-Host "  --- Roles instalados ---"
    $roles = @("AD-Domain-Services", "FS-Resource-Manager", "GPMC")
    foreach ($rol in $roles) {
        $r      = Get-WindowsFeature -Name $rol -ErrorAction SilentlyContinue
        $estado = if ($r.Installed) { "Instalado" } else { "No instalado" }
        Write-Host "  $rol : $estado"
    }

    Write-Host ""
    Write-Host "  --- Usuarios en AD ---"
    $usuariosAD = Get-ADUser -Filter * -Properties Department -ErrorAction SilentlyContinue
    if ($usuariosAD) {
        foreach ($u in $usuariosAD) {
            if ($u.SamAccountName -ne "Administrator" -and
                $u.SamAccountName -ne "Guest"         -and
                $u.SamAccountName -ne "krbtgt") {
                Write-Host "  $($u.SamAccountName) -> $($u.Department)"
            }
        }
    } else {
        Write-Host "  No hay usuarios creados aun"
    }

    Write-Host ""
    Pausar
}
