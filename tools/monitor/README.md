Monitor de direcciones en texto plano

Este pequeño monitor busca direcciones Ethereum en texto plano (hex de 40 bytes, prefijo 0x) dentro de los archivos modificados en un PR o en todo el repo cuando no hay `base_ref`.

Uso (local):

```bash
git fetch origin main
GITHUB_BASE_REF=main bash tools/monitor/check_plain_addresses.sh
```

En CI: el job `address_scan` en `.github/workflows/ci.yml` ejecuta el script con `fetch-depth: 0` para permitir `git blame`.

Opcional: configurar `ALERT_WEBHOOK` en `Secrets` (p.ej. Slack/Discord/Webhook) para recibir notificaciones.
