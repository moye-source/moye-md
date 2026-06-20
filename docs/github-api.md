# GitHub API Maintenance

Maintainers can update repository metadata with GitHub's REST API.

## Token

Create a fine-grained personal access token:

- Resource owner: `moye-source`
- Repository access: all repositories, or only `moye-source/moye-md`
- Repository permissions:
  - `Administration`: read and write

Use a short expiration, such as 7 or 30 days.

## Store the Token

Save the token in 1Password:

```bash
./scripts/store-github-token-in-1password.sh
```

The script stores the token in:

```text
op://Private/GitHub Personal Access Token/token
```

## Update Repository Metadata

Run:

```bash
./scripts/update-github-repo-metadata.sh
```

The script updates:

- repository description
- repository website
- repository topics

No token should be committed to this repository.
