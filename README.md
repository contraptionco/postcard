<div align="center">
  <a href="https://postcard.page">
    <img src="app/assets/images/logo/wordmark-accent.svg" alt="Postcard" width="200">
  </a>
  <br /><br />
</div>

**[Postcard](https://postcard.page)** replaces social media with a personal website, integrated newsletter, and light blogging functionality. Write once on your Postcard, then share everywhere - your posts automatically include sophisticated meta tags and OpenGraph images that look professional when shared on social platforms. Host it on your custom domain and build a long-term mailing list while creating your own personal corner of the internet.

By default, this repo runs in a simple solo mode intended for self-hosting. [Fork it](https://github.com/contraptionco/postcard/fork) and vibe code to your heart's content. Run it on your own server with Docker and a Postgres database.

This is the open source repository powering [postcard.page](https://postcard.page), which runs in multiuser mode. If you want to try Postcard for free, or pay to have  it hosted on your domain, [try it out](https://postcard.page).

*Postcard is a project of [Contraption Company](https://contraption.co) and is released under the [GPL open source license](./LICENSE).*

## Running Postcard in solo mode (recommended)

**Solo mode is recommended for open source users** - it's intended for running one website without complicated multi-domain setup or paywalls.

### Requirements

Postcard requires the following dependencies to be installed on your system:

- **Ruby** (3.1) and **Rails** (7)
- **PostgreSQL**
- **Vips** (image processing library)
- **Node.js** and **npm** (for open graph image generation with Puppeteer)

### Development quick start

After installing dependencies:
1. Install Ruby gems: `bundle install`
2. Install JavaScript dependencies: `npm install puppeteer`
3. Set up the database: `rails db:setup`
4. Start the Rails server: `./bin/dev-solo`
5. Access the application: [localtest.me:3000](http://localtest.me:3000)

- (We cannot use straight localhost because of [hCaptcha constraints](https://docs.hcaptcha.com/#local-development))

### Environment variables

For basic solo mode development, Postcard works out of the box with minimal configuration. You can optionally create a `.env` file for any customizations.

For a complete reference of all available configuration options, see `config/initializers/app_config.rb`.

For production, you'll need to set up [AWS](https://aws.amazon.com/) for email sending (*directions below*), and [hCaptcha](https://www.hcaptcha.com/) for spam prevention (free!).

Here's a list of all available environment variables for solo mode:

| Variable                 | Default                                     | Description                                                |
|--------------------------|---------------------------------------------|---------------------------------------------------------------|
| BASE_HOST                | localtest.me (dev) / postcard.page (prod)   | The domain for your Postcard installation. In multiuser mode, subdomains become public account pages. |
| SECRET_KEY_BASE          | null                                        | Used by Rails for session cookies and other cryptographic operations. Should be a long, random string kept secret. |
| DEFAULT_EMAIL_FROM       | hello@postcard.page                         | Default from email address for all outgoing emails. This is the address that appears as the sender in recipients' inboxes. |
| DEFAULT_EMAIL_FROM_NAME  | Postcard                                    | Default from name that appears alongside the from email address. This is the display name recipients see as the sender. |
| AWS_ACCESS_KEY_ID        | null                                        | AWS credential for accessing S3 storage. Required in production for storing user uploads like profile photos and attachments. |
| AWS_SECRET_ACCESS_KEY    | null                                        | AWS credential paired with the access key ID. Both are required to authenticate with AWS services. |
| AWS_REGION               | us-east-1                                   | AWS region where your S3 bucket is located. Different regions may offer better performance depending on your users' locations. |
| AWS_STORAGE_BUCKET       | null                                        | Name of the S3 bucket where files will be stored. This bucket must exist and be configured with proper permissions. |
| HCAPTCHA_SITE_KEY        | null                                        | Public key for hCaptcha bot protection. Used on forms to prevent spam and abuse. |
| HCAPTCHA_SECRET_KEY      | null                                        | Private key for hCaptcha verification. Used server-side to validate captcha responses. |
| GOOGLE_OAUTH_CLIENT_ID   | null                                        | Google OAuth credentials for enabling "Sign in with Google" functionality. Required if you want to allow Google login. |
| GOOGLE_OAUTH_CLIENT_SECRET| null                                        | Secret key paired with the Google OAuth client ID. Both are required for Google authentication to work. |
| DISABLE_ANONYMOUS_TELEMETRY | false                                     | Set to true to opt out of anonymous telemetry. See section below for details. |

### Anonymous Telemetry

Postcard collects anonymous usage statistics to help improve the software. This telemetry:

- **Is completely anonymous** - no personal information is collected
- **Runs once per hour** - minimal resource usage
- **Only collects**:
  - Application mode (solo/multiuser)
  - Rails environment
  - Ruby and Rails versions
  - Aggregate counts (number of accounts, posts, subscribers)
- **Can be disabled** - set `DISABLE_ANONYMOUS_TELEMETRY=true` in your environment

I use this data to understand how Postcard is being used and to prioritize improvements. The telemetry data is sent to a self-hosted Plausible Analytics instance and is never shared with third parties.

### Email Development

In development, emails are opened automatically in your browser using Letter Opener. You can also view all sent emails at [localtest.me:3000/letter_opener](http://localtest.me:3000/letter_opener) when logged in as an admin.

## AWS Setup

Postcard requires AWS for both file storage (S3) and email delivery (SES) in production. Here's how to set up both services:

### 1. Create AWS Account and IAM User

1. Sign up for an AWS account at [aws.amazon.com](https://aws.amazon.com)
2. Navigate to IAM (Identity and Access Management)
3. Create a new user for Postcard with programmatic access
4. Save the Access Key ID and Secret Access Key (you'll need these for environment variables)

### 2. Set Up S3 for File Storage

1. **Create an S3 Bucket:**
   - Go to S3 in the AWS Console
   - Click "Create bucket"
   - Choose a unique bucket name (e.g., `your-app-postcard-storage`)
   - Select your preferred region (e.g., `us-east-1`)
   - Keep default settings for now

2. **Configure Bucket Permissions:**
   - Go to your bucket's Permissions tab
   - Update the bucket policy to allow your application access:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "AWS": "arn:aws:iam::YOUR-ACCOUNT-ID:user/YOUR-IAM-USER"
         },
         "Action": [
           "s3:GetObject",
           "s3:PutObject",
           "s3:DeleteObject"
         ],
         "Resource": "arn:aws:s3:::your-bucket-name/*"
       },
       {
         "Effect": "Allow",
         "Principal": {
           "AWS": "arn:aws:iam::YOUR-ACCOUNT-ID:user/YOUR-IAM-USER"
         },
         "Action": "s3:ListBucket",
         "Resource": "arn:aws:s3:::your-bucket-name"
       }
     ]
   }
   ```

3. **Configure CORS (for direct uploads):**
   - In your bucket's Permissions tab, scroll to CORS configuration
   - Add this configuration:
   ```json
   [
     {
       "AllowedHeaders": ["*"],
       "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
       "AllowedOrigins": ["*"],
       "ExposeHeaders": ["ETag"]
     }
   ]
   ```

### 3. Set Up SES for Email Delivery

1. **Navigate to SES:**
   - Go to Simple Email Service (SES) in the AWS Console
   - Make sure you're in the same region as your S3 bucket

2. **Verify Your Domain:**
   - Click "Domains" in the left sidebar
   - Click "Verify a New Domain"
   - Enter your domain (e.g., `yourdomain.com`)
   - Follow the DNS verification steps provided by AWS
   - This allows you to send emails from any address at your domain

3. **Request Production Access:**
   - By default, SES starts in "sandbox mode" (can only send to verified addresses)
   - Go to "Sending Statistics" and click "Request a Sending Limit Increase"
   - Fill out the form explaining your use case
   - AWS typically approves legitimate applications within 24-48 hours

4. **Configure IAM Permissions:**
   - Add SES permissions to your IAM user
   - Attach this policy to your IAM user:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "ses:SendEmail",
           "ses:SendRawEmail"
         ],
         "Resource": "*"
       }
     ]
   }
   ```

### 4. Environment Variables

Add these to your `.env` file:

```bash
# AWS Configuration
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
AWS_REGION=us-east-1
AWS_STORAGE_BUCKET=your-bucket-name

# Email Configuration
DEFAULT_EMAIL_REPLY_TO=your-verified-email@yourdomain.com
```

## Production hosting

Postcard includes a Dockerfile for easy deployment.

It also includes a `render.yaml` for managed hosting on [Render](https://render.com). To host there, just connect this repo to your account and use the "Blueprint" functionality, paste in the AWS and hCaptcha keys, and the entire app will run with no further configuration.

## Multi-User Mode

This is the exact same repository that powers [postcard.page](https://postcard.page), which hosts multiple user accounts and personal websites. The hosted service at postcard.page runs in multi-user mode, allowing multiple users to create accounts and build their own personal websites.

To run Postcard in multi-user mode:

1. Set `APP_MODE=MULTIUSER` in your environment variables
2. Review `config/initializers/app_config.rb` for all the additional configuration options required
3. Set up Stripe for payment processing (required for premium features like custom domains)
4. Configure the custom domain logic, which works through a render proxy system located in the `render-proxy/` folder.

**Note:** Running Postcard in multi-user mode is significantly more complex than solo mode and involves setting up payment processing, custom domain routing, and additional infrastructure. You're welcome to try running it in multi-user mode, but be prepared for the additional setup complexity compared to the straightforward solo mode installation.
