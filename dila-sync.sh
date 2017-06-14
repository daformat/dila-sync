#!/bin/zsh

script_dir=`dirname $0`
conf_dir="$script_dir/.dila-sync"
config_file="$conf_dir/config"
log_level=0
use_git=0
is_first_run=1
# If you want to use git to version the deltas you must create a
# .dila-sync-gitwatch text file listing every directory to be versioned
# with a single path per line, paths are relative to script directory
watch_dirs_file="$script_dir/.dila-sync-gitwatch"
if [ -r "$watch_dirs_file" ]
then
	git_watch_dirs=$(cat $watch_dirs_file)
	git_watch_dirs_count=$(echo $git_watch_dirs | wc -l)
fi

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
while getopts "hvgl:" option
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
			# Use git for versioning (Yolo style)
			use_git=1
			;;
		l)
			# Limit wget download rate (see wget's --limit-rate option)
			limit_wget_rate=$OPTARG
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
	remote "ftp://ftp2.journal-officiel.gouv.fr:21/"
	use_git $use_git
)

# Create .dila-sync if not already exisiting
mkdir -p "$conf_dir"
# Create .tmp if not already exisiting
mkdir -p "$script_dir/.tmp"

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
	# So then, it's not the first run anymore
	is_first_run=0
fi

remote=$config[remote]

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
		echo "${txtylw}Dila-sync was initialized with git versioning.${txtrst}"
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
		echo "${txtred}${txtbld}Error${txtrst}"
		echo "${error} $1"
		exit 1
	else
		echo "${ok} $2"
	fi
}

get_applied_deltas_for_stock () {
	if [ -r "$conf_dir/applied-deltas" ]
	then
		cat "$conf_dir/applied-deltas" | grep "	${1}_" | cut -f1 | sed 's/^\s*$//g'
	fi
}

get_last_global_import_for_stock () {
	if [ -r "$conf_dir/stocks" ]
	then
		cat "$conf_dir/stocks" | grep "	Freemium_${1}_" | tail -n1 | cut -f1 | sed 's/^\s*$//g'
	fi
}

limit_rate_opts () {
	if [ -n "${limit_wget_rate}" ]
	then
		echo -n "--limit-rate=$limit_wget_rate"
	fi
}


# Start
# -----

# First run
# ---------
# create config file and display a few messages
if [ $is_first_run -eq 1 ]
then
	# Save config file
	cat <<-EOF > "$conf_dir/config"
		remote=$remote
		use_git=$use_git
	EOF

	# First run message
	cat <<-EOF
		${txtbld}First run${txtrst}
		It appears that you are running ${txtund}${txtbld}dila-sync${txtrst} for the first time.
		We will need to download a fresh copy of the whole stock(s) and the latest deltas.
		This might take some time... Enjoy your coffee!

	EOF

	# Additionnally display a warning if git is used for versioning
	if [ $use_git -ne 0 ]
	then
		if [ -z $git_watch_dirs ]
		then
			cat <<-EOF
				${txtbld}Using Git${txtrst}
				${txtund}${txtbld}dila-sync${txtrst} is set up to use ${txtund}${txtbld}git${txtrst} for versioning.
				However, no .dila-sync-gitwatch file was found in the script directory.
				Since versioning the whole stock is a bad idea, ${txtund}git versioning will be disabled${txtrst}.

			EOF
			use_git=0
		else
			cat <<-EOF
				${txtbld}Using Git${txtrst}
				${txtund}${txtbld}dila-sync${txtrst} is set up to use ${txtund}${txtbld}git${txtrst} for versioning.
				$git_watch_dirs_count directories are to be versioned.

			EOF
		fi
	fi
fi

stocks_to_sync="";

# On every stock_to_sync
# ----------------------

for stock_to_sync in "$@"
do
	# convert stock to lowercase
	stock_to_sync=$(echo "$stock_to_sync" | tr '[:upper:]' '[:lower:]')
	stocks_to_sync="$stocks_to_sync$stock_to_sync\n"

	stock_info="${txtpnk}${txtbld}[$stock_to_sync]${txtrst}"
	echo "${info} ${txtylw}${txtbld}Synchronizing ${stock_info}"
	echo

	stock_remote="${remote}$(echo $stock_to_sync | tr '[:lower:]' '[:upper:]')/"
	stock_git_watch_dirs=$(echo $git_watch_dirs | grep -E "^\./stock/$stock_to_sync")
	stock_git_watch_dirs_count=$(echo $git_watch_dirs | grep -E "^\./stock/$stock_to_sync" | wc -l)

	local_stock_date=0
	local_stock_date_info="no delta applied yet"
	is_first_run=1

	# We first check if any delta was applied
	applied_deltas=$(get_applied_deltas_for_stock $stock_to_sync)
	applied_deltas_count=$(echo $applied_deltas | grep -E "^\d.*" | wc -l)
	if [ $applied_deltas_count -gt 0 ]
	then
		# If we already applied delta on the current stock_to_sync, use the last one
		local_stock_date_info="$applied_deltas_count delta$([[ $applied_deltas_count -gt 1 ]] && echo "s") applied since import"
		local_stock_date=$(echo $applied_deltas | tail -n1 | cut -f1)
		is_first_run=0
	else
		# Determine local stock date from stock if no delta was already applied
		if [ $(get_last_global_import_for_stock $stock_to_sync | wc -l) -gt 0 ]
		then
			local_stock_date=$(get_last_global_import_for_stock $stock_to_sync)
			is_first_run=0
		fi
	fi

	# At this point if we were unable to find any local_stock_date, it's the
	# first run on the current $stock_to_sync
	if [ $is_first_run -eq 1 ]
	then
		# Stock first run message
		cat <<-EOF
			${txtbld}First sync${txtrst} ${stock_info}
			We need to download a fresh copy of the ${stock_to_sync} stock and the latest deltas.
			This might take some time... Enjoy your coffee!

		EOF
	fi

	if [ $use_git -gt 0 -a $stock_git_watch_dirs_count -gt 0 ]
	then
		cat <<-EOF
			${txtbld}Using Git${txtrst}
			${txtund}${txtbld}dila-sync${txtrst} is set up to use ${txtund}${txtbld}git${txtrst} for versioning.
			$stock_git_watch_dirs_count directories are to be versioned for the stock $stock_to_sync.

		EOF
		debug "${txtpnk}<git-watch>\n${txtcyn}$stock_git_watch_dirs\n${txtpnk}</git-watch>${txtrst} \n" 1
	fi

	# Display local stock date if we already have some local stock
	if [ -n $local_stock_date -a $local_stock_date -gt 0 ]
	then
		echo "${txtund}Local stock date:${txtrst} ${txtcyn}$(format_timestamp $local_stock_date)${txtrst} ($local_stock_date_info)"
		echo
	fi

	# Fetch stock and deltas list from remote
	# ---------------------------------------
	debug "\n$stock_info ${txtund}Remote:${txtrst} ${txtcyn}$remote${txtrst}" 1
	debug "$stock_info ${txtund}Stock remote:${txtrst} ${txtcyn}$stock_remote${txtrst}\n" 1

	echo -n "$stock_info Fetching stock and deltas... "
	wgetoutput=$(wget $(limit_rate_opts) -T 10 -q -O - $stock_remote)
	command_status "Error while getting remote data."

	# Now let's get only the actual urls
	listing=$(echo $wgetoutput | grep -o 'href="[^"]*"' | sed 's/href="\([^"]*\)"/\1/g')
	echo -n $txtcyn
	echo "$( echo $listing | wc -l) files found"
	echo $txtrst

	# Get global stock filename
	stock=$(echo $listing | grep -E "^${stock_remote}Freemium_${stock_to_sync}_" | sed "s@$stock_remote@@")
	stock_date=$(get_timestamp $stock)
	if [ $local_stock_date -eq 0 ]
	then
		local_stock_date=$stock_date
	fi

	echo "${txtund}Global stock:${txtrst}"
	echo "${txtcyn}$stock [$(format_timestamp $stock_date)]${txtrst}\n"

	# Get deltas list
	deltas=$(echo $listing | grep -E "^${stock_remote}${stock_to_sync}_" | sed "s@${stock_remote}@@g")

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
	if [ $is_first_run -eq 1 ]
	then

		# Get the global stock
		echo
		echo "$stock_info Downloading global stock..."
		$(wget $(limit_rate_opts) -N -T 10 -q --show-progress -P ./.tmp "${stock_remote}${stock}")
		command_status "Error while getting remote data."

		# Untar the global stock
		echo
		message="$stock_info Extracting global stock ${txtcyn}$stock...${txtrst}"
		# Create directory if not already exisiting
		mkdir -p "$script_dir/stock"

		# On global stocks we have to do a pre-check to see if we need to strip_components
		# "cass", "capp", "inca" are two examples of stocks containing a timestamp
		# as their root folder
		strip_components=$(tar -tzf "$script_dir/.tmp/$stock" | head -n1 | grep -E "^\d{8}-\d{6}/$" | wc -l)
		[[ strip_components -gt 0 ]] && echo "${stock_info} ${warn} The archive's root folder containes a timestamp, it will be stripped upon extraction"

		if [ $log_level -gt 0 ]
		then
			echo $message
			tar -xzvf "$script_dir/.tmp/$stock" -C "$script_dir/stock" --strip-components $strip_components
			command_status "$stock_info Error while extracting the global stock archive." "$stock unpacked, timestamp: ${txtylw}$stock_date${txtrst}"
		else
			if [ pv_installed ]
			then
				echo $message
				pv "$script_dir/.tmp/$stock" | tar -xzf - -C "$script_dir/stock" --strip-components $strip_components
				command_status "$stock_info Error while extracting the global stock archive." "timestamp: ${txtylw}$stock_date${txtrst}"
			else
				echo -n $message
				tar -xzf "$script_dir/.tmp/$stock" -C "$script_dir/stock" --strip-components $strip_components
				command_status "$stock_info Error while extracting the global stock archive." "timestamp: ${txtylw}$stock_date${txtrst}"
			fi
		fi

		# Using git
		if [ $use_git -gt 0 -a $stock_git_watch_dirs_count -gt 0 ]
		then
			# Init git repo
			if [ $stock_git_watch_dirs_count -eq 1 ]
			then
				git_msg="Initializing 1 git repository with global stock [$stock_date]..."
			else
				git_msg="Initializing $stock_git_watch_dirs_count git repositories with global stock [$stock_date]..."
			fi
			echo
			echo "$stock_info $git_msg"

			i=1
			while read git_watch_dir; do
				git_msg="[$i/$stock_git_watch_dirs_count] ${txtcyn}git init $git_watch_dir${txtrst}"
				if [ $log_level -gt 0 ]
				then
					# display a new line for each git repo if in verbose mode
					debug $git_msg
				else
					# Replace previous line if not in verbose mode
					echo -n "\r\033[K$git_msg"
				fi
				g=$(git init "$script_dir/$git_watch_dir" && git -C "$script_dir/$git_watch_dir" add . && git -C "$script_dir/$git_watch_dir" commit -m "Init with global stock [$stock_date]")
				# command_status "Error while initializing git repository"
				let i++
			done <<< "$stock_git_watch_dirs"

			# Print a newline if we didn't print any during the loop (eg. log_level=0)
			# Delete last line if we're not in verbose mode
			[[ $log_level -eq 0 ]] && echo -n "\r\033[K"
			echo "${ok} Done comitting global stock"
		fi

		# Done with global stock
		# Save original stock timestamp and archive name in .dila-sync/stocks
		echo "$stock_date	$stock">>"$conf_dir/stocks"
	fi

	# Deltas
	# ------
	# Get fresh deltas and apply them if any
	echo
	if [ $fresh_deltas_count -eq 0 ]
	then
		echo "$stock_info No fresh delta is available"
	else
		echo "$stock_info Fetch and apply $fresh_deltas_count fresh deltas..."

		# Fetch and apply fresh deltas, sequentially
		current_delta=1
		while read delta; do
			echo
			timestamp=$(get_timestamp $delta)

			# We only care about deltas that are fresher than our local stock
			if [ $timestamp -gt $local_stock_date ]
			then
				echo "$stock_info Downloading delta $current_delta/$fresh_deltas_count: ${txtcyn}$delta...${txtrst} "
				$(echo $delta | sed -e "s@^@$stock_remote@g" | wget $(limit_rate_opts) -N -T 10 -q --show-progress -P ./.tmp -i -)
				command_status "Error while getting remote data."
				echo

				# Unpack archive
				message="$stock_info Unpacking delta $current_delta/$fresh_deltas_count: ${txtcyn}$delta...${txtrst} "
				if [ $log_level -gt 0 ]
				then
					echo $message
					tar -xzvf "$script_dir/.tmp/$delta" -C "$script_dir/stock" --strip-components 1
					command_status "$stock_info Error while extracting delta archive $delta." "$delta unpacked, delta timestamp: ${txtylw}$timestamp${txtrst}"
				else
					if [ pv_installed ]
					then
						echo $message
						pv "$script_dir/.tmp/$delta" | tar -xzf - -C "$script_dir/stock" --strip-components 1
						command_status "$stock_info Error while extracting delta archive $delta." "delta timestamp: ${txtylw}$timestamp${txtrst}"
					else
						echo -n $message
						tar -xzf "$script_dir/.tmp/$delta" -C "$script_dir/stock" --strip-components 1
						command_status "$stock_info Error while extracting delta archive $delta." "delta timestamp: ${txtylw}$timestamp${txtrst}"
					fi
				fi

				# Delete perished files if any
				echo
				deletion_lists=$(find "$script_dir/stock" -maxdepth 1 -name 'liste_suppression*' -print)
				while read perished_files; do
					if [ -r "$perished_files" ]
					then
						perished_files_deleted=0;
						perished_files_not_found=0;
						echo "$stock_info Deleting perished files"
						while read perished
						do
							perished_filepath=$(echo $perished | sed 's@\(^.*\)/\([^/]\+\)$@\1@')
							perished_filename=$(echo $perished | sed 's@\(^.*\)/\([^/]\+\)$@\2@')
							file=$(find "$script_dir/stock/$perished_filepath" -maxdepth 1 -name "$perished_filename*" -print 2>/dev/null)
							find_return_code=$?

							# Does the perished file exist?
							if [ -z $file -o $find_return_code -gt 0 ]
							then
								[[ $log_level -eq 0 ]] && echo -n "\r\033"
								debug "${warn} unable to find $script_dir/stock/$perished_filepath/$perished_filename*"
								debug "    current line: $perished\n    [in $perished_files - extracted from $delta]"
								let perished_files_not_found++;

							# If a file was found, delete it
							else
								# Display file to be deleted (non-verbose)
								[[ $log_level -eq 0 ]] && echo -n "\r\033[Kdeleting $file"
								# Display file to be deleted (verbose)
								debug "deleting $file" 1
								rm "$file"
								let perished_files_deleted++;
							fi
						done < "$perished_files"

						# Delete last line if we're not in verbose mode
						[[ $log_level -eq 0 ]] && echo -n "\r\033[K"

						# Now, we can delete the perished files list
						debug "deleting perished files list $perished_files" 1
						rm "$perished_files"

						deletion_stats="$([[ $perished_files_deleted -gt 0 ]] && echo "${txtgrn}deleted: $perished_files_deleted ")"
						deletion_stats="$deletion_stats$([[ $perished_files_not_found -gt 0 ]] && echo "${txtred}not found: $perished_files_not_found")"
						deletion_stats="$deletion_stats${txtrst}"
						echo "${ok} Done deleting perished files. $deletion_stats"
					else
						echo "${info} No perished files in delta."
					fi
				done <<< "$deletion_lists"

				# Using git
				if [ $use_git -gt 0 -a $stock_git_watch_dirs_count -gt 0 ]
				then
					# Commit in git repos
					if [ $stock_git_watch_dirs_count -eq 1 ]
					then
						git_msg="Committing delta $current_delta/$fresh_deltas_count [$timestamp] in 1 repository..."
					else
						git_msg="Committing delta $current_delta/$fresh_deltas_count [$timestamp] in $stock_git_watch_dirs_count repositories..."
					fi
					echo
					echo "$stock_info $git_msg"
					i=1
					while read git_watch_dir; do
						git_msg="[$i/$stock_git_watch_dirs_count] ${txtcyn}Committing in $git_watch_dir${txtrst}"
						if [ $log_level -gt 0 ]
						then
							# display a new line for each git repo if in verbose mode
							debug $git_msg
						else
							# Replace previous line if not in verbose mode
							echo -n "\r\033[K$git_msg"
						fi
						g=$(git -C "$script_dir/$git_watch_dir" add -A && git -C "$script_dir/$git_watch_dir" commit -m "Apply delta [$timestamp]")
						# command_status "Error while comitting delta $current_delta/$fresh_deltas_count [$timestamp] in git repository"
						let i++
					done <<< "$stock_git_watch_dirs"

					# Delete last line if we're not in verbose mode
					[[ $log_level -eq 0 ]] && echo -n "\r\033[K"
					echo "${ok} Done comitting delta"
				fi

				# Finish up applying current delta
				# Save delta timestamp and archive name in .dila-sync/applied-deltas
				echo "$timestamp	$delta">>"$conf_dir/applied-deltas"
				# Finally, update stock_date to the current delta timestamp
				local_stock_date=$timestamp

				# Done, the current delta was applied
				echo
				echo "$stock_info ${ok} ${txtbld}Done applying delta $current_delta/$fresh_deltas_count [$timestamp]${txtrst}"

			# If current_delta is perished we just state it but don't process it
			else
				echo "$stock_info ${warn} Not processing perished delta $current_delta/$fresh_deltas_count: ${txtcyn}$delta${txtrst} "
				echo "delta timestamp: ${txtylw}$timestamp${txtrst}"
			fi

			# Next delta
			let current_delta++
		done <<< "$fresh_deltas"
	fi

	# Recap
	# -----
	echo
	echo "${txtbld}Done synchronizing${txtrst} $stock_info"
	[[ $fresh_deltas_count -gt 0 ]] && col=$txtgrn || col=$txtpnk
	echo "${txtund}Fresh deltas applied:${txtrst} ${col}$fresh_deltas_count${txtrst}"
	echo "${txtund}Total deltas applied:${txtrst} ${col}$(($applied_deltas_count + $fresh_deltas_count))${txtrst}"
	echo "${txtund}Stock date:${txtrst} ${txtcyn}$(format_timestamp $local_stock_date)${txtrst}"
	echo

	# Save status
	if [ $fresh_deltas_count -gt 0 ]
	then
		synced_stocks_status="$synced_stocks_status${txtbld}${txtcyn}[ • $stock_to_sync ]${txtrst} "
	else
		synced_stocks_status="$synced_stocks_status$stock_info "
	fi
done

# Completed - All stocks were synced
echo "$ok ${txtbld}Completed sync for $synced_stocks_status"
