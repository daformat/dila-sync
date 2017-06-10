#!/bin/zsh

log_level=0
script_dir=`dirname $0`
config_file="$script_dir/.dila-sync/config"

# Text color variables
txtred=$(tput setaf 1) #  red
txtgrn=$(tput setaf 2) #  green
txtylw=$(tput setaf 3) #  yellow
txtprp=$(tput setaf 4) #  purple
txtpnk=$(tput setaf 5) #  pink
txtcyn=$(tput setaf 6) #  cyan
txtwht=$(tput setaf 7) #  white

# Text modifiers
txtund=$(tput sgr 0 1)  # Underline
txtbld=$(tput bold)     # Bold
txtrst=$(tput sgr0)     # Reset

# Feedback helpers
info="${txtbld}${txtcyn}[i]${txtrst}"
warn="${txtbld}${txtylw}[!]${txtrst}"
error="${txtbld}${txtred}[!]${txtrst}"
ques="${txtbld}${txtpnk}[?]${txtrst}"
ok="${txtbld}${txtgrn}[ok]${txtrst}"

usage () {
	cat <<-EOF
		${txtbld}dila-sync${txtrst}
		Synchronize DILA’s Legifrance data
	EOF
}

# Call debug "Your message" [log_level]
# Where log_level is a number to be match against the current log level
debug () {
	# echo "Log level: $log_level"
	if [ -z $2 ]
	then
		echo $1
	elif [ $2 -le $log_level ]
	then
		echo $1
	fi
}

# Script Options
while getopts "hv" option
do
	case "$option" in
		h)
			# Help, display usage
			usage
			exit
			;;
		v)
			# Verbosity
			log_level=$((log_level+1))
			;;
		*)
			usage >&2
			exit 1
			;;
		?)
			# no options was given
			;;
	esac
done

# Shift off the options and optional --
shift "$((OPTIND-1))"

# Config
# ------

typeset -A config

# Default config
config=(
  remote "ftp://ftp2.journal-officiel.gouv.fr:21/LEGI/"
)

# Try to read config
if [ -r $config_file ]
then
  while read line
  do
    if echo $line | grep -F = &>/dev/null
    then
      varname=$(echo "$line" | cut -d '=' -f 1)
      config[$varname]=$(echo "$line" | cut -d '=' -f 2-)
    fi
  done < $config_file
fi

# Helpers
# -------

# Start
# -----

# Display a message if it's the first run
if [ -z $config[last_sync] ]
then
	cat <<-EOF
		${txtbld}First run${txtrst}
		It appears that you are running ${txtund}${txtbld}dila-sync${txtrst} for the first time.
		We need to download a fresh copy of the whole stock and the latest deltas.
		This might take some time... Enjoy your coffee!

	EOF
fi

remote=$config[remote];
debug "\n${txtund}Remote:${txtrst} $remote\n" 1

echo -n "Fetching stock index... "
wgetoutput=$(wget -q -O - $remote)

if [ $? -ne 0 ]
then
	echo "${txtred}Error${txtrst}"
	echo "${error} Error while getting remote data."
else
	echo "${txtgrn}Ok${txtrst}"
fi

# Now let's get only the actual urls
listing=$(echo $wgetoutput | grep -o 'href="[^"]*"' | sed 's/href="\([^"]*\)"/\1/g')
echo -n $txtcyn
echo "$( echo $listing | wc -l) files found"
echo $txtrst

# Get global stock filename
stock=$(echo $listing | grep -E "^${remote}Freemium_legi_global")
echo "${txtund}Global stock:${txtrst}"
echo "${txtcyn}$stock${txtrst} \n"

# Get deltas
deltas=$(echo $listing | grep -E "^${remote}legi_" )
deltas_count=$( echo $deltas | wc -l)
echo "${txtund}Deltas:${txtrst} $deltas_count"
debug "${txtcyn}$deltas${txtrst} \n" 1

# Is it the first run?
if [ -z $config[last_sync] ]
then
	echo
	echo "${info} Downloading global stock..."
	$(wget -N -q --show-progress -P ./stock "${remote}Freemium_legi_global_*.tar.gz")

	echo
	echo "${info} Downloading all $deltas_count deltas..."
	$(wget -N -q --show-progress -P ./deltas "${remote}legi*.tar.gz")
	if [ $? -ne 0 ]
	then
		echo "${txtred}Error${txtrst}"
		echo "${error} Error while getting remote data."
	else
		echo "${txtgrn}Ok${txtrst}"
	fi
else
	echo "Not the first run?"
fi
