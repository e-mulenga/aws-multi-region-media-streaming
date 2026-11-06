"""
Media Ingestion Lambda
======================
Called by the Step Functions media processing workflow.
Actions: validate | transcode | check_status | update_metadata
"""
import json, logging, os, boto3
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

QUEUE_ARN       = os.environ.get("MEDIACONVERT_QUEUE_ARN", "")
ROLE_ARN        = os.environ.get("MEDIACONVERT_ROLE_ARN", "")
OUTPUT_BUCKET   = os.environ.get("OUTPUT_BUCKET", "")
CONTENT_TABLE   = os.environ.get("CONTENT_TABLE_NAME", "")
ENVIRONMENT     = os.environ.get("ENVIRONMENT", "dev")
REGION          = os.environ.get("AWS_REGION", "af-south-1")

mc_client   = None   # lazy init — MediaConvert needs endpoint discovery
s3          = boto3.client("s3")
dynamodb    = boto3.resource("dynamodb")


def _get_mediaconvert_client():
    global mc_client
    if mc_client:
        return mc_client
    endpoints = boto3.client("mediaconvert", region_name=REGION).describe_endpoints()
    endpoint  = endpoints["Endpoints"][0]["Url"]
    mc_client = boto3.client("mediaconvert", region_name=REGION, endpoint_url=endpoint)
    return mc_client


def lambda_handler(event, context):
    action  = event.get("action", "validate")
    payload = event.get("input", event)
    logger.info("Media ingestion — action: %s", action)

    dispatch = {
        "validate"        : _validate,
        "transcode"       : _transcode,
        "check_status"    : _check_status,
        "update_metadata" : _update_metadata,
    }
    return dispatch.get(action, _validate)(payload)


def _validate(payload):
    detail = payload.get("detail", {})
    bucket = detail.get("bucket", {}).get("name", "")
    key    = detail.get("object", {}).get("key", "")
    size   = detail.get("object", {}).get("size", 0)

    if not bucket or not key:
        return {"valid": False, "error": "Missing bucket or key in event"}

    try:
        head = s3.head_object(Bucket=bucket, Key=key)
        file_size = head["ContentLength"]
        content_type = head.get("ContentType", "")
        logger.info("Validated: s3://%s/%s (%d bytes)", bucket, key, file_size)
        return {
            "valid"       : True,
            "bucket"      : bucket,
            "key"         : key,
            "size_bytes"  : file_size,
            "content_type": content_type,
            "content_id"  : key.replace("/", "-").replace(".", "-")[:64],
        }
    except Exception as exc:
        logger.error("Validation failed: %s", exc)
        return {"valid": False, "error": str(exc)}


def _transcode(payload):
    validation = payload.get("validation", {}).get("Payload", payload)
    bucket     = validation.get("bucket", "")
    key        = validation.get("key", "")
    content_id = validation.get("content_id", "unknown")

    if not bucket or not key:
        raise ValueError("Missing bucket or key for transcoding")

    mc = _get_mediaconvert_client()

    job_settings = {
        "Role": ROLE_ARN,
        "Queue": QUEUE_ARN,
        "UserMetadata": {
            "content_id" : content_id,
            "environment": ENVIRONMENT,
            "source_key" : key,
        },
        "Settings": {
            "Inputs": [{
                "FileInput": f"s3://{bucket}/{key}",
                "AudioSelectors": {"Audio Selector 1": {"DefaultSelection": "DEFAULT"}},
                "VideoSelector": {},
                "TimecodeSource": "ZEROBASED",
            }],
            "OutputGroups": [
                {
                    "Name": "HLS",
                    "OutputGroupSettings": {
                        "Type": "HLS_GROUP_SETTINGS",
                        "HlsGroupSettings": {
                            "Destination": f"s3://{OUTPUT_BUCKET}/vod/{content_id}/hls/index",
                            "SegmentLength" : 6,
                            "MinSegmentLength": 0,
                        }
                    },
                    "Outputs": [
                        {"AudioDescriptions": [{"CodecSettings": {"Codec": "AAC", "AacSettings": {"Bitrate": 96000, "CodingMode": "CODING_MODE_2_0", "SampleRate": 48000}}}], "ContainerSettings": {"Container": "M3U8"}, "NameModifier": "_1080p", "VideoDescription": {"Width": 1920, "Height": 1080, "CodecSettings": {"Codec": "H_264", "H264Settings": {"Bitrate": 8000000, "RateControlMode": "CBR"}}}},
                        {"AudioDescriptions": [{"CodecSettings": {"Codec": "AAC", "AacSettings": {"Bitrate": 96000, "CodingMode": "CODING_MODE_2_0", "SampleRate": 48000}}}], "ContainerSettings": {"Container": "M3U8"}, "NameModifier": "_720p",  "VideoDescription": {"Width": 1280, "Height": 720,  "CodecSettings": {"Codec": "H_264", "H264Settings": {"Bitrate": 4000000, "RateControlMode": "CBR"}}}},
                        {"AudioDescriptions": [{"CodecSettings": {"Codec": "AAC", "AacSettings": {"Bitrate": 96000, "CodingMode": "CODING_MODE_2_0", "SampleRate": 48000}}}], "ContainerSettings": {"Container": "M3U8"}, "NameModifier": "_480p",  "VideoDescription": {"Width": 854,  "Height": 480,  "CodecSettings": {"Codec": "H_264", "H264Settings": {"Bitrate": 1500000, "RateControlMode": "CBR"}}}},
                        {"AudioDescriptions": [{"CodecSettings": {"Codec": "AAC", "AacSettings": {"Bitrate": 96000, "CodingMode": "CODING_MODE_2_0", "SampleRate": 48000}}}], "ContainerSettings": {"Container": "M3U8"}, "NameModifier": "_360p",  "VideoDescription": {"Width": 640,  "Height": 360,  "CodecSettings": {"Codec": "H_264", "H264Settings": {"Bitrate": 800000,  "RateControlMode": "CBR"}}}},
                    ]
                }
            ]
        }
    }

    job = mc.create_job(**job_settings)
    job_id = job["Job"]["Id"]
    logger.info("MediaConvert job created: %s for content: %s", job_id, content_id)
    return {"job_id": job_id, "content_id": content_id, "bucket": bucket, "key": key}


def _check_status(payload):
    transcoding = payload.get("transcoding", {}).get("Payload", payload)
    job_id      = transcoding.get("job_id", "")
    content_id  = transcoding.get("content_id", "")

    if not job_id:
        return {"job_status": "ERROR", "error": "No job_id found"}

    mc  = _get_mediaconvert_client()
    job = mc.get_job(Id=job_id)
    status = job["Job"]["Status"]

    logger.info("Job %s status: %s", job_id, status)
    return {
        "job_id"      : job_id,
        "job_status"  : status,
        "content_id"  : content_id,
        "progress"    : job["Job"].get("JobPercentComplete", 0),
        "bucket"      : transcoding.get("bucket", ""),
        "key"         : transcoding.get("key", ""),
    }


def _update_metadata(payload):
    status     = payload.get("status", {}).get("Payload", payload)
    content_id = status.get("content_id", "unknown")
    now        = datetime.now(timezone.utc).isoformat()

    try:
        table = dynamodb.Table(CONTENT_TABLE)
        table.put_item(Item={
            "content_id"   : content_id,
            "version"      : 1,
            "status"       : "READY",
            "created_at"   : now,
            "updated_at"   : now,
            "environment"  : ENVIRONMENT,
            "hls_url"      : f"/vod/{content_id}/hls/index.m3u8",
            "source_key"   : status.get("key", ""),
            "job_id"       : status.get("job_id", ""),
        })
        logger.info("Metadata updated for content: %s", content_id)
        return {"content_id": content_id, "status": "READY", "updated_at": now}
    except Exception as exc:
        logger.error("Metadata update failed: %s", exc)
        return {"content_id": content_id, "status": "ERROR", "error": str(exc)}
