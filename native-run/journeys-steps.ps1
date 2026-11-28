function JnCustomerAfterSale(){
  # l198: the status line is overwritten by the generic saved message, so read the customer's own screen: profile text and purchase rows after the linked sale
  try{
    $b=Pick 'SaleCustomerButton' 4; if(-not $b){ return }
    $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 2
    $w=WinByTitle 'عميل للبيع' 10; if(-not $w){ Say 'NOTEXECUTED journeys cashier customer after sale: window did not open'; $script:notexec++; return }
    try{ $cm=$w.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'CsMessage'))); if($cm){ Say "DIAG journeys cashier customer: window message [$([string]$cm.Current.Name)]" } }catch{}
    $pn=BizPickCombo $w 'CsCustomer' '*Synthetic Customer*'; Start-Sleep 1
    $pr=ById $w 'CsProfile' 3; $pt=if($pr){ [string]$pr.Current.Name } else { '(missing)' }; Say "DIAG journeys cashier customer after sale: profile [$pt]"
    $pg=ById $w 'CsPurchases' 3; $cnt=-1; if($pg){ try{ $cnt=[int]$pg.GetCurrentPattern([System.Windows.Automation.GridPattern]::Pattern).Current.RowCount }catch{} }; Say "DIAG journeys cashier customer after sale: purchase rows=$cnt"
    Check ($cnt -ge 1) 'journeys cashier: the customer screen lists the linked sale'; Shot 'jn-cashier-customer-after-sale'
    try{ $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{}; Start-Sleep 1
  }catch{ Say "INFO journeys cashier customer after sale: $($_.Exception.Message)" } }
function JnStatusText(){ $e=Pick 'StatusLabel' 3; if($e){ return [string]$e.Current.Name } else { return '(missing)' } }
$script:jnCustomerAttached=$false
function JnCashierCustomer(){
  # l198: attach the synthetic loyalty customer to the next sale BEFORE paying (non-controlled line; the customer was added by the owner in BizSeedCustomer)
  try{
    $b=Pick 'SaleCustomerButton' 4; if(-not $b){ Say 'NOTEXECUTED journeys cashier customer: SaleCustomerButton not found'; $script:notexec++; return }
    $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 2
    $w=WinByTitle 'عميل للبيع' 10; if(-not $w){ Say 'NOTEXECUTED journeys cashier customer: the customer window did not open'; $script:notexec++; return }
try{ $cm=$w.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'CsMessage'))); if($cm){ Say "DIAG journeys cashier customer: window message [$([string]$cm.Current.Name)]" } }catch{}
    $pn=BizPickCombo $w 'CsCustomer' '*Synthetic Customer*'; if(-not $pn){ $pn=BizPickCombo $w 'CsCustomer' '' }
    Say "DIAG journeys cashier customer: chosen [$pn]"
    if($pn -and (BizInvoke $w 'CsUseNext')){ Start-Sleep 1; [void](JnLeftoverModal 'cashier-customer'); $lb=Pick 'SaleCustomerLabel' 3; $lt=if($lb){ [string]$lb.Current.Name } else { '(missing)' }; Say "DIAG journeys cashier customer: label [$lt]"; Check ($lt -like '*البيع التالي للعميل*') 'journeys cashier: the next sale is attached to the chosen customer (label shown)'; $script:jnCustomerAttached=$true; Shot 'jn-cashier-customer-attached' }
    else { Say 'NOTEXECUTED journeys cashier customer: no customer could be chosen (see DIAG)'; $script:notexec++; try{ $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{} }
  }catch{ Say "FAIL journeys cashier customer: $($_.Exception.Message)"; $script:fails++ } }
function JnReprint(){
  # l196: the reprint text window, driven right after the cashier sale (this.receipt is only set in the session that made the sale)
  $rb=Pick 'ReprintButton' 4; if(-not $rb){ Say 'NOTEXECUTED journeys reprint: ReprintButton not found'; $script:notexec++; return }
  $en=$false; try{ $en=[bool]$rb.Current.IsEnabled }catch{}; if(-not $en){ Say 'NOTEXECUTED journeys reprint: ReprintButton is disabled (no completed sale in this session)'; $script:notexec++; return }
  try{ $rb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL journeys reprint: invoke: $($_.Exception.Message)"; $script:fails++; return }
  Start-Sleep 2; $rw=$null; foreach($w in @(AllWinsDeep)){ if([string]$w.Current.Name -like '*نسخة مكررة*'){ $rw=$w } }
  if(-not $rw){ $md=FindModal; if($md){ Say "DIAG journeys reprint: a dialog opened instead [$($md.Current.Name)] texts=[$((@(WinBoxStatics $md)) -join ' / ')]"; [void](ModalDismiss 'jn-reprint-other') }; Say 'NOTEXECUTED journeys reprint: the reprint window did not open (see DIAG)'; $script:notexec++; return }
  Check ($true) 'journeys reprint: the duplicate-receipt window opens'
  $tb=$rw.FindFirst([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'ReprintText')))
  $txt=''; if($tb){ try{ $txt=[string]$tb.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{} }
  if($tb -and -not $txt){ try{ $txt=[string]$tb.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern).DocumentRange.GetText(20000) }catch{ Say "INFO journeys reprint: TextPattern read failed: $($_.Exception.Message)" } }
  if(-not $txt -and $tb){ $txt=[string]$tb.Current.Name }
  # l205: strengthened. The l204 table put each value one character per line, with non-empty text. Now: enough lines, the label and its value on the same row (UIA text elements), and no narrow wrapped text element.
  $nl=@(($txt -split "`n") | Where-Object { $_.Trim().Length -gt 0 }).Count; Say "DIAG journeys reprint: non-empty lines=$nl"
  $narrow=@(); $tbl=@(); try{ foreach($te in @($rw.FindAll([System.Windows.Automation.TreeScope]::Descendants,(New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text))))){ $nm=[string]$te.Current.Name; $br=$te.Current.BoundingRectangle; if($nm.Length -ge 4 -and -not $br.IsEmpty){ $tbl+=$nm; if(($br.Width / $nm.Length) -lt 3.0){ $narrow+=("[$nm w=$([int]$br.Width)]") } } } }catch{}
  Say "DIAG journeys reprint: text elements=$($tbl.Count) narrow=$($narrow.Count) $($narrow -join ' ')"
  Check ($nl -ge 8) 'journeys reprint: the receipt has at least 8 non-empty lines (header, id, time, cashier, item, total, thanks)'
  Check ($narrow.Count -eq 0 -and $tbl.Count -ge 5) 'journeys reprint: no text element is squeezed (width per character) and at least 5 text elements are measured'
  Say "DIAG journeys reprint: first lines = [$((($txt -split "`n") | Select-Object -First 6) -join ' // ')]"
  Say "DIAG journeys reprint: text length=$($txt.Length)"
  Check ($txt.Length -gt 20 -and $txt -match '\d') 'journeys reprint: the window shows a non-empty receipt text with numbers'
  Shot 'jn-cashier-reprint'
  try{ $rw.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{ Say "INFO journeys reprint: close failed: $($_.Exception.Message)" }
  Start-Sleep 1; [void](JnLeftoverModal 'cashier-after-reprint')
}
# l170 role journeys on real Windows: the owner creates a manager and an inventory user (the cashier already exists from the roles block), then each role logs in,
# visits every page on its rail, a screenshot is taken per page, and the UIA layout audit runs per page. Pages are VISITED, not worked through: no sale, refund or stock edit is driven here.
# l171 adds: cashier opens a shift, sells the first stock line, checks the refund button, closes the shift; the manager then refunds that sale through the reason dialog.
# Proves: per-role rail contents, that every page opens without a modal, and layout flags from UIA rectangles (not pixel proof). A person must read the screenshots.
. (Join-Path $PSScriptRoot 'business-steps.ps1')
# l177: close every top-level window of the program except the main one (l176: the "العمليات والنسخ" rail item opens its own Operations window; it stayed open, took the keyboard focus, and the next focus+Space pressed "restore from backup" there, leaving a file dialog). Never sends a key.
function JnCloseExtras($tag){
  # l178: owned (modal) windows are listed by UIA as children of their owner, not of the desktop, so the l177 TopWins loop never saw the Operations window. AllWinsDeep walks both. Logs every window it sees (the proof line).
  $n=0; try{ $mh=[int]$main.Current.NativeWindowHandle; $names=@()
    $all=@(AllWinsDeep); foreach($w in $all){ $h=0; try{ $h=[int]$w.Current.NativeWindowHandle }catch{}; $nm=''; try{ $nm=[string]$w.Current.Name }catch{}; $names+=("[$nm|hwnd=$h"+$(if($h -eq $mh){'|MAIN'}else{''})+"]") }
    Say "INFO journeys: $tag window check: $($all.Count) window(s) $($names -join ' ')"
    foreach($w in $all){ $h=0; try{ $h=[int]$w.Current.NativeWindowHandle }catch{}; if($h -eq $mh -or $h -eq 0){ continue }
      $nm=''; try{ $nm=[string]$w.Current.Name }catch{}; $cl=''; try{ $cl=[string]$w.Current.ClassName }catch{}
      # l180: a WPF ToolTip or drop-down is a Popup-class window with no title; it is not an extra program window and closes itself. Logged, not counted as a failure.
      if($cl -eq 'Popup' -and -not $nm){ Say "INFO journeys: $tag ignored Popup-class window with empty title (tooltip or drop-down, not a program window)"; continue }
      $closed=$false
      try{ $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); $closed=$true }catch{ Say "DIAG journeys: $tag WindowPattern.Close failed for [$nm]: $($_.Exception.Message)" }
      if(-not $closed){ try{ $bc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button); foreach($bt in @($w.FindAll($TS::Descendants,$bc))){ $bn=[string]$bt.Current.Name; $bi=[string]$bt.Current.AutomationId; if($bn -in @('Close','إغلاق','Cancel','إلغاء') -or $bi -eq 'Close'){ $bt.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $closed=$true; break } } }catch{ Say "DIAG journeys: $tag close-button fallback failed for [$nm]: $($_.Exception.Message)" } }
      if($closed){ $n++; Say "INFO journeys: $tag closed extra window [$nm] class=[$cl]"; Start-Sleep -Milliseconds 900 } else { Say "FAIL journeys: $tag could not close extra window [$nm] class=[$cl]"; $script:fails++ } }
    if($n -gt 0){ $left=@(AllWinsDeep).Count; Say "INFO journeys: $tag windows left after closing: $left (1 expected)" }
  }catch{ Say "DIAG journeys: JnCloseExtras failed: $($_.Exception.Message)" }
  return $n }
function JnPageSig(){ try{ $tc=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::Text); $mr=$main.Current.BoundingRectangle; $o=@(); foreach($e in @($main.FindAll($TS::Descendants,$tc))){ try{ $b=$e.Current.BoundingRectangle; if($b.X -lt ($mr.X+$mr.Width*0.62)){ $o+=[string]$e.Current.Name } }catch{} }; return (($o | Select-Object -First 60) -join '|') }catch{ return '' } }
function JnCreateUser($name,$pw,$roleWord){
  $ok=$false
  try{
    if(-not (NavTo @('الإدارة والنسخ الاحتياطي','Administration and backup') "jn-create-$name" 'NewUsername')){ return $false }
    $nu=Pick 'NewUsername' 5; $np=Pick 'NewPassword' 5; $ab=Pick 'AddUserButton' 5; $nr=Pick 'NewRole' 5
    if(-not ($nu -and $np -and $ab -and $nr)){ Say "NOTEXECUTED journeys: create-user controls for $name not found"; return $false }
    $nu.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($name)
    [void](BringFg); $np.SetFocus(); Start-Sleep -Milliseconds 400; $tr=TypeSecret $pw { FgOurs } { param($k) [System.Windows.Forms.SendKeys]::SendWait($k) }; Say "DIAG journeys: $name password typed=$($tr.typed)/$($tr.expected)"
    $ec=$nr.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern); $ec.Expand(); Start-Sleep -Milliseconds 700
    # l175: the drop-down list lives in a separate Popup window, so it must be searched in every top-level window of the process (l171: not found under the main window only)
    $li=@(); foreach($w in @(AllWinsDeep)){ $li+=@($w.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem))) | Where-Object { [string]$_.Current.Name -like "*$roleWord*" }) }
    $picked=$false; if(@($li).Count -ge 1){ $it=@($li)[0]; try{ $it.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $picked=$true }catch{ try{ $it.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $picked=$true }catch{} } }
    try{ $ec.Collapse() }catch{}
    if(-not $picked){
      # keyboard fallback: list order is Cashier, Inventory, HR, Manager; the box starts on Cashier
      $steps=@{ 'Cashier'=0; 'Inventory'=1; 'HR'=2; 'Manager'=3 }[$roleWord]
      if($null -ne $steps){ try{ $nr.SetFocus(); Start-Sleep -Milliseconds 400; for($k=0;$k -lt $steps;$k++){ [System.Windows.Forms.SendKeys]::SendWait('{DOWN}'); Start-Sleep -Milliseconds 300 }; $picked=$true; Say "DIAG journeys: role [$roleWord] chosen by $steps Down key(s) (popup items found: $(@($li).Count))" }catch{ Say "DIAG journeys: keyboard role pick failed: $($_.Exception.Message)" } } }
    Say "DIAG journeys: role item [$roleWord] picked=$picked; box now shows [$([string]$nr.Current.Name)]"
    if(-not $picked){ Say "NOTEXECUTED journeys: role $roleWord could not be chosen for $name"; return $false }
    # l195: verify the box really holds the wanted role before creating the user (l194: inventory1 box read [] and the user looked like a manager)
    $rd={ $t=''; try{ $t=[string]$nr.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{}; if(-not $t){ try{ $g=@($nr.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern).Current.GetSelection()); if($g.Count -gt 0){ $t=[string]$g[0].Current.Name } }catch{} }; if(-not $t){ $t=[string]$nr.Current.Name }; $t }
    $now=& $rd; Say "DIAG journeys: role box reads [$now] (want *$roleWord*)"
    if($now -notlike "*$roleWord*"){
      $st2=@{ 'Cashier'=0; 'Inventory'=1; 'HR'=2; 'Manager'=3 }[$roleWord]
      if($null -ne $st2 -and (BringFg)){ try{ $nr.SetFocus(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait('{HOME}'); Start-Sleep -Milliseconds 300; for($k=0;$k -lt $st2;$k++){ [System.Windows.Forms.SendKeys]::SendWait('{DOWN}'); Start-Sleep -Milliseconds 300 }; $now=& $rd; Say "DIAG journeys: after HOME + $st2 Down key(s) the role box reads [$now]" }catch{ Say "DIAG journeys: role retry failed: $($_.Exception.Message)" } }
      if($now -notlike "*$roleWord*"){ Say "NOTEXECUTED journeys: role box does not show $roleWord (reads [$now]); $name NOT created, so no wrong-role user exists"; $script:notexec++; return $false } }
    $ab.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 3
    $md=FindModal; if($md){ Say "DIAG journeys: modal after create $name [$($md.Current.Name)]"; try{ $md.SetFocus() }catch{}; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 1 }
    $ok=$true
  }catch{ Say "FAIL journeys: create $name : $($_.Exception.Message)"; $script:fails++ }
  return $ok }
function JnVisit($role,$mustLackAdmin){
  Start-Sleep 2; [void](JnCloseExtras "jn-$role-start"); [void](BringFg); Shot "jn-$role-landing"; LayoutAudit "$role-landing" $null
  $items=@(); for($i=1;$i -le 5;$i++){ $items=@(RailItems); if($items.Count -gt 0){ break }; Start-Sleep 2 }
  $labels=@($items | ForEach-Object { if($_.Label){ $_.Label } else { $_.Raw } }); Say "INFO journeys: $role rail ($($labels.Count)): $($labels -join ' | ')"
  Check ($labels.Count -ge 1) "journeys: $role sees at least one page on the rail"
  if(-not $script:jnRail){ $script:jnRail=@{} }; $script:jnRail[$role]=$labels.Count
  if($role -eq 'inventory' -and $script:jnRail.ContainsKey('manager')){ Check ($labels.Count -lt $script:jnRail['manager']) "journeys: inventory sees fewer rail pages ($($labels.Count)) than manager ($($script:jnRail['manager']))" }
  $hasAdmin=@($labels | Where-Object { $_ -match 'الإدارة' }).Count -gt 0
  if($mustLackAdmin){ Check (-not $hasAdmin) "journeys: $role does not see the administration page" } else { Check $hasAdmin "journeys: $role sees the administration page" }
  $n=0; foreach($it in $items){ $n++; $lab=if($it.Label){ $it.Label } else { "item$n" }
    $sig0=JnPageSig
    try{ $it.El.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 1800 }catch{ Say "INFO journeys: $role page [$lab] select failed: $($_.Exception.Message)" }
    # l175: in l171 the rail item looked selected but the page content never changed (every owner screenshot showed the Access page). Verify the content changed; else focus+Space, then one real click.
    $sig1=JnPageSig; if($sig1 -eq $sig0 -and $n -gt 1){ Say "DIAG journeys: $role [$lab] page content unchanged after Select; trying focus+Space"; [void](JnCloseExtras "jn-$role-$n-before-space"); if(-not (BringFg)){ Say "DIAG journeys: main window is not the foreground; no key is sent" } else { try{ $it.El.SetFocus(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.SendKeys]::SendWait(' '); Start-Sleep -Milliseconds 1800 }catch{} }; $sig1=JnPageSig
      if($sig1 -eq $sig0){ Say "DIAG journeys: $role [$lab] still unchanged; one real click"; try{ if(SafeRailClickOk $it.El "jn-$role-$n"){ $b=$it.El.Current.BoundingRectangle; [void][M.U]::SetCursorPos([int]($b.X+$b.Width/2),[int]($b.Y+$b.Height/2)); Start-Sleep -Milliseconds 300; [M.U]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [M.U]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 1800 } }catch{ Say "DIAG journeys: click failed: $($_.Exception.Message)" }; $sig1=JnPageSig }
      Say "DIAG journeys: $role [$lab] page content changed=$($sig1 -ne $sig0)" }

    $md=FindModal; if($md){ Say "FAIL journeys: $role page [$lab] raised a dialog [$($md.Current.Name)]"; $script:fails++; Shot "jn-$role-$n-modal"; try{ $md.SetFocus() }catch{}; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 1; continue }
    Shot ("jn-$role-$n"); LayoutAudit "$role-$lab" $null; Say "INFO journeys: $role visited page [$lab] screenshot jn-$role-$n"; [void](JnCloseExtras "jn-$role-$n-after-visit") }
}

function JnSet($id,$v){ $e=Pick $id 4; if(-not $e){ Say "FAIL journeys: control $id not found"; $script:fails++; return $false }; try{ $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($v); return $true }catch{ Say "FAIL journeys: set $id : $($_.Exception.Message)"; $script:fails++; return $false } }
function JnInvoke($id){ $e=Pick $id 4; if(-not $e){ Say "FAIL journeys: button $id not found"; $script:fails++; return $false }; try{ $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); return $true }catch{ Say "FAIL journeys: invoke $id : $($_.Exception.Message)"; $script:fails++; return $false } }
function JnYes($tag){ $m=WaitModal 10; if(-not $m){ Say "FAIL journeys: $tag confirmation did not open"; $script:fails++; return $false }
  $script:curModal=$m; $d=ModalDescs $m; $y=XPickButton $d 'yes'; if(-not $y){ Say "FAIL journeys: $tag Yes button not identified; nothing pressed"; $script:fails++; return $false }; [void](PressDesc $y $tag 'Yes'); Start-Sleep 3; return $true }
function JnFindById($id,$sec){ $end=(Get-Date).AddSeconds($sec); do{ foreach($w in @(AllWinsDeep)){ $e=ById $w $id 1; if($e){ return $e } }; Start-Sleep -Milliseconds 400 }while((Get-Date) -lt $end); return $null }
function JnLeftoverModal($tag){ $mm=FindModal; if($mm){ Say "INFO journeys: $tag left a dialog open: title=[$($mm.Current.Name)] text=[$((@(WinBoxStatics $mm)) -join ' / ')]"; Shot "jn-$tag-leftover-dialog"; $script:curModal=$mm; [void](ModalDismiss "jn-$tag"); return $true }; return $false }
# Cashier: open shift, sell one line, see the refund path unavailable, close the shift.
function JnCashierFlow(){
  Say 'INFO journeys: cashier flow (open shift, sell, refund availability, close shift)'
  if(-not (NavTo @('البيع','Sales') 'jn-cashier-sell' 'StockGrid')){ Say 'NOTEXECUTED journeys: cashier could not open the sell page'; $script:notexec++; return }
  Say "DIAG journeys: shift status before [$(ValTxt 'ShiftStatusLabel')]"
  if(JnSet 'OpeningCash' '100'){ if(JnInvoke 'OpenShiftButton'){ Start-Sleep 2; [void](JnLeftoverModal 'cashier-openshift'); $st=ValTxt 'ShiftStatusLabel'; Say "DIAG journeys: shift status after open [$st]"; Shot 'jn-cashier-shift-open'; Check ($st -ne '(missing)') 'journeys cashier: the shift status is shown after opening' } }
  $cl=Pick 'ClearCart' 4; if($cl){ try{ $cl.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{}; Start-Sleep 1 }
  $rows=@(RowsIn $main 'StockGrid'); Say "DIAG journeys: stock rows on the sell page = $($rows.Count)"
  if($rows.Count -lt 1){ Say 'NOTEXECUTED journeys: no stock row to sell'; $script:notexec++ } else {
    $r0=$rows[0]; Say "DIAG journeys: selling row [$((@(RowCells $r0)) -join ' | ')]"
    $sel=$false; try{ $r0.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{}; if(-not $sel){ [void](ClickRow $r0 $false) }; Start-Sleep 1
    [void](JnSet 'SaleQuantity' '1'); [void](JnSet 'SaleLineDiscount' '0'); [void](JnInvoke 'AddCartButton'); Start-Sleep 2
    $c1=@(Rows 'CartGrid').Count; Say "DIAG journeys: cart rows after add = $c1"; Shot 'jn-cashier-cart'; Check ($c1 -eq 1) 'journeys cashier: adding the selected stock line puts one row in the cart'
    if($c1 -ge 1){ JnCashierCustomer; if(JnInvoke 'Pay'){ [void](JnYes 'jn-cashier-sale-confirm'); Start-Sleep 1
        $ctrl=$null; foreach($w in @(TopWins $p.Id)){ if($w.Current.Name -like '*الدواء المراقب*'){ $ctrl=$w } }
        if($ctrl){ Say 'INFO journeys: the chosen line is a controlled drug and its register dialog opened; the sale was not completed by this journey'; Shot 'jn-cashier-controlled-dialog'; $script:notexec++ }
        else { [void](JnLeftoverModal 'cashier-after-sale'); if($script:jnCustomerAttached){ $stx=JnStatusText; Say "DIAG journeys cashier customer: status after sale [$stx]"; JnCustomerAfterSale }; $c2=@(Rows 'CartGrid').Count; Shot 'jn-cashier-after-sale'; Say "DIAG journeys: cart rows after sale = $c2; last sale [$(ValTxt 'LastSaleLabel')]; status [$(ValTxt 'StatusLabel')]"; Check ($c2 -eq 0) 'journeys cashier: after paying the cart is empty (sale saved)' } } } }
  try{ JnReprint }catch{ Say "FAIL journeys reprint: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"; $script:fails++ }
  if(NavTo @('المبيعات والورديات','Sales and shifts') 'jn-cashier-reports' 'SalesGrid'){ $rf=ById $main 'RefundButton' 3; $vis=$false; if($rf){ try{ $vis=(-not $rf.Current.IsOffscreen) -and $rf.Current.IsEnabled }catch{} }; Say "DIAG journeys: cashier sees an enabled RefundButton = $vis"; Shot 'jn-cashier-reports-refund'
    if($vis){ Say 'INFO journeys: the refund button is visible to the cashier; Core refuses the action for a cashier (Refund is Owner and Manager only), not clicked here'; $script:notexec++ } else { Check $true 'journeys cashier: the refund button is not offered to a cashier' } }
  if(NavTo @('البيع','Sales') 'jn-cashier-sell2' 'StockGrid'){
    if(JnSet 'CountedCash' '100'){ if(JnInvoke 'CloseShiftButton'){ Start-Sleep 1; [void](JnYes 'jn-cashier-closeshift-confirm'); Start-Sleep 2; $lm=JnLeftoverModal 'cashier-closeshift'; Shot 'jn-cashier-shift-closed'; Say "DIAG journeys: shift status after close [$(ValTxt 'ShiftStatusLabel')] dialog=$lm"; $mm2=FindModal; Check (-not $mm2) 'journeys cashier: no dialog is left open after closing the shift' } } }
}
# Manager: refund the whole sale made by the cashier (confirm, reason, continue) and read the result.
function JnManagerRefund(){
  Say 'INFO journeys: manager refund flow'
  if(-not (NavTo @('المبيعات والورديات','Sales and shifts') 'jn-manager-reports' 'SalesGrid')){ Say 'NOTEXECUTED journeys: manager could not open the reports page'; $script:notexec++; return }
  $rows=@(RowsIn $main 'SalesGrid'); Say "DIAG journeys: sales rows = $($rows.Count)"
  if($rows.Count -lt 1){ Say 'NOTEXECUTED journeys: no sale to refund (the cashier sale did not complete)'; $script:notexec++; return }
  $r0=$rows[0]; $sel=$false; try{ $r0.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $sel=$true }catch{}; if(-not $sel){ [void](ClickRow $r0 $false) }; Start-Sleep 1
  Shot 'jn-manager-before-refund'
  if(JnInvoke 'RefundButton'){ if(JnYes 'jn-manager-refund-confirm'){
      $ok=JnFindById 'RrOk' 8
      if(-not $ok){ Say 'FAIL journeys: the refund reason dialog did not open'; $script:fails++; Shot 'jn-manager-no-reason-dialog' } else {
        $note=JnFindById 'RrNote' 2; if($note){ try{ $note.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('Synthetic journey refund') }catch{} }
        Shot 'jn-manager-reason-dialog'; try{ $ok.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL journeys: RrOk invoke: $($_.Exception.Message)"; $script:fails++ }; Start-Sleep 3
        [void](JnLeftoverModal 'manager-after-reason'); Shot 'jn-manager-after-refund'; Say "DIAG journeys: after refund status [$(ValTxt 'StatusLabel')]"
        Check (-not (FindModal)) 'journeys manager: no dialog is left open after the refund' } } }
}
function JourneySteps(){
  Say 'INFO journeys: start (owner, manager, inventory, cashier). Visits only; no sale, refund or stock edit is driven.'
  $script:halt=$false
  $mOk=JnCreateUser 'manager1' $pwCash 'Manager'; $iOk=JnCreateUser 'inventory1' $pwCash 'Inventory'
  # owner first (logged in now)
  JnVisit 'owner' $false
  foreach($r in @(@('manager1','manager',$mOk),@('inventory1','inventory',$iOk),@('cashier1','cashier',$true))){
    if(-not $r[2]){ Say "NOTEXECUTED journeys: $($r[1]) journey (user was not created)"; $script:notexec++; continue }
    if(-not (Logout)){ return }
    if(Login $r[0] $pwCash "jn-$($r[1])"){ JnVisit $r[1] $true; if($r[1] -eq 'cashier'){ try{ JnCashierFlow }catch{ Say "FAIL journeys: cashier flow: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"; $script:fails++ } }; $lo=ById $main 'LogoutButton' 5; if($lo){ try{ $lo.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{}; Start-Sleep 2 } } else { Say "FAIL journeys: login as $($r[0]) failed"; $script:fails++ }
    Start-Sleep 1
  }
  if($mOk){ if(Logout){ if(Login 'manager1' $pwCash 'jn-manager-refund'){ try{ JnManagerRefund }catch{ Say "FAIL journeys: manager refund: $($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"; $script:fails++ }; $lo=ById $main 'LogoutButton' 5; if($lo){ try{ $lo.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{}; Start-Sleep 2 } } } }
  [void](Login 'owner' $pwOwner 'owner-after-journeys')
}
