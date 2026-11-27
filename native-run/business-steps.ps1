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
function BusinessSteps(){
  Say 'INFO business: optional step list starts (l161)'
  if(-not (NavTo @('الأصناف والمشتريات','Products & Purchasing') 'biz-inv' 'InvSearchBox')){ Say 'NOTEXECUTED business: could not open the Products page'; $script:notexec++; return }
  $w=BizOpen 'BusinessToolsButton' 'أدوات الأعمال'; if(-not $w){ return }
  Check ($true) 'business: the Business tools window opens'; Shot 'biz-1-open'
  $tc=@($w.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)))).Count
  Say "DIAG business: tab count [$tc]"; Check ($tc -eq 11) 'business: eleven tabs are present'
  foreach($t in @('الصلاحية والتخفيض','طلبات الشراء','تتبع التشغيلة','أسعار الموردين','تحويل مخزون','التفاعلات الدوائية','تقارير','مفاتيح سريعة','صحة النسخ الاحتياطي','صلاحيات الأدوار','فحص النظام والبيانات')){
    $ok=BizSelectTab $w $t; Check $ok "business: tab [$t] can be selected"; if($ok){ Shot ('biz-tab-'+($t -replace '\s','_')) } }
  # backup health: the status text must be one of the six statuses, an honest read of the folder
  if(BizSelectTab $w 'صحة النسخ الاحتياطي'){ $st=ById $w 'BtBackupStatus' 3; if($st){ $s=[string]$st.Current.Name; Say "DIAG business: backup health text [$s]"; Check ($s.Length -gt 0) 'business: the backup health tab shows a status' } else { Say 'NOTEXECUTED business: BtBackupStatus not found'; $script:notexec++ } }
    # system check tab: run it and read the grid is NOT driven in this list (shown only)
  # quick key: set slot 1 to the first product is NOT driven (needs a product pick); the editor is only shown
  Say 'NOTEXECUTED business: quick key set/clear, interaction save, VAT save, transfer note, CSV exports are not driven (they write data or open file dialogs); only the screens are shown'; $script:notexec++
  Shot 'biz-2-after'; BizCloseWin $w 'أدوات الأعمال'
  # sales screen strip: the three buttons and the customer window
  if(-not (NavTo @('المبيعات','Sales') 'biz-sales' 'SaleCustomerButton')){ Say 'NOTEXECUTED business: could not open the Sales page'; $script:notexec++; return }
  foreach($id in @('SaleCustomerButton','QuickKeysButton','ReprintButton')){ $e=Pick $id 4; Check ($e -ne $null) "business: sales strip button $id is present" }
  Shot 'biz-3-sales-strip'
  $cw=BizOpen 'SaleCustomerButton' 'عميل للبيع'
  if($cw){ Check ($true) 'business: the customer-for-sale window opens'; Shot 'biz-4-customer'; BizCloseWin $cw 'عميل للبيع' }
  $qw=BizOpen 'QuickKeysButton' 'مفاتيح سريعة'
  if($qw){ Check ($true) 'business: the quick keys window opens'; Shot 'biz-5-quickkeys'; BizCloseWin $qw 'مفاتيح سريعة' }
  Say 'NOTEXECUTED business: refund reason dialog, QR in Operations, interaction prompt at sale, reprint text window are not driven in this list'; $script:notexec++
}
