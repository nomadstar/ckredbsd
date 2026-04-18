IMMAC — Smart Contract MVP

Este directorio contiene un MVP del contrato inteligente IMMAC (registro + verificación básica + cálculo/claim).

Requisitos
- Node.js LTS (22.x recomendado por Hardhat)
- pnpm (o npm)

Instalación
```bash
cd IMMAC/contract
pnpm install
```

Tests
```bash
pnpm test
```

Uso rápido (deploy local con Hardhat)
```bash
pnpm hardhat run --network localhost scripts/deploy.js
```

Notas de diseño
- Las decisiones de verificación se delegan a cuentas `verifier` configuradas por el `owner`.
- `baseValue` se asigna por categoría (en wei) mediante `setBaseValue`.
- `approveContribution` envía multiplicadores escalados por 100 (p.ej. 125 = 1.25).
- En producción se recomienda usar multisig/DAO para `owner` y oráculos para verificación off-chain.

Seguridad y auditoría
- Este MVP es simplificado. Antes de producción realizar: auditoría externa, protecciones contra overflow, tests formales y un mecanismo de gobernanza real.
