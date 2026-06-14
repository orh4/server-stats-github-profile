#!/bin/bash

### VALUES ###

# The default is your router's IP, but it can be changed (eg. 1.1.1.1 or google.com)
PING_IP=192.168.1.1
PING_WAIT_TIME=1
PING_COUNT=5

# Gets the current date and time (adds it to the JSON output.)
CURRENT_TIME=$(date +"%d/%m/%Y @ %H:%M:%S UTC")

# The path to the repo/directory that will be pushed to GitHub.
REPO_PATH="/home/your/repo/name"
# Path as to where the converted JSON output will be saved.
JSON_PATH="$REPO_PATH/stats.json"
# Path as to where the badge-friendly JSON output will be saved.
BADGES_JSON_PATH="$REPO_PATH/badges_stats.json"

# The commit message the script will send out.
COMMIT_MSG="[AUTOMATED] updated: $(date +"%Y/%m/%d @ %H:%M:%S")"

### DEBUG MESSAGES ###

UPTIME_GET_MSG="getting uptime..."
CPU_TEMP_GET_MSG="getting cpu temperature..."
BATTERY_PERCENTAGE_GET_MSG="getting battery percentage..."
BATTERY_TIME_LEFT_MSG="getting battery time left..."
ENERGY_RATE_GET_MSG="getting energy-rate..."
PING_GET_MSG="getting ping... [ip: $PING_IP, count = $PING_COUNT, wait-time = $PING_WAIT_TIME second(s)]"

### STATS ###
# You can comment-out stats you don't want to display.

# CPU TEMPERATURE (default is thermal_zone0)
echo $CPU_TEMP_GET_MSG
CPU_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
CPU_TEMP=$((CPU_TEMP / 1000))

# The energy-rate (wattage) of the server (WHEN RUNNING ON BATTERY).
echo $ENERGY_RATE_GET_MSG
ENERGY_RATE=$(upower -b | awk '/energy-rate/ {print $2}')
ENERGY_RATE="$ENERGY_RATE W"

# The battery's percentage.
echo $BATTERY_PERCENTAGE_GET_MSG
BATTERY_PERCENTAGE=$(upower -b | awk '/percentage/ {print $2}')

echo $BATTERY_TIME_LEFT_MSG
BATTERY_TIME_LEFT=$(upower -b | awk '/time to empty/ {print $4}')

# The total uptime (how long the server has been on) of the device.
echo $UPTIME_GET_MSG
UPTIME=$(uptime -p | cut -b 4-)

# The average router ping latency (in miliseconds).
echo $PING_GET_MSG
LATENCY=$(ping -4 -W $PING_WAIT_TIME -c $PING_COUNT $PING_IP | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
LATENCY="$LATENCY ms"

### VERIFYING ###

# The array "stats" holds all the variable names.
STATS=(
	"CPU_TEMP"
	"ENERGY_RATE"
	"BATTERY_PERCENTAGE"
	"BATTERY_TIME_LEFT"
	"UPTIME"
	"LATENCY"
)

# This for loop iterates over the array "stats" and hence checks each variable if their respective values are non-empty, empty, or if the variable is not defined (commented out) respectively.
for VALUE in "${STATS[@]}"
do	
	# Checks if the value of the variable is non-empty / nil / undefined.
	# If value doesn't exist.
	if [[ ! -v $VALUE ]]; then
		echo UNDEFINED: The variable $VALUE does not exist.
		continue
	fi
	
	# If variable ENERGY_RATE is equal to zero (when server in on AC power, or when it is charging.)
	if [ $VALUE = "ENERGY_RATE" ]; then
		if [ "${!VALUE}" = 0 ]; then
			echo ON AC: The variable $VALUE is zero as the device is currently plugged in.
			ENERGY_RATE="[PLUGGED IN]"
		fi

		if [ $(upower -b | awk '/state/ {print $2}') = "charging" ]; then
			ENERGY_RATE="$ENERGY_RATE [PLUGGED IN]"
		fi	
	fi
	
	# If variable BATTERY_TIME_LEFT is equal to zero (when it is plugged in.)
	if [ $VALUE = "BATTERY_TIME_LEFT" ]; then
		if [ -z ${!VALUE} ]; then
			echo ON AC: The variable $VALUE is nil as the device is currently plugged in.
			BATTERY_TIME_LEFT="[PLUGGED IN]"
			continue
		else
			BATTERY_TIME_LEFT="$BATTERY_TIME_LEFT hours"
		fi
	fi
	
	# VERIFICATION (it iterates over the array "STATS".)
	if [ -n "${!VALUE}" ]; then
		echo "- got $VALUE!"
		echo "${!VALUE}"
	# If value is nil / empty.
	else
		echo NIL: The variable $VALUE has no value or has encountered an error.
	fi
done

### JSON FORMAT ###

# Outputs the values of each stat into a JSON format.
JSON_STRING=$(cat <<EOF
{
	"last_updated":"$CURRENT_TIME",
	"cpu_temperature":"$CPU_TEMP°C",
	"energy_rate":"$ENERGY_RATE",
	"battery_percentage":"$BATTERY_PERCENTAGE",
	"battery_time_left":"$BATTERY_TIME_LEFT",
	"uptime":"$UPTIME",
	"latency":"$LATENCY"
}
EOF
)

# Makes the file in the specified directory (also makes the directory if not already made.)
mkdir -p "$(dirname "$JSON_PATH")"

# Outputs the converted JSON output into the specified JSON path.
echo "$JSON_STRING" > "$JSON_PATH"
echo "$JSON_STRING" > "$BADGES_JSON_PATH"

sed -i "s|%|%25|g" $BADGES_JSON_PATH
sed -i "s|, |%2C%20|g" $BADGES_JSON_PATH
sed -i "s| |%20|g" $BADGES_JSON_PATH

# Just echoes/outputs the specified JSON path.
echo "saved to: $JSON_PATH"
cat $JSON_PATH

### GIT PUSH ###

cat template.md > README.md

cd "$REPO_PATH" || exit 1

# Checks if there are any differences between the local repo/directory and the repo up on GitHub.
# The tag "--quiet" makes the whole "git diff" return only an exit code. 0 is there are no changes, and 1 if there are changes.
# The "!" before the command inverts the output exit code. (i.e. If there is a change in the file, it will output the exit code 1, which then gets inverted into a 0, running the commands in the below if statement.)
# In shell, and exit code "0" marks a "true" value while an exit code "1" marks a "false" value.
git stash --quiet

git pull origin main --rebase --quiet

git stash pop --quiet

if ! git diff --quiet stats.json; then
	# Adds the given output JSON into the commit.
	git add stats.json
	git add badges_stats.json

	cat template.md > README.md
	git add README.md

	# Adds the configured commit message (configured via setting the "COMMIT_MSG" variable.)
	git commit -m "$COMMIT_MSG"
	
	# Pushes the commit to GitHub from origin (local files) to main (main branch on GitHub) and specifies where it got pushed to.
	if git push origin main 2>&1; then
		echo "pushed to configured github repo."
	else
		echo "push failed. remote may have new commits."
	fi
else
	echo "no changes to commit."
fi

