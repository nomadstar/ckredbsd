Monitor de direcciones en texto plano

Este pequeño monitor busca direcciones Ethereum en texto plano (hex de 40 bytes, prefijo 0x) dentro de los archivos modificados en un PR o en todo el repo cuando no hay `base_ref`.

Uso (local):

```bash
git fetch origin main
GITHUB_BASE_REF=main bash tools/monitor/check_plain_addresses.sh
```

En CI: el job `address_scan` en `.github/workflows/ci.yml` ejecuta el script con `fetch-depth: 0` para permitir `git blame`.

Opcional: configurar `ALERT_WEBHOOK` en `Secrets` (p.ej. Slack/Discord/Webhook) para recibir notificaciones.

Monitor en tiempo real (Node.js)

Ficheros añadidos:

- `package.json` — dependencias (`ethers`, `nodemailer`, `dotenv`).
- `monitor.js` — monitor en tiempo real que escucha bloques y detecta transacciones hacia `watchedAddresses`.
- `config.example.json` — ejemplo de configuración.

Variables de entorno (ejemplo `.env`):

```
PROVIDER_URL=wss://eth-mainnet.alchemyapi.io/v2/KEY
WATCHED_ADDRS=0x111...,0x222...
EMAIL_FROM=monitor@example.com
EMAIL_TO=security@example.com
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user
SMTP_PASS=pass
```

Ejecutar localmente:

```bash
cd tools/monitor
npm install
PROVIDER_URL="wss://..." WATCHED_ADDRS="0x123,0x456" EMAIL_TO="you@example.com" SMTP_HOST=... SMTP_USER=... SMTP_PASS=... npm start
```

Notas:
- El monitor mantiene un set en memoria de transacciones procesadas; para persistencia en producción integre una base de datos.
- Si proporciona un ABI (`ABI_PATH`) el monitor intentará decodificar llamadas de función y argumentos para dar el "motivo" de la transacción.

