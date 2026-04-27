# DNS Providers

Used by `cert.cert_mode: "dns"` for ACME DNS-01. The installer writes these
values from repeated `--cert-dns-env KEY=VALUE` arguments into `cert.dns_env`.

```yaml
cert:
  cert_mode: "dns"
  dns_provider: "cloudflare"
  dns_env:
    CF_API_TOKEN: "xxx"
```

| provider | aliases | env |
|---|---|---|
| cloudflare | cf | `CLOUDFLARE_DNS_API_TOKEN`, `CF_API_TOKEN`, `CLOUDFLARE_API_TOKEN` |
| alidns | aliyun | `ALICLOUD_ACCESS_KEY_ID`, `ALICLOUD_ACCESS_KEY_SECRET` (also accepts `ALI_ACCESS_KEY_*`, `ALIYUN_ACCESS_KEY_*`) |
| tencentcloud | tencent | `TENCENTCLOUD_SECRET_ID`, `TENCENTCLOUD_SECRET_KEY` |
| route53 | aws | AWS credential chain (env / IAM role / profile) |
| godaddy | | `GODADDY_API_KEY`, `GODADDY_API_SECRET` |
| namecheap | | `NAMECHEAP_API_KEY`, `NAMECHEAP_API_USER` |
| namesilo | | `NAMESILO_API_TOKEN` |
| digitalocean | do | `DO_AUTH_TOKEN` |
| linode | | `LINODE_TOKEN` |
| hetzner | | `HETZNER_API_TOKEN` |
| gandi | | `GANDI_BEARER_TOKEN` |
| porkbun | | `PORKBUN_API_KEY`, `PORKBUN_API_SECRET_KEY` |
| netlify | | `NETLIFY_PERSONAL_ACCESS_TOKEN` |
| azure | | `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP_NAME` |
| googleclouddns | gcp, gcloud | `GCE_PROJECT` |
| huaweicloud | huawei | `HUAWEICLOUD_ACCESS_KEY_ID`, `HUAWEICLOUD_SECRET_ACCESS_KEY` |
| bunny | | `BUNNY_ACCESS_KEY` |
| duckdns | | `DUCKDNS_TOKEN` |
| ovh | | `OVH_APPLICATION_KEY`, `OVH_APPLICATION_SECRET`, `OVH_CONSUMER_KEY` |
| vultr | | `VULTR_API_TOKEN` |
| desec | | `DESEC_TOKEN` |
