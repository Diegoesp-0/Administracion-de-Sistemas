$global:VERSION_ELEGIDA = ""
$global:PUERTO_ELEGIDO  = 80

# =============== MENSAJES ===============
function Write-Ok    { param($msg) Write-Host "[OK] $msg" }
function Write-Info  { param($msg) Write-Host "[INFO] $msg" }
function Write-Err   { param($msg) Write-Host "[ERROR] $msg" }
function Write-Title { param($msg) Write-Host "`n==== $msg ====`n" }

# =============== CHOCOLATEY ===============
function Asegurar-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = `
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1')) *>&1 | Out-Null
        $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
        Write-Ok "Chocolatey instalado."
    } else {
        Write-Info "Chocolatey: ok."
    }
}

# =============== REFRESCAR PATH ===============
function Refrescar-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH","User")
}

# =============== BUSCAR RUTA NGINX ===============
function Obtener-Ruta-Nginx {
    # Busca en C:\tools primero (choco instala como nginx-VERSION)
    $exe = Get-ChildItem "C:\tools" -Filter "nginx.exe" -Recurse `
        -ErrorAction SilentlyContinue -Depth 3 | Select-Object -First 1
    if ($exe) { return $exe.DirectoryName }

    # Rutas alternativas fijas
    foreach ($r in @("C:\nginx","C:\ProgramData\chocolatey\lib\nginx\tools\nginx")) {
        if (Test-Path "$r\nginx.exe") { return $r }
    }

    # Busqueda general
    $exe = Get-ChildItem "C:\" -Filter "nginx.exe" -Recurse `
        -ErrorAction SilentlyContinue -Depth 5 | Select-Object -First 1
    if ($exe) { return $exe.DirectoryName }

    return $null
}

# =============== BUSCAR RUTA APACHE ===============
function Obtener-Ruta-Apache {
    $conf = Get-ChildItem "C:\tools","C:\Apache24","C:\Apache2" -Filter "httpd.conf" `
        -Recurse -ErrorAction SilentlyContinue -Depth 5 | Select-Object -First 1
    if ($conf) { return $conf.DirectoryName }

    $conf = Get-ChildItem "C:\" -Filter "httpd.conf" -Recurse `
        -ErrorAction SilentlyContinue -Depth 6 | Select-Object -First 1
    if ($conf) { return $conf.DirectoryName }

    return $null
}

# =============== OBTENER VERSIONES ===============
function Obtener-Versiones-Choco {
    param([string]$paquete)

    Asegurar-Chocolatey

    $versiones = choco search $paquete --exact --all-versions --limit-output 2>$null `
        | ForEach-Object { ($_ -split '\|')[1] } `
        | Where-Object   { $_ -match '^\d+\.\d+' } `
        | Sort-Object    { [version]($_ -replace '[^0-9.]','') } `
        | Select-Object  -Unique

    return $versiones
}

function Obtener-Versiones-IIS {
    $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" `
        -ErrorAction SilentlyContinue).VersionString
    if ($ver) { return @($ver) }
    return @("10.0")
}

# =============== ELEGIR VERSION ===============
function Elegir-Version {
    param([string]$servidor, [string[]]$versiones)

    Clear-Host

    if ($versiones.Count -eq 0) {
        Write-Err "No se encontraron versiones para '$servidor'."
        return $false
    }

    Write-Host ""
    Write-Host "=== Versiones disponibles: $servidor ==="
    Write-Host ""

    for ($i = 0; $i -lt $versiones.Count; $i++) {
        $etiqueta = ""
        if ($i -eq 0)                    { $etiqueta = "  [LTS / Estable]" }
        if ($i -eq $versiones.Count - 1) { $etiqueta = "  [Latest / Desarrollo]" }
        Write-Host "  [$($i+1)] $($versiones[$i])$etiqueta"
    }
    Write-Host ""

    while ($true) {
        $sel = Read-Host "Elige una version [1-$($versiones.Count)]"
        $sel = $sel -replace '[^0-9]',''
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $versiones.Count) {
            $global:VERSION_ELEGIDA = $versiones[[int]$sel - 1]
            Write-Ok "Version elegida: $global:VERSION_ELEGIDA"
            return $true
        }
        Write-Err "Opcion invalida."
    }
}

# =============== VALIDAR PUERTO ===============
function Validar-Puerto {
    param([int]$puerto)

    if ($puerto -lt 1 -or $puerto -gt 65535) {
        Write-Err "El puerto debe estar entre 1 y 65535."
        return $false
    }

    foreach ($r in $global:PUERTOS_RESERVADOS) {
        if ($puerto -eq $r) {
            Write-Err "Puerto $puerto reservado para otro servicio."
            return $false
        }
    }

    $cx = Test-NetConnection -ComputerName localhost -Port $puerto `
        -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($cx.TcpTestSucceeded) {
        Write-Err "El puerto $puerto ya esta en uso."
        return $false
    }

    return $true
}

# =============== PEDIR PUERTO ===============
function Pedir-Puerto {
    Clear-Host
    Write-Host ""
    Write-Host "=== Configuracion de Puerto ==="
    Write-Host ""
    Write-Info "Puerto por defecto : 80"
    Write-Info "Otros comunes      : 8080, 8888"
    Write-Info "Bloqueados         : $($global:PUERTOS_RESERVADOS -join ', ')"
    Write-Host ""

    while ($true) {
        $input = Read-Host "Ingresa el puerto [Enter = 80]"
        if ([string]::IsNullOrWhiteSpace($input)) { $input = "80" }
        $input = $input -replace '[^0-9]',''
        if ([string]::IsNullOrWhiteSpace($input)) { Write-Err "Ingresa un numero."; continue }

        $puerto = [int]$input
        if (Validar-Puerto $puerto) {
            $global:PUERTO_ELEGIDO = $puerto
            Write-Ok "Puerto $puerto aceptado."
            Start-Sleep -Seconds 1
            break
        }
    }
}

# =============== FIREWALL ===============
function Abrir-Puerto-Firewall {
    param([int]$puerto, [string]$nombre)
    $existe = Get-NetFirewallRule -DisplayName "HTTP-$nombre-$puerto" -ErrorAction SilentlyContinue
    if (-not $existe) {
        New-NetFirewallRule -DisplayName "HTTP-$nombre-$puerto" `
            -Direction Inbound -Protocol TCP -LocalPort $puerto `
            -Action Allow -Profile Any | Out-Null
        Write-Ok "Firewall: puerto $puerto abierto."
    } else {
        Write-Info "Firewall: regla para puerto $puerto ya existe."
    }
}

# =============== INSTALAR IIS ===============
function Instalar-IIS {
    Write-Title "Instalando IIS..."

    $features = @(
        "Web-Server","Web-Common-Http","Web-Static-Content",
        "Web-Default-Doc","Web-Http-Errors","Web-Security",
        "Web-Filtering","Web-Http-Logging","Web-Stat-Compression"
    )
    foreach ($f in $features) {
        Install-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Ok "IIS instalado."

    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    & $appcmd set site "Default Web Site" /bindings:"http/*:$($global:PUERTO_ELEGIDO):" 2>&1 | Out-Null
    Write-Ok "Puerto configurado -> $global:PUERTO_ELEGIDO"

    Set-Content -Path "$global:IIS_WEBROOT\web.config" -Encoding UTF8 -Value @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <security>
      <requestFiltering removeServerHeader="true">
        <verbs>
          <add verb="TRACE" allowed="false" />
          <add verb="DELETE" allowed="false" />
        </verbs>
      </requestFiltering>
    </security>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
    Write-Ok "Seguridad configurada."

    Set-Content -Path "$global:IIS_WEBROOT\index.html" -Encoding UTF8 -Value @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>IIS</title></head>
<body>
<h1>Servidor: IIS</h1>
<p>Version: $($global:VERSION_ELEGIDA)</p>
<p>Puerto: $($global:PUERTO_ELEGIDO)</p>
</body>
</html>
"@
    Write-Ok "index.html creado."

    $acl  = Get-Acl $global:IIS_WEBROOT
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IIS_IUSRS","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $global:IIS_WEBROOT $acl
    Write-Ok "Permisos aplicados -> IIS_IUSRS."

    Abrir-Puerto-Firewall $global:PUERTO_ELEGIDO "IIS"

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Set-Service   W3SVC -StartupType Automatic
    Start-Sleep -Seconds 2

    if ((Get-Service W3SVC -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Ok "IIS activo en puerto $global:PUERTO_ELEGIDO"
    } else {
        Write-Err "IIS no arranco. Revisa el Visor de Eventos."
    }
}

# =============== INSTALAR APACHE WINDOWS ===============
function Instalar-Apache-Win {
    Write-Title "Instalando Apache2 (Windows)..."

    Asegurar-Chocolatey
    Write-Info "Instalando Apache $global:VERSION_ELEGIDA via Chocolatey..."
    choco install apache-httpd --version=$global:VERSION_ELEGIDA -y --no-progress 2>&1 | Out-Null
    Refrescar-Path
    Write-Ok "Apache instalado."

    $confDir = Obtener-Ruta-Apache
    if (-not $confDir) {
        Write-Err "No se encontro httpd.conf tras la instalacion."
        return
    }

    $httpdConf  = "$confDir\httpd.conf"
    $apacheRoot = Split-Path $confDir -Parent

    $contenido = Get-Content $httpdConf -Raw
    $contenido = $contenido -replace 'Listen 80', "Listen $global:PUERTO_ELEGIDO"
    $contenido += @"

ServerTokens Prod
ServerSignature Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</IfModule>

<LimitExcept GET POST HEAD OPTIONS>
    Require all denied
</LimitExcept>
"@
    Set-Content $httpdConf $contenido -Encoding UTF8
    Write-Ok "Puerto y seguridad configurados."

    $htmlDir = "$apacheRoot\htdocs"
    New-Item -ItemType Directory -Force -Path $htmlDir | Out-Null
    Set-Content -Path "$htmlDir\index.html" -Encoding UTF8 -Value @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>Apache2</title></head>
<body>
<h1>Servidor: Apache2</h1>
<p>Version: $($global:VERSION_ELEGIDA)</p>
<p>Puerto: $($global:PUERTO_ELEGIDO)</p>
</body>
</html>
"@
    Write-Ok "index.html creado."

    Abrir-Puerto-Firewall $global:PUERTO_ELEGIDO "Apache"

    $httpdExe = "$apacheRoot\bin\httpd.exe"
    if (Test-Path $httpdExe) {
        & $httpdExe -k install 2>&1 | Out-Null
        Start-Service Apache2.4 -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if ((Get-Service Apache2.4 -ErrorAction SilentlyContinue).Status -eq "Running") {
            Write-Ok "Apache activo en puerto $global:PUERTO_ELEGIDO"
        } else {
            Write-Err "Apache no arranco. Revisa $apacheRoot\logs\error.log"
        }
    } else {
        Write-Err "No se encontro httpd.exe en $apacheRoot\bin"
    }
}

# =============== INSTALAR NGINX WINDOWS ===============
function Instalar-Nginx-Win {
    Write-Title "Instalando Nginx (Windows)..."

    Asegurar-Chocolatey
    Write-Info "Instalando Nginx $global:VERSION_ELEGIDA via Chocolatey..."
    choco install nginx --version=$global:VERSION_ELEGIDA -y --no-progress 2>&1 | Out-Null
    Refrescar-Path
    Write-Ok "Nginx instalado."

    $nginxRoot = Obtener-Ruta-Nginx
    if (-not $nginxRoot) {
        Write-Err "No se encontro nginx.exe tras la instalacion."
        return
    }
    Write-Info "Nginx en: $nginxRoot"

    $nginxConf = "$nginxRoot\conf\nginx.conf"
    if (Test-Path $nginxConf) {
        $contenido = Get-Content $nginxConf -Raw
        $contenido = $contenido -replace 'listen\s+80;', "listen $global:PUERTO_ELEGIDO;"
        # Insertar server_tokens y headers despues de "http {"
        $contenido = $contenido -replace '(http\s*\{)', @"
`$1
    server_tokens off;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
"@
        Set-Content $nginxConf $contenido -Encoding UTF8
        Write-Ok "Puerto y seguridad configurados."
    } else {
        Write-Err "No se encontro nginx.conf"
    }

    # Sobreescribir index.html por defecto
    $htmlDir = "$nginxRoot\html"
    New-Item -ItemType Directory -Force -Path $htmlDir | Out-Null
    Set-Content -Path "$htmlDir\index.html" -Encoding UTF8 -Force -Value @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>Nginx</title></head>
<body>
<h1>Servidor: Nginx</h1>
<p>Version: $($global:VERSION_ELEGIDA)</p>
<p>Puerto: $($global:PUERTO_ELEGIDO)</p>
</body>
</html>
"@
    Write-Ok "index.html creado."

    Abrir-Puerto-Firewall $global:PUERTO_ELEGIDO "Nginx"

    # Registrar como servicio con NSSM
    if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando NSSM..."
        choco install nssm -y --no-progress 2>&1 | Out-Null
        Refrescar-Path
    }

    $svcExiste = Get-Service nginx -ErrorAction SilentlyContinue
    if ($svcExiste) {
        Stop-Service nginx -Force -ErrorAction SilentlyContinue
        & nssm remove nginx confirm 2>&1 | Out-Null
    }

    $nginxExe = "$nginxRoot\nginx.exe"
    & nssm install nginx $nginxExe 2>&1 | Out-Null
    & nssm set nginx AppDirectory $nginxRoot 2>&1 | Out-Null
    & nssm set nginx AppStdout "$nginxRoot\logs\service.log" 2>&1 | Out-Null
    & nssm set nginx AppStderr "$nginxRoot\logs\service-error.log" 2>&1 | Out-Null
    Set-Service nginx -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service nginx -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    if ((Get-Service nginx -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Ok "Nginx activo en puerto $global:PUERTO_ELEGIDO"
    } else {
        Write-Err "Nginx no arranco. Revisa $nginxRoot\logs\error.log"
    }
}

# =============== MENU INSTALACION ===============
function Instalar-HTTP {
    Clear-Host
    Write-Host ""
    Write-Host "=== Instalacion de Servidor HTTP ==="
    Write-Host ""
    Write-Host "  [1] IIS (Internet Information Services)"
    Write-Host "  [2] Apache2"
    Write-Host "  [3] Nginx"
    Write-Host ""

    while ($true) {
        $opcion = Read-Host "Selecciona un servidor [1-3]"
        $opcion = $opcion -replace '[^0-9]',''
        if ($opcion -match '^[123]$') { break }
        Write-Err "Opcion invalida."
    }

    switch ($opcion) {
        "1" {
            $versiones = Obtener-Versiones-IIS
            if (-not (Elegir-Version "IIS" $versiones)) { return }
            Pedir-Puerto
            Instalar-IIS
        }
        "2" {
            Write-Info "Consultando versiones de Apache..."
            $versiones = Obtener-Versiones-Choco "apache-httpd"
            if ($versiones.Count -eq 0) { $versiones = @("2.4.62","2.4.63") }
            if (-not (Elegir-Version "Apache2" $versiones)) { return }
            Pedir-Puerto
            Instalar-Apache-Win
        }
        "3" {
            Write-Info "Consultando versiones de Nginx..."
            $versiones = Obtener-Versiones-Choco "nginx"
            if ($versiones.Count -eq 0) { $versiones = @("1.26.2","1.27.2") }
            if (-not (Elegir-Version "Nginx" $versiones)) { return }
            Pedir-Puerto
            Instalar-Nginx-Win
        }
    }
}

# =============== VERIFICAR ESTADO ===============
function Verificar-HTTP {
    Clear-Host
    Write-Host ""
    Write-Host "=== Estado de Servidores HTTP ==="
    Write-Host ""

    Write-Host -NoNewline "  IIS     : "
    $iis = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($iis) {
        $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" `
            -ErrorAction SilentlyContinue).VersionString
        $puerto = & "$env:SystemRoot\system32\inetsrv\appcmd.exe" list site "Default Web Site" 2>$null `
            | Select-String ':(\d+):' `
            | ForEach-Object { $_.Matches[0].Groups[1].Value } `
            | Select-Object -First 1
        if ($iis.Status -eq "Running") {
            Write-Host "Instalado y activo -- version: $ver -- puerto: $puerto"
        } else {
            Write-Host "Instalado pero detenido -- version: $ver"
        }
    } else { Write-Host "No instalado" }

    Write-Host -NoNewline "  Apache2 : "
    $apache = Get-Service Apache2.4 -ErrorAction SilentlyContinue
    if ($apache) {
        $confDir = Obtener-Ruta-Apache
        $puerto = if ($confDir) {
            Get-Content "$confDir\httpd.conf" | Select-String '^Listen\s+(\d+)' `
                | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
        } else { "?" }
        if ($apache.Status -eq "Running") {
            Write-Host "Instalado y activo -- puerto: $puerto"
        } else {
            Write-Host "Instalado pero detenido -- puerto: $puerto"
        }
    } else { Write-Host "No instalado" }

    Write-Host -NoNewline "  Nginx   : "
    $nginx = Get-Service nginx -ErrorAction SilentlyContinue
    if ($nginx) {
        $nginxRoot = Obtener-Ruta-Nginx
        $puerto = if ($nginxRoot -and (Test-Path "$nginxRoot\conf\nginx.conf")) {
            Get-Content "$nginxRoot\conf\nginx.conf" | Select-String 'listen\s+(\d+)' `
                | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
        } else { "?" }
        if ($nginx.Status -eq "Running") {
            Write-Host "Instalado y activo -- puerto: $puerto"
        } else {
            Write-Host "Instalado pero detenido -- puerto: $puerto"
        }
    } else { Write-Host "No instalado" }

    Write-Host ""
}

# =============== REVISAR CURL ===============
function Revisar-HTTP {
    Clear-Host
    Write-Host ""
    Write-Host "=== Revision de Servidores HTTP ==="
    Write-Host ""
    Write-Host "  [1] IIS"
    Write-Host "  [2] Apache2"
    Write-Host "  [3] Nginx"
    Write-Host "  [4] Todos"
    Write-Host ""

    while ($true) {
        $opcion = Read-Host "Selecciona [1-4]"
        $opcion = $opcion -replace '[^0-9]',''
        if ($opcion -match '^[1234]$') { break }
        Write-Err "Opcion invalida."
    }

    function Curl-Servidor {
        param([string]$nombre, [int]$puerto)
        Write-Host ""
        Write-Host "--- $nombre (puerto $puerto) ---"
        Write-Host "Headers:"
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" `
                -Method Head -UseBasicParsing -ErrorAction Stop
            $resp.Headers.GetEnumerator() | ForEach-Object {
                Write-Host "$($_.Key): $($_.Value)"
            }
        } catch { Write-Err "No se pudo conectar a puerto $puerto" }
        Write-Host "Index:"
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" `
                -UseBasicParsing -ErrorAction Stop
            Write-Host $resp.Content
        } catch { Write-Err "No se pudo obtener index de puerto $puerto" }
    }

    $puertoIIS = & "$env:SystemRoot\system32\inetsrv\appcmd.exe" list site "Default Web Site" 2>$null `
        | Select-String ':(\d+):' `
        | ForEach-Object { $_.Matches[0].Groups[1].Value } `
        | Select-Object -First 1

    $confDir      = Obtener-Ruta-Apache
    $puertoApache = if ($confDir) {
        Get-Content "$confDir\httpd.conf" | Select-String '^Listen\s+(\d+)' `
            | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
    } else { 80 }

    $nginxRoot   = Obtener-Ruta-Nginx
    $puertoNginx = if ($nginxRoot -and (Test-Path "$nginxRoot\conf\nginx.conf")) {
        Get-Content "$nginxRoot\conf\nginx.conf" | Select-String 'listen\s+(\d+)' `
            | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
    } else { 80 }

    switch ($opcion) {
        "1" { Curl-Servidor "IIS"    ([int]$puertoIIS)    }
        "2" { Curl-Servidor "Apache" ([int]$puertoApache) }
        "3" { Curl-Servidor "Nginx"  ([int]$puertoNginx)  }
        "4" {
            Curl-Servidor "IIS"    ([int]$puertoIIS)
            Curl-Servidor "Apache" ([int]$puertoApache)
            Curl-Servidor "Nginx"  ([int]$puertoNginx)
        }
    }
}
