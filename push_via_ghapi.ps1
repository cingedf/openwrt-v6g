$ErrorActionPreference='Stop'
$repo='cingedf/openwrt-v6g'
$files = @(
  '.gitattributes',
  '.github/workflows/build.yml',
  'README.md',
  'config/v6g_minimal.config',
  'diy-part2.sh',
  'dts/mt7621_qihoo_360t6gs.dts',
  'files/etc/uci-defaults/99-v6g-firstboot',
  'mt7621-qihoo-device.mk'
)
$tree=@()
foreach($f in $files){
  $b64=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path (Get-Location) $f)))
  $tmp=[IO.Path]::GetTempFileName()
  @{ content=$b64; encoding='base64' } | ConvertTo-Json -Compress | Set-Content $tmp -Encoding ascii
  $sha = gh api "repos/$repo/git/blobs" --input $tmp --jq '.sha'
  if(-not $sha){ throw "blob fail: $f" }
  Write-Host "blob $f -> $sha"
  $tree += @{ path=$f; mode='100644'; type='blob'; sha=$sha }
}
$treeTmp=[IO.Path]::GetTempFileName()
@{ tree=$tree } | ConvertTo-Json -Depth 6 | Set-Content $treeTmp -Encoding ascii
$treeSha = gh api "repos/$repo/git/trees" --input $treeTmp --jq '.sha'
Write-Host "tree -> $treeSha"
$commitTmp=[IO.Path]::GetTempFileName()
@{
  message='V6G (qihoo_360t6gs) official OpenWrt v25.12.5 board overlay + cloud build workflow'
  tree=$treeSha
  parents=@()
} | ConvertTo-Json -Depth 6 | Set-Content $commitTmp -Encoding ascii
$commitSha = gh api "repos/$repo/git/commits" --input $commitTmp --jq '.sha'
Write-Host "commit -> $commitSha"
$refTmp=[IO.Path]::GetTempFileName()
@{ ref='refs/heads/main'; sha=$commitSha } | ConvertTo-Json -Compress | Set-Content $refTmp -Encoding ascii
$refOut = gh api "repos/$repo/git/refs" --input $refTmp --jq '.ref '.Replace(' ','') 2>$null
if(-not $refOut){ $refOut = gh api "repos/$repo/git/refs" --input $refTmp --jq '.ref' }
Write-Host "ref -> $refOut"
