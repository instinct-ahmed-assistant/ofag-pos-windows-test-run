function GlyphPixels($el,$label){ try{ $r=$el.Current.BoundingRectangle; $w=[int]$r.Width; $h=[int]$r.Height; if($w -lt 20 -or $h -lt 12){ Say "NOTEXECUTED $label pixel check: empty rectangle"; $script:notexec++; return }; $bmp=New-Object System.Drawing.Bitmap $w,$h; $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen([int]$r.X,[int]$r.Y,0,0,$bmp.Size); $g.Dispose(); $dark=0; $rows=@{}; for($y=4;$y -lt ($h-4);$y++){ for($x=4;$x -lt ($w-4);$x++){ $c=$bmp.GetPixel($x,$y); if(($c.R+$c.G+$c.B) -lt 330){ $dark++; $rows[$y]=1 } } }; $bmp.Dispose(); Say "DIAG $label glyph pixels dark=$dark rowspan=$($rows.Count) box=${w}x${h}"; Check (($dark -ge 40) -and ($rows.Count -ge 9)) "$label shows readable digit glyphs in the pixels (not a clipped strip)" }catch{ Say "WARN $label pixel check failed: $($_.Exception.Message)" } }
# l161 OPTIONAL step list for the Business tools window, quick keys window, customer-for-sale window and reprint. Dot-sourced by trial-l118-fresh.ps1 only when env OFAG_BUSINESS=1. Uses the driver helpers (Say, Check, NavTo, Pick, ById, WinByTitle, WinGone, Shot). Never runs unless opted in; every step that cannot run says NOTEXECUTED. Written offline, NEVER executed natively: ids come from the source (BusinessToolsWindow.cs, CustomerSaleWindow.cs, QuickKeysWindow.cs), not from observed UIA output, so a missing id is reported as NOTEXECUTED/FAIL for the reader, not assumed.
function BizOpen($btnId,$title){
  $b=Pick $btnId 5; if(-not $b){ Say "NOTEXECUTED business: $btnId not found"; $script:notexec++; return $null }
  try{ $b.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }catch{ Say "FAIL business: invoke $btnId : $($_.Exception.Message)"; $script:fails++; return $null }
  Start-Sleep 2; $w=WinByTitle $title 10
  if(-not $w){ $wn=@(); foreach($x in @(AllWinsDeep)){ try{ $wn+="[$($x.Current.Name)|$($x.Current.ClassName)|$([int]$x.Current.BoundingRectangle.X),$([int]$x.Current.BoundingRectangle.Y),$([int]$x.Current.BoundingRectangle.Width)x$([int]$x.Current.BoundingRectangle.Height)]" }catch{} }; Say "DIAG business: windows now: $($wn -join ' ')"; Shot "dlg-business-$btnId-not-open"; Say "FAIL business: window [$title] did not open"; $script:fails++; return $null }
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
      if($nm -match '^(PageUp|PageDown|PageLeft|PageRight|LineUp|LineDown|LineLeft|LineRight|Line |Page |Scroll|Minimize|Maximize|Close$|Restore|System)'){ continue }
      # l185 (POLICY CHANGE, disclosed): an element that lies partly outside the viewport of a scroll viewer that itself fits inside the window is scrollable content, not overflow; an element inside a COLLAPSED expander is not on screen. Both are skipped now. A scroller that itself extends past the window is still flagged.
      # l172: an element inside a scrolling area whose centre lies outside that area's visible viewport is clipped, not overlapping (UIA still reports its virtual rectangle); skip it
      $clipped=$false; try{ $wk=[System.Windows.Automation.TreeWalker]::ControlViewWalker; $pa=$wk.GetParent($e); $hop=0; while($pa -and $hop -lt 25){ $sp=$null; try{ $sp=$pa.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern) }catch{}; if($sp){ $pr=$pa.Current.BoundingRectangle; if(-not $pr.IsEmpty){ $cx=$r.Left+$r.Width/2; $cy=$r.Top+$r.Height/2; if($cx -lt $pr.Left -or $cx -gt $pr.Right -or $cy -lt $pr.Top -or $cy -gt $pr.Bottom){ $clipped=$true; break }; if(($r.Bottom -gt $pr.Bottom+2 -or $r.Top -lt $pr.Top-2 -or $r.Right -gt $pr.Right+2 -or $r.Left -lt $pr.Left-2) -and $pr.Left -ge $wr.Left-2 -and $pr.Right -le $wr.Right+2 -and $pr.Bottom -le $wr.Bottom+2 -and $pr.Top -ge $wr.Top-2){ $clipped=$true; break } } } else { $ec=$null; try{ $ec=$pa.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern) }catch{}; if($ec -and $ec.Current.ExpandCollapseState -eq [System.Windows.Automation.ExpandCollapseState]::Collapsed -and $pa.Current.AutomationId -ne $e.Current.AutomationId){ $clipped=$true; break } }; $pa=$wk.GetParent($pa); $hop++ } }catch{}
      if($clipped){ continue }
      # l180: remember which top-level window owns the element; owned windows are listed under the main window by UIA, so l179 compared controls of different windows (PlanEnd of the main window x a button of the Procurement window) and reported false overlaps
      $wh=0; $wrq=$null; try{ $wk2=[System.Windows.Automation.TreeWalker]::ControlViewWalker; $q=$wk2.GetParent($e); $hp=0; while($q -and $hp -lt 40){ if($q.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window){ $wh=[int]$q.Current.NativeWindowHandle; $wrq=$q.Current.BoundingRectangle; break }; $q=$wk2.GetParent($q); $hp++ } }catch{}
      $items+=[pscustomobject]@{N=$nm;T=$c.ControlType.ProgrammaticName;R=$r;W=$wh;WR=$(if($wrq){$wrq}else{$wr})} }catch{} }
    $flags=0; $n=$items.Count
    for($i=0;$i -lt $n;$i++){ $a=$items[$i]
      $wr=$a.WR; if($a.R.Left -lt $wr.Left-2 -or $a.R.Right -gt $wr.Right+2 -or $a.R.Top -lt $wr.Top-2 -or $a.R.Bottom -gt $wr.Bottom+2){ Say "LAYOUT-FLAG [$label] OUTSIDE-WINDOW $($a.N) rect=$([int]$a.R.Left),$([int]$a.R.Top),$([int]$a.R.Right),$([int]$a.R.Bottom) window=$([int]$wr.Left),$([int]$wr.Top),$([int]$wr.Right),$([int]$wr.Bottom)"; $flags++ }
      if(($a.T -match 'Button|Edit') -and ($a.N -notmatch '^PART_') -and ($a.R.Height -lt 20 -or $a.R.Width -lt 24)){ Say "LAYOUT-FLAG [$label] TINY $($a.N) size=$([int]$a.R.Width)x$([int]$a.R.Height)"; $flags++ }
      for($j=$i+1;$j -lt $n;$j++){ $b=$items[$j]
        if($a.W -ne $b.W){ continue }
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
  # l186: open the Procurement window itself so it is captured and audited (no screenshot of it existed before)
  $pw=BizOpen 'ProcurementOpenButton' 'المشتريات والطلبيات وإعادة الطلب'; if($pw){ Check ($true) 'business: the Procurement window opens'; Shot 'proc-window-1-top'; LayoutAudit 'procurement' $pw; BizCloseWin $pw 'المشتريات والطلبيات وإعادة الطلب' }
  $w=BizOpen 'BusinessToolsButton' 'أدوات الأعمال'; if(-not $w){ return }
  Check ($true) 'business: the Business tools window opens'; Shot 'biz-1-open'; LayoutAudit 'business-tools' $w
  $tc=@($w.FindAll($TS::Descendants,(New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem)))).Count
  Say "DIAG business: tab count [$tc]"; Check ($tc -eq 13) 'business: thirteen tabs are present'
  foreach($t in @('الصلاحية والتخفيض','طلبات الشراء','تتبع التشغيلة','أسعار الموردين','تحويل مخزون','التفاعلات الدوائية','تقارير','مفاتيح سريعة','صحة النسخ الاحتياطي','صلاحيات الأدوار','فحص النظام والبيانات','تقارير المشتريات والمخزون','ساعات العمل')){
    $ok=BizSelectTab $w $t; Check $ok "business: tab [$t] can be selected"; if($ok){ Shot ('biz-tab-'+($t -replace '\s','_')) } }
  if(BizSelectTab $w 'صلاحيات الأدوار'){ foreach($rid in @('BtRoleSelect','BtRoleTemplate','BtRoleMode_sales')){ $re=ById $w $rid 3; Check ($re -ne $null) "business: roles editor control $rid is present"; if($re){ $vt=''; try{ $vt=[string]$re.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }catch{ $vt=[string]$re.Current.Name }; Say "DIAG business: roles editor $rid shows [$vt]"; Check (-not ($vt -like '*DataRowView*')) "business: roles editor $rid does not show a raw type name" } } }
  # opening hours tab (l168): edit Monday, save, read it back, restore
  if(BizSelectTab $w 'ساعات العمل'){ $o1=ById $w 'BtHoursOpen_1' 3; $sv1=ById $w 'BtHoursSave_1' 3; $cl1=ById $w 'BtHoursClose_1' 3
    if($o1 -and $sv1 -and $cl1){ try{ $vp=[System.Windows.Automation.ValuePattern]::Pattern; $d0=[string]$o1.GetCurrentPattern($vp).Current.Value; Say "DIAG business: hours Monday open shows [$d0]"; Check ($d0 -eq '09:00') 'business: opening hours default Monday open is 09:00'; GlyphPixels $o1 'business: hours Monday open field'
        $o1.GetCurrentPattern($vp).SetValue('10:30'); $sv1.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 700
        [void](BizSelectTab $w 'صلاحيات الأدوار'); [void](BizSelectTab $w 'ساعات العمل'); Start-Sleep -Milliseconds 500; $o1b=ById $w 'BtHoursOpen_1' 3; $d1=[string]$o1b.GetCurrentPattern($vp).Current.Value; Say "DIAG business: hours Monday open after save and reopen [$d1]"; Check ($d1 -eq '10:30') 'business: an edited opening time is saved and shown again'
        $o1b.GetCurrentPattern($vp).SetValue('09:00'); (ById $w 'BtHoursSave_1' 3).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 500 }catch{ Say "FAIL business: hours step: $($_.Exception.Message)"; $script:fails++ } } else { Say 'NOTEXECUTED business: opening hours controls not found'; $script:notexec++ } }
  # backup health: the status text must be one of the six statuses, an honest read of the folder
  if(BizSelectTab $w 'صحة النسخ الاحتياطي'){ $st=ById $w 'BtBackupStatus' 3; if($st){ $s=[string]$st.Current.Name; Say "DIAG business: backup health text [$s]"; Check ($s.Length -gt 0) 'business: the backup health tab shows a status' } else { Say 'NOTEXECUTED business: BtBackupStatus not found'; $script:notexec++ } }
  # restore drill (l182): click it, read the result text. With no backup folder set the honest result is the 'no folder' message, which is still a non-empty answer; a MATCHES verdict is not required here.
  if(BizSelectTab $w 'صحة النسخ الاحتياطي'){ $db=ById $w 'BtRestoreDrill' 3; if($db){ try{ $db.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Start-Sleep -Milliseconds 1500; $dr=ById $w 'BtRestoreDrillResult' 3; $drs=''; if($dr){ $drs=[string]$dr.Current.Name }; Say "DIAG business: restore drill result [$drs]"; Check ($drs.Length -gt 0) 'business: the restore drill button gives a visible result'; Shot 'biz-drill' }catch{ Say "FAIL business: restore drill step: $($_.Exception.Message)"; $script:fails++ } } else { Say 'NOTEXECUTED business: BtRestoreDrill not found'; $script:notexec++ } }
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
