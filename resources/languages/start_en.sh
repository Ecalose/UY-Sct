#!/bin/bash

# Import various modules
for script in "$(dirname "$0")/resources/module_codes/cn"/*.sh \
	"$(dirname "$0")/resources/module_codes/general"/*.sh; do
	source "$script"
done
source "$(dirname "$0")/resources/my_tools/nice_rom/only_modify.sh"

super_sub_partitions_list="my_.*\.img|\
mi_ext\.img|\
odm\.img|odm_dlkm\.img|\
product\.img|\
system\.img|system_dlkm\.img|system_ext\.img|\
vendor\.img|vendor_dlkm\.img"

# Define paths for tools and workspace directories
TOOL_DIR="$(dirname "$0")/resources/my_tools"
WORK_DIR="$(dirname "$0")/my_workspaces"

# Define current workspace variable
current_workspace=""

# Function to show main menu
function show_main_menu {
	clear
	echo -e "\033[38;2;135;206;235m"
	echo -e "                               "
	echo -e "   ──────────────────────────"
	echo -e "                             "
	echo -e "           UY Scuti  "
	echo -e "                             "
	echo -e "   ──────────────────────────"
	tput sgr0
	echo -e "\n   [01] Select Workspace\n"
	echo -e "   [02] Create Workspace\n"
	echo -e "   [03] Delete Workspace\n"
	echo -e "   [04] Change Language Settings\n"
	echo -e "   [05] Exit Program\n"
	echo -n "   Please select an option: "
}

# Function to show workspace menu
function show_workspace_menu {
	echo -e "\033[38;2;135;206;235m"
	echo -e "                               "
	echo -e "   ────────────────────────"
	echo -e "                             "
	echo -e "           Workspace        "
	echo -e "                             "
	echo -e "   ────────────────────────"
	tput sgr0
	echo -e "\n   [01] Extract Partition Files\n"
	echo -e "   [02] Package Partition Files\n"
	echo -e "   [03] Package SUPER Partition\n"
	echo -e "   [04] One-click Modify\n"
	echo -e "   [05] Build Flash Package\n"
	echo -e "   [06] Return to Main Menu\n"
	echo -e "   [07] Exit Program\n"
	echo -n "   Please select an option: "
}

# Function to create workspace
function create_workspace {
	while true; do
		echo ""
		echo -n "   Please enter a name for the new workspace: "
		read workspace
		if [ -z "$workspace" ]; then
			clear
			echo -e "\n   No valid input was entered."
			continue
		fi
		if echo "$workspace" | grep -Pvq "^[a-zA-Z0-9_\-\.\p{Han}—\s]*$"; then
			clear
			echo -e "\n   Invalid workspace name."
		else
			if [ -d "$WORK_DIR/$workspace" ]; then
				echo "   Workspace $workspace already exists, no need to create."
				echo -n "   Press any key to return to main menu..."
				read -n 1
				return
			else
				mkdir -p "$WORK_DIR/$workspace"
				echo "   Workspace $workspace has been created."
				echo -n "   Press any key to return to main menu..."
				read -n 1
				return
			fi
		fi
	done
}

# Function to select workspace
function select_workspace {
	local workspaces=("$WORK_DIR"/*)
	if [ -z "$(ls -A "$WORK_DIR")" ]; then
		echo -e "\n"
		echo -n "   No available workspace, press any key to return."
		read -n 1
		return
	fi

	while true; do
		echo -e "\n"
		echo -e "   The following are all available workspaces:\n"
		local i=1
		for workspace in "${workspaces[@]}"; do
			if [ -d "$workspace" ]; then
				printf "   [%02d] %s\n\n" "$i" "$(basename "$workspace")"
				i=$((i + 1))
			fi
		done
		echo -e "\n   [Q] Return to main menu\n"
		echo -n "   Please enter the workspace number to select: "
		read choice
		if [[ "$choice" =~ ^[Qq]$ ]]; then
			return
		elif [[ "$choice" =~ ^[0-9]+$ ]]; then
			workspace=$(ls -d "$WORK_DIR"/* | sed -n "${choice}p")
			if [ -d "$workspace" ]; then
				current_workspace="$(basename "$workspace")"
				echo "   You have selected workspace '$current_workspace'."
				workspace_menu
				break
			else
				clear
				echo -e "\n   The workspace number does not exist, please try again."
			fi
		else
			clear
			echo -e "\n   Invalid input, please try again."
		fi
	done
}

# Function to delete workspace
function delete_workspace {
	if [ -z "$(ls -A "$WORK_DIR")" ]; then
		echo -e "\n"
		echo -n "   No workspace to delete, press any key to return."
		read -n 1
		return
	fi

	while true; do
		echo -e "\n"
		echo -e "   The following are all workspaces:\n"
		local i=1
		for workspace in "$WORK_DIR"/*; do
			if [ -d "$workspace" ]; then
				printf "   [%02d] %s\n\n" "$i" "$(basename "$workspace")"
				i=$((i + 1))
			fi
		done
		echo -e "\n   [Q] Return to main menu\n"
		echo -n "   Please enter the number of the workspace to delete: "
		read choice
		if [[ "$choice" =~ ^[Qq]$ ]]; then
			return
		elif [[ "$choice" =~ ^[0-9]+$ ]]; then
			workspace=$(ls -d "$WORK_DIR"/* | sed -n "${choice}p")
			if [ -d "$workspace" ]; then
				rm -rf "$workspace"
				find "$TOOL_DIR/boot_editor" -mindepth 1 ! -regex '^'"$TOOL_DIR/boot_editor"'/\(aosp\|bbootimg\|src\|tools\|gradlew\)\(/.*\)?$' -exec rm -rf {} \; 2>/dev/null
				echo "   Workspace $(basename "$workspace") has been deleted."
				echo -n "   Press any key to return to main menu..."
				read -n 1
				return
			else
				clear
				echo -e "\n   The workspace number does not exist, please try again."
			fi
		else
			clear
			echo -e "\n   Invalid input, please try again."
		fi
	done
}

# Add new features in workspace menu function
function workspace_menu {
	while true; do
		clear
		keep_clean
		show_workspace_menu
		read choice
		case "$choice" in
		1)
			clear
			extract_img
			;;
		2)
			clear
			package_regular_image
			;;
		3)
			clear
			package_super_image
			;;
		4)
			clear
			one_click_modify
			;;
		5)
			clear
			rebuild_rom
			;;
		6)
			clear
			return
			;;
		7)
			clear
			exit 0
			;;
		*)
			clear
			echo "   Invalid selection, please try again."
			;;
		esac
	done
}

# One-click modify action
function one_click_modify {
	pushd . >/dev/null
	local workspace_path=$(realpath "$WORK_DIR/$current_workspace")
	echo -e "\n"
	add_path "$workspace_path"
	popd
}

# Remove unwanted Zone.Identifier files to keep directory clean
function keep_clean {
	find "$(dirname "$0")" -type f -name "*Zone.Identifier*" -exec rm -rf {} \;
}

# Main loop
while true; do
	clear
	keep_clean
	show_main_menu
	read choice
	case "$choice" in
	1)
		clear
		select_workspace
		;;
	2)
		clear
		create_workspace
		;;
	3)
		clear
		delete_workspace
		;;
	4)
		clear
		echo -e "\n   [1] English\n"
		echo -e "   [2] 中文\n"
		echo -n "   Please select new language setting: "
		read new_language
		if [ "$new_language" = "1" ]; then
			replace_script "start_en.sh"
			exec "$(dirname "$0")/start.sh"
		elif [ "$new_language" = "2" ]; then
			replace_script "start_cn.sh"
			exec "$(dirname "$0")/start.sh"
		else
			echo "   Invalid selection, please try again."
		fi
		;;
	5)
		clear
		exit 0
		;;
	*)
		echo "   Invalid selection, please try again."
		;;
	esac
done