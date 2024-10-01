from datetime import datetime, timezone
import os
import unittest
from unittest import mock

import botocore.session
from botocore.stub import Stubber
os.environ['STACK_NAME'] = 'upload-action-test'
import api_call

cloudformation = botocore.session.get_session().create_client('cloudformation')
stubber = Stubber(cloudformation)

future_date = datetime(2050, 12,31,23,59, tzinfo=timezone.utc)

response = {
    "StackEvents": [
        {
            "StackId": "arn:aws:cloudformation:eu-west-2:842766856468:stack/upload-action-test/e8757440-7b26-11ef-b77c-0622e8144257",
            "EventId": "a1d848f0-7b49-11ef-9ef6-0205a9f72d57",
            "StackName": "upload-action-test",
            "LogicalResourceId": "upload-action-test",
            "PhysicalResourceId": "arn:aws:cloudformation:eu-west-2:842766856468:stack/upload-action-test/e8757440-7b26-11ef-b77c-0622e8144257",
            "ResourceType": "AWS::CloudFormation::Stack",
            "Timestamp": future_date,
            "ResourceStatus": "UPDATE_COMPLETE"
        },
        {
            "StackId": "arn:aws:cloudformation:eu-west-2:842766856468:stack/upload-action-test/e8757440-7b26-11ef-b77c-0622e8144257",
            "EventId": "HelloWorldFunctionVersion8f8068e4d5-3a54d4be-da56-4ec0-93b4-7d7573fdd9f8",
            "StackName": "upload-action-test",
            "LogicalResourceId": "HelloWorldFunctionVersion8f8068e4d5",
            "PhysicalResourceId": "arn:aws:lambda:eu-west-2:842766856468:function:upload-action-test-HelloWorldFunction-1eBRNHdkwwyq:2",
            "ResourceType": "AWS::Lambda::Version",
            "Timestamp": future_date,
            "ResourceStatus": "DELETE_SKIPPED"
        },
        {
            "StackId": "arn:aws:cloudformation:eu-west-2:842766856468:stack/upload-action-test/e8757440-7b26-11ef-b77c-0622e8144257",
            "EventId": "a0f34020-7b49-11ef-b2ab-0ae979326cf3",
            "StackName": "upload-action-test",
            "LogicalResourceId": "upload-action-test",
            "PhysicalResourceId": "arn:aws:cloudformation:eu-west-2:842766856468:stack/upload-action-test/e8757440-7b26-11ef-b77c-0622e8144257",
            "ResourceType": "AWS::CloudFormation::Stack",
            "Timestamp": future_date,
            "ResourceStatus": "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS"
        }
    ]
}
next_response = {
    "StackEvents": [
        {
            "StackId": "arn:aws:cloudformation:eu-west-2:842766856468:stack/upload-action-test/e8757440-7b26-11ef-b77c-0622e8144257",
            "EventId": "a1d848f0-7b49-11ef-9ef6-0205a9f72d57",
            "StackName": "upload-action-test",
            "LogicalResourceId": "upload-action-test",
            "PhysicalResourceId": "arn:aws:cloudformation:eu-west-2:842766856468:stack/upload-action-test/e8757440-7b26-11ef-b77c-0622e8144257",
            "ResourceType": "AWS::CloudFormation::Stack",
            "Timestamp": future_date,
            "ResourceStatus": "ROLLBACK_IN_PROGRESS"
        }
    ]
}

expected_params = {'StackName': 'upload-action-test'}

stubber.activate()

class CheckApiCall(unittest.TestCase):

    def test_bad_exit(self):
        with mock.patch('boto3.client', mock.MagicMock(return_value=cloudformation)):
            now_date = datetime.now(timezone.utc)
            with self.assertRaises(SystemExit) as cm:
                stubber.add_response('describe_stack_events', next_response, expected_params)
                api_call.wait_for_stack_status( now_date, 3)
            self.assertEqual(cm.exception.code, 65)

    def test_good_exit(self):
        with mock.patch('boto3.client', mock.MagicMock(return_value=cloudformation)):
            now_date = datetime.now(timezone.utc)
            stubber.add_response('describe_stack_events', response, expected_params)
            returnVal = api_call.wait_for_stack_status( now_date, 3)
            self.assertEqual(returnVal, None)

if __name__ == '__main__':
    unittest.main()
