#	This is the windows equivalent of run_ug.sh 
#	Should be called by TaskMan
#	Register self by injecting hostname/IP keypair to ETCD.


$localip = Get-NetIPAddress
$body = @ {
	"siteURL"				=	"http://192.168.1.32:2379/v3/kv/range"
	"decoderWinHostname"	=	decoderip/$env:computername.wavelet.local
	"decoderWinIP"			=	$localip
}
Invoke-WebRequest -Mehod 'Post' -Uri $siteURL -Body ($body|ConertTo-Json) -Headers $headers -ContentType "application/json"


# launch UG with error detection and auto restart in fullscreen mode
.\uv.exe -d:fs vulkan_sdl2