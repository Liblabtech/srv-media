#Requires -Version 5.1
# =============================================================================
# srv-media — Creation des enregistrements CNAME Cloudflare
# =============================================================================
# Script interactif PowerShell pour creer les CNAME DNS dans Cloudflare
# qui redirigent les sous-domaines vers le host (serveur media).
#
# Usage: .\scripts\setup-dns.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

# --- Couleurs ---
function Write-Info    { param($Msg) Write-Host "[INFO] " -ForegroundColor Blue -NoNewline; Write-Host $Msg }
function Write-Ok      { param($Msg) Write-Host "[OK] " -ForegroundColor Green -NoNewline; Write-Host $Msg }
function Write-Warn    { param($Msg) Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $Msg }
function Write-Err     { param($Msg) Write-Host "[ERROR] " -ForegroundColor Red -NoNewline; Write-Host $Msg }
function Write-Step    { param($Step, $Msg) Write-Host "[$Step] " -ForegroundColor Cyan -NoNewline; Write-Host $Msg }

# =============================================================================
# Chargement du proxy-hosts.json
# =============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$ProxyHostsFile = Join-Path $ProjectDir "proxy\proxy-hosts.json"

if (-not (Test-Path $ProxyHostsFile)) {
    Write-Err "Fichier proxy-hosts.json introuvable : $ProxyHostsFile"
    exit 1
}

$ProxyHosts = Get-Content $ProxyHostsFile -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   srv-media — Setup DNS Cloudflare (CNAME)        ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# Etape 1 : Credentials Cloudflare
# =============================================================================

Write-Step "1/5" "Configuration Cloudflare"
Write-Host ""

# Essayer de charger depuis .env
$EnvFile = Join-Path $ProjectDir ".env"
$CF_Email = ""
$CF_Token = ""
$ServerIP = ""

if (Test-Path $EnvFile) {
    $envContent = Get-Content $EnvFile
    foreach ($line in $envContent) {
        if ($line -match "^CF_API_EMAIL=(.+)$") { $CF_Email = $Matches[1].Trim() }
        if ($line -match "^CF_API_TOKEN=(.+)$") { $CF_Token = $Matches[1].Trim() }
        if ($line -match "^SERVER_IP=(.+)$")    { $ServerIP = $Matches[1].Trim() }
    }
}

# Demander interactivement si manquant
if (-not $CF_Email -or $CF_Email -eq "your-cloudflare-email@example.com") {
    $CF_Email = Read-Host "  Cloudflare Email"
}
else {
    $confirm = Read-Host "  Cloudflare Email [$CF_Email]"
    if ($confirm) { $CF_Email = $confirm }
}

if (-not $CF_Token -or $CF_Token -eq "your-cloudflare-api-token") {
    $CF_Token = Read-Host "  Cloudflare API Token (Global API Key ou API Token)"
}
else {
    $masked = $CF_Token.Substring(0, [Math]::Min(6, $CF_Token.Length)) + "..."
    $confirm = Read-Host "  Cloudflare API Token [$masked]"
    if ($confirm) { $CF_Token = $confirm }
}

if (-not $ServerIP) {
    $ServerIP = Read-Host "  IP du serveur cible (pour le CNAME/A record) [172.0.16.126]"
    if (-not $ServerIP) { $ServerIP = "172.0.16.126" }
}
else {
    $confirm = Read-Host "  IP du serveur [$ServerIP]"
    if ($confirm) { $ServerIP = $confirm }
}

Write-Host ""

# --- Headers API ---
$Headers = @{
    "X-Auth-Email" = $CF_Email
    "X-Auth-Key"   = $CF_Token
    "Content-Type"  = "application/json"
}

# =============================================================================
# Etape 2 : Recuperer les zones Cloudflare
# =============================================================================

Write-Step "2/5" "Recuperation des zones DNS Cloudflare..."
Write-Host ""

try {
    $zonesResponse = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones" `
        -Method Get -Headers $Headers
}
catch {
    Write-Err "Echec d'authentification Cloudflare. Verifiez email + API token."
    Write-Err $_.Exception.Message
    exit 1
}

if (-not $zonesResponse.success) {
    Write-Err "Erreur API Cloudflare : $($zonesResponse.errors | ConvertTo-Json)"
    exit 1
}

# Extraire les zones uniques necessaires a partir des domaines
$RequiredZones = @{}
foreach ($host in $ProxyHosts) {
    $parts = $host.domain.Split(".")
    # Le zone name est les 2 derniers segments (ex: lib-lab.cloud)
    $zoneName = ($parts[-2..-1]) -join "."
    $RequiredZones[$zoneName] = $true
}

Write-Info "Zones requises : $($RequiredZones.Keys -join ', ')"

$ZoneMap = @{}
foreach ($zone in $zonesResponse.result) {
    if ($RequiredZones.ContainsKey($zone.name)) {
        $ZoneMap[$zone.name] = $zone.id
        Write-Ok "Zone trouvee : $($zone.name) (ID: $($zone.id))"
    }
}

foreach ($required in $RequiredZones.Keys) {
    if (-not $ZoneMap.ContainsKey($required)) {
        Write-Err "Zone '$required' non trouvee dans votre compte Cloudflare !"
        exit 1
    }
}

Write-Host ""

# =============================================================================
# Etape 3 : Choix du type d'enregistrement
# =============================================================================

Write-Step "3/5" "Configuration des enregistrements DNS"
Write-Host ""
Write-Host "  Les sous-domaines peuvent pointer vers :" -ForegroundColor White
Write-Host "    1) Un hostname (CNAME) — ex: srv-media.lib-lab.cloud" -ForegroundColor White
Write-Host "    2) Une IP directement (A record) — ex: $ServerIP" -ForegroundColor White
Write-Host ""

$recordChoice = Read-Host "  Choix [1=CNAME / 2=A record] (defaut: 2)"
if (-not $recordChoice) { $recordChoice = "2" }

$RecordType = "A"
$RecordTarget = $ServerIP

if ($recordChoice -eq "1") {
    $RecordType = "CNAME"
    $RecordTarget = Read-Host "  Hostname cible pour le CNAME (ex: srv-media.lib-lab.cloud)"
    if (-not $RecordTarget) {
        Write-Err "Hostname requis pour CNAME."
        exit 1
    }
}

# Proxied ou DNS only ?
Write-Host ""
Write-Host "  Mode Cloudflare :" -ForegroundColor White
Write-Host "    1) Proxied (orange cloud) — trafic passe par Cloudflare (CDN + protection)" -ForegroundColor White
Write-Host "    2) DNS Only (grey cloud) — resolution DNS directe vers votre serveur" -ForegroundColor White
Write-Host ""
$proxyChoice = Read-Host "  Choix [1=Proxied / 2=DNS Only] (defaut: 2)"
$Proxied = $false
if ($proxyChoice -eq "1") { $Proxied = $true }

# Delai entre creations
$Delay = Read-Host "  Delai entre chaque creation (secondes) [2]"
if (-not $Delay) { $Delay = 2 }
$Delay = [int]$Delay

Write-Host ""

# =============================================================================
# Etape 4 : Selection des enregistrements a creer
# =============================================================================

Write-Step "4/5" "Selection des enregistrements"
Write-Host ""
Write-Host "  Domaines disponibles :" -ForegroundColor White
Write-Host ""

for ($i = 0; $i -lt $ProxyHosts.Count; $i++) {
    $num = ($i + 1).ToString().PadLeft(2)
    Write-Host "    $num) $($ProxyHosts[$i].domain)" -ForegroundColor White
}

Write-Host ""
Write-Host "  Options :" -ForegroundColor Yellow
Write-Host "    - 'all' pour tout creer" -ForegroundColor White
Write-Host "    - Numeros separes par des virgules (ex: 1,3,5,10)" -ForegroundColor White
Write-Host "    - Plage (ex: 1-10)" -ForegroundColor White
Write-Host ""

$selection = Read-Host "  Selection [all]"
if (-not $selection) { $selection = "all" }

$SelectedIndices = @()

if ($selection -eq "all") {
    $SelectedIndices = 0..($ProxyHosts.Count - 1)
}
elseif ($selection -match "^\d+-\d+$") {
    $range = $selection.Split("-")
    $SelectedIndices = ([int]$range[0] - 1)..([int]$range[1] - 1)
}
else {
    $SelectedIndices = $selection.Split(",") | ForEach-Object { [int]$_.Trim() - 1 }
}

Write-Host ""
Write-Info "$($SelectedIndices.Count) enregistrements selectionnes."
Write-Host ""

# =============================================================================
# Etape 5 : Creation des enregistrements DNS
# =============================================================================

Write-Step "5/5" "Creation des enregistrements DNS..."
Write-Host ""

$Success = 0
$Skipped = 0
$Failed = 0
$Total = $SelectedIndices.Count

foreach ($idx in $SelectedIndices) {
    $entry = $ProxyHosts[$idx]
    $domain = $entry.domain
    $counter = ($SelectedIndices.IndexOf($idx) + 1)

    # Determiner la zone
    $parts = $domain.Split(".")
    $zoneName = ($parts[-2..-1]) -join "."
    $zoneId = $ZoneMap[$zoneName]

    # Extraire le nom relatif (sans la zone)
    $recordName = $domain

    # Verifier si l'enregistrement existe deja
    try {
        $existingUrl = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records?name=$domain&type=$RecordType"
        $existing = Invoke-RestMethod -Uri $existingUrl -Method Get -Headers $Headers

        if ($existing.result.Count -gt 0) {
            Write-Host "  [$counter/$Total] " -NoNewline
            Write-Host "~" -ForegroundColor Yellow -NoNewline
            Write-Host " $domain (existe deja, ID: $($existing.result[0].id))"
            $Skipped++
            Start-Sleep -Seconds $Delay
            continue
        }
    }
    catch {
        # Continuer meme si la verification echoue
    }

    # Creer l'enregistrement
    $body = @{
        type    = $RecordType
        name    = $recordName
        content = $RecordTarget
        ttl     = 1  # Auto
        proxied = $Proxied
    } | ConvertTo-Json

    try {
        $createUrl = "https://api.cloudflare.com/client/v4/zones/$zoneId/dns_records"
        $result = Invoke-RestMethod -Uri $createUrl -Method Post -Headers $Headers -Body $body

        if ($result.success) {
            Write-Host "  [$counter/$Total] " -NoNewline
            Write-Host "+" -ForegroundColor Green -NoNewline
            $proxyIcon = if ($Proxied) { " [proxied]" } else { " [DNS only]" }
            Write-Host " $domain -> $RecordTarget ($RecordType)$proxyIcon"
            $Success++
        }
        else {
            Write-Host "  [$counter/$Total] " -NoNewline
            Write-Host "x" -ForegroundColor Red -NoNewline
            Write-Host " $domain — $($result.errors | ConvertTo-Json -Compress)"
            $Failed++
        }
    }
    catch {
        Write-Host "  [$counter/$Total] " -NoNewline
        Write-Host "x" -ForegroundColor Red -NoNewline
        Write-Host " $domain — $($_.Exception.Message)"
        $Failed++
    }

    Start-Sleep -Seconds $Delay
}

# =============================================================================
# Resume
# =============================================================================

Write-Host ""
Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                Resume                             ║" -ForegroundColor Cyan
Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "    Type       : " -NoNewline; Write-Host "$RecordType -> $RecordTarget" -ForegroundColor White
Write-Host "    Proxied    : " -NoNewline; Write-Host "$Proxied" -ForegroundColor White
Write-Host "    Crees      : " -NoNewline; Write-Host "$Success" -ForegroundColor Green
Write-Host "    Existants  : " -NoNewline; Write-Host "$Skipped" -ForegroundColor Yellow
Write-Host "    Echoues    : " -NoNewline; Write-Host "$Failed" -ForegroundColor Red
Write-Host "    Total      : " -NoNewline; Write-Host "$Total" -ForegroundColor Cyan
Write-Host ""

if ($Success -gt 0) {
    Write-Ok "Enregistrements DNS crees. Propagation DNS : quelques secondes a minutes."
}

Write-Host ""
