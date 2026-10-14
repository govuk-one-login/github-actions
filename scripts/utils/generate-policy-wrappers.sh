#!/bin/bash

# Generate CloudFormation wrappers for .tpl policy files
# Usage: ./scripts/generate-policy-wrappers.sh <policy_directory>
POLICY_DIR=$1;shift;

GENERATED_DIR="${POLICY_DIR}/generated_policies"

# Create generated policies directory
mkdir -p "$GENERATED_DIR"

# Clean existing generated files
rm -f "$GENERATED_DIR"/*.json

echo "Generating CloudFormation wrappers for policy files..."
tpl_count=0
failed_count=0


for tpl_file in $(find ${POLICY_DIR} -name "*.json*" -o -name "*.tpl"); do
    if [[ -f "$tpl_file" ]]; then
        # Create wrapper filename in generated directory
        base_name=$(basename "$tpl_file" .tpl)
        base_name=$(basename "$base_name" .json)
        wrapper_file="$GENERATED_DIR/${base_name}-wrapper.json"

        echo "Wrapping: $tpl_file -> $wrapper_file"

        # Create CloudFormation wrapper with the policy content using Python
        if python3 -c "
import json
import sys
try:
    with open('$tpl_file', 'r') as f:
        policy = json.load(f)
    wrapper = {
        'AWSTemplateFormatVersion': '2010-09-09',
        'Resources': {
            'PolicyCheck': {
                'Type': 'AWS::IAM::Policy',
                'Properties': {
                    'PolicyName': 'CheckPolicy',
                    'PolicyDocument': policy,
                    'Roles': ['DummyRole']
                }
            }
        }
    }
    with open('$wrapper_file', 'w') as f:
        json.dump(wrapper, f, indent=2)
except Exception as e:
    print(f'Error processing $tpl_file: {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
            ((tpl_count++))
        else
            echo "Failed to process $tpl_file"
            ((failed_count++))
        fi
    fi
done

echo "Generated $tpl_count CloudFormation wrapper files in $GENERATED_DIR"
if [[ $failed_count -gt 0 ]]; then
    echo "Failed to process $failed_count files"
    exit 1
fi
