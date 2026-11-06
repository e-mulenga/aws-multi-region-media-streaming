#!/usr/bin/env python3
"""Generate architecture/diagrams/*.png (pip install diagrams; needs graphviz `dot`).

Colour convention:
  blue   = consumed from the AWS Enterprise Landing Zone (read via remote state, never recreated)
  amber  = created by this repository in af-south-1
  green  = eu-west-1 (DR region, and home of services not available in af-south-1)
  purple = global-service control plane in us-east-1 (CloudFront / WAF / alarms only, no workloads)
The diagrams show the INTENDED design; they are not evidence of a deployed environment.
"""
import os
from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Lambda
from diagrams.aws.database import Dynamodb, Aurora
from diagrams.aws.integration import StepFunctions, Eventbridge, SNS
from diagrams.aws.management import Cloudwatch, Organizations
from diagrams.aws.media import ElementalMediaconvert, ElementalMediapackage
from diagrams.aws.network import CF, APIGateway, Route53, VPC
from diagrams.aws.security import WAF, Shield, KMS, SecretsManager, CertificateManager, IAM
from diagrams.aws.storage import S3, Backup
from diagrams.aws.general import Users
from diagrams.onprem.vcs import Github

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "architecture", "diagrams")
os.makedirs(OUT, exist_ok=True)
LZ = {"bgcolor": "#E8F0FE", "pencolor": "#1A73E8", "style": "rounded", "fontsize": "13"}
NEW = {"bgcolor": "#FFF4E0", "pencolor": "#FF9900", "style": "rounded", "fontsize": "13"}
DR = {"bgcolor": "#EAF7EA", "pencolor": "#2E7D32", "style": "rounded", "fontsize": "13"}
EDGE = {"bgcolor": "#F3E8FD", "pencolor": "#7B1FA2", "style": "rounded", "fontsize": "13"}
G = {"fontsize": "20", "pad": "0.5", "nodesep": "0.6", "ranksep": "0.9"}


def d(name, title, direction="LR"):
    return Diagram(title, filename=os.path.join(OUT, name), show=False, direction=direction, graph_attr=G, outformat="png")


with d("executive-architecture", "Media streaming platform - executive view (design)"):
    viewers = Users("Viewers")
    creators = Users("Content teams")
    with Cluster("Landing Zone (consumed)", graph_attr=LZ):
        lz = Organizations("Network, DNS zone, TLS cert,\nkeys strategy, alerts topic")
    with Cluster("Global edge (us-east-1 control plane)", graph_attr=EDGE):
        cdn = CF("CloudFront + WAF")
    with Cluster("af-south-1 (created)", graph_attr=NEW):
        pipe = ElementalMediaconvert("Upload -> transcode\n-> publish pipeline")
        media = S3("Processed media")
        api = APIGateway("Catalogue and\nanalytics API")
    with Cluster("eu-west-1 (DR + services not in af-south-1)", graph_attr=DR):
        live = ElementalMediapackage("Live packaging\n(MediaPackage)")
        rep = S3("Replica + standby data")
    creators >> pipe
    viewers >> cdn >> api
    pipe >> media
    cdn >> media
    cdn >> live
    media >> rep
    lz - Edge(style="dotted") - pipe

with d("landing-zone-integration", "Landing Zone integration: consumed vs created", direction="TB"):
    with Cluster("Landing Zone (consumed - never recreated)", graph_attr=LZ):
        net = VPC("VPCs, DB subnet groups\n(af-south-1, eu-west-1)")
        dns = Route53("Route 53 zone")
        cert = CertificateManager("CloudFront cert\n(us-east-1)")
        keys = KMS("key_strategy,\nshared_kms_keys")
        alerts = SNS("monitoring_topic_arn")
        state = S3("Remote state\n(contract v2)")
    with Cluster("This repository (created)", graph_attr=NEW):
        cf = CF("CloudFront + WAF")
        st = S3("Media buckets")
        db = Dynamodb("Metadata tables")
        wf = StepFunctions("Workflow")
        aur = Aurora("Aurora (optional)")
    state >> wf
    dns >> cf
    cert >> cf
    keys >> st
    keys >> db
    alerts << wf
    net >> aur

with d("logical-architecture", "Logical architecture and trust boundaries"):
    users = Users("Internet")
    with Cluster("Edge (us-east-1 control plane)", graph_attr=EDGE):
        waf = WAF("WAF")
        cf = CF("CloudFront")
    with Cluster("af-south-1", graph_attr=NEW):
        api = APIGateway("HTTP API")
        fn = Lambda("content / analytics")
        s3 = S3("processed bucket")
        ddb = Dynamodb("DynamoDB")
    with Cluster("eu-west-1", graph_attr=DR):
        s3dr = S3("replica bucket")
        mp = ElementalMediapackage("MediaPackage")
    users >> waf >> cf
    cf >> Edge(label="/api/*") >> api >> fn >> ddb
    cf >> Edge(label="default (OAC)") >> s3
    cf >> Edge(label="failover", style="dashed") >> s3dr
    cf >> Edge(label="/out/*") >> mp

with d("network-architecture", "Network and traffic architecture", direction="TB"):
    users = Users("Viewers")
    with Cluster("Public edge", graph_attr=EDGE):
        cf = CF("CloudFront (HTTPS only,\nTLS 1.2+)")
    with Cluster("Landing Zone VPC af-south-1 (consumed)", graph_attr=LZ):
        vpc = VPC("DB subnets only used here\n(no NAT, no endpoints in LZ)")
        aur = Aurora("Aurora primary\n(optional, SG 5432 from VPC CIDR)")
    with Cluster("Outside the VPC (regional service endpoints)", graph_attr=NEW):
        api = APIGateway("HTTP API")
        fn = Lambda("Lambda (not VPC-attached)")
        ddb = Dynamodb("DynamoDB")
    with Cluster("Landing Zone VPC eu-west-1 (consumed)", graph_attr=DR):
        aur2 = Aurora("Aurora secondary")
    users >> cf >> api >> fn >> ddb
    vpc - aur
    aur >> Edge(label="global replication") >> aur2

with d("security-architecture", "Security architecture and control mapping", direction="TB"):
    with Cluster("Preventive", graph_attr=NEW):
        waf = WAF("WAF: rate limit +\nmanaged rules")
        shield = Shield("Shield Advanced\n(optional)")
        oac = CF("OAC: buckets are\nnever public")
        jwt = APIGateway("JWT authorizer\non write routes")
    with Cluster("Data protection", graph_attr=LZ):
        keys = KMS("dev: AWS-managed keys\nstage/prod: LZ CMKs")
        sm = SecretsManager("Secrets Manager\n(MediaPackage CDN secret,\nAurora master password)")
    with Cluster("Detective", graph_attr=NEW):
        cw = Cloudwatch("Alarms, WAF logs,\nAPI access logs")
        sns = SNS("LZ alerts topic")
    waf >> oac
    jwt >> keys
    keys >> sm
    cw >> sns

with d("data-flow-diagram", "Ingest-to-playback data flow"):
    creator = Users("Content team")
    with Cluster("af-south-1", graph_attr=NEW):
        ing = S3("ingestion bucket")
        eb = Eventbridge("S3 event")
        sf = StepFunctions("workflow")
        lam = Lambda("ingestion Lambda")
        mc = ElementalMediaconvert("MediaConvert (HLS)")
        proc = S3("processed bucket")
        ddb = Dynamodb("content metadata")
    with Cluster("eu-west-1", graph_attr=DR):
        dr = S3("replica")
        ddbr = Dynamodb("metadata replica")
    viewer = Users("Viewer")
    cf = CF("CloudFront")
    creator >> ing >> eb >> sf >> lam >> mc >> proc
    lam >> ddb
    proc >> Edge(label="CRR") >> dr
    ddb >> Edge(label="global table") >> ddbr
    viewer >> cf >> proc

with d("disaster-recovery-diagram", "Disaster recovery: af-south-1 -> eu-west-1"):
    with Cluster("af-south-1 (primary)", graph_attr=NEW):
        p_s3 = S3("processed")
        p_ddb = Dynamodb("metadata")
        p_aur = Aurora("Aurora primary")
        p_bk = Backup("Backup vault")
    with Cluster("eu-west-1 (DR)", graph_attr=DR):
        d_s3 = S3("replica")
        d_ddb = Dynamodb("replica table")
        d_aur = Aurora("Aurora secondary")
        d_bk = Backup("DR vault")
    with Cluster("Edge (us-east-1 control plane)", graph_attr=EDGE):
        r53 = Route53("Health check")
        cf = CF("CloudFront\norigin failover")
    p_s3 >> Edge(label="CRR") >> d_s3
    p_ddb >> Edge(label="global table") >> d_ddb
    p_aur >> Edge(label="Aurora Global") >> d_aur
    p_bk >> Edge(label="copy") >> d_bk
    r53 >> Edge(label="alarm -> human decision") >> cf
    cf >> Edge(style="dashed", label="5xx failover") >> d_s3

with d("terraform-deployment-diagram", "Terraform deployment, CI/CD and environment promotion"):
    gh = Github("GitHub Actions\n(ci + security)")
    with Cluster("Landing Zone (consumed)", graph_attr=LZ):
        st = S3("State bucket\n(partial backend config)")
        oidc = IAM("GitHub OIDC provider")
    with Cluster("Stacks", graph_attr=NEW):
        dev = Organizations("dev\nAWS-managed keys")
        stg = Organizations("stage\nCMK")
        prod = Organizations("prod\nCMK")
    gh >> oidc
    gh >> Edge(label="fmt, validate, tfsec,\ncheckov, gitleaks, trivy") >> dev
    dev >> Edge(label="manual promote") >> stg >> prod
    st - Edge(style="dotted") - dev
