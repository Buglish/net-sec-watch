# Release checklist

Author: SJ du Preez

## Prepared release

Version file: `VERSION`

Current prepared version: `0.1.0-rc.1`

## Release procedure

1. Confirm clean working tree.
2. Run:

   ```bash
   make check
   make test-deployment
   ```

3. Commit the release candidate.
4. Create an annotated tag:

   ```bash
   git tag -a v0.1.0 -m "Release Net Sec Watch v0.1.0"
   ```

5. Push branch and tag:

   ```bash
   git push origin HEAD
   git push origin v0.1.0
   ```

6. Publish release notes with deployment and rollback instructions.

## Rollback

Use:

```bash
scripts/rollback-release.sh <previous-tag>
```
