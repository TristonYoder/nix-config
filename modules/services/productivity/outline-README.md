# Outline Module

This module provides a comprehensive NixOS configuration for [Outline](https://www.getoutline.com/), a fast and collaborative wiki for your team.

## Overview

The Outline module handles:
- Environment variable generation and secret management
- Multiple authentication methods (Slack, Google, Microsoft, Discord, OIDC)
- File storage configuration (local and S3)
- Email/SMTP settings
- Rate limiting
- Reverse proxy integration with Caddy
- Security and SSL/TLS configuration

## Module Structure

```nix
modules.services.productivity.outline = {
  enable = true;
  # ... configuration options
};
```

## Core Configuration

### Basic Setup

```nix
modules.services.productivity.outline = {
  enable = true;
  domain = "outline.example.com";
  publicUrl = "https://outline.example.com";
  port = 3000;
  
  # Database (required)
  databaseUrl = "postgres://user:password@localhost:5432/outline";
  
  # Redis (required)
  redisUrl = "redis://localhost:6379";
  
  # Secrets - path to files containing sensitive data
  secretKeyFile = /run/agenix/outline-secrets/secret-key;
  utilsSecretFile = /run/agenix/outline-secrets/utils-secret;
};
```

## Secrets Management

All sensitive values should be provided via file paths to encrypted secrets using [agenix](../README.md):

### Required Secrets
- `secretKeyFile`: Session secret key (minimum 32 characters)
- `utilsSecretFile`: Encryption secret for end-to-end encryption

### Authentication Secrets
When using any authentication method, provide secrets as file paths:

```nix
modules.services.productivity.outline = {
  enable = true;
  
  slackAuthentication = {
    enable = true;
    clientId = "xoxb-...";
    secretFile = /run/agenix/outline-secrets/slack-secret;
  };
  
  googleAuthentication = {
    enable = true;
    clientId = "...googleapis.com";
    clientSecretFile = /run/agenix/outline-secrets/google-secret;
  };
};
```

### Encrypted Secret Files

Secrets are stored in `/secrets/` as encrypted age files:
- `outline-secrets.age` - Main application secrets (keys, OIDC secrets, etc.)

Decrypt and re-encrypt with:
```bash
./secrets/decrypt-secret.sh outline-secrets
# Edit the file
./secrets/encrypt-secret.sh outline-secrets.age
```

## Email Configuration

Configure SMTP for notifications and user management:

```nix
modules.services.productivity.outline = {
  enable = true;
  
  smtp = {
    host = "mail.example.com";
    port = 587;
    secure = true;
    username = "outline@example.com";
    passwordFile = /run/agenix/outline-secrets/smtp-password;
    fromEmail = "noreply@example.com";
    replyEmail = "support@example.com";
  };
};
```

## File Storage

### Local Storage (Default)

```nix
modules.services.productivity.outline = {
  enable = true;
  
  storage = {
    storageType = "local";
    localRootDir = "/var/lib/outline/data";
    uploadMaxSize = 26214400; # 25MB
  };
};
```

### S3 Storage

```nix
modules.services.productivity.outline = {
  enable = true;
  
  storage = {
    storageType = "s3";
    uploadMaxSize = 26214400;
    accessKey = "AKIA...";
    secretKeyFile = /run/agenix/outline-secrets/s3-secret;
    uploadBucketName = "outline-uploads";
    uploadBucketUrl = "https://s3.amazonaws.com/outline-uploads";
    region = "us-east-1";
    forcePathStyle = false;
    acl = "private";
  };
};
```

## Authentication Methods

### Slack Authentication

```nix
modules.services.productivity.outline = {
  slackAuthentication = {
    enable = true;
    clientId = "xoxb-...";
    clientSecretFile = /run/agenix/outline-secrets/slack-client-secret;
  };
};
```

### Slack Integration

Enable Slack workspace integration for notifications:

```nix
modules.services.productivity.outline = {
  slackIntegration = {
    enable = true;
    appId = "A...";
    messageActions = true;
    verificationTokenFile = /run/agenix/outline-secrets/slack-verification-token;
  };
};
```

### Google OAuth

```nix
modules.services.productivity.outline = {
  googleAuthentication = {
    enable = true;
    clientId = "...googleapis.com";
    clientSecretFile = /run/agenix/outline-secrets/google-client-secret;
  };
};
```

### Microsoft Azure AD

```nix
modules.services.productivity.outline = {
  microsoftAuthentication = {
    enable = true;
    clientId = "...";
    clientSecretFile = /run/agenix/outline-secrets/azure-client-secret;
    resourceAppId = "..."; # Optional
  };
};
```

### Discord

```nix
modules.services.productivity.outline = {
  discordAuthentication = {
    enable = true;
    clientId = "...";
    clientSecretFile = /run/agenix/outline-secrets/discord-client-secret;
    serverId = ""; # Optional: require user to be in this server
    serverRoles = ""; # Optional: comma-separated role IDs
  };
};
```

### OIDC (Generic OpenID Connect)

```nix
modules.services.productivity.outline = {
  oidcAuthentication = {
    enable = true;
    displayName = "My Identity Provider";
    clientId = "...";
    clientSecretFile = /run/agenix/outline-secrets/oidc-client-secret;
    authUrl = "https://idp.example.com/oauth/authorize";
    tokenUrl = "https://idp.example.com/oauth/token";
    userinfoUrl = "https://idp.example.com/oauth/userinfo";
    scopes = "openid profile email";
    usernameClaim = "preferred_username";
  };
};
```

## Rate Limiting

Enable rate limiting to prevent abuse:

```nix
modules.services.productivity.outline = {
  enable = true;
  
  rateLimiter = {
    enable = true;
    requests = 1000;       # Requests per window
    durationWindow = 60;   # Window in seconds
  };
};
```

## Analytics and Monitoring

### Google Analytics

```nix
modules.services.productivity.outline = {
  googleAnalyticsId = "UA-...";
};
```

### Sentry Error Tracking

```nix
modules.services.productivity.outline = {
  sentryDsn = "https://...@sentry.io/...";
  sentryTunnel = "https://sentry-tunnel.example.com";
};
```

## Server Configuration

### Performance

```nix
modules.services.productivity.outline = {
  enable = true;
  concurrency = 4;  # Number of worker processes
};
```

### HTTPS and Security

```nix
modules.services.productivity.outline = {
  enable = true;
  forceHttps = true;
  sslCertFile = "/path/to/cert.pem";
  sslKeyFile = "/path/to/key.pem";
};
```

Note: When using Caddy reverse proxy, SSL/TLS is typically handled by Caddy, not Outline.

### Branding

```nix
modules.services.productivity.outline = {
  enable = true;
  logo = "https://example.com/logo.png";
  cdnUrl = "https://cdn.example.com";
  defaultLanguage = "en_US";
};
```

## Complete Example

```nix
# In hosts/myhost/configuration.nix
modules.services.productivity.outline = {
  enable = true;
  domain = "outline.theyoder.family";
  publicUrl = "https://outline.theyoder.family";
  port = 3000;
  
  # Database and Cache
  databaseUrl = "postgres://outline:password@localhost:5432/outline";
  redisUrl = "redis://localhost:6379";
  
  # Secrets
  secretKeyFile = config.age.secrets.outline-secret-key.path;
  utilsSecretFile = config.age.secrets.outline-utils-secret.path;
  
  # Email
  smtp = {
    host = "mail.theyoder.family";
    port = 587;
    secure = true;
    username = "outline@theyoder.family";
    passwordFile = config.age.secrets.outline-smtp-password.path;
    fromEmail = "noreply@theyoder.family";
    replyEmail = "support@theyoder.family";
  };
  
  # File Storage
  storage = {
    storageType = "local";
    localRootDir = "/data/outline/uploads";
    uploadMaxSize = 26214400; # 25MB
  };
  
  # Authentication
  googleAuthentication = {
    enable = true;
    clientId = "...googleapis.com";
    clientSecretFile = config.age.secrets.outline-google-secret.path;
  };
  
  oidcAuthentication = {
    enable = true;
    displayName = "Internal IDP";
    clientId = "outline";
    clientSecretFile = config.age.secrets.outline-oidc-secret.path;
    authUrl = "https://idp.internal/oauth/authorize";
    tokenUrl = "https://idp.internal/oauth/token";
    userinfoUrl = "https://idp.internal/oauth/userinfo";
  };
  
  # Rate Limiting
  rateLimiter = {
    enable = true;
    requests = 1000;
    durationWindow = 60;
  };
  
  # Features
  enableUpdateCheck = true;
  maximumImportSize = 5242880; # 5MB
  
  # Monitoring
  googleAnalyticsId = "UA-...";
};
```

## Dependencies

The module expects:
- **PostgreSQL**: For document and user data storage
- **Redis**: For caching and sessions
- **Caddy**: For reverse proxy (when enabled)
- **agenix**: For secret management

## Related Files

- [Secrets configuration](../secrets/secrets.nix)
- [Caddy infrastructure module](./infrastructure/caddy.nix)
- [Docker compose example](../../docker/dockercompose/outline/)
- [Module README](README.md)

## References

- [Outline Environment Variables](https://docs.getoutline.com/s/hosting/doc/environment-variables-1pWWvrtdUe)
- [Outline Installation Guide](https://docs.getoutline.com/s/hosting)
