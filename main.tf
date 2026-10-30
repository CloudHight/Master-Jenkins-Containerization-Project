locals {
  name = "team-1"
}

data "aws_route53_zone" "zone" {
  name         = var.domain_name
  private_zone = false

}
#calling acm certificate
data "aws_acm_certificate" "cert" {
  domain      = var.domain_name
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

# Customer managed KMS key (EBS, RDS, Secrets Manager, logs, SNS, backups)
module "kms" {
  source = "./module/kms"
  name   = local.name
  region = var.region
}

# Secrets in AWS Secrets Manager (replaces Vault)
module "secrets" {
  source          = "./module/secrets"
  name            = local.name
  kms_key_arn     = module.kms.key_arn
  ssh_private_key = module.vpc.private_key
}

module "vpc" {
  source = "./module/vpc"
  name   = local.name
  az1    = "eu-west-3a"
  az2    = "eu-west-3b"
}

module "Bastion" {
  source          = "./module/Bastion"
  name            = local.name
  vpc             = module.vpc.vpc_id
  subnets         = [module.vpc.public_subnet1_id, module.vpc.public_subnet2_id]
  keypair         = module.vpc.public_key
  region          = var.region
  cw_config_param = module.monitoring.cw_config_param
}

module "Ansible" {
  source             = "./module/Ansible"
  name               = local.name
  keypair            = module.vpc.public_key
  subnet_id          = module.vpc.private_subnet1_id
  vpc                = module.vpc.vpc_id
  bastion_key        = module.Bastion.bastion_sg
  region             = var.region
  nexus_registry     = module.nexus.nexus_registry
  nexus_secret_arn   = module.secrets.nexus_admin_secret_arn
  ssh_key_secret_arn = module.secrets.ssh_private_key_secret_arn
  kms_key_arn        = module.kms.key_arn
  cw_config_param    = module.monitoring.cw_config_param
}
module "database" {
  source                 = "./module/database"
  name                   = local.name
  private_subnet1_id     = module.vpc.private_subnet1_id
  private_subnet2_id     = module.vpc.private_subnet2_id
  bastion-security-group = module.Bastion.bastion_sg
  vpc-id                 = module.vpc.vpc_id
  stage-security-group   = module.stage-env.stage_sg
  prod-security-group    = module.prod-env.prod_sg
  kms_key_arn            = module.kms.key_arn
  deletion_protection    = var.db_deletion_protection
}

module "sonaqube" {
  source              = "./module/sonaqube"
  name                = local.name
  vpc                 = module.vpc.vpc_id
  keypair             = module.vpc.public_key
  subnet_id           = module.vpc.private_subnet1_id
  subnets             = [module.vpc.public_subnet1_id, module.vpc.public_subnet2_id]
  certificate         = data.aws_acm_certificate.cert.arn
  hosted_zone_id      = data.aws_route53_zone.zone.id
  domain_name         = var.domain_name
  region              = var.region
  kms_key_arn         = module.kms.key_arn
  sonar_db_secret_arn = module.secrets.sonar_db_secret_arn
  cw_config_param     = module.monitoring.cw_config_param
}

module "prod-env" {
  source           = "./module/prod-env"
  name             = local.name
  vpc-id           = module.vpc.vpc_id
  bastion          = module.Bastion.bastion_sg
  key-name         = module.vpc.public_key
  pri-subnet1      = module.vpc.private_subnet1_id
  pri-subnet2      = module.vpc.private_subnet2_id
  pub-subnet1      = module.vpc.public_subnet1_id
  pub-subnet2      = module.vpc.public_subnet2_id
  acm-cert-arn     = data.aws_acm_certificate.cert.arn
  domain           = var.domain_name
  ansible          = module.Ansible.ansible_sg
  region           = var.region
  nexus_registry   = module.nexus.nexus_registry
  nexus_secret_arn = module.secrets.nexus_admin_secret_arn
  db_secret_arn    = module.database.db_secret_arn
  kms_key_arn      = module.kms.key_arn
  cw_config_param  = module.monitoring.cw_config_param
}
module "stage-env" {
  source           = "./module/stage-env"
  name             = local.name
  vpc-id           = module.vpc.vpc_id
  bastion          = module.Bastion.bastion_sg
  key-name         = module.vpc.public_key
  pri-subnet1      = module.vpc.private_subnet1_id
  pri-subnet2      = module.vpc.private_subnet2_id
  pub-subnet1      = module.vpc.public_subnet1_id
  pub-subnet2      = module.vpc.public_subnet2_id
  acm-cert-arn     = data.aws_acm_certificate.cert.arn
  domain           = var.domain_name
  ansible          = module.Ansible.ansible_sg
  region           = var.region
  nexus_registry   = module.nexus.nexus_registry
  nexus_secret_arn = module.secrets.nexus_admin_secret_arn
  db_secret_arn    = module.database.db_secret_arn
  kms_key_arn      = module.kms.key_arn
  cw_config_param  = module.monitoring.cw_config_param
}

module "nexus" {
  source           = "./module/nexus"
  name             = local.name
  vpc              = module.vpc.vpc_id
  keypair          = module.vpc.public_key
  subnet_id        = module.vpc.private_subnet1_id
  subnets          = [module.vpc.public_subnet1_id, module.vpc.public_subnet2_id]
  certificate      = data.aws_acm_certificate.cert.arn
  hosted_zone_id   = data.aws_route53_zone.zone.id
  domain_name      = var.domain_name
  region           = var.region
  kms_key_arn      = module.kms.key_arn
  nexus_secret_arn = module.secrets.nexus_admin_secret_arn
  cw_config_param  = module.monitoring.cw_config_param
}

# WAF: user -> WAF -> ALB -> private app tier
module "waf_app" {
  source      = "./module/waf"
  name        = "${local.name}-app"
  kms_key_arn = module.kms.key_arn
  alb_arns = {
    stage = module.stage-env.alb_arn
    prod  = module.prod-env.alb_arn
  }
}

# Tools get a higher rate limit and allow large uploads (docker push, scanner reports)
module "waf_tools" {
  source                      = "./module/waf"
  name                        = "${local.name}-tools"
  kms_key_arn                 = module.kms.key_arn
  rate_limit                  = 20000
  common_rule_count_overrides = ["SizeRestrictions_BODY"]
  # Artifact uploads (Maven PUT /repository/, Docker blob PATCH/PUT /v2/) are binary/JSON and trip the
  # body-inspection rules; those rules stay enforced on every other Nexus/SonarQube path
  rule_path_exemptions = {
    xss-body-uploads  = { rule = "CrossSiteScripting_BODY", label = "CrossSiteScripting_Body", paths = ["/repository/", "/v2/"] }
    ssrf-body-uploads = { rule = "EC2MetaDataSSRF_BODY", label = "EC2MetaDataSSRF_Body", paths = ["/repository/", "/v2/"] }
    lfi-body-uploads  = { rule = "GenericLFI_BODY", label = "GenericLFI_Body", paths = ["/repository/", "/v2/"] }
    rfi-body-uploads  = { rule = "GenericRFI_BODY", label = "GenericRFI_Body", paths = ["/repository/", "/v2/"] }
    sqli-body-uploads = { rule = "SQLi_BODY", label = "SQLi_Body", paths = ["/repository/", "/v2/"], rule_set = "sqli" }
  }
  alb_arns = {
    nexus     = module.nexus.alb_arn
    sonarqube = module.sonaqube.alb_arn
  }
}

# CloudWatch monitoring, logs and alerts
module "monitoring" {
  source      = "./module/monitoring"
  name        = local.name
  region      = var.region
  kms_key_arn = module.kms.key_arn
  vpc_id      = module.vpc.vpc_id
  alert_email = var.alert_email
  instances = {
    nexus     = module.nexus.instance_id
    sonarqube = module.sonaqube.instance_id
    ansible   = module.Ansible.instance_id
  }
  asgs = {
    bastion = module.Bastion.asg_name
    stage   = module.stage-env.asg_name
    prod    = module.prod-env.asg_name
  }
  load_balancers = {
    stage     = module.stage-env.alb_arn_suffix
    prod      = module.prod-env.alb_arn_suffix
    nexus     = module.nexus.alb_arn_suffix
    sonarqube = module.sonaqube.alb_arn_suffix
  }
  target_groups = {
    stage        = { lb_arn_suffix = module.stage-env.alb_arn_suffix, tg_arn_suffix = module.stage-env.tg_arn_suffix }
    prod         = { lb_arn_suffix = module.prod-env.alb_arn_suffix, tg_arn_suffix = module.prod-env.tg_arn_suffix }
    nexus        = { lb_arn_suffix = module.nexus.alb_arn_suffix, tg_arn_suffix = module.nexus.tg_arn_suffix }
    nexus-docker = { lb_arn_suffix = module.nexus.alb_arn_suffix, tg_arn_suffix = module.nexus.docker_tg_arn_suffix }
    sonarqube    = { lb_arn_suffix = module.sonaqube.alb_arn_suffix, tg_arn_suffix = module.sonaqube.tg_arn_suffix }
  }
  web_acls = {
    app   = module.waf_app.web_acl_name
    tools = module.waf_tools.web_acl_name
  }
  rds_instances = {
    petclinic = module.database.db_identifier
  }
}

# AWS Backup for everything tagged Backup = team-1 (Nexus, SonarQube, Ansible, RDS)
module "backup" {
  source        = "./module/backup"
  name          = local.name
  kms_key_arn   = module.kms.key_arn
  sns_topic_arn = module.monitoring.sns_topic_arn
}
