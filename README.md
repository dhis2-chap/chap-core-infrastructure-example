# Deploy CHAP
**This repository is an example of how CHAP Core infrastructure and code could be deployed to a server running Docker inside a LXC/LXD container.**

To be able to run CHAP Core correctly, it requires you to have access to Google Earth Engine credentials and provide these to CHAP Core. You can read more about DHIS2 and Google Earth Engine [here](https://docs.dhis2.org/en/topics/tutorials/google-earth-engine-sign-up.html) If you do not have access to these credentials, you can start CHAP Core, but it will not be able to give you any predictions or evaluations.
 
General CHAP documentation could be fond at: [https://dhis2-chap.github.io/chap-core/](https://dhis2-chap.github.io/chap-core/)

### Central files in this repository:
- [GitHub action](.github/workflows/deploy_nrec.yml)
- [Deployment](./init.sh)

### Overview of CHAP architecture:

![CHAP_with_routes_without_climate_data_store drawio (2)](./documentation/chap_core_routes.png)


## Verify installation:

You need to verify that CHAP Core is accessible from outside the CHAP Core container. On your server operating system (not within you LXC container) execute:

```sh
  curl http://localhost:8000/list-models
```

This should print similar content as:

![image](https://github.com/user-attachments/assets/62a602fa-0fe9-411f-9700-879ae83e6436)
