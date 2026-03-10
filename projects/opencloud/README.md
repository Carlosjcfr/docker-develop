# OpenCloud Cheat Sheet

OpenCloud is a modular, decentralized self-hosted cloud platform.

## Management

- **Status/Start**: `./opencloud.sh start`
- **Updates**: `./opencloud.sh update`
- **Removal**: `./opencloud.sh uninstall`

## Access Details

- **Main Interface**: `https://<HOST_IP>:9200`
- **Admin User**: `admin`
- **Admin pass**: Found in `config.env` after installation.

## Important Information

- **Ports**: 9200 (Default Web/Proxy)
- **Data Path**: `./data/storage` (User files)
- **Config Path**: `./data/config` (System settings)
- **Logs**: `podman logs -f opencloud`

## Troubleshooting

- If the container is stuck, run: `podman restart opencloud`
- Identity Manager reset: `podman exec -it opencloud opencloud init`
