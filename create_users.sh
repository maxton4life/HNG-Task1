#!/bin/bash
#: Title       : create_users.sh
#: Date        : July 01 2024
#: Author      : maxton

#: Description : ##################################################################
# This script is designed to automate the process of creating users,               #
# adding them to groups, and securely handling their passwords.                     #
# It includes logging of each action taken for accountability and troubleshooting purposes. #
#############################################################################################

# Set and define global variables for directories and files
LOG_DIR="/var/log"
SECURE_DIR="/var/secure"
LOG_FILE="$LOG_DIR/user_management.log"
PASSWORD_FILE="$SECURE_DIR/user_passwords.txt"

# Function to initialize directories
initialize_directories() {
    # Create the log and secure directories if they do not exist
    mkdir -p "$LOG_DIR" "$SECURE_DIR"
}

# Function to initialize files
initialize_files() {
    # Create the log file and password file
    touch "$LOG_FILE" "$PASSWORD_FILE"
    # Set secure permissions on the password file (read and write for owner only)
    chmod 600 "$PASSWORD_FILE"
}

# Function to log actions to the log file
log_action() {
    local message="$1" # Get the message to log
    # Append the message with the current date and time to the log file
    printf "%s - %s\n" "$(date)" "$message" >> "$LOG_FILE"
}

# Function to create a user
create_user() {
    local user="$1"   # Get the username
    local groups="$2" # Get the groups the user should be added to
    local password    # Variable to hold the generated password

    # Check if the user already exists
    if id "$user" &>/dev/null; then
        log_action "User $user already exists."
        return
    fi

    # Create a personal group for the user
    groupadd "$user"

    # Split the groups string into an array
    IFS=' ' read -ra group_array <<< "$groups"
    log_action "User $user will be added to groups: ${group_array[*]}"

    # Create each additional group if it does not exist
    for group in "${group_array[@]}"; do
        group=$(echo "$group" | xargs) # Trim whitespace
        if ! getent group "$group" &>/dev/null; then
            groupadd "$group"
            log_action "Group $group created."
        fi
    done

    # Create the user with a home directory and bash shell, and set the primary group
    useradd -m -s /bin/bash -g "$user" "$user"
    if [ $? -eq 0 ]; then
        log_action "User $user created with primary group: $user"
    else
        log_action "Failed to create user $user."
        return
    fi

    # Add the user to each additional group
    for group in "${group_array[@]}"; do
        usermod -aG "$group" "$user"
    done
    log_action "User $user added to groups: ${group_array[*]}"

    # Generate a random password for the user
    password=$(</dev/urandom tr -dc A-Za-z0-9 | head -c 12)
    # Set the user's password
    echo "$user:$password" | chpasswd
    # Store the username and password in the password file
    printf "%s,%s\n" "$user" "$password" >> "$PASSWORD_FILE"

    # Set secure permissions on the user's home directory
    chmod 700 "/home/$user"
    chown "$user:$user" "/home/$user"

    log_action "Password for user $user set and stored securely."
}

# Main function to control script execution
main() {
    initialize_directories
    initialize_files

    # Check if the correct number of arguments is provided
    if [ $# -ne 1 ]; then
        printf "Usage: %s <user_list_file>\n" "$0"
        exit 1
    fi

    local filename="$1" # Get the filename from the arguments
    # Check if the file exists
    if [ ! -f "$filename" ]; then
        printf "Users list file %s not found.\n" "$filename"
        exit 1
    fi

    # Read the user list file line by line
    while IFS=';' read -r user groups; do
        # Trim whitespace from the username and groups
        user=$(echo "$user" | xargs)
        groups=$(echo "$groups" | xargs | tr -d ' ')
        # Replace commas with spaces for group format
        groups=$(echo "$groups" | tr ',' ' ')
        # Create the user
        create_user "$user" "$groups"
    done < "$filename"

    printf "User creation process completed. Check %s for details.\n" "$LOG_FILE"
}

# Run the main function with all script arguments
main "$@"
