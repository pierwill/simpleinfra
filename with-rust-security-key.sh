#!/bin/bash
# This script executes the command provided as argument with the gpg
# environment configured to use the Rust Security team key. Sample usage:
#
#    ./with-rust-key.sh gpg sign -u EFB9860AE7520DAC --detach --armor file.txt
#
# The script has been tested with GnuPG 2.2, and requires jq and the 1password
# CLI to be installed and configured:
#
#    https://support.1password.com/command-line-getting-started/
#
# The script is designed to leave no traces of the key on the host system after
# it finishes, but a program with your user's privileges can still interact
# with the key as long as the script is running.
set -euo pipefail
IFS=$'\n\t'

# Directory where to store the gpg keys
export GNUPGHOME="/dev/shm/rust-gpg"

# 1password UUIDs to import into the temporary gpg environment
IMPORT_KEYS=(
    "e2rq3jfyb35tmtfuofhcm7bo6q" # public.asc
    "mn7kdu6hnramxkmxd7a2wrdhlu" # secret.asc
)

# 1password UUID of the secret key's password
SECRET_KEY_PASSWORD_UUID="6a6doblupfhkjr7wt24li2jpk4"

# ID of the key used to sign Rust releases
SIGNING_KEY_ID="EFB9860AE7520DAC"

##############################################################################

ensure_bin() {
    name="$1"
    if ! which "${name}" >/dev/null 2>&1; then
        echo "the binary $1 is missing!"
        exit 1
    fi
}

ensure_bin jq
ensure_bin op

# Ensure no traces are left on the system
cleanup() {
    # Remove the gpg keys from the local machine
    rm -rf "${GNUPGHOME}"

    # Flush the gpg agent cache to remove the password
    echo RELOADAGENT | gpg-connect-agent

    # Overwrite and unset `passphrase` variable
    passphrase=$(printf '=%.0s' {1..1024})
    unset passphrase
}
trap cleanup EXIT

# Ensure we're signed into 1password
if [[ -z "${OP_SESSION_rust_lang+x}" ]]; then
    echo "1password auth session is not present, logging in..."
    eval "$(op signin rust_lang)"
else
    echo "reusing 1password auth session"
fi

# Create the directory if it doesn't exist
if [[ -d "${GNUPGHOME}" ]]; then
    echo "${GNUPGHOME} already exist, exiting"
    exit 1
fi
mkdir "${GNUPGHOME}"
chmod 0700 "${GNUPGHOME}"

# Import the keys into the temporary gpg home
echo "importing the gpg keys inside ${GNUPGHOME}"
for uuid in "${IMPORT_KEYS[@]}"; do
    op get document "${uuid}" | gpg --import --armor --batch --pinentry-mode loopback
done

# Load the password into the gpg agent
passphrase="$(op get item "${SECRET_KEY_PASSWORD_UUID}" | jq -r ".details.password")"
echo "dummy" | gpg -u "${SIGNING_KEY_ID}" --pinentry-mode loopback --batch --yes --passphrase "${passphrase}" --sign --armor >/dev/null

# Execute the user-provided program
echo "running:" "$@"
set +e
"$@"
errorcode="$?"
set -e

# Make sure to return the correct exit code
exit "${errorcode}"
