#!/bin/bash
# Dialog driven interface for recording AWIPS screens with ffmpeg
# jacob.wimberley, WFO GSP, 2017-09-28 original version
#                           2017-11-21 various improvements

function ExitIfCancelled () {
if [ $? -ne 0 ]
then
	exit 1
fi
}

filename=`zenity --entry --text "Enter video file name. DO NOT include the extension (.mp4)" --title "Desktop recorder"`
ExitIfCancelled
dirname=`zenity --file-selection --directory --title="Choose a directory in which to save your video"`
ExitIfCancelled

if [[ `hostname` =~ "lx" ]]
then
	screen=`zenity --list --title "Desktop recorder" --text="Which screen do you want to record?" --radiolist --column "" --column "Monitor" L Left M Middle R Right`
	ExitIfCancelled
	if [ $screen == "Left" ]
	then
		video_size="1280x1024"
		ii=":0.0+0,150"
	elif [ $screen == "Middle" ]
	then
		video_size="2560x1440"
		ii=":0.0+1280,0"
	else
		video_size="2560x1440"
		ii=":0.0+3840,0"
	fi

else
	video_size="2560x1440"
	ii=":0.0+0,0"
fi

cmd="ffmpeg -video_size $video_size -framerate 25 -f x11grab -i $ii -f pulse -ac 2 -i default -strict -2 $dirname/$filename.mp4"
echo $cmd
zenity --info --text="Get your screen ready to record. Put on your headset.\\nWhen you click Begin, a terminal window will appear, and once data start scrolling in that window, the recording has started.\\nClick in that terminal window and press the Q key when you want to stop recording." --title="Desktop recorder" --ok-label="Begin"
xterm -T "Click here and press q to end recording" -e $cmd
if [ $? -ne 0 ]
then
        exit 0
fi
resize=`zenity --list --title "Desktop recorder" --text="Your file was saved to $dirname/$filename.mp4.\\nDo you want to make a resized version for social media?" --radiolist --column "" --column "Size" N "Do not resize" 1920x1080 "Medium (HDTV quality)" 1280x720 "Small (Phone quality)"`
if [ "$resize" == "Medium (HDTV quality)" ]
then
	video_resize="1920:1080"
elif [ "$resize" == "Small (Phone quality)" ]
then
	video_resize="1280:720"
else
	exit 0
fi
rcmd="ffmpeg -i $dirname/$filename.mp4 -vf scale=$video_resize -strict -2 $dirname/${filename}_small.mp4"
echo $rcmd
xterm -T "Resizing..." -e $rcmd
zenity --info --no-wrap --title="Desktop video resized" --text="Your resized video is at $dirname/${filename}_small.mp4"
