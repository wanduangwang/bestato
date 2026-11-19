param(
    [string] $Godot = 'godot',
    [string] $AppId = 'touristappid',
    [string] $RelayUrl = '',
    [string] $OutputDirectory = 'dist/wechat'
)

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$engine = (Get-Command $Godot -ErrorAction Stop).Source
$version = (& $engine --version) -join ' '
if ($version -notmatch '^4\.6\.3\.stable\.official\.7d41c59c4') {
    throw 'Use the official Godot 4.6.3 editor console executable.'
}
if ($AppId -notmatch '^(touristappid|wx[0-9a-f]{16})$') { throw 'Invalid WeChat AppID.' }
if ($RelayUrl) {
    $endpoint = $null
    if (-not [Uri]::TryCreate($RelayUrl, [UriKind]::Absolute, [ref]$endpoint) -or
        $endpoint.Scheme -ne 'wss' -or $endpoint.HostNameType -ne [UriHostNameType]::Dns -or
        $endpoint.IsLoopback -or $endpoint.UserInfo -or $endpoint.Query -or $endpoint.Fragment -or
        $endpoint.AbsolutePath -ne '/wechat-room') {
        throw 'Use a registered wss:// DNS endpoint ending in /wechat-room.'
    }
}
$out = [IO.Path]::GetFullPath($OutputDirectory, $project)
$cache = (New-Item -ItemType Directory -Force (Join-Path $project '.godot/wechat-build/toolchain')).FullName
$work = (New-Item -ItemType Directory (Join-Path $cache ('build-' + [Guid]::NewGuid()))).FullName
$source = (New-Item -ItemType Directory (Join-Path $work 'project')).FullName

function Get-PinnedArchive([string] $name, [string] $url, [string] $sha256) {
    $archive = Join-Path $cache $name
    if (-not (Test-Path -LiteralPath $archive)) {
        $download = Join-Path $work $name
        curl.exe --fail --silent --show-error --location --retry 1 --max-time 90 $url -o $download
        if ($LASTEXITCODE -ne 0) { throw "Could not download $name." }
        if ((Get-FileHash -LiteralPath $download).Hash -ne $sha256) { throw "Invalid checksum for $name." }
        Copy-Item -LiteralPath $download -Destination $archive
    }
    if ((Get-FileHash -LiteralPath $archive).Hash -ne $sha256) { throw "Invalid checksum for $name." }
    return $archive
}

$upstream = 'https://github.com/AnranS/godot_for_minigame'
$exporterSource = 'https://codeload.github.com/AnranS/godot_for_minigame/zip/refs/tags/v0.3.1'
$exporterHash = '75e345ba5381187a1b28d755e11b28ebbc7ef69dfeb05842d3077ec077a9d099'
$exporter = Get-PinnedArchive 'exporter-v0.3.1.zip' $exporterSource $exporterHash
$templateName = 'godot_minigame_template_4.6.3-stable_emsdk-4.0.3_2d-full_release_abi-1_r1.zip'
$templateTag = 'template-4.6.3-stable-emsdk-4.0.3-2d-full-release-abi-1-r1'
$templateHash = '5f205b709e40ba8e16ab6131f30b434d7843d1a73921f5630b48bca72490e5a9'
$template = Get-PinnedArchive $templateName "$upstream/releases/download/$templateTag/$templateName" $templateHash
Expand-Archive -LiteralPath $exporter -DestinationPath $work
$vendor = Join-Path $work 'godot_for_minigame-0.3.1'
foreach ($name in @('project.godot', 'export_presets.cfg', 'assets', 'i18n', 'scenes', 'scripts')) {
    Copy-Item -LiteralPath (Join-Path $project $name) -Destination $source -Recurse
}
$preset = Join-Path $source 'export_presets.cfg'
(Get-Content -LiteralPath $preset -Raw).Replace('custom_features=""', 'custom_features="wechat_minigame"') |
    Set-Content -LiteralPath $preset -Encoding utf8NoBOM
Copy-Item -LiteralPath (Join-Path $vendor 'addons') -Destination $source -Recurse
$vendorAddon = Join-Path $source 'addons/godot_mini_game'

# Keep the verified template cache inside the isolated export project.
$exporterScript = Join-Path $vendorAddon 'exporter.gd'
$storeLine = 'return OS.get_config_dir().path_join("godot_mini_game/templates/v1")'
$exporterCode = Get-Content -LiteralPath $exporterScript -Raw
if (-not $exporterCode.Contains($storeLine)) { throw 'Exporter template store changed.' }
$exporterCode = $exporterCode.Replace($storeLine, 'return ProjectSettings.globalize_path("res://.godot/wechat-templates")')
# Use the adapter's socket and expose the engine filesystem before hashing the runtime.
$fsAnchor = 'var _module_copy_marker :='
if (-not $exporterCode.Contains($fsAnchor)) { throw 'Exporter filesystem anchor changed.' }
$tab = [char]9
$fsPatch = @(
    'var bestato_socket := "new WebSocket("'
    'var text_encoder := "buffer=new TextEncoder(\"utf-8\").encode(event.data)"'
    'if content.count(_module_copy_anchor) != 1 or content.count(bestato_socket) != 2 or content.count(text_encoder) != 1:'
    ($tab + 'return ERR_FILE_CORRUPT')
    'content = content.replace(_module_copy_anchor, _module_copy_anchor + "Module[\"bestatoFS\"]=FS;")'
    'content = content.replace(bestato_socket, "new window.WebSocket(")'
    'content = content.replace("event.data instanceof Blob", "typeof Blob!==\"undefined\"&&event.data instanceof Blob")'
    'content = content.replace(text_encoder, "const size=lengthBytesUTF8(event.data);buffer=new Uint8Array(size+1);stringToUTF8Array(event.data,buffer,0,size+1);buffer=buffer.subarray(0,size)")'
    'modified = true'
) -join ([Environment]::NewLine + $tab)
$exporterCode.Replace($fsAnchor, $fsPatch + [Environment]::NewLine + $tab + $fsAnchor) |
    Set-Content -LiteralPath $exporterScript -Encoding utf8NoBOM
$entry = Join-Path $vendorAddon 'templates/wechat/game.js'
$entryCode = Get-Content -LiteralPath $entry -Raw
$bridge = Get-Content -LiteralPath (Join-Path $project 'platform/wechat/bestato-platform.js') -Raw
$bridge = $bridge.Replace('module.exports = function installBestatoWechat', 'function installBestatoWechat')
$relayJson = ConvertTo-Json -InputObject $RelayUrl -Compress
$loaderAnchor = 'const loader = new Loader();'
if (-not $entryCode.Contains($loaderAnchor)) { throw 'Unexpected WeChat entrypoint.' }
$insert = $bridge + [Environment]::NewLine + $loaderAnchor + [Environment]::NewLine +
    "loader.installBestatoPlatform = (fs) => installBestatoWechat(fs, _api, $relayJson);"
$entryCode.Replace($loaderAnchor, $insert) | Set-Content -LiteralPath $entry -Encoding utf8NoBOM
$loader = Join-Path $vendorAddon 'templates/common/js/loader.js'
$loaderCode = Get-Content -LiteralPath $loader -Raw
$start = '      await engine.start();'
if (-not $loaderCode.Contains($start)) { throw 'Loader startup anchor changed.' }
$loaderCode.Replace($start, '      this.installBestatoPlatform(engine.rtenv.bestatoFS);' + [Environment]::NewLine + $start) |
    Set-Content -LiteralPath $loader -Encoding utf8NoBOM
$adapter = Join-Path $vendorAddon 'templates/common/adapter.js'
$adapterCode = Get-Content -LiteralPath $adapter -Raw
$socketSend = '  send(data) { if (this.readyState === 1) this._task.send({ data }); }'
$socketClose = 'code: r.code, reason: r.reason'
$screen = 'const _testCtx = _mainCanvas.getContext("webgl2");'
if (-not $adapterCode.Contains($socketSend) -or -not $adapterCode.Contains($socketClose) -or
    -not $adapterCode.Contains($screen)) {
    throw 'Adapter socket or canvas anchors changed.'
}
# Godot reads browser-compatible instance state, protocol and pending bytes.
$sendPatch = @'
  get OPEN() { return _WebSocket.OPEN; }
  get CLOSING() { return _WebSocket.CLOSING; }
  protocol = "";
  bufferedAmount = 0;
  send(data) {
    if (this.readyState !== _WebSocket.OPEN) return;
    const bytes = typeof data === "string" ? data.length : data.byteLength;
    this.bufferedAmount += bytes;
    const sent = () => { this.bufferedAmount -= bytes; };
    this._task.send({ data, success: sent, fail: (error) => { sent(); this._fire("error", error); } });
  }
'@
$adapterCode = $adapterCode.Replace($socketSend, $sendPatch).Replace($socketClose, 'code: r?.code ?? 1006, reason: r?.reason ?? ""')
# The loading screen and Godot share one context. The letterboxed viewport
# needs a full-size framebuffer blit, which requires a non-MSAA context.
$adapterCode.Replace($screen, 'const _testCtx = _mainCanvas.getContext("webgl2", { antialias: false, preserveDrawingBuffer: true });') |
    Set-Content -LiteralPath $adapter -Encoding utf8NoBOM
$config = Join-Path $vendorAddon 'templates/wechat/project.config.json.template'
(Get-Content -LiteralPath $config -Raw).Replace('"urlCheck": false', '"urlCheck": true') |
    Set-Content -LiteralPath $config -Encoding utf8NoBOM

$importLog = Join-Path $work 'import.log'
& $engine --headless --path $source --import --quit --log-file $importLog
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR' -Quiet)) {
    throw "Godot import failed. See $importLog"
}
$exportLog = Join-Path $work 'export.log'
$script = Join-Path $project 'tools/wechat/export.gd'
& $engine --headless --path $source --log-file $exportLog --script $script -- $template $AppId $out
if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $exportLog -Pattern 'SCRIPT ERROR' -Quiet)) {
    throw "WeChat export failed. See $exportLog"
}
Copy-Item -LiteralPath (Join-Path $vendor 'LICENSE') -Destination "$out.LICENSE-GodotMiniGame.txt" -Force
$engineArchive = [IO.Compression.ZipFile]::OpenRead($template)
try {
    $notice = $engineArchive.GetEntry('GODOT_COPYRIGHT.txt')
    if ($null -eq $notice) { throw 'The engine template is missing its copyright notice.' }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($notice, "$out.GODOT_COPYRIGHT.txt", $true)
} finally {
    $engineArchive.Dispose()
}
$files = @(Get-ChildItem -LiteralPath $out -File -Recurse)
$total = ($files | Measure-Object -Property Length -Sum).Sum
$subpackages = @((Get-Content -LiteralPath (Join-Path $out 'game.json') -Raw | ConvertFrom-Json).subpackages.root)
$mainFiles = foreach ($file in $files) {
    $relative = [IO.Path]::GetRelativePath($out, $file.FullName).Replace('\', '/')
    if (-not ($subpackages | Where-Object { $relative.StartsWith($_, [StringComparison]::Ordinal) })) { $file }
}
$main = ($mainFiles | Measure-Object -Property Length -Sum).Sum
if ($main -gt 4MB -or $total -gt 30MB) { throw "WeChat package limit exceeded: $main main bytes, $total total bytes." }
Write-Output "WeChat build: $out"
Write-Output "Package sizes: $main main bytes, $total total bytes."
Write-Output "Build logs: $work"
