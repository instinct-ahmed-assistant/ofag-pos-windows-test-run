# l150 OPTIONAL step list for the loyalty window. Dot-sourced by trial-l118-fresh.ps1 only when env OFAG_LOYALTY=1 and the candidate is l150 or later. Uses the driver's helpers (Say, Check, NavTo, Pick, ById, WinByTitle, WinGone, Shot). Every step that cannot run is NOTEXECUTED, never a silent pass. SYNTHETIC data only.
function LoyVal($w,$id,$text){ $e=ById $w $id 4; if(-not $e){ return $false }; try{ $e.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($text); return $true }catch{ Say "INFO loyalty: set $id failed: $($_.Exception.Message)"; return $false } }
function LoyClick($w,$id){ $e=ById $w $id 4; if(-not $e){ return $false }; try{ $e.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 900; return $true }catch{ Say "INFO loyalty: invoke $id failed: $($_.Exception.Message)"; return $false } }
function LoyText($w,$id){ $e=ById $w $id 3; if($e){ return [string]$e.Current.Name } else { return '(missing)' } }
function LoyaltySteps(){
  Say 'INFO loyalty: optional step list starts (l150)'
  if(-not (NavTo @('الأصناف والمشتريات','Products & Purchasing') 'loyalty-inv' 'InvSearchBox')){ Say 'NOTEXECUTED loyalty: could not open the Products page'; $script:notexec++; return }
  $btn=Pick 'LoyaltyButton' 5; if(-not $btn){ Say 'NOTEXECUTED loyalty: LoyaltyButton not found'; $script:notexec++; return }
  try{ $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL loyalty: invoke LoyaltyButton: $($_.Exception.Message)"; $script:fails++; return }
  Start-Sleep 2; $w=WinByTitle 'نقاط الولاء' 10
  if(-not $w){ Say 'FAIL loyalty: the loyalty window did not open'; $script:fails++; return }
  Check ($true) 'loyalty: the window opens'; Shot 'loy-1-open'
  $st0=LoyText $w 'LoyStatus'; Say "DIAG loyalty status at open: [$st0]"; Check ($st0 -like '*متوقفة*' -or $st0 -like '*مفعلة*') 'loyalty: the status line tells whether points are on or off'
  # owner config
  $en=ById $w 'LoyEnabled' 4; $ok1=$false
  if($en){ try{ $tg=$en.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern); if($tg.Current.ToggleState -ne [System.Windows.Automation.ToggleState]::On){ $tg.Toggle() }; $ok1=$true }catch{ Say "INFO loyalty: toggle failed: $($_.Exception.Message)" } }
  $ok2=(LoyVal $w 'LoyEarn' '10') -and (LoyVal $w 'LoyValue' '10')
  if($ok1 -and $ok2 -and (LoyClick $w 'LoyConfigSave')){ $st1=LoyText $w 'LoyStatus'; Say "DIAG loyalty status after save: [$st1] message=[$(LoyText $w 'LoyMessage')]"; Check ($st1 -like '*مفعلة*10*') 'loyalty: owner turns points on at 10 per 100.00 and the status shows it' } else { Say 'NOTEXECUTED loyalty: owner config controls not all reachable'; $script:notexec++ }
  # customer
  $cb=ById $w 'LoyCustomer' 4; $picked=$false
  if($cb){ try{ $ec=$cb.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern); $ec.Expand(); Start-Sleep -Milliseconds 700
      $li=@($w.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)))); Say "DIAG loyalty customer list items: $($li.Count)"
      if($li.Count -ge 1){ $it=$li[0]; Say "DIAG loyalty first item name=[$($it.Current.Name)] class=[$($it.Current.ClassName)]"
        try{ $it.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); $picked=$true }catch{ Say "INFO loyalty: SelectionItem unsupported on the item" }
        if(-not $picked){ try{ $it.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $picked=$true }catch{ Say "INFO loyalty: Invoke unsupported on the item" } }
        if(-not $picked){ try{ $r=$it.Current.BoundingRectangle; if($r.Width -gt 2 -and $r.Height -gt 2){ [void][M.U]::SetCursorPos([int]($r.X+$r.Width/2),[int]($r.Y+$r.Height/2)); Start-Sleep -Milliseconds 300; [M.U]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 80; [M.U]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 600; $picked=$true; Say 'INFO loyalty: item chosen by a mouse click' } }catch{ Say "INFO loyalty: mouse click failed: $($_.Exception.Message)" } } }; try{ $ec.Collapse() }catch{} }catch{ Say "INFO loyalty: customer pick failed: $($_.Exception.Message)" } }
  if((-not $picked) -and $cb){ try{ $cb.SetFocus(); Start-Sleep -Milliseconds 300; [System.Windows.Forms.SendKeys]::SendWait('{DOWN}'); Start-Sleep -Milliseconds 800; $sv=''; try{ $sv=[string]$cb.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ $sv=[string]$cb.Current.Name }; Say "DIAG loyalty: keyboard pick left the customer box showing [$sv]"; if($sv -and $sv -notlike '*DataRowView*'){ $picked=$true } }catch{ Say "INFO loyalty: keyboard pick failed: $($_.Exception.Message)" } }
  if(-not $picked){ Say 'NOTEXECUTED loyalty: no customer could be chosen (the synthetic database may have none); award and redeem steps skipped'; $script:notexec++ }
  else {
    Start-Sleep -Milliseconds 800; $b0=LoyText $w 'LoyBalance'; Say "DIAG loyalty balance after choosing a customer: [$b0]"; Check ($b0 -like '*الرصيد*') 'loyalty: choosing a customer shows the balance'
    $aw=ById $w 'LoyAwardLast' 3
    if($aw -and $aw.Current.IsEnabled){ [void](LoyClick $w 'LoyAwardLast'); $m1=LoyText $w 'LoyMessage'; $b1=LoyText $w 'LoyBalance'; Say "DIAG loyalty award message=[$m1] balance=[$b1]"; Check ($m1 -like '*نقطة*' -or $m1 -like '*لا نقاط جديدة*') 'loyalty: awarding for the last sale answers with points or "nothing new"' }
    elseif($env:OFAG_JOURNEYS -eq '1' ){ Say 'INFO loyalty: award button disabled in the owner pass (no sale in this instance); the cashier journey attaches a customer to a sale and reads the points message instead (JnCashierCustomer)' }
    else { Say 'NOTEXECUTED loyalty: award button disabled (no sale was made in this program instance, or the journey sale was a controlled drug)'; $script:notexec++ }
    [void](LoyVal $w 'LoyRedeemPoints' '1'); [void](LoyClick $w 'LoyRedeem'); $m2=LoyText $w 'LoyMessage'; Say "DIAG loyalty redeem message=[$m2] balance=[$(LoyText $w 'LoyBalance')]"
    Check ($m2 -like '*اسمح للعميل بخصم*' -or $m2 -like '*لا يكفي*') 'loyalty: redeeming one point gives the discount amount, or says the balance is not enough'
  }
  Shot 'loy-2-after'; [void](LoyClick $w 'LoyClose'); Check (WinGone 'نقاط الولاء' 8) 'loyalty: the window closes'
}
