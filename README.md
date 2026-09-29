# Deploy CHAP
**This repository is an example of how CHAP Core infrastructure and code could be deployed to a server running Docker inside a LXC/LXD container.**

This repository uses a GitHub Action to deploy CHAP Core to a server. The process consists of two steps. First, it deletes the instance by rebuilding it. Next, it deploys CHAP Core to an LXC container. This repository assumes you are running DHIS2 on the same server.

To be able to run CHAP Core correctly, it requires you to have access to Google Earth Engine credentials and provide these to CHAP Core. You can read more about DHIS2 and Google Earth Engine [here](https://docs.dhis2.org/en/topics/tutorials/google-earth-engine-sign-up.html)
 
General CHAP documentation could be fond at: [https://dhis2-chap.github.io/chap-core/](https://dhis2-chap.github.io/chap-core/)
Server documentation could be found at: [https://dhis2-chap.github.io/chap-core/server/running-chap-on-server.html](https://dhis2-chap.github.io/chap-core/server/running-chap-on-server.html)

### Central files in this repository:
- [GitHub action](.github/workflows/deploy_nrec.yml)
- [Deployment](./init.sh)

### Database seed

Every deploy rebuilds the server, which deletes both databases. To keep the demo
content, [`seed/chap-stable.sql.gz`](./seed/chap-stable.sql.gz) (a plain `pg_dump`
of the stable instance) is restored into both `stable` and `master` before chap
first starts. Chap's startup migrations then bring it to each checkout's schema.
Anything added on the servers after the dump is lost at the next deploy unless the
seed is refreshed.

To refresh it from the running stable instance:

```bash
ssh ubuntu@<host> "lxc exec chap-core-stable -- docker exec chap-core-postgres-1 \
  sh -c 'pg_dump -U \"\$POSTGRES_USER\" \"\$POSTGRES_DB\"'" | gzip -9n > seed/chap-stable.sql.gz
gunzip -c seed/chap-stable.sql.gz | tail -4    # must end with "dump complete"
```

This repository is public, so the seed must only ever hold demo data.

### Overview of CHAP architecture:

![CHAP_with_routes_without_climate_data_store drawio (2)](./documentation/chap_core_routes.png)
