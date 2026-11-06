"""Media Notification Lambda — send SNS alerts on workflow completion or failure."""
import json, logging, os, boto3
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)
sns   = boto3.client("sns")
ddb   = boto3.resource("dynamodb")
TOPIC = os.environ.get("ALERTS_TOPIC", "")
TABLE = os.environ.get("CONTENT_TABLE_NAME", "")
ENV   = os.environ.get("ENVIRONMENT", "dev")

def lambda_handler(event, context):
    action  = event.get("action", "notify_success")
    payload = event.get("input", event)
    content_id = _extract_content_id(payload)

    if action == "notify_success":
        msg = f"✅ Media platform [{ENV.upper()}] Content READY: {content_id}\nHLS: /vod/{content_id}/hls/index.m3u8\nTime: {datetime.now(timezone.utc).isoformat()}"
        subject = f"[Media platform] Content Processing Complete — {content_id}"
    else:
        error = payload.get("error", {})
        msg = f"❌ Media platform [{ENV.upper()}] Processing FAILED: {content_id}\nError: {json.dumps(error, default=str)}\nTime: {datetime.now(timezone.utc).isoformat()}"
        subject = f"[Media platform] Content Processing Failed — {content_id}"
        _update_failed_status(content_id)

    if TOPIC:
        try:
            sns.publish(TopicArn=TOPIC, Subject=subject, Message=msg)
            logger.info("Notification sent for content: %s", content_id)
        except Exception as exc:
            logger.error("SNS publish failed: %s", exc)

    return {"content_id": content_id, "notification_sent": bool(TOPIC), "action": action}

def _extract_content_id(payload):
    for key in ["content_id", "Payload"]:
        v = payload.get(key, {})
        if isinstance(v, dict):
            cid = v.get("content_id")
            if cid:
                return cid
    return payload.get("content_id", "unknown")

def _update_failed_status(content_id):
    if not TABLE or content_id == "unknown":
        return
    try:
        ddb.Table(TABLE).update_item(
            Key={"content_id": content_id, "version": 1},
            UpdateExpression="SET #s = :s, updated_at = :t",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": "FAILED", ":t": datetime.now(timezone.utc).isoformat()}
        )
    except Exception as exc:
        logger.warning("Status update failed: %s", exc)
