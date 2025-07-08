# Course Calendar App: Terraform + AWS Elastic Beanstalk Automation

**Project Purpose:**  _A self‑taught DevOps exercise to understand how AWS services (VPC, Subnets, Security Groups, RDS, S3, Elastic Beanstalk) work together, and how to fully automate deployment including schema import hooks using Terraform and Linux shell scripts._

## Project Overview

This project implements a **Course Calendar** web application (PHP + MySQL) and demonstrates how to:

* Define **infrastructure-as-code** using **Terraform**

* Provision a **VPC**, **Subnets**, **Security Groups**, and **RDS**

* Package application code into a **versioned S3** bundle

* Configure **Elastic Beanstalk** for zero‑downtime deployments

* Execute **post‑deploy shell hooks** to import the MySQL schema automatically

_All source and configuration files are included so you can reproduce, study, and adapt for your own learning._

### Architecture Diagram
```text
┌────────────┐     ┌─────────────┐     ┌────────────┐
│            │     │             │     │            │
│   Client   ├────►│  Load      ├────►│  EC2 (PHP)  │
│  Browser   │HTTP │ Balancer   │HTTP │ Instance    │
│            │     │ (ALB/CLB)  │     │ w/ PHP-FPM  │
└────────────┘     └─────────────┘     └────┬───────┘
                                               │
                                               │
                                          JDBC │
                                               ▼
                                 ┌────────────────────────┐
                                 │    RDS MySQL Instance  │
                                 └────────────────────────┘

┌────────┐    ┌───────────┐     ┌─────────┐
│ GitHub ├─►  │ S3 Bucket │◄────┤ Terraform│
└────────┘    │(Versions) │     └─────────┘
             └───────────┘
```

## Prerequisites

* AWS account with privileges to create VPCs, RDS, S3, IAM, EC2, Beanstalk

* Terraform CLI

* AWS CLI configured (aws configure)

* Git and GitHub account (for source control)

### Repository Structure
```text
calendar-infra/              ← root folder
├── app/                     ← PHP source & SQL schema
│   ├── appointments.sql     ← DB schema + seed data
│   ├── calendar.php, ...    ← PHP, JS, CSS files
│   └── .platform/hooks/     ← EB post‑deploy hook for SQL import
├── main.tf                  ← Terraform configuration
├── .gitignore               ← ignores TF state, .terraform, logs
└── README.md                ← this documentation
```

### Terraform Automation

All AWS resources are defined in `main.tf`.  You can `terraform plan` and `terraform apply` to build the entire stack.


### Networking: VPC, Subnets, Security Groups

* EC2 SG allows SSH (22) and HTTP (80)

* LB SG allows HTTP (80) from the Internet

* RDS SG allows MySQL (3306) only from the EC2 SG


### S3 Bucket & App Versioning

* Create a versioned, private S3 bucket

* Pack the app/ folder into a zip with Terraform archive_file

* Upload as an S3 object


### IAM Roles & Instance Profile

* **Service Role** for Beanstalk (AWSElasticBeanstalkServiceRolePolicy)

* **EC2 Role** with AWSElasticBeanstalkWebTier

* **Instance Profile** to allow EC2 to interact with AWS on your behalf

### Application Hooks (SQL Import)
Under `app/.platform/hooks/postdeploy/01-import-sql.sh`:

```sh
#!/usr/bin/env bash
# Install MySQL client on Amazon Linux 2023
sudo dnf install -y mariadb105
# Import schema (ignoring errors if already exists)
mysql -h "$RDS_HOSTNAME" -P "$RDS_PORT" -u "$RDS_USERNAME" -p"$RDS_PASSWORD" \
      "$RDS_DB_NAME" < /var/app/current/app/appointments.sql || true
```

* Execution confirmed in EB logs:

    `[INFO] Running script: .platform/hooks/postdeploy/01-import-sql.sh`


### 🚀 Usage
1. Open the EB endpoint in your browser.

2. Add or edit calendar appointments via the UI.

3. Verify data persistence by running:

```sh
mysql -h <RDS_HOST> -u admin -p app_db \
  -e "SELECT COUNT(*) FROM appointments;"
```
4. Check EB logs for hook execution details under `/var/log/eb-hooks.log`.


### 🐛 Problems Encountered & Solutions
1. **Default VPC Deployment**

    * **Issue:** EB defaulted to AWS’s “default” VPC and ignored custom SGs.

    * **Fix:** Added EC2 & ELB subnet settings under `aws:ec2:vpc`:
    ```hcl
    VPCId,
    Subnets,
    ELBSubnets,
    AssociatePublicIpAddress = true
    ```

2. **“SecurityGroup does not exist”**

    * **Issue:** EB service role couldn’t see custom SG as it was deploying on the default VPC.

    * **Fix:**

      * Provided the correct custom `vpc` and `subnets`.

      * Ensured EB’s service role `(AWSElasticBeanstalkServiceRolePolicy)` had `ec2:DescribeSecurityGroups`.

3. **Incorrect `subnet_ids` Type**

    * **Issue:** Passing a comma‑separated string instead of a list.

    * **Fix:** Used Terraform list syntax:
    ```sh
    subnet_ids = [ids[0], ids[1]]
    ```

4. **Hook Script Not Found / Not Executed**

    * Issue: `.platform/hooks/postdeploy` path or permissions error.

    * Fix:

      * Placed `01-import-sql.sh` under `app/.platform/hooks/postdeploy/`.

      * Marked executable `(chmod +x)`.

      * Verified in EB logs.

5. **MySQL Client Missing in Hook**

    * **Issue:**` mysql`: command not found on `Amazon Linux 2023`.

    * **Fix:** Installed `mariadb105` in hook before import.


### ✨Next Steps & Best Practices

* **CI/CD Integration:** GitHub Actions to terraform apply on merge to main and EB deploy.

* **Secrets Management:** Move DB credentials to AWS Secrets Manager.

* **Monitoring & Alerts:** Configure CloudWatch alarms for high 5xx rates, CPU/memory.

* **Cost Control:** Use smaller instance types or scale down in non‑production.


### 📄License

This project is released under the MIT License. Feel free to fork, learn, and adapt!


