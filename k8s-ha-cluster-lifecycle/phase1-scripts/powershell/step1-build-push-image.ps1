# Step 1 - build the Django image and push it to Docker Hub.
# Needs the Docker CLI: Docker Desktop, or minikube's Docker via
#   & minikube -p minikube docker-env --shell powershell | Invoke-Expression
. "$PSScriptRoot\lib.ps1"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI not found. Install Docker Desktop, or build inside minikube (see README, Step 1)."
}

Write-Step "Building $Image from $AppDir"
docker build -t $Image $AppDir
if ($LASTEXITCODE -ne 0) { throw "docker build failed" }

Write-Step "Quick local test (container on port 8000)"
$ErrorActionPreference = "Continue"     # docker writes normal output to stderr
docker rm -f django-test 2>&1 | Out-Null
docker run -d --name django-test -p 8000:8000 $Image | Out-Null
Start-Sleep -Seconds 5
docker logs django-test 2>&1
docker rm -f django-test 2>&1 | Out-Null
$ErrorActionPreference = "Stop"

Write-Step "Pushing to Docker Hub (run 'docker login' first if this fails with 'denied')"
docker push $Image
if ($LASTEXITCODE -ne 0) { throw "docker push failed - run: docker login -u <dockerhub-user>" }

Write-Host "`nDone. Check https://hub.docker.com/r/$($Image.Split(':')[0])/tags - the repository must be Public." -ForegroundColor Green
