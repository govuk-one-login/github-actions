from datetime import datetime, timezone
import botocore
import boto3
import time
import os

# Initialize a session using CloudFormation
client = boto3.client('cloudformation')

# Name of the CloudFormation stack
stack_name = os.environ['STACK_NAME']

def check_stack_status(event, from_date):
    update_complete = False
    create_complete = False
    update_failed = False

    # print(event)

    if event['LogicalResourceId'] == stack_name:
        if event['Timestamp'] > from_date:
            resource_status = event['ResourceStatus']
            if resource_status == 'UPDATE_COMPLETE':
                update_complete = True
            if resource_status == 'CREATE_COMPLETE':
                create_complete = True
            if resource_status == 'ROLLBACK_IN_PROGRESS':
                update_failed = True

    return update_complete, create_complete, update_failed


def wait_for_stack_status(stack_name, from_date, max_attempts=100):
    print(f"Waiting for stack {stack_name} to reach CREATE_COMPLETE, or UPDATE_COMPLETE status...")
    attempts = 0
    while attempts < max_attempts:
        try:
            response = client.describe_stack_events(StackName=stack_name)
            if not response:
                print("No response received.")
                break

            events = response['StackEvents']
            # print(events)
            num_events = len(events)

            for i in range(0, num_events):
                event = events[i]

                update_complete, create_complete, update_failed = (
                    check_stack_status(event, from_date))
                if update_complete:
                    print("Stack update complete.")
                    return

                if create_complete:
                    print("Stack creation complete.")
                    return
                if update_failed:
                    print("Stack update failed.")
                    exit(os.EX_DATAERR)
        except botocore.exceptions.ClientError:
            print("There was an ValidationError")
        finally:
            attempts += 1
            print(f"Attempt {attempts}/{max_attempts}: Waiting for stack to reach desired status...")
            time.sleep(2)


    print("Max attempts reached or desired status not found within the attempts limit.")


if __name__ == "__main__":
    now_date = datetime.now(timezone.utc)
    wait_for_stack_status(stack_name, now_date, 100)
    print("Script execution completed.")
