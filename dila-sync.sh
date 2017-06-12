#!/bin/zsh

script_dir=`dirname $0`
config_file="$script_dir/.dila-sync/config"
log_level=0
use_git=0
# This should be changed to provide a better support for watching mutliple parts
# of the stock. The script should use a list of directories and loop through
# them to execute the required git magic on all of them
# As of now, this only supports versionning a single directory
# which is admitedly a little bit limited...
# The path is relative to the script directory
git_watch_dir="stock/legi/global/code_et_TNC_en_vigueur/code_en_vigueur/LEGI/TEXT/00/00/06/07/40/LEGITEXT000006074068"

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
while getopts "hvg" option
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
		g)
			# Use git for versionning (Yolo style)
			use_git=1
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
	use_git $use_git
)

# Create .dila-sync if not already exisiting
mkdir -p "$script_dir/.dila-sync"

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

# $config[use_git] takes precedence over -g script option
# Since if we didn't initialized the stock with git, nothing
# git-related is going to work...
if [ $use_git -ne $config[use_git] ]
then
	if [ $use_git -eq 1 ]
	then
		echo "${txtylw}You asked to use git but dila-sync was previously initialized without git.${txtrst}"
		echo "${txtylw}Skipping git usage...${txtrst}"
	else
		echo "${txtylw}Dila-sync was initialized with git versionning.${txtrst}"
		echo "${txtylw}Please update .dila-sync/config if you do not wish to use git anymore.${txtrst}"
	fi
	echo
	use_git=$config[use_git]
fi

# Helpers
# -------

pv_installed=$(hash pv 2>/dev/null)

# Extract timestamp from a single filename
get_timestamp () {
	local name
	if [ -z $1 ]
	then
		read name
	else
		name=$1
	fi

	echo $name | sed 's/.*_\([0-9]\+-[0-9]\+\)\.tar\.gz/\1/' | sed 's/-//'
}

# Format timestamp to a mor human friendly format
format_timestamp () {
	local timestamp
	if [ -z $1 ]
	then
		read timestamp
	else
		timestamp=$1
	fi

	echo $timestamp | sed 's/^\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/'
}

# Print $1 message if last command exited with a non-zero code
# and exits with status 1 if so
command_status () {
	if [ $? -ne 0 ]
	then
		echo "${txtred}Error${txtrst}"
		echo "${error} $1"
		exit 1
	else
		echo "${txtgrn}Ok${txtrst} $2"
	fi
}

# Start
# -----

# Display a message if it's the first run
if [ -z $config[last_delta] -o $config[last_delta] -eq 0 ]
then
	cat <<-EOF
		${txtbld}First run${txtrst}
		It appears that you are running ${txtund}${txtbld}dila-sync${txtrst} for the first time.
		We need to download a fresh copy of the whole stock and the latest deltas.
		This might take some time... Enjoy your coffee!

	EOF
	local_stock_date=0

	# Additionnally display a warning if git is used for versionning
	if [ $use_git -ne 0 ]
	then
		cat <<-EOF
			${txtbld}Using Git${txtrst}
			${txtund}${txtbld}dila-sync${txtrst} is set up to use ${txtund}${txtbld}git${txtrst} for versionning.
			Git support is still experimental and shouldn't be provided for the whole stock.
			Instead, we should provide a way to explicitely set a list of sub-directories
			to be versionned as autonomous git repos.

			${txtund}${txtbld}TL,DR:${txtrst} I hope you didn’t set ${txtund}\$git_watch_dir${txtrst} to version everything...

		EOF
	fi
else
	local_stock_date=$config[last_delta]
	echo "${txtund}Local stock date:${txtrst} ${txtcyn}$(format_timestamp $local_stock_date)${txtrst}"
fi

remote=$config[remote]
debug "\n${txtund}Remote:${txtrst} ${txtcyn}$remote${txtrst}\n" 1

echo -n "Fetching stock index... "
wgetoutput=$(wget -T 10 -q -O - $remote)
command_status "Error while getting remote data."

# Now let's get only the actual urls
listing=$(echo $wgetoutput | grep -o 'href="[^"]*"' | sed 's/href="\([^"]*\)"/\1/g')
echo -n $txtcyn
echo "$( echo $listing | wc -l) files found"
echo $txtrst

# Get global stock filename
stock=$(echo $listing | grep -E "^${remote}Freemium_legi_global" | sed "s@$remote@@")
stock_date=$(get_timestamp $stock)
if [ $local_stock_date -eq 0 ]
then
	local_stock_date=$stock_date
fi

echo "${txtund}Global stock:${txtrst}"
echo "${txtcyn}$stock [$(format_timestamp $stock_date)]${txtrst}\n"

# Get deltas list
deltas=$(echo $listing | grep -E "^${remote}legi_" | sed "s@$remote@@g")

# Count them
if [ -z $deltas ]
then
	deltas_count=0
else
	deltas_count=$(echo $deltas | wc -l)
fi
[[ $deltas_count -eq 0 ]] && col="${txtpnk}" || col="${txtcyn}"
echo "${txtund}Deltas:${txtrst} ${col}$deltas_count${txtrst}"
echo "${txtund}Oldest:${txtrst} ${txtcyn}$(echo $deltas | head -n 1 | get_timestamp | format_timestamp)${txtrst}"
echo "${txtund}Latest:${txtrst} ${txtcyn}$(echo $deltas | tail -n 1 | get_timestamp | format_timestamp)${txtrst}"

# Debug deltas if not empty
if [ -n $deltas -a $deltas_count -gt 0 ]
then
	debug "${txtpnk}<deltas>\n${txtcyn}$deltas\n${txtpnk}</deltas>${txtrst} \n" 1
fi

# Filter out perished deltas
fresh_deltas=""
while read delta; do
	timestamp=$(get_timestamp $delta)
	if [ $timestamp -gt $local_stock_date ]
	then
		fresh_deltas="$fresh_deltas$delta\n"
	fi
done <<< "$deltas"
# Remove empty lines if any
fresh_deltas=$(echo $fresh_deltas | sed 's/^\s*$//g')

# Count them
if [ -z $fresh_deltas ]
then
	fresh_deltas_count=0
else
	# We have to add the ending newline since we removed any empty lines before
	fresh_deltas_count=$(echo $fresh_deltas | wc -l)
fi
[[ $fresh_deltas_count -eq 0 ]] && col="${txtpnk}" || col="${txtcyn}"
echo "${txtund}Fresh deltas:${txtrst} ${col}$fresh_deltas_count${txtrst}"

# Debug fresh deltas if not empty
if [ -n $fresh_deltas -a $fresh_deltas_count -gt 0 ]
then
	debug "${txtpnk}<fresh>\n${txtcyn}$fresh_deltas\n${txtpnk}</fresh>${txtrst} \n" 1
fi

# Global stock
# ------------
# If it's the first run we have to download and untar the global stock
if [ -z $config[last_delta] -o $config[last_delta] -eq 0 ]
then
	# Create .tmp if not already exisiting
	mkdir -p "$script_dir/.tmp"

	# Get the global stock
	echo
	echo "${info} Downloading global stock..."
	$(wget -N -T 10 -q --show-progress -P ./.tmp "${remote}Freemium_legi_global_*.tar.gz")
	command_status "Error while getting remote data."

	# Untar the global stock
	echo
	message="${info} Extracting global stock ${txtcyn}$stock...${txtrst}"
	# Create directory if not already exisiting
	mkdir -p "$script_dir/stock"

	if [ $log_level -gt 0 ]
	then
		echo $message
		tar -xzvf "$script_dir/.tmp/$stock" -C "$script_dir/stock"
		command_status "Error while extracting the global stock archive." "$stock unpacked, timestamp: ${txtylw}$stock_date${txtrst}"
	else
		if [ pv_installed ]
		then
			echo $message
			pv "$script_dir/.tmp/$stock" | tar -xzf - -C "$script_dir/stock"
			command_status "Error while extracting the global stock archive." "timestamp: ${txtylw}$stock_date${txtrst}"
		else
			echo -n $message
			tar -xzf "$script_dir/.tmp/$stock" -C "$script_dir/stock"
			command_status "Error while extracting the global stock archive." "timestamp: ${txtylw}$stock_date${txtrst}"
		fi
	fi

	# Save original stock_date and archive name in .dila-sync/
	echo "$stock_date	$stock">>"$script_dir/.dila-sync/stocks"

	if [ $use_git -gt 0 ]
	then
		# Init git repo
		echo "Initializing git repository with global stock [$stock_date]..."
		g=$(git init "$script_dir/$git_watch_dir" && git -C "$script_dir/$git_watch_dir" add . && git -C "$script_dir/$git_watch_dir" commit -m "Init with global stock [$stock_date]")
		# command_status "Error while initializing git repository"
	fi
fi

# Deltas
# ------
# Get fresh deltas and apply them if any
echo
if [ $fresh_deltas_count -eq 0 ]
then
	echo "${info} No fresh delta is available"
else
	echo "${info} Downloading $fresh_deltas_count fresh deltas..."
	$(echo $fresh_deltas | sed -e "s@^@$remote@g" | wget -N -T 10 -q --show-progress -P ./.tmp -i -)
	command_status "Error while getting remote data."

	# Be it the first run or another one, apply fresh deltas, sequentially
	current_delta=1
	while read delta; do
		echo
		timestamp=$(get_timestamp $delta)

		# We only care about deltas that are fresher
		if [ $timestamp -gt $local_stock_date ]
		then
			# Unpack archive
			message="${info} Unpacking delta $current_delta/$fresh_deltas_count: ${txtcyn}$delta...${txtrst} "
			if [ $log_level -gt 0 ]
			then
				echo $message
				tar -xzvf "$script_dir/.tmp/$delta" -C "$script_dir/stock" --strip-components 1
				command_status "Error while extracting delta archive $delta." "$delta unpacked, delta timestamp: ${txtylw}$timestamp${txtrst}"
			else
				if [ pv_installed ]
				then
					echo $message
					pv "$script_dir/.tmp/$delta" | tar -xzf - -C "$script_dir/stock" --strip-components 1
					command_status "Error while extracting delta archive $delta." "delta timestamp: ${txtylw}$timestamp${txtrst}"
				else
					echo -n $message
					tar -xzf "$script_dir/.tmp/$delta" -C "$script_dir/stock" --strip-components 1
					command_status "Error while extracting delta archive $delta." "delta timestamp: ${txtylw}$timestamp${txtrst}"
				fi
			fi

			# Delete perished files if any
			echo
			deletion_lists=$(find "$script_dir/stock" -maxdepth 1 -name 'liste_suppression*' -print)
			while read perished_files; do
				if [ -r "$perished_files" ]
				then
					echo "${info} Deleting perished files"
					while read perished
					do
						perished_filepath=$(echo $perished | sed 's@\(^.*\)/\([^/]\+\)$@\1@')
						perished_filename=$(echo $perished | sed 's@\(^.*\)/\([^/]\+\)$@\2@')
						file=$(find "$script_dir/stock/$perished_filepath" -maxdepth 1 -name "$perished_filename*" -print)
						if [ -z $file ]
						then
							debug "${warn} unable to find $script_dir/stock/$perished_filepath/$perished_filename*"
							debug "-> current line: $perished [in $perished_files]"
						else
							debug "deleting $file"
							rm "$file"
						fi
					done < "$perished_files"
					debug "deleting perished files list $perished_files"
					rm "$perished_files"
				else
					echo "${info} no perished files in delta"
				fi
			done <<< "$deletion_lists"

			# Save delta timestamp and archive name in .dila-sync/
			echo "$timestamp	$delta">>"$script_dir/.dila-sync/applied-deltas"

			if [ $use_git -gt 0 ]
			then
				# Commit in git repo
				echo "Commiting delta $current_delta/$fresh_deltas_count [$timestamp]..."
				g=$(git -C "$script_dir/$git_watch_dir" add -A && git -C "$script_dir/$git_watch_dir" commit -m "Apply delta [$timestamp]")
				# command_status "Error while comitting delta $current_delta/$fresh_deltas_count [$timestamp] in git repository"
			fi

			# Finally replace stock_date by the current delta timestamp
			local_stock_date=$timestamp

		# If current_delta is perished we just state it but don't process it
		else
			echo "${warn} Not processing perished delta $current_delta/$fresh_deltas_count: ${txtcyn}$delta${txtrst} "
			echo "delta timestamp: ${txtylw}$timestamp${txtrst}"
		fi

		# Next delta
		let current_delta++
	done <<< "$fresh_deltas"
fi

# Recap
# -----
echo
echo "${info} Up to date."
echo "${txtund}Deltas applied:${txtrst} ${col}$fresh_deltas_count${txtrst}"
echo "${txtund}Stock date:${txtrst} ${txtcyn}$(format_timestamp $local_stock_date)${txtrst}"

# We currently always save config infos.
# This might change in the future
cat <<-EOF > "$script_dir/.dila-sync/config"
	remote=$remote
	last_delta=$local_stock_date
	use_git=$use_git
EOF
