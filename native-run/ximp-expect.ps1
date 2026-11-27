# Pure helpers for the r112b import drill v3 (no UI). Offline-tested by test-ximp-offline.ps1 before any app launch.
function XNorm($t){ $x=[string]$t; $x=[regex]::Replace($x,'[\u200E\u200F\u202A-\u202E\u2066-\u2069]',''); $ar=[string]('٠١٢٣٤٥٦٧٨٩'); for($i=0;$i -lt 10;$i++){ $x=$x.Replace([string]$ar[$i],[string]$i) }; $x=$x.Replace('٫','.').Replace([string][char]0x2212,'-'); return $x.Trim() }
function XNumEq($cell,$dec){ $x=XNorm $cell; $d=[decimal]0; if([decimal]::TryParse($x,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$d)){ return ($d -eq [decimal]$dec) }; return $false }
# Rows of an xlsx sheet (array of string[] rows) that contain a cell exactly equal to $val. Returns an object with .Count and .Rows so PowerShell never unrolls or nests the result.
function XRowsWithCell($rows,$val){ $list=New-Object System.Collections.ArrayList; foreach($r in @($rows)){ $cells=@($r | ForEach-Object { [string]$_ }); if($cells -ccontains [string]$val){ [void]$list.Add($cells) } }; return [pscustomobject]@{ Count=[int]$list.Count; Rows=$list } }
# Column index of an exact header name (after XNorm), or -1.
function XCol($header,$name){ $h=@($header | ForEach-Object { XNorm $_ }); for($i=0;$i -lt $h.Count;$i++){ if($h[$i] -ceq $name){ return $i } }; return -1 }
function XCell($row,$idx){ $c=@($row); if($idx -lt 0 -or $idx -ge $c.Count){ return $null }; return [string]$c[$idx] }
# Choose the single modal button wanted from UIA descriptors (hashtables with type, id, name). $which = yes, no or ok. Returns the descriptor, or $null when none or more than one matches.
function XPickButton($descs,$which){
  $namePat=@{ yes='^&?(Yes|نعم)$'; no='^&?(No|لا)$'; ok='^&?(OK|موافق)$' }[$which]; $idPat=@{ yes='^(6|CommandButton_6)$'; no='^(7|CommandButton_7)$'; ok='^(1|CommandButton_1)$' }[$which]
  $hit=@(@($descs) | Where-Object { $t=[string]$_.type; (($t -like '*Button*') -or ($t -like '*Pane*')) -and ((([string]$_.name) -match $namePat) -or (([string]$_.id) -match $idPat)) })
  if($hit.Count -eq 1){ return $hit[0] }; return $null }
# True when a modal title looks like the import confirmation (not a refusal).
function XIsConfirmTitle($title){ return (([string]$title) -match 'تأكيد') }

function XComboOk($cb,$pats){ $a=@($cb); if($a.Count -lt @($pats).Count){ return $false }
  for($k=0;$k -lt @($pats).Count;$k++){ $v=$a[$k]; if($v -is [System.Array]){ return $false }; $v=[string]$v; if(@($pats)[$k] -eq ''){ if($v -ne ''){ return $false } } elseif(-not ($v -match @($pats)[$k])){ return $false } }
  return $true }
function XPtInRect($x,$y,$l,$t,$w,$h){ return ($w -gt 0 -and $h -gt 0 -and $x -ge $l -and $y -ge $t -and $x -le ($l+$w) -and $y -le ($t+$h)) }

# ---- r113 additions (pure, offline-tested) ----
# Exact header list, in order, after XNorm of each cell.
function XHeaderIs($header,$expected){ $h=@($header | ForEach-Object { XNorm $_ }); $e=@($expected); if($h.Count -ne $e.Count){ return $false }; for($i=0;$i -lt $e.Count;$i++){ if(-not ($h[$i] -ceq [string]$e[$i])){ return $false } }; return $true }
function XIsInternalId($v){ return ([string]$v) -cmatch '^[0-9a-f]{32}$' }
# Purchases export linkage: for each wanted source ref there is exactly ONE data row carrying it in source_ref; on that row purchase_ref equals purchase_id and is an internal 32-hex id; the wanted rows have distinct ids. $hd is the header row, $rows all rows including the header.
function XLinkCheck($rows,$hd,$wanted){ $ci=XCol $hd 'purchase_ref'; $pi=XCol $hd 'purchase_id'; $si=XCol $hd 'source_ref'; if($ci -lt 0 -or $pi -lt 0 -or $si -lt 0){ return $false }
  $ids=@(); foreach($w in @($wanted)){ $hit=@(); foreach($r in @($rows | Select-Object -Skip 1)){ if((XCell $r $si) -ceq [string]$w){ $hit+=,@($r) } }
    if($hit.Count -ne 1){ return $false }; $r1=@($hit[0]); $a=XCell $r1 $ci; $b=XCell $r1 $pi; if(-not ($a -ceq $b) -or -not (XIsInternalId $a)){ return $false }; $ids+=$a }
  return (@($ids | Sort-Object -Unique).Count -eq @($ids).Count) }

# r113 v5c: row identity for the (virtualized) mapping grid. Never infer a row from a count or a position.
# Names of the realized elements of the grid, and a label pattern: is the row for that label realized?
function XRowRealized($names,$labelPat){ return (@(@($names) | Where-Object { ([string]$_) -match $labelPat }).Count -ge 1) }
# Verdict for the required purchase_ref row: NOTREALIZED when the row was not found (absence is never a pass); PASS only for an EMPTY chooser whose own row status says more than one match.
function XRefRowVerdict($found,$combo,$status){ if(-not $found){ return 'NOTREALIZED' }; if(([string]$combo).Trim() -ne ''){ return 'FAIL-chosen' }; if(([string]$status) -notmatch 'أكثر من تطابق'){ return 'FAIL-status' }; return 'PASS' }

# ---- r114 v6 ----
# Verdict for a purchase_ref row that must show the CANONICAL suggestion: chooser exactly "<idx>: purchase_ref" (the app prefixes the 1-based column number) AND the row status names the canonical column (القياسي) and is NOT the more-than-one-match status. NOTREALIZED when the row was not found (absence is never a pass). Mismatched chooser/status combinations are failures.
function XRefRowCanonical($found,$combo,$status,$idx){ if(-not $found){ return 'NOTREALIZED' }
  $c=([string]$combo).Trim(); $s=[string]$status
  if($c -eq ''){ return 'FAIL-empty-chooser' }
  if(-not ($c -ceq ("$idx"+': purchase_ref'))){ return 'FAIL-chooser' }
  if($s -match 'أكثر من تطابق'){ return 'FAIL-status-is-conflict' }
  if($s -notmatch 'القياسي'){ return 'FAIL-status-not-canonical' }
  return 'PASS' }

# ---- r114 v7 (Sales + OpeningStock slice) ----
# Count rows of an export sheet whose named string columns equal exactly and whose named numeric columns equal exactly (decimal). $hd is the header row, $rows all rows including the header. Returns -1 when a named column is missing.
function XRowCount($rows,$hd,$strSpec,$numSpec){ $idx=@{}; foreach($k in @(@($strSpec.Keys)+@($numSpec.Keys))){ $i=XCol $hd $k; if($i -lt 0){ return -1 }; $idx[$k]=$i }
  $n=0; foreach($r in @($rows | Select-Object -Skip 1)){ $ok=$true
    foreach($k in @($strSpec.Keys)){ if(-not ((XNorm (XCell $r $idx[$k])) -ceq [string]$strSpec[$k])){ $ok=$false; break } }
    if($ok){ foreach($k in @($numSpec.Keys)){ if(-not (XNumEq (XCell $r $idx[$k]) $numSpec[$k])){ $ok=$false; break } } }
    if($ok){ $n++ } }
  return $n }
# Expected drawer cash (EGP, decimal) from the Sales page shift label. Handles Arabic-Indic digits, comma and Arabic thousands separators. $null when no number is found.
function XShiftExpected($text){ $x=XNorm $text; $x=$x.Replace([string][char]0x066C,'').Replace(',',''); $m=[regex]::Match($x,'(\d+(?:\.\d+)?)\s*ج\.م'); if(-not $m.Success){ return $null }; return [decimal]::Parse($m.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture) }
function XShiftEq($text,$want){ $v=XShiftExpected $text; if($null -eq $v){ return $false }; return ($v -eq [decimal]$want) }
