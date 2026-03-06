# 🔗 URL Shortener — Serverless on AWS

A simple, zero-cost URL shortener built with **Python**, **AWS Lambda**, **API Gateway**, **DynamoDB**, and deployed via **Terraform**.

```
User → API Gateway → Lambda (Python) → DynamoDB
```

---

## 📁 Project Structure

```
url-shortener/
├── app/
│   └── lambda_function.py     ← Python Lambda code
├── terraform/
│   ├── main.tf                ← AWS infrastructure
│   ├── variables.tf           ← configurable inputs
│   └── outputs.tf             ← printed endpoints
├── .gitignore
└── README.md
```

---

## 💰 Cost: $0 (Free Tier)

| Service       | Free Tier                                |
| ------------- | ---------------------------------------- |
| AWS Lambda    | 1M requests/month free                   |
| API Gateway   | 1M requests/month free (first 12 months) |
| DynamoDB      | 25 GB + 200M requests/month free         |
| GitHub        | Free for public/private repos            |

---

## 🚀 Quick Start

### Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured (`aws configure`)
- [Terraform](https://www.terraform.io/downloads) ≥ 1.0
- [Git](https://git-scm.com/)

### 1️⃣ Clone & Navigate

```bash
git clone https://github.com/<your-username>/url-shortener.git
cd url-shortener
```

### 2️⃣ Deploy with Terraform

```bash
cd terraform
terraform init
terraform plan        # preview what will be created
terraform apply       # type "yes" to confirm
```

After `apply` completes, Terraform prints your live API URL:

```
Outputs:

api_base_url      = "https://xxxxxxxxxx.execute-api.ap-south-1.amazonaws.com/prod"
shorten_endpoint  = "https://xxxxxxxxxx.execute-api.ap-south-1.amazonaws.com/prod/shorten"
```

### 3️⃣ Test It!

**Shorten a URL:**

```bash
curl -X POST https://<your-api-url>/prod/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://www.google.com/search?q=aws+lambda+tutorial"}'
```

Response:

```json
{
  "short_code": "aB3xZ9",
  "short_url": "https://<your-api-url>/prod/aB3xZ9",
  "long_url": "https://www.google.com/search?q=aws+lambda+tutorial"
}
```

**Redirect (open in browser or curl):**

```bash
curl -L https://<your-api-url>/prod/aB3xZ9
```

**Check Stats:**

```bash
curl https://<your-api-url>/prod/stats/aB3xZ9
```

Response:

```json
{
  "short_code": "aB3xZ9",
  "long_url": "https://www.google.com/search?q=aws+lambda+tutorial",
  "hits": 3,
  "created_at": 1709723456
}
```

---

## 🔄 Update Workflow

1. Edit `app/lambda_function.py`
2. Push changes to GitHub
3. Re-deploy:

```bash
cd terraform
terraform apply
```

The `source_code_hash` in `main.tf` detects file changes automatically — Terraform will update the Lambda for you.

---

## 🧹 Tear Down (Important!)

When done practicing, destroy everything to avoid any future charges:

```bash
cd terraform
terraform destroy     # type "yes" to confirm
```

---

## ⚠️ Golden Rules

| Rule | Why |
| --- | --- |
| `terraform destroy` when done | Avoid unexpected charges |
| Never commit `*.tfstate` | Contains sensitive infrastructure details |
| Never commit AWS credentials | Security risk |
| Stick to `ap-south-1` | Your configured region |

---

## 🗺️ API Reference

| Method | Path           | Description                        |
| ------ | -------------- | ---------------------------------- |
| POST   | `/shorten`     | Create a short URL                 |
| GET    | `/{code}`      | Redirect to original URL (301)     |
| GET    | `/stats/{code}`| Get hit count & metadata           |

### POST /shorten

**Request Body:**

```json
{ "url": "https://example.com/long/path" }
```

**Response (201):**

```json
{
  "short_code": "aB3xZ9",
  "short_url": "https://<api>/prod/aB3xZ9",
  "long_url": "https://example.com/long/path"
}
```

### GET /{code}

**Response (301):** Redirects to the original URL.

### GET /stats/{code}

**Response (200):**

```json
{
  "short_code": "aB3xZ9",
  "long_url": "https://example.com/long/path",
  "hits": 42,
  "created_at": 1709723456
}
```

---

## 📝 License

MIT — do whatever you want with it. 🎉
