"""
Writer Lambda — Second half of the pipeline.

Triggered by SQS, reads batches of transformed records,
writes them to DynamoDB, emits CloudWatch metrics.
"""

import json
import os
import time
import logging
import boto3
from datetime import datetime, timezone, timedelta
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def log(level, message, **kwargs):
    """Structured JSON logging — same pattern as processor Lambda."""
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "level": level,
        "message": message,
        "function": os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "local"),
        **kwargs
    }
    getattr(logger, level.lower())(json.dumps(entry))


# -------------------------------------------------------
# AWS CLIENTS — initialized outside handler for warm reuse
# -------------------------------------------------------
dynamodb = boto3.resource("dynamodb")
cloudwatch = boto3.client("cloudwatch")

TABLE_NAME   = os.environ["DYNAMODB_TABLE_NAME"]
ENVIRONMENT  = os.environ.get("ENVIRONMENT", "prod")
PROJECT_NAME = os.environ.get("PROJECT_NAME", "serverless-pipeline")

# Get the table object once — reused across warm invocations
table = dynamodb.Table(TABLE_NAME)


def push_metric(metric_name, value, unit="Count"):
    """Push custom metric to CloudWatch under ServerlessPipeline/Writer namespace."""
    try:
        cloudwatch.put_metric_data(
            Namespace=f"{PROJECT_NAME}/Writer",
            MetricData=[
                {
                    "MetricName": metric_name,
                    "Value": value,
                    "Unit": unit,
                    "Dimensions": [
                        {"Name": "Environment", "Value": ENVIRONMENT}
                    ],
                    "Timestamp": datetime.now(timezone.utc),
                }
            ],
        )
    except Exception as e:
        log("WARNING", "Failed to push metric", metric=metric_name, error=str(e))


def write_record_to_dynamodb(record: dict) -> bool:
    """
    Write a single record to DynamoDB.

    Uses put_item with a condition expression to prevent
    overwriting an existing record with the same record_id.
    Returns True on success, False on failure.
    """
    try:
        # Add TTL — DynamoDB will auto-delete this item after 90 days
        # expires_at must be a Unix timestamp integer for TTL to work
        expiry = datetime.now(timezone.utc) + timedelta(days=90)
        record["expires_at"] = int(expiry.timestamp())

        table.put_item(
            Item=record,
            # Only write if this record_id doesn't already exist
            # Prevents duplicate writes if SQS delivers the message twice
            ConditionExpression="attribute_not_exists(record_id)"
        )
        return True

    except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
        # Record already exists — this is fine, just a duplicate delivery
        log("INFO", "Duplicate record skipped",
            record_id=record.get("record_id"))
        return True  # not a failure — idempotent behavior

    except Exception as e:
        log("ERROR", "Failed to write record to DynamoDB",
            record_id=record.get("record_id"),
            error=str(e),
            error_type=type(e).__name__)
        return False


def handler(event, context):
    """
    Main handler — SQS triggers this with a batch of messages.

    'event' contains a list of SQS messages under event["Records"].
    Each message body is a JSON string of one transformed record.

    IMPORTANT: SQS batch handling has a specific contract —
    if this function raises an exception, SQS retries the ENTIRE batch.
    We use partial batch failure reporting instead, so only failed
    messages get retried, not the whole batch.
    """
    invocation_start = time.perf_counter()
    lambda_request_id = context.aws_request_id
    batch_size = len(event.get("Records", []))

    log("INFO", "Writer Lambda invoked",
        request_id=lambda_request_id,
        batch_size=batch_size)

    push_metric("BatchSize", batch_size)

    success_count = 0
    failure_count = 0

    # Track which messages failed — for partial batch failure reporting
    # This tells SQS to only retry the specific failed messages
    batch_item_failures = []

    for sqs_message in event.get("Records", []):
        message_id    = sqs_message["messageId"]
        receipt_handle = sqs_message["receiptHandle"]
        write_start   = time.perf_counter()

        try:
            # Parse the message body back into a dict
            record = json.loads(sqs_message["body"])

            log("INFO", "Writing record",
                record_id=record.get("record_id"),
                source_key=record.get("source_key"))

            success = write_record_to_dynamodb(record)

            if success:
                success_count += 1
                write_latency_ms = (time.perf_counter() - write_start) * 1000
                push_metric("WriteLatency", write_latency_ms, unit="Milliseconds")
                log("INFO", "Record written successfully",
                    record_id=record.get("record_id"),
                    latency_ms=round(write_latency_ms, 2))
            else:
                failure_count += 1
                # Report this specific message as failed
                # SQS will retry only this message, not the whole batch
                batch_item_failures.append(
                    {"itemIdentifier": message_id}
                )

        except json.JSONDecodeError as e:
            # Malformed message body — can never succeed, send straight to DLQ
            log("ERROR", "Malformed SQS message body — sending to DLQ",
                message_id=message_id,
                error=str(e))
            # Don't add to batch_item_failures — let it go to DLQ immediately
            failure_count += 1

        except Exception as e:
            log("ERROR", "Unexpected error processing message",
                message_id=message_id,
                error=str(e),
                error_type=type(e).__name__)
            failure_count += 1
            batch_item_failures.append({"itemIdentifier": message_id})

    # Push aggregate metrics for this invocation
    total_latency_ms = (time.perf_counter() - invocation_start) * 1000
    push_metric("RecordsWritten", success_count)
    push_metric("WriteFailures", failure_count)
    push_metric("InvocationLatency", total_latency_ms, unit="Milliseconds")

    log("INFO", "Invocation complete",
        success_count=success_count,
        failure_count=failure_count,
        total_latency_ms=round(total_latency_ms, 2))

    # Return partial batch failure report to SQS
    # Empty list = all messages succeeded
    return {"batchItemFailures": batch_item_failures}