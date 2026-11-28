# l208: the "Ask the program" screen (fixed questions, no model). Owner pass. Optional: nothing here Halts the run.
function AskText($w,$id){ $e=ById $w $id 3; if($e){ return [string]$e.Current.Name } else { return '' } }
function AskHeaders($w){ $g=ById $w 'AskGrid' 3; if(-not $g){ return @() }; try{ return @($g.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::HeaderItem))) | ForEach-Object { [string]$_.Current.Name } | Where-Object { $_ }) }catch{ return @() } }
function AskOne($w,$q,$expect,$shot){
  $in=ById $w 'AskInput' 4; if(-not $in){ Say "NOTEXECUTED ask: input not found for [$q]"; $script:notexec++; return }
  try{ $in.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($q) }catch{ Say "NOTEXECUTED ask: could not type [$q]: $($_.Exception.Message)"; $script:notexec++; return }
  $go=ById $w 'AskGo' 4; if(-not $go){ Say 'NOTEXECUTED ask: AskGo not found'; $script:notexec++; return }
  try{ $go.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "NOTEXECUTED ask: AskGo invoke failed: $($_.Exception.Message)"; $script:notexec++; return }
  Start-Sleep -Milliseconds 1200
  $n=AskText $w 'AskNote'; $hd=@(AskHeaders $w); $rows=@(RowsIn $w 'AskGrid'); $rc=$(if($rows){ @($rows).Count }else{ 0 })
  Say "DIAG ask: q=[$q] note=[$($n -replace '\s+',' ')] headers=[$($hd -join ' | ')] rows=$rc"
  Check ($n -like "*$expect*") "ask: [$q] shows [$expect]"
  $latin=@($hd | Where-Object { $_ -match '^[A-Za-z][A-Za-z ]*$' })
  Check ($latin.Count -eq 0) "ask: [$q] has no English-only column header ([$($latin -join ',')])"
  Shot $shot
}
function AskSteps(){
  Say 'INFO ask: optional step list starts (l208)'
  if(-not (NavTo @('أدوات البيع','Sales tools') 'ask-nav' 'AskButton')){ Say 'NOTEXECUTED ask: could not open the page that holds the Ask button'; $script:notexec++; return }
  $b=Pick 'AskButton' 5; if(-not $b){ Say 'NOTEXECUTED ask: AskButton not found'; $script:notexec++; return }
  try{ $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL ask: invoke AskButton: $($_.Exception.Message)"; $script:fails++; return }
  Start-Sleep 2; $w=WinByTitle 'اسأل البرنامج (أسئلة جاهزة، للقراءة فقط)' 10
  if(-not $w){ Say 'FAIL ask: the Ask window did not open'; $script:fails++; return }
  Check ($true) 'ask: the window opens'; Shot 'ask-0-open'
  AskOne $w 'مبيعات اليوم' 'ملخص المبيعات' 'ask-1-sales-today'
  AskOne $w 'النواقص' 'النواقص' 'ask-2-low-stock'
  AskOne $w 'محتاج اطلب ايه' 'اقتراح إعادة الطلب' 'ask-3-reorder'
  AskOne $w 'ينتهي خلال 30 يوم' 'ينتهي خلال عدد أيام' 'ask-4-expiring'
  AskOne $w 'مبيعات الكاشير اليوم' 'مبيعات كل كاشير' 'ask-5-cashier'
  AskOne $w 'نقدي ولا اجل النهارده' 'نقدي وآجل' 'ask-6-payment'
  AskOne $w 'ربح كل صنف هذا الشهر' 'الربح لكل صنف' 'ask-7-profit'
  AskOne $w 'مبيعت اليوم' 'هل تقصد' 'ask-8-did-you-mean'
  AskOne $w 'مبيعات الكاشير' 'أي فترة' 'ask-9-needs-period'
  # close: Escape is not sent (no blind keys); use the window pattern
  try{ $w.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close() }catch{ Say "INFO ask: window close failed: $($_.Exception.Message)" }
  Check (WinGone 'اسأل البرنامج (أسئلة جاهزة، للقراءة فقط)' 8) 'ask: the window closes'
}
