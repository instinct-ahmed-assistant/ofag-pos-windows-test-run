param([Parameter(Mandatory=$true)][string]$Exe,[string]$OutDir)
$ErrorActionPreference='Continue'; $fails=0
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$dest=Join-Path $env:RUNNER_TEMP 'inst-dest'
& (Join-Path $PSScriptRoot '..\installer\Install.ps1') -Exe $Exe -Dest $dest -NoLaunch
$t=Join-Path $dest 'OneForAllGood.Pharmacy.TRIAL.exe'
if(Test-Path $t){ Write-Host "PASS installed exe exists" } else { Write-Host "FAIL installed exe missing"; $fails++ }
$lnk=Join-Path ([Environment]::GetFolderPath('Desktop')) 'One For All Good TRIAL.lnk'
if(Test-Path $lnk){ Write-Host "PASS desktop shortcut exists" } else { Write-Host "FAIL desktop shortcut missing"; $fails++ }
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing
$p=Start-Process $t -PassThru
function Tops(){ $c=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty,$p.Id); return @([System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,$c)) }
function Snap($n){ try{ $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size); $f=Join-Path $OutDir $n; $bmp.Save($f,[System.Drawing.Imaging.ImageFormat]::Png); Write-Host "SCREENSHOT $f" }catch{ Write-Host "WARN screenshot failed: $($_.Exception.Message)" } }
$dlg=$null; $end=(Get-Date).AddSeconds(40); do{ foreach($w in (Tops)){ if($w.Current.ClassName -eq '#32770'){ $dlg=$w } }; if(-not $dlg){ Start-Sleep -Milliseconds 400 } }while(-not $dlg -and (Get-Date) -lt $end)
if($dlg){ Write-Host "PASS installed exe shows its start dialog [$($dlg.Current.Name)]"; Snap 'inst-01-start-dialog.png'; try{ $dlg.SetFocus() }catch{}; Start-Sleep -Milliseconds 500; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}') } else { Write-Host "FAIL installed exe showed no start dialog in 40 s"; $fails++ }
$main=$null; $end=(Get-Date).AddSeconds(40); do{ foreach($w in (Tops)){ if($w.Current.ClassName -ne '#32770' -and $w.Current.Name){ $main=$w } }; if(-not $main){ Start-Sleep -Milliseconds 500 } }while(-not $main -and (Get-Date) -lt $end)
if($main){ Write-Host "PASS main window after dismissing the dialog: [$($main.Current.Name)]" } else { Write-Host "FAIL no main window after dismissing the dialog"; $fails++ }
Start-Sleep 3; Snap 'inst-02-main-window.png'
if(-not $p.HasExited){ Write-Host "PASS installed exe is still running" } else { Write-Host "FAIL installed exe exited"; $fails++ }
try{ Stop-Process -Id $p.Id -Force }catch{}
if($fails -gt 0){ Write-Host "RESULT FAILED fails=$fails"; exit 1 } else { Write-Host "RESULT all assertions passed" }
