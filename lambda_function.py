import json
import boto3
import datetime
import os
from botocore.exceptions import ClientError
s3 = boto3.client('s3')
dynamodb = boto3.client('dynamodb')
kms = boto3.client('kms')

def lambda_handler(event, context):

    bucketName = event['detail']['requestParameters']['bucketName']

    res1 = check_s3_encryption(bucketName)

    if res1['encryptionStatus']=="AWS S3 Encryption" or res1['encryptionStatus']=="No Encryption":
        
        print("Calling function to check if exception exists for bucket encryption")
        response_exception=check_exception(bucketName)

        if response_exception['exceptionStatus'] == 'None':
            print("No exception present for bucket:", bucketName)
            print("Calling function to encrypt with AWS KMS")
            encrypt_s3(bucketName)
        
        if response_exception['exceptionStatus'] == 'Yes':
            print("Exception still in effect for Bucket: %s. Expiration is: %s. Bucket will not be encrypted" %(bucketName,response_exception['response']['Item']['expiry']['S']) )
            print("Nothing to do. Exiting")
            return
        
    if res1['encryptionStatus'] == "KMS CMEK Encryption":
        print("Nothing to do. Alredy encrypted with KMS CMEK.")
        print("Checking if the encryption key is enabled for rotation...")
        
        enable_key_rotation(bucketName, res1['rules'])
        
    if res1['encryptionStatus'] == "N/A":
        print("Recieved an error while checking for encryption")
        print(res1['error'])
        
        
def check_s3_encryption(bucketName):

    try:
        enc = s3.get_bucket_encryption(Bucket=bucketName)
        rules = enc['ServerSideEncryptionConfiguration']['Rules']
        encryption = rules[0]['ApplyServerSideEncryptionByDefault']['SSEAlgorithm']
        if encryption == "AES256":
            print('Bucket: %s, AWS S3 Encryption: %s' % (bucketName, rules))
            return {
                'encryptionStatus': 'AWS S3 Encryption'
            }
        if encryption == "aws:kms":
            print('Bucket: %s, KMS CMEK Encryption: %s' % (bucketName, rules))
            return {
                'encryptionStatus': 'KMS CMEK Encryption',
                'rules': rules
            }
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'ServerSideEncryptionConfigurationNotFoundError':
            print('Bucket: %s, no server-side encryption' % (bucketName))
            return {
                'encryptionStatus': 'No Encryption'
            }
        else:
            return {
                'encryptionStatus': 'N/A',
                'error': e.response
            }


def encrypt_s3(bucketName):
    
    kmskey = os.environ['ExceptionTableName'])
    response = s3.put_bucket_encryption(
    Bucket=bucketName,
    ServerSideEncryptionConfiguration={
        'Rules': [
            {
                'ApplyServerSideEncryptionByDefault': {
                    'SSEAlgorithm': 'aws:kms',
                    'KMSMasterKeyID': kmskey
                }
            },
        ]
    }
    )
    if response['ResponseMetadata']['HTTPStatusCode'] == 200:
        print("Successfully encrypted bucket:",bucketName)
        print("Calling recording function to log the action taken")
        
        record_action('encrypt',bucketName,kmskey,response)
        
    else:
        print("Error received while encryption:")
        print(response)
        
def record_action(type,resourceName,kmskey,response):
    
    if type == 'encrypt':
        Message = 'S3 bucket encryption event recorded'
    
    if type == 'rotate':
        Message = 'KMS key enabled for auto rotation event recorded'
        
    try:
        resp_action = dynamodb.put_item(
        TableName=os.environ['RecordingTableName']),
        Item={
            'Message': {
                'S': Message,
            },
            'ResourceName': {
                'S': resourceName,
            },
            'KMSKey': {
                'S': kmskey,
            },
            'Timestamp': {
                'S': response['ResponseMetadata']['HTTPHeaders']['date'],
            },        
        } 
        )

    except ClientError as e:
        print("Exception received while recording event in DynamoDB. Please check the below error")
        print(e)
        
    if resp_action['ResponseMetadata']['HTTPStatusCode'] == 200:
        print("Successfully recorded message for Bucket: %s , KMS Key: %s" % (resourceName,kmskey))
        
def enable_key_rotation(bucketName,rules):
    
    kmsKey = rules[0]['ApplyServerSideEncryptionByDefault']['KMSMasterKeyID']
    try:
        response1 = kms.get_key_rotation_status(
        KeyId = kmsKey
        )
    
        if response1['KeyRotationEnabled'] == 'True':
            print("Automatic Key rotation is already enabled")
            exit(0)
        else:
            print("Automatic Key rotation is not enabled. Enabling rotation now..")
        
        try:
            response2 = kms.enable_key_rotation(
            KeyId = kmsKey
            )
            
            if response2['ResponseMetadata']['HTTPStatusCode'] == 200:
                print("Automatic key rotation now enabled")
                print("Calling recording function to log the action taken")
                
                record_action('rotate',bucketName,kmsKey,response2)
        
        except ClientError as e2:
            
            print("Exception received while enabling automatic key rotation. Please check the below error")
            print(e2)

    except ClientError as e1:   
        print("Exception received while checking for automatic key rotation. Please check the below error")
        print(e1)

def check_exception(bucketName):
            
    try:
        
        response = dynamodb.get_item(
        TableName=os.environ['ExceptionTableName'],
        Key={
            'ResourceName': {
                'S': bucketName
            }
        },
        ConsistentRead=True
        )
        
        if "Item" in response:

            if response['Item']['expiry']['S'] == "None":
                return {
                    'exceptionStatus': 'Yes',
                    'response': response
                }

            expiry=datetime.datetime.strptime(response['Item']['expiry']['S'], "%m/%d/%y %H:%M")
            
            if expiry > datetime.datetime.now():
                return {
                    'exceptionStatus': 'Yes',
                    'response': response
                }
            else:
                return {
                    'exceptionStatus': 'None',
                    'response': response
                }
        else:
            return {
                'exceptionStatus': 'None',
                'response': response
            }
    
    except ClientError as e:
        print("Error received while getting item from DynamoDB. Please check the below error")
        print(e)