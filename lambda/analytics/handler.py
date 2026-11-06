"""Media platform Analytics Lambda — viewer event tracking and engagement metrics."""
import json, logging, os, uuid, boto3
from datetime import datetime, timezone
from boto3.dynamodb.conditions import Key

logger = logging.getLogger()
logger.setLevel(logging.INFO)
ddb   = boto3.resource("dynamodb")
TABLE = os.environ.get("ANALYTICS_TABLE_NAME", "")
ENV   = os.environ.get("ENVIRONMENT", "dev")

VALID_EVENTS = {"play", "pause", "seek", "complete", "buffer", "error", "quality_change"}

def lambda_handler(event, context):
    method      = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path        = event.get("rawPath", "/")
    path_params = event.get("pathParameters") or {}

    try:
        if method == "POST":
            body = json.loads(event.get("body", "{}"))
            return _record_event(body)
        elif method == "GET" and path_params.get("content_id"):
            qs = event.get("queryStringParameters") or {}
            return _get_analytics(path_params["content_id"], qs.get("period", "7d"))
        else:
            return _response(405, {"error": "Method not allowed"})
    except Exception as exc:
        logger.error("Analytics error: %s", exc, exc_info=True)
        return _response(500, {"error": "Internal server error"})

def _record_event(body):
    event_type = body.get("event_type", "")
    if event_type not in VALID_EVENTS:
        return _response(400, {"error": f"Invalid event_type. Must be one of: {', '.join(VALID_EVENTS)}"})

    now       = datetime.now(timezone.utc)
    event_id  = str(uuid.uuid4())
    ttl_epoch = int(now.timestamp()) + (90 * 86400)  # 90-day TTL

    item = {
        "event_id"      : event_id,
        "timestamp"     : now.isoformat(),
        "content_id"    : body.get("content_id", ""),
        "user_id"       : body.get("user_id", "anonymous"),
        "event_type"    : event_type,
        "playback_position": body.get("playback_position", 0),
        "quality"       : body.get("quality", "auto"),
        "player_version": body.get("player_version", "unknown"),
        "environment"   : ENV,
        "ttl"           : ttl_epoch,
    }
    ddb.Table(TABLE).put_item(Item=item)
    logger.info("Event recorded: %s for content: %s", event_type, item["content_id"])
    return _response(202, {"event_id": event_id, "recorded": True})

def _get_analytics(content_id, period):
    table = ddb.Table(TABLE)
    resp  = table.query(
        IndexName="content-analytics-index",
        KeyConditionExpression=Key("content_id").eq(content_id),
        Limit=1000,
        ScanIndexForward=False
    )
    items      = resp.get("Items", [])
    play_count = sum(1 for i in items if i.get("event_type") == "play")
    completes  = sum(1 for i in items if i.get("event_type") == "complete")
    completion  = round((completes / play_count * 100), 1) if play_count > 0 else 0

    return _response(200, {
        "content_id"          : content_id,
        "period"              : period,
        "total_events"        : len(items),
        "play_count"          : play_count,
        "completion_count"    : completes,
        "completion_rate_pct" : completion,
        "event_breakdown"     : {e: sum(1 for i in items if i.get("event_type") == e) for e in VALID_EVENTS}
    })

def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps(body, default=str)
    }
