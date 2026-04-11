$DC_PATH = "DC=empresa,DC=local"


function Rol1-AdminIdentidad {
    Print-Info "Configurando Rol 1: admin_identidad..."

    foreach ($ou in @("Cuates", "NoCuates")) {
        $path = "OU=$ou,$DC_PATH"

        dsacls $path /G "EMPRESA\admin_identidad:CC;user" | Out-Null

        dsacls $path /G "EMPRESA\admin_identidad:DC;user" | Out-Null

        dsacls $path /G "EMPRESA\admin_identidad:WP" /I:S | Out-Null

        dsacls $path /G "EMPRESA\admin_identidad:CA;Reset Password;user" /I:S | Out-Null

        dsacls $path /G "EMPRESA\admin_identidad:WP;lockoutTime;user" /I:S | Out-Null

        Print-Ok "  Permisos aplicados en OU: $ou"
    }

    Print-Ok "Rol 1 (admin_identidad) configurado."
}


function Rol2-AdminStorage {
    Print-Info "Configurando Rol 2: admin_storage..."

    foreach ($ou in @("Cuates", "NoCuates")) {
        $path = "OU=$ou,$DC_PATH"
        dsacls $path /D "EMPRESA\admin_storage:CA;Reset Password;user" /I:S | Out-Null
        Print-Ok "  Reset Password DENEGADO en OU: $ou"
    }

    net localgroup "Opers. de servidor" "EMPRESA\admin_storage" /add 2>$null | Out-Null
    
    dsacls $DC_PATH /G "EMPRESA\admin_storage:GR" /I:S | Out-Null

    Print-Ok "Rol 2 (admin_storage) configurado."
}


function Rol3-AdminPoliticas {
    Print-Info "Configurando Rol 3: admin_politicas..."

    dsacls $DC_PATH /G "EMPRESA\admin_politicas:GR" /I:S | Out-Null

    Print-Ok "  Lectura en todo el dominio aplicada."
    Print-Ok "Rol 3 (admin_politicas) configurado."
}


function Rol4-AdminAuditoria {
    Print-Info "Configurando Rol 4: admin_auditoria..."

    dsacls $DC_PATH /G "EMPRESA\admin_auditoria:GR" /I:S | Out-Null

    net localgroup "Lectores del registro de eventos" "EMPRESA\admin_auditoria" /add 2>$null | Out-Null

    Print-Ok "  Lectura en todo el dominio aplicada."
    Print-Ok "  Acceso a logs de seguridad configurado."
    Print-Ok "Rol 4 (admin_auditoria) configurado."
}


function Configurar-Delegacion {
    Clear-Host
    Write-Host "========== Configuracion de Delegacion RBAC =========="
    Write-Host ""

    Rol1-AdminIdentidad
    Write-Host ""
    Rol2-AdminStorage
    Write-Host ""
    Rol3-AdminPoliticas
    Write-Host ""
    Rol4-AdminAuditoria

    Write-Host ""
    Print-Ok "Delegacion RBAC configurada correctamente."
    Write-Host ""
    Write-Host "Resumen:"
    Write-Host "  admin_identidad -> Cuates/NoCuates: Crear/Eliminar/Modificar/Reset/Desbloquear" -ForegroundColor White
    Write-Host "  admin_storage   -> Cuates/NoCuates: Reset Password DENEGADO + FSRM" -ForegroundColor White
    Write-Host "  admin_politicas -> Todo el dominio: Solo lectura" -ForegroundColor White
    Write-Host "  admin_auditoria -> Todo el dominio: Solo lectura + Logs de seguridad" -ForegroundColor White
    Write-Host ""
}
