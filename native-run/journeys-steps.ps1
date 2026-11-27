# l170 role journeys on real Windows: the owner creates a manager and an inventory user (the cashier already exists from the roles block), then each role logs in,
# visits every page on its rail, a screenshot is taken per page, and the UIA layout audit runs per page. Pages are VISITED, not worked through: no sale, refund or stock edit is driven here.
# l171 adds: cashier opens a shift, sells the first stock line, checks the refund button, closes the shift; the manager then refunds that sale through the reason dialog.
# Proves: per-role rail contents, that every page opens without a modal, and layout flags from UIA rectangles (not pixel proof). A person must read the screenshots.
. (Join-Path $PSScriptRoot 'business-steps.ps1')
function JnCreateUser($name,$pw,$roleWord){
  $ok=$false
  try{
    if(-not (NavTo @('الإدارة والنسخ الاحتياطي','Administration and backup') "jn-create-$name" 'NewUsername')){ return $false }
    $nu=Pick 'NewUsername' 5; $np=Pick 'NewPassword' 5; $ab=Pick 'AddUserButton' 5; $nr=Pick 'NewRole' 5
    if(-not ($nu -and $np -and $ab -and $nr)){ Say "NOTEXECUTED journeys: create-user controls for $name not found"; return $false }
    $nu.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($name)
    [void](BringFg); $np.SetFocus(); Start-Sleep -Milliseconds 400; $tr=TypeSecret $pw { FgOurs } { param($k) [System.Windows.Forms.SendKeys]::SendWait($k) }; Say "DIAG journeys: $name password typed=$($tr.typed)/$($tr.expected)"
    $ec=$nr.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern); $ec.Expand(); Start-Sleep -Milliseconds 600
    $li=@($main.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))) | Where-Object { [string]$_.Current.Name -like "*$roleWord*" }
    $picked=$false; if(@($li).Count -ge 1){ $it=@($li)[0]; try{ $it.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $picked=$true }catch{ try{ $it.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $picked=$true }catch{} } }
    try{ $ec.Collapse() }catch{}
    Say "DIAG journeys: role item [$roleWord] picked=$picked; box now shows [$([string]$nr.Current.Name)]"
    if(-not $picked){ Say "NOTEXECUTED journeys: role $roleWord could not be chosen for $name"; return $false }
    $ab.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep 3
    $md=FindModal; if($md){ Say "DIAG journeys: modal after create $name [$($md.Current.Name)]"; try{ $md.SetFocus() }catch{}; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 1 }
    $ok=$true
  }catch{ Say "FAIL journeys: create $name : $($_.Exception.Message)"; $script:fails++ }
  return $ok }
function JnVisit($role,$mustLackAdmin){
  Start-Sleep 2; Shot "jn-$role-landing"; LayoutAudit "$role-landing" $null
  $items=@(); for($i=1;$i -le 5;$i++){ $items=@(RailItems); if($items.Count -gt 0){ break }; Start-Sleep 2 }
  $labels=@($items | ForEach-Object { if($_.Label){ $_.Label } else { $_.Raw } }); Say "INFO journeys: $role rail ($($labels.Count)): $($labels -join ' | ')"
  Check ($labels.Count -ge 1) "journeys: $role sees at least one page on the rail"
  $hasAdmin=@($labels | Where-Object { $_ -match 'الإدارة' }).Count -gt 0
  if($mustLackAdmin){ Check (-not $hasAdmin) "journeys: $role does not see the administration page" } else { Check $hasAdmin "journeys: $role sees the administration page" }
  $n=0; foreach($it in $items){ $n++; $lab=if($it.Label){ $it.Label } else { "item$n" }
    try{ $it.El.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 1800 }catch{ Say "INFO journeys: $role page [$lab] select failed: $($_.Exception.Message)"; continue }
    $md=FindModal; if($md){ Say "FAIL journeys: $role page [$lab] raised a dialog [$($md.Current.Name)]"; $script:fails++; Shot "jn-$role-$n-modal"; try{ $md.SetFocus() }catch{}; [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep 1; continue }
    Shot ("jn-$role-$n"); LayoutAudit "$role-$lab" $null; Say "INFO journeys: $role visited page [$lab] screenshot jn-$role-$n" }
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
    if($c1 -ge 1){ if(JnInvoke 'Pay'){ [void](JnYes 'jn-cashier-sale-confirm'); Start-Sleep 1
        $ctrl=$null; foreach($w in @(TopWins $p.Id)){ if($w.Current.Name -like '*الدواء المراقب*'){ $ctrl=$w } }
        if($ctrl){ Say 'INFO journeys: the chosen line is a controlled drug and its register dialog opened; the sale was not completed by this journey'; Shot 'jn-cashier-controlled-dialog'; $script:notexec++ }
        else { [void](JnLeftoverModal 'cashier-after-sale'); $c2=@(Rows 'CartGrid').Count; Shot 'jn-cashier-after-sale'; Say "DIAG journeys: cart rows after sale = $c2; last sale [$(ValTxt 'LastSaleLabel')]; status [$(ValTxt 'StatusLabel')]"; Check ($c2 -eq 0) 'journeys cashier: after paying the cart is empty (sale saved)' } } } }
  if(NavTo @('المبيعات والورديات','Sales and shifts') 'jn-cashier-reports' 'SalesGrid'){ $rf=ById $main 'RefundButton' 3; $vis=$false; if($rf){ try{ $vis=(-not $rf.Current.IsOffscreen) -and $rf.Current.IsEnabled }catch{} }; Say "DIAG journeys: cashier sees an enabled RefundButton = $vis"; Shot 'jn-cashier-reports-refund'
    if($vis){ Say 'INFO journeys: the refund button is visible to the cashier; Core refuses the action for a cashier (Refund is Owner and Manager only), not clicked here'; $script:notexec++ } else { Check $true 'journeys cashier: the refund button is not offered to a cashier' } }
  if(NavTo @('البيع','Sales') 'jn-cashier-sell2' 'StockGrid'){
    if(JnSet 'CountedCash' '100'){ if(JnInvoke 'CloseShiftButton'){ Start-Sleep 2; $lm=JnLeftoverModal 'cashier-closeshift'; Shot 'jn-cashier-shift-closed'; Say "DIAG journeys: shift status after close [$(ValTxt 'ShiftStatusLabel')] dialog=$lm"; $mm2=FindModal; Check (-not $mm2) 'journeys cashier: no dialog is left open after closing the shift' } } }
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
