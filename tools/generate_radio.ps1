# Offline asset authoring only. No speech engine or microphone is used by the game.
Add-Type -AssemblyName System.Speech
$bl6Synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
$bl6Voice = $bl6Synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq 'en-US' } | Select-Object -First 1
if (-not $bl6Voice) { throw 'An English Windows speech voice is required to regenerate the optional radio recordings.' }
$bl6Synth.SelectVoice($bl6Voice.VoiceInfo.Name)
$bl6Synth.Rate = -1
$bl6Synth.Volume = 90
$bl6Output = Join-Path $PSScriptRoot '../.tools/radio_raw'
New-Item -ItemType Directory -Force -Path $bl6Output | Out-Null
$bl6Lines = [ordered]@{
    radio_arrival = 'Sector Six lost telemetry forty minutes ago. Check the operations terminal. We will monitor your progress from upstairs.'
    radio_power = 'Power has returned. The overnight team may be in the cooling gallery. Restore circulation before reconnecting the network.'
    radio_cooling = 'We have your pressure readings. You are the only technician currently assigned to this level.'
    radio_network = 'Do not reconnect the network. That maintenance order was withdrawn. Can you hear me? Do not reconnect.'
    radio_core = 'This is a containment system. They turned it off on purpose. Your work order was issued from inside Sector Six.'
    radio_escape = 'The elevator is responding. Release the brake in electrical. Purge the lift line in cooling. Return to the lift. Keep moving.'
}
try {
    foreach ($bl6Pair in $bl6Lines.GetEnumerator()) {
        $bl6Synth.SetOutputToWaveFile((Join-Path $bl6Output ($bl6Pair.Key + '.wav')))
        $bl6Synth.Speak($bl6Pair.Value)
        $bl6Synth.SetOutputToNull()
        Write-Output ('Recorded ' + $bl6Pair.Key)
    }
} finally { $bl6Synth.Dispose() }
