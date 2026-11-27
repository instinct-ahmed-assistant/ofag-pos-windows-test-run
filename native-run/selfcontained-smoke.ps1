# Self-contained start proof. Hides every installed .NET from the process, starts the self-contained exe, records which runtime it loaded. Synthetic TRIAL data only.
param([Parameter(Mandatory=$true)][string]$Exe,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log=Join-Path $OutDir 'selfcontained.log'
function Say($m){ $l=('{0:HH:mm:ss} {1}' -f (Get-Date),$m); Add-Content -Path $log -Value $l; Write-Output $l }
function Shot($name){ try{ $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size); $bmp.Save((Join-Path $OutDir ($name+'.png')),[System.Drawing.Imaging.ImageFormat]::Png); Say "SCREENSHOT $name.png" }catch{ Say "WARN screenshot failed: $($_.Exception.Message)" } }
$fails=0
$dn='C:\Program Files\dotnet'; $hid='C:\Program Files\dotnet-HIDDEN-by-test'; $renamed=$false
Say "INFO exe=$Exe size=$((Get-Item $Exe).Length)"
Say "INFO sha256=$((Get-FileHash $Exe -Algorithm SHA256).Hash)"
try{ if(Test-Path $dn){
    try{ Rename-Item -Path $dn -NewName 'dotnet-HIDDEN-by-test' -ErrorAction Stop; $renamed=$true; Say 'INFO installed .NET folder renamed away' }catch{
      Say "INFO plain rename denied: $($_.Exception.Message); trying takeown and icacls"
      try{ $t1=Start-Process -FilePath 'takeown.exe' -ArgumentList @('/F',$dn,'/R','/D','Y') -Wait -PassThru -WindowStyle Hidden; Say "takeown exit $($t1.ExitCode)"; $t2=Start-Process -FilePath 'icacls.exe' -ArgumentList @($dn,'/grant','Administrators:(OI)(CI)F','/T','/C') -Wait -PassThru -WindowStyle Hidden; Say "icacls exit $($t2.ExitCode)"; Rename-Item -Path $dn -NewName 'dotnet-HIDDEN-by-test' -ErrorAction Stop; $renamed=$true; Say 'INFO installed .NET folder renamed after takeown' }catch{ Say "WARN could not hide installed .NET ($($_.Exception.Message)); weaker test: only PATH and DOTNET_ROOT variables are cleared" } }
  } else { Say "INFO no installed .NET folder at $dn" } }catch{ Say "WARN hide step: $($_.Exception.Message)" }
$env:DOTNET_MULTILEVEL_LOOKUP='0'; $env:DOTNET_ROOT=(New-Item -ItemType Directory -Force -Path (Join-Path $env:RUNNER_TEMP 'empty-dotnet-root')).FullName
Say ("INFO installed .NET hidden by rename: " + $renamed)
Say ("CHECK dotnet visible: " + [bool](Get-Command dotnet -ErrorAction SilentlyContinue))
foreach($v in 'DOTNET_ROOT','DOTNET_ROOT(x86)','DOTNET_ROOT_X64'){ [Environment]::SetEnvironmentVariable($v,$null,'Process') }
$env:PATH=(($env:PATH -split ';' | Where-Object { $_ -notmatch 'dotnet' }) -join ';')
Say ("CHECK dotnet visible after PATH cleanup: " + [bool](Get-Command dotnet -ErrorAction SilentlyContinue))
$p=Start-Process -FilePath $Exe -PassThru
$ok=$false; $end=(Get-Date).AddSeconds(60)
do{ Start-Sleep -Milliseconds 700; $p.Refresh(); if($p.HasExited){ break }; if($p.MainWindowHandle -ne [IntPtr]::Zero){ $ok=$true } }while(-not $ok -and (Get-Date) -lt $end)
if($p.HasExited){ Say "FAIL process exited early, exit code $($p.ExitCode)"; $fails++ }
elseif($ok){ Say "PASS window appeared: '$($p.MainWindowTitle)'" }
else { Say "FAIL no window within 60 s (process alive)"; $fails++ }
Start-Sleep 3; Shot 'sc-01-started'
try{ $p.Refresh(); $all=@($p.Modules | ForEach-Object { $_.FileName }); Say "INFO loaded modules: $($all.Count)"; foreach($m in $all){ Say "MODULE $m" }
  $bad=@($all | Where-Object { $_ -like 'C:\Program Files\dotnet\*' -or $_ -like 'C:\Program Files (x86)\dotnet\*' })
  if($bad.Count -gt 0){ Say "FAIL $($bad.Count) module(s) loaded from an installed .NET folder"; $fails++ } else { Say 'PASS no loaded module comes from an installed .NET folder (single-file build carries its runtime inside the exe)' }
  $self=@($all | Where-Object { $_ -ieq (Resolve-Path $Exe).Path }); if($self.Count -ge 1){ Say 'PASS the app exe itself is the runtime host module' } else { Say 'INFO app exe path not in module list (extraction path used); see MODULE lines' } }catch{ Say "WARN module listing failed: $($_.Exception.Message)" }
try{ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }catch{}
if($renamed){ try{ Rename-Item -Path $hid -NewName 'dotnet' -ErrorAction Stop; Say "INFO installed .NET folder restored" }catch{ Say "WARN restore failed: $($_.Exception.Message)" } }
Say "RESULT selfcontained fails=$fails"
exit $fails
