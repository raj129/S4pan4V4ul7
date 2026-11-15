param(
    [string]$DebugApk = 'build\app\outputs\flutter-apk\app-debug.apk',
    [string]$ReleaseApk = 'build\app\outputs\flutter-apk\app-release.apk',
    [string]$Sdk = $env:ANDROID_HOME
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-CanonicalManifestAttributes {
    param([System.Xml.XmlElement]$Node, [hashtable]$Resources)

    $attributes = @{}
    foreach ($attribute in @($Node.Attributes | Sort-Object Name)) {
        if ($attribute.Name -eq 'xmlns:android') { continue }
        if ($Node.LocalName -eq 'application' -and
            $attribute.LocalName -in @('debuggable', 'testOnly')) { continue }
        $value = $attribute.Value
        # Resource IDs are assigned independently by each build.
        if ($value -match '^@ref/(0x7f[0-9a-fA-F]+)$') {
            $id = $Matches[1].ToLowerInvariant()
            if (-not $Resources.ContainsKey($id)) {
                throw "Unresolved manifest resource $id."
            }
            $value = '@' + $Resources[$id]
        }
        $attributes[$attribute.Name] = $value
    }
    return $attributes
}

function Get-ManifestNodeMatchKey {
    param([System.Xml.XmlElement]$Node)

    $ns = 'http://schemas.android.com/apk/res/android'
    $identity = @()
    foreach ($name in @('name', 'scheme', 'host', 'port', 'mimeType', 'path', 'pathPrefix')) {
        $value = $Node.GetAttribute($name, $ns)
        if ($value) { $identity += "$name=$value" }
    }
    if ($Node.LocalName -eq 'intent-filter') {
        $childKeys = @($Node.ChildNodes |
            Where-Object { $_ -is [System.Xml.XmlElement] } |
            ForEach-Object { Get-ManifestNodeMatchKey $_ } |
            Sort-Object)
        $identity += 'children=' + ($childKeys -join ',')
    }
    return $Node.LocalName + '|' + ($identity -join '|')
}

function Get-ManifestNodeLabel {
    param([System.Xml.XmlElement]$Node, [int]$Index)

    $name = $Node.GetAttribute(
        'name',
        'http://schemas.android.com/apk/res/android'
    )
    if ($name) { return "$($Node.LocalName)[name=$name]" }
    return "$($Node.LocalName)[$Index]"
}

function Get-ManifestDifferenceDetails {
    param(
        [System.Xml.XmlElement]$DebugNode,
        [hashtable]$DebugResources,
        [System.Xml.XmlElement]$ReleaseNode,
        [hashtable]$ReleaseResources,
        [string]$Path = '/manifest'
    )

    $differences = New-Object 'System.Collections.Generic.List[string]'
    if ($DebugNode.LocalName -ne $ReleaseNode.LocalName) {
        $differences.Add("$Path element kind differs")
        return $differences.ToArray()
    }

    $debugAttributes = Get-CanonicalManifestAttributes $DebugNode $DebugResources
    $releaseAttributes = Get-CanonicalManifestAttributes $ReleaseNode $ReleaseResources
    $attributeNames = @(@($debugAttributes.Keys) + @($releaseAttributes.Keys) |
        Sort-Object -Unique)
    foreach ($name in $attributeNames) {
        $inDebug = $debugAttributes.ContainsKey($name)
        $inRelease = $releaseAttributes.ContainsKey($name)
        if (-not $inDebug) {
            $differences.Add("$Path attribute $name exists only in release APK")
        } elseif (-not $inRelease) {
            $differences.Add("$Path attribute $name exists only in debug APK")
        } elseif ($debugAttributes[$name] -ne $releaseAttributes[$name]) {
            $differences.Add("$Path attribute $name differs")
        }
    }

    $debugChildren = @($DebugNode.ChildNodes |
        Where-Object { $_ -is [System.Xml.XmlElement] })
    $releaseChildren = @($ReleaseNode.ChildNodes |
        Where-Object { $_ -is [System.Xml.XmlElement] })
    $releaseChildUsed = @()
    for ($i = 0; $i -lt $releaseChildren.Count; $i++) {
        $releaseChildUsed += $false
    }
    $debugOccurrences = @{}

    for ($i = 0; $i -lt $debugChildren.Count; $i++) {
        $debugChild = $debugChildren[$i]
        $localName = $debugChild.LocalName
        if (-not $debugOccurrences.ContainsKey($localName)) {
            $debugOccurrences[$localName] = 0
        }
        $debugOccurrences[$localName]++
        $childLabel = Get-ManifestNodeLabel $debugChild $debugOccurrences[$localName]
        $childPath = "$Path/$childLabel"
        $matchKey = Get-ManifestNodeMatchKey $debugChild
        $matchIndex = -1

        for ($j = 0; $j -lt $releaseChildren.Count; $j++) {
            if (-not $releaseChildUsed[$j] -and
                (Get-ManifestNodeMatchKey $releaseChildren[$j]) -ceq $matchKey) {
                $matchIndex = $j
                break
            }
        }
        if ($matchIndex -lt 0) {
            for ($j = 0; $j -lt $releaseChildren.Count; $j++) {
                if (-not $releaseChildUsed[$j] -and
                    $releaseChildren[$j].LocalName -eq $localName) {
                    $matchIndex = $j
                    break
                }
            }
        }

        if ($matchIndex -lt 0) {
            $differences.Add("$childPath element exists only in debug APK")
            continue
        }
        $releaseChildUsed[$matchIndex] = $true
        $nested = @(Get-ManifestDifferenceDetails `
            $debugChild $DebugResources `
            $releaseChildren[$matchIndex] $ReleaseResources `
            $childPath)
        foreach ($difference in $nested) { $differences.Add($difference) }
    }

    $releaseOccurrences = @{}
    for ($i = 0; $i -lt $releaseChildren.Count; $i++) {
        if ($releaseChildUsed[$i]) { continue }
        $localName = $releaseChildren[$i].LocalName
        if (-not $releaseOccurrences.ContainsKey($localName)) {
            $releaseOccurrences[$localName] = 0
        }
        $releaseOccurrences[$localName]++
        $childLabel = Get-ManifestNodeLabel $releaseChildren[$i] $releaseOccurrences[$localName]
        $childPath = "$Path/$childLabel"
        $differences.Add("$childPath element exists only in release APK")
    }
    return $differences.ToArray()
}

function Get-CanonicalManifestNode {
    param([System.Xml.XmlElement]$Node, [hashtable]$Resources)

    $attributes = Get-CanonicalManifestAttributes $Node $Resources
    $attributeValues = @()
    foreach ($name in @($attributes.Keys | Sort-Object)) {
        $attributeValues += $name + '=' + $attributes[$name]
    }
    $children = @()
    foreach ($child in $Node.ChildNodes) {
        if ($child -isnot [System.Xml.XmlElement]) { continue }
        # Crashlytics generates a different mapping/build ID for each variant.
        if ($child.LocalName -eq 'meta-data' -and
            $child.GetAttribute('name', 'http://schemas.android.com/apk/res/android') -eq
            'com.google.firebase.crashlytics.mapping_file_id') { continue }
        $children += Get-CanonicalManifestNode $child $Resources
    }
    return (@($Node.LocalName, ($attributeValues -join "`n"), (@($children | Sort-Object) -join "`n")) |
        ConvertTo-Json -Compress)
}

function Assert-FeatureManifest {
    param([xml]$Manifest, [bool]$Release)

    $ns = 'http://schemas.android.com/apk/res/android'
    if ($Manifest.manifest.package -ne 'com.system.calculator') {
        throw 'Unexpected application ID.'
    }
    $app = $Manifest.manifest.application
    if ($Release -and $app.GetAttribute('debuggable', $ns) -eq 'true') {
        throw 'Release APK is debuggable.'
    }
    if ($app.GetAttribute('allowBackup', $ns) -ne 'false') {
        throw 'Vault backup protection is missing.'
    }
    $permissions = @($Manifest.manifest.SelectNodes('uses-permission') |
        ForEach-Object { $_.GetAttribute('name', $ns) })
    foreach ($permission in @('INTERNET', 'SEND_SMS', 'RECEIVE_SMS', 'CAMERA',
            'RECORD_AUDIO', 'READ_CONTACTS', 'READ_CALL_LOG', 'WRITE_CALL_LOG',
            'POST_NOTIFICATIONS', 'ACCESS_FINE_LOCATION', 'ACCESS_BACKGROUND_LOCATION',
            'FOREGROUND_SERVICE_DATA_SYNC', 'FOREGROUND_SERVICE_LOCATION')) {
        if ('android.permission.' + $permission -notin $permissions) {
            throw "Required permission missing: $permission."
        }
    }
    foreach ($name in @('MainActivity', 'DataSmsReceiver', 'DataSmsCallbackReceiver',
            'ChatUploadService', 'MockLocationService')) {
        $fullName = 'com.system.calculator.' + $name
        $found = @($app.ChildNodes | Where-Object {
            $_ -is [System.Xml.XmlElement] -and
            $_.GetAttribute('name', $ns) -in @($fullName, ".$name")
        })
        if ($found.Count -ne 1) { throw "Required component missing: $name." }
    }
    $receiver = @($app.SelectNodes('receiver') | Where-Object {
        $_.GetAttribute('name', $ns) -in @(
            '.DataSmsReceiver', 'com.system.calculator.DataSmsReceiver')
    })[0]
    if ($receiver.GetAttribute('permission', $ns) -ne 'android.permission.BROADCAST_SMS' -or
        $null -eq $receiver.SelectSingleNode(
            "intent-filter/action[@android:name='android.intent.action.DATA_SMS_RECEIVED']",
            (New-AndroidNamespaceManager $Manifest)) -or
        $null -eq $receiver.SelectSingleNode(
            "intent-filter/data[@android:scheme='sms' and @android:port='42831']",
            (New-AndroidNamespaceManager $Manifest))) {
        throw 'Protected data SMS port routing is missing.'
    }
}

function New-AndroidNamespaceManager {
    param([xml]$Manifest)
    $manager = New-Object System.Xml.XmlNamespaceManager($Manifest.NameTable)
    $manager.AddNamespace('android', 'http://schemas.android.com/apk/res/android')
    return ,$manager
}

function Get-ApkManifest {
    param([string]$Apk, [string]$Analyzer, [string]$Aapt)
    $decoded = & $Analyzer manifest print $Apk
    if ($LASTEXITCODE -ne 0) { throw "Cannot decode manifest: $Apk." }
    $resources = @{}
    # Do not log resource contents or API-key metadata.
    $table = & $Aapt dump resources $Apk
    if ($LASTEXITCODE -ne 0) { throw "Cannot decode resources: $Apk." }
    foreach ($line in $table) {
        if ($line -match '^\s*resource (0x[0-9a-fA-F]+) (\S+)') {
            $resources[$Matches[1].ToLowerInvariant()] = $Matches[2]
        }
    }
    return @{ Xml = [xml]($decoded -join "`n"); Resources = $resources }
}

function Get-ApkAssets {
    param([string]$Apk, [bool]$Release)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
    try {
        $assets = @{}
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if (-not $name.StartsWith('assets/flutter_assets/') -or $name.EndsWith('/')) {
                continue
            }
            $relative = $name.Substring('assets/flutter_assets/'.Length)
            if ($relative -in @('kernel_blob.bin', 'vm_snapshot_data',
                    'isolate_snapshot_data', 'NativeAssetsManifest.json')) { continue }
            # Icon tree shaking changes font bytes, not font availability.
            if ($relative -match '\.(ttf|otf)$') {
                $assets[$relative] = 'font'
                continue
            }
            $stream = $entry.Open()
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $assets[$relative] = [BitConverter]::ToString($sha.ComputeHash($stream))
            } finally {
                $sha.Dispose()
                $stream.Dispose()
            }
        }
        if ($assets.Count -eq 0) { throw 'APK contains no Flutter assets.' }
        $abis = @($zip.Entries | Where-Object {
            $_.FullName -match '^lib/[^/]+/libflutter\.so$'
        } | ForEach-Object { $_.FullName.Split('/')[1] } | Sort-Object)
        if ($abis.Count -eq 0) { throw 'APK contains no Flutter runtime.' }
        if ($Release) {
            foreach ($abi in $abis) {
                if ($null -eq $zip.GetEntry("lib/$abi/libapp.so")) {
                    throw "Release AOT code missing for $abi."
                }
            }
        }
        return @{ Assets = $assets; Abis = $abis }
    } finally { $zip.Dispose() }
}

function Assert-AssetParity {
    param([hashtable]$Debug, [hashtable]$Release)
    if (($Debug.Abis -join ',') -ne ($Release.Abis -join ',')) {
        throw 'APK CPU architectures differ. Build both APKs with identical target platforms.'
    }
    foreach ($name in @(@($Debug.Assets.Keys) + @($Release.Assets.Keys) | Sort-Object -Unique)) {
        if (-not $Debug.Assets.ContainsKey($name) -or
            -not $Release.Assets.ContainsKey($name) -or
            $Debug.Assets[$name] -ne $Release.Assets[$name]) {
            throw "Flutter asset differs or is missing: $name."
        }
    }
}

if ($MyInvocation.InvocationName -eq '.') { return }

if (-not $Sdk) { $Sdk = $env:ANDROID_SDK_ROOT }
if (-not $Sdk) { throw 'Set ANDROID_HOME or pass -Sdk with the Android SDK path.' }
$extension = ''
if ($env:OS -eq 'Windows_NT') { $extension = '.bat' }
$analyzer = Join-Path $Sdk "cmdline-tools/latest/bin/apkanalyzer$extension"
$aaptName = 'aapt2'
if ($env:OS -eq 'Windows_NT') { $aaptName += '.exe' }
$aapt = Get-ChildItem (Join-Path $Sdk 'build-tools') -Directory |
    Where-Object { Test-Path (Join-Path $_.FullName $aaptName) } |
    Sort-Object { [version](($_.Name -split '-')[0]) } -Descending |
    Select-Object -First 1 |
    ForEach-Object { Join-Path $_.FullName $aaptName }
if (-not (Test-Path $analyzer) -or -not $aapt) {
    throw 'Install Android SDK command-line tools (latest) and build-tools.'
}
$DebugApk = (Resolve-Path $DebugApk).Path
$ReleaseApk = (Resolve-Path $ReleaseApk).Path
if ($DebugApk -eq $ReleaseApk) { throw 'Supply two distinct APK files.' }
$debug = Get-ApkManifest $DebugApk $analyzer $aapt
$release = Get-ApkManifest $ReleaseApk $analyzer $aapt
Assert-FeatureManifest $debug.Xml $false
Assert-FeatureManifest $release.Xml $true
if ((Get-CanonicalManifestNode $debug.Xml.DocumentElement $debug.Resources) -ne
    (Get-CanonicalManifestNode $release.Xml.DocumentElement $release.Resources)) {
    $differences = @(Get-ManifestDifferenceDetails `
        $debug.Xml.DocumentElement $debug.Resources `
        $release.Xml.DocumentElement $release.Resources)
    if ($differences.Count -eq 0) {
        $differences = @('Canonical forms differ, but no structural difference was found.')
    }
    $limit = 12
    $shown = @($differences | Select-Object -First $limit)
    $message = "Manifest feature configuration differs (manifest values redacted):`n  " +
        ($shown -join "`n  ")
    if ($differences.Count -gt $limit) {
        $message += "`n  ... $($differences.Count - $limit) more difference(s) not shown."
    }
    throw $message
}
Assert-AssetParity (Get-ApkAssets $DebugApk $false) (Get-ApkAssets $ReleaseApk $true)
Write-Output ('APK packaging parity passed: manifests, required features, Flutter assets and ABIs. ' +
    'Signing, device behavior and external API authorization require separate verification.')
