# Deploy CHAP
This repository is an example of how CHAP Core infrastructure and code could be deployed to a server using Docker inside LXC/LXD.

General CHAP documentation: [https://dhis2-chap.github.io/chap-core/](https://dhis2-chap.github.io/chap-core/)

### Central files in this repository:
- [GitHub action](.github/workflows/deploy_nrec.yml)
- [Deployment](./init.sh)

### Overview of CHAP architecture:

![CHAP_with_routes_without_climate_data_store drawio (2)](./documentation/chap_core_routes.png)


## Verify installation:

On your server, use your terminal and execute:

```sh
  curl http://localhost:8000/list-models
```

This should print similar content as:

![image](https://github.com/user-attachments/assets/62a602fa-0fe9-411f-9700-879ae83e6436)