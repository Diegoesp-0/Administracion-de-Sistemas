. "$PSScriptRoot\windows-funciones_http.ps1"

# Variables globales
$global:PUERTOS_RESERVADOS = @(21, 22, 23, 25, 53, 3306, 5432, 6379, 27017)
$global:IIS_WEBROOT        = "C:\inetpub\wwwroot"
$global:APACHE_WEBROOT     = "C:\Apache24\htdocs"
$global:NGINX_WEBROOT      = "C:\nginx\html"

$param = $args[0]

switch ($param) {
    { $_ -eq "-i" -or $_ -eq "--instalar"  } { Instalar-HTTP  }
    { $_ -eq "-v" -or $_ -eq "--verificar" } { Verificar-HTTP }
    { $_ -eq "-r" -or $_ -eq "--revisar"   } { Revisar-HTTP   }
    default {
        Write-Host ""
        Write-Host "  -i   Instalar servidor HTTP"
        Write-Host "  -v   Ver estado de servidores"
        Write-Host "  -r   Revisar respuesta HTTP (curl)"
        Write-Host ""
    }
}
