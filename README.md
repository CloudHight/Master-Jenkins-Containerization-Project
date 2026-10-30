# 1st-June-2026-iscovery-Project-Team-1

## Architecture

```
User ──HTTPS──▶ AWS WAF ──▶ ALB (public subnets) ──▶ EC2 / ASG (private subnets) ──▶ RDS (private)
                                                         │
                                                         └─▶ NAT gateway for outbound updates
```

| Layer | What protects it |
|---|---|
| Edge | AWS WAF on every ALB: IP reputation, common rule set, known bad inputs, SQLi, per-IP rate limit. HTTP → HTTPS redirect, TLS 1.2/1.3 only. |
| App tier | Jenkins, SonarQube, Nexus, Ansible, stage and prod all run in private subnets with no public IP. Security groups only accept traffic from their ALB. |
| Access | IAM role based. Each server has its own least privilege role, and operators connect with SSM Session Manager (no shared SSH keys on the bastion). |
| Secrets | AWS Secrets Manager (Nexus admin, SonarQube DB, Ansible SSH key, RDS master password managed by RDS). No Vault. |
| Data | Customer managed KMS key for EBS, RDS, Secrets Manager, CloudWatch Logs, SNS and AWS Backup. RDS is private, encrypted, keeps 7 days of automated backups and a final snapshot. |
| Backup | AWS Backup daily (35 days) and weekly (90 days) for everything tagged `Backup = <stack name>`. Failed jobs alert to SNS. |
| Observability | CloudWatch agent (memory, disk, system logs), VPC flow logs, WAF logs, RDS logs, alarms (CPU, status checks, memory, disk, ALB 5xx, latency, unhealthy targets, WAF blocks, RDS CPU/storage), SNS alerts and a dashboard per stack. No New Relic. |

## Stacks

- `jenkins-vault/`: Jenkins (private subnet, ALB and WAF). Its role has a scoped deploy policy for the `team-1` stack instead of AdministratorAccess. Apply manually first.
- Repository root: the `team-1` application stack, deployed by the Jenkins pipeline.

## Useful variables

| Variable | Default | Purpose |
|---|---|---|
| `alert_email` | `""` | E-mail subscribed to alerts (confirm the subscription e-mail) |
| `db_deletion_protection` | `true` | Set to `false` before running the destroy pipeline |

## Endpoints

- `https://jenkins.<domain>`, `https://sonarqube.<domain>`, `https://nexus.<domain>`
- Docker registry: `nexus.<domain>:8085` (TLS, password in Secrets Manager: `terraform output nexus_admin_secret_arn`)
- `https://stage.<domain>`, `https://prod.<domain>`
