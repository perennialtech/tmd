#!/bin/sh

set -eu

fail() {
	echo "docker-entrypoint: $*" >&2
	exit 1
}

validate_id() {
	id_name=$1
	id_value=$2

	case "$id_value" in
	"" | 0 | 0* | *[!0-9]*)
		fail "$id_name must be a canonical positive decimal integer"
		;;
	esac

	if [ "${#id_value}" -gt 10 ] ||
		{ [ "${#id_value}" -eq 10 ] && [ "$id_value" \> 2147483647 ]; }; then
		fail "$id_name must not exceed 2147483647"
	fi
}

validate_umask() {
	case "$1" in
	[0-7][0-7][0-7] | [0-7][0-7][0-7][0-7])
		;;
	*)
		fail "UMASK must contain three or four octal digits"
		;;
	esac
}

validate_id TML_UID "$TML_UID"
validate_id TML_GID "$TML_GID"
validate_umask "$UMASK"

if [ "$(awk -F: '$1 == "tml" { count++ } END { print count + 0 }' /etc/passwd)" -ne 1 ]; then
	fail "the image must contain exactly one tml user"
fi

if [ "$(awk -F: '$1 == "tml" { count++ } END { print count + 0 }' /etc/group)" -ne 1 ]; then
	fail "the image must contain exactly one tml group"
fi

current_tml_uid=$(awk -F: '$1 == "tml" { print $3 }' /etc/passwd)
current_tml_gid=$(awk -F: '$1 == "tml" { print $3 }' /etc/group)

uid_owner=$(awk -F: -v wanted="$TML_UID" \
	'$3 == wanted && $1 != "tml" { print $1; exit }' /etc/passwd)
if [ -n "$uid_owner" ]; then
	fail "TML_UID $TML_UID is already assigned to container user $uid_owner"
fi

gid_owner=$(awk -F: -v wanted="$TML_GID" \
	'$3 == wanted && $1 != "tml" { print $1; exit }' /etc/group)
if [ -n "$gid_owner" ]; then
	fail "TML_GID $TML_GID is already assigned to container group $gid_owner"
fi

passwd_tmp=
group_tmp=

cleanup() {
	if [ -n "$passwd_tmp" ]; then
		rm -f "$passwd_tmp"
	fi
	if [ -n "$group_tmp" ]; then
		rm -f "$group_tmp"
	fi
}

trap cleanup EXIT HUP INT TERM

passwd_tmp=$(mktemp /etc/passwd.tmd.XXXXXX)
group_tmp=$(mktemp /etc/group.tmd.XXXXXX)

awk -F: -v OFS=: -v uid="$TML_UID" -v gid="$TML_GID" \
	'$1 == "tml" { $3 = uid; $4 = gid } { print }' \
	/etc/passwd >"$passwd_tmp"

awk -F: -v OFS=: -v gid="$TML_GID" \
	'$1 == "tml" { $3 = gid } { print }' \
	/etc/group >"$group_tmp"

chmod 0644 "$passwd_tmp" "$group_tmp"

mv "$group_tmp" /etc/group
group_tmp=
mv "$passwd_tmp" /etc/passwd
passwd_tmp=

trap - EXIT HUP INT TERM

mkdir -p /tModLoader

if [ "$current_tml_uid" != "$TML_UID" ] ||
	[ "$current_tml_gid" != "$TML_GID" ]; then
	chown -R "$TML_UID:$TML_GID" /home/tml
fi

# Persistent data may have been restored with arbitrary ownership, so it is
# reconciled on every startup.
chown -R "$TML_UID:$TML_GID" /tModLoader

umask "$UMASK"

exec setpriv \
	--reuid="$TML_UID" \
	--regid="$TML_GID" \
	--init-groups \
	/home/tml/manage-tModLoaderServer.sh \
	start \
	--folder /tModLoader \
	"$@"
