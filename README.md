# Notes API (FastAPI + Docker + Terraform on GCP)

A small note‑taking REST API you can run locally with Docker Compose and deploy to Google Cloud with Terraform. CI/CD is handled by GitHub Actions (deploy + destroy workflows).

---
## Architecture


![Architecture diagram](./KLM-homework.drawio.png)

---
## TL;DR

* **Language/Framework:** Python / FastAPI
* **Container:** Docker
* **Local run:** `docker-compose up --build` (from repo root)
* **Cloud:** GCP (Cloud Run, Cloud SQL Postgres, API Gateway, Secret Manager, Artifact Registry)
* **IaC:** Terraform (remote state in GCS)
* **CI/CD:** GitHub Actions (manual trigger or on push to `main`)

---

### Notes API (FastAPI + Docker + Terraform on GCP)

A small note‑taking REST API you can run locally with Docker Compose and deploy to Google Cloud with Terraform. CI/CD is handled by GitHub Actions (deploy + destroy workflows).

## TL;DR

- **Language/Framework:** Python / FastAPI  
- **Container:** Docker  
- **Local run:** docker-compose up --build  
- **Cloud:** GCP (Cloud Run, Cloud SQL, API Gateway, Secret Manager, Artifact Registry)  
- **IaC:** Terraform (remote state in GCS)  
- **CI/CD:** GitHub Actions (deploy + destroy workflows)

## Project structure

```text
klm-homework/
├─ .github/
│ └─ workflows/
├─ app/
│ ├─ crud.py
│ ├─ database.py
│ ├─ main.py
│ └─ models.py
├─ infra/
├─ .gitignore
├─ build_push.sh
├─ docker-compose.yml
├─ Dockerfile
├─ README.md
└─ requirements.txt
```
### What's what

* **app/** – FastAPI app (endpoints, models, DB access)
* **infra/** – Terraform code for GCP infra (backend, providers, Cloud Run, Cloud SQL, API GW, IAM)
* **.github/workflows/** – CI/CD (deploy & destroy)
* **docker-compose.yml** – Local API + DB
* **Dockerfile** – App image definition
* **build_push.sh** – Local helper for building/pushing image
* **requirements.txt** – Python dependencies

---

### Components

* **API Gateway** – single public entry point
* **Cloud Run** – runs the containerized FastAPI app
* **Cloud SQL (Postgres)** – relational DB for notes
* **Secret Manager** – stores DB password securely
* **Artifact Registry** – stores Docker images
* **Terraform (with GCS backend)** – manages state and infra
* **GitHub Actions** – CI/CD workflows (deploy + destroy)

---

## API (FastAPI)

**Why FastAPI?** It’s fast, simple, type‑friendly, and ships with great docs via Swagger.

**Endpoints**

* `POST /notes` – Create a new note
* `GET /notes` – Retrieve all notes
* `GET /notes/{id}` – Retrieve a specific note by ID
* `PUT /notes/{id}` – Update an existing note
* `DELETE /notes/{id}` – Delete a note

---

## Why Cloud Run?

**Considered:**

* **VMs:** too much ops overhead for a tiny API
* **App Engine:** more constraints, less flexible these days
* **Cloud Run:** fully managed, cheap at low traffic, quick deploys, auto‑scaling

**Choice:** Cloud Run is the best fit for this lightweight service.

---

## Database (Cloud SQL Postgres)

* Planned Serverless VPC Connector initially for private networking.
* The connector refused to stabilize cleanly during deployment.
* **Switched to the Cloud SQL Auth Proxy path used by Cloud Run:**

  * Cloud Run annotated with `run.googleapis.com/cloudsql-instances`.
  * DB password stored in Secret Manager.
  * **IAM grants:** `roles/cloudsql.client`, `roles/secretmanager.secretAccessor`, `roles/run.invoker`.
* This still provides a secure, working setup without Private IP.

---

## Local Development

1. **Build locally** (from repo root)

```bash
cd klm-homework
docker build -t notes-api:local .
```

2. **Run API + DB with Docker Compose** (from repo root)

```bash
cd klm-homework
docker-compose up --build
```

App will be available at: [http://localhost:8000](http://localhost:8000)

3. **Run only the API container**
   (Useful if pointing the app at Cloud SQL instead of local Postgres.)

```bash
cd klm-homework
docker run -p 8000:8000 notes-api:local
```

---

## Calling the API (examples)

Assumes local server at `http://localhost:8000`.

**Create**

```bash
curl -X POST http://localhost:8000/notes \
  -H "Content-Type: application/json" \
  -d '{"title":"First Note","content":"This is my first note"}'
```

**List**

```bash
curl http://localhost:8000/notes
```

**Get by ID**

```bash
curl http://localhost:8000/notes/1
```

**Update**

```bash
curl -X PUT http://localhost:8000/notes/1 \
  -H "Content-Type: application/json" \
  -d '{"title":"Updated","content":"This is updated content"}'
```

**Delete**

```bash
curl -X DELETE http://localhost:8000/notes/1
```

**Swagger UI**

[http://localhost:8000/docs](http://localhost:8000/docs)

---

## Terraform

* Remote backend: **Google Cloud Storage (GCS)**
* Bucket name: `${PROJECT_ID}-tfstate` (created by the deploy workflow if missing)
* Prefix: `notes-api`

**Example `infra/backend.tf`:**

```hcl
terraform {
  backend "gcs" {
    bucket = "homework-klm-tfstate"
    prefix = "notes-api"
  }
}
```

> Adjust the bucket to your project. Keep prefix stable.

**Variables (provided via CI secrets)**

* `TF_VAR_project_id`
* `TF_VAR_region`
* `TF_VAR_db_password`

---

## CI/CD (GitHub Actions)

Two workflows live under `.github/workflows/`:

### 1) Deploy workflow

**What it does (at a high level):**

* Authenticates to GCP and configures Docker for Artifact Registry
* Ensures the GCS bucket for Terraform remote state exists
* Runs Terraform format/validate/plan
* Applies foundational infra (Artifact Registry, service account, Secret Manager)
* Lints & tests Python (black, flake8, pytest)
* Builds & pushes Docker image to Artifact Registry
* Applies full infra (Cloud Run, Cloud SQL, API Gateway)
* Smoke test against API Gateway (`GET /notes` should return 200)

**How to run it:**

* **Manual:** GitHub → Actions → *Deploy Notes API* → **Run workflow**

### 2) Destroy workflow

**What it does:**

* Authenticates to GCP
* Terminates DB sessions so Postgres objects can be dropped cleanly
* Runs `terraform destroy` to remove all resources
* Best‑effort state lock cleanup in GCS (if a stale `.tflock` exists)

**How to run it (manual only):**

* GitHub → Actions → *Destroy Notes API* → **Run workflow**

---

## Required GitHub Secrets

Set these repository secrets:

* `GCP_SA_KEY` – Service account key JSON with:

  * `roles/run.admin`
  * `roles/iam.serviceAccountUser`
  * `roles/storage.admin`
  * `roles/artifactregistry.admin`
  * `roles/secretmanager.admin`
  * `roles/cloudsql.admin`
* `TF_VAR_db_password` – Postgres DB password

`TF_VAR_project_id` and `TF_VAR_region` can come from workflow env or be stored as secrets as well.

---

## Production Notes

Right now the deploy workflow runs all steps in sequence. In a real setup, you would likely:

* Split into multiple workflows (infra, build, deploy, tests)
* Gate each step with manual approvals (e.g., environment protection rules)
* Keep destroy behind a manual trigger with restricted permissions

