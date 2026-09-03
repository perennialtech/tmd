#!/usr/bin/env bash

#shellcheck disable=2164
#shellcheck disable=2155

script_version="5.0.0.0"

# Shut up both commands
function pushd {
	command pushd "$@" >/dev/null || return
}

function popd {
	command popd >/dev/null || return
}

# Copied from BashUtils.sh so there's no need for a dependency on it
function machine_has {
	command -v "$1" >/dev/null 2>&1
	return $?
}

function validate_autosave_interval {
	local LC_ALL=C
	local value="${TML_AUTOSAVE_INTERVAL_SECONDS-300}"

	if [[ ! $value =~ ^[1-9][0-9]*$ ]]; then
		echo "TML_AUTOSAVE_INTERVAL_SECONDS must be a canonical positive decimal integer" >&2
		exit 1
	fi

	if [[ ${#value} -gt 10 ]] ||
		{ [[ ${#value} -eq 10 ]] && [[ $value > 2147483647 ]]; }; then
		echo "TML_AUTOSAVE_INTERVAL_SECONDS must not exceed 2147483647" >&2
		exit 1
	fi

	autosave_interval_seconds="$value"
}

# There is seemingly no official documentation on this file but other "official" software does this same check.
# See: https://github.com/moby/moby/blob/v27.4.0/libnetwork/drivers/bridge/setup_bridgenetfiltering.go#L92-L95
function is_in_docker {
	if [[ -v ISDOCKER ]] || [[ -f /.dockerenv ]] || [[ -f /run/.containerenv ]]; then
		return 0
	fi
	return 1
}

# Check PATH and flags for required commands for tml/mod installation
function verify_steamcmd {
	# Prioritize an ENV Variable
	if [[ -v STEAMCMDPATH ]]; then
		if ! [[ -f $STEAMCMDPATH ]]; then
			echo "STEAMCMDPATH is set to a file that does not exist"
			exit 1
		fi
		steam_cmd="$STEAMCMDPATH"
		return
	fi

	if [[ -v steamcmd_path ]]; then
		if ! [[ -f $steamcmd_path ]]; then
			echo "--steamcmdpath is set to a file that does not exist"
			exit 1
		fi
		steam_cmd="$steamcmd_path"
		return
	fi

	steam_cmd=$(command -v steamcmd)
	if [[ -z $steam_cmd ]]; then
		echo "steamcmd could not be found in PATH, please install steamcmd or provide the STEAMCMDPATH environment variable"
		exit 1
	fi
}

function get_version {
	if [[ -v TMLVERSION ]]; then
		printf '%s\n' "$TMLVERSION"
	elif [[ -v tml_version ]]; then
		printf '%s\n' "$tml_version"
	else
		local latest_url
		local latest_release

		if ! latest_url=$(curl -fsSL \
			-o /dev/null \
			-w '%{url_effective}' \
			"https://github.com/tModLoader/tModLoader/releases/latest"); then
			echo "Could not resolve the latest tModLoader release" >&2
			return 1
		fi

		latest_release="${latest_url##*/}"
		if [[ -z $latest_release || $latest_release == latest ]]; then
			echo "GitHub did not return a tModLoader release tag" >&2
			return 1
		fi

		printf '%s\n' "$latest_release"
	fi
}

function install_tml_github {
	echo "Installing TML from GitHub"

	local ver
	local oldver
	local file

	if ! ver=$(get_version); then
		return 1
	fi

	if [[ ! $ver =~ ^v[0-9]+(\.[0-9]+){3}$ ]]; then
		echo "Invalid tModLoader release tag: $ver" >&2
		return 1
	fi

	# Nullglob prevents backup cleanup from treating an unmatched pattern as a
	# literal filename.
	shopt -s nullglob

	if [[ -r .ver ]]; then
		if ! oldver=$(<.ver); then
			echo "Could not read the installed tModLoader version" >&2
			return 1
		fi

		if [[ ! $oldver =~ ^v[0-9]+(\.[0-9]+){3}$ ]]; then
			echo "The installed tModLoader version is invalid: $oldver" >&2
			return 1
		fi

		if [[ $ver == "$oldver" ]]; then
			echo "Current tModLoader version ($ver) is up to date!"
			return 0
		fi

		echo "New version $ver is wanted, current version is $oldver"

		if ! mkdir -- "$oldver"; then
			return 1
		fi

		for file in *; do
			if [[ $file != "manage-tModLoaderServer.sh" &&
				$file != v*.tar.gz &&
				$file != "$oldver" ]]; then
				if ! mv -- "$file" "$oldver"; then
					return 1
				fi
			fi
		done

		if ! $keep_backups; then
			echo "Removing old backups"
			for file in v*.tar.gz; do
				if ! rm -- "$file"; then
					return 1
				fi
				echo "Removed old version $file"
			done
		fi

		echo "Compressing $oldver backup"
		if ! tar czf "$oldver.tar.gz" "$oldver"/*; then
			return 1
		fi
		if ! rm -r -- "$oldver"; then
			return 1
		fi
	fi

	shopt -u nullglob

	echo "Downloading version $ver"
	if ! curl -fL \
		-o tModLoader.zip \
		"https://github.com/tModLoader/tModLoader/releases/download/$ver/tModLoader.zip"; then
		echo "Could not download tModLoader release $ver" >&2
		return 1
	fi

	echo "Unzipping tModLoader.zip"
	if ! unzip -q tModLoader.zip; then
		rm -f tModLoader.zip
		echo "Could not extract tModLoader release $ver" >&2
		return 1
	fi

	if ! rm -f tModLoader.zip; then
		return 1
	fi

	if [[ ! -f LaunchUtils/ScriptCaller.sh ]]; then
		echo "The tModLoader archive does not contain LaunchUtils/ScriptCaller.sh" >&2
		return 1
	fi

	if ! printf '%s\n' "$ver" >.ver; then
		echo "Could not record the installed tModLoader version" >&2
		return 1
	fi
}

function install_tml_steam {
	echo "Installing TML from Steam"

	if ! [[ -v username ]]; then
		echo "Provide the --username flag in order to download TML from Steam" >&2
		return 1
	fi

	# tModLoader is installed under the selected server directory. Steam's other
	# assets remain under $HOME/Steam or $HOME/.steam.
	if ! "$steam_cmd" \
		+force_install_dir "$folder/server" \
		+login "$username" \
		+app_update 1281930 \
		+quit; then
		echo "SteamCMD failed to install tModLoader" >&2
		return 1
	fi
}

function install_tml {
	if ! mkdir -p server; then
		return 1
	fi
	if ! pushd server; then
		return 1
	fi

	if $github; then
		if ! install_tml_github; then
			popd
			return 1
		fi
	else
		if ! verify_steamcmd || ! install_tml_steam; then
			popd
			return 1
		fi
	fi

	if [[ -f "$folder/serverconfig.txt" && -f serverconfig.txt ]]; then
		echo "Removing duplicate serverconfig.txt"
		if ! rm serverconfig.txt; then
			popd
			return 1
		fi
	fi

	if ! popd; then
		return 1
	fi

	if ! is_in_docker; then
		echo "Creating folder structure"
		if ! mkdir -p Mods Worlds; then
			return 1
		fi
	fi

	root_dir="$folder/server"
	LogFile="$folder/server/tModLoader-Logs/DotNet.log"
	if [[ ! -f "$root_dir/LaunchUtils/DotNetVersion.sh" ||
		! -f "$root_dir/LaunchUtils/InstallDotNet.sh" ]]; then
		echo "The tModLoader release is missing its .NET installation scripts" >&2
		return 1
	fi

	. "$root_dir/LaunchUtils/DotNetVersion.sh"

	if ! chmod a+x "$root_dir/LaunchUtils/InstallDotNet.sh"; then
		return 1
	fi
	if ! bash "$root_dir/LaunchUtils/InstallDotNet.sh"; then
		echo "The tModLoader .NET installation failed" >&2
		return 1
	fi
}

function configure_workshop_mods {
	local LC_ALL=C
	local workshop_ids="${TML_WORKSHOP_IDS-}"
	local mods_dir="$folder/Mods"
	local workshop_root="$folder/steamapps/workshop/content/1281930"
	local legacy_path
	local unsupported_mod

	mkdir -p "$mods_dir" || exit 1

	# These files represent unsupported mod installation paths and must not be
	# silently combined with the generated Workshop configuration.
	for legacy_path in \
		"$folder/install.txt" \
		"$folder/tmlversion.txt" \
		"$mods_dir/install.txt" \
		"$mods_dir/tmlversion.txt"; do
		if [[ -e $legacy_path ]]; then
			echo "Unsupported mod configuration file found: $legacy_path" >&2
			echo "Configure every desired mod through TML_WORKSHOP_IDS and remove this file." >&2
			exit 1
		fi
	done

	unsupported_mod=$(find "$mods_dir" \
		\( -type f -o -type l \) \
		-name '*.tmod' \
		-print \
		-quit) || exit 1
	if [[ -n $unsupported_mod ]]; then
		echo "Unsupported local mod file found: $unsupported_mod" >&2
		echo "Configure every desired mod through TML_WORKSHOP_IDS and remove local .tmod files." >&2
		exit 1
	fi

	if [[ -n $workshop_ids && ! $workshop_ids =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]]; then
		echo "TML_WORKSHOP_IDS must be empty or a comma-separated list of canonical positive decimal Workshop IDs without whitespace" >&2
		exit 1
	fi

	local -a workshop_id_list=()
	local -a steamcmd_args=(+force_install_dir "$folder" +login anonymous)
	local -a enabled_names=()
	local -A seen_ids=()
	local -A seen_names=()
	local workshop_id
	local internal_name
	local item_dir

	if [[ -n $workshop_ids ]]; then
		IFS=',' read -r -a workshop_id_list <<<"$workshop_ids"
	fi

	for workshop_id in "${workshop_id_list[@]}"; do
		if [[ ${#workshop_id} -gt 20 ]] ||
			[[ ${#workshop_id} -eq 20 && $workshop_id > 18446744073709551615 ]]; then
			echo "Workshop ID exceeds the unsigned 64-bit Steam ID range: $workshop_id" >&2
			exit 1
		fi

		if [[ -v 'seen_ids[$workshop_id]' ]]; then
			echo "Duplicate Workshop ID in TML_WORKSHOP_IDS: $workshop_id" >&2
			exit 1
		fi
		seen_ids["$workshop_id"]=1
		steamcmd_args+=(+workshop_download_item 1281930 "$workshop_id")
	done

	if [[ ${#workshop_id_list[@]} -gt 0 ]]; then
		verify_steamcmd
		steamcmd_args+=(+quit)

		echo "Downloading ${#workshop_id_list[@]} Workshop mod(s)"
		if ! "$steam_cmd" "${steamcmd_args[@]}"; then
			echo "SteamCMD failed to download the configured Workshop mods" >&2
			exit 1
		fi
	fi

	for workshop_id in "${workshop_id_list[@]}"; do
		item_dir="$workshop_root/$workshop_id"
		if [[ ! -d $item_dir ]]; then
			echo "Workshop item $workshop_id was not downloaded under $workshop_root" >&2
			exit 1
		fi

		local -a discovered_names=()
		mapfile -t discovered_names < <(
			find "$item_dir" -type f -name '*.tmod' -exec basename '{}' .tmod ';' |
				sort -u
		)

		if [[ ${#discovered_names[@]} -ne 1 ]]; then
			echo "Workshop item $workshop_id must contain exactly one unique .tmod name; found ${#discovered_names[@]}" >&2
			exit 1
		fi

		internal_name="${discovered_names[0]}"
		if [[ ! $internal_name =~ ^[A-Za-z][A-Za-z0-9_]*$ ]]; then
			echo "Workshop item $workshop_id has an invalid internal mod name: $internal_name" >&2
			exit 1
		fi

		if [[ -v 'seen_names[$internal_name]' ]]; then
			echo "Multiple Workshop IDs resolve to the internal mod name $internal_name" >&2
			exit 1
		fi
		seen_names["$internal_name"]=1
		enabled_names+=("$internal_name")
	done

	local enabled_tmp
	local enabled_mode
	local creation_umask
	local index

	enabled_tmp=$(mktemp "$mods_dir/.enabled.json.XXXXXX") || exit 1
	creation_umask=$(umask)
	printf -v enabled_mode '%04o' "$((0666 & ~(8#$creation_umask)))"

	if ! chmod "$enabled_mode" "$enabled_tmp"; then
		rm -f "$enabled_tmp"
		echo "Could not set permissions on generated mod configuration" >&2
		exit 1
	fi

	if ! {
		printf '[\n'
		for ((index = 0; index < ${#enabled_names[@]}; index++)); do
			if [[ $index -gt 0 ]]; then
				printf ',\n'
			fi
			printf '  "%s"' "${enabled_names[$index]}"
		done
		if [[ ${#enabled_names[@]} -gt 0 ]]; then
			printf '\n'
		fi
		printf ']\n'
	} >"$enabled_tmp"; then
		rm -f "$enabled_tmp"
		echo "Could not write generated mod configuration" >&2
		exit 1
	fi

	if ! mv "$enabled_tmp" "$mods_dir/enabled.json"; then
		rm -f "$enabled_tmp"
		echo "Could not install generated mod configuration" >&2
		exit 1
	fi

	echo "Configured ${#enabled_names[@]} Workshop mod(s)"
}

function print_help {
	echo \
		"tML dedicated server installation and maintenance script

Usage: script.sh COMMAND [OPTIONS]

ENV Variables:
 STEAMCMDPATH        Custom path for the steamcmd binary if your package manager does not have it
 TMLVERSION                       tModLoader version to download. By default this is the latest release
 TML_WORKSHOP_IDS                 Comma-separated Workshop IDs to download and enable. Include every dependency
 TML_AUTOSAVE_INTERVAL_SECONDS    Positive autosave interval in seconds. Defaults to 300

Options:
 -h|--help           Show command line help
 -v|--version        Display the current version of the management script
 -g|--github         Download tML from Github instead of using steamcmd
 -f|--folder         The folder containing all of your server data (Mods, Worlds, serverconfig.txt, etc..)
 -u|--username       The steam username to use when downloading tML
 --keepbackups       When installing with --github, keep all previous versions instead of deleting them when updating
 --tmlversion        Version of tModLoader to install. Only works if --github is provided. Functionally equivalent to the TMLVERSION env variable
 --steamcmdpath      Path to steamcmd.sh for Steam tModLoader downloads. Functionally equivalent to the STEAMCMDPATH env variable

Commands:
 install-tml         Installs tModLoader from Steam (or Github if --github is provided)
 start [args]        Configures Workshop mods, then launches the server with any extra args
"
	exit
}

function require_option_value {
	if [[ $# -lt 2 ]]; then
		echo "$1 requires a value" >&2
		exit 1
	fi
}

github=false
keep_backups=false
start_args=()

if [[ $# -eq 0 ]]; then
	echo "No command supplied"
	print_help
fi

# Options that do not require a command remain available as the first argument.
cmd="$1"
if [[ ${cmd:0:1} != "-" ]]; then
	shift
fi

while [[ $# -gt 0 ]]; do
	case $1 in
	-h | --help)
		print_help
		;;
	-v | --version)
		echo "tML Dedicated Server Tool v$script_version"
		exit
		;;
	-g | --github)
		github=true
		;;
	-f | --folder)
		require_option_value "$@"
		folder="$2"
		shift
		;;
	-u | --username)
		require_option_value "$@"
		username="$2"
		shift
		;;
	--keepbackups)
		keep_backups=true
		;;
	--tmlversion)
		require_option_value "$@"
		tml_version="$2"
		github=true
		shift
		;;
	--steamcmdpath)
		require_option_value "$@"
		steamcmd_path="$2"
		shift
		;;
	-config | -steamworkshopfolder | -tmlsavedirectory)
		echo "$1 is managed by the container launcher and cannot be overridden" >&2
		exit 1
		;;
	*)
		if [[ $cmd != start ]]; then
			echo "Unknown option for $cmd: $1" >&2
			exit 1
		fi
		start_args+=("$1")
		;;
	esac
	shift
done

if [[ $cmd == start ]]; then
	validate_autosave_interval
fi

if ! machine_has "curl"; then
	echo "curl must be installed for the management script to work"
	exit 1
fi

if ! [[ -v folder ]]; then
	echo "Setting folder to current directory"
	folder="$(dirname "$(realpath "$0")")"
fi

if ! mkdir -p -- "$folder"; then
	exit 1
fi
if ! folder=$(cd -- "$folder" && pwd -P); then
	echo "Could not resolve the server data directory" >&2
	exit 1
fi
if ! pushd "$folder"; then
	exit 1
fi

case $cmd in
install-tml)
	if ! install_tml; then
		exit 1
	fi
	;;
start)
	# ScriptCaller must not reject the first launch before its log exists.
	export SKIP_DOTNET_LOGCHECK=1

	if ! machine_has setsid; then
		echo "setsid must be installed to launch and stop the server safely" >&2
		exit 1
	fi

	if is_in_docker; then
		if ! mkdir -p \
			"$folder/Mods" \
			"$folder/Worlds" \
			"$HOME/server/tModLoader-Logs"; then
			exit 1
		fi

		if ! printf '%s\n' \
			'dotnet installed via management script... pending first server start...' \
			>>"$HOME/server/tModLoader-Logs/server.log"; then
			exit 1
		fi
		cd "$HOME/server" || exit 1
	elif [[ ! -f "$folder/server/LaunchUtils/ScriptCaller.sh" ]]; then
		echo "A tModLoader server is not installed yet; run install-tml before starting it" >&2
		exit 1
	else
		cd "$folder/server" || exit 1
	fi

	configure_workshop_mods

	if ! chmod +x ./LaunchUtils/ScriptCaller.sh; then
		exit 1
	fi

	server_io_dir=$(mktemp -d "${TMPDIR:-/tmp}/tmd-server-io.XXXXXX") || exit 1
	server_input_fifo="$server_io_dir/input"

	if ! mkfifo "$server_input_fifo"; then
		rm -rf -- "$server_io_dir"
		exit 1
	fi

	# A read/write descriptor keeps the FIFO open while the console relay and
	# autosave scheduler independently submit complete server commands.
	if ! exec 9<>"$server_input_fifo"; then
		rm -rf -- "$server_io_dir"
		exit 1
	fi

	console_relay_pid=
	autosave_timer_pid=

	cleanup_server_io() {
		local helper_pid

		for helper_pid in "$console_relay_pid" "$autosave_timer_pid"; do
			if [[ -n $helper_pid ]] && kill -0 "$helper_pid" 2>/dev/null; then
				kill "$helper_pid" 2>/dev/null || :
			fi
		done

		for helper_pid in "$console_relay_pid" "$autosave_timer_pid"; do
			if [[ -n $helper_pid ]]; then
				wait "$helper_pid" 2>/dev/null || :
			fi
		done

		exec 9>&-
		rm -rf -- "$server_io_dir"
	}

	trap cleanup_server_io EXIT

	setsid ./LaunchUtils/ScriptCaller.sh \
		-server \
		-config "$folder/serverconfig.txt" \
		-steamworkshopfolder "$folder/steamapps/workshop" \
		-tmlsavedirectory "$folder" \
		"${start_args[@]}" \
		<"$server_input_fifo" &
	server_pid=$!

	forward_console_input() {
		local input_line

		while IFS= read -r input_line || [[ -n $input_line ]]; do
			printf '%s\n' "$input_line" >&9 || return 1
		done
	}

	forward_console_input <&0 &
	console_relay_pid=$!

	sleep "$autosave_interval_seconds" &
	autosave_timer_pid=$!

	forward_server_signal() {
		kill -s "$1" -- "-$server_pid" 2>/dev/null || :
	}

	trap 'forward_server_signal TERM' TERM
	trap 'forward_server_signal INT' INT
	trap 'forward_server_signal HUP' HUP

	server_status=0
	supervisor_failure=

	while true; do
		completed_pid=
		wait -n -p completed_pid "$server_pid" "$autosave_timer_pid"
		completed_status=$?

		# A trapped container signal interrupts wait without completing either
		# child. The signal handler forwards it to the complete server group.
		if [[ -z $completed_pid ]]; then
			continue
		fi

		if [[ $completed_pid == "$server_pid" ]]; then
			server_status=$completed_status
			break
		fi

		if [[ $completed_pid != "$autosave_timer_pid" ]]; then
			supervisor_failure="wait returned an unexpected child process"
			break
		fi

		if [[ $completed_status -ne 0 ]]; then
			supervisor_failure="the autosave timer failed"
			break
		fi

		if ! printf 'save\n' >&9; then
			supervisor_failure="the autosave command could not be submitted"
			break
		fi

		sleep "$autosave_interval_seconds" &
		autosave_timer_pid=$!
	done

	if [[ -n $supervisor_failure ]]; then
		echo "Server supervisor failure: $supervisor_failure" >&2
		forward_server_signal TERM

		while kill -0 "$server_pid" 2>/dev/null; do
			wait "$server_pid" 2>/dev/null || :
		done

		server_status=1
	fi

	trap - TERM INT HUP
	cleanup_server_io
	trap - EXIT
	exit "$server_status"
	;;
*)
	echo "Invalid Command: $cmd"
	print_help
	;;
esac

popd
