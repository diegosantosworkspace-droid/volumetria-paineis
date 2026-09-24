# github_configurar.ps1 - Prepara o repo VOLUMETRIA_SITE e conecta ao GitHub (uma vez)
# Uso (com token):
#   $env:GH_TOKEN = "seu_token_aqui"
#   powershell -ExecutionPolicy Bypass -File github_configurar.ps1 joaosilva
param([Parameter(Mandatory=$true)][string]$Usuario)

$ErrorActionPreference = 'Stop'
$site = Split-Path -Parent $MyInvocation.MyCommand.Path
$token = $env:GH_TOKEN
if (-not $token) {
    Write-Error "Defina GH_TOKEN primeiro: $env:GH_TOKEN = 'seu_token'"
    exit 1
}
$repo = 'volumetria-paineis'
Set-Location $site

# 1) Garante branch main + commit inicial (se ainda nao houver .git)
if (-not (Test-Path (Join-Path $site '.git'))) {
    git init -b main 2>&1 | Out-Null
    git add -A 2>&1 | Out-Null
    git -c user.name=$Usuario -c user.email="$Usuario@users.noreply.github.com" commit -m "painels volumetria - publicacao inicial" 2>&1 | Out-Null
} else {
    # garante user local caso falte
    git config user.name $Usuario
    git config user.email "$Usuario@users.noreply.github.com"
}

# 2) Cria o repositorio remoto (privado) via API do GitHub usando o token
$headers = @{ Authorization = "token $token"; 'User-Agent' = 'volumetria-publicar' }
$body = @{ name = $repo; private = $true; auto_init = $false } | ConvertTo-Json
try {
    $criado = Invoke-RestMethod -Method Post -Uri 'https://api.github.com/user/repos' -Headers $headers -Body $body -ContentType 'application/json'
    Write-Output "Repo criado ok: $($criado.full_name) ($($criado.html_url))"
} catch {
    $msg = $_.Exception.Message
    if ($msg -match 'already exists') {
        Write-Output "Repo ja existe (prosseguindo para conectar)."
    } else {
        Write-Error "Falha ao criar repo: $msg"
        exit 1
    }
}

# 3) Configura o remoto (sem token na URL) e guarda a credencial no credential.helper
$remote = "https://$Usuario@github.com/$Usuario/$repo.git"
git remote remove origin 2>&1 | Out-Null
git remote add origin $remote
git config credential.helper store
# Armazena usuario+token via git credential (fica em ~/.git-credentials, texto plano,
# como convém ao helper store). Usado pelo push do publicar_site sem expor o token.
$credo = "https://$Usuario`:$token@github.com`n"
$credo | git credential approve 2>&1 | Out-Null
Write-Output "Credencial armazenada no credential.helper do git (sem expor o token nos logs)."

# 4) Push da branch principal (usa a credencial guardada acima)
$pushOut = git push -u origin main 2>&1 | Out-String
Write-Output ("push: " + (($pushOut -replace "`n",' ').Trim()))

# 5) Habilita GitHub Pages (branch main, pasta raiz)
try {
    $pages = @{ source = @{ branch = 'main'; path = '/' } } | ConvertTo-Json -Depth 3
    Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Usuario/$repo/pages" -Headers $headers -Body $pages -ContentType 'application/json' | Out-Null
    Write-Output "GitHub Pages habilitado."
} catch {
    try {
        Invoke-RestMethod -Method Put -Uri "https://api.github.com/repos/$Usuario/$repo/pages" -Headers $headers -Body $pages -ContentType 'application/json' | Out-Null
        Write-Output "GitHub Pages ja estava habilitado (PUT ok)."
    } catch {
        Write-Output "Aviso: nao consegui habilitar Pages automaticamente: $($_.Exception.Message)"
    }
}

Write-Output ""
Write-Output "PRONTO. Para ir ao vivo (pode levar ~1-2 min apos o primeiro push):"
Write-Output "  https://$Usuario.github.io/$repo/"
Start-Sleep -Seconds 2