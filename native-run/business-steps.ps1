# l161 OPTIONAL step list for the Business tools window, quick keys window, customer-for-sale window and reprint. Dot-sourced by trial-l118-fresh.ps1 only when env OFAG_BUSINESS=1. Uses the driver helpers (Say, Check, NavTo, Pick, ById, WinByTitle, WinGone, Shot). Never runs unless opted in; every step that cannot run says NOTEXECUTED. Written offline, NEVER executed natively: ids come from the source (BusinessToolsWindow.cs, CustomerSaleWindow.cs, QuickKeysWindow.cs), not from observed UIA output, so a missing id is reported as NOTEXECUTED/FAIL for the reader, not assumed.
function BizOpen($btnId,$title){
  $b=Pick $btnId 5; if(-not $b){ Say "NOTEXECUTED business: $btnId not found"; $script:notexec++; return $null }
  try{ $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL business: invoke $btnId : $($_.Exception.Message)"; $script:fails++; return $null }
  Start-Sleep 2; $w=WinByTitle $title 10
  if(-not $w){ Say "FAIL business: window [$title] did not open"; $script:fails++; return $null }
  return $w
}
function BizCloseWin($w,$title){ try{ $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{ Say "INFO business: close failed: $($_.Exception.Message)" }; Check (WinGone $title 8) "business: [$title] closes" }
function BizSelectTab($w,$text){
  $c=New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)
  $tabs=@($w.FindAll($TS::Descendants,$c)); foreach($t in $tabs){ if([string]$t.Current.Name -eq $text){ try{ $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select(); Start-Sleep -Milliseconds 900; return $true }catch{ return $false } } }
  Say "DIAG business: tab [$text] not found among $($tabs.Count) tabs"; return $false
}
# NavOpt: navigate WITHOUT the driver's Halt on a missing rail item. Counts the rail items matching the labels first (read only); if there is not exactly one, report NOTEXECUTED and return $false, so one missing optional page cannot stop the rest of the run (run 46013506963 halted every later block after one wrong label).
function BizNavOpt($labels,$tag,$pageId){
  try{ $r=@(RailDiag "$tag-pre"); $idx=@(RailMatch @($r | ForEach-Object { $_.Label }) $labels) }catch{ Say "NOTEXECUTED business: rail could not be read for $tag : $($_.Exception.Message)"; $script:notexec++; return $false }
  if($idx.Count -ne 1){ Say "NOTEXECUTED business: $tag rail item with label in [$($labels -join ',')] found $($idx.Count) (need 1); this step list is skipped, the run continues"; $script:notexec++; return $false }
  return (NavTo $labels $tag $pageId) }
# l166: layout audit. Reads UIA BoundingRectangle of key interactive controls that are on screen and flags (a) two controls whose rectangles overlap by more than 3 px in both directions (a control that sits inside a ComboBox or DataGrid is ignored), (b) a control that extends past the window rectangle, (c) a button or edit smaller than 20 px high or 24 px wide. UIA rectangles are not pixel proof: a flag means "look at the screenshot", no flag does not prove the layout is clean (text clipping inside a control is not detected).
function LayoutAudit($label,$root){
  try{
    if(-not $root){ $root=$main }
    $wr=$root.Current.BoundingRectangle
    $types=@([System.Windows.Automation.ControlType]::Button,[System.Windows.Automation.ControlType]::Edit,[System.Windows.Automation.ControlType]::ComboBox,[System.Windows.Automation.ControlType]::DataGrid,[System.Windows.Automation.ControlType]::RadioButton,[System.Windows.Automation.ControlType]::CheckBox,[System.Windows.Automation.ControlType]::Expander)
    $or=New-Object System.Windows.Automation.OrCondition(@($types | ForEach-Object { New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,$_) }))
    $cond=New-Object System.Windows.Automation.AndCondition($or,(New-Object System.Windows.Automation.PropertyCondition($AE::IsOffscreenProperty,$false)))
    $els=@($root.FindAll($TS::Descendants,$cond)); $items=@()
    foreach($e in $els){ try{ $c=$e.Current; $r=$c.BoundingRectangle; if($r.IsEmpty -or $r.Width -lt 1 -or $r.Height -lt 1 -or [double]::IsInfinity($r.Width)){ continue }
      $nm=[string]$c.AutomationId; if(-not $nm){ $nm=[string]$c.Name }; if(-not $nm){ continue }
      if($nm -match '^(Line |Page |Scroll|Minimize|Maximize|Close$|Restore|System)'){ continue }
      $items+=[pscustomobject]@{N=$nm;T=$c.ControlType.ProgrammaticName;R=$r} }catch{} }
    $flags=0; $n=$items.Count
    for($i=0;$i -lt $n;$i++){ $a=$items[$i]
      if($a.R.Left -lt $wr.Left-2 -or $a.R.Right -gt $wr.Right+2 -or $a.R.Top -lt $wr.Top-2 -or $a.R.Bottom -gt $wr.Bottom+2){ Say "LAYOUT-FLAG [$label] OUTSIDE-WINDOW $($a.N) rect=$([int]$a.R.Left),$([int]$a.R.Top),$([int]$a.R.Right),$([int]$a.R.Bottom) window=$([int]$wr.Left),$([int]$wr.Top),$([int]$wr.Right),$([int]$wr.Bottom)"; $flags++ }
      if(($a.T -match 'Button|Edit') -and ($a.R.Height -lt 20 -or $a.R.Width -lt 24)){ Say "LAYOUT-FLAG [$label] TINY $($a.N) size=$([int]$a.R.Width)x$([int]$a.R.Height)"; $flags++ }
      for($j=$i+1;$j -lt $n;$j++){ $b=$items[$j]
        $w=[Math]::Min($a.R.Right,$b.R.Right)-[Math]::Max($a.R.Left,$b.R.Left); $h=[Math]::Min($a.R.Bottom,$b.R.Bottom)-[Math]::Max($a.R.Top,$b.R.Top)
        if($w -gt 3 -and $h -gt 3){
          if(($a.T -match 'ComboBox|DataGrid|Expander') -or ($b.T -match 'ComboBox|DataGrid|Expander')){ continue }
          Say "LAYOUT-FLAG [$label] OVERLAP $($a.N) x $($b.N) overlap=$([int]$w)x$([int]$h) a=$([int]$a.R.Left),$([int]$a.R.Top),$([int]$a.R.Right),$([int]$a.R.Bottom) b=$([int]$b.R.Left),$([int]$b.R.Top),$([int]$b.R.Right),$([int]$b.R.Bottom)"; $flags++ } } }
    Say "DIAG layout [$label]: $n controls read, $flags flags"
    Check ($flags -eq 0) "layout audit [$label]: no overlapping, clipped or tiny key controls by UIA rectangles (UIA is not pixel proof)"
  }catch{ Say "NOTEXECUTED layout audit [$label]: $($_.Exception.Message)"; $script:notexec++ }
}
function BusinessSteps(){
  Say 'INFO business: optional step list starts (l161)'
  if(-not (BizNavOpt @('الأصناف والمشتريات','Products & Purchasing') 'biz-inv' 'InvSearchBox')){ Say 'NOTEXECUTED business: could not open the Products page'; $script:notexec++; return }
  LayoutAudit 'inventory-default' $null; Shot 'layout-inventory-default'
  try{ $tg=Pick 'InvPanelToggleButton' 3; if($tg){ $tg.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 800; Shot 'layout-inventory-side-open'; LayoutAudit 'inventory-side-open' $null; $tg.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 500 } else { Say 'NOTEXECUTED layout: side panel toggle not found'; $script:notexec++ } }catch{ Say "NOTEXECUTED layout: side panel toggle failed: $($_.Exception.Message)"; $script:notexec++ }
  $w=BizOpen 'BusinessToolsButton' 'أدوات الأعمال'; if(-not $w){ return }
  Check ($true) 'business: the Business tools window opens'; Shot 'biz-1-open'; LayoutAudit 'business-tools' $w
  $tc=@($w.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)))).Count
  Say "DIAG business: tab count [$tc]"; Check ($tc -eq 12) 'business: twelve tabs are present'
  foreach($t in @('الصلاحية والتخفيض','طلبات الشراء','تتبع التشغيلة','أسعار الموردين','تحويل مخزون','التفاعلات الدوائية','تقارير','مفاتيح سريعة','صحة النسخ الاحتياطي','صلاحيات الأدوار','فحص النظام والبيانات','تقارير المشتريات والمخزون')){
    $ok=BizSelectTab $w $t; Check $ok "business: tab [$t] can be selected"; if($ok){ Shot ('biz-tab-'+($t -replace '\s','_')) } }
  if(BizSelectTab $w 'صلاحيات الأدوار'){ foreach($rid in @('BtRoleSelect','BtRoleTemplate','BtRoleAreas')){ $re=ById $w $rid 3; Check ($re -ne $null) "business: roles editor control $rid is present" } }
  # backup health: the status text must be one of the six statuses, an honest read of the folder
  if(BizSelectTab $w 'صحة النسخ الاحتياطي'){ $st=ById $w 'BtBackupStatus' 3; if($st){ $s=[string]$st.Current.Name; Say "DIAG business: backup health text [$s]"; Check ($s.Length -gt 0) 'business: the backup health tab shows a status' } else { Say 'NOTEXECUTED business: BtBackupStatus not found'; $script:notexec++ } }
    # system check tab: run it and read the grid is NOT driven in this list (shown only)
  # quick key: set slot 1 to the first product is NOT driven (needs a product pick); the editor is only shown
  Say 'NOTEXECUTED business: quick key set/clear, interaction save, VAT save, transfer note, CSV exports are not driven (they write data or open file dialogs); only the screens are shown'; $script:notexec++
  Shot 'biz-2-after'; BizCloseWin $w 'أدوات الأعمال'
  # sales screen strip (rail label is 'البيع', page element StockGrid; 'المبيعات والورديات' is the Reports page, not this one): the three buttons and the customer window
  if(-not (BizNavOpt @('البيع','Sales') 'biz-sales' 'StockGrid')){ Say 'NOTEXECUTED business: could not open the Sales page'; $script:notexec++; return }
  LayoutAudit 'sales' $null; Shot 'layout-sales'
  foreach($id in @('SaleCustomerButton','QuickKeysButton','ReprintButton')){ $e=Pick $id 4; Check ($e -ne $null) "business: sales strip button $id is present" }
  Shot 'biz-3-sales-strip'
  $cw=BizOpen 'SaleCustomerButton' 'عميل للبيع'
  if($cw){ Check ($true) 'business: the customer-for-sale window opens'; Shot 'biz-4-customer'; BizCloseWin $cw 'عميل للبيع' }
  $qw=BizOpen 'QuickKeysButton' 'مفاتيح سريعة'
  if($qw){ Check ($true) 'business: the quick keys window opens'; Shot 'biz-5-quickkeys'; BizCloseWin $qw 'مفاتيح سريعة' }
  Say 'NOTEXECUTED business: refund reason dialog, QR in Operations, interaction prompt at sale, reprint text window are not driven in this list'; $script:notexec++
}
