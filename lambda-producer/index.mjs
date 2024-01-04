/**
 *
 * Event doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html#api-gateway-simple-proxy-for-lambda-input-format
 * @param {Object} event - API Gateway Lambda Proxy Input Format
 *
 * Context doc: https://docs.aws.amazon.com/lambda/latest/dg/nodejs-prog-model-context.html 
 * @param {Object} context
 *
 * Return doc: https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-lambda-proxy-integrations.html
 * @returns {Object} object - API Gateway Lambda Proxy Output Format
 * 
 */

import { DynamoDBClient, ScanCommand } from "@aws-sdk/client-dynamodb";

import { SQSClient, GetQueueUrlCommand, SendMessageCommand } from "@aws-sdk/client-sqs";

const dynamodb = new DynamoDBClient({ region: 'us-west-2' });


const sqs = new SQSClient({ region: 'us-west-2' });





export const handler = async (event, context) => {
    try {

        const tableName = process.env.TABLE_NAME;

        const queueName = process.env.QUEUE_NAME;

        const accountId = process.env.ACCOUNT_ID

        const params = { TableName: tableName };

        const data = await dynamodb.send(new ScanCommand(params));

        for (const item of data.Items) {
            const title = item['name']['S'];

            const queueUrl = await getQueueUrl(queueName, accountId);

            const message = {
                MessageBody: title,
                QueueUrl: queueUrl
            };

            await sqs.send(new SendMessageCommand(message));


        }

        return {
            'statusCode': 200,
            'body': JSON.stringify({
                message: 'hello world',
            })
        }
    } catch (err) {
        console.log(err);
        return err;
    }
};


async function getQueueUrl(queueName, accountId) {
    const params = {
        QueueName: queueName,
        QueueOwnerAWSAccountId: accountId
    };

    const command = new GetQueueUrlCommand(params);
    const data = await sqs.send(command);
    return data.QueueUrl;
}