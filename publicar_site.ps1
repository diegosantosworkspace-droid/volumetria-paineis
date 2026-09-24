# publicar_site.ps1 - Publica os painéis de volumetria no site estático (GitHub Pages)
# Sincroniza dashboard + dados de cada RDC para VOLUMETRIA_SITE\<cod>\ e faz push automático.
# Uso:
#   powershell -ExecutionPolicy Bypass -File publicar_site.ps1            (sobe tudo)
#   powershell -ExecutionPolicy Bypass -File publicar_site.ps1 -ApenasSeMudou
# (O parametro precisa vir antes de qualquer outra instrucao.)

param([switch]$ApenasSeMudou)

$ErrorActionPreference = 'Continue'

$site    = Split-Path -Parent $MyInvocation.MyCommand.Path          # ...VOLUMETRIA_SITE
$desk    = Split-Path -Parent $site                                 # Desktop
$logPath = Join-Path $site 'publicar.log'

function Log([string]$m) {
    $li = '[' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '] ' + $m
    Add-Content -Path $logPath -Value $li -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Output $li
}

# RDC -> pasta origem (dashboard + json). Só publica RDC que tem dados.
$rdcs = @(
    @{cod='sp1'; dir=Join-Path $desk 'VOLUMETRIA';     cidade='Guarulhos'},
    @{cod='sp2'; dir=Join-Path $desk 'VOLUMETRIA_SP2'; cidade='Barueri'},
    @{cod='sp4'; dir=Join-Path $desk 'VOLUMETRIA_SP4'; cidade='Bauru'},
    @{cod='sp5'; dir=Join-Path $desk 'VOLUMETRIA_SP5'; cidade='Ribeirao Preto'},
    @{cod='sp6'; dir=Join-Path $desk 'VOLUMETRIA_SP6'; cidade='Hortolandia'},
    @{cod='sp8'; dir=Join-Path $desk 'VOLUMETRIA_SP8'; cidade='Guarulhos'}
)

# --- Checagem rápida: se nada mudou e --ApenasSeMudou, sai sem gastar push ---
if ($ApenasSeMudou) {
    $mudou = $false
    foreach ($r in $rdcs) {
        $json     = Join-Path $r.dir 'dados_volumetria.json'
        $destJson = Join-Path $site ($r.cod + '\dados_volumetria.json')
        if (Test-Path $json) {
            if (-not (Test-Path $destJson)) { $mudou = $true; break }
            if ((Get-Item $json).LastWriteTime -gt (Get-Item $destJson).LastWriteTime) { $mudou = $true; break }
        }
        $dash     = Join-Path $r.dir 'volumetria_dashboard.html'
        $destDash = Join-Path $site ($r.cod + '\index.html')
        if (Test-Path $dash) {
            if (-not (Test-Path $destDash)) { $mudou = $true; break }
            if ((Get-Item $dash).LastWriteTime -gt (Get-Item $destDash).LastWriteTime) { $mudou = $true; break }
        }
    }
    if (-not $mudou) { Log 'publicar_site: nada mudou; sem push.'; exit 0 }
}

# --- Copia dashboard (como index.html) + dados + recursos publicos de cada RDC ---
foreach ($r in $rdcs) {
    $dash = Join-Path $r.dir 'volumetria_dashboard.html'
    $json = Join-Path $r.dir 'dados_volumetria.json'
    $pub  = Join-Path $r.dir 'public'
    $dest = Join-Path $site $r.cod
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    if (Test-Path $dash) {
        $html = Get-Content $dash -Raw -Encoding UTF8
        # Título do painel por RDC (dashboard tem SP1/GUARULHOS hardcoded)
        $html = $html -replace '(class="rdc-code">)[^<]*(<)', ('$1' + $r.cod.ToUpper() + '$2')
        $html = $html -replace '(class="rdc-name">)[^<]*(<)', ('$1' + $r.cidade.ToUpper() + '$2')
        Set-Content -Path (Join-Path $dest 'index.html') -Value $html -Encoding UTF8 -NoNewline
    }
    if (Test-Path $json) {
        Copy-Item $json (Join-Path $dest 'dados_volumetria.json') -Force
    }
    $prog = Join-Path $r.dir 'programacao.json'
    if (Test-Path $prog) {
        Copy-Item $prog (Join-Path $dest 'programacao.json') -Force
    }
    if (Test-Path $pub) {
        $destPub = Join-Path $dest 'public'
        New-Item -ItemType Directory -Path $destPub -Force | Out-Null
        Copy-Item (Join-Path $pub '*') $destPub -Recurse -Force
    }
}

# --- Regenera o portal index.html com data de atualização + ultimo dado por RDC ---
$cards = ''
foreach ($r in $rdcs) {
    $json = Join-Path $site ($r.cod + '\dados_volumetria.json')
    $ufmt = 'aguardando dados'
    $tot  = ''
    if (Test-Path $json) {
        try {
            $j = Get-Content $json -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.geradoEm) { $ufmt = $j.geradoEm }
            $soma = 0
            if ($j.porDataTotal) { $j.porDataTotal.PSObject.Properties | ForEach-Object { $soma += [int]$_.Value } }
            $tot = '<div class="total">total <b>' + ('{0:N0}' -f $soma) + '</b></div>'
        } catch { $ufmt = 'dados indisponiveis' }
    }
    $cards += '<div class="card"><div class="cod">' + $r.cod.ToUpper() + '</div>' +
              '<div class="cidade">' + $r.cidade + '</div>' +
              '<div class="status">Painel online</div>' + $tot +
              '<div class="upd">' + $ufmt + '</div>' +
              '<a href="' + $r.cod + '/">ABRIR</a></div>'
}
$htmlBody = @"
<!DOCTYPE html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Volumetria - Paineis dos RDCs</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; background:#0d1420; color:#dfe8f2; margin:0; min-height:100vh; }
  header { background:#152030; padding:26px 24px; border-bottom:3px solid #FFDD00; }
  h1 { color:#FFDD00; font-size:28px; margin:0; }
  p.meta { color:#9db8d4; margin:6px 0 0; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(240px,1fr)); gap:18px; padding:26px 24px; }
  .card { background:#152030; border:1px solid #2c3b4f; border-radius:10px; padding:18px; text-align:center; transition:transform .12s, box-shadow .12s; }
  .card:hover { transform:translateY(-3px); box-shadow:0 6px 18px rgba(0,0,0,.45); border-color:#FFDD00; }
  .card .cod { font-size:34px; font-weight:800; color:#FFDD00; }
  .card .cidade { color:#9db8d4; margin-top:4px; font-size:14px; }
  .card .status { margin-top:10px; font-size:13px; color:#63e08c; }
  .card .total { margin-top:8px; font-size:15px; color:#FFDD00; }
  .card .upd { margin-top:2px; font-size:12px; color:#5f7894; }
  .card a { display:inline-block; margin-top:14px; padding:9px 22px; border:1px solid #FFDD00; color:#FFDD00; border-radius:6px; text-decoration:none; font-weight:700; font-size:14px; }
  .card a:hover { background:#FFDD00; color:#0d1420; }
  footer { padding:14px 24px; color:#5f7894; font-size:12px; }
</style>
</head>
<body>
<header>
  <h1>VOLUMETRIA &middot; PAINEIS</h1>
  <p class="meta">Acesso externo aos paineis de volumetria dos RDCs - atualiza automaticamente a cada processamento.</p>
</header>
<div class="grid">
$cards
</div>
<footer>Publicacao automatica a partir da maquina de origem &middot; Volumetria</footer>
</body>
</html>
"@
$htmlBody | Set-Content (Join-Path $site 'index.html') -Encoding UTF8

# --- Git: commit + push (só se houver mudança) ---
Set-Location $site
if (-not (Test-Path (Join-Path $site '.git'))) {
    Log 'publicar_site: sem .git local; rode github_configurar.ps1 antes.'
    exit 0
}
$antes = & git status --porcelain 2>$null
if (-not $antes) {
    Log 'publicar_site: sem mudancas no git; nada a empurrar.'
    exit 0
}
& git add -A 2>&1 | Out-Null
$msg = 'painels atualizados em ' + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss') + ' via publicar_site'
& git commit -m $msg 2>&1 | ForEach-Object { Log ('  git: ' + $_) }
$push = & git push origin HEAD 2>&1 | Out-String
Log ('publicar_site: push: ' + (($push -replace "`n",' ').Trim()))
Log 'publicar_site: concluido com sucesso.'
exit 0