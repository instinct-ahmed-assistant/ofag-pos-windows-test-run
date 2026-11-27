# Pure rules for the l116 native localization probe. No UI. A rule PASSes only when its captured box text exists and satisfies it; a missing capture is NOTEXECUTED, never PASS.
function L116Rules(){ return @(
 @{id='L1';box='G1|validate';must='وضع: أصناف جديدة.';mustNot='وضع: Products';what='Products validate result shows the Arabic mode label'},
 @{id='L2';box='G1|commit';must='وضع: أصناف جديدة.';mustNot='وضع: Products';what='Products commit result shows the Arabic mode label'},
 @{id='L3';box='V7-2|validate';must='وضع: رصيد افتتاحي فقط.';mustNot='وضع: OpeningStock';what='OpeningStock validate result shows the Arabic mode label'},
 @{id='L4';box='V7-6|validate';must='وضع: ترحيل مبيعات نقدية الآن.';mustNot='وضع: Sales';what='Sales validate result shows the Arabic mode label'},
 @{id='L5';box='G6a|validate';must='وضع: مشتريات نقدية.';mustNot='وضع: Purchases';what='Purchases validate result shows the Arabic mode label'},
 @{id='L6';box='V7-7d|validate';must='المخزون غير كافٍ.';mustNot='Insufficient stock';what='real Excel refusal box: Arabic reason, no English (the v7 leak)'},
 @{id='L7';box='V7-7d|commit';must='المخزون غير كافٍ.';mustNot='Insufficient stock';what='same refusal at commit'}
) }
function L116Verdict($rule,$boxes){
  if(-not $boxes.ContainsKey($rule.box)){ return @{ verdict='NOTEXECUTED'; why="no captured text for $($rule.box)" } }
  $t=[string]$boxes[$rule.box]
  if($t.IndexOf($rule.must,[System.StringComparison]::Ordinal) -lt 0){ return @{ verdict='FAIL'; why="expected text [$($rule.must)] not found in [$($t -replace '\s+',' ')]" } }
  if($t.IndexOf($rule.mustNot,[System.StringComparison]::Ordinal) -ge 0){ return @{ verdict='FAIL'; why="forbidden text [$($rule.mustNot)] present in [$($t -replace '\s+',' ')]" } }
  return @{ verdict='PASS'; why='ok' } }
# Observation only (never a verdict): Latin words of 4+ letters left in a message, except allowed product terms.
function L116Residue($text){ $allow=@('XLSX','Excel','TRIAL','DATA','Pilot','Good','Pharmacy','Sheet1'); $o=@(); foreach($m in [regex]::Matches([string]$text,'[A-Za-z]{4,}')){ if($allow -cnotcontains $m.Value){ $o+=$m.Value } }; return @($o | Select-Object -Unique) }

function L116StkRules(){ return @(
 @{id='L8';box='STK|refusal';must='لم يكتمل الإجراء: اختر من 1 إلى 500 دفعة مختلفة موجودة، وملاحظة حتى 1000 حرف.';mustNot='Select';what='Stocktake Begin with no batch selected: Arabic refusal (prefix plus translated Core text), no English leak (the r105 native run showed English tails in this window)'}
) }

# Pure database rule for the Stocktake probe. Opening the window runs Stocktakes() -> EnsureStocktakeSchema() (PharmacyDb.Stocktake.cs), which creates three EMPTY tables on first use (schema-on-open). That is a declared, explained difference, never a silent pass:
# PASS only when (a) every table present in both snapshots is identical (rows and hash), (b) the only tables present after but not before are a subset of the three stocktake tables, each with 0 rows, and (c) no table disappeared. Snapshot values are 'rows|hash'.
function L116StkSnapVerdict($a,$b){
  if($null -eq $a -or $null -eq $b){ return @{ verdict='FAIL'; why='snapshot pair incomplete'; lazy=@() } }
  $lazyOk=@('stocktake_count_events','stocktake_lines','stocktakes'); $lazy=@()
  foreach($k in @($a.Keys)){ if(-not $b.ContainsKey($k)){ return @{ verdict='FAIL'; why="table $k disappeared"; lazy=@() } } }
  foreach($k in @($b.Keys | Sort-Object)){
    if($a.ContainsKey($k)){ if([string]$a[$k] -cne [string]$b[$k]){ return @{ verdict='FAIL'; why="table $k changed ($($a[$k]) -> $($b[$k]))"; lazy=@() } } }
    else{ if($lazyOk -cnotcontains $k){ return @{ verdict='FAIL'; why="unexpected new table $k"; lazy=@() } }; if(([string]$b[$k]) -notlike '0|*'){ return @{ verdict='FAIL'; why="new table $k is not empty ($($b[$k]))"; lazy=@() } }; $lazy+=$k } }
  return @{ verdict='PASS'; why="no existing table changed; lazily created empty stocktake tables: [$($lazy -join ',')]"; lazy=$lazy } }
