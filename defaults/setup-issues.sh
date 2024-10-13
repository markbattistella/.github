#!/bin/bash

# Function to remove all labels from a repository
remove_labels() {
  REPO=$1
  echo "Removing labels from $REPO"
  
  LABELS=$(gh api repos/$REPO/labels --jq '.[].name')
  
  for LABEL in $LABELS; do
    echo "Deleting label: $LABEL"
    gh api -X DELETE repos/$REPO/labels/$LABEL
  done
}

# Function to add labels from a JSON file
add_labels() {
  REPO=$1
  JSON_FILE=$2
  echo "Adding labels to $REPO from $JSON_FILE"
  
  LABELS=$(cat "$JSON_FILE")
  
  echo "$LABELS" | jq -c '.[]' | while read label; do
    NAME=$(echo "$label" | jq -r '.name')
    COLOR=$(echo "$label" | jq -r '.color')
    DESCRIPTION=$(echo "$label" | jq -r '.description')
  
    echo "Adding label: $NAME"
    gh api repos/$REPO/labels -f name="$NAME" -f color="$COLOR" -f description="$DESCRIPTION"
  done
}

# Function to handle the menu
menu() {
  echo "Choose an option:"
  echo "1 - Delete all existing labels"
  echo "2 - Add new predefined labels (provide JSON file path)"
  echo "3 - Delete all labels and add new predefined labels (provide JSON file path)"
  echo "4 - Exit"
  
  read -p "Enter your choice: " CHOICE
  REPO=$1  # Get the repo name from the command-line argument

  case $CHOICE in
    1)
      echo "Deleting all labels from $REPO."
      remove_labels $REPO
      ;;
    2)
      read -p "Enter the path to the JSON file: " JSON_FILE
      echo "Adding new predefined labels to $REPO from $JSON_FILE."
      add_labels $REPO $JSON_FILE
      ;;
    3)
      read -p "Enter the path to the JSON file: " JSON_FILE
      echo "Deleting all labels and adding new predefined labels to $REPO from $JSON_FILE."
      remove_labels $REPO
      add_labels $REPO $JSON_FILE
      ;;
    4)
      echo "Exiting script."
      exit 0
      ;;
    *)
      echo "Invalid choice! Please choose a valid option."
      ;;
  esac
}

# Check if the repo name is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <repo>"
  exit 1
fi

# Run the menu with the repo argument
menu $1
