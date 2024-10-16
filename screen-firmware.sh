#!/bin/bash

# Clear the terminal screen
clear

echo "Updating display firmware"
echo " "
echo "DO NOT power off the machine! This may take a while."
#update screen firmware

#stopping display service
echo "Stopping display service"
sudo service display stop
echo " "
echo "Stopped display service"

#Make sure display_connector is on dev
DISPLAY_CONNECTOR_DIR="${HOME}/display_connector"
current_branch=$(git --git-dir="$DISPLAY_CONNECTOR_DIR/.git" --work-tree="$DISPLAY_CONNECTOR_DIR" rev-parse --abbrev-ref HEAD)
if [ "$current_branch" = "main" ]; then
    echo "You are on the main branch. Switching to dev."
    branch_name="dev"
    repo_dir="DISPLAY_CONNECTOR_DIR"
    if [ -d "$repo_dir" ]; then
        git -C "$repo_dir" reset --hard >/dev/null 2>&1
        git -C "$repo_dir" clean -fd >/dev/null 2>&1
        git -C "$repo_dir" checkout "$branch_name" >/dev/null 2>&1 && echo -e "${G}Switched $repo_dir to $branch_name.${NC}"
    fi
    
fi

# Create and activate a Python virtual environment
#venv
echo " "
echo "Creating and activating a virtual environment..."
python3 -m venv Display-Update
source Display-Update/bin/activate
pip install pyserial
echo " "
echo "Activated virtual environment successfully"
#Themes
main_repo_url="https://github.com/Choccy-vr/display_firmware_dev.git"
themes_path="Themes"

# Step 1: Fetch the list of themes using the GitHub API
echo "Fetching the list of available themes..."
themes_list=$(curl -s "https://api.github.com/repos/Choccy-vr/display_firmware_dev/contents/$themes_path" | jq -r '.[] | select(.type == "dir") | .name')

if [[ -z "$themes_list" ]]; then
    echo "No themes found in the repository."
    exit 1
fi

# Step 2: Display the list of available themes with numbering
echo "Available Themes:"
theme_array=()
index=1
for theme in $themes_list; do
    theme_array+=("$theme")
    echo "$index) $theme"
    index=$((index + 1))
done

# Step 3: Prompt the user to select a theme
echo "Enter the number of the theme you want to download:"
read selection

# Validate the selection
if ! [[ "$selection" =~ ^[0-9]+$ ]] || ((selection < 1 || selection > ${#theme_array[@]})); then
    echo "Invalid selection. Please choose a valid number."
    exit 1
fi

selected_theme="${theme_array[$selection-1]}"
theme_clone_url="$main_repo_url"

# Step 4: Clone only the selected theme subdirectory using sparse-checkout
echo "Cloning $selected_theme into the themes directory..."
mkdir -p "$themes_path"
cd "$themes_path"
git init
git remote add origin "$theme_clone_url"
git config core.sparseCheckout true
echo "$themes_path/$selected_theme" >> .git/info/sparse-checkout
git pull origin main

# Move the theme to the themes directory and clean up
mv "$themes_path/$selected_theme" ./
rm -rf .git "$themes_path"

echo "Theme $selected_theme has been successfully downloaded into the themes directory."

#Modify scripts
echo "Making necessary modifications"
# Path to the JSON file
json_file="$themes_path/$selected_theme/Config.json"

# Check if the JSON file exists
if [[ ! -f "$json_file" ]]; then
    echo "JSON file not found: $json_file"
    exit 1
fi

# Loop through each script entry in the JSON file
echo "Processing scripts from $json_file..."

# Using jq to parse the JSON and iterate through each script
for script in $(jq -c '.scripts[]' "$json_file"); do
    source_file=$(echo "$script" | jq -r '.source')
    destination_file=$(echo "$script" | jq -r '.destination')

    # Full path to the source file
    full_source_path="$themes_path/$selected_theme/$source_file"
    # Full path to the destination file
    full_destination_path="${HOME}/$destination_file"

    # Copy the file and overwrite if it exists
    cp -f "$full_source_path" "$full_destination_path"

    echo "Copied $full_source_path to $full_destination_path"
done

#modify display_connector.cfg
config_file="${HOME}/printer_data/config/display_connector.cfg"
new_line="display_type = openneptune"
if ! grep -Fxq "$new_line" "$config_file"; then
    sed -i "/\[general\]/a $new_line" "$config_file"
fi
#Flashing
echo " "
echo "Starting to flash!"
echo " "
python3 "${HOME}/display_firmware/Nexus.py" -i "${HOME}/$themes_path/$selected_theme/tft/OpenNeptuneUi.tft" -u 115200 -p /dev/ttyS1
echo " "
#done
echo " "
echo " Updated display firmware successfully. Restarting"
sudo reboot
