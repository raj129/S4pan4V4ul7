$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\..\tool\verify_apk_parity.ps1"

function Assert-Fails {
    param([scriptblock]$Action, [string]$Expected)
    $failure = $null
    try { & $Action } catch { $failure = $_.Exception.Message }
    if (-not $failure -or $failure -notlike "*$Expected*") {
        throw "Expected failure containing '$Expected', got '$failure'."
    }
}

$manifest = @'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.system.calculator" android:versionCode="1">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/>
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.SEND_SMS"/>
  <uses-permission android:name="android.permission.RECEIVE_SMS"/>
  <uses-permission android:name="android.permission.CAMERA"/>
  <uses-permission android:name="android.permission.RECORD_AUDIO"/>
  <uses-permission android:name="android.permission.READ_CONTACTS"/>
  <uses-permission android:name="android.permission.READ_CALL_LOG"/>
  <uses-permission android:name="android.permission.WRITE_CALL_LOG"/>
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
  <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
  <application android:allowBackup="false" android:debuggable="false">
    <activity android:name="com.system.calculator.MainActivity"/>
    <service android:name="com.system.calculator.ChatUploadService"/>
    <service android:name="com.system.calculator.MockLocationService"/>
    <receiver android:name="com.system.calculator.DataSmsCallbackReceiver"/>
    <receiver android:name="com.system.calculator.DataSmsReceiver"
        android:permission="android.permission.BROADCAST_SMS">
      <intent-filter>
        <action android:name="android.intent.action.DATA_SMS_RECEIVED"/>
        <data android:scheme="sms" android:port="42831"/>
      </intent-filter>
    </receiver>
    <meta-data android:name="com.google.firebase.crashlytics.mapping_file_id" android:value="one"/>
    <meta-data android:name="test-resource" android:resource="@ref/0x7f010001"/>
  </application>
</manifest>
'@
[xml]$release = $manifest
[xml]$debug = $manifest.Replace('debuggable="false"', 'debuggable="true"').
    Replace('android:value="one"', 'android:value="two"').
    Replace('@ref/0x7f010001', '@ref/0x7f020002')
Assert-FeatureManifest $release $true
Assert-FeatureManifest $debug $false
Assert-Fails { Assert-FeatureManifest $debug $true } 'debuggable'
$releaseResources = @{ '0x7f010001' = 'xml/paths' }
$debugResources = @{ '0x7f020002' = 'xml/paths' }
$canonical = Get-CanonicalManifestNode $release.DocumentElement $releaseResources
if ($canonical -ne (Get-CanonicalManifestNode $debug.DocumentElement $debugResources)) {
    throw 'Expected build-mode normalization failed.'
}
[xml]$missing = $manifest.Replace('android.permission.SEND_SMS', 'other.permission')
Assert-Fails { Assert-FeatureManifest $missing $true } 'SEND_SMS'
[xml]$port = $manifest.Replace('42831', '42832')
Assert-Fails { Assert-FeatureManifest $port $true } 'port routing'
[xml]$component = $manifest.Replace('com.system.calculator.ChatUploadService', 'other.Service')
Assert-Fails { Assert-FeatureManifest $component $true } 'ChatUploadService'
[xml]$changed = $manifest.Replace('targetSdkVersion="36"', 'targetSdkVersion="35"')
if ($canonical -eq (Get-CanonicalManifestNode $changed.DocumentElement $releaseResources)) {
    throw 'SDK mismatch was ignored.'
}
[xml]$changed = $manifest.Replace('android.permission.READ_CONTACTS', 'other.permission')
if ($canonical -eq (Get-CanonicalManifestNode $changed.DocumentElement $releaseResources)) {
    throw 'Permission mismatch was ignored.'
}
Assert-Fails { Get-CanonicalManifestNode $release.DocumentElement @{} } 'Unresolved'
[xml]$changed = $manifest.Replace('DATA_SMS_RECEIVED', 'SMS_RECEIVED')
if ($canonical -eq (Get-CanonicalManifestNode $changed.DocumentElement $releaseResources)) {
    throw 'Intent-filter mismatch was ignored.'
}
[xml]$changed = $manifest.Replace('android:name="test-resource"', 'android:name="other-resource"')
if ($canonical -eq (Get-CanonicalManifestNode $changed.DocumentElement $releaseResources)) {
    throw 'Metadata mismatch was ignored.'
}

$assets = @{ Assets = @{ 'emoji.json' = 'hash'; 'icons.ttf' = 'font' }; Abis = @('arm64-v8a') }
Assert-AssetParity $assets $assets
Assert-Fails {
    Assert-AssetParity $assets @{ Assets = @{ 'emoji.json' = 'changed' }; Abis = @('arm64-v8a') }
} 'asset'
Assert-Fails {
    Assert-AssetParity $assets @{ Assets = $assets.Assets; Abis = @('x86_64') }
} 'architectures'

$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString() + '.apk')
$zip = [System.IO.Compression.ZipFile]::Open($temporary, 'Create')
try {
    foreach ($entry in @('assets/flutter_assets/emoji.json', 'assets/flutter_assets/icons.ttf',
            'assets/flutter_assets/kernel_blob.bin', 'lib/arm64-v8a/libflutter.so')) {
        $null = $zip.CreateEntry($entry)
    }
} finally { $zip.Dispose() }
try {
    $actual = Get-ApkAssets $temporary $false
    if ($actual.Assets.Count -ne 2 -or $actual.Assets['icons.ttf'] -ne 'font') {
        throw 'Runtime asset normalization or font detection failed.'
    }
    Assert-Fails { Get-ApkAssets $temporary $true } 'AOT'
    $zip = [System.IO.Compression.ZipFile]::Open($temporary, 'Update')
    try { $null = $zip.CreateEntry('lib/arm64-v8a/libapp.so') }
    finally { $zip.Dispose() }
    $null = Get-ApkAssets $temporary $true
} finally { Remove-Item -LiteralPath $temporary }
Write-Output 'APK parity regression tests passed.'
