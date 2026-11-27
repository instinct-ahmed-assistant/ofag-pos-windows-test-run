# l118 native fresh-default-layout probe. Derived from the l116 stocktake probe helpers (unchanged). Seeds a FRESH database with the new SeedFresh seeder (identical to the pinned SeedSr except that it does NOT switch the new layout on), launches the TRIAL exe, signs in as owner WITHOUT touching any setting, and records the default screens. SYNTHETIC data only.
# Proves (or reports FAIL/NOTEXECUTED): G1 English-header Products import, G2 Arabic-header suggestion shown in the mapping grid and imported, G3 float-artifact prices land as exact cents, G4 a second confirm of the same loaded file is refused with no DB change, G5 a file with one bad row is refused whole with no DB change, G6 Purchases import then an intentional second purchase with a new purchase_ref, G7 two price-like headers: no import without a manual choice; plus export read-back of the imported rows.
# NOT proven: arbitrary files, manual column choice in the mapping grid (EXCLUDED-SCOPE), Sales and OpeningStock modes natively, barcode text traps (OBSERVED literal behaviour offline only, an unresolved review item), English-mode UI, DPI, real data. UIA bounds are not pixel proof; screenshots are for human inspection.
param([Parameter(Mandatory=$true)][string]$Zip,[Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$ExpectZipSha,[Parameter(Mandatory=$true)][string]$ExpectExeSha,[Parameter(Mandatory=$true)][string]$SeedExe,[Parameter(Mandatory=$true)][string]$ExpectSeedSha,[Parameter(Mandatory=$true)][string]$SnapExe,[Parameter(Mandatory=$true)][string]$ExpectSnapSha,[Parameter(Mandatory=$true)][string]$FixDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log=Join-Path $OutDir 'trial-flow-result.txt'
$script:XimpVersion='v4'; . (Join-Path $PSScriptRoot 'ximp-expect.ps1'); . (Join-Path $PSScriptRoot 'l116-expect.ps1'); $script:Boxes=@{}
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing
$AE=[System.Windows.Automation.AutomationElement]; $TS=[System.Windows.Automation.TreeScope]
$script:fails=0; $script:halt=$false; $script:everHalted=$false; $script:notexec=0; $script:abort=$false
# ---- helpers (copied verbatim from the restart-export driver by the kit build) ----
function Say($m){ $l=(Get-Date -Format o)+' '+$m; Add-Content -Path $log -Value $l; Write-Host $l; if(([string]$m) -like 'NOTEXECUTED*'){ $script:notexec=[int]$script:notexec+1 } }
function Neutral(){ try{ [System.Windows.Forms.Cursor]::Position=New-Object System.Drawing.Point(500,8) }catch{} }
function Shot($name){ try{ Neutral; Start-Sleep -Milliseconds 400; $b=[System.Windows.Forms.SystemInformation]::VirtualScreen; $bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height; $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size); $bmp.Save((Join-Path $OutDir ($name+'.png')),[System.Drawing.Imaging.ImageFormat]::Png); Say "SCREENSHOT $name.png ($($b.Width)x$($b.Height))" }catch{ Say "WARN screenshot $name failed: $($_.Exception.Message)" } }
function TopWins($procId){ $c=New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty,$procId); return @($AE::RootElement.FindAll($TS::Children,$c)) }
function Dump($w,$name){ try{ $all=$w.FindAll($TS::Descendants,[System.Windows.Automation.Condition]::TrueCondition); $lines=@("window: name=$($w.Current.Name) elements=$($all.Count)"); foreach($e in $all){ $lines+=("{0}|id={1}|name={2}|offscreen={3}" -f $e.Current.ControlType.ProgrammaticName,$e.Current.AutomationId,$e.Current.Name,$e.Current.IsOffscreen) }; $lines | Set-Content -Path (Join-Path $OutDir ($name+'-uia.txt')) -Encoding UTF8 }catch{ Say "WARN dump $name failed" } }
function ById($root,$id,$sec){ $c=New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty,$id); $end=(Get-Date).AddSeconds($sec); do{ $e=$root.FindFirst($TS::Descendants,$c); if($e){return $e}; Start-Sleep -Milliseconds 250 }while((Get-Date) -lt $end); return $null }
function Bounds($w,$tag){ try{ $r=$w.Current.BoundingRectangle; $wa=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $bottom=$r.Y+$r.Height; Say ("BOUNDS $tag window x=$([int]$r.X) y=$([int]$r.Y) w=$([int]$r.Width) h=$([int]$r.Height) bottom=$([int]$bottom); workarea x=$($wa.X) y=$($wa.Y) w=$($wa.Width) h=$($wa.Height) bottom=$($wa.Bottom); overflow_px=$([int]([math]::Max(0,$bottom-$wa.Bottom)))") }catch{ Say "WARN bounds $tag failed" } }
function Patterns($e){ try{ return (($e.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) -join ',') }catch{ return '?' } }
function FindModal(){ foreach($w in (TopWins $p.Id)){ if($w.Current.ClassName -eq '#32770'){ return $w } }
  $c=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window); foreach($m in @($main.FindAll($TS::Descendants,$c))){ $hasBtn=$false; foreach($k in @($m.FindAll($TS::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){ if(@('1','2','6','7') -contains $k.Current.AutomationId -and $k.Current.ClassName -ne 'tooltips_class32' -and @('Yes','No','OK','Cancel') -contains $k.Current.Name){ $hasBtn=$true } }; if($hasBtn){ return $m } }; return $null }
function Halt($why){ $script:everHalted=$true; if(-not $script:halt){ $script:halt=$true; Say "HALT $why; all dependent actions are skipped"; try{ DumpLockLog "halt" }catch{} } }
# one exit verdict for the whole run: any failure, any halt that ever happened (sticky, never cleared), any NOTEXECUTED step or an abort makes the exit non-zero
function Verdict(){ if($script:fails -gt 0 -or $script:halt -or $script:everHalted -or ([int]$script:notexec -gt 0) -or $script:abort){ return 1 }; return 0 }
function Guard($tag){ if($script:halt){ Say "SKIPPED $tag (halted)"; return $false }; if(FindModal){ Halt "$tag blocked: an unexpected modal is open"; Shot "dlg-unexpected-before-$tag"; return $false }; return $true }
$script:ssTries=@{}
# l144: lock diagnostics and re-login. The app writes every lock reason to %TEMP%\OneForAllGood-lock.log; print it, and if the login form is showing (account was locked) sign in again as owner, at most 3 times per run, and log it. A re-login does not restore the page that was open, so the caller still reports its own result.
# l149: restart between big sections so every Sales-dependent block starts on the FIRST page entry after a fresh login (v44-v48: after leaving Sales and re-entering it the UIA tree kept the previous page). The database persists across the restart (shift, stock and sales state continue). Not run when the run is halted; a failed relaunch or login is a FAIL and halts, never silent.
function RestartApp($tag){
  if($script:halt){ Say "NOTEXECUTED restart $tag : run halted"; return $false }
  try{ Sanitize "before-restart-$tag"; Say "DIAG RestartApp $tag : closing the app and starting a fresh instance"
    try{ $script:p.CloseMainWindow() | Out-Null; Start-Sleep 3; if(-not $script:p.HasExited){ $script:p.Kill() } }catch{}; Start-Sleep 2
    $script:mainHwnd=0; $script:lastNav=$null; $script:ssTries=@{}
    Launch "launch-$tag"; if($script:halt -or -not $main){ Say "FAIL restart $tag : app did not relaunch"; $script:fails++; Halt "restart $tag"; return $false }
    $ok=Login 'owner' $pwOwner "owner-$tag"; if(-not $ok){ Say "FAIL restart $tag : login after relaunch failed"; $script:fails++; return $false }
    Say "DIAG RestartApp $tag : fresh instance signed in"; return $true
  }catch{ Say "FAIL restart $tag : $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber))"; $script:fails++; return $false } }
$script:reLogins=0
# l148: re-find the main window element from its HWND (a cached element can keep describing an earlier page). Called after every successful page switch and before the scroll fallback.
$script:mainHwnd=0
function ReanchorMain($why){
  try{ if($script:mainHwnd -eq 0 -and $main){ $script:mainHwnd=[int64]$main.Current.NativeWindowHandle }; if($script:mainHwnd -eq 0){ return }
    $e=[System.Windows.Automation.AutomationElement]::FromHandle([System.IntPtr]$script:mainHwnd); if($e){ $script:main=$e; Say "DIAG ReanchorMain ($why): main re-found from HWND $($script:mainHwnd)" }
  }catch{ Say "INFO ReanchorMain ($why) failed: $($_.Exception.Message)" } }
# l145: a real mouse click is only made when the whole element lies inside its nearest vertically scrollable ancestor (the rail viewport), below the header band (Tabs top), and not on the lock/logout button. v46 clicked a rail item that had scrolled under the header and hit the lock-account button.
function SafeRailClickOk($el,$tag){
  try{ try{ $el.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 300 }catch{}
    $b=$el.Current.BoundingRectangle; if($b.IsEmpty -or $b.Width -lt 5 -or $b.Height -lt 5){ Say "DIAG $tag click guard: element has no usable bounds"; return $false }
    $cx=$b.X+$b.Width/2; $cy=$b.Y+$b.Height/2
    $w=[System.Windows.Automation.TreeWalker]::ControlViewWalker; $a=$w.GetParent($el); $cont=$null
    while($a -and -not [object]::ReferenceEquals($a,$main) -and $a.Current.ControlType -ne [System.Windows.Automation.ControlType]::Window){ $ok=$false; try{ $ok=[bool]$a.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern).Current.VerticallyScrollable }catch{}; if($ok){ $cont=$a; break }; $a=$w.GetParent($a) }
    if($cont){ $c=$cont.Current.BoundingRectangle; if($b.Y -lt ($c.Y+2) -or ($b.Y+$b.Height) -gt ($c.Y+$c.Height-2)){ Say "DIAG $tag click guard: element y=$([int]$b.Y)..$([int]($b.Y+$b.Height)) is not fully inside its scroll container y=$([int]$c.Y)..$([int]($c.Y+$c.Height)); click skipped"; return $false } } else { Say "DIAG $tag click guard: no scrollable ancestor found" }
    $tb=ById $main 'Tabs' 0; if($tb){ $t=$tb.Current.BoundingRectangle; if($cy -lt $t.Y){ Say "DIAG $tag click guard: point y=$([int]$cy) is above the page area (header band, Tabs top y=$([int]$t.Y)); click skipped"; return $false } }
    $lo=ById $main 'LogoutButton' 0; if($lo){ $l=$lo.Current.BoundingRectangle; if(-not $l.IsEmpty -and $cx -ge ($l.X-6) -and $cx -le ($l.X+$l.Width+6) -and $cy -ge ($l.Y-6) -and $cy -le ($l.Y+$l.Height+6)){ Say "DIAG $tag click guard: point is on the lock/logout button; click skipped"; return $false } }
    return $true
  }catch{ Say "DIAG $tag click guard error (click skipped): $($_.Exception.Message)"; return $false } }
$script:lastNav=$null; $script:inRestore=$false
function DumpLockLog($tag){ try{ $ll=Join-Path ([System.IO.Path]::GetTempPath()) 'OneForAllGood-lock.log'; if(Test-Path $ll){ $lt=Get-Content -Raw $ll; if($lt.Length -gt 4000){ $lt=$lt.Substring($lt.Length-4000) }; Say "DIAG $tag app lock log: $($lt -replace '\r?\n',' | ')" } else { Say "DIAG $tag app lock log: file not present (no lock was recorded by the app)" } }catch{ Say "INFO $tag lock log unreadable: $($_.Exception.Message)" } }
function ReLogin($why){
  try{ if($script:reLogins -ge 3){ return $false }
    $lu=ById $main 'LoginUsername' 0; if(-not $lu){ return $false }; $tb=ById $main 'Tabs' 0; if($tb -and -not $tb.Current.IsOffscreen){ return $false }
    $script:reLogins++; Say "DIAG RELOGIN the login form is showing ($why); app was locked. Re-login $($script:reLogins) of 3"; DumpLockLog 'relogin'
    $ok=Login 'owner' $pwOwner "relogin$($script:reLogins)"; Say "DIAG RELOGIN result ok=$ok"; if($ok -and $script:lastNav -and -not $script:inRestore){ $script:inRestore=$true; try{ $ln=$script:lastNav; Say "DIAG RELOGIN restoring page $($ln.tag)"; $rr=NavTo $ln.labels "restore-$($ln.tag)" $ln.pageId $ln.topId; Say "DIAG RELOGIN page restore ok=$rr" }finally{ $script:inRestore=$false } }; return [bool]$ok
  }catch{ Say "INFO ReLogin failed (script line $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)"; return $false } }
# l144: when an AutomationId is not found after the normal lookup, scroll every ScrollPattern container under the main window (0%, 100%, then 25/50/75%), re-find after each container move, and log container, percent and result. Capped at 6 searches per id. Still not found stays not found (callers report NOTEXECUTED or FAIL); this never fabricates an element.
function ScrollSearch($id,$why){
  try{ $k=[string]$id; if(-not $script:ssTries.ContainsKey($k)){ $script:ssTries[$k]=0 }; $script:ssTries[$k]++; if($script:ssTries[$k] -gt 6){ return $null }
    $cs=@($main.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::IsScrollPatternAvailableProperty,$true))))
    Say "DIAG ScrollSearch $id ($why) try $($script:ssTries[$k]): $($cs.Count) scroll containers"
    foreach($sid in @('SalesScroll','SettingsScroll')){ $se=ById $main $sid 0; if($se){ try{ $sp0=$se.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern); $vp=-1; try{ $vp=$sp0.Current.VerticalScrollPercent }catch{}; $sp0.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll,0); Start-Sleep -Milliseconds 300; $e0=ById $main $id 0; Say "DIAG ScrollSearch $id named scroller $sid was at $vp%, set to 0%: found=$([bool]$e0)"; if($e0){ return $e0 } }catch{ Say "DIAG ScrollSearch $id named scroller $sid not scrollable: $($_.Exception.Message)" } } }
    foreach($pct in @(0,100,25,50,75)){ $ci=0
      foreach($c in $cs){ $ci++; $sp=$null; try{ $sp=$c.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern) }catch{ continue }
        $vs=$false; try{ $vs=$sp.Current.VerticallyScrollable }catch{}; if(-not $vs){ continue }
        $cid=''; $cls=''; try{ $cid=$c.Current.AutomationId; $cls=$c.Current.ClassName }catch{}
        try{ $sp.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll,[double]$pct) }catch{ Say "DIAG ScrollSearch $id container $ci id=[$cid] class=[$cls] set $pct% failed: $($_.Exception.Message)"; continue }
        Start-Sleep -Milliseconds 300
        $e=ById $main $id 0; Say "DIAG ScrollSearch $id container $ci id=[$cid] class=[$cls] at $pct%: found=$([bool]$e)"
        if($e){ return $e } } }
    Say "DIAG ScrollSearch ${id}: not found after all containers and percents"
  }catch{ Say "INFO ScrollSearch $id failed (script line $($_.InvocationInfo.ScriptLineNumber)): $($_.Exception.Message)" }
  return $null }
# l164: Pick fallback. Controls inside the collapsed InvMoreExpander (header: المزيد من الإجراءات) or the collapsed InvSidePanel are absent from UIA (first real l162 run: ItemCardButton, LoyaltyButton, BusinessToolsButton, PriceTiersButton, DraftReceiveButton not found). Pick expands the expander and, if still not found, opens the side panel, once, then looks again. Quiet: no Halt or FAIL here; the caller reports a miss.
function ExpandMoreQuiet($id){
  try{
    $x=ById $main 'InvMoreExpander' 1
    if($x){ $ec=$x.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern); $st=[string]$ec.Current.ExpandCollapseState
      if($st -ne 'Expanded'){ $ec.Expand(); Start-Sleep -Milliseconds 900; Say "INFO pick: InvMoreExpander expanded to look for $id" }
      $e=ById $main $id 2; if($e){ return $e } }
    # ItemCardButton, PriceTiersButton, DraftReceiveButton and the bonus fields live in InvSidePanel, which starts Collapsed (and so absent from UIA) until InvPanelToggleButton is pressed. Press it only when the panel is not showing (ProductName absent), so a second call never closes it.
    $pn=ById $main 'ProductName' 1
    if(-not $pn){ $tg=ById $main 'InvPanelToggleButton' 2
      if($tg){ $tg.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 1200; Say "INFO pick: InvPanelToggleButton pressed to open the side panel while looking for $id" } }
    return (ById $main $id 3)
  }catch{ Say "INFO pick: expander/side panel fallback failed for ${id}: $($_.Exception.Message)"; return $null } }
function Pick($id,$sec){ $e=ById $main $id $sec; if(-not $e){ if(ReLogin "Pick $id"){ $e=ById $main $id 3 } }; if(-not $e){ ReanchorMain "Pick $id"; $e=ById $main $id 1 }; if(-not $e){ $e=ExpandMoreQuiet $id }; if(-not $e){ $e=ScrollSearch $id 'Pick' }; return $e }
function Sel($id,$tag){ if(-not (Guard $tag)){ Halt "$tag failed"; return $false }; $e=Pick $id 8; if(-not $e){ Say "NOTEXECUTED tab $tag"; Halt "$tag failed"; return $false }; try{ $e.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 1200; Say "TAB $tag"; return $true }catch{ Say "NOTEXECUTED tab $tag select failed"; Halt "$tag failed"; return $false } }
function Check($ok,$msg){ if($ok){ Say "PASS $msg" } else { Say "FAIL $msg"; $script:fails++ } }
function TxtOf($id){ $e=Pick $id 3; if($e){ return $e.Current.Name } else { return '(missing)' } }
function Rows($gridId){ $g=Pick $gridId 8; if(-not $g){ return $null }; return @($g.FindAll($TS::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::DataItem)))) }
function CellNames($row){ if($null -eq $row){ return @() }; return @($row.FindAll($TS::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Custom))) | ForEach-Object { $_.Current.Name }) }
function GridRows($id){ $g=Pick $id 5; if(-not $g){ return $null }; $o=@(); foreach($r in (Rows $id)){ if($null -eq $r){ continue }; $o+=,@(CellNames $r) }; return ,$o }   # leading comma keeps a single row from unrolling into its cells
# ---- end helpers ----
# ---- end helpers ----
Add-Type -Namespace M -Name U -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void mouse_event(uint f,uint dx,uint dy,uint d,System.UIntPtr e);'
# Observed (r90v3 dump and log): each rail RadioButton has an empty UIA name and two child Texts: an icon glyph in the Private Use Area (e.g. U+E7BF) and then the label. Label = the child text left after removing private-use glyph characters and surrounding whitespace; it must be exactly one non-empty text, otherwise the item has NO usable label (never joined, never matched loosely). The same function feeds navigation and the Cashier checks.
function RailLabel($texts){ $c=@(@($texts) | ForEach-Object { ([regex]::Replace([string]$_,'[\uE000-\uF8FF]','')).Trim() } | Where-Object { $_ -ne '' }); if($c.Count -eq 1){ return $c[0] } else { return '' } }
# Return-shape convention for every list-returning helper here: emit the items UNROLLED (return $o); EVERY caller wraps the call in @(...) so 0, 1 and n items all give a real array with the right .Count.
# Pure: indexes of items whose normalized label equals one of the wanted labels EXACTLY (no substring; a group header or a longer label never matches).
function RailMatch($labels,$wanted){ $o=@(); for($i=0;$i -lt @($labels).Count;$i++){ if(@($wanted) -ccontains @($labels)[$i]){ $o+=$i } }; return $o }
function RailItems(){ $tc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::RadioButton); $o=@(); $mr=$main.Current.BoundingRectangle; foreach($rb in @($main.FindAll($TS::Descendants,$tc))){ $br=$rb.Current.BoundingRectangle; if(-not $br.IsEmpty -and -not $mr.IsEmpty -and ($br.X+$br.Width/2) -lt ($mr.X+0.75*$mr.Width)){ continue }; $t=@($rb.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))) | ForEach-Object { $_.Current.Name }); $o+=[pscustomobject]@{ El=$rb; Label=(RailLabel $t); Raw=(($t | ForEach-Object { 'U+' + (($_.ToCharArray() | Select-Object -First 1 | ForEach-Object { '{0:X4}' -f [int]$_ }) -join '') + ':' + $_.Trim() }) -join ' / '); Off=$rb.Current.IsOffscreen } }; return $o }
function RailItemsEnglish(){ $tc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::RadioButton); $o=@(); $mr=$main.Current.BoundingRectangle; foreach($rb in @($main.FindAll($TS::Descendants,$tc))){ $br=$rb.Current.BoundingRectangle; if(-not $br.IsEmpty -and -not $mr.IsEmpty -and ($br.X+$br.Width/2) -gt ($mr.X+0.25*$mr.Width) -and ($br.X+$br.Width/2) -lt ($mr.X+0.75*$mr.Width)){ continue }; $t=@($rb.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))) | ForEach-Object { $_.Current.Name }); $o+=[pscustomobject]@{ El=$rb; Label=(RailLabel $t); Raw=(($t | ForEach-Object { 'U+' + (($_.ToCharArray() | Select-Object -First 1 | ForEach-Object { '{0:X4}' -f [int]$_ }) -join '') + ':' + $_.Trim() }) -join ' / '); Off=$rb.Current.IsOffscreen } }; return $o }
function RailDiag($tag){ $tabs=@($main.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)))); Say "DIAG $tag TabItem elements in the UIA tree: $($tabs.Count) [$(($tabs | ForEach-Object { $_.Current.AutomationId + '=' + $_.Current.Name }) -join ' | ')]"; $r=@(RailItems); Say "DIAG $tag rail RadioButtons: $($r.Count) [$(($r | ForEach-Object { $_.Label + ' {' + $_.Raw + '}' + $(if($_.Off){' (offscreen)'}) }) -join ' | ')]"; return $r }
# pure verdict (mocked): the page is "up" only when its rail item is the selected one AND, when a page-top element is named, that element exists and lies inside the window; the page's own later content may sit below the fold and is NOT required to be on screen here (ScrollPanel proves that afterwards)
function Roots(){ $o=@(); foreach($w in (TopWins $p.Id)){ if($w.Current.ClassName -ne '#32770'){ $o+=$w } }; return $o }
function RootDesc($w){ try{ return "hwnd=$($w.Current.NativeWindowHandle) name=[$($w.Current.Name)] rid=$(($w.GetRuntimeId()) -join '.')" }catch{ return 'unreadable (stale?)' } }
# find an element under the current main window; if absent, under every other top-level window of the process, then re-anchor $main on the root that has it (logged). Diagnoses a stale or replaced window root after language change / relogin.
function FindAny($id,$sec){ $e=ById $main $id $sec; if($e){ return $e }
  if(ReLogin "FindAny $id"){ $e=ById $main $id 3; if($e){ return $e } }
  $e=ScrollSearch $id 'FindAny'; if($e){ return $e }
  $rs=@(Roots); Say "DIAG FindAny $id not under main [$(RootDesc $main)]; top-level windows of the process: $($rs.Count)"; foreach($r in $rs){ Say "DIAG   root $(RootDesc $r)" }
  foreach($r in $rs){ $x=ById $r $id 2; if($x){ Say "DIAG FindAny $id FOUND under root $(RootDesc $r); re-anchoring main on it"; $script:main=$r; return $x } }
  return $null }
# diagnostic (different path from tree search): hit-test the window at a grid of screen points (ElementFromPoint) and log what UIA reports there, with the ancestor chain, to learn whether the page content is reachable at all
function PointScan($tag){ try{ $w=$main.Current.BoundingRectangle; $seen=@{}; $n=0
    foreach($y in 160,260,360,420,480,540,600,650){ foreach($x in 330,480,630,780,930){ if($x -gt $w.Right -or $y -gt $w.Bottom){ continue }; $n++
        try{ $e=[System.Windows.Automation.AutomationElement]::FromPoint((New-Object System.Windows.Point($x,$y))); if($e){ $chain=@(); $a=$e; $k=0; $wk=[System.Windows.Automation.TreeWalker]::RawViewWalker; while($a -and $k -lt 12){ $chain+=("{0}/{1}" -f $a.Current.ControlType.ProgrammaticName.Replace('ControlType.',''),$a.Current.AutomationId); $a=$wk.GetParent($a); $k++ }
          Say ("DIAG POINTSCAN {0} ({1},{2}) pid={3} name=[{4}] chain: {5}" -f $tag,$x,$y,$e.Current.ProcessId,$e.Current.Name,($chain -join ' < ')); if($e.Current.AutomationId){ $seen[$e.Current.AutomationId]=1 } } }catch{ Say "INFO POINTSCAN $x,$y failed: $($_.Exception.Message)" } } }
    Say "DIAG POINTSCAN $tag points=$n distinct automation ids hit: $((@($seen.Keys) | Sort-Object) -join ',')" }catch{ Say "INFO PointScan failed: $($_.Exception.Message)" } }
function DumpAll($tag){ $i=0; foreach($r in @(Roots)){ $i++; Dump $r "$tag-root$i" }; Dump $main "$tag-main" }
function NavVerdict($railSelected,$pageFound,$topNeeded,$topFound,$topInWindow){ if(-not $railSelected){ return $false }; if(-not $pageFound){ return $false }; if($topNeeded){ return ($topFound -and $topInWindow) }; return $true }
function InWin($e){ $r=$e.Current.BoundingRectangle; $w=$main.Current.BoundingRectangle; return ($r.Width -gt 0 -and $r.Height -gt 0 -and $r.Right -gt $w.Left -and $r.Left -lt $w.Right -and $r.Bottom -gt $w.Top -and $r.Top -lt $w.Bottom) }
function PageUp($id,$topId,$rb){ $sel=$false; try{ $sel=[bool]$rb.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }catch{}
  $e=FindAny $id 4; $t=$null; $tin=$false; if($topId){ $t=FindAny $topId 4; if($t){ $tin=(InWin $t) } }
  $ein=$false; if($e){ $ein=(InWin $e) }
  Say "DIAG PageUp rail_selected=$sel page_element[$id] found=$([bool]$e) inWindow=$ein offscreenFlag=$(if($e){$e.Current.IsOffscreen}) top_element[$topId] found=$([bool]$t) inWindow=$tin"
  return (NavVerdict $sel ([bool]$e) ([bool]$topId) ([bool]$t) $tin) }

function Logout(){ $lo=Pick 'LogoutButton' 5; if(-not $lo){ Say 'FAIL LogoutButton not found'; $script:fails++; Halt 'logout'; return $false }
  try{ $lo.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 3; Say 'STEP logout invoked' }catch{ Say "FAIL logout invoke failed: $($_.Exception.Message)"; $script:fails++; Halt 'logout'; return $false }
  $m=FindModal; if($m){ Say "INFO modal after logout: $($m.Current.Name)"; Shot 'dlg-logout'; Halt 'unexpected modal after logout (not answered blindly)'; return $false }; return $true }
# Scroll the page so the whole unassigned panel (title, note, total, header and ALL rows) is inside the window, proven by bounds, then capture.
function PanelFit($win){ $g=Pick 'SupUnassignedGrid' 3; if(-not $g){ return @{ ok=$false; why='grid not found' } }; $rows=@(Rows 'SupUnassignedGrid'); if($rows.Count -lt 1){ return @{ ok=$false; why='no rows' } }
  $wb=$win.Current.BoundingRectangle; $bottom=$wb.Y+$wb.Height-4; $last=$rows[$rows.Count-1].Current.BoundingRectangle; $ok=($last.Y+$last.Height -le $bottom) -and (-not $rows[$rows.Count-1].Current.IsOffscreen) -and ($last.Height -gt 0)
  return @{ ok=$ok; lastBottom=[int]($last.Y+$last.Height); winBottom=[int]$bottom; rows=$rows.Count } }
function ScrollPanel($tag,$shot){
  $w=$main; $f=PanelFit $w; Say "DIAG $tag panel fit before scroll: ok=$($f.ok) lastRowBottom=$($f.lastBottom) windowBottom=$($f.winBottom) rows=$($f.rows) $($f.why)"
  if(-not $f.ok){
    try{ $rr=@(Rows 'SupUnassignedGrid'); $rr[$rr.Count-1].GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 900 }catch{ Say "INFO $tag ScrollItem unavailable: $($_.Exception.Message)" }
    $f=PanelFit $w; Say "DIAG $tag panel fit after ScrollItem: ok=$($f.ok) lastRowBottom=$($f.lastBottom) windowBottom=$($f.winBottom)" }
  if(-not $f.ok){
    $g=Pick 'SupUnassignedGrid' 3; $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker; $a=$walker.GetParent($g); $tries=0; $sv=$null
    while($a -and $tries -lt 25){ $tries++; try{ $sp=$a.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern); if($sp.Current.VerticallyScrollable){ $sv=$sp; Say "INFO $tag scrollable ancestor found (up $tries levels): class=$($a.Current.ClassName) id=$($a.Current.AutomationId) vpercent=$([math]::Round($sp.Current.VerticalScrollPercent,1))"; break } }catch{}; $a=$walker.GetParent($a) }
    if($sv){ for($i=0;$i -lt 8 -and -not $f.ok;$i++){ try{ $sv.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount,[System.Windows.Automation.ScrollAmount]::LargeIncrement); Start-Sleep -Milliseconds 700 }catch{ Say "INFO $tag scroll step failed: $($_.Exception.Message)"; break }; $f=PanelFit $w; Say "DIAG $tag after scroll step $($i+1): ok=$($f.ok) lastRowBottom=$($f.lastBottom) vpercent=$([math]::Round($sv.Current.VerticalScrollPercent,1))" } }
    else { Say "INFO $tag no vertically scrollable ancestor found within 25 levels" } }
  Shot $shot
  foreach($id in 'SupUnassignedTitle','SupUnassignedNote','SupUnassignedTotal','SupUnassignedGrid'){ $e=Pick $id 2; if($e){ $r=$e.Current.BoundingRectangle; Say ("BOUNDS {0} {1} x={2} y={3} w={4} h={5} offscreen={6}" -f $tag,$id,[int]$r.X,[int]$r.Y,[int]$r.Width,[int]$r.Height,$e.Current.IsOffscreen) } }
  $ri=0; foreach($row in @(Rows 'SupUnassignedGrid')){ $ri++; $r=$row.Current.BoundingRectangle; Say ("BOUNDS {0} row{1} y={2} h={3} offscreen={4}" -f $tag,$ri,[int]$r.Y,[int]$r.Height,$row.Current.IsOffscreen) }
  $gg=Pick 'SupUnassignedGrid' 2; if($gg){ $gr=$gg.Current.BoundingRectangle; $wr=$w.Current.BoundingRectangle; $hs=@($gg.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::HeaderItem)))); $bad=0; $hi=0
    foreach($h in $hs){ $hi++; $hr=$h.Current.BoundingRectangle; Say ("BOUNDS {0} header{1} [{2}] left={3} right={4} w={5} (grid left={6} right={7}, window right={8})" -f $tag,$hi,$h.Current.Name,[int]$hr.Left,[int]$hr.Right,[int]$hr.Width,[int]$gr.Left,[int]$gr.Right,[int]$wr.Right); if($hr.Width -gt 0 -and ($hr.Right -gt $gr.Right+1 -or $hr.Left -lt $gr.Left-1 -or $hr.Right -gt $wr.Right)){ $bad++ } }
    $mins=@(90,100,90,88,92,100); $narrow=@(); for($i=0;$i -lt [math]::Min($hs.Count,6);$i++){ $hw=[int]$hs[$i].Current.BoundingRectangle.Width; if($hw -lt $mins[$i]){ $narrow+="col$($i+1)=$hw<$($mins[$i])" } }; Check ($narrow.Count -eq 0) "${tag}: every column is at least its pixel-measured minimum width (date 100, Purchases header 88, cost 92; narrow: $($narrow -join ','))"
    Check ($hs.Count -ge 6 -and $bad -eq 0) "${tag}: all $($hs.Count) column headers (including the cost column) lie inside the grid and the window, no horizontal overflow (bad=$bad)" }
  Check $f.ok "${tag}: every unassigned-panel row is inside the window after scrolling (last row bottom $($f.lastBottom) <= window bottom $($f.winBottom)); see $shot.png" }
function GridVis($g){ $w=$main.Current.BoundingRectangle; $r=$g.Current.BoundingRectangle; $top=[math]::Max($r.Top,$w.Top); $bot=[math]::Min($r.Bottom,$w.Bottom); $vis=[math]::Max(0,$bot-$top); return @{ visible=[int]$vis; x=[int]$r.X; y=[int]$r.Y; w=[int]$r.Width; h=[int]$r.Height; ok=($r.Width -gt 0 -and $vis -ge 150 -and $r.Top -lt $w.Bottom) } }
function EnsureGridVisible($g,$tag){
  $v=GridVis $g; Say "DIAG $tag StockGrid on screen: visible_px=$($v.visible) bounds x=$($v.x) y=$($v.y) w=$($v.w) h=$($v.h) offscreenFlag=$($g.Current.IsOffscreen)"
  if(-not $v.ok){
    $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker; $a=$walker.GetParent($g); $n=0
    while($a -and $n -lt 25 -and -not $v.ok){ $n++; try{ $sp=$a.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern); if($sp.Current.VerticallyScrollable){ for($i=0;$i -lt 8 -and -not $v.ok;$i++){ $sp.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount,[System.Windows.Automation.ScrollAmount]::LargeIncrement); Start-Sleep -Milliseconds 600; $v=GridVis $g; Say "DIAG $tag scrolled ancestor $($a.Current.ClassName) step $($i+1): visible_px=$($v.visible) y=$($v.y)" } } }catch{}; if(-not $v.ok){ $a=$walker.GetParent($a) } }
  }
  Check $v.ok "$tag StockGrid is on screen with at least 150 px of its height inside the window (visible $($v.visible) px)"
  return $v }
# returns an explicit status: 'ok', 'visual-fail' (an isolated, non-mutating visual failure after a successful navigation; the FAIL counter was raised, no halt, process alive, no modal) or 'unsafe' (modal, dead process, failed or ambiguous navigation: the halt stays set) or 'skipped-halted'
function StockShot(){
  if($script:halt){ return 'skipped-halted' }
  if($p.HasExited){ Say 'FAIL process exited before the Sales/stock capture'; EarlyDiag 'sales-capture'; $script:fails++; $script:abort=$true; Halt 'process exited'; return 'unsafe' }
  if(FindModal){ Say 'FAIL unexpected modal before the Sales/stock capture'; $script:fails++; $script:abort=$true; Halt 'unexpected modal before the stock capture'; return 'unsafe' }
  $f0=$script:fails
  if(-not (NavTo @('البيع','Sales') 'sales-tab' 'StockGrid')){ if(-not $script:halt){ Halt 'sales navigation failed' }; $script:fails++; return 'unsafe' }
  if($script:halt){ return 'unsafe' }
  $g=Pick 'StockGrid' 6
  if($g){ [void](EnsureGridVisible $g 'sales-stock'); $rc=-1; try{ $rc=[int]$g.GetCurrentPattern([System.Windows.Automation.GridPattern]::Pattern).Current.RowCount }catch{}
    $rr=@(Rows 'StockGrid'); Say "DIAG sales page StockGrid: RowCount(GridPattern)=$rc realized rows=$($rr.Count) (the synthetic seed has 6 lots, one product)"; Shot '25-sales-stock-grid-visible'
    Check ($rc -lt 0 -or $rc -eq 6) "stock grid shows the 6 seeded lots (RowCount $rc)" } else { Say 'FAIL StockGrid not found on the Sales page'; $script:fails++ }
  if($script:fails -gt $f0){ return 'visual-fail' } else { return 'ok' } }
function NavTo($labels,$tag,$pageId,$topId=$null){
  $script:ssTries=@{}  # l146: the scroll-search cap is per page visit
  if(-not $script:inRestore){ $script:lastNav=@{ labels=$labels; tag=$tag; pageId=$pageId; topId=$topId } }
  if(-not (Guard $tag)){ Halt "$tag failed"; return $false }
  $r=@(RailDiag "$tag-before"); $idx=@(RailMatch @($r | ForEach-Object { $_.Label }) $labels); $m=@($idx | ForEach-Object { $r[$_] })
  if($m.Count -ne 1){ Say "NOTEXECUTED $tag rail item with label in [$($labels -join ',')]: found $($m.Count) (need exactly 1)"; Shot "dlg-$tag-rail-not-found"; Halt "$tag rail item"; return $false }
  $rb=$m[0].El; Say "INFO $tag rail item patterns=$(Patterns $rb) offscreen=$($m[0].Off)"
  try{ $sip=$rb.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern); $sip.Select(); Start-Sleep -Milliseconds 1500; Say "INFO $tag SelectionItemPattern.Select() called" }catch{ Say "INFO $tag SelectionItemPattern unavailable or failed: $($_.Exception.Message)" }
  if(PageUp $pageId $topId $rb){ ReanchorMain "after $tag"; Say "TAB $tag via SelectionItemPattern; page element $pageId visible"; return $true }
  try{ $rb.SetFocus(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait(' '); Start-Sleep -Milliseconds 1500 }catch{ Say "INFO $tag focus/space failed: $($_.Exception.Message)" }
  if(PageUp $pageId $topId $rb){ Say "TAB $tag via focus+Space; page element $pageId visible"; return $true }
  Say "INFO $tag Space did not bring the page up; one real mouse click at the rail item centre"; Shot "dlg-$tag-after-space"
  try{ if(-not (SafeRailClickOk $rb $tag)){ throw "mouse click skipped: target not safely inside the rail viewport" }; $b=$rb.Current.BoundingRectangle; $x=[int]($b.X+$b.Width/2); $y=[int]($b.Y+$b.Height/2); [void][M.U]::SetCursorPos($x,$y); Start-Sleep -Milliseconds 300; [M.U]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [M.U]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 1800; Neutral }catch{ Say "FAIL $tag mouse click failed: $($_.Exception.Message)" }
  if(PageUp $pageId $topId $rb){ Say "TAB $tag via one mouse click; page element $pageId visible"; return $true }
  Say "FAIL $tag page element $pageId not visible after Space and one click"; Shot "dlg-$tag-not-navigated"; DumpAll "dlg-$tag-not-navigated"; PointScan $tag; $script:fails++; Halt "$tag navigation"; return $false }

function Latin($t){ $x=[string]$t; $ar='٠١٢٣٤٥٦٧٨٩'; for($i=0;$i -lt 10;$i++){ $x=$x.Replace([string]$ar[$i],[string]$i) }; return $x.Replace('٫','.').Replace('٬','') }
function ReadXlsxSheet($path,$sheet){ $o=@{ ok=$false; why=''; rows=@() }
  try{ Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue; $zip=[System.IO.Compression.ZipFile]::OpenRead($path)
    try{ function Entry($n){ $e=$zip.GetEntry($n); if(-not $e){ return $null }; $sr=New-Object System.IO.StreamReader($e.Open(),[Text.Encoding]::UTF8); try{ return $sr.ReadToEnd() } finally{ $sr.Dispose() } }
      $wbx=Entry 'xl/workbook.xml'; $rel=Entry 'xl/_rels/workbook.xml.rels'; if(-not $wbx -or -not $rel){ $o.why='workbook parts missing'; return $o }
      $wb=[xml]$wbx; $rl=[xml]$rel; $sh=@($wb.SelectNodes("//*[local-name()='sheet']") | Where-Object { $_.GetAttribute('name') -ceq $sheet }); if($sh.Count -ne 1){ $o.why="sheet [$sheet] found $($sh.Count) times"; return $o }
      $rid=$sh[0].GetAttribute('id','http://schemas.openxmlformats.org/officeDocument/2006/relationships'); $tg=@($rl.SelectNodes("//*[local-name()='Relationship']") | Where-Object { $_.GetAttribute('Id') -ceq $rid }); if($tg.Count -ne 1){ $o.why='sheet relationship not found'; return $o }
      $t=$tg[0].GetAttribute('Target'); if($t.StartsWith('/')){ $t=$t.TrimStart('/') } else { $t='xl/'+$t }
      $ss=@(); $sst=Entry 'xl/sharedStrings.xml'; if($sst){ $sx=[xml]$sst; foreach($si in @($sx.SelectNodes("//*[local-name()='si']"))){ $ss+=((@($si.SelectNodes(".//*[local-name()='t']") | ForEach-Object { $_.InnerText }) -join '')) } }
      $sd=Entry $t; if(-not $sd){ $o.why="sheet part $t missing"; return $o }; $x=[xml]$sd; $rows=@()
      foreach($r in @($x.SelectNodes("//*[local-name()='row']"))){ $cells=@{}; $max=0
        foreach($c in @($r.SelectNodes("*[local-name()='c']"))){ $ref=$c.GetAttribute('r'); $col=0; foreach($ch in ($ref -replace '\d','').ToCharArray()){ $col=$col*26+([int][char]$ch-64) }; $ty=$c.GetAttribute('t'); $v=''
          if($ty -eq 's'){ $vn=$c.SelectSingleNode("*[local-name()='v']"); if($vn){ $v=$ss[[int]$vn.InnerText] } } elseif($ty -eq 'inlineStr'){ $v=((@($c.SelectNodes(".//*[local-name()='t']") | ForEach-Object { $_.InnerText }) -join '')) } else { $vn=$c.SelectSingleNode("*[local-name()='v']"); if($vn){ $v=$vn.InnerText } }
          $cells[$col]=$v; if($col -gt $max){ $max=$col } }
        $line=@(); for($i=1;$i -le $max;$i++){ if($cells.ContainsKey($i)){ $line+=[string]$cells[$i] } else { $line+='' } }; $rows+=,$line }
      $o.rows=$rows; $o.ok=$true; return $o } finally{ $zip.Dispose() } }catch{ $o.why=$_.Exception.Message; return $o } }

# ---- v6: conflicting-ref fixture (g8) and both-ref-columns-all-blank fixture (g9). Row-specific, wheel-bounded, DbSnap no-write. ----
function RefFixtureStep($tag,$file,$kind){
  $a=Snap "$tag-before"
  if(-not ((SetMode 'مشتريات نقدية' $tag) -and (OpenFile $file $tag))){ Excl "$tag fixture $file" 'NOTEXECUTED: the file could not be opened'; return }
  [void](SheetIs $tag 'Sheet1'); [void](ReadMap $tag)
  $refPat='^مرجع سطر شراء فريد'; $row=MapRow $tag $refPat; $wn=0; if(-not $row.found){ Shot "$tag-map-before-wheel" }
  while(-not $row.found -and $wn -lt 4){ $wn++; if(-not (WheelGrid $tag $wn)){ break }; $row=MapRow $tag $refPat }
  if($wn -gt 0){ Shot "$tag-map-after-wheel" }; Say "INFO $tag purchase_ref row lookup after $wn wheel notch(es): found=$($row.found) combo=[$($row.combo)] status=[$($row.status)] ($($row.why))"
  if($kind -ceq 'conflict'){ $vd=XRefRowVerdict $row.found $row.combo $row.status; $what='the purchase_ref row has an EMPTY chooser and its own status says more than one match' }
  else { $vd=XRefRowCanonical $row.found $row.combo $row.status '7'; $what='the purchase_ref row shows chooser [7: purchase_ref] and its own status names the canonical column' }
  if($vd -ceq 'NOTREALIZED'){ Excl "$tag row-specific check: $what" 'NOTEXECUTED: the purchase_ref row was not realized after the bounded wheel; absence is not a pass' }
  else { Check ($vd -ceq 'PASS') "$tag row-specific: $what (verdict $vd, chooser [$($row.combo)], status [$($row.status)])" }
  [void](SetConfirm $tag); $v=DoValidate $tag; Check ($v.refused -eq $true) "$tag validate refused"
  if($kind -ceq 'blank'){ Check (([string]$v.text) -match 'فارغ') "$tag the refusal names the blank required field (text [$($v.text -replace '\s+',' ')])" }
  else { Say "INFO $tag validate refusal text (not asserted beyond refused): [$($v.text -replace '\s+',' ')]" }
  $c=DoCommit $tag $false; Check ($c.refused -eq $true) "$tag commit refused"; $d=Snap "$tag-after"; CompareSnap $a $d "$tag $kind purchase_ref fixture"
}
# ---- v7: Sales + OpeningStock slice on synthetic products ZZ-OS1 / ZZ-OS2 created natively by Products import. Exact stock, line, and drawer-cash effects are read back natively (app exports and the Sales page shift label) and asserted. Expected values were settled by executing the same fixtures through the r114 Core with the SeedSr seed state (sales-opening-seq-r114-core-linux.txt). ----
function GoExcelTab(){ if(-not (NavTo @('الأصناف والمشتريات','Products & Purchasing') 'inventory-tab' 'ProductGrid')){ return $false }; if(-not (PressId $main 'InvExcelButton' 'to-excel-tab')){ return $false }; return [bool](ById $main 'ExcelMode' 10) }
function ReadShiftLabel($tag){ if(-not (NavTo @('البيع','Sales') "$tag-sales" 'StockGrid')){ return $null }; Start-Sleep -Milliseconds 600; $t=ValTxt 'ShiftStatusLabel'; Say "INFO $tag Sales page shift label: [$t]"; Shot "$tag-shift-label"; return $t }
function ImportStep($tag,$modeLabel,$file){ if(-not (GoExcelTab)){ Say "FAIL $tag could not return to the Excel tab"; $script:fails++; return $null }
  if(-not ((SetMode $modeLabel $tag) -and (OpenFile $file $tag))){ Excl "$tag $file" 'NOTEXECUTED: file could not be opened'; return $null }
  [void](SheetIs $tag 'Sheet1'); [void](ReadMap $tag); [void](SetConfirm $tag); return $true }
function RefuseStep($tag,$modeLabel,$file,$phrase){ $a=Snap "$tag-before"; $s=ImportStep $tag $modeLabel $file; if($null -eq $s){ return }
  $v=DoValidate $tag; Check ($v.refused -eq $true) "$tag validate refused"; if($phrase){ Check (([string]$v.text) -match $phrase) "$tag the refusal text names the reason (pattern [$phrase]; text [$($v.text -replace '\s+',' ')])" } else { Say "INFO $tag validate refusal text (not asserted beyond refused): [$($v.text -replace '\s+',' ')]" }
  $c=DoCommit $tag $false; Check ($c.refused -eq $true) "$tag commit refused"; $d=Snap "$tag-after"; CompareSnap $a $d "$tag refusal" }
function SliceSalesOpening(){
  $dir2=$exportDir
  # baseline drawer cash (seed: opening 10.00 + 8 seeded cash sales of 1620.00 = 1630.00; earlier steps in this run are purchases/products only and do not touch cash)
  $t0=ReadShiftLabel 'V7-base'; Check (XShiftEq $t0 1630) "V7 baseline drawer cash is 1630.00 as the seed defines it (label [$t0])"; $base=XShiftExpected $t0
  # 1 Products
  $a=Snap 'V7-1-before'; $s=ImportStep 'V7-1' 'أصناف جديدة' 'h1-products-zz.xlsx'
  if($s){ $v=DoValidate 'V7-1'; Check ($v.refused -eq $false) 'V7-1 products preview accepted'; $c=DoCommit 'V7-1' $true; Check (($c.refused -eq $false) -and $c.confirmed) 'V7-1 products committed'; $d=Snap 'V7-1-after'
    Check ((Rc $d 'products') -eq ((Rc $a 'products')+2)) "V7-1 products +2"; Check ((Rc $d 'batches') -eq (Rc $a 'batches')) 'V7-1 batches unchanged'; Check ((Rc $d 'sales') -eq (Rc $a 'sales')) 'V7-1 sales unchanged' } else { return }
  # 2 OpeningStock commit
  $a=Snap 'V7-2-before'; $s=ImportStep 'V7-2' 'رصيد افتتاحي فقط' 'h2-opening-ok.xlsx'
  if($s){ $v=DoValidate 'V7-2'; Check ($v.refused -eq $false) 'V7-2 opening stock preview accepted'; $c=DoCommit 'V7-2' $true; Check (($c.refused -eq $false) -and $c.confirmed) 'V7-2 opening stock committed'; $d=Snap 'V7-2-after'
    Check ((Rc $d 'batches') -eq ((Rc $a 'batches')+2)) 'V7-2 batches +2'; foreach($t in 'products','sales','sale_lines','purchases'){ Check ((Rc $d $t) -eq (Rc $a $t)) "V7-2 table $t unchanged" }
    $xf=Join-Path $dir2 'v7-opening-export-1.xlsx'; if(ExportMode 'رصيد افتتاحي فقط' $xf 'V7-2-export'){ Copy-Item $xf (Join-Path $OutDir 'v7-opening-export-1.xlsx') -Force; $x=ReadXlsxSheet $xf 'Stock'; Check $x.ok "V7-2 Stock sheet readable ($($x.why))"
      if($x.ok){ $rows=@($x.rows); $hd=@($rows[0]); Check (XHeaderIs $hd @('name','barcode','lot','expiry','quantity','CostEGP','PriceEGP')) 'V7-2 OpeningStock export header is the 7 expected columns'
        Check ((XRowCount $rows $hd @{barcode='ZZ-OS1';lot='O1'} @{quantity=50;CostEGP=7;PriceEGP=10}) -eq 1) 'V7-2 export: ZZ-OS1 lot O1 quantity 50 cost 7.00 price 10.00, exactly one row'
        Check ((XRowCount $rows $hd @{barcode='ZZ-OS1';lot='O2'} @{quantity=20;CostEGP=7.5;PriceEGP=10}) -eq 1) 'V7-2 export: ZZ-OS1 lot O2 quantity 20 cost 7.50 price 10.00, exactly one row'
        Check ((XRowCount $rows $hd @{barcode='ZZ-OS1'} @{}) -eq 2) 'V7-2 export: exactly two ZZ-OS1 batches'; Check ((XRowCount $rows $hd @{barcode='ZZ-OS2'} @{}) -eq 0) 'V7-2 export: ZZ-OS2 has no batch'
        $ex=@($rows | Select-Object -Skip 1 | Where-Object { (XCell $_ (XCol $hd 'barcode')) -ceq 'ZZ-OS1' } | ForEach-Object { 'lot='+(XCell $_ (XCol $hd 'lot'))+' expiryCell=['+(XCell $_ (XCol $hd 'expiry'))+']' }); Say "INFO V7-2 expiry cells as exported (format not asserted): $($ex -join '; ')" } } } else { return }
  $t1=ReadShiftLabel 'V7-2-shift'; Check (XShiftEq $t1 $base) "V7-2 opening stock does not change drawer cash (label [$t1])"
  # 3 to 5 refusals
  RefuseStep 'V7-3' 'رصيد افتتاحي فقط' 'h2-opening-ok.xlsx' 'مسجل من قبل'
  RefuseStep 'V7-4' 'رصيد افتتاحي فقط' 'h3-opening-existing-batches.xlsx' 'تشغيلات سابقة'
  RefuseStep 'V7-5' 'رصيد افتتاحي فقط' 'h4-opening-expired.xlsx' 'منتهي الصلاحية'
  # 6 Sales commit
  $a=Snap 'V7-6-before'; $s=ImportStep 'V7-6' 'ترحيل مبيعات نقدية الآن' 'h5-sales-ok.xlsx'
  if($s){ $v=DoValidate 'V7-6'; Check ($v.refused -eq $false) 'V7-6 sales preview accepted'; Say "INFO V7-6 sales preview text: [$($v.text -replace '\s+',' ')]"; $b=Snap 'V7-6-after-validate'; CompareSnap $a $b 'V7-6 validate'
    $c=DoCommit 'V7-6' $true; Check (($c.refused -eq $false) -and $c.confirmed) 'V7-6 sales committed'; $d=Snap 'V7-6-after'
    Check ((Rc $d 'sales') -eq ((Rc $a 'sales')+2)) "V7-6 sales +2 ($((Rc $a 'sales')) -> $((Rc $d 'sales')))"; Check ((Rc $d 'sale_lines') -eq ((Rc $a 'sale_lines')+2)) 'V7-6 sale_lines +2'; Check ((Rc $d 'batches') -eq (Rc $a 'batches')) 'V7-6 batches row count unchanged (quantities change inside rows)'; Check ((Rc $d 'products') -eq (Rc $a 'products')) 'V7-6 products unchanged'
    $xf=Join-Path $dir2 'v7-opening-export-2.xlsx'; if(ExportMode 'رصيد افتتاحي فقط' $xf 'V7-6-stock-export'){ Copy-Item $xf (Join-Path $OutDir 'v7-opening-export-2.xlsx') -Force; $x=ReadXlsxSheet $xf 'Stock'; Check $x.ok 'V7-6 Stock sheet readable'
      if($x.ok){ $rows=@($x.rows); $hd=@($rows[0]); Check ((XRowCount $rows $hd @{barcode='ZZ-OS1';lot='O1'} @{quantity=47;CostEGP=7}) -eq 1) 'V7-6 stock export: lot O1 is now exactly 47 (50 - 3), cost unchanged 7.00'; Check ((XRowCount $rows $hd @{barcode='ZZ-OS1';lot='O2'} @{quantity=18;CostEGP=7.5}) -eq 1) 'V7-6 stock export: lot O2 is now exactly 18 (20 - 2), cost unchanged 7.50' } }
    $xf=Join-Path $dir2 'v7-sales-export-1.xlsx'; if(ExportMode 'ترحيل مبيعات نقدية الآن' $xf 'V7-6-sales-export'){ Copy-Item $xf (Join-Path $OutDir 'v7-sales-export-1.xlsx') -Force; $x=ReadXlsxSheet $xf 'Sales'; Check $x.ok 'V7-6 Sales sheet readable'
      if($x.ok){ $rows=@($x.rows); $hd=@($rows[0]); Check (XHeaderIs $hd @('sale_id','createdUTC','cashier','barcode','name','lot','quantity','PriceEGP','LineTotalEGP','refunded')) 'V7-6 Sales export header is the 10 expected columns'
        Check ((XRowCount $rows $hd @{barcode='ZZ-OS1';lot='O1'} @{quantity=3;PriceEGP=10;LineTotalEGP=30;refunded=0}) -eq 1) 'V7-6 sales export: one line ZZ-OS1 lot O1 quantity 3 at 10.00, line total 30.00, not refunded'
        Check ((XRowCount $rows $hd @{barcode='ZZ-OS1';lot='O2'} @{quantity=2;PriceEGP=10;LineTotalEGP=20;refunded=0}) -eq 1) 'V7-6 sales export: one line ZZ-OS1 lot O2 quantity 2 at 10.00, line total 20.00, not refunded'
        Check ((XRowCount $rows $hd @{barcode='ZZ-OS1'} @{}) -eq 2) 'V7-6 sales export: exactly two ZZ-OS1 lines'; Check (($rows.Count-1) -eq (Rc $d 'sale_lines')) "V7-6 sales export data rows $($rows.Count-1) equal the sale_lines table rows $(Rc $d 'sale_lines')" } } } else { return }
  $t2=ReadShiftLabel 'V7-6-shift'; Check (XShiftEq $t2 ($base+50)) "V7-6 drawer cash is exactly baseline + 50.00 = $($base+50) (30.00 + 20.00 cash sales; label [$t2])"; Check (XShiftEq $t2 1680) 'V7-6 drawer cash is exactly 1680.00 (Core-settled expectation)'
  # 7 refusals
  RefuseStep 'V7-7a' 'ترحيل مبيعات نقدية الآن' 'h5-sales-ok.xlsx' 'مسجل من قبل'
  RefuseStep 'V7-7b' 'ترحيل مبيعات نقدية الآن' 'h6-sales-reused-id-different-content.xlsx' 'مستورد من قبل'
  RefuseStep 'V7-7c' 'ترحيل مبيعات نقدية الآن' 'h7-sales-price-mismatch.xlsx' 'لا يطابق'
  RefuseStep 'V7-7d' 'ترحيل مبيعات نقدية الآن' 'h8-sales-second-invoice-exceeds-stock.xlsx' $null
  RefuseStep 'V7-7e' 'ترحيل مبيعات نقدية الآن' 'h9-sales-refunded-row.xlsx' 'مرتجعة'
  # 8 preview only
  $a=Snap 'V7-8-before'; $s=ImportStep 'V7-8' 'ترحيل مبيعات نقدية الآن' 'h10-sales-preview-only.xlsx'
  if($s){ $v=DoValidate 'V7-8'; Check ($v.refused -eq $false) 'V7-8 valid new invoice preview accepted'; $b=Snap 'V7-8-after'; CompareSnap $a $b 'V7-8 preview only (not committed)' }
  # 9 final
  $t3=ReadShiftLabel 'V7-9-shift'; Check (XShiftEq $t3 1680) "V7-9 after all refusals and the preview the drawer cash is still exactly 1680.00 (label [$t3])"
  $xf=Join-Path $dir2 'v7-sales-export-2.xlsx'; if((GoExcelTab) -and (ExportMode 'ترحيل مبيعات نقدية الآن' $xf 'V7-9-sales-export')){ Copy-Item $xf (Join-Path $OutDir 'v7-sales-export-2.xlsx') -Force; $x=ReadXlsxSheet $xf 'Sales'; if($x.ok){ $rows=@($x.rows); $hd=@($rows[0]); Check ((XRowCount $rows $hd @{barcode='ZZ-OS1'} @{}) -eq 2) 'V7-9 final sales export still has exactly two ZZ-OS1 lines'; Check ((XRowCount $rows $hd @{} @{refunded=1}) -eq 0) 'V7-9 no refunded line exists' } else { Say 'FAIL V7-9 final Sales sheet unreadable'; $script:fails++ } }
  Excl 'Sales import without an open shift natively' 'EXCLUDED-SCOPE: the seeded database always has an open shift; the no-shift refusal (Open your shift before selling) was observed offline only, in the Core log'
}
# ---- startup: hashes, seed (pinned SeedSr: 7 synthetic products incl. SR-FAST, used only as a stocked product for Purchases) ----
$zh=(Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLower(); if($zh -ne $ExpectZipSha){ Say "FAIL zip hash $zh"; exit 1 }; Say 'PASS zip sha256 matches expected'
$dir=Join-Path $env:RUNNER_TEMP 'trial'; Expand-Archive -Path $Zip -DestinationPath $dir -Force
$exe=Join-Path $dir 'OneForAllGood.Pharmacy.TRIAL.exe'
$eh=(Get-FileHash -Algorithm SHA256 $exe).Hash.ToLower(); if($eh -ne $ExpectExeSha){ Say "FAIL exe hash $eh"; exit 1 }; Say 'PASS exe sha256 matches expected'
$FixDir=(Resolve-Path -LiteralPath $FixDir).ProviderPath; if(-not [System.IO.Path]::IsPathRooted($FixDir)){ Say "FAIL fixture dir not absolute: $FixDir"; exit 1 }; Say "INFO fixture dir resolved to the absolute path $FixDir (v2 kit change: the Open dialog resolves a relative typed path against Documents)"
$fxSums=Join-Path $FixDir 'FIXTURE-SHA256SUMS.txt'; $fxBad=0; foreach($l in @(Get-Content $fxSums)){ if($l -match '^([0-9a-f]{64})\s+\*?(\S+)$'){ $h=(Get-FileHash -Algorithm SHA256 (Join-Path $FixDir $Matches[2])).Hash.ToLower(); if($h -ne $Matches[1]){ Say "FAIL fixture hash mismatch $($Matches[2])"; $fxBad++ } else { Say "PASS fixture sha256 $($Matches[2]) $h" } } }; if($fxBad -gt 0){ exit 1 }
$chars='abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
$pwOwner=-join (1..16 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
$pwCash=-join (1..16 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })   # l148: defined once up front (v48: it was set only inside the roles block, so the network block typed a null password when roles did not run)
$env:POS_SEED_OWNER_PW=$pwOwner
foreach($t in @(@($SeedExe,$ExpectSeedSha,'seeder'),@($SnapExe,$ExpectSnapSha,'snapshot tool'))){ if(-not (Test-Path $t[0])){ Say "FAIL $($t[2]) missing: $($t[0])"; exit 6 }; $h=(Get-FileHash -Algorithm SHA256 $t[0]).Hash.ToLower(); if($h -ne $t[1]){ Say "FAIL $($t[2]) hash $h"; exit 6 }; Say "PASS $($t[2]) sha256 matches the pinned prebuilt ($h)" }
$seedOut=& $SeedExe 2>&1 | Out-String; Set-Content -Path (Join-Path $OutDir "seed-output-raw.txt") -Value $seedOut -Encoding UTF8; Say "INFO seeder exit code $LASTEXITCODE"
Remove-Item Env:POS_SEED_OWNER_PW -ErrorAction SilentlyContinue
if($seedOut -notmatch 'seeded synthetic stock-rate trial database'){ Say "FAIL seeding did not complete: $(($seedOut -split "`n" | Select-Object -Last 3) -join ' | ')"; exit 6 }
Set-Content -Path (Join-Path $OutDir 'seed-output.txt') -Value $seedOut -Encoding UTF8
Say 'PASS synthetic database seeded (SR-FAST present as the stocked product for Purchases)'
$vs=[System.Windows.Forms.SystemInformation]::VirtualScreen; Say "INFO screen $($vs.Width)x$($vs.Height)"

function EarlyDiag($tag){
  try{ $pp=$script:p; $alive=$false; $ec='n/a'; if($pp){ try{ $pp.Refresh(); $alive=-not $pp.HasExited; if($pp.HasExited){ $ec=$pp.ExitCode } }catch{} }
    Say "DIAG $tag process id=$(if($pp){$pp.Id}) alive=$alive exitcode=$ec"
    $n=0; foreach($w in @(TopWins $pp.Id)){ $n++; try{ $r=$w.Current.BoundingRectangle; Say "DIAG $tag process window class=[$($w.Current.ClassName)] name=[$($w.Current.Name)] hwnd=$($w.Current.NativeWindowHandle) x=$([int]$r.X) y=$([int]$r.Y) w=$([int]$r.Width) h=$([int]$r.Height) offscreen=$($w.Current.IsOffscreen) modal=$($w.Current.ClassName -eq '#32770')" }catch{ Say "DIAG $tag process window unreadable" } }
    Say "DIAG $tag top-level windows of the process: $n"
    $k=0; foreach($w in @($AE::RootElement.FindAll($TS::Children,[System.Windows.Automation.Condition]::TrueCondition))){ $k++; if($k -le 25){ try{ Say "DIAG $tag desktop window pid=$($w.Current.ProcessId) class=[$($w.Current.ClassName)] name=[$($w.Current.Name)]" }catch{} } }
    Shot "dlg-$tag-early-exit"
    $i=0; foreach($w in @(TopWins $pp.Id)){ $i++; Dump $w "dlg-$tag-early-root$i" }
    try{ $ev=@(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddMinutes(-6)} -ErrorAction Stop | Where-Object { $_.Message -match 'OneForAllGood|Pharmacy|\.NET Runtime|Application Error|WPF|XamlParse' } | Select-Object -First 4); foreach($x in $ev){ $m=([string]$x.Message); if($m.Length -gt 1800){ $m=$m.Substring(0,1800) }; Say "DIAG $tag eventlog id=$($x.Id) provider=$($x.ProviderName) time=$($x.TimeCreated.ToString('o')) message=$($m -replace '\r?\n',' | ')" }; if($ev.Count -eq 0){ Say "DIAG $tag eventlog: no matching Application events in the last 6 minutes" } }catch{ Say "INFO $tag eventlog unreadable: $($_.Exception.Message)" }
    try{ $cl=Join-Path ([System.IO.Path]::GetTempPath()) 'OneForAllGood-crash.log'; if(Test-Path $cl){ $ct=Get-Content -Raw $cl; if($ct.Length -gt 6000){ $ct=$ct.Substring(0,6000) }; Say "DIAG $tag app crash log: $($ct -replace '\r?\n',' | ')"; Copy-Item $cl (Join-Path $OutDir 'OneForAllGood-crash.log') -Force } else { Say "DIAG $tag app crash log: file not present (the process died before or without the managed handlers)" } }catch{ Say "INFO $tag crash log unreadable: $($_.Exception.Message)" }
    $d=Join-Path $env:LOCALAPPDATA 'OneForAllGood-TRIAL'; if(Test-Path $d){ foreach($f in @(Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 20)){ Say "DIAG $tag trial data file $($f.FullName) bytes=$($f.Length)" } } else { Say "DIAG $tag trial data folder does not exist" }
  }catch{ Say "INFO EarlyDiag $tag failed: $($_.Exception.Message)" } }
function Launch($tag){
  $script:p=Start-Process -FilePath $exe -PassThru
  $mb=$null; $end=(Get-Date).AddSeconds(40); do{ foreach($w in (TopWins $script:p.Id)){ if($w.Current.ClassName -eq '#32770'){ $mb=$w } }; if($script:p.HasExited){ Say "FAIL $tag exited early"; EarlyDiag $tag; exit 2 }; if(-not $mb){ Start-Sleep -Milliseconds 400 } }while(-not $mb -and (Get-Date) -lt $end)
  if($mb){ Say "PASS $tag start warning found"; try{$mb.SetFocus()}catch{}; Start-Sleep -Milliseconds 500; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 3 } else { Say "FAIL $tag no start warning"; EarlyDiag $tag; exit 3 }
  $script:main=$null; $end=(Get-Date).AddSeconds(40); do{ foreach($w in (TopWins $script:p.Id)){ if($w.Current.ClassName -ne '#32770' -and $w.Current.Name){ $script:main=$w } }; if(-not $script:main){ Start-Sleep -Milliseconds 400 } }while(-not $script:main -and (Get-Date) -lt $end)
  if(-not $script:main){ Say "FAIL $tag no main window"; EarlyDiag $tag; exit 4 }
  Say "PASS $tag main window: $($script:main.Current.Name)"; Start-Sleep 2 }
try{ $preSnapText=& $SnapExe 2>&1 | Out-String; Set-Content -Path (Join-Path $OutDir 'snap-prelaunch.txt') -Value $preSnapText -Encoding UTF8; Say "INFO prelaunch snapshot taken before the app starts (observation only; saved as snap-prelaunch.txt)" }catch{ $preSnapText=$null; Say "INFO prelaunch snapshot failed: $($_.Exception.Message)" }
Launch 'launch1'; Bounds $main 'first-window'; Shot '10-first-window'
Add-Type -Namespace M -Name W -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow(); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h,out uint pid); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr h); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern short GetKeyState(int k);'
# foreground window of THIS run's process? (keystrokes go to the foreground window, so every typed character is gated on it)
function FgOurs(){ try{ $h=[M.W]::GetForegroundWindow(); [uint32]$fp=0; [void][M.W]::GetWindowThreadProcessId($h,[ref]$fp); return ($fp -eq [uint32]$script:p.Id) }catch{ return $false } }
function BringFg(){ try{ $h=[System.IntPtr]([int]$main.Current.NativeWindowHandle); [void][M.W]::SetForegroundWindow($h); $main.SetFocus() }catch{}; Start-Sleep -Milliseconds 400; return (FgOurs) }
function EscKey($c){ if('+^%~(){}[]'.Contains([string]$c)){ return '{' + $c + '}' } return [string]$c }
# types $text one character at a time through $send, checking before EVERY character that our window is still the foreground window; returns counts only (the value is never logged)
function TypeSecret($text,$fgCheck,$send){ if([string]::IsNullOrEmpty([string]$text)){ Say 'FAIL TypeSecret called with an empty or null text (driver data bug, nothing typed)'; return @{ typed=0; expected=0; lost=$false; ok=$false } }; $n=0; $lost=$false; foreach($c in $text.ToCharArray()){ if(-not (& $fgCheck)){ $lost=$true; break }; & $send (EscKey $c); $n++; Start-Sleep -Milliseconds 25 }; return @{ typed=$n; expected=$text.Length; lost=$lost; ok=((-not $lost) -and $n -eq $text.Length) } }
# pure decision after one login attempt (mocked): retry ONLY when typing was disrupted; a fully typed, uninterrupted entry that is rejected is reported as a credential rejection, never retried blindly
function LoginPlan($typedOk,$tabsVisible,$modalUp,$attempt){ if($tabsVisible){ return 'pass' }; if(-not $typedOk){ if($attempt -lt 2){ return 'retry' } else { return 'fail-typing' } }; if($modalUp){ return 'credential-rejected' }; return 'fail-no-tabs' }
function Login($user,$pw,$tag){
  $u=ById $main 'LoginUsername' 20; $pb=ById $main 'LoginPassword' 5; $lb=ById $main 'LoginButton' 5
  if(-not ($u -and $pb -and $lb)){ Say "FAIL $tag login ids not found"; $script:fails++; Halt "$tag login"; return $false }
  for($attempt=1;$attempt -le 2;$attempt++){
    $fg0=BringFg; $caps=(([M.W]::GetKeyState(0x14) -band 1) -eq 1); if($caps){ [System.Windows.Forms.SendKeys]::SendWait('{CAPSLOCK}'); Start-Sleep -Milliseconds 200 }
    $u.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($user)
    $pb.SetFocus(); Start-Sleep -Milliseconds 400; $hf0=$false; try{ $hf0=[bool]$pb.Current.HasKeyboardFocus }catch{}
    [System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 100; [System.Windows.Forms.SendKeys]::SendWait('{BACKSPACE}'); Start-Sleep -Milliseconds 150
    $tr=TypeSecret $pw { FgOurs } { param($k) [System.Windows.Forms.SendKeys]::SendWait($k) }
    $hf1=$false; try{ $hf1=[bool]$pb.Current.HasKeyboardFocus }catch{}
    Say "DIAG $tag login attempt $attempt input: foreground_ours_before=$fg0 capslock_was_on=$caps password_box_focus_before=$hf0 typed=$($tr.typed)/$($tr.expected) foreground_lost_midway=$($tr.lost) password_box_focus_after=$hf1 modal_open=$([bool](FindModal))"
    $lb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 4
    $t=ById $main 'Tabs' 20; $tabs=($t -and -not $t.Current.IsOffscreen); $md=FindModal
    $plan=LoginPlan ($tr.ok -and $hf1) $tabs ([bool]$md) $attempt
    if($plan -eq 'pass'){ Say "PASS $tag logged in, Tabs visible (attempt $attempt)"; return $true }
    Shot "dlg-$tag-login-attempt$attempt"; Say "DIAG $tag login attempt $attempt result=$plan"
    if($md){ try{ $md.SetFocus() }catch{}; Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 800 }
    if($plan -ne 'retry'){ break } }
  Say "FAIL $tag login did not succeed ($plan); credential value, hash and read-back are never logged"; $script:fails++; Halt "$tag login"; return $false }
Add-Type -Namespace W -Name S -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll",CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern int GetClassName(System.IntPtr h,System.Text.StringBuilder b,int n); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetDlgCtrlID(System.IntPtr h); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetParent(System.IntPtr h); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr h,out uint pid); public delegate bool EnumProc(System.IntPtr h,System.IntPtr l); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool EnumChildWindows(System.IntPtr p,EnumProc cb,System.IntPtr l); [System.Runtime.InteropServices.DllImport("user32.dll",EntryPoint="SendMessageW",CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern System.IntPtr SendMsgStr(System.IntPtr h,int m,System.IntPtr w,string l); [System.Runtime.InteropServices.DllImport("user32.dll",EntryPoint="SendMessageW",CharSet=System.Runtime.InteropServices.CharSet.Unicode)] public static extern System.IntPtr SendMsgSb(System.IntPtr h,int m,System.IntPtr w,System.Text.StringBuilder l); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr SendMessage(System.IntPtr h,int m,System.IntPtr w,System.IntPtr l);'
function RealOps(){ return @{ AppPid=[uint32]$p.Id
  Cls={ param($h) $b=New-Object System.Text.StringBuilder 256; [void][W.S]::GetClassName([IntPtr]$h,$b,256); $b.ToString() }
  Id={ param($h) [W.S]::GetDlgCtrlID([IntPtr]$h) }
  Pid={ param($h) $o=[uint32]0; [void][W.S]::GetWindowThreadProcessId([IntPtr]$h,[ref]$o); $o }
  Txt={ param($h) $b=New-Object System.Text.StringBuilder 2048; [void][W.S]::SendMsgSb([IntPtr]$h,0x000D,[IntPtr]2048,$b); $b.ToString() }
  Kids={ param($h) $l=New-Object System.Collections.ArrayList; $cb=[W.S+EnumProc]{ param($c,$x) [void]$l.Add($c); $true }; [void][W.S]::EnumChildWindows([IntPtr]$h,$cb,[IntPtr]::Zero); $o=@(); foreach($c in $l){ $cb2=New-Object System.Text.StringBuilder 256; [void][W.S]::GetClassName($c,$cb2,256); $t=New-Object System.Text.StringBuilder 256; [void][W.S]::SendMsgSb($c,0x000D,[IntPtr]256,$t); $o+=[pscustomobject]@{ H=[int64]$c; Par=[int64][W.S]::GetParent($c); Id=[W.S]::GetDlgCtrlID($c); Cls=$cb2.ToString(); Txt=$t.ToString() } }; $o }
  SetText={ param($h,$t) [W.S]::SendMsgStr([IntPtr]$h,0x000C,[IntPtr]::Zero,$t) }
  Click={ param($h) [W.S]::SendMessage([IntPtr]$h,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero) } } }
# pure (mocked): the file-name Edit of a common file dialog from ALL descendant windows (each: H, Par, Id, Cls). Rule A (Save As, natively proven): exactly one Edit with ctrl id 1001. Rule B (Open dialog, observed natively: the name box is a ComboBoxEx32 id 1148 > ComboBox > Edit, there is NO id-1001 Edit): Edits whose ancestor chain contains a ComboBoxEx32 with id 1148. Search box, address band and list-view edits never qualify. Returns the matches (the caller needs exactly 1).
function ResolveNameEdit($kids){ $k=@($kids); $a=@($k | Where-Object { $_.Id -eq 1001 -and $_.Cls -eq 'Edit' }); if($a.Count -ge 1){ return $a }
  $o=@(); foreach($e in @($k | Where-Object { $_.Cls -eq 'Edit' })){ $par=$e.Par; $hit=$false; for($d=0;$d -lt 8 -and $par -ne 0;$d++){ $n=@($k | Where-Object { $_.H -eq $par }); if($n.Count -ne 1){ break }; if($n[0].Cls -eq 'ComboBoxEx32' -and $n[0].Id -eq 1148){ $hit=$true; break }; $par=$n[0].Par }; if($hit){ $o+=$e } }
  return $o }
# pure (mocked): parse the read-only snapshot tool output into table -> "rows|hash"; $null when the output is not a complete snapshot
function ParseSnap($text){ $h=@{}; $done=$false; foreach($l in @(([string]$text) -split "`r?`n")){ if($l -match '^TABLE (\S+) rows=(\d+) hash=(\S+)$'){ $h[$Matches[1]]=$Matches[2]+'|'+$Matches[3] } elseif($l -match '^SNAPDONE tables=(\d+)$'){ $done=($h.Count -eq [int]$Matches[1]) } }; if(-not $done -or $h.Count -eq 0){ return $null }; return $h }
# pure (mocked): names of tables whose rows or hash differ, or that exist on only one side (sorted)
function SnapDiff($a,$b){ $o=@(); foreach($k in @(@($a.Keys)+@($b.Keys) | Sort-Object -Unique)){ if(-not $a.ContainsKey($k) -or -not $b.ContainsKey($k) -or $a[$k] -ne $b[$k]){ $o+=$k } }; return $o }
function Snap($tag){ try{ $t=& $SnapExe 2>&1 | Out-String; $script:lastCfg=@(([string]$t -split "`r?`n") | Where-Object { $_ -like 'SYNCCFG *' } | ForEach-Object { $_.Substring(8).Trim() }); $m=ParseSnap $t; if($null -eq $m){ Say "FAIL snapshot $tag incomplete: $((($t -split "`n") | Select-Object -Last 2) -join ' | ')"; $script:fails++; return $null }; Say "INFO snapshot $tag tables=$($m.Count) rows: $((@($m.Keys | Sort-Object | Where-Object { $m[$_] -notlike '0|*' } | ForEach-Object { $_+'='+($m[$_] -split '\|')[0] }) -join ' '))"; return $m }catch{ Say "FAIL snapshot $tag failed: $($_.Exception.Message)"; $script:fails++; return $null } }
function CompareSnap($a,$b,$tag){ if($null -eq $a -or $null -eq $b){ Say "FAIL $tag snapshot comparison impossible (a snapshot is missing)"; $script:fails++; return }; $d=@(SnapDiff $a $b); Check ($d.Count -eq 0) "$tag no database table changed (row counts and content hashes of every table equal; users counted only)$(if($d.Count){ ': changed=' + ($d -join ',') })"; if($d.Count){ foreach($k in $d){ Say "INFO $tag changed table $k before=[$($a[$k])] after=[$($b[$k])]" } } }
function ByName($name,$ctl){ $c=New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,$name)),(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$ctl))); return @($main.FindAll($TS::Descendants,$c)) }
function PressByName($name,$tag){ if(-not (Guard $tag)){ return $false }; $b=ByName $name ([System.Windows.Automation.ControlType]::Button); if($b.Count -ne 1){ Say "FAIL $tag button '$name' found $($b.Count) times (need exactly 1)"; $script:fails++; Halt "$tag button"; return $false }
  try{ $b[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Say "STEP $tag pressed '$name'"; return $true }catch{ Say "FAIL $tag Invoke failed on '$name': $($_.Exception.Message) patterns=$(Patterns $b[0])"; $script:fails++; Halt "$tag invoke"; return $false } }
function ValueOf($id){ $e=Pick $id 3; if(-not $e){ return $null }; try{ return $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ return $e.Current.Name } }
$StkTables=@('audit','batches','movements','outbox','stocktake_count_events','stocktake_lines','stocktakes')
function Skip($what,$why){ Say "NOTEXECUTED $what ($why)" }
function Excl($what,$why){ Say "EXCLUDED-SCOPE $what ($why)" }
function Gate($ok,$msg){ Check $ok $msg; if(-not $ok){ Halt "gate failed: $msg" }; return $ok }
Add-Type -Namespace M -Name K -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte scan,uint flags,System.UIntPtr extra);'
# Source: StocktakeWindow is created with Owner=this (MainWindow.Next.cs Stocktake_Click) and the review dialog with Owner=this window. WPF owned windows are not guaranteed to be direct children of the desktop in UIA, so search the process top-level windows AND every Window element beneath them; match by exact title, or (for the stocktake window) structurally by containing the StocktakeBatches grid.
function AllWinsDeep(){ $o=@(); $seen=@{}; foreach($w in @(TopWins $p.Id)){ $k=''; try{ $k=[string]$w.Current.NativeWindowHandle }catch{}; if(-not $seen.ContainsKey($k)){ $seen[$k]=1; $o+=$w }
    try{ foreach($x in @($w.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))))){ $k2=''; try{ $k2=[string]$x.Current.NativeWindowHandle }catch{}; if($k2 -eq '' -or -not $seen.ContainsKey($k2)){ if($k2 -ne ''){ $seen[$k2]=1 }; $o+=$x } } }catch{} }; return $o }
function WinByTitle($title,$sec){ $end=(Get-Date).AddSeconds($sec); do{ foreach($w in @(AllWinsDeep)){ try{ if($w.Current.ClassName -eq '#32770'){ continue }; if([string]$w.Current.Name -ceq $title){ return $w }
        if($title -ceq $script:WinTitle){ if(ById $w 'StocktakeBatches' 0){ if(-not [object]::ReferenceEquals($w,$main) -and [string]$w.Current.Name -cne [string]$script:main.Current.Name){ return $w } } } }catch{} }; Start-Sleep -Milliseconds 300 }while((Get-Date) -lt $end); return $null }
function WinList($tag){ $n=0; foreach($w in @(AllWinsDeep)){ $n++; try{ $r=$w.Current.BoundingRectangle; Say "DIAG $tag window#$n class=[$($w.Current.ClassName)] name=[$($w.Current.Name)] hwnd=$($w.Current.NativeWindowHandle) x=$([int]$r.X) y=$([int]$r.Y) w=$([int]$r.Width) h=$([int]$r.Height) offscreen=$($w.Current.IsOffscreen)" }catch{ Say "DIAG $tag window#$n unreadable" } }
  $c=0; foreach($w in @($AE::RootElement.FindAll($TS::Children,[System.Windows.Automation.Condition]::TrueCondition))){ $c++; if($c -le 30){ try{ Say "DIAG $tag desktop pid=$($w.Current.ProcessId) class=[$($w.Current.ClassName)] name=[$($w.Current.Name)]" }catch{} } } }
# mandatory on every failure that involves a window: full-screen shot, window list, UIA dump of every window of the process, any message-box statics
function FailDiag($tag){ try{ Shot "FAILDIAG-$tag" }catch{}; try{ WinList $tag }catch{}; try{ $i=0; foreach($w in @(AllWinsDeep)){ $i++; Dump $w "FAILDIAG-$tag-win$i" } }catch{}; try{ foreach($w in @(AllWinsDeep)){ if($w.Current.ClassName -eq '#32770'){ Say "DIAG $tag message box [$($w.Current.Name)] texts: $((@(WinBoxStatics $w)) -join ' | ')" } } }catch{} }
function WinBoxStatics($w){ $o=@(); try{ foreach($t in @($w.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))))){ $n=[string]$t.Current.Name; if($n.Length -gt 0){ $o+=$n } } }catch{}; return $o }
function GridCount($root,$id){ $g=ById $root $id 5; if(-not $g){ return -1 }; $rc=-1; try{ $rc=[int]$g.GetCurrentPattern([System.Windows.Automation.GridPattern]::Pattern).Current.RowCount }catch{}; $real=@(RowsIn $root $id).Count; if($rc -ge 0){ return $rc } else { return $real } }
function WinGone($title,$sec){ $end=(Get-Date).AddSeconds($sec); do{ if(-not (WinByTitle $title 0)){ return $true }; Start-Sleep -Milliseconds 300 }while((Get-Date) -lt $end); return $false }
function NormTxt($t){ $x=[regex]::Replace([string]$t,'[\u200E\u200F\u202A-\u202E\u2066-\u2069]',''); $x=(Latin $x).Replace([string][char]0x2212,'-').Trim(); return $x }
function RowsIn($root,$gridId){ $g=ById $root $gridId 8; if(-not $g){ return $null }; return @($g.FindAll($TS::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::DataItem)))) }
function RowCells($row){ return @(CellNames $row | ForEach-Object { NormTxt $_ }) }
# identity of a batch row = its barcode cell AND its lot cell (exact cell texts, column-order independent)
function RowIs($cells,$bc,$lot){ return (@($cells) -ccontains $bc -and @($cells) -ccontains $lot) }
function FindRow($root,$gridId,$lot,$bc){ $m=@(); foreach($r in @(RowsIn $root $gridId)){ $c=@(RowCells $r); if(@($c) -ccontains $lot -and ($bc -eq '' -or @($c) -ccontains $bc)){ $m+=$r } }; if($m.Count -eq 1){ return $m[0] }; return $null }
function IsSel($row){ try{ return [bool]$row.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }catch{ return $null } }
function GridDump($root,$gridId,$tag){ $o=@(); foreach($r in @(RowsIn $root $gridId)){ $o+=('['+((RowCells $r) -join ' | ')+'] sel='+(IsSel $r)) }; Say "GRID $tag $gridId rows=$($o.Count): $($o -join ' ;; ')" }
function Sanitize($tag){ # stray runner dialogs and Task View must not steal focus or keys (v15 evidence)
  try{ $c=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window); foreach($w in @($AE::RootElement.FindAll($TS::Children,$c))){ $n=[string]$w.Current.Name; if([int]$w.Current.ProcessId -ne [int]$p.Id -and ($n -eq 'System Properties' -or $n -eq 'Task View')){ Say "DIAG Sanitize $tag stray window [$n] class=[$($w.Current.ClassName)] pid=$($w.Current.ProcessId)"; if($n -eq 'System Properties'){ try{ $bc=New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,'OK'); $ok=$w.FindFirst($TS::Descendants,$bc); if($ok){ $ok.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Say "DIAG Sanitize $tag clicked OK" } }catch{ Say "DIAG Sanitize $tag OK failed: $($_.Exception.Message)" } } else { [System.Windows.Forms.SendKeys]::SendWait('{ESC}'); Say "DIAG Sanitize $tag sent Escape for Task View" } } } }catch{ Say "DIAG Sanitize $tag error: $($_.Exception.Message)" }
  try{ [void](BringFg) }catch{} }
function ClickRow($row,$ctrl){ try{ $si=$row.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern); $si.ScrollIntoView(); Start-Sleep -Milliseconds 300 }catch{}; $b=$row.Current.BoundingRectangle; if($b.IsEmpty -or $b.Width -lt 5 -or $b.Height -lt 5){ return $false }; $x=[int]($b.X+$b.Width/2); $y=[int]($b.Y+$b.Height/2); $vs=[System.Windows.Forms.SystemInformation]::VirtualScreen; if($y -ge ($vs.Bottom-60) -or $y -lt $vs.Top -or $x -lt $vs.Left -or $x -ge $vs.Right){ Say "DIAG ClickRow refused: point $x,$y is outside the safe screen area (taskbar or off screen)"; return $false }; [void][M.U]::SetCursorPos($x,$y); Start-Sleep -Milliseconds 250
  if($ctrl){ [M.K]::keybd_event(0x11,0,0,[UIntPtr]::Zero) }; [M.U]::mouse_event(2,0,0,0,[UIntPtr]::Zero); [M.U]::mouse_event(4,0,0,0,[UIntPtr]::Zero); if($ctrl){ [M.K]::keybd_event(0x11,0,2,[UIntPtr]::Zero) }; Start-Sleep -Milliseconds 400; Neutral; return $true }
# Select exactly the wanted (barcode,lot) rows of a multi-select grid; verify by IsSelected readback that the selected set equals the wanted set. Pattern route first; if it throws or the readback differs, observed-row-bounds ctrl-click route; verify again.
function SelectExact($root,$gridId,$want,$tag){
  $all=@(RowsIn $root $gridId); $wantCells=@(); $ok=$true
  $first=$true; foreach($w in $want){ $r=FindRow $root $gridId $w[1] $w[0]; if(-not $r){ Say "FAIL $tag row $($w[0])/$($w[1]) not found exactly once"; return $false }
    try{ $sp=$r.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern); if($first){ $sp.Select() } else { $sp.AddToSelection() }; $first=$false }catch{ Say "INFO $tag pattern select failed for $($w[1]): $($_.Exception.Message)"; $ok=$false } }
  Start-Sleep -Milliseconds 500
  $v=SelVerdict $root $gridId $want; Say "INFO $tag pattern route: ok=$ok readback_ok=$($v.ok) selected=[$($v.sel -join ',')] wrong=[$($v.wrong -join ',')]"
  if($v.ok){ return $true }
  Say "INFO $tag falling back to ctrl-click at the CURRENT observed row bounds (identity re-read for every row)"
  $first=$true; foreach($w in $want){ $r=FindRow $root $gridId $w[1] $w[0]; if(-not $r){ Say "FAIL $tag fallback: row $($w[1]) vanished"; return $false }; if(-not (ClickRow $r (-not $first))){ Say "FAIL $tag fallback: row $($w[1]) has no usable bounds"; return $false }; $first=$false }
  $v=SelVerdict $root $gridId $want; Say "INFO $tag fallback readback_ok=$($v.ok) selected=[$($v.sel -join ',')] wrong=[$($v.wrong -join ',')]"; return $v.ok }
function SelVerdict($root,$gridId,$want){ $sel=@(); $wrong=@(); $wl=@($want | ForEach-Object { $_[1] })
  foreach($r in @(RowsIn $root $gridId)){ $c=@(RowCells $r); $lot=''; foreach($l in $script:StkLots){ if(@($c) -ccontains $l){ $lot=$l } }; $s=IsSel $r; if($s -eq $true){ $sel+=$lot; if($wl -cnotcontains $lot){ $wrong+=$lot } } elseif($wl -ccontains $lot){ $wrong+="unselected:$lot" } }
  return @{ ok=($wrong.Count -eq 0 -and $sel.Count -eq $wl.Count); sel=$sel; wrong=$wrong } }
# single line/run selection by lot (pattern, then bounds click), verified: that row selected and no other
function SelectOne($root,$gridId,$lot,$tag){ $r=FindRow $root $gridId $lot ''; if(-not $r){ Say "FAIL $tag line $lot not found exactly once"; return $false }
  try{ $r.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }catch{ Say "INFO $tag pattern select failed: $($_.Exception.Message)" }; Start-Sleep -Milliseconds 500
  $v=SelVerdict $root $gridId @(,@('',$lot)); if($v.ok){ return $true }
  Say "INFO $tag fallback click at current bounds"; $r=FindRow $root $gridId $lot ''; if($r -and (ClickRow $r $false)){ $v=SelVerdict $root $gridId @(,@('',$lot)); return $v.ok }; return $false }
function SetBox($root,$id,$val,$tag){ $e=ById $root $id 5; if(-not $e){ Say "FAIL $tag box $id not found"; return $false }
  try{ $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue([string]$val); Start-Sleep -Milliseconds 300; $b=$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value; if($b -ceq [string]$val){ return $true }; Say "FAIL $tag box $id read back [$b], wanted [$val]"; return $false }catch{ Say "FAIL $tag box $id set failed: $($_.Exception.Message)"; return $false } }
function PressIn2($root,$name,$tag){ if(-not (Guard $tag)){ return $false }
  $c=New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,$name)),(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)))
  $b=@($root.FindAll($TS::Descendants,$c)); if($b.Count -ne 1){ Say "FAIL $tag button '$name' found $($b.Count) times (need exactly 1)"; $script:fails++; Halt "$tag button"; return $false }
  if(-not $b[0].Current.IsEnabled){ Say "FAIL $tag button '$name' is disabled"; $script:fails++; Halt "$tag button disabled"; return $false }
  try{ $b[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Say "STEP $tag pressed '$name'"; Start-Sleep -Milliseconds 1200; return $true }catch{ Say "FAIL $tag Invoke failed on '$name': $($_.Exception.Message)"; $script:fails++; Halt "$tag invoke"; return $false } }
# the single status TextBlock of the window: exactly one Text whose name starts with one of the known prefixes
function MsgText($root){ $pfx=@('بدأت مسودة فقط','حُفظ العدّ','اعتمد الجرد','لم يكتمل الإجراء'); $m=@(); foreach($t in @($root.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))))){ $n=[string]$t.Current.Name; foreach($x in $pfx){ if($n.StartsWith($x)){ $m+=$n } } }
  if($m.Count -ne 1){ Say "INFO MsgText: $($m.Count) status texts matched"; return $null }; return $m[0] }
function Reveal($root,$id,$tag){ $e=ById $root $id 4; if(-not $e){ Say "INFO $tag reveal: $id not found"; return }
  $rw=$root.Current.BoundingRectangle; function Frac($x){ $r=$x.Current.BoundingRectangle; if($r.Height -le 0){ return 0.0 }; return [math]::Max(0,[math]::Min($r.Bottom,$rw.Bottom)-[math]::Max($r.Top,$rw.Top))/$r.Height }
  $f=Frac $e; $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker; $a=$walker.GetParent($e); $n=0
  while($a -and $n -lt 25 -and $f -lt 0.97){ $n++; try{ $sp=$a.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern); if($sp.Current.VerticallyScrollable){ for($i=0;$i -lt 12 -and $f -lt 0.97;$i++){ $below=($e.Current.BoundingRectangle.Bottom -gt $rw.Bottom); $sp.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount,$(if($below){[System.Windows.Automation.ScrollAmount]::SmallIncrement}else{[System.Windows.Automation.ScrollAmount]::SmallDecrement})); Start-Sleep -Milliseconds 250; $f=Frac $e } } }catch{}; $a=$walker.GetParent($a) }
  Say "INFO $tag reveal $id visible_fraction_by_UIA=$([math]::Round($f,2)) (UIA bounds only, not pixel proof; inspect the screenshot)" }
function ShotAt($root,$id,$name){ try{ [void](BringFg) }catch{}; Reveal $root $id $name; Shot $name }
function Maximize($w,$tag){ try{ $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).SetWindowVisualState([System.Windows.Automation.WindowVisualState]::Maximized); Start-Sleep -Milliseconds 800; Say "INFO $tag window maximized"; $r=$w.Current.BoundingRectangle; Say "BOUNDS $tag x=$([int]$r.X) y=$([int]$r.Y) w=$([int]$r.Width) h=$([int]$r.Height)" }catch{ Say "INFO $tag maximize unavailable: $($_.Exception.Message)" } }
function ProbeText(){ try{ return (& $ProbeExe 2>&1 | Out-String) }catch{ return '' } }
function WorkArea(){ return [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
function InsideRect($r,$o,$tol){ return ($r.Width -gt 0 -and $r.Height -gt 0 -and $r.Left -ge $o.Left-$tol -and $r.Top -ge $o.Top-$tol -and $r.Right -le $o.Right+$tol -and $r.Bottom -le $o.Bottom+$tol) }
# window inside the work area (initial, un-maximized state is what a user gets); logs the numbers, raises a FAIL when any edge is outside (tolerance 10 px for the invisible resize border)
function LayoutProof($w,$tag,$buttons){ $wa=WorkArea; $r=$w.Current.BoundingRectangle
  Say ("BOUNDS $tag window x=$([int]$r.X) y=$([int]$r.Y) w=$([int]$r.Width) h=$([int]$r.Height) right=$([int]$r.Right) bottom=$([int]$r.Bottom); workarea x=$($wa.X) y=$($wa.Y) w=$($wa.Width) h=$($wa.Height) right=$($wa.Right) bottom=$($wa.Bottom)")
  $ok=(InsideRect $r $wa 10); Check $ok "$tag window lies inside the work area by UIA bounds (initial state, not maximized by the driver)"
  foreach($bn in @($buttons)){ $b=@(ByNameIn $w $bn); if($b.Count -ne 1){ Check $false "$tag button '$bn' found exactly once (actual $($b.Count))"; continue }; $br=$b[0].Current.BoundingRectangle; Say ("BOUNDS $tag button [$bn] x=$([int]$br.X) y=$([int]$br.Y) w=$([int]$br.Width) h=$([int]$br.Height) offscreen=$($b[0].Current.IsOffscreen)"); Check ((InsideRect $br $wa 2) -and (InsideRect $br $r 2) -and -not $b[0].Current.IsOffscreen) "$tag button '$bn' is inside the window and the work area by UIA bounds" }
  return $ok }
function ByNameIn($root,$name){ $c=New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,$name)),(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))); return @($root.FindAll($TS::Descendants,$c)) }
function ValueIn($root,$id){ $e=ById $root $id 3; if(-not $e){ return $null }; try{ return [string]$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ return (NormTxt $e.Current.Name) } }
function GridHeads($g){ return @($g.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::HeaderItem)))) }
function SnapGate($a,$b,$allowed,$tag){ if($null -eq $a -or $null -eq $b){ [void](Gate $false "$tag snapshot pair complete"); return }; $d=@(SnapDiff $a $b | Sort-Object); $e=@($allowed | Sort-Object); $same=((($d -join ',') -ceq ($e -join ','))); foreach($k in $d){ Say "INFO $tag changed table $k" }; [void](Gate $same "$tag whole-database diff is exactly [$($e -join ',')] (actual [$($d -join ',')])") }
# ======== stock-rate drill (synthetic TRIAL data only) ========
function AllWins(){ $o=@(); foreach($w in @(TopWins $p.Id)){ $o+=$w; try{ $o+=@($w.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window)))) }catch{} }; return $o }
function WaitOpenDialog($sec,$tag,$titles){ $end=(Get-Date).AddSeconds($sec); $ro=RealOps; $found=@()
  do{ Start-Sleep -Milliseconds 500; $found=@(); foreach($w in @(AllWins)){ try{ if(@($titles) -ccontains [string]$w.Current.Name -and [string]$w.Current.ClassName -eq '#32770'){ $h=[int64]$w.Current.NativeWindowHandle; if($h -ne 0 -and [uint32](& $ro.Pid $h) -eq [uint32]$p.Id -and @(ResolveNameEdit @(& $ro.Kids $h)).Count -eq 1){ $found+=$w } } }catch{} } }while($found.Count -eq 0 -and (Get-Date) -lt $end)
  if($found.Count -ne 1){ Say "INFO $tag file dialogs found process-wide: $($found.Count)"; FailDiag "$tag-nodialog" }
  return $found }
function SaveViaWin32($dlg,$path,$ops,$btn){
  $h=$dlg.Hwnd
  $cls=[string](@($ops.Cls.Invoke($h))[0]); if($cls -ne '#32770'){ return @{ ok=$false; why="Save As window class is '$cls', not #32770" } }
  if([uint32](@($ops.Pid.Invoke($h))[0]) -ne [uint32]$ops.AppPid){ return @{ ok=$false; why='Save As window belongs to another process' } }
  $kids=@($ops.Kids.Invoke($h))
  $ed=@(ResolveNameEdit $kids); $sv=@($kids | Where-Object { $_.Id -eq 1 -and $_.Cls -eq 'Button' -and (($_.Txt -replace '&','') -eq $btn) })
  if($ed.Count -ne 1){ return @{ ok=$false; why="file name Edit candidates: $($ed.Count) (need exactly 1); descendants=$(@($kids).Count)" } }
  if($sv.Count -ne 1){ return @{ ok=$false; why="child windows with ctrl id 1 class Button text $btn`: $($sv.Count) (need exactly 1)" } }
  [void]$ops.SetText.Invoke($ed[0].H,$path)
  $back=[string](@($ops.Txt.Invoke($ed[0].H))[0]); if($back -ne $path){ return @{ ok=$false; why="file name box read back '$back', not the requested path"; typed=$false } }
  [void]$ops.Click.Invoke($sv[0].H)
  return @{ ok=$true; why=''; typed=$true } }
# Source: MainWindow.xaml: StockRateButton (x:Name, so AutomationId) sits in the collapsed InvMoreExpander; collapsed content is absent from UIA, so expand first (same lesson as the stocktake run 45734349877).
function ExpandMore2($tag){ $x=ById $main 'InvMoreExpander' 8; if(-not $x){ Say "FAIL $tag InvMoreExpander not found"; $script:fails++; Halt "$tag expander"; return $false }
  try{ $ec=$x.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern); $st=[string]$ec.Current.ExpandCollapseState; Say "INFO $tag expander state before: $st"; if($st -ne 'Expanded'){ $ec.Expand(); Start-Sleep -Milliseconds 800 }; $st=[string]$ec.Current.ExpandCollapseState; Say "INFO $tag expander state after: $st" }catch{ Say "FAIL $tag expander pattern failed: $($_.Exception.Message) patterns=$(Patterns $x)"; $script:fails++; Halt "$tag expander"; return $false }
  if($st -ne 'Expanded'){ Say "FAIL $tag expander not expanded ($st)"; $script:fails++; Halt "$tag expander"; return $false }; return $true }
function PressId($win,$id,$tag){ if(-not (Guard $tag)){ return $false }; $e=ById $win $id 5; if(-not $e){ Say "FAIL $tag button $id not found"; $script:fails++; Halt "$tag button"; return $false }
  if(-not $e.Current.IsEnabled){ Say "FAIL $tag button $id disabled"; $script:fails++; Halt "$tag disabled"; return $false }
  try{ $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Say "STEP $tag pressed $id"; Start-Sleep -Milliseconds 1500; return $true }catch{ Say "FAIL $tag Invoke failed on $id`: $($_.Exception.Message)"; $script:fails++; Halt "$tag invoke"; return $false } }
function SelectCombo($win,$id,$pred,$tag){ $c=ById $win $id 5; if(-not $c){ Say "FAIL $tag combo $id not found"; return $false }
  try{ $ec=$c.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern); $ec.Expand(); Start-Sleep -Milliseconds 800
    $lc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)
    $items=@($c.FindAll($TS::Descendants,$lc)); if($items.Count -eq 0){ $pc=New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty,$p.Id); $items=@($AE::RootElement.FindAll($TS::Descendants,(New-Object System.Windows.Automation.AndCondition($lc,$pc)))) }
    $names=@($items | ForEach-Object { NormTxt $_.Current.Name }); Say "INFO $tag $id items: $($names -join ' | ')"
    $hit=@(); foreach($it in $items){ if(& $pred (NormTxt $it.Current.Name)){ $hit+=$it } }
    if($hit.Count -ne 1){ Say "FAIL $tag $id matching items: $($hit.Count) (need exactly 1)"; Shot "dlg-$tag-combo"; try{ $ec.Collapse() }catch{}; return $false }
    $hit[0].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 700; try{ $ec.Collapse() }catch{}; Start-Sleep -Milliseconds 400
    $sel=@($c.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()); $nm=''; if($sel.Count -eq 1){ $nm=NormTxt $sel[0].Current.Name }
    $ok=($sel.Count -eq 1 -and [bool](& $pred $nm)); Say "INFO $tag $id selection read back: [$nm] ok=$ok"; return $ok }catch{ Say "FAIL $tag combo $id failed: $($_.Exception.Message) patterns=$(Patterns $c)"; return $false } }
function ComboNow($win,$id){ $c=ById $win $id 5; if(-not $c){ return $null }; try{ $sel=@($c.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()); if($sel.Count -eq 1){ return (NormTxt $sel[0].Current.Name) } }catch{}; return $null }

# ---- r112 import drill helpers ----
function NumEq($cell,$dec){ $x=NormTxt $cell; $d=[decimal]0; if([decimal]::TryParse($x,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d)){ return ($d -eq [decimal]$dec) }; return $false }
function Rc($snap,$t){ if($null -eq $snap -or -not $snap.ContainsKey($t)){ return -1 }; return [int](($snap[$t] -split '\|')[0]) }
function Fx($n){ if([System.IO.Path]::IsPathRooted($n)){ return $n }; return (Join-Path $FixDir $n) }
function Btn($name,$tag){ $b=@(ByName $name ([System.Windows.Automation.ControlType]::Button)); if($b.Count -ne 1){ Say "FAIL $tag button '$name' found $($b.Count) times (need 1)"; $script:fails++; Halt "$tag button"; return $null }; return $b[0] }
function ValTxt($id){ $v=ValueIn $main $id; if($null -eq $v){ return '(missing)' }; return [string]$v }
function MapDump($tag){ $g=ById $main 'MappingGrid' 6; if(-not $g){ Say "FAIL $tag MappingGrid not found"; $script:fails++; return '' }; $o=@(); foreach($e in @($g.FindAll($TS::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){ $n=[string]$e.Current.Name; $v=''; try{ $v=[string]$e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{}; if($n -and $n -notlike 'Pharmacy.*' -and $n -notlike 'System.*'){ $o+=$n }; if($v){ $o+=('value:'+$v) } }; $t=(@($o | Select-Object -Unique) -join ' | '); Say "MAPPING $tag : $t"; try{ ($o | Select-Object -Unique) | Set-Content -Path (Join-Path $OutDir ("mapping-$tag.txt")) -Encoding UTF8 }catch{}; return $t }
function ModalDismiss($tag){ $m=FindModal; if(-not $m){ return $null }; $script:curModal=$m; $txt=(@(WinBoxStatics $m) -join ' / '); Say "MODAL $tag title=[$($m.Current.Name)] text=[$txt]"; Shot "modal-$tag"; Dump $m "modal-$tag"
  # v4: dismiss only by a physical click on an identified OK button (UIA dump logged); no Enter/keyboard fallback. An unidentified dialog halts the run.
  $descs=ModalDescs $m; Say "INFO $tag dismiss controls: $((@($descs | ForEach-Object { $_.type.Replace('ControlType.','')+':'+$_.id+':'+$_.name }) -join ' ; '))"
  $ok=XPickButton $descs 'ok'; if(-not $ok){ Say "FAIL $tag the dialog has no identifiable single OK button; nothing pressed"; $script:fails++; Halt "$tag dismiss"; return $txt }
  [void](PressDesc $ok $tag 'OK'); Start-Sleep -Milliseconds 500; return $txt }
function WaitModal($sec){ $end=(Get-Date).AddSeconds($sec); do{ $m=FindModal; if($m){ return $m }; Start-Sleep -Milliseconds 300 }while((Get-Date) -lt $end); return $null }
# v5c: find a mapping-grid row by its FIELD LABEL (never by count or position). Returns found, the row's chooser selection and the row's own text. The grid is virtualized: unrealized rows are simply absent.
function MapRow($tag,$labelPat){ $r=@{ found=$false; combo=''; status=''; why='' }; $g=ById $main 'MappingGrid' 6; if(-not $g){ $r.why='grid missing'; return $r }
  $cc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ComboBox); $tcn=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text); $w=[System.Windows.Automation.TreeWalker]::ControlViewWalker
  foreach($e in @($g.FindAll($TS::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){ $n=[string]$e.Current.Name; if($n -notmatch $labelPat){ continue }
    $a=$e; for($k=0;$k -lt 6 -and $a;$k++){ $a=$w.GetParent($a); if(-not $a){ break }; $cb=@($a.FindAll($TS::Descendants,$cc)); if($cb.Count -gt 1){ $r.why='climbed past the row (more than one chooser)'; return $r }
      if($cb.Count -eq 1){ $c=$cb[0]; $t1=''; try{ $sel=@($c.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()); if($sel.Count -ge 1){ $t1=[string]$sel[0].Current.Name } }catch{}
        if(-not $t1){ try{ $t1=[string]$c.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{} }
        $tx=@(); foreach($x in @($a.FindAll($TS::Descendants,$tcn))){ $nn=[string]$x.Current.Name; if($nn -and $nn -ne $n){ $tx+=$nn } }
        $r.found=$true; $r.combo=(NormTxt $t1); $r.status=(NormTxt (($tx | Select-Object -Unique) -join ' ')); $r.why="row label [$(NormTxt $n)]"; return $r } }
    $r.why="label [$(NormTxt $n)] found but no single-chooser row ancestor"; return $r }
  $r.why='label not realized in the grid'; return $r }
# v5c: bounded physical wheel over the grid: grid bounds non-empty and inside our main window, our window in the foreground, one logged notch. No keyboard.
function WheelGrid($tag,$notch){ $g=ById $main 'MappingGrid' 6; if(-not $g){ Say "INFO $tag wheel: grid missing"; return $false }
  try{ $gb=$g.Current.BoundingRectangle; $mb=$main.Current.BoundingRectangle }catch{ Say "INFO $tag wheel: bounds unreadable"; return $false }
  if($gb.IsEmpty -or $gb.Width -lt 50 -or $gb.Height -lt 50 -or $gb.Left -lt $mb.Left -or $gb.Right -gt ($mb.Right+2) -or $gb.Top -lt $mb.Top -or $gb.Top -gt $mb.Bottom){ Say "INFO $tag wheel: grid bounds not usable grid=($([int]$gb.X),$([int]$gb.Y),$([int]$gb.Width),$([int]$gb.Height)) window=($([int]$mb.X),$([int]$mb.Y),$([int]$mb.Width),$([int]$mb.Height)); nothing done"; return $false }
  if(-not (FgOurs)){ Say "INFO $tag wheel: app not foreground; nothing done"; return $false }
  $cx=[int]($gb.X+$gb.Width/2); $cy=[int]([math]::Min($gb.Y+$gb.Height/2,$mb.Bottom-5)); $d=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int](-120)),0)
  Say "INFO $tag wheel notch $notch at ($cx,$cy) over the mapping grid"; [void][M.U]::SetCursorPos($cx,$cy); Start-Sleep -Milliseconds 300; [M.U]::mouse_event(0x0800,0,0,$d,[UIntPtr]::Zero); Start-Sleep -Milliseconds 700; return $true }
function SheetIs($tag,$want){ $sn=ComboNow $main 'ExcelSheet'; $ok=($null -ne $sn -and $sn -ceq $want); Check $ok "$tag the import tab's selected sheet (ExcelSheet selection read back) is [$want] (actual [$sn])"; return $ok }
function OpenFile($name,$tag){ if(-not (Guard $tag)){ return $false }; $b=Btn 'اختيار ملف XLSX' $tag; if(-not $b){ return $false }
  try{ $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL $tag open button invoke failed: $($_.Exception.Message)"; $script:fails++; Halt "$tag open"; return $false }
  $dl=@(WaitOpenDialog 15 $tag @('Open','فتح')); if($dl.Count -ne 1){ Say "FAIL $tag Open dialogs: $($dl.Count)"; $script:fails++; Halt "$tag open dialog"; return $false }
  $h=[int64]$dl[0].Current.NativeWindowHandle; $fg=FgOurs; if(-not $fg){ try{ [void][M.W]::SetForegroundWindow([System.IntPtr]$h); Start-Sleep -Milliseconds 500 }catch{}; $fg=FgOurs }
  if(-not $fg){ Say "FAIL $tag app not foreground; nothing typed"; $script:fails++; Halt "$tag keyboard"; return $false }
  $path=Fx $name; [System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 300
  foreach($ch in $path.ToCharArray()){ if(-not (FgOurs)){ Say "FAIL $tag foreground lost while typing"; $script:fails++; Halt "$tag typing"; return $false }; [System.Windows.Forms.SendKeys]::SendWait((EscKey $ch)); Start-Sleep -Milliseconds 15 }
  Start-Sleep -Milliseconds 500; Shot "dlg-$tag-open-typed"; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 2500
  $lbl=NormTxt (TxtOf 'ExcelFileLabel'); $leaf=[System.IO.Path]::GetFileName($name); $ok=($lbl -ceq $leaf); Check $ok "$tag the file label shows the chosen file [$leaf] (actual [$lbl])"; if(-not $ok){ FailDiag "$tag-open"; Halt "$tag file not chosen" }; return $ok }
function SetMode($label,$tag){ $ok=SelectCombo $main 'ExcelMode' { param($n) $n -ceq (NormTxt $label) } "$tag-mode"; Check $ok "$tag mode set to [$label] and read back"; if(-not $ok){ Halt "$tag mode" }; return $ok }
function ReadMap($tag){ if(-not (Guard $tag)){ return $null }; if(-not (PressByName 'قراءة واقتراح الربط' "$tag-read")){ return $null }; Start-Sleep -Milliseconds 2500; $v=NormTxt (ValTxt 'ExcelValidation'); Say "INFO $tag validation box after read: [$($v -replace '\s+',' ')]"
  $mt=MapDump $tag; Reveal $main 'MappingGrid' $tag; Shot "$tag-mapping"; Reveal $main 'ExcelPreviewGrid' $tag; Shot "$tag-preview"; return $mt }
function SetConfirm($tag){ $c=ById $main 'ExcelConfirm' 5; if(-not $c){ Say "FAIL $tag ExcelConfirm not found"; $script:fails++; Halt "$tag confirm"; return $false }
  try{ $tp=$c.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern); if([string]$tp.Current.ToggleState -ne 'On'){ $tp.Toggle(); Start-Sleep -Milliseconds 500 }; $st=[string]$tp.Current.ToggleState; Check ($st -eq 'On') "$tag the review checkbox is on (state $st)"; return ($st -eq 'On') }catch{ Say "FAIL $tag confirm toggle failed: $($_.Exception.Message)"; $script:fails++; return $false } }
# Validate: returns @{ refused=bool; text=... }. A refusal is a modal error and/or a validation box starting with the refusal word.
function DoValidate($tag){ if(-not (PressByName 'تحقق دون حفظ' "$tag-validate")){ return @{ refused=$null; text='(not pressed)' } }; $m=WaitModal 6; $mt=$null; if($m){ $mt=ModalDismiss "$tag-validate" }; Start-Sleep -Milliseconds 800; $v=NormTxt (ValTxt 'ExcelValidation'); $ref=($null -ne $mt) -or ($v -like 'مرفوض*'); Say "INFO $tag validate: refused=$ref modal=[$mt] box=[$($v -replace '\s+',' ')]"; Reveal $main 'ExcelValidation' $tag; Shot "$tag-validate"; $script:Boxes["$tag|validate"]="$mt || $v"; return @{ refused=$ref; text=("$mt || $v") } }
# Commit (v3): the confirmation dialog is recognised by its title and its Yes/No buttons are chosen by name or id from a logged UIA dump; Yes is invoked on purpose (never Enter on a default button). An unexpected confirm is answered No and recorded as FAIL. A refusal dialog (no confirm title) is dismissed with its OK button.
function ModalDescs($m){ $o=@(); foreach($e in @($m.FindAll($TS::Descendants,[System.Windows.Automation.Condition]::TrueCondition))){ $o+=@{ type=[string]$e.Current.ControlType.ProgrammaticName; id=[string]$e.Current.AutomationId; name=[string]$e.Current.Name; el=$e } }; return ,$o }
function PressDesc($d,$tag,$label){ $el=$d.el; $m=$script:curModal
  # v4: physical mouse click on the observed button bounds. Checks: modal exists and is our process's top-level #32770, button bounds non-empty and inside the modal bounds, modal is foreground (one SetForegroundWindow attempt, then re-check). No keyboard fallback.
  if(-not $m){ Say "FAIL $tag no modal handle for pressing [$label]"; $script:fails++; return $false }
  try{ $mb=$m.Current.BoundingRectangle; $bb=$el.Current.BoundingRectangle; $mh=[int64]$m.Current.NativeWindowHandle }catch{ Say "FAIL $tag could not read modal/button bounds for [$label]: $($_.Exception.Message)"; $script:fails++; return $false }
  Say "INFO $tag press-plan [$label] control type=$($d.type) id=[$($d.id)] name=[$($d.name)] buttonRect=($($bb.X),$($bb.Y),$($bb.Width),$($bb.Height)) modalRect=($($mb.X),$($mb.Y),$($mb.Width),$($mb.Height)) modalClass=[$($m.Current.ClassName)] modalHwnd=$mh"
  if($bb.IsEmpty -or $bb.Width -lt 20 -or $bb.Height -lt 10){ Say "FAIL $tag button bounds empty or too small; nothing clicked"; $script:fails++; return $false }
  $cx=[int]($bb.X+$bb.Width/2); $cy=[int]($bb.Y+$bb.Height/2)
  if(-not (XPtInRect $cx $cy $mb.X $mb.Y $mb.Width $mb.Height)){ Say "FAIL $tag click point ($cx,$cy) is outside the modal bounds; nothing clicked"; $script:fails++; return $false }
  $fgh=[int64][M.W]::GetForegroundWindow(); if($fgh -ne $mh){ try{ [void][M.W]::SetForegroundWindow([System.IntPtr]$mh); Start-Sleep -Milliseconds 500 }catch{}; $fgh=[int64][M.W]::GetForegroundWindow() }
  Say "INFO $tag foreground window handle=$fgh modal handle=$mh ours=$(FgOurs)"
  if($fgh -ne $mh){ Say "FAIL $tag the modal is not the foreground window; nothing clicked"; $script:fails++; return $false }
  $cur=FindModal; if(-not $cur -or ([int64]$cur.Current.NativeWindowHandle) -ne $mh){ Say "FAIL $tag the modal changed before the click; nothing clicked"; $script:fails++; return $false }
  [void][M.U]::SetCursorPos($cx,$cy); Start-Sleep -Milliseconds 400; [M.U]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 120; [M.U]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
  Say "CONFIRM-CLICK $tag physical left click on [$label] at ($cx,$cy) inside modal hwnd=$mh (button id=[$($d.id)] name=[$($d.name)])"
  Start-Sleep -Milliseconds 1200; $after=FindModal; $gone=($null -eq $after -or ([int64]$after.Current.NativeWindowHandle) -ne $mh)
  Say "INFO $tag click outcome: modal $(if($gone){'closed'}else{'STILL OPEN'})"; if(-not $gone){ Say "FAIL $tag the modal is still open after the click on [$label]"; $script:fails++; return $false }
  return $true }
function DoCommit($tag,$expectConfirm){ if(-not (PressByName 'تأكيد وتطبيق بالكامل' "$tag-commit")){ return @{ refused=$null; confirmed=$false; text='(not pressed)' } }
  $m=WaitModal 10; $confirmed=$false; $txt=''; $ref=$false
  if($m){ $script:curModal=$m; $title=[string]$m.Current.Name; $txt=(@(WinBoxStatics $m) -join ' / '); Dump $m "modal-$tag"; $descs=ModalDescs $m; Say "INFO $tag modal title=[$title] controls: $((@($descs | ForEach-Object { $_.type.Replace('ControlType.','')+':'+$_.id+':'+$_.name }) -join ' ; '))"
    $yes=XPickButton $descs 'yes'; $no=XPickButton $descs 'no'
    if(XIsConfirmTitle $title){ Shot "modal-$tag-confirm"
      if(-not $yes -or -not $no){ Say "FAIL $tag the confirmation dialog has no identifiable single Yes and No button; nothing pressed (no Enter fallback)"; $script:fails++; Halt "$tag confirm buttons"; return @{ refused=$null; confirmed=$false; text='(confirm buttons unidentified)' } }
      if($expectConfirm){ if(PressDesc $yes $tag 'Yes'){ $confirmed=$true; Start-Sleep -Milliseconds 2500 } }
      else { Say "FAIL $tag the app asked for a confirmation although the import should have been refused before it; answering No"; $script:fails++; [void](PressDesc $no $tag 'No'); $ref=$true; Start-Sleep -Milliseconds 800 } }
    else { Say "INFO $tag the dialog is not the confirmation (title [$title]); dismissing it as a refusal"; $txt=ModalDismiss "$tag-commit-refusal"; $ref=$true } }
  Start-Sleep -Milliseconds 800; $v=NormTxt (ValTxt 'ExcelValidation'); if($v -like 'مرفوض*'){ $ref=$true }
  Say "INFO $tag commit: refused=$ref confirmed=$confirmed modal=[$txt] box=[$($v -replace '\s+',' ')]"; Reveal $main 'ExcelValidation' $tag; Shot "$tag-after-commit"; $script:Boxes["$tag|commit"]="$txt || $v"; return @{ refused=$ref; confirmed=$confirmed; text="$txt || $v" } }
# Mapping choosers (v3): the selected source column of each mapping row, read from the ComboBox elements (selection, value, or inner text), logged and written to a file.
function MapCombos($tag){ $g=ById $main 'MappingGrid' 6; $res=@(); if(-not $g){ Say "FAIL $tag MappingGrid not found for combos"; $script:fails++; return $res }
  $cc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ComboBox); $i=0
  foreach($c in @($g.FindAll($TS::Descendants,$cc))){ $t=''
    try{ $sel=@($c.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()); if($sel.Count -ge 1){ $t=[string]$sel[0].Current.Name } }catch{}
    if(-not $t){ try{ $t=[string]$c.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{} }
    if(-not $t){ $tx=@(); foreach($e in @($c.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))))){ $n=[string]$e.Current.Name; if($n){ $tx+=$n } }; $t=($tx -join ' ') }
    $i++; $res+=(NormTxt $t); Say "MAPCOMBO $tag row#$i selected=[$(NormTxt $t)] offscreen=$($c.Current.IsOffscreen)" }
  try{ $res | Set-Content -Path (Join-Path $OutDir "mapcombos-$tag.txt") -Encoding UTF8 }catch{}; return $res }
function MapComboCheck($tag,$pats,$what){ $cb=@(MapCombos $tag); $ok=(XComboOk $cb $pats)
  Check $ok "$tag the mapping choosers show $what (read from the ComboBox elements; $($cb.Count) choosers read: [$($cb -join ' | ')])" }
function ExportMode($label,$file,$tag){ if(-not (SetMode $label "$tag")){ return $false }; if(Test-Path $file){ Remove-Item $file -Force }
  if(-not (PressByName 'تصدير الوضع المحدد' "$tag-export")){ return $false }
  $dl=@(WaitOpenDialog 15 $tag @('Save As')); if($dl.Count -ne 1){ Say "FAIL $tag Save As dialogs: $($dl.Count)"; $script:fails++; Halt "$tag save dialog"; return $false }
  $h=[int64]$dl[0].Current.NativeWindowHandle; $fg=FgOurs; if(-not $fg){ try{ [void][M.W]::SetForegroundWindow([System.IntPtr]$h); Start-Sleep -Milliseconds 500 }catch{}; $fg=FgOurs }
  if(-not $fg){ Say "FAIL $tag app not foreground"; $script:fails++; Halt "$tag keyboard"; return $false }
  [System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 300; foreach($ch in $file.ToCharArray()){ if(-not (FgOurs)){ Say "FAIL $tag foreground lost"; $script:fails++; Halt "$tag typing"; return $false }; [System.Windows.Forms.SendKeys]::SendWait((EscKey $ch)); Start-Sleep -Milliseconds 15 }
  Start-Sleep -Milliseconds 500; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); $end=(Get-Date).AddSeconds(25); do{ Start-Sleep -Milliseconds 700 }while(-not (Test-Path $file) -and (Get-Date) -lt $end); Start-Sleep 2
  $ex=Test-Path $file; Check $ex "$tag export file exists at the typed path"; if($ex){ Say "INFO $tag export bytes=$((Get-Item $file).Length) sha256=$((Get-FileHash -Algorithm SHA256 $file).Hash.ToLower())" }; return $ex }
function RowByCell($rows,$val){ $m=@(); foreach($r in @($rows)){ if(@($r) -ccontains $val){ $m+=,@($r) } }; return ,$m }

# ---- the drill ----
# ---- l116 Stocktake refusal probe (replaces the import drill): open the Stocktake window, press Begin with NO batch selected, read the status line ----
function RevealEl($root,$e,$tag){ $wa=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $wr=$root.Current.BoundingRectangle
  $top=[math]::Max($wr.Top,$wa.Top); $bot=[math]::Min($wr.Bottom,$wa.Bottom)
  function FracS($x){ $r=$x.Current.BoundingRectangle; if($r.Height -le 0){ return 0.0 }; return [math]::Max(0,[math]::Min($r.Bottom,$bot)-[math]::Max($r.Top,$top))/$r.Height }
  $f=FracS $e; $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker; $a=$walker.GetParent($e); $n=0
  while($a -and $n -lt 25 -and $f -lt 0.97){ $n++; try{ $sp=$a.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern); if($sp.Current.VerticallyScrollable){ for($i=0;$i -lt 14 -and $f -lt 0.97;$i++){ $below=($e.Current.BoundingRectangle.Bottom -gt $bot); $sp.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount,$(if($below){[System.Windows.Automation.ScrollAmount]::LargeIncrement}else{[System.Windows.Automation.ScrollAmount]::SmallDecrement})); Start-Sleep -Milliseconds 300; $f=FracS $e } } }catch{}; $a=$walker.GetParent($a) }
  Say "INFO $tag reveal status text: visible_fraction_inside_window_and_screen_by_UIA=$([math]::Round($f,2)) (UIA bounds only, not pixel proof; inspect the screenshot)"; return $f }
function StatusEl($root,$prefix){ $m=@(); foreach($x in @($root.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))))){ if(([string]$x.Current.Name).StartsWith($prefix)){ $m+=$x } }; if($m.Count -eq 1){ return $m[0] }; return $null }
$script:StkWin='الجرد الفعلي المحلي'
function FindStkWin($sec){ $end=(Get-Date).AddSeconds($sec); do{ foreach($w in @(AllWinsDeep)){ try{ if([string]$w.Current.Name -ceq $script:StkWin -and $w.Current.ClassName -ne '#32770' -and (ById $w 'StocktakeBatches' 0)){ return $w } }catch{} }; Start-Sleep -Milliseconds 400 }while((Get-Date) -lt $end); return $null }
function StkGone($sec){ $end=(Get-Date).AddSeconds($sec); do{ if(-not (FindStkWin 0)){ return $true }; Start-Sleep -Milliseconds 400 }while((Get-Date) -lt $end); return $false }
function HdrCheck($gridId,$tag){
  $g=Pick $gridId 4; if(-not $g){ Say "INFO $tag grid $gridId not present on this page"; return }
  $gr=$g.Current.BoundingRectangle
  $hs=@($g.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::HeaderItem))))
  $sbs=@($g.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ScrollBar)))) | Where-Object { $o=$_.Current.Orientation; -not $_.Current.IsOffscreen -and $_.Current.BoundingRectangle.Width -gt 0 -and "$o" -eq 'Vertical' }
  Say "DIAG $tag grid x=$([int]$gr.X) w=$([int]$gr.Width) header items=$($hs.Count) vertical scrollbars=$(@($sbs).Count)"
  foreach($h in $hs){ $r=$h.Current.BoundingRectangle; if($r.Width -le 0){ continue }; $inside=($r.Left -ge ($gr.Left-2) -and $r.Right -le ($gr.Right+2)); $hit=$false; foreach($sb in @($sbs)){ $q=$sb.Current.BoundingRectangle; $ov=[math]::Min($r.Right,$q.Right)-[math]::Max($r.Left,$q.Left); if($ov -gt 2){ $hit=$true } }
    Say "DIAG $tag header [$($h.Current.Name)] x=$([int]$r.X) w=$([int]$r.Width) h=$([int]$r.Height) insideGrid=$inside overlapsScrollbar=$hit"
    if(-not $inside -or $hit){ Say "FAIL $tag header [$($h.Current.Name)] is cut off (outside the grid edge or under the scrollbar; UIA bounds, confirm in the screenshot)"; $script:fails++ } }
}
if(Login 'owner' $pwOwner 'owner'){
  Start-Sleep 2
  Shot '01-default-after-login'
  $r=@(RailDiag 'default-layout')
  Check ($r.Count -ge 8) "default layout: the navigation rail is present right after the first owner login with no setting touched ($($r.Count) rail items)"
  $wb0=ById $main 'WhatsAppButton' 3; Check ($null -eq $wb0 -or $wb0.Current.IsOffscreen) 'WhatsApp: the button is hidden on a fresh database (no number set)'
  $mk=Join-Path $env:LOCALAPPDATA 'OneForAllGood-TRIAL\new-layout-default.applied'; Check (Test-Path $mk) 'default layout: the one-time default marker was written beside the database'
  # fast sale: scan a seeded barcode
  $sc=Pick 'ScanCode' 6; if($sc){ try{ BringFg | Out-Null; $sc.SetFocus(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait('SR-FAST'); Start-Sleep -Milliseconds 300; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 1500 }catch{ Say "INFO scan failed: $($_.Exception.Message)" }; Shot '02-fast-sale-cart'; $cr=@(Rows 'CartGrid'); Say "DIAG cart rows after scanning SR-FAST: $($cr.Count)"; Check ($cr.Count -ge 1) 'fast sale: scanning SR-FAST puts one line in the cart'; HdrCheck 'CartGrid' 'cart' } else { Say 'NOTEXECUTED fast-sale scan: ScanCode not found'; $script:notexec++ }
  $g=Pick 'StockGrid' 6; if($g){ [void](EnsureGridVisible $g 'sales-stock'); Shot '03-sale-stock-grid'; HdrCheck 'StockGrid' 'stock' } else { Say 'FAIL StockGrid not found'; $script:fails++ }
  $pages=@( @('الأصناف والمشتريات','Products & Purchasing','inventory','InvSearchBox','ProductGrid'), @('الصلاحية والتنبيهات','Expiry and alerts','expiry','ExpiryDays','ExpiryGrid'), @('Excel استيراد وتصدير','Excel import and export','excel','ExcelHeaderRow','MappingGrid'), @('العملاء','Customers','customers','CustomersGrid','CustomersGrid'), @('الموردون','Suppliers','suppliers','SuppliersGrid','SuppliersGrid'), @('المبيعات والورديات','Sales and shifts','reports','SalesGrid','SalesGrid'), @('الفريق والحضور','Team and attendance','team','EmployeeName','EmployeesGrid'), @('مسودة الرواتب','Payroll draft','payroll','PayrollMonth','PayrollGrid'), @('الجدولة والإجازات','Scheduling and leave','planning','PlanStart'), @('الإدارة والنسخ الاحتياطي','Admin and backup','settings','NewUsername') )
  $n=10
  foreach($pg in $pages){ $script:halt=$false; if(NavTo @($pg[0],$pg[1]) "page-$($pg[2])" $pg[3]){ Shot ("{0}-page-{1}" -f $n,$pg[2]); if($pg.Count -gt 4){ HdrCheck $pg[4] "page-$($pg[2])-$($pg[4])" }; if($pg[2] -eq 'reports'){ HdrCheck 'ShiftsGrid' 'page-reports-ShiftsGrid' } } else { Say "FAIL page $($pg[2]) could not be opened by the rail" ; Shot ("{0}-page-{1}-FAILED" -f $n,$pg[2]) }; $n++ }
  $script:halt=$false
  # l136: design pass. Theme toggle: dark screenshots of the sale screen and three pages, then back to light. Screenshots are for a person to read; the assertions only check that the pages open and the toggle button exists.
  try{
    $tt=ById $main 'ThemeToggleButton' 4
    if(-not $tt){ Say 'FAIL design: the theme toggle button was not found'; $script:fails++ }
    else{
      [void](NavTo @('البيع','Sales') 'design-sales-light' 'StockGrid'); Start-Sleep -Milliseconds 500; Shot 'd0-sale-light'
      try{ $tt.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL design toggle invoke: $($_.Exception.Message)"; $script:fails++ }
      Start-Sleep -Milliseconds 900
      if(NavTo @('البيع','Sales') 'design-sales-dark' 'StockGrid'){ Start-Sleep -Milliseconds 500; Shot 'd1-sale-dark' } else { Say 'FAIL design: sales page did not open in dark'; $script:fails++ }
      foreach($dp in @( @('الأصناف والمشتريات','Products & Purchasing','items','InvSearchBox'), @('الصلاحية والتنبيهات','Expiry and alerts','expiry','ExpiryDays'), @('العملاء','Customers','customers','CustomersGrid'), @('المبيعات والورديات','Sales and shifts','reports','SalesGrid'), @('الإدارة والنسخ الاحتياطي','Administration and backup','admin','NewUiBox') )){ $script:halt=$false; if(NavTo @($dp[0],$dp[1]) "design-$($dp[2])-dark" $dp[3]){ Start-Sleep -Milliseconds 500; Shot ("d-{0}-dark" -f $dp[2]) } else { Say "FAIL design: page $($dp[2]) did not open in dark"; $script:fails++ } }
      $script:halt=$false
      $tt2=ById $main 'ThemeToggleButton' 4; if($tt2){ try{ $tt2.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{} ; Start-Sleep -Milliseconds 900 }
      foreach($dp in @( @('الأصناف والمشتريات','Products & Purchasing','items','InvSearchBox'), @('الصلاحية والتنبيهات','Expiry and alerts','expiry','ExpiryDays'), @('العملاء','Customers','customers','CustomersGrid'), @('المبيعات والورديات','Sales and shifts','reports','SalesGrid'), @('الإدارة والنسخ الاحتياطي','Administration and backup','admin','NewUiBox') )){ $script:halt=$false; if(NavTo @($dp[0],$dp[1]) "design-$($dp[2])-light" $dp[3]){ Start-Sleep -Milliseconds 500; Shot ("d-{0}-light" -f $dp[2]) } else { Say "FAIL design: page $($dp[2]) did not open in light"; $script:fails++ } }
      $script:halt=$false
      $tt2=ById $main 'ThemeToggleButton' 4; if($tt2){ try{ $tt2.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{} ; Start-Sleep -Milliseconds 900 }
      $script:halt=$false
      $tt2=ById $main 'ThemeToggleButton' 4; if($tt2){ try{ $tt2.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{} ; Start-Sleep -Milliseconds 900 }
      [void](NavTo @('البيع','Sales') 'design-sales-back' 'StockGrid'); Start-Sleep -Milliseconds 500; Shot 'd9-sale-light-again'
      Say 'PASS design: toggle present, sale screen and pages opened in dark and light (read the d* screenshots)'
    }
  }catch{ Say "FAIL design block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  $cb=Pick 'NewUiBox' 4; if($cb){ $st='?'; try{ $st=$cb.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState }catch{}; Say "DIAG NewUiBox toggle state=$st"; Check ("$st" -eq 'On') 'settings: the new-layout checkbox is ticked by default' } else { Say 'NOTEXECUTED NewUiBox not found'; $script:notexec++ }

  # ---- WhatsApp button: set a SYNTHETIC number from settings, button appears, click opens the link, clear -> hidden ----
  function IsOpsTitle($n){ return ([string]$n).Contains([string][char]0x0627+[string][char]0x0644+[string][char]0x0639+[string][char]0x0645+[string][char]0x0644+[string][char]0x064A+[string][char]0x0627+[string][char]0x062A) }
  function OpsWin(){
    foreach($w in (TopWins $p.Id)){ if($w.Current.ClassName -ne '#32770' -and (IsOpsTitle $w.Current.Name) -and $w.Current.Name -ne $main.Current.Name){ return $w } }
    try{ $wc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window); foreach($w in @($main.FindAll($TS::Descendants,$wc))){ if((IsOpsTitle $w.Current.Name) -and $w.Current.Name -ne $main.Current.Name){ return $w } } }catch{}
    try{ $ac=New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty,$p.Id)),(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))); foreach($w in @($AE::RootElement.FindAll($TS::Descendants,$ac))){ if((IsOpsTitle $w.Current.Name) -and $w.Current.Name -ne $main.Current.Name){ return $w } } }catch{}
    return $null }
  function CloseOps($tag){ for($k=0;$k -lt 3;$k++){ $w=OpsWin; if(-not $w){ Say "PASS $tag Operations window is closed"; return $true }; try{ $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{ Say "INFO $tag WindowPattern.Close failed: $($_.Exception.Message)"; try{ $w.SetFocus(); Start-Sleep -Milliseconds 300; [System.Windows.Forms.SendKeys]::SendWait('%{F4}') }catch{} }; Start-Sleep 2 }; Say "FAIL $tag Operations window would not close"; $script:fails++; return $false }
  function ByName($root,$name,$sec){ $c=New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,$name); $end=(Get-Date).AddSeconds($sec); do{ $e=$root.FindFirst($TS::Descendants,$c); if(-not $e){ Start-Sleep -Milliseconds 400 } }while(-not $e -and (Get-Date) -lt $end); return $e }
  function TabByName($root,$name){ $c=New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)),(New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,$name))); $end=(Get-Date).AddSeconds(5); do{ $e=$root.FindFirst($TS::Descendants,$c); if(-not $e){ Start-Sleep -Milliseconds 400 } }while(-not $e -and (Get-Date) -lt $end); return $e }
  function OpenOps($tag){
    $script:halt=$false; if(OpsWin){ Say "INFO $tag an Operations window is already open; reusing it"; return $true }
    [void](ExpandMore2 "$tag-more"); $script:halt=$false
    $ob=ByName $main 'العمليات والنسخ الاحتياطي' 6
    if($ob){ Say "DIAG $tag Operations button found (offscreen=$($ob.Current.IsOffscreen) enabled=$($ob.Current.IsEnabled))"; try{ $ob.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView() }catch{}; Start-Sleep -Milliseconds 600
      try{ $ob.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 3; if(OpsWin){ Say "PASS $tag Operations window opened via the button"; return $true } }catch{ Say "INFO $tag button invoke failed: $($_.Exception.Message)" } }
    else { Say "INFO $tag Operations button not found after expanding the More-actions expander" }
    $ri=@(RailItems | Where-Object { $_.Label -ceq 'العمليات والنسخ' })
    if($ri.Count -eq 1){ Say "INFO $tag trying the Owner rail item"; try{ $ri[0].El.SetFocus(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait(' '); Start-Sleep 3 }catch{ Say "INFO $tag rail item failed: $($_.Exception.Message)" }; if(OpsWin){ Say "PASS $tag Operations window opened via the rail item"; return $true } }
    Say "FAIL $tag Operations window could not be opened (button found=$([bool]$ob), rail items matching=$($ri.Count))"; $script:fails++; Shot "$tag-ops-not-opened"; DumpAll "$tag-ops-not-opened"; [void](RailDiag "$tag-ops-not-opened")
    try{ $all=@($main.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)))); Say "DIAG $tag buttons in the UIA tree ($($all.Count)): $(($all | ForEach-Object { $_.Current.AutomationId + '=' + $_.Current.Name + $(if($_.Current.IsOffscreen){'(off)'}) }) -join ' | ')" }catch{}
    return $false }
  $script:halt=$false
  if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'wa-inventory' 'InvSearchBox'){  # the Operations button lives on the Products & Purchasing page (MainWindow.xaml, InventoryTab), not on Admin
    $opened=OpenOps 'wa1'; $ow=OpsWin
    if(-not $opened){ Say 'NOTEXECUTED WhatsApp: the Operations window could not be opened (see wa1 diagnostics)'; $script:notexec++ } else {
      if(-not $ow){ Say 'NOTEXECUTED WhatsApp: the Operations window did not open'; $script:notexec++; Shot '40-wa-ops-not-open' } else {
        $tabs=TabByName $ow 'واتساب الصيدلية'
        if($tabs){ try{ $tabs.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }catch{ Say "INFO WhatsApp tab select: $($_.Exception.Message)" }; Start-Sleep 1 }
        $nb=ById $ow 'OpsWhatsAppNumber' 6; $sv=ById $ow 'OpsWhatsAppSave' 4
        if(-not ($nb -and $sv)){ Say 'NOTEXECUTED WhatsApp: number box or save button not found'; $script:notexec++; Shot '41-wa-ops-controls-missing'; DumpAll 'wa-ops' } else {
          $nb.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('+1 555 010 0123'); Start-Sleep -Milliseconds 500
          $sv.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 2; Shot '42-wa-ops-saved'
          $cur=ById $ow 'OpsWhatsAppCurrent' 3; $ct=if($cur){ $cur.Current.Name } else { '(missing)' }; Say "DIAG WhatsApp current-number label: [$ct]"; Check ($ct -like '*15550100123*') 'WhatsApp: the saved synthetic number is shown normalized (+15550100123)'
        }
        [void](CloseOps 'wa1-close')
      }
    }
    $wb=ById $main 'WhatsAppButton' 5
    if(-not $wb){ Say 'FAIL WhatsApp: the button did not appear after a number was saved'; $script:fails++; Shot '43-wa-button-missing' } else {
      Say "PASS WhatsApp: the button appeared after a number was set (name=[$($wb.Current.Name)] enabled=$($wb.Current.IsEnabled))"; Check ($wb.Current.IsEnabled) 'WhatsApp: the button is enabled'; Shot '44-wa-button-visible'
      $before=@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'msedge|chrome|firefox|iexplore' } | ForEach-Object { $_.Id })
      try{ $wb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL WhatsApp: button could not be invoked: $($_.Exception.Message)"; $script:fails++ }
      Start-Sleep 6; Shot '45-wa-after-click'
      $after=@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'msedge|chrome|firefox|iexplore' } | ForEach-Object { $_.Id }); $new=@($after | Where-Object { $before -notcontains $_ })
      Say "DIAG WhatsApp click: browser processes before=$($before.Count) after=$($after.Count) new=$($new.Count); modal=$([bool](FindModal)); app alive=$(-not $p.HasExited)"
      Check ((-not (FindModal)) -and (-not $p.HasExited)) 'WhatsApp: clicking the button gives no error dialog and the app keeps running'
      if($new.Count -gt 0){ Say 'PASS WhatsApp: clicking started a browser process (the wa.me link was handed to the system)' } else { Say 'INFO WhatsApp: no NEW browser process seen (a browser may already have been running, or the shell handled it silently); the screenshot 45 is the evidence' }
      foreach($id in $new){ try{ Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }catch{} }
      try{ $main.SetFocus() }catch{}
    }
    # clear -> hidden again
    $opened2=OpenOps 'wa2'; $ow=OpsWin
    if($opened2){
      if($ow){ $tabs=TabByName $ow 'واتساب الصيدلية'; if($tabs){ try{ $tabs.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }catch{}; Start-Sleep 1 }
        $nb=ById $ow 'OpsWhatsAppNumber' 6; $sv=ById $ow 'OpsWhatsAppSave' 4
        if($nb -and $sv){ $nb.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue(''); Start-Sleep -Milliseconds 400; $sv.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 2 }
        [void](CloseOps 'wa2-close')
        $wb2=ById $main 'WhatsAppButton' 3; Check ($null -eq $wb2 -or $wb2.Current.IsOffscreen) 'WhatsApp: clearing the number hides the button again'; Shot '46-wa-cleared-hidden' } }
  }

  # ---- Add-item form (l118d): required markers, blank-barcode internal code, name typing with mixed Latin/digits, auto-select the saved row ----
  if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'item-inventory' 'InvSearchBox'){
    $tg=$null; if(-not (Pick 'ProductName' 2)){ $tg=Pick 'InvPanelToggleButton' 6 }
    if($tg){ try{ $tg.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ try{ $tg.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle() }catch{ Say "INFO item panel toggle failed: $($_.Exception.Message)" } }; Start-Sleep 2 }
    $pn=Pick 'ProductName' 6
    if(-not $pn){ Say 'NOTEXECUTED item form: ProductName not found'; Shot '50-item-form-not-found' } else {
      Shot '50-item-form-initial'
      $bh=Pick 'BarcodeHint' 3; Check ($null -ne $bh) 'item form: the blank-barcode hint is on screen'
      $rs=Pick 'ReceiveStepsHint' 3; Check ($null -ne $rs) 'item form: the receive-panel steps hint is on screen'
      try{ BringFg | Out-Null; $pn.SetFocus(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait('Panadol Extra 48 tab'); Start-Sleep -Milliseconds 800 }catch{ Say "INFO typing name failed: $($_.Exception.Message)" }
      $nv=''; try{ $nv=$pn.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{}
      Check ($nv -ceq 'Panadol Extra 48 tab') "item form: the typed mixed name is stored in typing order (value [$nv])"
      Shot '51-item-name-typed'
      $pp=Pick 'ProductPrice' 4; if($pp){ $pp.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('12.50') }
      $bc=Pick 'ProductBarcode' 4; if($bc){ $bcv=$bc.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value; Check ($bcv -eq '') 'item form: the barcode box is left empty' }
      $sb=$main.FindFirst($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty,'حفظ صنف')))
      if(-not $sb){ Say 'NOTEXECUTED item form: the save button was not found' } else {
        try{ $sb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL item form: save invoke failed: $($_.Exception.Message)"; $script:fails++ }
        Start-Sleep 3; Check (-not (FindModal)) 'item form: saving with a blank barcode gives no error dialog'; Shot '52-item-saved'
        $rows=@(Rows 'ProductGrid'); $hit=$null; foreach($r in $rows){ if($null -eq $r){ continue }; $cn=@(CellNames $r); if(($cn -join '|') -like '*Panadol Extra 48 tab*'){ $hit=$r; Say "DIAG item row cells: $($cn -join ' | ')" } }
        Check ($null -ne $hit) 'item form: the new item appears in the table'
        if($hit){ $cn=@(CellNames $hit); Check ((($cn -join '|') -match 'L-\d{6}-\d{6}')) 'item form: the barcode column holds an internal code L-yymmdd-hhmmss'
          $sel=$false; try{ $sel=[bool]$hit.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }catch{ Say "INFO item row selection pattern: $($_.Exception.Message)" }
          Check $sel 'item form: the new row is selected automatically' }
        $lbl=Pick 'InvSelectedLabel' 3; if($lbl){ Say "DIAG selected-item label: [$($lbl.Current.Name)]" ; Check ($lbl.Current.Name -like '*Panadol Extra 48 tab*') 'item form: the receive panel names the new item' } else { Say 'INFO InvSelectedLabel not found by id (no automation id); see screenshot 52' }

        # ---- Item card (l119a): open for the selected new item, fill, save, reopen, verify persistence ----
        $cardWin={ foreach($w in (TopWins $p.Id)){ if($w.Current.Name -eq 'بطاقة الصنف' -and $w.Current.Name -ne $main.Current.Name){ return $w } }; try{ $wc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window); foreach($w in @($main.FindAll($TS::Descendants,$wc))){ if($w.Current.Name -eq 'بطاقة الصنف'){ return $w } } }catch{}; return $null }
        $cb=Pick 'ItemCardButton' 4
        if(-not $cb){ Say 'NOTEXECUTED item card: ItemCardButton not found'; Shot '53-itemcard-button-missing' } else {
          try{ $cb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL item card: button invoke failed: $($_.Exception.Message)"; $script:fails++ }
          Start-Sleep 3; $cw=& $cardWin
          if(-not $cw){ Say 'NOTEXECUTED item card: window did not open'; Shot '53-itemcard-not-open' } else {
            Check $true 'item card: the window opened'; Shot '54-itemcard-open'
            foreach($pair in @(@('CardDosageForm','أقراص'),@('CardCategory','مسكنات وخافضات حرارة'),@('CardShelf',''))){
              $cmb=ById $cw $pair[0] 4
              if(-not $cmb){ Say "FAIL item card: dropdown $($pair[0]) not found"; $script:fails++; continue }
              try{ $ecp=$cmb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern); $ecp.Expand(); Start-Sleep -Milliseconds 800
                $lc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem); $its=@($cmb.FindAll($TS::Descendants,$lc)); $nm=@($its | ForEach-Object { $_.Current.Name })
                Say "DIAG item card dropdown $($pair[0]) lists $($nm.Count) items: $(($nm | Select-Object -First 6) -join ' , ')"
                if($pair[0] -eq 'CardDosageForm'){ Shot '54b-itemcard-dosage-list-open' }
                if($pair[1] -ne ''){ Check ($nm -contains $pair[1]) "item card: dropdown $($pair[0]) lists the seeded value $($pair[1])" } else { Say "INFO item card: $($pair[0]) has no seeded values by design (count $($nm.Count))" }
                $ecp.Collapse(); Start-Sleep -Milliseconds 400
              }catch{ Say "FAIL item card: could not expand $($pair[0]): $($_.Exception.Message)"; $script:fails++ }
            }
            $setv={ param($id,$val) $e=ById $cw $id 4; if(-not $e){ Say "FAIL item card: control $id not found"; $script:fails++; return }; try{ $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($val) }catch{ Say "FAIL item card: cannot set $id : $($_.Exception.Message)"; $script:fails++ } }
            & $setv 'CardDosageForm' 'أقراص'; & $setv 'CardStrength' '500mg + 65mg'; & $setv 'CardActive' 'Paracetamol + Caffeine'; & $setv 'CardCategory' 'مسكنات وخافضات حرارة'; & $setv 'CardManufacturer' 'GSK'
            & $setv 'CardStrip' '12'; & $setv 'CardBox' '48'; & $setv 'CardMinStock' '20'; & $setv 'CardShelf' 'A3'; & $setv 'CardNotes' 'synthetic note'
            Start-Sleep -Milliseconds 600; Shot '55-itemcard-filled'
            $sv=ById $cw 'CardSave' 4; if($sv){ try{ $sv.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL item card: save invoke failed: $($_.Exception.Message)"; $script:fails++ } } else { Say 'FAIL item card: CardSave not found'; $script:fails++ }
            Start-Sleep 2; $cm=ById $cw 'CardMessage' 3; $mt=if($cm){ $cm.Current.Name } else { '(missing)' }; Say "DIAG item card message: [$mt]"; Check ($mt -like '*تم حفظ*') 'item card: save reports success'; Shot '56-itemcard-saved'
            try{ $cw.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{ Say "INFO item card close failed: $($_.Exception.Message)" }; Start-Sleep 2
            Check (-not (& $cardWin)) 'item card: the window closed'
            $selNow=$false; try{ $selNow=[bool]$hit.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }catch{ Say "INFO item row selection re-read: $($_.Exception.Message)" }
            $rows2=@(Rows 'ProductGrid'); $selCount=0; foreach($r2 in $rows2){ try{ if($r2.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected){ $selCount++ } }catch{} }
            Say "DIAG after the card closed: rows=$($rows2.Count) selectedRows=$selCount"
            Check ($selCount -eq 1) 'item card: a product row is still selected after the card closes (no re-click needed)'
            $cb=Pick 'ItemCardButton' 4
            if($cb){ $cr=$cb.Current.BoundingRectangle; Say "DIAG ItemCardButton found enabled=$($cb.Current.IsEnabled) offscreen=$($cb.Current.IsOffscreen) rect=$([int]$cr.X),$([int]$cr.Y),$([int]$cr.Width),$([int]$cr.Height)" } else { Say 'DIAG ItemCardButton not found for reopen' }
            if($cb){ try{ $cb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Say 'DIAG ItemCardButton invoked for reopen' }catch{ Say "FAIL item card: reopen Invoke threw: $($_.Exception.Message)"; $script:fails++ } }
            $cw=$null; for($k=0;$k -lt 16 -and -not $cw;$k++){ Start-Sleep -Milliseconds 500; $cw=& $cardWin }
            Shot '57-itemcard-reopen-state'
            if(-not $cw){ Say 'NOTEXECUTED item card: reopen did not open the window' } else {
              $getv={ param($id) $e=ById $cw $id 4; if(-not $e){ return '(missing)' }; try{ return $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ return '(no value pattern)' } }
              $vals=@{}; foreach($id in 'CardDosageForm','CardStrength','CardActive','CardCategory','CardManufacturer','CardStrip','CardBox','CardMinStock','CardShelf'){ $vals[$id]=& $getv $id }
              Say ("DIAG item card reopened values: " + (($vals.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=[$($_.Value)]" }) -join ' '))
              Check ($vals['CardStrength'] -ceq '500mg + 65mg' -and $vals['CardManufacturer'] -ceq 'GSK' -and $vals['CardStrip'] -ceq '12' -and $vals['CardBox'] -ceq '48' -and $vals['CardMinStock'] -ceq '20' -and $vals['CardShelf'] -ceq 'A3') 'item card: saved values persist after closing and reopening the card'
              Check ($vals['CardDosageForm'] -ceq 'أقراص') 'item card: the dosage-form dropdown value persisted'
              Shot '57-itemcard-reopened'
              try{ $cw.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{}; Start-Sleep 2
            }
          }
        }
      }
    }
  }
  Sanitize 'before-strip'
  [void](RestartApp 'strip')
  # ---- l120a: sell by strip on the sale screen. Defensive block: any step that cannot run is NOTEXECUTED, never a silent pass ----
  try{
    $ok2=NavTo @('الأصناف والمشتريات','Items') 'packsale-items' 'ProductGrid'
    if(-not $ok2){ Say 'NOTEXECUTED strip sale: could not open the items page'  } else {
      $row=$null; foreach($r in @(RowsIn $main 'ProductGrid')){ if(@(RowCells $r) -ccontains 'SR-NOSALE'){ $row=$r; break } }
      if(-not $row){ Say 'NOTEXECUTED strip sale: seeded product row SR-NOSALE not found in ProductGrid'; GridDump $main 'ProductGrid' 'packsale' } else {
        [void](ClickRow $row $false); Start-Sleep 1
        $cb2=Pick 'ItemCardButton' 4
        if(-not $cb2){ Say 'NOTEXECUTED strip sale: ItemCardButton not found' } else {
          try{ $cb2.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL strip sale: card button: $($_.Exception.Message)"; $script:fails++ }
          Start-Sleep 3; $cw2=& $cardWin
          if(-not $cw2){ Say 'NOTEXECUTED strip sale: card window did not open for the seeded product'; Shot '58-packsale-card-not-open' } else {
            foreach($pair in @(@('CardStrip','5'),@('CardBox','10'))){ $e=ById $cw2 $pair[0] 4; if($e){ try{ $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($pair[1]) }catch{ Say "FAIL strip sale: set $($pair[0]): $($_.Exception.Message)"; $script:fails++ } } else { Say "FAIL strip sale: $($pair[0]) not found"; $script:fails++ } }
            $sv2=ById $cw2 'CardSave' 4; if($sv2){ try{ $sv2.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL strip sale: save: $($_.Exception.Message)"; $script:fails++ } }
            Start-Sleep 2; $cm=ValueIn $cw2 'CardMessage'; Say "INFO strip sale: card message [$cm]"; Shot '58-packsale-card-saved'
            try{ $cw2.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{}; Start-Sleep 2
            if(NavTo @('البيع','Sales') 'packsale-sales' 'StockGrid'){
              $sr=@(RowsIn $main 'StockGrid'); Say "INFO strip sale: stock rows $($sr.Count)"
              $slow=$null; foreach($r in $sr){ if(@(RowCells $r) -ccontains 'SR-NOSALE'){ $slow=$r; break } }
              if(-not $slow){ Say 'NOTEXECUTED strip sale: no stock lot of SR-NOSALE on the sale page'; GridDump $main 'StockGrid' 'packsale-stock' } else {
                $before=@(Rows 'CartGrid').Count
                $sel=$false; try{ $slow.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{ Say "DIAG strip sale: SelectionItem failed: $($_.Exception.Message)" }; if(-not $sel){ [void](ClickRow $slow $false) }; Start-Sleep 1; Say "INFO strip sale: stock row selected=$(IsSel $slow)"
                $qe=Pick 'SaleQuantity' 4; if($qe){ try{ $qe.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('2') }catch{} }
                $okc=SelectCombo $main 'SalePack' { param($n) $n -ceq (NormTxt 'شريط') } 'packsale-combo'; Check $okc 'strip sale: the pack box is set to strip and read back'
                Start-Sleep 1; $hint=ValTxt 'SalePackHint'; Say "INFO strip sale hint: [$hint]"; Shot '59-packsale-hint'
                Check ($hint -like '*5 وحدة*' -and $hint -like '*10 وحدة*') 'strip sale: the hint shows 5 units per strip and 10 per box'
                $ab=Pick 'AddCartButton' 4; if($ab){ try{ $ab.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL strip sale: add: $($_.Exception.Message)"; $script:fails++ } }
                Start-Sleep 2; Shot '60-packsale-cart'; $cr2=@(Rows 'CartGrid'); GridDump $main 'CartGrid' 'packsale-cart'
                $has20=$false; foreach($r in $cr2){ if(@(RowCells $r) -ccontains '10'){ $has20=$true } }
                Check ($cr2.Count -gt $before -and $has20) "strip sale: 2 strips (5 units each) became 10 units in a new cart line (cart rows $before -> $($cr2.Count))"
              }
            }
          }
        }
      }
    }
  }catch{ Say "FAIL strip sale block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  [void](RestartApp 'linedisc')
  # ---- l122: per-line discount on the sale screen (10% on one SR-EDGE unit at 15.00 should show a line total of 13.50) ----
  try{
    if(NavTo @('البيع','Sales') 'linedisc-sales' 'StockGrid'){
      $sr=@(RowsIn $main 'StockGrid'); $edge=$null; foreach($r in $sr){ if(@(RowCells $r) -ccontains 'SR-EDGE'){ $edge=$r; break } }
      if(-not $edge){ Say 'NOTEXECUTED line discount: no SR-EDGE lot on the sale page'; GridDump $main 'StockGrid' 'linedisc-stock' } else {
        $sel=$false; try{ $edge.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{}; if(-not $sel){ [void](ClickRow $edge $false) }; Start-Sleep 1
        $qe=Pick 'SaleQuantity' 4; if($qe){ try{ $qe.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('1') }catch{} }
        $de=Pick 'SaleLineDiscount' 4
        if(-not $de){ Say 'FAIL line discount: SaleLineDiscount box not found'; $script:fails++ } else {
          try{ $de.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('10') }catch{ Say "FAIL line discount: set value: $($_.Exception.Message)"; $script:fails++ }
          $b4=@(Rows 'CartGrid').Count; $ab=Pick 'AddCartButton' 4; if($ab){ try{ $ab.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL line discount: add: $($_.Exception.Message)"; $script:fails++ } }
          Start-Sleep 2; Shot '67-linedisc-cart'; $cr3=@(Rows 'CartGrid'); GridDump $main 'CartGrid' 'linedisc-cart'
          $has=$false; foreach($r in $cr3){ $cells=@(RowCells $r); if(($cells -ccontains 'SR-EDGE' -or ($cells | Where-Object { $_ -like 'L-SR-EDGE*' })) -and @($cells | Where-Object { $_ -match '^13[.,]5' }).Count -ge 1){ $has=$true } }
          Check ($cr3.Count -gt $b4 -and $has) "line discount: 10% on one SR-EDGE unit gives a cart line total of 13.50 (cart rows $b4 -> $($cr3.Count))"
        }
      }
    } else { Say 'NOTEXECUTED line discount: could not open the sale page' }
  }catch{ Say "FAIL line discount block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  if($env:OFAG_LOYALTY -eq '1'){ try{ $lp=Join-Path $PSScriptRoot 'loyalty-steps.ps1'; if(Test-Path $lp){ . $lp; LoyaltySteps } else { Say 'NOTEXECUTED loyalty: loyalty-steps.ps1 not found'; $script:notexec++ } }catch{ Say "FAIL loyalty steps: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ } }
  if($env:OFAG_BUSINESS -eq '1'){ try{ $lp=Join-Path $PSScriptRoot 'business-steps.ps1'; if(Test-Path $lp){ . $lp; $h0=$script:halt; BusinessSteps; if(-not $h0 -and $script:halt -and -not $p.HasExited -and -not (FindModal)){ Say 'INFO business: a halt raised inside the optional business step list was cleared (process alive, no modal); later blocks continue'; $script:halt=$false } } else { Say 'NOTEXECUTED business: business-steps.ps1 not found'; $script:notexec++ } }catch{ Say "FAIL business steps: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ } }
  [void](RestartApp 'ctrl')
  # ---- l123: controlled-drug register (mark an item, sale asks for the register entry, entry saved, register window shows it) ----
  try{
    $findW={ param($title) foreach($w in (TopWins $p.Id)){ if($w.Current.ClassName -ne '#32770' -and $w.Current.Name -like "*$title*" -and $w.Current.Name -ne $main.Current.Name){ return $w } }; try{ $wc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window); foreach($w in @($main.FindAll($TS::Descendants,$wc))){ if($w.Current.Name -like "*$title*"){ return $w } } }catch{}; return $null }
    $invoke={ param($el,$what) try{ $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true }catch{ Say "FAIL controlled: invoke $what : $($_.Exception.Message)"; $script:fails++; return $false } }
    $setv={ param($el,$v,$what) try{ $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($v); return $true }catch{ Say "FAIL controlled: set $what : $($_.Exception.Message)"; $script:fails++; return $false } }
    $closeW={ param($w) try{ $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{ Say "INFO controlled: close window: $($_.Exception.Message)" }; Start-Sleep 1 }
    # name of the SR-EDGE product, read from the sale page stock row
    $prodName=$null
    if(NavTo @('البيع','Sales') 'ctrl-sales0' 'StockGrid'){ foreach($r in @(RowsIn $main 'StockGrid')){ $cc=@(RowCells $r); if($cc -ccontains 'SR-EDGE' -or @($cc | Where-Object { $_ -like '*SR-EDGE*' }).Count -gt 0){ $prodName=@($cc | Where-Object { $_ -like 'Synthetic*' } | Select-Object -First 1)[0]; break } } }
    if(-not $prodName){ Say 'NOTEXECUTED controlled register: could not read the SR-EDGE product name from the stock grid' }
    else {
      Say "INFO controlled: product=[$prodName]"
      # 1. mark the product controlled on the Items page
      $marked=$false
      if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'ctrl-items' 'ProductGrid'){
        $sb=Pick 'InvSearchBox' 5; if($sb){ [void](& $setv $sb $prodName 'search box'); Start-Sleep 2 } else { Say 'INFO controlled: InvSearchBox not found; relying on the unfiltered grid' }
        $prow=$null; foreach($r in @(RowsIn $main 'ProductGrid')){ if(@(RowCells $r) -ccontains $prodName){ $prow=$r; break } }
        if(-not $prow){ Say 'NOTEXECUTED controlled register: product row not found on Items page'; GridDump $main 'ProductGrid' 'ctrl-products' }
        else {
          $sel=$false; try{ $prow.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{}; if(-not $sel){ [void](ClickRow $prow $false) }; Start-Sleep 1
          $tb=Pick 'ControlledToggleButton' 5
          if(-not $tb){ Say 'FAIL controlled: ControlledToggleButton not found'; $script:fails++ } else { if(& $invoke $tb 'toggle'){ Start-Sleep 2; $marked=$true; Shot '68-controlled-marked'; Say "INFO controlled: status after marking = [$(ValTxt 'StatusLabel')]" } }
        }
      }
      if($marked){
        # 2. sale of that product must ask for the register entry
        if(NavTo @('البيع','Sales') 'ctrl-sales' 'StockGrid'){
          $cl=Pick 'ClearCart' 4; if($cl){ [void](& $invoke $cl 'clear cart'); Start-Sleep 1 }
          $edge=$null; foreach($r in @(RowsIn $main 'StockGrid')){ $cc=@(RowCells $r); if($cc -ccontains 'SR-EDGE' -or @($cc | Where-Object { $_ -like '*SR-EDGE*' }).Count -gt 0){ $edge=$r; break } }
          if(-not $edge){ Say 'NOTEXECUTED controlled sale: SR-EDGE lot not on the sale page'; GridDump $main 'StockGrid' 'ctrl-stock' } else {
            $sel=$false; try{ $edge.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{}; if(-not $sel){ [void](ClickRow $edge $false) }; Start-Sleep 1
            $qe=Pick 'SaleQuantity' 4; if($qe){ [void](& $setv $qe '1' 'quantity') }
            $de=Pick 'SaleLineDiscount' 4; if($de){ [void](& $setv $de '0' 'discount') }
            $ab=Pick 'AddCartButton' 4; if($ab){ [void](& $invoke $ab 'add') }; Start-Sleep 2
            $pay=Pick 'Pay' 4
            if(-not $pay){ Say 'FAIL controlled: Pay button not found'; $script:fails++ } else {
              [void](& $invoke $pay 'pay'); $m=WaitModal 10
              if(-not $m){ Say 'FAIL controlled: the sale confirmation did not open'; $script:fails++; Shot '69-controlled-noconfirm' } else {
                $script:curModal=$m; $descs=ModalDescs $m; $yes=XPickButton $descs 'yes'
                if(-not $yes){ Say 'FAIL controlled: confirmation Yes button not identified; nothing pressed'; $script:fails++ } else { [void](PressDesc $yes 'ctrl-sale-confirm' 'Yes'); Start-Sleep 2 }
              }
              $ew=$null; $end=(Get-Date).AddSeconds(10); do{ $ew=& $findW 'بيانات الدواء المراقب'; if(-not $ew){ Start-Sleep -Milliseconds 400 } }while(-not $ew -and (Get-Date) -lt $end)
              Check ($null -ne $ew) 'controlled sale: the register entry dialog opened for the controlled line'
              if($ew){
                Shot '69-controlled-entry-dialog'
                # empty confirm must be refused
                $cb=ById $ew 'CtrlConfirm' 4; if($cb){ [void](& $invoke $cb 'confirm empty'); Start-Sleep 1; $mt=''; try{ $mt=[string](ById $ew 'CtrlMessage' 3).Current.Name }catch{}; Shot '70-controlled-entry-refused'; $still=& $findW 'بيانات الدواء المراقب'; Check ($mt.Length -gt 0 -and $null -ne $still) "controlled sale: empty fields are refused and the dialog stays open (message=[$mt])" } else { Say 'FAIL controlled: CtrlConfirm not found'; $script:fails++ }
                foreach($pair in @(@('CtrlPatient1','Synthetic Patient'),@('CtrlPatientId1','29001010000000'),@('CtrlPrescriber1','Dr Synthetic'),@('CtrlRx1','RX-SYN-1'))){ $f=ById $ew $pair[0] 4; if($f){ [void](& $setv $f $pair[1] $pair[0]) } else { Say "FAIL controlled: field $($pair[0]) not found"; $script:fails++ } }
                Shot '71-controlled-entry-filled'
                $cb=ById $ew 'CtrlConfirm' 4; if($cb){ [void](& $invoke $cb 'confirm filled'); Start-Sleep 3 }
                $gone=$null -eq (& $findW 'بيانات الدواء المراقب'); Shot '72-controlled-after-sale'
                Check $gone 'controlled sale: with all fields filled the dialog closed and the sale was saved'
              }
            }
          }
        }
        # 3. register window shows the entry
        if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'ctrl-items2' 'ProductGrid'){
          $rb=Pick 'ControlledRegisterButton' 5
          if(-not $rb){ Say 'FAIL controlled: ControlledRegisterButton not found'; $script:fails++ } else {
            [void](& $invoke $rb 'register'); Start-Sleep 3; $rw=& $findW 'سجل الأدوية المراقبة'
            if(-not $rw){ Say 'FAIL controlled: register window did not open'; $script:fails++ } else {
              Shot '73-controlled-register-window'; $rr=@(RowsIn $rw 'CtrlRegGrid'); GridDump $rw 'CtrlRegGrid' 'ctrl-register'
              $hit=$false; foreach($r in $rr){ $cc=@(RowCells $r); if($cc -contains 'Synthetic Patient' -and $cc -contains 'RX-SYN-1'){ $hit=$true } }
              Check $hit 'controlled register: the saved entry (patient and prescription number) is listed'
              & $closeW $rw
            }
          }
        }
        # 4. unmark again so later steps see a normal product
        if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'ctrl-items3' 'ProductGrid'){
          $sb=Pick 'InvSearchBox' 5; if($sb){ [void](& $setv $sb $prodName 'search box'); Start-Sleep 2 }
          foreach($r in @(RowsIn $main 'ProductGrid')){ if(@(RowCells $r) -ccontains $prodName){ try{ $r.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }catch{}; break } }
          Start-Sleep 1; $tb=Pick 'ControlledToggleButton' 5; if($tb){ [void](& $invoke $tb 'unmark'); Start-Sleep 1; Say "INFO controlled: status after unmarking = [$(ValTxt 'StatusLabel')]" }
          $sb=Pick 'InvSearchBox' 5; if($sb){ [void](& $setv $sb '' 'search box clear') }
        }
      }
    }
  }catch{ Say "FAIL controlled register block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  # ---- l125: bonus units on purchase (buy 10 + 2 free of Synthetic Slow B: stock must rise by exactly 12) ----
  try{
    $setvB={ param($el,$v,$what) try{ $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($v); return $true }catch{ Say "FAIL bonus: set $what : $($_.Exception.Message)"; $script:fails++; return $false } }
    if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'bonus-items' 'ProductGrid'){
      $sb=Pick 'InvSearchBox' 5; if($sb){ [void](& $setvB $sb 'Synthetic Slow B' 'search box'); Start-Sleep 2 }
      $brow=$null; foreach($r in @(RowsIn $main 'ProductGrid')){ if(@(RowCells $r) -ccontains 'Synthetic Slow B'){ $brow=$r; break } }
      if(-not $brow){ Say 'NOTEXECUTED bonus units: Synthetic Slow B row not found'; GridDump $main 'ProductGrid' 'bonus-products' } else {
        $before=@(RowCells $brow)[2]
        $sel=$false; try{ $brow.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{}; if(-not $sel){ [void](ClickRow $brow $false) }; Start-Sleep 1
        $ok=$true
        foreach($pair in @(@('LotNumber','BONUS-L1'),@('ReceiveQuantity','10'),@('UnitCost','12'),@('BonusUnits','2'),@('SupplierName','Synthetic Supplier'))){ $f=Pick $pair[0] 5; if($f){ if(-not (& $setvB $f $pair[1] $pair[0])){ $ok=$false } } else { Say "FAIL bonus: field $($pair[0]) not found"; $script:fails++; $ok=$false } }
        $ed=Pick 'ExpiryDate' 5; if($ed){ [void](& $setvB $ed '1/1/2031' 'ExpiryDate') } else { Say 'FAIL bonus: ExpiryDate not found'; $script:fails++; $ok=$false }
        Start-Sleep 1; Shot '74-bonus-form-filled'
        if($ok){
          $rb=Pick 'ReceiveStockButton' 5
          if(-not $rb){ $names=@(); try{ foreach($bb in @($main.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))))){ $names+=[string]$bb.Current.Name+'{'+[string]$bb.Current.AutomationId+'}' } }catch{}; Say "FAIL bonus: ReceiveStockButton not found; buttons seen: $($names -join ' | ')"; $script:fails++ }
          else { try{ $rb.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView() }catch{}; try{ $rr0=$rb.Current.BoundingRectangle; Say "INFO bonus: receive button offscreen=$($rb.Current.IsOffscreen) rect=$([int]$rr0.X),$([int]$rr0.Y),$([int]$rr0.Width),$([int]$rr0.Height) enabled=$($rb.Current.IsEnabled)" }catch{}
            try{ $rb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL bonus: invoke receive: $($_.Exception.Message)"; $script:fails++ } }
          Start-Sleep 3
          $mm=FindModal; if($mm){ Say "INFO bonus: a dialog opened: title=[$($mm.Current.Name)] text=[$((@(WinBoxStatics $mm)) -join ' / ')]"; [void](ModalDismiss 'bonus-dialog') }
          Shot '75-bonus-after-receive'; Say "INFO bonus: status = [$(ValTxt 'StatusLabel')]"
          $after=$null; foreach($r in @(RowsIn $main 'ProductGrid')){ if(@(RowCells $r) -ccontains 'Synthetic Slow B'){ $after=@(RowCells $r)[2]; break } }
          Say "INFO bonus: stock units before=[$before] after=[$after]"
          $okn=$false; try{ $okn=([long]$after -eq ([long]$before + 12)) }catch{}
          Check $okn 'bonus units: receiving 10 paid + 2 free raised the stock by exactly 12'
        } else { Say 'NOTEXECUTED bonus units: form could not be filled' }
      }
      $sb=Pick 'InvSearchBox' 5; if($sb){ [void](& $setvB $sb '' 'search box clear') }
    } else { Say 'NOTEXECUTED bonus units: could not open the Items page' }
  }catch{ Say "FAIL bonus block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  [void](RestartApp 'tiers')
  # ---- l126: price tiers (define Insurance 12.00 for Synthetic Fast A at 15.00, choose it on the sale page, sell, check price and saved sale) ----
  try{
    $setvT={ param($el,$v,$what) try{ $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($v); return $true }catch{ Say "FAIL tiers: set $what : $($_.Exception.Message)"; $script:fails++; return $false } }
    $invT={ param($el,$what) try{ $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true }catch{ Say "FAIL tiers: invoke $what : $($_.Exception.Message)"; $script:fails++; return $false } }
    $findT={ param($title) foreach($w in (TopWins $p.Id)){ if($w.Current.ClassName -ne '#32770' -and $w.Current.Name -like "*$title*" -and $w.Current.Name -ne $main.Current.Name){ return $w } }; try{ $wc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window); foreach($w in @($main.FindAll($TS::Descendants,$wc))){ if($w.Current.Name -like "*$title*"){ return $w } } }catch{}; return $null }
    $tierOk=$false
    if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'tier-items' 'ProductGrid'){
      $sb=Pick 'InvSearchBox' 5; if($sb){ [void](& $setvT $sb 'Synthetic Fast A' 'search box'); Start-Sleep 2 }
      $trow=$null; foreach($r in @(RowsIn $main 'ProductGrid')){ if(@(RowCells $r) -ccontains 'Synthetic Fast A'){ $trow=$r; break } }
      if(-not $trow){ Say 'NOTEXECUTED price tiers: Synthetic Fast A row not found'; GridDump $main 'ProductGrid' 'tier-products' } else {
        $sel=$false; try{ $trow.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{}; if(-not $sel){ [void](ClickRow $trow $false) }; Start-Sleep 1
        $tbt=Pick 'PriceTiersButton' 5
        if(-not $tbt){ Say 'FAIL tiers: PriceTiersButton not found'; $script:fails++ } else {
          [void](& $invT $tbt 'open tiers'); Start-Sleep 3; $tw=& $findT 'شرائح الأسعار'
          Check ($null -ne $tw) 'price tiers: the tiers window opened for the selected product'
          if($tw){
            Shot '76-tiers-window-open'
            $f1=ById $tw 'TierName' 4; $f2=ById $tw 'TierPrice' 4
            if($f1 -and $f2){ [void](& $setvT $f1 'Insurance' 'TierName'); [void](& $setvT $f2 '12' 'TierPrice') } else { Say 'FAIL tiers: TierName or TierPrice not found'; $script:fails++ }
            $sv=ById $tw 'TierSave' 4; if($sv){ [void](& $invT $sv 'save tier'); Start-Sleep 2 }
            $mt=''; try{ $mt=[string](ById $tw 'TierMessage' 3).Current.Name }catch{}
            Shot '77-tiers-saved'; $rr=@(RowsIn $tw 'TierGrid'); GridDump $tw 'TierGrid' 'tier-grid'
            $hasT=$false; foreach($r in $rr){ $cc=@(RowCells $r); if($cc -contains 'Insurance' -and @($cc | Where-Object { $_ -match '^12([.,]00)?$' }).Count -ge 1){ $hasT=$true } }
            Check $hasT "price tiers: the Insurance tier at 12.00 is saved and listed (message=[$mt])"; $tierOk=$hasT
            $cl=ById $tw 'TierClose' 4; if($cl){ [void](& $invT $cl 'close tiers'); Start-Sleep 1 }
          }
        }
      }
      $sb=Pick 'InvSearchBox' 5; if($sb){ [void](& $setvT $sb '' 'search box clear') }
    } else { Say 'NOTEXECUTED price tiers: could not open the Items page' }
    if($tierOk){
      if(NavTo @('البيع','Sales') 'tier-sales' 'StockGrid'){
        $clr=Pick 'ClearCart' 4; if($clr){ [void](& $invT $clr 'clear cart'); Start-Sleep 1 }
        $fast=$null; foreach($r in @(RowsIn $main 'StockGrid')){ $cc=@(RowCells $r); if($cc -ccontains 'Synthetic Fast A'){ $fast=$r; break } }
        if(-not $fast){ Say 'NOTEXECUTED tier sale: Synthetic Fast A not in the stock grid'; GridDump $main 'StockGrid' 'tier-stock' } else {
          $sel=$false; try{ $fast.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{}; if(-not $sel){ [void](ClickRow $fast $false) }; Start-Sleep 1
          $qe=Pick 'SaleQuantity' 4; if($qe){ [void](& $setvT $qe '1' 'quantity') }; $de=Pick 'SaleLineDiscount' 4; if($de){ [void](& $setvT $de '0' 'discount') }
          $cb=Pick 'SaleTier' 5; $picked=$false
          if(-not $cb){ Say 'FAIL tiers: SaleTier combo not found'; $script:fails++ } else {
            try{ $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand(); Start-Sleep 1 }catch{ Say "INFO tiers: expand: $($_.Exception.Message)" }
            $lc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)
            $item=$null; foreach($root in @($main) + @(TopWins $p.Id)){ foreach($li in @($root.FindAll($TS::Descendants,$lc))){ if([string]$li.Current.Name -eq 'Insurance'){ $item=$li; break } }; if($item){ break } }
            $how=''
            if($item){ Say "INFO tiers: combo item found type=$($item.Current.ControlType.ProgrammaticName) class=$($item.Current.ClassName)"
              try{ $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $how='SelectionItem' }catch{ Say "INFO tiers: SelectionItem unsupported on the item: $($_.Exception.Message)" }
              if(-not $how){ try{ $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $how='Invoke' }catch{ Say "INFO tiers: Invoke unsupported on the item: $($_.Exception.Message)" } } }
            try{ $cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() }catch{}
            Start-Sleep 1
            $cur=''; try{ $cur=[string]$cb.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{}
            if($cur -ne 'Insurance'){
              # keyboard fallback: focus the collapsed combo and press Down once (blank -> Insurance)
              try{ [void](BringFg); $cb.SetFocus(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait('{DOWN}'); Start-Sleep -Milliseconds 800; $how='keyboard Down' }catch{ Say "INFO tiers: keyboard fallback failed: $($_.Exception.Message)" }
              try{ $cur=[string]$cb.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{}
            }
            $nm2=''; try{ $nm2=[string]$cb.Current.Name }catch{}; $kids=''; try{ $kids=(@($cb.FindAll($TS::Descendants,[System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object { [string]$_.Current.Name } | Where-Object { $_ }) -join ' / ') }catch{}
            Say "INFO tiers (diagnostic only, not asserted): combo value=[$cur] name=[$nm2] child names=[$kids] via [$how]"
            Shot '78-tier-combo-selected'
            $picked=$true   # the real test is the cart line below: it must show the Insurance tier and 12.00
            Start-Sleep 1
          }
          if($picked){
            $ab=Pick 'AddCartButton' 4; if($ab){ [void](& $invT $ab 'add') }; Start-Sleep 2; Shot '78-tier-cart'; $cr=@(Rows 'CartGrid'); GridDump $main 'CartGrid' 'tier-cart'
            $okc=$false; foreach($r in $cr){ $cc=@(RowCells $r); if($cc -ccontains 'Synthetic Fast A' -and $cc -contains 'Insurance' -and @($cc | Where-Object { $_ -match '^12([.,]0+)?$' }).Count -ge 2){ $okc=$true } }
            Check $okc 'tier sale: the cart line shows the Insurance tier and the 12.00 price and line total (normal price is 15.00)'
            $pay=Pick 'Pay' 4
            if($pay){ [void](& $invT $pay 'pay'); $m=WaitModal 10
              if($m){ $script:curModal=$m; $descs=ModalDescs $m; $yes=XPickButton $descs 'yes'; if($yes){ [void](PressDesc $yes 'tier-sale-confirm' 'Yes'); Start-Sleep 3 } else { Say 'FAIL tiers: sale confirmation Yes not identified'; $script:fails++ } } else { Say 'FAIL tiers: the sale confirmation did not open'; $script:fails++ }
              $mm=FindModal; if($mm){ Say "INFO tiers: a dialog is open after the sale: title=[$($mm.Current.Name)] text=[$((@(WinBoxStatics $mm)) -join ' / ')]"; [void](ModalDismiss 'tier-after-sale') }
              Shot '79-tier-after-sale'; $left=@(Rows 'CartGrid').Count; Say "INFO tiers: status=[$(ValTxt 'StatusLabel')] cart rows after sale=$left"
              Check ($left -eq 0) 'tier sale: the tiered sale was saved (cart emptied)'
            }
          }
        }
      } else { Say 'NOTEXECUTED tier sale: could not open the sale page' }
    }
  }catch{ Say "FAIL price tiers block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  # ---- l130: phone monitor exporter (off by default; enable -> encrypted push to the brand Firestore project -> fetch the document back and decrypt it with Node in the workflow; disable -> no further push) ----
  # SYNTHETIC data only. The test document stays in the project (the rules deny delete); its token is random and only lives in this run's evidence.
  try{
    $pcode=''
    if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'phone-inventory' 'InvSearchBox'){
      $opened=OpenOps 'ph1'; $ow=OpsWin
      if(-not $opened -or -not $ow){ Say 'NOTEXECUTED phone monitor: the Operations window could not be opened'; $script:notexec++ } else {
        $tabs=TabByName $ow 'مراقبة الهاتف'
        if(-not $tabs){ Say 'NOTEXECUTED phone monitor: the Phone monitor tab was not found'; $script:notexec++ } else {
          try{ $tabs.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }catch{ Say "INFO phone tab select: $($_.Exception.Message)" }; Start-Sleep 1
          $st=ById $ow 'OpsPhoneState' 5; $st0=if($st){ [string]$st.Current.Name } else { '(missing)' }; Say "DIAG phone state before: [$st0]"; Shot '80-phone-tab-default'
          Check ($st0 -like '*متوقفة*') 'phone monitor: the default state is OFF (متوقفة)'
          Check ($st0 -like '*لا يوجد رمز ربط*') 'phone monitor: no pairing code exists before it is enabled'
          $en=ById $ow 'OpsPhoneEnable' 5
          if(-not $en){ Say 'NOTEXECUTED phone monitor: enable button not found'; $script:notexec++ } else {
            try{ $en.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL phone enable invoke: $($_.Exception.Message)"; $script:fails++ }
            Start-Sleep 8
            $ce=ById $ow 'OpsPhoneCode' 5; if($ce){ try{ $pcode=[string]$ce.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ $pcode='' } }
            $parts=@($pcode -split '\.'); Check ($parts.Count -eq 3 -and $parts[0] -eq 'OFAG1' -and $parts[1].Length -eq 43) 'phone monitor: a pairing code of the agreed shape (OFAG1.token43.key) is shown'
            $st=ById $ow 'OpsPhoneState' 5; $st1=if($st){ [string]$st.Current.Name } else { '(missing)' }; Say "DIAG phone state after enable: [$st1]"; Shot '81-phone-enabled'
            Check ($st1 -like '*مفعّلة*') 'phone monitor: the state reads ON after enabling'
            Check ($st1 -like '*Last push OK*') 'phone monitor: the app reports the first push succeeded'
            if($parts.Count -eq 3 -and $parts[1].Length -eq 43){
              Set-Content -Path (Join-Path $OutDir 'phone-code.txt') -Value $pcode -Encoding ascii -NoNewline
              $url='https://firestore.googleapis.com/v1/projects/one-for-all-good/databases/(default)/documents/monitor/'+$parts[1]
              try{ $r1=Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30; Set-Content -Path (Join-Path $OutDir 'phone-doc-1.json') -Value $r1.Content -Encoding utf8; $d1=$r1.Content | ConvertFrom-Json; $ts1=[string]$d1.fields.ts.integerValue; Say "INFO phone document fetched back: ts=$ts1 c-length=$(([string]$d1.fields.c.stringValue).Length)"; Check ($ts1 -match '^\d{13}$') 'phone monitor: the document exists on the server with an integer ts' }catch{ Say "FAIL phone monitor: fetching the document back failed: $($_.Exception.Message)"; $script:fails++; $ts1='' }
              $dis=ById $ow 'OpsPhoneDisable' 5
              if($dis -and $ts1){
                $nowb=Get-Date; Start-Sleep 70
                try{ $r1b=Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30; $ts1b=[string](($r1b.Content | ConvertFrom-Json).fields.ts.integerValue); Say "INFO phone push while ON: ts moved $ts1 -> $ts1b"; Check ($ts1b -ne $ts1) 'phone monitor: while ON a later push replaced the document (60 s timer)' }catch{ Say "FAIL phone monitor: second fetch failed: $($_.Exception.Message)"; $script:fails++ }
                try{ $dis.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL phone disable invoke: $($_.Exception.Message)"; $script:fails++ }
                Start-Sleep 3; $r2=Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30; Set-Content -Path (Join-Path $OutDir 'phone-doc-2.json') -Value $r2.Content -Encoding utf8; $tsOff=[string](($r2.Content | ConvertFrom-Json).fields.ts.integerValue)
                $st=ById $ow 'OpsPhoneState' 5; Say "DIAG phone state after disable: [$([string]$st.Current.Name)]"; Shot '82-phone-disabled'
                Check (([string]$st.Current.Name) -like '*متوقفة*') 'phone monitor: the state reads OFF after disabling'
                Start-Sleep 75
                $r3=Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30; $tsLater=[string](($r3.Content | ConvertFrom-Json).fields.ts.integerValue); Say "INFO phone after disable: ts $tsOff then (75 s later) $tsLater"
                Check ($tsLater -eq $tsOff) 'phone monitor: after disabling nothing more is pushed (document unchanged for 75 s, longer than the 60 s timer)'
              } else { Say 'NOTEXECUTED phone monitor: disable button or first timestamp missing'; $script:notexec++ }
            }
          }
        }
        [void](CloseOps 'ph1-close')
      }
    } else { Say 'NOTEXECUTED phone monitor: could not open the Products page' }
  }catch{ Say "FAIL phone monitor block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  Sanitize 'before-draft'
  # l120b: draft receive screen (opens, empty draft cannot be saved, a manual row stays blocked until it is complete)
  try{
    if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'draft-items' 'ProductGrid'){
      $db0=Pick 'DraftReceiveButton' 4
      if(-not $db0){ Say 'NOTEXECUTED draft receive: DraftReceiveButton not found'; Shot '61-draft-no-button' } else {
        try{ $db0.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL draft receive: open: $($_.Exception.Message)"; $script:fails++ }
        Start-Sleep 3; $dw=$null; foreach($w in (TopWins $p.Id)){ if($w.Current.Name -like '*مسودة استلام*'){ $dw=$w } }
        if(-not $dw){ try{ $wc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window); foreach($w in @($main.FindAll($TS::Descendants,$wc))){ if($w.Current.Name -like '*مسودة استلام*'){ $dw=$w } } }catch{} }
        if(-not $dw){ Say 'NOTEXECUTED draft receive: window did not open'; Shot '61-draft-not-open' } else {
          Shot '61-draft-open'; Say 'PASS draft receive: window opened'
          $sv=ById $dw 'DraftSave' 4; if($sv){ Check (-not $sv.Current.IsEnabled) 'draft receive: Save is disabled while the draft is empty' } else { Say 'FAIL draft receive: DraftSave not found'; $script:fails++ }
          $ad=ById $dw 'DraftAddRow' 4; if($ad){ try{ $ad.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL draft receive: add row: $($_.Exception.Message)"; $script:fails++ }; Start-Sleep 2
            $sv=ById $dw 'DraftSave' 4; if($sv){ Check (-not $sv.Current.IsEnabled) 'draft receive: Save stays disabled with an incomplete manual row' }
            GridDump $dw 'DraftGrid' 'draft-grid'; Shot '62-draft-manual-row'
            $se=ById $dw 'DraftSummary' 3; $sm=''; if($se){ $sm=$se.Current.Name }; Say "INFO draft summary: [$sm]" } else { Say 'FAIL draft receive: DraftAddRow not found'; $script:fails++ }
          try{ $dw.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{}; Start-Sleep 2
        }
      }
    }
  }catch{ Say "FAIL draft receive block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  Sanitize 'before-roles'
  [void](RestartApp 'roles')
  # ---- l121: cashier role and English mode (owner creates a cashier, locks, switches to English, logs in as the cashier) ----
  try{
    $ownerRail=@(RailItemsEnglish); $ownerLabels=@($ownerRail | ForEach-Object { $_.Label }); Say "INFO roles: owner rail has $($ownerLabels.Count) items"
    if(NavTo @('الإدارة والنسخ الاحتياطي','Administration and backup') 'roles-settings' 'NewUsername'){
      $nub=ById $main 'NewUiBox' 3; if($nub){ Say 'PASS NewUiBox is reachable on the first Settings entry after a fresh start' } else { Say 'INFO NewUiBox not found by the plain lookup on first Settings entry (Pick fallback follows)'; $nub=Pick 'NewUiBox' 3; if($nub){ Say 'PASS NewUiBox found by the fallback' } else { Say 'FAIL NewUiBox not reachable on Settings'; $script:fails++ } }
      $nu=Pick 'NewUsername' 5; $np=Pick 'NewPassword' 5; $ab=Pick 'AddUserButton' 5
      if(-not ($nu -and $np -and $ab)){ Say 'NOTEXECUTED roles: NewUsername, NewPassword or AddUserButton not found' } else {
        try{ $nu.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('cashier1') }catch{ Say "FAIL roles: set username: $($_.Exception.Message)"; $script:fails++ }
        [void](BringFg); $np.SetFocus(); Start-Sleep -Milliseconds 400; $tr2=TypeSecret $pwCash { FgOurs } { param($k) [System.Windows.Forms.SendKeys]::SendWait($k) }
        Say "DIAG roles: cashier password typed=$($tr2.typed)/$($tr2.expected) lost=$($tr2.lost)"
        Shot '63-roles-new-user-form'
        try{ $ab.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL roles: create button: $($_.Exception.Message)"; $script:fails++ }
        Start-Sleep 3; $md=FindModal; if($md){ Say "DIAG roles: modal after create: [$($md.Current.Name)]"; Shot 'dlg-roles-after-create'; try{ $md.SetFocus() }catch{}; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 1 }
        $lo=ById $main 'LogoutButton' 5
        if(-not $lo){ Say 'NOTEXECUTED roles: LogoutButton not found' } else {
          try{ $lo.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL roles: lock: $($_.Exception.Message)"; $script:fails++ }
          Start-Sleep 2; Shot '64-roles-locked'
          $lg=ById $main 'LangButton' 8
          if(-not $lg){ Say 'NOTEXECUTED english: LangButton not found on the login screen' } else {
            try{ $lg.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL english: toggle: $($_.Exception.Message)"; $script:fails++ }
            Start-Sleep 2; $lbn=ById $main 'LoginButton' 5; $lbt=''; if($lbn){ $lbt=[string]$lbn.Current.Name }; Say "INFO english: login button text [$lbt]"; Shot '65-english-login'
            Check ($lbt -match '[A-Za-z]' -and $lbt -notmatch '[\u0600-\u06FF]') 'english mode: the login button text is English'
          }
          if(Login 'cashier1' $pwCash 'cashier'){
            Start-Sleep 2; Shot '66-cashier-main'
            $cr=@(); for($ri=1;$ri -le 5;$ri++){ $cr=@(RailItemsEnglish); if($cr.Count -gt 0){ break }; Say "DIAG cashier rail attempt $ri found 0, waiting 2 s"; Start-Sleep 2 }; if($cr.Count -eq 0){ [void](RailDiag 'cashier') }; $cl=@($cr | ForEach-Object { if($_.Label){ $_.Label } else { $_.Raw } }); Say "INFO cashier rail ($($cl.Count)): $($cl -join ' | ')"
            Check ($cl.Count -ge 1 -and $cl.Count -lt $ownerLabels.Count) "cashier role: the rail shows fewer pages than the owner ($($cl.Count) vs $($ownerLabels.Count))"
            Check (-not (@($cl | Where-Object { $_ -match 'Administration|Backup|Payroll|الإدارة|مسودة الرواتب' }).Count)) 'cashier role: no administration or payroll page in the rail'
            Check (@($cl | Where-Object { $_ -match '[A-Za-z]' -and $_ -notmatch '[\u0600-\u06FF]' }).Count -ge 1) 'english mode: at least one rail label is English'
            $lo2=ById $main 'LogoutButton' 5; if($lo2){ try{ $lo2.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{}; Start-Sleep 2 }
            $lg2=ById $main 'LangButton' 8; if($lg2){ try{ $lg2.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{}; Start-Sleep 2 }
            [void](Login 'owner' $pwOwner 'owner-after-roles')
          }
        }
      }
    } else { Say 'NOTEXECUTED roles: could not open the administration page' }
  }catch{ Say "FAIL roles block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  # ---- l134: invoice photo OCR on a real image (Windows OCR en-US, same path and reader as the draft receive screen). The image is drawn here with SYNTHETIC text; no real invoice. ----
  # What this proves: the engine on this runner reads printed English digits and words from pixels and the reader turns them into rows. It does NOT prove Arabic, handwriting, photos taken with a phone, skew, or the draft screen's file dialog.
  try{
    Add-Type -AssemblyName System.Drawing
    $img=Join-Path $OutDir 'ocr-invoice.png'; $ocrOut=Join-Path $OutDir 'ocr-result.json'; Remove-Item $ocrOut -Force -ErrorAction SilentlyContinue
    $bmp=New-Object System.Drawing.Bitmap 1400,520; $g=[System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::White); $g.TextRenderingHint=[System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $f=New-Object System.Drawing.Font('Arial',26); $br=[System.Drawing.Brushes]::Black
    $g.DrawString('Synthetic Pharma Supplies',$f,$br,40,30); $g.DrawString('Invoice No 12345    Date 20/11/2026',$f,$br,40,85)
    $hx=@(40,470,580,720,830,960,1140); $hd=@('Item','Qty','Price','Disc','Net','Lot','Expiry'); for($i=0;$i -lt 7;$i++){ $g.DrawString($hd[$i],$f,$br,$hx[$i],150) }
    $rowsT=@( @('Adol Extra','20','12.50','0','250.00','AB1234','05/2028'), @('Cetal Plus','10','30.00','10','270.00','CD5678','11/2027'), @('Zinc Forte','5','45.60','0','228.00','EF9012','03/2029') )
    $y=215; foreach($rw in $rowsT){ for($i=0;$i -lt 7;$i++){ $g.DrawString($rw[$i],$f,$br,$hx[$i],$y) }; $y+=60 }
    $g.DrawString('Total 748.00',$f,$br,830,420); $g.Dispose(); $bmp.Save($img,[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    $op=Start-Process -FilePath $exe -ArgumentList @('--ocr-selftest',('"'+$img+'"'),('"'+$ocrOut+'"')) -PassThru
    if(-not $op.WaitForExit(150000)){ try{ $op.Kill() }catch{}; Say 'FAIL ocr: the read did not finish in 150 s'; $script:fails++ }
    if(-not (Test-Path $ocrOut)){ Say 'FAIL ocr: no result file'; $script:fails++ } else {
      $oj=Get-Content $ocrOut -Raw -Encoding utf8 | ConvertFrom-Json
      if($oj.error){ Say "FAIL ocr: the engine reported: $($oj.error)"; $script:fails++ } else {
        Say "DIAG ocr: words=$($oj.words) invoiceNo=[$($oj.invoiceNo)] date=[$($oj.date)] total=[$($oj.total)] sum=[$($oj.sum)] rows=$(@($oj.rows).Count) unparsed=$(@($oj.unparsed).Count)"; Say "DIAG ocr text: [$($oj.text)]"
        Check ($oj.words -ge 20) "ocr: words were read from the image ($($oj.words))"
        Check ("$($oj.invoiceNo)" -eq '12345') 'ocr: the invoice number 12345 was read'
        Check ("$($oj.date)" -eq '20/11/2026') 'ocr: the invoice date was read'
        $orows=@($oj.rows); Check ($orows.Count -eq 3) "ocr: three item rows were found ($($orows.Count))"
        for($i=0;$i -lt [Math]::Min(3,$orows.Count);$i++){ $e=$rowsT[$i]; $r=$orows[$i]
          $okr=(("$($r.name)").Trim() -eq $e[0]) -and ([string]$r.qty -eq $e[1]) -and ([decimal]$r.price -eq [decimal]$e[2]) -and ([decimal]$r.disc -eq [decimal]$e[3]) -and ([decimal]$r.net -eq [decimal]$e[4]) -and ($r.lot -eq $e[5]) -and ($r.expiry -eq $e[6])
          Say "DIAG ocr row $($i+1): name=[$($r.name)] qty=$($r.qty) price=$($r.price) disc=$($r.disc) net=$($r.net) lot=[$($r.lot)] exp=[$($r.expiry)] status=$($r.status) flagged=$($r.flagged)"
          Check $okr "ocr: row $($i+1) ($($e[0])) was read exactly: name, quantity, price, discount, net, lot, expiry" }
        Check ([decimal]$oj.total -eq [decimal]748 -and $oj.totalMatches) 'ocr: the invoice total 748.00 was read and equals the sum of the rows'
      }
    }
    # ---- l135 A: the SAME image through the draft receive screen (real window, Pick-image button; a trial-only hook file replaces the file dialog) ----
    $hook=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OneForAllGood-TRIAL\test-ocr-image.txt'
    try{
      if(Test-Path $img){
        Set-Content -Path $hook -Value $img -Encoding ascii
        if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'ocr-draft-items' 'ProductGrid'){
          $db1=Pick 'DraftReceiveButton' 4
          if(-not $db1){ Say 'NOTEXECUTED ocr draft screen: DraftReceiveButton not found' } else {
            try{ $db1.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL ocr draft: open: $($_.Exception.Message)"; $script:fails++ }
            Start-Sleep 3; $dw2=$null; $dwNames=@()
            foreach($w in (TopWins $p.Id)){ $dwNames+=[string]$w.Current.Name; if($w.Current.Name -like '*مسودة استلام*' -or $w.Current.Name -like '*Draft*receiv*'){ $dw2=$w } }
            if(-not $dw2){ try{ $wc2=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window); foreach($w in @($main.FindAll($TS::Descendants,$wc2))){ $dwNames+=[string]$w.Current.Name; if($w.Current.Name -like '*مسودة استلام*' -or $w.Current.Name -like '*Draft*receiv*'){ $dw2=$w } } }catch{} }
            if(-not $dw2){ Say "DIAG ocr draft: windows seen = [$($dwNames -join ' / ')]"; Shot '99-ocr-draft-not-open' }
            if(-not $dw2){ Say 'NOTEXECUTED ocr draft screen: window did not open' } else {
              $pk=ById $dw2 'DraftPickImage' 4
              if(-not $pk){ Say 'NOTEXECUTED ocr draft screen: DraftPickImage not found' } else {
                try{ $pk.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL ocr draft: pick: $($_.Exception.Message)"; $script:fails++ }
                $mt=''; $end=(Get-Date).AddSeconds(240); do{ Start-Sleep 3; $me=ById $dw2 'DraftMessage' 1; $mt=if($me){ [string]$me.Current.Name } else { '' } }while(-not ($mt -like '*قُرئ*' -or $mt -like '*تعذّرت*' -or $mt -like '*لم تُقرأ*') -and (Get-Date) -lt $end)
                Say "DIAG ocr draft message: [$mt]"; Shot '99-ocr-draft-screen'
                $se=ById $dw2 'DraftSupplier' 3; $sv=''; if($se){ try{ $sv=[string]$se.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{} }
                $ie=ById $dw2 'DraftInvoiceNo' 3; $iv=''; if($ie){ try{ $iv=[string]$ie.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{} }
                Say "DIAG ocr draft fields: supplier=[$sv] invoiceNo=[$iv]"; GridDump $dw2 'DraftGrid' 'ocr-draft-grid'
                Check ($mt -like '*قُرئ 3 سطر*') 'ocr draft screen: the screen read 3 rows from the image through its own button'
                Check ($iv -eq '12345') 'ocr draft screen: the invoice number field was filled with 12345'
                Check ($sv -eq 'Synthetic Pharma Supplies') 'ocr draft screen: the supplier field holds only the supplier line (not the invoice line)'
                $gt=((@(RowsIn $dw2 'DraftGrid') | ForEach-Object { (RowCells $_) -join ' | ' }) -join ' ;; ')
                Check ($gt -like '*Adol Extra*' -and $gt -like '*Cetal Plus*' -and $gt -like '*Zinc Forte*') 'ocr draft screen: the grid shows the three item names'
              }
              try{ $dw2.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{}; Start-Sleep 2
            }
          }
        } else { Say 'NOTEXECUTED ocr draft screen: could not open the Items page' }
      }
    }catch{ Say "FAIL ocr draft screen block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
    finally{ Remove-Item $hook -Force -ErrorAction SilentlyContinue }
    # ---- l135 B: Arabic. Probe the Windows OCR languages on this runner; try the free Windows OCR Arabic capability; if an Arabic engine exists, read a SYNTHETIC Arabic-name invoice. ----
    try{
      $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
      function PsOut($cmd,$sec){ $o=Join-Path $env:TEMP ([guid]::NewGuid().ToString('N')+'.txt'); $enc=[Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($cmd)); $pp=Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-EncodedCommand',$enc) -RedirectStandardOutput $o -RedirectStandardError ($o+'.err') -PassThru -WindowStyle Hidden; if(-not $pp.WaitForExit($sec*1000)){ try{ $pp.Kill() }catch{}; return 'TIMEOUT' }; $t=''; if(Test-Path $o){ $t=(Get-Content $o -Raw) }; if(Test-Path ($o+'.err')){ $t+=' '+(Get-Content ($o+'.err') -Raw) }; return ([string]$t).Trim() }
      $probe='[void][Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]; ([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag }) -join ","'
      $langs=PsOut $probe 60; Say "DIAG ocr languages installed: [$langs]"
      if($langs -notmatch 'ar'){
        $inst=PsOut 'try{ (Get-WindowsCapability -Online -Name "Language.OCR*ar-SA*" | Out-String); (Add-WindowsCapability -Online -Name "Language.OCR~~~ar-SA~0.0.1.0" | Out-String) }catch{ "ERR: "+$_.Exception.Message }' 420
        Say "DIAG ocr arabic capability install: [$inst]"
        $langs=PsOut $probe 60; Say "DIAG ocr languages after the install attempt: [$langs]"
      }
      if($langs -notmatch 'ar'){ Say 'NOTEXECUTED arabic ocr: no Arabic OCR engine on this runner (the Windows Arabic OCR capability could not be installed)' } else {
        $imgA=Join-Path $OutDir 'ocr-invoice-ar.png'; $bm=New-Object System.Drawing.Bitmap 1400,520; $g2=[System.Drawing.Graphics]::FromImage($bm); $g2.Clear([System.Drawing.Color]::White); $g2.TextRenderingHint=[System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $f2=New-Object System.Drawing.Font('Arial',26); $b2=[System.Drawing.Brushes]::Black; $sf=New-Object System.Drawing.StringFormat; $sf.FormatFlags=[System.Drawing.StringFormatFlags]::DirectionRightToLeft
        $ar1=-join ([char[]](0x0634,0x0631,0x0643,0x0629,0x20,0x0627,0x0644,0x062A,0x062C,0x0631,0x0628,0x0629,0x20,0x0644,0x0644,0x0623,0x062F,0x0648,0x064A,0x0629))
        $nm=@( (-join ([char[]](0x0623,0x062F,0x0648,0x0644,0x20,0x0625,0x0643,0x0633,0x062A,0x0631,0x0627))), (-join ([char[]](0x0633,0x064A,0x062A,0x0627,0x0644,0x20,0x0628,0x0644,0x0633))), (-join ([char[]](0x0632,0x0646,0x0643,0x20,0x0641,0x0648,0x0631,0x062A))) )
        $g2.DrawString($ar1,$f2,$b2,(New-Object System.Drawing.PointF(1300,30)),$sf); $g2.DrawString('Invoice No 12345    Date 20/11/2026',$f2,$b2,40,85)
        $hx2=@(470,580,720,830,960,1140); $hd2=@('Qty','Price','Disc','Net','Lot','Expiry'); for($i=0;$i -lt 6;$i++){ $g2.DrawString($hd2[$i],$f2,$b2,$hx2[$i],150) }
        $y=215; for($r=0;$r -lt 3;$r++){ $rw=$rowsT[$r]; $g2.DrawString($nm[$r],$f2,$b2,(New-Object System.Drawing.PointF(440,$y)),$sf); for($i=1;$i -lt 7;$i++){ $g2.DrawString($rw[$i],$f2,$b2,$hx2[$i-1],$y) }; $y+=60 }
        $g2.DrawString('Total 748.00',$f2,$b2,830,420); $g2.Dispose(); $bm.Save($imgA,[System.Drawing.Imaging.ImageFormat]::Png); $bm.Dispose()
        foreach($mode in @('ar-SA','both')){
          $oa=Join-Path $OutDir ("ocr-result-ar-$mode.json"); Remove-Item $oa -Force -ErrorAction SilentlyContinue
          $po=Start-Process -FilePath $exe -ArgumentList @('--ocr-selftest',('"'+$imgA+'"'),('"'+$oa+'"'),$mode) -PassThru; if(-not $po.WaitForExit(240000)){ try{ $po.Kill() }catch{}; Say "FAIL arabic ocr ($mode): timed out"; $script:fails++ }
          if(-not (Test-Path $oa)){ Say "FAIL arabic ocr ($mode): no result file"; $script:fails++; continue }
          $oa2=Get-Content $oa -Raw -Encoding utf8 | ConvertFrom-Json; if($oa2.error){ Say "FAIL arabic ocr ($mode): $($oa2.error)"; $script:fails++; continue }
          Say "DIAG arabic ocr ($mode): words=$($oa2.words) rows=$(@($oa2.rows).Count) supplier=[$($oa2.supplier)] text=[$($oa2.text)]"
          if($mode -eq 'both'){
            $ar_rows=@($oa2.rows); Check ($ar_rows.Count -eq 3) "arabic ocr (both engines): three item rows found ($($ar_rows.Count))"
            function FoldAr($t){ return ([regex]::Replace([string]$t,'[\u0622\u0623\u0625\u0671]',[string][char]0x0627)).Trim() }
            $supExp=[regex]::Unescape('\u0634\u0631\u0643\u0629 \u0627\u0644\u062A\u062C\u0631\u0628\u0629 \u0644\u0644\u0623\u062F\u0648\u064A\u0629')
            Check ((FoldAr $oa2.supplier) -eq (FoldAr $supExp)) 'arabic ocr: the supplier line reads in reading order (alef variants folded)'
            for($i=0;$i -lt [Math]::Min(3,$ar_rows.Count);$i++){ $e=$rowsT[$i]; $r=$ar_rows[$i]
              $okn=([decimal]$r.price -eq [decimal]$e[2]) -and ([string]$r.qty -eq $e[1]) -and ([decimal]$r.net -eq [decimal]$e[4]) -and ($r.lot -eq $e[5]) -and ($r.expiry -eq $e[6])
              Say "DIAG arabic ocr row $($i+1): name=[$($r.name)] qty=$($r.qty) price=$($r.price) net=$($r.net) lot=[$($r.lot)] exp=[$($r.expiry)]"
              Check $okn "arabic ocr: row $($i+1) numbers, lot and expiry read exactly"
              Check (([string]$r.name) -match '[\u0600-\u06FF]') "arabic ocr: row $($i+1) name came back as Arabic letters"
              Check ((FoldAr $r.name) -eq (FoldAr $nm[$i])) "arabic ocr: row $($i+1) Arabic name in reading order (alef variants folded: the engine drops hamza marks, display keeps what it read)"
              Say "INFO arabic ocr row $($i+1): hamza kept exactly=$((([string]$r.name).Trim()) -eq $nm[$i])" } } }
      }
    }catch{ Say "FAIL arabic ocr block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  }catch{ Say "FAIL ocr block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  # ---- l132: network cashier link (host on the main PC, a second program instance started with --station connects over TCP) ----
  # SYNTHETIC data only. This runs on ONE machine over 127.0.0.1: it proves the protocol, security checks and the station screens, NOT a second physical PC, the LAN or the Windows firewall.
  try{
    function PortOpen($pt){ try{ $tc=New-Object System.Net.Sockets.TcpClient; $iar=$tc.BeginConnect('127.0.0.1',$pt,$null,$null); $okc=$iar.AsyncWaitHandle.WaitOne(2000); $res=($okc -and $tc.Connected); $tc.Close(); return $res }catch{ return $false } }
    function NetOps($tag,$act){ try{ return (NetOpsInner $tag $act) }catch{ Say "FAIL network $tag step: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++; try{ [void](CloseOps ($tag+'-close-after-error')) }catch{}; return $null } }
    function NetOpsInner($tag,$act){ if(-not (NavTo @('الأصناف والمشتريات','Products & Purchasing') ($tag+'-inv') 'InvSearchBox')){ Say "NOTEXECUTED network: could not open the Products page ($tag)"; return $null }
      $opened=OpenOps $tag; $ow=OpsWin; if(-not $opened -or -not $ow){ Say "NOTEXECUTED network: the Operations window could not be opened ($tag)"; return $null }
      $tabs=TabByName $ow 'محطات الكاشير'; if(-not $tabs){ Say "NOTEXECUTED network: the stations tab was not found ($tag)"; [void](CloseOps ($tag+'-close')); return $null }
      try{ $tabs.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }catch{ Say "INFO net tab select: $($_.Exception.Message)" }; Start-Sleep 1
      $r=& $act $ow; [void](CloseOps ($tag+'-close')); return $r }
    $netCode=NetOps 'net1' { param($ow)
      $st=ById $ow 'OpsNetState' 5; $st0=if($st){ [string]$st.Current.Name } else { '(missing)' }; Say "DIAG net state before: [$st0]"; Shot '91-net-tab-default'
      Check ($st0 -like '*متوقف*') 'network link: the default state is OFF (متوقف)'
      Check (-not (PortOpen 47621)) 'network link: nothing listens on the port before it is enabled'
      $en=ById $ow 'OpsNetEnable' 5; if(-not $en){ Say 'NOTEXECUTED network: enable button not found'; return '' }
      try{ $en.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL net enable invoke: $($_.Exception.Message)"; $script:fails++ }; Start-Sleep 4
      $ce=ById $ow 'OpsNetCode' 5; $c=''; if($ce){ try{ $c=[string]$ce.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{} }
      $pp=@($c -split '\.'); Check ($pp.Count -eq 2 -and $pp[0] -eq 'OFAGN1' -and $pp[1].Length -eq 43) 'network link: a station code of the agreed shape (OFAGN1.43 chars) is shown'
      $st=ById $ow 'OpsNetState' 5; $st1=if($st){ [string]$st.Current.Name } else { '(missing)' }; Say "DIAG net state after enable: [$st1]"; Shot '92-net-enabled'
      Check ($st1 -like '*يعمل*') 'network link: the state reads RUNNING after enabling'
      Check (PortOpen 47621) 'network link: the host now accepts TCP connections on the port (loopback)'
      return $c }
    if($netCode -and $netCode.StartsWith('OFAGN1.')){
      Set-Content -Path (Join-Path $OutDir 'net-code.txt') -Value $netCode -Encoding ascii -NoNewline
      $sp=Start-Process -FilePath $exe -ArgumentList '--station' -PassThru
      $sw=$null; $end=(Get-Date).AddSeconds(40); do{ foreach($w in (TopWins $sp.Id)){ if($w.Current.Name -eq 'محطة كاشير'){ $sw=$w } }; if(-not $sw){ Start-Sleep -Milliseconds 500 } }while(-not $sw -and (Get-Date) -lt $end)
      if(-not $sw){ Say 'FAIL network: the station window did not open'; $script:fails++; Shot '93-net-no-station' } else {
        function SetV($id,$v){ $e=ById $sw $id 5; if(-not $e){ Say "FAIL network: control $id not found"; $script:fails++; return }; try{ $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($v) }catch{ Say "FAIL network: set $id : $($_.Exception.Message)"; $script:fails++ } }
        function Clk($id){ $e=ById $sw $id 5; if(-not $e){ Say "FAIL network: button $id not found"; $script:fails++; return }; try{ $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL network: click $id : $($_.Exception.Message)"; $script:fails++ } }
        function StatusT(){ $e=ById $sw 'StationStatus' 3; if($e){ return [string]$e.Current.Name } else { return '(missing)' } }
        function StationLogin(){ $pb=ById $sw 'StationPassword' 5; if(-not $pb){ Say 'FAIL network: password box not found'; $script:fails++; return }
          try{ $h=[System.IntPtr]([int]$sw.Current.NativeWindowHandle); [void][M.W]::SetForegroundWindow($h); $sw.SetFocus() }catch{}; Start-Sleep -Milliseconds 400; $pb.SetFocus(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 100; [System.Windows.Forms.SendKeys]::SendWait('{BACKSPACE}'); Start-Sleep -Milliseconds 150
          $fgS={ try{ $h=[M.W]::GetForegroundWindow(); [uint32]$fp=0; [void][M.W]::GetWindowThreadProcessId($h,[ref]$fp); return ($fp -eq [uint32]$sp.Id) }catch{ return $false } }
          $tr=TypeSecret $pwCash $fgS { param($k) [System.Windows.Forms.SendKeys]::SendWait($k) }; Say "DIAG network: station password typed=$($tr.typed)/$($tr.expected) lost=$($tr.lost)"; Clk 'StationLoginButton'; Start-Sleep 3 }
        Start-Sleep 2; Shot '93-net-station-open'
        # 1. a WRONG station code must not give access
        SetV 'StationHost' '127.0.0.1'; SetV 'StationPort' '47621'; SetV 'StationCode' ('OFAGN1.'+('A'*43)); Clk 'StationConnect'; Start-Sleep 2
        SetV 'StationUser' 'cashier1'; StationLogin; $sb=StatusT; Say "DIAG network wrong-code status: [$sb]"; Shot '94-net-wrong-code'
        $saleBox=ById $sw 'StationSearchButton' 2; Check ($sb -notlike '*تم الدخول*' -and ($null -eq $saleBox -or -not $saleBox.Current.IsEnabled)) 'network link: a station with a WRONG code is not signed in and the sale panel stays disabled'
        # 2. the right code
        SetV 'StationCode' $netCode; Clk 'StationConnect'; Start-Sleep 3; $sc=StatusT; Say "DIAG network connect status: [$sc]"; Check ($sc -like '*تم الاتصال*') 'network link: the station connects with the right code'
        StationLogin; $sl=StatusT; Say "DIAG network login status: [$sl]"; Shot '95-net-station-login'; Check ($sl -like '*تم الدخول*cashier1*Cashier*') 'network link: the cashier signs in over the link and the host reports the real role (Cashier)'
        Clk 'StationShiftButton'; Start-Sleep 3; Say "DIAG network shift status: [$(StatusT)]"
        SetV 'StationSearch' 'Synthetic'; Clk 'StationSearchButton'; Start-Sleep 3; $ss=StatusT; Say "DIAG network search status: [$ss]"
        $g=ById $sw 'StationGrid' 5; $rows=@(); if($g){ $rows=@($g.FindAll($TS::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::DataItem)))) }
        Check ($rows.Count -ge 1) "network link: the search returns stock rows from the host ($($rows.Count) rows)"
        if($rows.Count -ge 1){
          try{ $rows[0].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }catch{ Say "FAIL network: select row: $($_.Exception.Message)"; $script:fails++ }; Start-Sleep 1
          SetV 'StationUnits' '1'; Clk 'StationAddButton'; Start-Sleep 3; Say "DIAG network add status: [$(StatusT)]"
          $cb=ById $sw 'StationCart' 3; $ci=@(); if($cb){ $ci=@($cb.FindAll($TS::Children,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))) }
          Check ($ci.Count -ge 1) "network link: the FEFO pick from the host fills the cart ($($ci.Count) line)"; Shot '96-net-cart'
          Clk 'StationSellButton'; Start-Sleep 4; $re=ById $sw 'StationReceipt' 3; $rt=if($re){ [string]$re.Current.Name } else { '(missing)' }; Say "DIAG network receipt: [$rt]"; Shot '97-net-sold'
          Check ($rt -like '*الإيصال*الإجمالي*cashier1*') 'network link: the sale completed on the host and its receipt came back to the station'
        }
      }
      try{ if($sp -and -not $sp.HasExited){ $sp.Kill() } }catch{}; Start-Sleep 2
      [void](NetOps 'net2' { param($ow)
        $dis=ById $ow 'OpsNetDisable' 5; if(-not $dis){ Say 'NOTEXECUTED network: disable button not found'; return $null }
        try{ $dis.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL net disable invoke: $($_.Exception.Message)"; $script:fails++ }; Start-Sleep 3
        $st=ById $ow 'OpsNetState' 5; $st2=if($st){ [string]$st.Current.Name } else { '(missing)' }; Say "DIAG net state after disable: [$st2]"; Shot '98-net-disabled'
        Check ($st2 -like '*متوقف*') 'network link: the state reads OFF after disabling'
        Check (-not (PortOpen 47621)) 'network link: after disabling, the port no longer accepts connections'
        return $null })
    } else { Say 'NOTEXECUTED network link: no station code, the station part did not run'; $script:notexec++ }
  }catch{ Say "FAIL network link block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
  Sanitize 'before-restart'
  # persistence across a restart
  try{ $p.CloseMainWindow() | Out-Null; Start-Sleep 3; if(-not $p.HasExited){ $p.Kill() } }catch{}
  Start-Sleep 2
  Launch 'launch2'
  if(Login 'owner' $pwOwner 'owner2'){ Start-Sleep 2; Shot '30-relaunch-after-login'; $r2=@(RailDiag 'relaunch'); Check ($r2.Count -ge 8) "after a restart the rail is still the layout ($($r2.Count) items)" }
  # ---- l130: live database encryption (SQLite3 Multiple Ciphers 3.54.1). Runs last because it restarts the app several times. SYNTHETIC trial data only. ----
  try{
    $dbp=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'OneForAllGood-TRIAL\pharmacy.db'; $dbdir=Split-Path $dbp
    function Hdr($f){ try{ $fs=[System.IO.File]::Open($f,'Open','Read','ReadWrite'); $b=New-Object byte[] 15; [void]$fs.Read($b,0,15); $fs.Close(); return [System.Text.Encoding]::ASCII.GetString($b) }catch{ return "(unreadable: $($_.Exception.Message))" } }
    function FindWinWith($id,$sec){ $end=(Get-Date).AddSeconds($sec); do{ foreach($w in (TopWins $p.Id)){ $e=ById $w $id 1; if($e){ return @{ win=$w; el=$e } } }; Start-Sleep -Milliseconds 300 }while((Get-Date) -lt $end); return $null }
    function LaunchWith($tag,$pre){
      $script:p=Start-Process -FilePath $exe -PassThru
      & $pre
      $mb=$null; $end=(Get-Date).AddSeconds(40); do{ foreach($w in (TopWins $script:p.Id)){ if($w.Current.ClassName -eq '#32770'){ $mb=$w } }; if($script:p.HasExited){ Say "FAIL $tag exited early"; return $false }; if(-not $mb){ Start-Sleep -Milliseconds 400 } }while(-not $mb -and (Get-Date) -lt $end)
      if($mb){ Say "PASS $tag start warning found"; try{$mb.SetFocus()}catch{}; Start-Sleep -Milliseconds 500; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 3 } else { Say "FAIL $tag no start warning"; return $false }
      $script:main=$null; $end=(Get-Date).AddSeconds(40); do{ foreach($w in (TopWins $script:p.Id)){ if($w.Current.ClassName -ne '#32770' -and $w.Current.Name){ $script:main=$w } }; if(-not $script:main){ Start-Sleep -Milliseconds 400 } }while(-not $script:main -and (Get-Date) -lt $end)
      if(-not $script:main){ Say "FAIL $tag no main window"; return $false }
      Say "PASS $tag main window: $($script:main.Current.Name)"; Start-Sleep 2; return $true }
    $h0=Hdr $dbp; Say "DIAG db header before encryption: [$h0]"; Check ($h0 -eq 'SQLite format 3') 'database encryption: before, the file has the plain SQLite header'
    $encOk=$false
    if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'enc-inventory' 'InvSearchBox'){
      $opened=OpenOps 'enc1'; $ow=OpsWin
      if(-not $opened -or -not $ow){ Say 'NOTEXECUTED database encryption: the Operations window could not be opened'; $script:notexec++ } else {
        $es=ById $ow 'OpsEncState' 6; $es0=if($es){ [string]$es.Current.Name } else { '(missing)' }; Say "DIAG enc state before: [$es0]"; Shot '83-enc-before'
        Check ($es0 -like '*غير مشفرة*') 'database encryption: the window says the database is not encrypted yet'
        $eb=ById $ow 'OpsEncryptDb' 6
        if(-not $eb){ Say 'NOTEXECUTED database encryption: OpsEncryptDb button not found'; $script:notexec++ } else {
          try{ $eb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL enc invoke: $($_.Exception.Message)"; $script:fails++ }
          $m=WaitModal 12
          if($m){ $script:curModal=$m; $descs=ModalDescs $m; $yes=XPickButton $descs 'yes'; if($yes){ [void](PressDesc $yes 'enc-confirm' 'Yes') } else { Say 'FAIL enc: confirmation Yes not identified'; $script:fails++ } } else { Say 'FAIL enc: the confirmation did not appear'; $script:fails++ }
          $rkw=FindWinWith 'RecKeyText' 15
          if(-not $rkw){ Say 'FAIL enc: the recovery key window did not appear'; $script:fails++; Shot '84-enc-no-reckey' } else {
            $rk=''; try{ $rk=[string]$rkw.el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{}
            Shot '84-enc-recovery-key'
            Check ($rk -match '^[0-9a-f]{64}$') 'database encryption: the recovery key (64 hex = 256-bit) is shown'
            $okb=ById $rkw.win 'RecKeyOk' 3; $okEnabledBefore=$false; try{ $okEnabledBefore=[bool]$okb.Current.IsEnabled }catch{}
            Check (-not $okEnabledBefore) 'database encryption: OK stays disabled until the owner ticks "I saved the key"'
            $cbx=ById $rkw.win 'RecKeySaved' 3; if($cbx){ try{ $cbx.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle() }catch{ Say "FAIL enc tick: $($_.Exception.Message)"; $script:fails++ } }; Start-Sleep 1
            Set-Content -Path (Join-Path $OutDir 'enc-recovery-key.txt') -Value $rk -Encoding ascii -NoNewline
            try{ $okb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL enc OK invoke: $($_.Exception.Message)"; $script:fails++ }
            $m2=WaitModal 40; if($m2){ Say "MODAL enc-done text=[$((@(WinBoxStatics $m2)) -join ' / ')]"; Shot '85-enc-done'; [void](ModalDismiss 'enc-done') } else { Say 'FAIL enc: the finished message did not appear'; $script:fails++ }
            $end=(Get-Date).AddSeconds(60); while(-not $p.HasExited -and (Get-Date) -lt $end){ Start-Sleep -Milliseconds 400 }
            Check ($p.HasExited) 'database encryption: the program closes itself after encrypting'
            $encOk=$true
          }
        }
      }
    } else { Say 'NOTEXECUTED database encryption: could not open the Products page' }
    if($encOk){
      if(-not $p.HasExited){ try{ $p.Kill() }catch{} }; Start-Sleep 2
      $h1=Hdr $dbp; Say "DIAG db header after encryption: [$h1]"; Check ($h1 -ne 'SQLite format 3' -and $h1 -notlike '(unreadable*') 'database encryption: after, the file does NOT have the SQLite header'
      $bytes=[System.IO.File]::ReadAllBytes($dbp); $txt=[System.Text.Encoding]::UTF8.GetString($bytes); Check (-not $txt.Contains('Synthetic Fast A') -and -not $txt.Contains('owner')) 'database encryption: product and user names are not readable in the file bytes'
      Check (Test-Path (Join-Path $dbdir 'db-key.dat')) 'database encryption: the Windows-protected key file exists'
      $pb=@(Get-ChildItem -Path $dbdir -Filter 'pharmacy.db.plain-backup-*' -ErrorAction SilentlyContinue); Check ($pb.Count -ge 1 -and (Hdr $pb[0].FullName) -eq 'SQLite format 3') 'database encryption: a plain safety copy exists (and is plain, to be deleted by the owner)'
      # restart: key comes from Windows silently, data is there
      $okL=LaunchWith 'launch3' {}
      if(-not $okL){ Say 'FAIL launch3 (encrypted database, stored key) did not start'; $script:fails++ } elseif(Login 'owner' $pwOwner 'owner-encrypted'){
        Start-Sleep 2; Shot '86-enc-relaunch'
        if(NavTo @('الأصناف والمشتريات','Products & Purchasing') 'enc-items' 'InvSearchBox'){
          $sb=Pick 'InvSearchBox' 5; if($sb){ try{ $sb.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Synthetic Fast A') }catch{} ; Start-Sleep 2 }
          $found=$false; foreach($r in @(RowsIn $main 'ProductGrid')){ if(@(RowCells $r) -ccontains 'Synthetic Fast A'){ $found=$true; break } }
          Check $found 'database encryption: after restart (key from Windows, no prompt) the data is there: Synthetic Fast A is listed'
          Shot '87-enc-items'
        }
        # delete the plain copies from the app
        $opened=OpenOps 'enc2'; $ow=OpsWin
        if($opened -and $ow){
          $es=ById $ow 'OpsEncState' 6; Check (([string]$es.Current.Name) -like '*مشفرة.*' -and ([string]$es.Current.Name) -notlike '*غير*') 'database encryption: the window now says the database is encrypted'
          $dp=ById $ow 'OpsDeletePlain' 6
          if($dp){ try{ $dp.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL delete-plain invoke: $($_.Exception.Message)"; $script:fails++ }
            $m=WaitModal 10; if($m){ $script:curModal=$m; $descs=ModalDescs $m; $yes=XPickButton $descs 'yes'; if($yes){ [void](PressDesc $yes 'enc-del-confirm' 'Yes') } else { Say 'FAIL enc: delete confirmation Yes not identified'; $script:fails++ } } else { Say 'FAIL enc: the delete confirmation did not appear'; $script:fails++ }
            Start-Sleep 2; Shot '88-enc-plain-deleted'
            $pb2=@(Get-ChildItem -Path $dbdir -Filter 'pharmacy.db.plain-backup-*' -ErrorAction SilentlyContinue); Check ($pb2.Count -eq 0) 'database encryption: the plain safety copies are gone after the owner deletes them in the app'
          } else { Say 'NOTEXECUTED delete plain copies: button not found'; $script:notexec++ }
          [void](CloseOps 'enc2-close')
        } else { Say 'NOTEXECUTED delete plain copies: Operations window did not open'; $script:notexec++ }
      }
      # lost Windows key file: recovery key path (wrong key first, then the right one)
      try{ $p.CloseMainWindow() | Out-Null; Start-Sleep 3; if(-not $p.HasExited){ $p.Kill() } }catch{}; Start-Sleep 2
      Remove-Item -Path (Join-Path $dbdir 'db-key.dat') -Force -ErrorAction SilentlyContinue
      $rkSaved=(Get-Content (Join-Path $OutDir 'enc-recovery-key.txt') -Raw).Trim()
      $okR=LaunchWith 'launch4' {
        $w1=FindWinWith 'RecKeyInput' 25
        if(-not $w1){ Say 'FAIL recovery: the key prompt did not appear when the Windows key file was missing'; $script:fails++; return }
        Say 'PASS recovery: the app asks for the recovery key when the Windows key file is missing'; Shot '89-enc-recovery-prompt'
        try{ $w1.el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue(('a'*64)) }catch{}
        try{ (ById $w1.win 'RecKeyOk' 3).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{}
        $bad=WaitModal 10; Check ($null -ne $bad) 'recovery: a wrong key is refused with a message'; if($bad){ [void](ModalDismiss 'enc-wrong-key') }
        $w2=FindWinWith 'RecKeyInput' 15
        if(-not $w2){ Say 'FAIL recovery: the prompt did not come back after a wrong key'; $script:fails++; return }
        try{ $w2.el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($rkSaved) }catch{}
        try{ (ById $w2.win 'RecKeyOk' 3).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL recovery OK invoke: $($_.Exception.Message)"; $script:fails++ }
      }
      if($okR -and (Login 'owner' $pwOwner 'owner-recovered')){ Start-Sleep 2; Shot '90-enc-recovered'; Check (Test-Path (Join-Path $dbdir 'db-key.dat')) 'recovery: the right recovery key opened the data and re-saved the Windows key file'; $r4=@(RailDiag 'recovered'); Check ($r4.Count -ge 8) "recovery: the app is usable after the recovery key ($($r4.Count) rail items)" }
      elseif(-not $okR){ Say 'FAIL recovery launch did not complete'; $script:fails++ }
    }
  }catch{ Say "FAIL database encryption block: $($_.Exception.Message) (script line $($_.InvocationInfo.ScriptLineNumber): $(([string]$_.InvocationInfo.Line).Trim()))"; $script:fails++ }
}
try{ $p.Refresh(); if(-not $p.HasExited){ Say 'PASS process still running at end' } else { Say 'FAIL process exited during the run'; $script:fails++ } }catch{}
DumpLockLog 'end of run'
try{ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }catch{}
Say 'EXCLUDED-SCOPE: Manager, Inventory and HR roles, cashier sale and permission refusals, English mode beyond the login screen and rail, DPI scaling, real data'
if((Verdict) -ne 0){ Say "RESULT FAILED fails=$($script:fails) halt=$($script:halt) everHalted=$($script:everHalted) notexecuted=$($script:notexec) abort=$($script:abort)"; exit 1 } else { Say 'RESULT all assertions passed' }
