# Blocking parse gate: fails the job (exit 1) if any given PowerShell file has a syntax error, or calls a command that is neither defined in the file nor available. Runs BEFORE the app is launched.
param([Parameter(Mandatory=$true)][string[]]$Files)
$Files=@($Files | ForEach-Object { $_ -split "," } | Where-Object { $_ })
$bad=0
# v3: functions defined in ANY of the given files count as defined (a driver may dot-source a helper library given in the same list)
$allDefs=@(); foreach($f0 in $Files){ $t0=$null; $e0=$null; $a0=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f0).Path,[ref]$t0,[ref]$e0); if($e0.Count -eq 0){ $allDefs+=@($a0.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | ForEach-Object { $_.Name }) } }
foreach($f in $Files){
  $t=$null; $e=$null; $ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f).Path,[ref]$t,[ref]$e)
  if($e.Count -gt 0){ foreach($x in $e){ Write-Output "PARSE ERROR $f line $($x.Extent.StartLineNumber): $($x.Message)" }; $bad++; continue }
  $defs=@($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | ForEach-Object { $_.Name })
  foreach($c in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.CommandAst]},$true)){
    $n=$c.GetCommandName(); if(-not $n){ continue }
    if(($defs -contains $n) -or ($allDefs -contains $n)){ continue }; if(Get-Command $n -ErrorAction SilentlyContinue){ continue }; if(@('Get-WinEvent') -contains $n){ continue }   # Windows-only cmdlet, present on windows-2022
    Write-Output "UNDEFINED COMMAND '$n' in $f line $($c.Extent.StartLineNumber)"; $bad++ }
  if($bad -eq 0){ Write-Output "PASS parse gate $f (functions: $($defs.Count))" }
}
if($bad -gt 0){ Write-Output "FAIL parse gate: $bad problem(s); app not launched"; exit 1 }
