$DOMINIO      = "empresa.local"
$DC_PATH      = "DC=empresa,DC=local"
$CSV_USUARIOS = "$PSScriptRoot\usuarios_p9.csv"


$ADMINS = @(
    [PSCustomObject]@{ Sam = "admin_identidad"; Nombre = "Admin"; Apellido = "Identidad"; Password = "Admin@Identidad123" },
    [PSCustomObject]@{ Sam = "admin_storage";   Nombre = "Admin"; Apellido = "Storage";   Password = "Admin@Storage123"   },
    [PSCustomObject]@{ Sam = "admin_politicas"; Nombre = "Admin"; Apellido = "Politicas"; Password = "Admin@Politicas123" },
    [PSCustomObject]@{ Sam = "admin_auditoria"; Nombre = "Admin"; Apellido = "Auditoria"; Password = "Admin@Auditoria123" }
)

function Inicializar-Entorno {
    Write-Host ""
    Write-Host "--- Inicializar Entorno ---" -ForegroundColor Yellow

    $rol = Get-WindowsFeature -Name AD-Domain-Services

    if ($rol.InstallState -ne "Installed") {
        Print-Info "Instalando rol AD-Domain-Services..."
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
        Print-Ok "Rol instalado correctamente."
    } else {
        Print-Warn "El rol AD-Domain-Services ya esta instalado. Se omite."
    }

    $domainRole = (Get-WmiObject Win32_ComputerSystem).DomainRole

    if ($domainRole -ge 4) {
        Print-Warn "Este servidor ya es Controlador de Dominio. Se omite la promocion."
        return
    }

    Print-Info "Promoviendo servidor a Controlador de Dominio..."
    Print-Info "Dominio: $DOMINIO"

    $safePass = ConvertTo-SecureString "SafeMode@Pass123!" -AsPlainText -Force

    Install-ADDSForest `
        -DomainName                    $DOMINIO `
        -DomainNetBiosName             "EMPRESA" `
        -InstallDns `
        -SafeModeAdministratorPassword $safePass `
        -Force

    Print-Warn "El servidor se reiniciara automaticamente."
    Print-Warn "Despues del reinicio ejecuta el script de nuevo y elige opcion 2."
}

function Crear-OUs {
    Print-Info "Verificando Unidades Organizativas..."

    foreach ($ou in @("Admins", "Cuates", "NoCuates")) {

        $existe = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue

        if (-not $existe) {
            New-ADOrganizationalUnit -Name $ou -Path $DC_PATH
            Print-Ok "OU creada: $ou"
        } else {
            Print-Warn "OU ya existe: $ou (se omite)"
        }
    }
}

function Crear-Admins {
    Print-Info "Verificando usuarios administradores delegados..."

    foreach ($admin in $ADMINS) {

        $existe = Get-ADUser -Filter "SamAccountName -eq '$($admin.Sam)'" -ErrorAction SilentlyContinue

        if (-not $existe) {
            $pass = ConvertTo-SecureString $admin.Password -AsPlainText -Force

            New-ADUser `
                -Name              "$($admin.Nombre) $($admin.Apellido)" `
                -GivenName         $admin.Nombre `
                -Surname           $admin.Apellido `
                -SamAccountName    $admin.Sam `
                -UserPrincipalName "$($admin.Sam)@$DOMINIO" `
                -AccountPassword   $pass `
                -Path              "OU=Admins,$DC_PATH" `
                -Enabled           $true

            Print-Ok "Admin creado : $($admin.Sam)"
            Print-Info "  Contrasena: $($admin.Password)"
        } else {
            Print-Warn "Admin ya existe: $($admin.Sam) (se omite)"
        }
    }
}

function Crear-UsuariosCSV {

    if (-not (Test-Path $CSV_USUARIOS)) {
        Print-Err "No se encontro el CSV en:"
        Print-Err "  $CSV_USUARIOS"
        Print-Info "Formato esperado: Nombre,Apellido,Usuario,OU,Contrasena"
        return
    }

    $usuarios = Import-Csv $CSV_USUARIOS
    $creados  = 0
    $omitidos = 0

    Print-Info "Leyendo CSV: $($usuarios.Count) usuario(s) encontrado(s)..."
    Write-Host ""

    foreach ($u in $usuarios) {

        if ($u.OU -notin @("Cuates", "NoCuates")) {
            Print-Warn "OU invalida '$($u.OU)' para '$($u.Usuario)'. Solo Cuates o NoCuates."
            $omitidos++
            continue
        }

        $existe = Get-ADUser -Filter "SamAccountName -eq '$($u.Usuario)'" -ErrorAction SilentlyContinue

        if (-not $existe) {
            $pass   = ConvertTo-SecureString $u.Contrasena -AsPlainText -Force
            $ouPath = "OU=$($u.OU),$DC_PATH"

            New-ADUser `
                -Name              "$($u.Nombre) $($u.Apellido)" `
                -GivenName         $u.Nombre `
                -Surname           $u.Apellido `
                -SamAccountName    $u.Usuario `
                -UserPrincipalName "$($u.Usuario)@$DOMINIO" `
                -AccountPassword   $pass `
                -Path              $ouPath `
                -Enabled           $true

            Print-Ok "Creado: $($u.Usuario) ($($u.Nombre) $($u.Apellido)) -> $($u.OU)"
            $creados++
        } else {
            Print-Warn "Ya existe: $($u.Usuario) (se omite)"
            $omitidos++
        }
    }

    Write-Host ""
    Print-Info "Resumen: $creados creado(s), $omitidos omitido(s)."
}

function Configurar-AD {
    Write-Host ""
    Write-Host "--- Configuracion de Active Directory ---" -ForegroundColor Yellow

    Crear-OUs
    Write-Host ""
    Crear-Admins
    Write-Host ""
    Crear-UsuariosCSV

    Write-Host ""
    Print-Ok "Configuracion de Active Directory completada."
    Write-Host ""
}
