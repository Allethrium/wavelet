#!/bin/bash

tail -fn0 logfile | \
while read line ; do
        echo "$line" | grep "pattern"
        if [ $? = 0 ]
        then
                ... do something ...
        fi
done

