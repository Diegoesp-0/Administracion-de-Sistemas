$DC_PATH = "DC=empresa,DC=local"

function Rol1-AdminIdentidad {
    Print-Info "Configurando Rol 1: admin_identidad..."

    foreach ($ou in @("Cuates", "NoCuates")) {
        $path = "OU=$ou,$DC_PATH"

        dsacls $path /G "EMPRESA\admin_identidad:CA;Reset Password;user" /I:S | Out-Null

        dsacls $path /G "EMPRESA\admin_identidad:CC;user" | Out-Null

        dsacls $path /G "EMPRESA\admin_identidad:DC;user" | Out-Null

        dsacls $path /G "EMPRESA\admin_identidad:WP" /I:S | Out-Null

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

    Print-Ok "  Lectura en todo el dominio aplicada."
    Print-Ok "Rol 4 (admin_auditoria) configurado."
}

function Configurar-Delegacion {
    Write-Host ""
    Write-Host "--- Configuracion de Delegacion RBAC ---" -ForegroundColor Yellow

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
    Print-Info "Resumen de permisos:"
    Write-Host "  admin_identidad → Cuates y NoCuates: Reset/Crear/Eliminar/Modificar usuarios" -ForegroundColor White
    Write-Host "  admin_storage   → Cuates y NoCuates: Reset Password DENEGADO" -ForegroundColor White
    Write-Host "  admin_politicas → Todo el dominio: Solo lectura" -ForegroundColor White
    Write-Host "  admin_auditoria → Todo el dominio: Solo lectura" -ForegroundColor White
    Write-Host ""
}
