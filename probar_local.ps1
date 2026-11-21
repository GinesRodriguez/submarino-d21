# probar_local.ps1 - Tu Submarino d21: prueba local como si estuviera publicado.
# Uso:  powershell -ExecutionPolicy Bypass -File .\probar_local.ps1 [-Archivo Tu_Submarino_d21_v21_16.html] [-Puerto 8021]
# No hace commit ni push. Termina con Ctrl+C o cerrando la ventana de Chrome; en ambos casos cierra Chrome y el servidor.
param(
  [string]$Archivo = "index.html",
  [int]$Puerto = 8021,
  [switch]$SinNavegador
)
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $raiz

# Log de cada lanzamiento: logs\probar_local_AAAA-MM-DD_HH-MM-SS.log (salida, avisos y errores)
$dirLogs = Join-Path $raiz "logs"
if (-not (Test-Path $dirLogs)) { New-Item -ItemType Directory -Path $dirLogs | Out-Null }
$logFile = Join-Path $dirLogs ("probar_local_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))
try { Start-Transcript -Path $logFile -Force | Out-Null } catch {}
Write-Host "Log: $logFile"
Write-Host ("Inicio: {0} | Archivo={1} Puerto={2} SinNavegador={3} | PowerShell {4}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Archivo, $Puerto, $SinNavegador, $PSVersionTable.PSVersion)
trap {
  Write-Host ("ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  Write-Host ($_.InvocationInfo.PositionMessage)
  Write-Host ($_.ScriptStackTrace)
  try { Stop-Transcript | Out-Null } catch {}
  exit 1
}

$tipos = @{
  ".html"="text/html; charset=utf-8"; ".js"="application/javascript"; ".css"="text/css";
  ".json"="application/json"; ".png"="image/png"; ".jpg"="image/jpeg"; ".jpeg"="image/jpeg";
  ".webp"="image/webp"; ".gif"="image/gif"; ".svg"="image/svg+xml"; ".ico"="image/x-icon";
  ".mp3"="audio/mpeg"; ".ogg"="audio/ogg"; ".flac"="audio/flac"; ".wav"="audio/wav";
  ".woff2"="font/woff2"; ".woff"="font/woff"; ".ttf"="font/ttf"
}

# 1) Comprobaciones previas: el HTML y las canciones que referencia
Write-Host "== Comprobando archivos ==" -ForegroundColor Cyan
if (-not (Test-Path $Archivo)) { Write-Host "No existe $Archivo" -ForegroundColor Red; try { Stop-Transcript | Out-Null } catch {}; exit 1 }
$html = Get-Content $Archivo -Raw -Encoding UTF8
$refs = [regex]::Matches($html, '["''](assets/[^"''\s\)]+)["'']') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$faltan = 0
foreach ($r in $refs) {
  if (Test-Path (Join-Path $raiz $r)) { Write-Host "  OK  $r" } else { Write-Host "  FALTA $r" -ForegroundColor Red; $faltan++ }
}
# Variantes .mp3/.ogg que el juego prueba segun navegador
foreach ($r in $refs | Where-Object { $_ -match '\.(ogg|mp3)$' }) {
  $alt = if ($r -match '\.ogg$') { $r -replace '\.ogg$','.mp3' } else { $r -replace '\.mp3$','.ogg' }
  if (Test-Path (Join-Path $raiz $alt)) { Write-Host "  OK  $alt (alternativa)" }
}
$nMusica = (Get-ChildItem (Join-Path $raiz "assets\music") -File -ErrorAction SilentlyContinue).Count
Write-Host "Canciones en assets\music: $nMusica"
$mb = [math]::Round((Get-Item $Archivo).Length/1MB,2)
Write-Host "Archivo: $Archivo ($mb MB)"
$ver = [regex]::Match($html, 'GAME_BUILD\s*=\s*"([^"]+)"').Groups[1].Value
if ($ver) { Write-Host "Version (GAME_BUILD): $ver" }
if ($faltan -gt 0) { Write-Host "Faltan $faltan archivos: la musica o imagenes pueden fallar." -ForegroundColor Yellow }

# 2) Servidor web local (como GitHub Pages, rutas relativas a esta carpeta)
$prefijo = "http://localhost:$Puerto/"
$srv = New-Object System.Net.HttpListener
$srv.Prefixes.Add($prefijo)
try { $srv.Start() } catch { Write-Host "No puedo abrir el puerto $Puerto. Prueba con -Puerto 8022" -ForegroundColor Red; exit 1 }
$url = $prefijo + [uri]::EscapeDataString($Archivo) + "?v=" + (Get-Date -Format "HHmmss")
Write-Host ""
Write-Host "== Servidor en $prefijo ==" -ForegroundColor Green
Write-Host "Juego: $url"
Write-Host "Ctrl+C o cerrar la ventana de Chrome para terminar."

# 3) Autocomprobacion por HTTP de todo lo que carga el juego
$job = Start-Job -ArgumentList $prefijo, $Archivo, $refs -ScriptBlock {
  param($p, $a, $rs)
  Start-Sleep -Milliseconds 800
  $res = @()
  foreach ($x in @($a) + $rs) {
    try { $r = Invoke-WebRequest -Uri ($p + $x) -Method Head -UseBasicParsing -TimeoutSec 10; $res += "  $($r.StatusCode)  $x" }
    catch { $res += "  ERROR  $x  $($_.Exception.Message)" }
  }
  $res
}

# Chrome en ventana propia con perfil temporal: asi se puede cerrar al terminar
$chrome = $null; $perfil = $null
if (-not $SinNavegador) {
  $rutasChrome = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe")
  $exe = $rutasChrome | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if ($exe) {
    $perfil = Join-Path $env:TEMP ("submarino_d21_prueba_" + $Puerto)
    $chrome = Start-Process -FilePath $exe -PassThru -ArgumentList @(
      "--user-data-dir=`"$perfil`"", "--no-first-run", "--no-default-browser-check",
      "--autoplay-policy=no-user-gesture-required", "--new-window", $url)
    Write-Host "Chrome abierto (cerrar la ventana tambien termina la prueba)."
  } else {
    Write-Host "No encuentro Chrome; abro el navegador por defecto (esa ventana no se cerrara sola)." -ForegroundColor Yellow
    Start-Process $url
  }
}
function Cerrar-Chrome {
  if ($perfil) {
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -like "*$perfil*" } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  }
}
$chromeVisto = $false

$autoMostrado = $false
try {
  while ($srv.IsListening) {
    $ctxTask = $srv.GetContextAsync()
    while (-not $ctxTask.AsyncWaitHandle.WaitOne(300)) {
      if ($perfil) {
        $vivos = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$perfil*" })
        if ($vivos.Count -gt 0) { $chromeVisto = $true }
        elseif ($chromeVisto) { Write-Host "Ventana de Chrome cerrada: fin de la prueba."; $srv.Stop(); break }
      }
      if (-not $autoMostrado -and $job.State -eq "Completed") {
        Write-Host "== Autocomprobacion HTTP ==" -ForegroundColor Cyan
        Receive-Job $job | ForEach-Object { Write-Host $_ }
        $autoMostrado = $true
      }
    }
    if (-not $srv.IsListening) { break }
    $ctx = $ctxTask.Result
    $req = $ctx.Request; $resp = $ctx.Response
    $rel = [uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
    if ($rel -eq "") { $rel = "index.html" }
    $ruta = [IO.Path]::GetFullPath((Join-Path $raiz $rel))
    $codigo = 200
    if (-not $ruta.StartsWith($raiz) -or -not (Test-Path $ruta -PathType Leaf)) {
      $codigo = 404; $resp.StatusCode = 404
      $b = [Text.Encoding]::UTF8.GetBytes("404 $rel"); $resp.ContentLength64 = $b.Length; try { if ($req.HttpMethod -ne "HEAD") { $resp.OutputStream.Write($b,0,$b.Length) } } catch {}
    } else {
      $ext = [IO.Path]::GetExtension($ruta).ToLower()
      $resp.ContentType = if ($tipos[$ext]) { $tipos[$ext] } else { "application/octet-stream" }
      $resp.Headers.Add("Accept-Ranges","bytes")
      $resp.Headers.Add("Cache-Control","no-cache")
      $len = (Get-Item $ruta).Length
      $rango = $req.Headers["Range"]
      $fs = [IO.File]::OpenRead($ruta)
      try {
        if ($rango -and $rango -match 'bytes=(\d*)-(\d*)') {
          $ini = if ($matches[1]) { [long]$matches[1] } else { 0 }
          $fin = if ($matches[2]) { [long]$matches[2] } else { $len - 1 }
          $codigo = 206; $resp.StatusCode = 206
          $resp.Headers.Add("Content-Range","bytes $ini-$fin/$len")
          $resp.ContentLength64 = $fin - $ini + 1
          if ($req.HttpMethod -ne "HEAD") {
            $fs.Seek($ini,'Begin') | Out-Null
            $buf = New-Object byte[] 65536; $quedan = $fin - $ini + 1
            while ($quedan -gt 0) { $n = $fs.Read($buf,0,[math]::Min($buf.Length,$quedan)); if ($n -le 0) {break}; $resp.OutputStream.Write($buf,0,$n); $quedan -= $n }
          }
        } else {
          $resp.ContentLength64 = $len
          if ($req.HttpMethod -ne "HEAD") { $fs.CopyTo($resp.OutputStream) }
        }
      } catch {} finally { $fs.Close() }
    }
    try { $resp.Close() } catch {}
    if ($req.HttpMethod -ne "HEAD") { Write-Host ("{0}  {1}  {2}" -f (Get-Date -Format "HH:mm:ss"), $codigo, $rel) }
  }
} finally {
  Cerrar-Chrome
  try { $srv.Stop() } catch {}
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  Write-Host ("Servidor parado. Fin: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
  try { Stop-Transcript | Out-Null } catch {}
}
