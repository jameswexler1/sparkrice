#!/bin/bash

echo "Auto-clicker toggle script"
echo "Press 'c' to start/stop clicking. Press 'q' to quit."

clicking=0

while true; do
    read -rsn1 key
    if [[ $key == "c" ]]; then
        if [[ $clicking -eq 0 ]]; then
            echo "Clicking started (every 5s)..."
            clicking=1
            while [[ $clicking -eq 1 ]]; do
                xdotool click 1
                sleep 5
                # Check if 'c' was pressed again (non-blocking)
                read -rsn1 -t 0.1 key2
                if [[ $key2 == "c" ]]; then
                    clicking=0
                    echo "Clicking stopped."
                    break
                fi
            done
        else
            clicking=0
            echo "Clicking stopped."
        fi
    elif [[ $key == "q" ]]; then
        echo "Quitting."
        break
    fi
done
